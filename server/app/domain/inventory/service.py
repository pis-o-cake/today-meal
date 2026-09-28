"""재고 도메인 서비스.

등록·차감·보정·되돌리기가 모두 여기 있다. 되물을 일이 하나라도 있으면 **아무 항목도
반영하지 않는다** — 절반만 반영하면 사용자가 무엇이 남았는지 알 수 없다.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, time
from decimal import Decimal
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.core import units as unit_utils
from app.core.enums import (
    ChangeAction,
    DateKind,
    FreshnessGrade,
    FridgeCondition,
    PriorityReason,
    QuantityCertainty,
    StateEventKind,
    StorageLocation,
)
from app.core.particles import with_object, with_subject, with_topic
from app.domain.command.models import ChangeEvent
from app.domain.command.validation import ValidatedItem
from app.domain.ingredient import service as ingredient_service
from app.domain.inventory import crud
from app.domain.inventory.models import BatchDate, BatchStateEvent, IngredientBatch


async def list_batches(
    session: AsyncSession, household_id: int, limit: int = 200
) -> list[IngredientBatch]:
    """가구의 현재 재고를 돌려준다."""
    return await crud.list_active(session, household_id, limit)


@dataclass(slots=True)
class AppliedChange:
    """한 항목에 일어난 변화. 응답 문구와 화면 상세를 만드는 재료다."""

    batch_id: int
    display_name: str
    action: ChangeAction
    quantity_before: Decimal | None
    quantity_after: Decimal | None
    unit: str | None
    qualitative_amount: str | None = None


@dataclass(slots=True)
class ApplyOutcome:
    """실행 결과.

    Attributes:
        changes: 일어난 변화. 비어 있으면 아무것도 바꾸지 않았다는 뜻이다.
        question: 되물을 한 가지. 있으면 **아무것도 바꾸지 않았다.**
    """

    changes: list[AppliedChange] = field(default_factory=list)
    question: str | None = None

    @property
    def ok(self) -> bool:
        return self.question is None


async def register_items(
    session: AsyncSession,
    *,
    household_id: int,
    command_id: UUID,
    items: Sequence[ValidatedItem],
) -> ApplyOutcome:
    """재료를 새 묶음으로 넣는다.

    같은 재료를 다시 넣어도 기존 묶음에 합치지 않는다. 기한과 개봉 상태가 다른 팩은 별도로
    관리해야 하고, 합치면 그 구분이 사라진다.
    """
    changes: list[AppliedChange] = []
    for item in items:
        ingredient = await ingredient_service.resolve_or_create(session, item.raw_name)
        batch = IngredientBatch(
            household_id=household_id,
            ingredient_id=ingredient.ingredient_id,
            raw_name=item.raw_name,
            quantity=item.amount,
            unit=item.unit,
            qualitative_amount=item.qualitative_amount,
            quantity_certainty=item.certainty.value,
            storage_location=item.storage.value,
            last_confirmed_at=_now(),
        )
        session.add(batch)
        await session.flush()

        for validated in item.dates:
            session.add(
                BatchDate(
                    batch_id=batch.batch_id,
                    kind=validated.kind.value,
                    date_value=validated.value,
                    is_confirmed=validated.is_confirmed,
                    source=validated.source.value,
                    raw_text=validated.raw_text,
                )
            )
        session.add(
            BatchStateEvent(
                batch_id=batch.batch_id,
                command_id=command_id,
                kind=StateEventKind.STOCKED_IN.value,
                occurred_at=_now(),
            )
        )
        session.add(
            ChangeEvent(
                command_id=command_id,
                batch_id=batch.batch_id,
                action=ChangeAction.STOCK_IN.value,
                quantity_delta=item.amount,
                quantity_before=Decimal("0") if item.amount is not None else None,
                quantity_after=item.amount,
                unit=item.unit,
                certainty=item.certainty.value,
            )
        )
        changes.append(
            AppliedChange(
                batch_id=batch.batch_id,
                display_name=item.raw_name,
                action=ChangeAction.STOCK_IN,
                quantity_before=Decimal("0") if item.amount is not None else None,
                quantity_after=item.amount,
                unit=item.unit,
                qualitative_amount=item.qualitative_amount,
            )
        )
    await session.flush()
    return ApplyOutcome(changes=changes)


async def apply_usage(
    session: AsyncSession,
    *,
    household_id: int,
    command_id: UUID,
    items: Sequence[ValidatedItem],
) -> ApplyOutcome:
    """사용 차감과 잔량 보정을 반영한다.

    항목의 `is_remaining` 이 차감과 보정을 가른다 — "두 개 썼어"는 `consume`, "두 개 남았어"는
    `adjust` 다. 결과 잔량이 같아도 다른 사실이므로 이력에서 구분된다.

    IMPORTANT: 되물을 일이 하나라도 있으면 **아무 항목도 반영하지 않는다.** 절반만 반영하면
    사용자가 무엇이 남았는지 알 수 없다.
    """
    plans: list[tuple[ValidatedItem, IngredientBatch]] = []
    for item in items:
        ingredient = await ingredient_service.resolve_or_create(session, item.raw_name)
        candidates = await crud.find_target_batches(
            session, household_id, ingredient.ingredient_id
        )
        usable = [b for b in candidates if b.quantity is None or b.quantity > 0]
        if not usable:
            return ApplyOutcome(
                question=f"{with_topic(item.raw_name)} 등록된 재고에 없어요."
            )
        if len(usable) > 1 and not item.is_remaining:
            # 어느 팩인지 모른다. 기한이 다른 팩을 임의로 고르면 잘못된 것을 먼저 쓴다.
            return ApplyOutcome(
                question=f"{with_subject(item.raw_name)} 여러 개 있어요. 어느 것을 쓰셨어요?"
            )
        plans.append((item, usable[0]))

    changes: list[AppliedChange] = []
    for item, batch in plans:
        outcome = _apply_to_batch(session, command_id, item, batch)
        if not outcome.ok:
            return outcome
        changes.extend(outcome.changes)
    await session.flush()
    return ApplyOutcome(changes=changes)


def _apply_to_batch(
    session: AsyncSession, command_id: UUID, item: ValidatedItem, batch: IngredientBatch
) -> ApplyOutcome:
    """한 묶음에 한 항목을 반영한다."""
    before = batch.quantity

    if item.amount is None:
        # 정성 사용이다. 숫자를 만들지 않고 잔량을 추정으로 낮춘다.
        batch.quantity_certainty = QuantityCertainty.QUALITATIVE.value
        batch.qualitative_amount = item.qualitative_amount or batch.qualitative_amount
        batch.last_confirmed_at = _now()
        session.add(
            ChangeEvent(
                command_id=command_id,
                batch_id=batch.batch_id,
                action=ChangeAction.CONSUME.value,
                quantity_before=before,
                quantity_after=batch.quantity,
                unit=batch.unit,
                certainty=QuantityCertainty.QUALITATIVE.value,
                note=item.qualitative_amount,
            )
        )
        return ApplyOutcome(
            changes=[
                AppliedChange(
                    batch_id=batch.batch_id,
                    display_name=item.raw_name,
                    action=ChangeAction.CONSUME,
                    quantity_before=before,
                    quantity_after=batch.quantity,
                    unit=batch.unit,
                    qualitative_amount=item.qualitative_amount,
                )
            ]
        )

    amount = _convert_to_batch_unit(item, batch)
    if amount is None:
        return ApplyOutcome(
            question=f"{item.raw_name}의 양을 {batch.unit or '단위'} 기준으로 알려주세요."
        )

    if item.is_remaining:
        after = amount
        action = ChangeAction.ADJUST
    else:
        if before is None:
            return ApplyOutcome(
                question=f"{with_subject(item.raw_name)} 지금 얼마나 남았는지 알려주세요."
            )
        if amount > before:
            # 음수 재고를 저장하지 않는다. 기록이 틀어진 것이므로 현재 잔량을 확인한다.
            return ApplyOutcome(
                question=(
                    f"{with_subject(item.raw_name)} {_fmt(before)}{batch.unit or ''}"
                    "밖에 없어요. 지금 얼마나 남았어요?"
                )
            )
        after = before - amount
        action = ChangeAction.CONSUME

    batch.quantity = after
    batch.unit = batch.unit or item.unit
    batch.quantity_certainty = item.certainty.value
    batch.last_confirmed_at = _now()
    batch.depleted_at = _now() if after == 0 else None

    session.add(
        ChangeEvent(
            command_id=command_id,
            batch_id=batch.batch_id,
            action=action.value,
            quantity_delta=after - (before or Decimal("0")),
            quantity_before=before,
            quantity_after=after,
            unit=batch.unit,
            certainty=item.certainty.value,
        )
    )
    return ApplyOutcome(
        changes=[
            AppliedChange(
                batch_id=batch.batch_id,
                display_name=item.raw_name,
                action=action,
                quantity_before=before,
                quantity_after=after,
                unit=batch.unit,
            )
        ]
    )


def _convert_to_batch_unit(item: ValidatedItem, batch: IngredientBatch) -> Decimal | None:
    """발화의 단위를 묶음의 단위로 맞춘다. 근거가 없으면 `None`."""
    if item.unit is None or batch.unit is None or item.unit == batch.unit:
        return item.amount
    result = unit_utils.convert(unit_utils.Quantity(item.amount, item.unit), batch.unit)
    if result.needs_confirm or result.quantity is None:
        return None
    return result.quantity.amount


async def open_items(
    session: AsyncSession,
    *,
    household_id: int,
    command_id: UUID,
    items: Sequence[ValidatedItem],
    occurred_on: date | None = None,
) -> ApplyOutcome:
    """개봉을 기록한다. **수량을 바꾸지 않는다.**

    개봉은 먹은 것이 아니므로 차감이 아니다. `batch_state_event` 에만 남기며, 개봉 후 보관
    지침은 제품 표시를 우선하므로 기한을 자동으로 줄이지도 늘리지도 않는다.
    """
    return await _record_state(
        session,
        household_id=household_id,
        command_id=command_id,
        items=items,
        kind=StateEventKind.OPENED,
        occurred_on=occurred_on,
    )


async def move_items(
    session: AsyncSession,
    *,
    household_id: int,
    command_id: UUID,
    items: Sequence[ValidatedItem],
) -> ApplyOutcome:
    """보관 위치를 옮긴다.

    WARNING: 전체 이동만 처리한다. "반은 냉동실로"처럼 일부만 옮기는 발화는 묶음 분할이
    필요하고 그것은 이 슬라이스 범위가 아니다 — 되묻는다.

    **냉동 전환을 이유로 원래 기한을 연장하지 않는다.**
    """
    changes: list[AppliedChange] = []
    for item in items:
        if item.storage is StorageLocation.UNKNOWN:
            return ApplyOutcome(
                question=f"{with_object(item.raw_name)} 어디로 옮기셨어요?"
            )
        if item.amount is not None or item.qualitative_amount is not None:
            return ApplyOutcome(
                question=f"{with_object(item.raw_name)} 전부 옮기셨어요?"
            )

        ingredient = await ingredient_service.resolve_or_create(session, item.raw_name)
        candidates = await crud.find_target_batches(
            session, household_id, ingredient.ingredient_id
        )
        if not candidates:
            return ApplyOutcome(
                question=f"{with_topic(item.raw_name)} 등록된 재고에 없어요."
            )
        if len(candidates) > 1:
            return ApplyOutcome(
                question=f"{with_subject(item.raw_name)} 여러 개예요. 어느 것을 옮기셨어요?"
            )

        batch = candidates[0]
        previous = batch.storage_location
        batch.storage_location = item.storage.value
        batch.last_confirmed_at = _now()
        session.add(
            BatchStateEvent(
                batch_id=batch.batch_id,
                command_id=command_id,
                kind=StateEventKind.MOVED.value,
                occurred_at=_now(),
                from_location=previous,
                to_location=item.storage.value,
            )
        )
        changes.append(
            AppliedChange(
                batch_id=batch.batch_id,
                display_name=item.raw_name,
                action=ChangeAction.MOVE,
                quantity_before=batch.quantity,
                quantity_after=batch.quantity,
                unit=batch.unit,
            )
        )
    await session.flush()
    return ApplyOutcome(changes=changes)


async def _record_state(
    session: AsyncSession,
    *,
    household_id: int,
    command_id: UUID,
    items: Sequence[ValidatedItem],
    kind: StateEventKind,
    occurred_on: date | None,
) -> ApplyOutcome:
    """수량을 바꾸지 않는 상태 이벤트를 남긴다."""
    changes: list[AppliedChange] = []
    for item in items:
        ingredient = await ingredient_service.resolve_or_create(session, item.raw_name)
        candidates = await crud.find_target_batches(
            session, household_id, ingredient.ingredient_id
        )
        if not candidates:
            return ApplyOutcome(
                question=f"{with_topic(item.raw_name)} 등록된 재고에 없어요."
            )
        if len(candidates) > 1:
            return ApplyOutcome(
                question=f"{with_subject(item.raw_name)} 여러 개예요. 어느 것인가요?"
            )

        batch = candidates[0]
        moment = (
            datetime.combine(occurred_on, time.min, tzinfo=UTC) if occurred_on else _now()
        )
        session.add(
            BatchStateEvent(
                batch_id=batch.batch_id,
                command_id=command_id,
                kind=kind.value,
                occurred_at=moment,
            )
        )
        batch.last_confirmed_at = _now()
        changes.append(
            AppliedChange(
                batch_id=batch.batch_id,
                display_name=item.raw_name,
                action=ChangeAction.MOVE if kind is StateEventKind.MOVED else ChangeAction.SPLIT,
                quantity_before=batch.quantity,
                quantity_after=batch.quantity,
                unit=batch.unit,
            )
        )
    await session.flush()
    return ApplyOutcome(changes=changes)


async def revert_command(
    session: AsyncSession, *, command_id: UUID, reverting_command_id: UUID
) -> ApplyOutcome:
    """한 명령의 변경을 되돌린다.

    행을 고치지 않고 **역산 이벤트를 추가한다.** 되돌린 뒤 다시 되돌릴 수 있고, 이력에
    무엇이 일어났는지가 남는다. 역산 순서는 적용의 역순이다.
    """
    events = await crud.list_events_of_command(session, command_id)
    if not events:
        return ApplyOutcome(question="되돌릴 변경이 없어요.")

    changes: list[AppliedChange] = []
    for event in reversed(events):
        batch = await crud.get_batch(session, event.batch_id)
        if batch is None:
            continue
        before = batch.quantity
        after = event.quantity_before
        batch.quantity = after
        batch.depleted_at = _now() if after == 0 else None
        batch.last_confirmed_at = _now()

        delta = None
        if after is not None and before is not None:
            delta = after - before
        session.add(
            ChangeEvent(
                command_id=reverting_command_id,
                batch_id=batch.batch_id,
                action=ChangeAction.REVERT.value,
                quantity_delta=delta,
                quantity_before=before,
                quantity_after=after,
                unit=batch.unit,
                certainty=event.certainty,
                reverses_event_id=event.change_event_id,
            )
        )
        changes.append(
            AppliedChange(
                batch_id=batch.batch_id,
                display_name=batch.raw_name,
                action=ChangeAction.REVERT,
                quantity_before=before,
                quantity_after=after,
                unit=batch.unit,
            )
        )

        # 등록을 되돌리면 묶음 자체를 숨긴다. 하드 삭제하지 않아 다시 살릴 수 있다.
        if event.action == ChangeAction.STOCK_IN.value:
            batch.deleted_at = _now()

    await session.flush()
    return ApplyOutcome(changes=changes)


def _now() -> datetime:
    return datetime.now(UTC)


def _fmt(value: Decimal | None) -> str:
    """수량을 사람이 읽는 형태로. 정수면 소수점을 떼고, 소수면 유지한다."""
    if value is None:
        return "?"
    normalized = value.normalize()
    if normalized == normalized.to_integral_value():
        return str(int(normalized))
    return str(normalized)


@dataclass(slots=True)
class PriorityBatch:
    """먼저 확인할 묶음 하나.

    Attributes:
        reason: 먼저 확인하는 이유.
        days_left: 표시기한까지 남은 날. 지났으면 음수. 기한이 없으면 `None`.
        is_cookable: '오늘 요리할 재료' 후보로 쓸 수 있는지. 기한이 지난 항목은 제외한다.
    """

    batch: IngredientBatch
    reason: PriorityReason
    days_left: int | None
    is_cookable: bool

    @property
    def sort_key(self) -> tuple[int, int]:
        order = _REASON_ORDER[self.reason]
        return (order, self.days_left if self.days_left is not None else 999)


# 사유의 우선순위. 지난 것을 먼저 보여주되 요리 후보에서는 뺀다.
_REASON_ORDER: dict[PriorityReason, int] = {
    PriorityReason.EXPIRED: 0,
    PriorityReason.EXPIRING: 1,
    PriorityReason.OPENED: 2,
    PriorityReason.QUANTITY_UNKNOWN: 3,
}

# 개봉 후 이 일수가 지나면 확인 대상으로 올린다. 제품 표시를 대체하는 값이 아니라
# 사용자가 한 번 보게 하는 화면 기준이다.
OPENED_REVIEW_DAYS = 3

# 표시기한으로 쓰는 날짜 종류. 제조일·포장일은 기한이 아니므로 판정에 쓰지 않는다.
_EXPIRY_KINDS = (DateKind.USE_BY, DateKind.SELL_BY, DateKind.BEST_BEFORE)


def soonest_expiry(batch: IngredientBatch) -> tuple[DateKind, date] | None:
    """가장 이른 표시기한과 그 종류.

    IMPORTANT: 제조일을 기한으로 쓰지 않는다. 종류를 보존한 채 돌려주어 화면이 무엇인지
    밝힐 수 있게 한다.
    """
    candidates = [
        (DateKind(row.kind), row.date_value)
        for row in batch.dates
        if row.date_value is not None and row.kind in {k.value for k in _EXPIRY_KINDS}
    ]
    if not candidates:
        return None
    return min(candidates, key=lambda pair: pair[1])


def _opened_on(batch: IngredientBatch) -> date | None:
    moments = [
        event.occurred_at.date()
        for event in batch.state_events
        if event.kind == StateEventKind.OPENED.value
    ]
    return max(moments) if moments else None


def classify_priority(
    batch: IngredientBatch, *, today: date, alert_days: Sequence[int]
) -> PriorityBatch | None:
    """묶음이 먼저 확인할 대상인지 판정한다.

    Args:
        batch: 판정할 묶음.
        today: 가구 시간대의 오늘.
        alert_days: 기한 알림 시점(D-n). 가구 설정에서 온다.

    Returns:
        해당하면 판정 결과, 아니면 `None`.
    """
    expiry = soonest_expiry(batch)
    if expiry is not None:
        days_left = (expiry[1] - today).days
        if days_left < 0:
            # 기한이 지났다. 안전을 단정하지 않고 확인 대상으로만 올린다.
            return PriorityBatch(batch, PriorityReason.EXPIRED, days_left, is_cookable=False)
        if alert_days and days_left <= max(alert_days):
            return PriorityBatch(batch, PriorityReason.EXPIRING, days_left, is_cookable=True)

    opened = _opened_on(batch)
    if opened is not None and (today - opened).days >= OPENED_REVIEW_DAYS:
        return PriorityBatch(batch, PriorityReason.OPENED, None, is_cookable=True)

    if batch.quantity is None or batch.quantity_certainty in {
        QuantityCertainty.UNKNOWN.value,
        QuantityCertainty.ESTIMATED.value,
    }:
        return PriorityBatch(
            batch, PriorityReason.QUANTITY_UNKNOWN, None, is_cookable=True
        )
    return None


async def list_priority_batches(
    session: AsyncSession, household_id: int, *, today: date, alert_days: Sequence[int]
) -> list[PriorityBatch]:
    """먼저 확인할 재료를 우선순위대로 돌려준다."""
    batches = await crud.list_with_dates(session, household_id)
    found = [
        classified
        for batch in batches
        if (classified := classify_priority(batch, today=today, alert_days=alert_days))
        is not None
    ]
    return sorted(found, key=lambda item: item.sort_key)


async def cookable_batches(
    session: AsyncSession, household_id: int, *, today: date
) -> list[IngredientBatch]:
    """오늘 요리에 쓸 수 있는 묶음.

    기한이 지난 것과 잔량이 0 인 것을 뺀다. **기한이 지난 재료를 추천 재료로 쓰지 않는다.**
    """
    batches = await crud.list_with_dates(session, household_id)
    usable: list[IngredientBatch] = []
    for batch in batches:
        expiry = soonest_expiry(batch)
        if expiry is not None and (expiry[1] - today).days < 0:
            continue
        if batch.quantity is not None and batch.quantity <= 0:
            continue
        usable.append(batch)
    return usable


async def find_by_names(
    session: AsyncSession, household_id: int, names: list[str]
) -> list[IngredientBatch]:
    """음성 조회용. 이름으로 묶음을 찾는다."""
    return await crud.find_batches_by_names(session, household_id, names)


# 신선도 등급 경계. 가구의 알림 일정과 별개로 **화면 표현**의 기준이다.
# 알림은 "언제 알릴까"이고 등급은 "지금 어떤 상태인가"라서 값이 갈린다.
URGENT_WITHIN_DAYS = 1
SOON_WITHIN_DAYS = 3


def freshness_of(batch: IngredientBatch, *, today: date) -> tuple[FreshnessGrade, int | None]:
    """묶음의 신선도 등급과 남은 날.

    **기한 축만 본다.** 잔량 미확인은 등급에 섞지 않고 호출자가 별도 신호로 다룬다.

    Args:
        batch: 판정할 묶음.
        today: 가구 시간대의 오늘.

    Returns:
        `(등급, 남은 날)`. 기한 정보가 없으면 `(UNKNOWN, None)`.
    """
    expiry = soonest_expiry(batch)
    if expiry is None:
        return FreshnessGrade.UNKNOWN, None
    days_left = (expiry[1] - today).days
    if days_left < 0:
        return FreshnessGrade.EXPIRED, days_left
    if days_left <= URGENT_WITHIN_DAYS:
        return FreshnessGrade.URGENT, days_left
    if days_left <= SOON_WITHIN_DAYS:
        return FreshnessGrade.SOON, days_left
    return FreshnessGrade.FRESH, days_left


@dataclass(slots=True)
class ConditionSummary:
    """냉장고 전체 컨디션.

    Attributes:
        condition: 화면 맨 위에 뜨는 한 낱말.
        urgent_count: 오늘·내일 안에 써야 하는 묶음 수.
        soon_count: 며칠 안에 써야 하는 묶음 수.
        expired_count: 표시기한이 지난 묶음 수.
        unknown_quantity_count: 잔량을 모르는 묶음 수. 등급과 섞지 않는다.
        total_count: 살아 있는 묶음 수.
    """

    condition: FridgeCondition
    urgent_count: int
    soon_count: int
    expired_count: int
    unknown_quantity_count: int
    total_count: int


async def condition_summary(
    session: AsyncSession, household_id: int, *, today: date
) -> ConditionSummary:
    """냉장고 컨디션을 계산한다.

    등급 기준을 서버에 두는 이유는 화면이 여럿이기 때문이다. 앱에 두면 홈과 냉장고 화면이
    서로 다른 말을 한다.
    """
    batches = await crud.list_with_dates(session, household_id)
    counts = {grade: 0 for grade in FreshnessGrade}
    unknown_quantity = 0
    for batch in batches:
        grade, _ = freshness_of(batch, today=today)
        counts[grade] += 1
        if batch.quantity is None or batch.quantity_certainty in {
            QuantityCertainty.UNKNOWN.value,
            QuantityCertainty.ESTIMATED.value,
        }:
            unknown_quantity += 1

    urgent = counts[FreshnessGrade.URGENT] + counts[FreshnessGrade.EXPIRED]
    soon = counts[FreshnessGrade.SOON]
    if urgent:
        condition = FridgeCondition.URGENT
    elif soon:
        condition = FridgeCondition.ATTENTION
    else:
        condition = FridgeCondition.RELAXED

    return ConditionSummary(
        condition=condition,
        urgent_count=counts[FreshnessGrade.URGENT],
        soon_count=soon,
        expired_count=counts[FreshnessGrade.EXPIRED],
        unknown_quantity_count=unknown_quantity,
        total_count=len(batches),
    )
