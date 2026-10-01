"""발화 하나를 처리하는 파이프라인.

여섯 단계다. 각 단계가 무엇을 막는지가 이 모듈의 설계다.

<pre>{@code
1 수신    전사 텍스트 · 명령 ID · 가구
2 멱등    같은 명령 ID 가 이미 처리됐으면 저장된 결과를 그대로 돌려준다
3 해석    LlmGateway 가 구조화된 제안을 만든다
4 검증    동작 · 단위 · 대상 · 날짜 · 잔량을 확인한다. 실패하면 확인 질문
5 실행    재고를 바꾸고 ChangeEvent 를 한 묶음으로 남긴다
6 응답    읽어줄 한 문장 · 화면 상세 · 되돌리기 토큰
}</pre>

IMPORTANT: 4단계를 통과하지 못하면 5단계에 가지 않는다. 모델의 출력은 제안이고 실행 권한이
없다는 것이 이 순서로 표현된다.
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

from loguru import logger
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import dates as date_utils
from app.core.enums import (
    ChangeAction,
    CommandIntent,
    CommandStatus,
    HistoryKind,
    QuantityCertainty,
)
from app.core.exceptions import UpstreamError
from app.core.llm.gateway import InventoryContext, LlmGateway
from app.core.llm.prompts import command_ko
from app.core.llm.schemas import CommandProposal
from app.core.locale import translate, unit_label
from app.core.particles import sanitize_fragment, with_means, with_topic
from app.domain.command import crud
from app.domain.command.models import Command
from app.domain.command.schemas import HistoryRow
from app.domain.command.validation import ValidatedItem, ValidationOutcome, validate
from app.domain.household import service as household_service
from app.domain.inventory import service as inventory_service
from app.domain.inventory.service import AppliedChange, ApplyOutcome

# 이 의도들은 수량이 반드시 있어야 실행할 수 있다.
_AMOUNT_REQUIRED = frozenset(
    {CommandIntent.REGISTER, CommandIntent.CONSUME, CommandIntent.ADJUST, CommandIntent.CORRECT}
)

# 수량이 아니라 상태만 바꾸는 의도. 차감하지 않는다.
_STATE_ONLY = frozenset({CommandIntent.OPEN, CommandIntent.MOVE})

# 모델에 넘기는 재고 항목 수. 전부 넘기면 토큰이 비용이고 모델이 엉뚱한 항목을 고른다.
_CONTEXT_ITEM_LIMIT = 25


@dataclass(slots=True)
class CommandResult:
    """처리 결과. API 스키마로 바로 옮길 수 있는 형태다."""

    command_id: UUID
    status: CommandStatus
    intent: CommandIntent
    spoken: str | None = None
    clarification_question: str | None = None
    screen: dict[str, object] | None = None
    undo_token: UUID | None = None


async def interpret(
    session: AsyncSession,
    gateway: LlmGateway,
    *,
    household_id: int,
    command_id: UUID,
    utterance: str,
    locale: str = "ko",
    follows: UUID | None = None,
) -> CommandResult:
    """발화 하나를 처리한다.

    Args:
        follows: 같은 대화에서 되물은 명령. 없으면 앞 발화와 잇지 않는다.
    """
    existing = await crud.get(session, command_id)
    if existing is not None:
        # 2단계. 네트워크 재시도가 재고를 두 번 바꾸지 않는다.
        logger.info("Replaying stored result for command {}", command_id)
        return _from_stored(existing)

    household = await household_service.get_household(session, household_id)
    today = date_utils.today_in(household.timezone)

    command = Command(
        command_id=command_id,
        household_id=household_id,
        utterance=utterance,
        status=CommandStatus.PENDING.value,
        prompt_version=command_ko.VERSION,
    )
    session.add(command)
    await session.flush()

    context = await _build_context(session, household_id, today.isoformat(), household.timezone)
    spoken = await _with_unanswered(session, command, follows)

    started = time.perf_counter()
    try:
        result = await gateway.interpret(spoken, context)
    except UpstreamError as error:
        # 실패를 완료처럼 알리지 않는다.
        command.status = CommandStatus.FAILED.value
        command.validation_error = error.detail
        await session.commit()
        logger.warning("Command {} failed upstream: {}", command_id, error.detail)
        return CommandResult(
            command_id=command_id,
            status=CommandStatus.FAILED,
            intent=CommandIntent.UNKNOWN,
            spoken=translate("error.upstream_failed", locale),
        )

    command.latency_ms = int((time.perf_counter() - started) * 1000)
    command.proposal = result.proposal.model_dump(mode="json")
    command.llm_model = result.usage.model
    intent = result.proposal.intent
    command.intent = intent.value

    if intent is CommandIntent.QUERY:
        # 조회는 재고를 바꾸지 않는다. 읽어서 답하기만 한다.
        answer = await _answer_query(
            session, household_id, result.proposal, today, locale
        )
        command.status = CommandStatus.APPLIED.value
        command.spoken_response = answer
        await session.commit()
        return CommandResult(
            command_id=command_id,
            status=CommandStatus.APPLIED,
            intent=intent,
            spoken=answer,
            # IMPORTANT: 조회에는 되돌릴 것이 없다. 되돌리기 토큰을 주지 않는다.
            undo_token=None,
        )

    if intent is CommandIntent.RECOMMEND:
        # 추천은 별도 엔드포인트가 담당한다. 여기서는 의도와 **지목한 재료**만 돌려준다.
        focus = _focus_of(command)
        command.status = CommandStatus.APPLIED.value
        command.spoken_response = (
            translate("intent.recommend_with", locale).format(
                names=with_means(", ".join(focus))
            )
            if focus
            else translate("intent.recommend", locale)
        )
        await session.commit()
        return _from_stored(command)

    if intent is CommandIntent.PLAN_FUTURE:
        # 미래 계획은 현재 재고에 반영하지 않는다. 의도만 기록해 이력에 남긴다.
        command.status = CommandStatus.APPLIED.value
        command.spoken_response = translate("intent.plan_future", locale)
        await session.commit()
        return _from_stored(command)

    if intent is CommandIntent.UNKNOWN:
        command.status = CommandStatus.REJECTED.value
        command.validation_error = "intent could not be determined"
        command.spoken_response = translate("error.command_rejected", locale)
        await session.commit()
        return _from_stored(command)

    if intent is CommandIntent.CANCEL:
        # IMPORTANT: 취소는 항목이 없다. 대상은 서버가 직전 반영 명령으로 고른다. 항목 검증에
        # 넣으면 실제 모델이 준 빈 항목 목록이 "항목 없음" 으로 거절돼 말로 취소할 수 없었다.
        applied = await _execute(
            session, command, ValidationOutcome(), intent, household_id, locale
        )
        await session.commit()
        return applied

    if intent is CommandIntent.REGISTER:
        redated = await _redate_stocked(
            session, command, result.proposal, spoken, today, household_id, locale
        )
        if redated is not None:
            await session.commit()
            return redated

    outcome = validate(
        result.proposal,
        today=today,
        require_amount=intent in _AMOUNT_REQUIRED and intent not in _STATE_ONLY,
        utterance=spoken,
    )
    if outcome.question is not None:
        # 4단계에서 멈춘다. 확인되지 않은 변경을 적용하지 않는다.
        command.status = CommandStatus.CLARIFYING.value
        command.clarification_question = outcome.question
        await session.commit()
        return _from_stored(command)
    if outcome.rejection is not None:
        command.status = CommandStatus.REJECTED.value
        command.validation_error = outcome.rejection
        command.spoken_response = translate("error.command_rejected", locale)
        await session.commit()
        logger.info("Command {} rejected: {}", command_id, outcome.rejection)
        return _from_stored(command)

    applied = await _execute(session, command, outcome, intent, household_id, locale)
    await session.commit()
    return applied


async def _redate_stocked(
    session: AsyncSession,
    command: Command,
    proposal: CommandProposal,
    spoken: str,
    today: date,
    household_id: int,
    locale: str,
) -> CommandResult | None:
    """있는 재료의 기한만 말했으면 그 묶음의 기한을 고친다.

    실제 모델은 "두부 유통기한은 10월 5일까지야" 를 수량 없는 등록으로 준다. 그대로 검증하면
    "두부는 얼마나인가요?" 를 되묻는데, 사용자는 넣은 것이 아니라 기한을 알려준 것이다.

    IMPORTANT: 모든 항목이 수량 없이 기한만 있고 **모두 살아 있는 묶음이 있을 때만** 여기서
    끝낸다. 하나라도 아니면 `None` 을 돌려 일반 등록 경로(수량 확인)로 넘긴다.

    Returns:
        기한을 고친 결과. 이 경로가 아니면 `None`.
    """
    outcome = validate(proposal, today=today, require_amount=False, utterance=spoken)
    if not outcome.ok or not outcome.items:
        return None
    if any(_has_amount(item) or not item.dates for item in outcome.items):
        return None
    applied = await inventory_service.redate_items(
        session,
        household_id=household_id,
        command_id=command.command_id,
        items=outcome.items,
    )
    if applied is None:
        return None
    logger.info("Command {} set dates on existing stock", command.command_id)
    return _finish(command, applied, locale, key="command.applied")


def _has_amount(item: ValidatedItem) -> bool:
    return item.amount is not None or item.qualitative_amount is not None


async def _execute(
    session: AsyncSession,
    command: Command,
    outcome: ValidationOutcome,
    intent: CommandIntent,
    household_id: int,
    locale: str,
) -> CommandResult:
    """5단계와 6단계. 의도별로 재고를 바꾸고 응답을 만든다."""
    target: Command | None = None
    if intent in {CommandIntent.CORRECT, CommandIntent.CANCEL}:
        target = await crud.latest_applied(session, household_id)
        if target is None or target.command_id == command.command_id:
            command.status = CommandStatus.CLARIFYING.value
            command.clarification_question = translate("command.nothing_to_undo", locale)
            return _from_stored(command)
        command.target_command_id = target.command_id

    if intent is CommandIntent.CANCEL:
        result = await inventory_service.revert_command(
            session, command_id=target.command_id, reverting_command_id=command.command_id
        )
        if result.ok:
            target.status = CommandStatus.REVERTED.value
        return _finish(command, result, locale, key="command.reverted")

    if intent is CommandIntent.CORRECT:
        # 정정은 새 사용이 아니라 교체다. 되돌린 뒤 다시 적용하므로 중복 차감이 없다.
        reverted = await inventory_service.revert_command(
            session, command_id=target.command_id, reverting_command_id=command.command_id
        )
        if not reverted.ok:
            return _finish(command, reverted, locale, key="command.applied")
        target.status = CommandStatus.SUPERSEDED.value
        replay_intent = CommandIntent(target.intent) if target.intent else CommandIntent.CONSUME
        applied = await _apply_by_intent(
            session, command, outcome, replay_intent, household_id
        )
        merged = ApplyOutcome(
            changes=[*reverted.changes, *applied.changes], question=applied.question
        )
        return _finish(command, merged, locale, key="command.corrected")

    applied = await _apply_by_intent(session, command, outcome, intent, household_id)
    return _finish(command, applied, locale, key="command.applied")


async def _apply_by_intent(
    session: AsyncSession,
    command: Command,
    outcome: ValidationOutcome,
    intent: CommandIntent,
    household_id: int,
) -> ApplyOutcome:
    if intent is CommandIntent.OPEN:
        return await inventory_service.open_items(
            session,
            household_id=household_id,
            command_id=command.command_id,
            items=outcome.items,
        )
    if intent is CommandIntent.MOVE:
        return await inventory_service.move_items(
            session,
            household_id=household_id,
            command_id=command.command_id,
            items=outcome.items,
        )
    if intent is CommandIntent.REGISTER:
        return await inventory_service.register_items(
            session,
            household_id=household_id,
            command_id=command.command_id,
            items=outcome.items,
        )
    return await inventory_service.apply_usage(
        session,
        household_id=household_id,
        command_id=command.command_id,
        items=outcome.items,
    )


def _finish(
    command: Command, outcome: ApplyOutcome, locale: str, *, key: str
) -> CommandResult:
    """실행 결과를 명령 행에 반영하고 응답을 만든다."""
    if not outcome.ok:
        command.status = CommandStatus.CLARIFYING.value
        command.clarification_question = outcome.question
        return _from_stored(command)

    command.status = CommandStatus.APPLIED.value
    command.spoken_response = _spoken(outcome.changes, locale, key=key)
    return CommandResult(
        command_id=command.command_id,
        status=CommandStatus.APPLIED,
        intent=CommandIntent(command.intent),
        spoken=command.spoken_response,
        screen={"changes": [_change_row(c) for c in outcome.changes]},
        undo_token=command.command_id,
    )


# 정정의 대상이 될 직전 발화를 모델에 넘기는 시간. 오래된 말을 고치는 것으로 읽지 않게 한다.
_PREVIOUS_WINDOW = timedelta(minutes=30)


def _utcnow() -> datetime:
    return datetime.now(UTC)


# 되물은 질문에 답이 이어질 수 있는 시간. 질문 낭독과 응답 창을 합친 것보다 넉넉히 둔다.
_FOLLOW_UP_WINDOW = timedelta(seconds=90)

# 새 명령임을 알리는 말. 이 말이 있으면 답이 아니라 새로 시작한 발화다.
_NEW_COMMAND_WORDS = (
    "넣었", "샀", "썼", "먹었", "남았", "버렸", "옮겼", "열었", "있어", "취소", "되돌", "뭐 먹",
)


async def _with_unanswered(
    session: AsyncSession, command: Command, follows: UUID | None
) -> str:
    """되물은 질문의 답이면 앞에서 한 말에 이어 붙인다.

    질문에는 "10개"·"10월이야" 처럼 짧게 답한다. 그 말만으로는 무엇에 대한 것인지 알 수
    없어 해석이 실패한다. 새 명령을 말했으면 잇지 않는다 — 답하지 않고 넘어간 앞 발화가
    뒤늦게 반영되면 안 된다.

    IMPORTANT: 앱이 같은 대화의 답이라고 [follows] 로 밝힌 경우에만 잇는다. 시간 창만으로
    이으면 대화를 닫고 호출어로 새로 시작한 발화에 지난 오인식이 붙어 해석이 계속 틀린다.
    """
    utterance = command.utterance
    if follows is None:
        return utterance
    if any(word in utterance for word in _NEW_COMMAND_WORDS):
        return utterance
    waiting = await crud.unanswered(
        session,
        command.household_id,
        within=_FOLLOW_UP_WINDOW,
        excluding=command.command_id,
    )
    if not waiting or waiting[-1].command_id != follows:
        return utterance
    logger.info(
        "Command {} continues {} unanswered utterance(s)", command.command_id, len(waiting)
    )
    return " ".join([*(earlier.utterance for earlier in waiting), utterance])


def _spoken(changes: list[AppliedChange], locale: str, *, key: str) -> str:
    """읽어줄 한 문장.

    결과를 숫자로 말한다 — '등록 완료' 가 아니라 '계란 8개 남았어요' 다. 잔량을 모르는
    항목은 숫자를 지어내지 않고 그대로 표현한다.
    """
    if not changes:
        return translate(key, locale)
    parts = []
    for change in changes:
        if change.action is ChangeAction.REVERT:
            continue
        parts.append(_describe(change, locale))
    if not parts:
        parts = [_describe(change, locale) for change in changes]
    spoken = f"{', '.join(parts)} {translate(key, locale)}"
    missing = _without_expiry(changes, locale)
    return f"{spoken} {missing}" if missing else spoken


def _describe(change: AppliedChange, locale: str) -> str:
    if change.quantity_after is None:
        amount = change.qualitative_amount or "확인 필요"
        described = f"{change.display_name} {amount}"
    else:
        unit = unit_label(change.unit, locale)
        described = f"{change.display_name} {_fmt(change.quantity_after)}{unit}"
    until = _until(change, locale)
    return f"{described}, {until}" if until else described


def _until(change: AppliedChange, locale: str) -> str:
    """함께 말한 기한. 말하지 않았으면 빈 문자열.

    음성에서는 연도까지 읽는다 — 해가 바뀌는 때에 "1월 3일"만 읽으면 어느 해인지 모른다.
    """
    if change.date_kind is None or change.date_value is None:
        return ""
    when = translate("date.spoken", locale).format(
        year=change.date_value.year, month=change.date_value.month, day=change.date_value.day
    )
    return translate(f"date.until.{change.date_kind}", locale).format(date=when)


def _without_expiry(changes: list[AppliedChange], locale: str) -> str:
    """기한 없이 넣은 재료를 알린다. 넣은 것이 없거나 모두 기한이 있으면 빈 문자열.

    말하지 않은 기한을 채우지 않으므로, 입력되지 않았다는 사실을 그대로 알린다. 넣은 재료가
    모두 기한이 없으면 이름을 되풀이하지 않는다.
    """
    stocked = [c for c in changes if c.action is ChangeAction.STOCK_IN]
    missing = [c.display_name for c in stocked if c.date_value is None]
    if not missing:
        return ""
    if len(missing) == len(stocked):
        return translate("command.no_expiry", locale)
    names = with_topic(", ".join(missing))
    return translate("command.no_expiry_for", locale).format(names=names)


def _change_row(change: AppliedChange) -> dict[str, object]:
    return {
        "batch_id": change.batch_id,
        "name": change.display_name,
        "action": change.action.value,
        "before": _fmt(change.quantity_before) if change.quantity_before is not None else None,
        "after": _fmt(change.quantity_after) if change.quantity_after is not None else None,
        "unit": change.unit,
        "date_kind": change.date_kind,
        "date_value": change.date_value.isoformat() if change.date_value else None,
    }


def _from_stored(command: Command) -> CommandResult:
    """저장된 명령 행을 결과로 옮긴다. 멱등 재생과 같은 경로를 쓴다."""
    status = CommandStatus(command.status)
    intent = CommandIntent(command.intent)
    return CommandResult(
        command_id=command.command_id,
        status=status,
        intent=intent,
        spoken=command.spoken_response,
        clarification_question=command.clarification_question,
        screen={"focus": _focus_of(command)} if intent is CommandIntent.RECOMMEND else None,
        undo_token=command.command_id if status is CommandStatus.APPLIED else None,
    )


def _focus_of(command: Command) -> list[str]:
    """메뉴를 물으며 지목한 재료. "삼겹살로 뭐 해 먹지"의 삼겹살이다.

    추천은 냉장고 전체를 보고 만든다. 지목한 재료를 넘기지 않으면 물은 것과 다른 답이 온다.
    """
    items = (command.proposal or {}).get("items") or []
    names = [sanitize_fragment(item.get("raw_name"), limit=20) for item in items]
    return [name for name in names if name]


async def _answer_query(
    session: AsyncSession,
    household_id: int,
    proposal: CommandProposal,
    today: date,
    locale: str,
) -> str:
    """조회 의도에 답한다.

    재료를 지목했으면 그 잔량을, 지목하지 않았으면 먼저 쓸 재료를 답한다. **잔량을 모르는
    항목은 숫자를 지어내지 않고** 모른다고 말한다.
    """
    names = [item.raw_name.strip() for item in proposal.items if item.raw_name.strip()]
    if names:
        batches = await inventory_service.find_by_names(session, household_id, names)
        if not batches:
            joined = ", ".join(names)
            return f"{joined}은 등록된 재고에 없어요."
        return ", ".join(_describe_stock(batch, locale) for batch in batches) + " 있어요."

    priority = await inventory_service.list_priority_batches(
        session, household_id, today=today, alert_days=[3, 1, 0]
    )
    if not priority:
        total = await inventory_service.list_batches(session, household_id, 5)
        if not total:
            return "등록된 재료가 없어요."
        return ", ".join(_describe_stock(b, locale) for b in total) + " 있어요."
    first = priority[:3]
    stocks = ", ".join(_describe_stock(p.batch, locale) for p in first)
    return f"먼저 쓸 재료는 {stocks}예요."


def _describe_stock(batch: object, locale: str) -> str:
    """잔량을 사람이 읽는 형태로. 모르면 모른다고 한다."""
    quantity = getattr(batch, "quantity", None)
    unit = unit_label(getattr(batch, "unit", None), locale)
    name = getattr(batch, "raw_name", "")
    if quantity is None:
        qualitative = getattr(batch, "qualitative_amount", None)
        return f"{name} {qualitative}" if qualitative else f"{name} 잔량 미확인"
    return f"{name} {_fmt(quantity)}{unit}"


async def _build_context(
    session: AsyncSession, household_id: int, today: str, timezone: str
) -> InventoryContext:
    """모델에 넘길 짧은 재고 문맥. `batch_id` 는 넘기지 않는다 — 대상 선택은 서버가 한다."""
    batches = await inventory_service.list_batches(session, household_id, _CONTEXT_ITEM_LIMIT)
    items = []
    for batch in batches:
        amount = (
            f"{_fmt(batch.quantity)}{batch.unit or ''}"
            if batch.quantity is not None
            else (batch.qualitative_amount or "잔량 미확인")
        )
        soonest = min(
            (d.date_value for d in batch.dates if d.date_value is not None), default=None
        )
        suffix = f" (기한 {soonest.isoformat()})" if soonest else ""
        items.append(f"{batch.raw_name} {amount}{suffix}")
    # IMPORTANT: "두 개가 아니라 세 개"처럼 재료를 빼고 고치는 말은 직전 발화 없이는 대상을
    # 알 수 없다. 넘기지 않았더니 모델이 이름 없는 항목을 내 스키마 검증에서 실패했다.
    previous = await crud.latest_applied(session, household_id)
    recent = previous is not None and previous.created_at >= _utcnow() - _PREVIOUS_WINDOW
    return InventoryContext(
        items=items,
        today=today,
        timezone=timezone,
        previous_utterance=previous.utterance if recent else None,
    )


def _fmt(value: object) -> str:
    from decimal import Decimal

    if not isinstance(value, Decimal):
        return str(value)
    normalized = value.normalize()
    if normalized == normalized.to_integral_value():
        return str(int(normalized))
    return str(normalized)


# 되돌리기 버튼이 만든 명령의 발화 칸. 말이 아니라 표시다 — 기록 화면에는 [_said] 가
# 언어 팩 문구로 바꿔 보여준다. 이미 쌓인 행이 이 값을 갖고 있으므로 바꾸지 않는다.
_UNDO_UTTERANCE = "undo"


def _said(command: Command) -> str:
    """기록 화면에 보일 발화. 되돌리기 버튼이 만든 명령은 언어 팩 문구로 바꾼다.

    사용자는 "undo" 라고 말한 적이 없다. 그대로 보이면 하지 않은 말이 말풍선에 뜬다.
    """
    if command.utterance == _UNDO_UTTERANCE:
        return translate("history.undo")
    return command.utterance


async def undo(
    session: AsyncSession,
    *,
    household_id: int,
    command_id: UUID,
    target_command_id: UUID,
    locale: str = "ko",
) -> CommandResult:
    """명령 묶음 전체를 되돌린다. 되돌리기 자체도 하나의 명령으로 기록된다."""
    existing = await crud.get(session, command_id)
    if existing is not None:
        return _from_stored(existing)

    target = await crud.get(session, target_command_id)
    if target is None or target.household_id != household_id:
        command = Command(
            command_id=command_id,
            household_id=household_id,
            utterance=_UNDO_UTTERANCE,
            intent=CommandIntent.CANCEL.value,
            status=CommandStatus.REJECTED.value,
            validation_error=f"unknown target command {target_command_id}",
            spoken_response=translate("command.nothing_to_undo", locale),
        )
        session.add(command)
        await session.commit()
        return _from_stored(command)

    command = Command(
        command_id=command_id,
        household_id=household_id,
        utterance=_UNDO_UTTERANCE,
        intent=CommandIntent.CANCEL.value,
        status=CommandStatus.PENDING.value,
        target_command_id=target_command_id,
    )
    session.add(command)
    await session.flush()

    result = await inventory_service.revert_command(
        session, command_id=target_command_id, reverting_command_id=command_id
    )
    if result.ok:
        target.status = CommandStatus.REVERTED.value
    outcome = _finish(command, result, locale, key="command.reverted")
    await session.commit()
    return outcome


async def history(
    session: AsyncSession,
    *,
    household_id: int,
    limit: int = 50,
    on: date | None = None,
    timezone: str = "Asia/Seoul",
) -> list[HistoryRow]:
    """변경 이력을 최근 순으로 돌려준다.

    수량 변경과 상태 변경을 한 타임라인에 섞고, 명시값과 추정값을 구분해 표시한다.

    Args:
        on: 이 날 하루치만. 없으면 최근 것부터 `limit` 개다.
        timezone: 하루를 자르는 기준. 가구의 시간대다 — UTC 로 자르면 밤 늦게 한 일이
            다음 날로 넘어간다.
    """
    window = _day_window(on, timezone) if on is not None else None
    rows = await crud.list_history(session, household_id, limit, window=window)
    out: list[HistoryRow] = []
    for kind, event in rows:
        if kind is HistoryKind.QUANTITY:
            out.append(
                HistoryRow(
                    kind=kind.value,
                    action=event.action,
                    name=event.batch.raw_name,
                    batch_id=event.batch_id,
                    quantity_before=_fmt(event.quantity_before)
                    if event.quantity_before is not None
                    else None,
                    quantity_after=_fmt(event.quantity_after)
                    if event.quantity_after is not None
                    else None,
                    unit=event.unit,
                    is_estimated=event.certainty
                    in {QuantityCertainty.ESTIMATED.value, QuantityCertainty.QUALITATIVE.value},
                    occurred_at=event.created_at,
                    command_id=event.command_id,
                    reverses_event_id=event.reverses_event_id,
                    utterance=_said(event.command),
                    spoken_response=event.command.spoken_response,
                )
            )
            continue
        out.append(
            HistoryRow(
                kind=kind.value,
                action=event.kind,
                name=event.batch.raw_name,
                batch_id=event.batch_id,
                # 상태 변경은 수량을 바꾸지 않는다. 잔량 칸을 비워 그 사실을 드러낸다.
                occurred_at=event.occurred_at,
                command_id=event.command_id,
            )
        )
    return out


async def history_days(
    session: AsyncSession, *, household_id: int, timezone: str, limit: int = 60
) -> list[date]:
    """기록이 있는 날짜. 달력이 고를 수 있는 날을 정한다."""
    return await crud.list_history_days(
        session, household_id, timezone=timezone, limit=limit
    )


def _day_window(on: date, timezone: str) -> tuple[datetime, datetime]:
    """그 날 하루를 `[시작, 끝)` 시각 범위로.

    저장된 시각은 UTC 이므로 가구의 시간대로 만든 자정을 UTC 로 옮겨 비교한다.
    """
    # WARNING: 이 모듈의 `time` 은 표준 라이브러리 모듈(지연 측정용)이다.
    # `datetime.time` 이 아니므로 자정을 직접 만든다.
    start = datetime(on.year, on.month, on.day, tzinfo=ZoneInfo(timezone))
    return start.astimezone(UTC), (start + timedelta(days=1)).astimezone(UTC)
