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
from datetime import date
from uuid import UUID

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
from app.core.locale import translate
from app.domain.command import crud
from app.domain.command.models import Command
from app.domain.command.schemas import HistoryRow
from app.domain.command.validation import ValidationOutcome, validate
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
) -> CommandResult:
    """발화 하나를 처리한다."""
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

    started = time.perf_counter()
    try:
        result = await gateway.interpret(utterance, context)
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
        answer = await _answer_query(session, household_id, result.proposal, today)
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
        # 추천은 별도 엔드포인트가 담당한다. 여기서는 의도만 기록한다.
        command.status = CommandStatus.APPLIED.value
        command.spoken_response = translate("intent.recommend", locale)
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

    outcome = validate(
        result.proposal,
        today=today,
        require_amount=intent in _AMOUNT_REQUIRED and intent not in _STATE_ONLY,
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
        parts.append(_describe(change))
    if not parts:
        parts = [_describe(change) for change in changes]
    return f"{', '.join(parts)} {translate(key, locale)}"


def _describe(change: AppliedChange) -> str:
    if change.quantity_after is None:
        amount = change.qualitative_amount or "확인 필요"
        return f"{change.display_name} {amount}"
    return f"{change.display_name} {_fmt(change.quantity_after)}{change.unit or ''}"


def _change_row(change: AppliedChange) -> dict[str, object]:
    return {
        "batch_id": change.batch_id,
        "name": change.display_name,
        "action": change.action.value,
        "before": _fmt(change.quantity_before) if change.quantity_before is not None else None,
        "after": _fmt(change.quantity_after) if change.quantity_after is not None else None,
        "unit": change.unit,
    }


def _from_stored(command: Command) -> CommandResult:
    """저장된 명령 행을 결과로 옮긴다. 멱등 재생과 같은 경로를 쓴다."""
    status = CommandStatus(command.status)
    return CommandResult(
        command_id=command.command_id,
        status=status,
        intent=CommandIntent(command.intent),
        spoken=command.spoken_response,
        clarification_question=command.clarification_question,
        screen=None,
        undo_token=command.command_id if status is CommandStatus.APPLIED else None,
    )


async def _answer_query(
    session: AsyncSession,
    household_id: int,
    proposal: CommandProposal,
    today: date,
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
        return ", ".join(_describe_stock(batch) for batch in batches) + " 있어요."

    priority = await inventory_service.list_priority_batches(
        session, household_id, today=today, alert_days=[3, 1, 0]
    )
    if not priority:
        total = await inventory_service.list_batches(session, household_id, 5)
        if not total:
            return "등록된 재료가 없어요."
        return ", ".join(_describe_stock(b) for b in total) + " 있어요."
    first = priority[:3]
    return "먼저 쓸 재료는 " + ", ".join(_describe_stock(p.batch) for p in first) + "예요."


def _describe_stock(batch: object) -> str:
    """잔량을 사람이 읽는 형태로. 모르면 모른다고 한다."""
    quantity = getattr(batch, "quantity", None)
    unit = getattr(batch, "unit", None) or ""
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
    return InventoryContext(items=items, today=today, timezone=timezone)


def _fmt(value: object) -> str:
    from decimal import Decimal

    if not isinstance(value, Decimal):
        return str(value)
    normalized = value.normalize()
    if normalized == normalized.to_integral_value():
        return str(int(normalized))
    return str(normalized)


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
            utterance="undo",
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
        utterance="undo",
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
    session: AsyncSession, *, household_id: int, limit: int = 50
) -> list[HistoryRow]:
    """변경 이력을 최근 순으로 돌려준다.

    수량 변경과 상태 변경을 한 타임라인에 섞고, 명시값과 추정값을 구분해 표시한다.
    """
    rows = await crud.list_history(session, household_id, limit)
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
                    utterance=event.command.utterance,
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
