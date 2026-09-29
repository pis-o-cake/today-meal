"""화면에서 고친 재고.

말이 아니라 **손으로** 고치는 경로다. 목업의 재료 상세(`FridgeItem`)가 쓴다.

말로 고치는 경로(`domain/command`)와 같은 자리에 기록을 남긴다 — `command` 한 줄과
`change_event` 한 줄이다. 기록을 남기지 않으면 기록 화면에서 재고가 저절로 바뀐 것처럼
보이고, 되돌릴 수도 없다.

IMPORTANT: 기한 종류를 **서로 바꾸지 않는다.** 사용자가 종류를 고르면 그 종류로 저장하며,
제조일을 소비기한으로 승격하지 않는다.

CAUTION: `utterance` 는 발화가 아니라 "화면에서 고쳤다" 는 표시다. 발화를 지어내면 기록
화면이 사용자가 하지 않은 말을 보여준다.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, date, datetime
from decimal import Decimal
from uuid import uuid4

from loguru import logger
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.enums import (
    ChangeAction,
    CommandIntent,
    CommandStatus,
    DateKind,
    DateSource,
    QuantityCertainty,
    StateEventKind,
    StorageLocation,
)
from app.core.exceptions import NotFoundError
from app.core.locale import translate
from app.domain.command.models import ChangeEvent, Command
from app.domain.ingredient import service as ingredient_service
from app.domain.inventory import crud
from app.domain.inventory.models import BatchDate, BatchStateEvent, IngredientBatch


@dataclass(slots=True)
class BatchEdit:
    """화면이 보낸 수정. **보낸 칸만** 바꾼다.

    `None` 과 "비우라" 를 구분해야 하므로 값을 지우는 것은 따로 표시한다
    (`clear_quantity`·`clear_date`) — `None` 만으로는 "그대로 둬라" 와 구별되지 않는다.
    """

    name: str | None = None
    quantity: Decimal | None = None
    clear_quantity: bool = False
    unit: str | None = None
    storage_location: StorageLocation | None = None
    date_kind: DateKind | None = None
    date_value: date | None = None
    clear_date: bool = False


async def edit_batch(
    session: AsyncSession, *, household_id: int, batch_id: int, edit: BatchEdit
) -> IngredientBatch:
    """묶음 하나를 화면에서 고친다.

    Args:
        household_id: 호출자의 가구. 남의 가구 묶음은 없는 것으로 다룬다.
        batch_id: 고칠 묶음.
        edit: 바꿀 칸.

    Returns:
        고쳐진 묶음.

    Raises:
        NotFoundError: 그 묶음이 없거나 다른 가구의 것이다.
    """
    batch = await _own_batch(session, household_id, batch_id)
    before = batch.quantity

    command = Command(
        command_id=uuid4(),
        household_id=household_id,
        utterance=translate("history.manual_edit"),
        intent=CommandIntent.ADJUST.value,
        status=CommandStatus.APPLIED.value,
    )
    session.add(command)

    if edit.name is not None and edit.name.strip():
        ingredient = await ingredient_service.resolve_or_create(session, edit.name)
        batch.ingredient_id = ingredient.ingredient_id
        batch.raw_name = edit.name.strip()

    _apply_quantity(batch, edit)
    _apply_storage(session, batch, edit, command_id=command.command_id)
    _apply_date(batch, edit)

    if batch.quantity != before:
        session.add(
            ChangeEvent(
                command_id=command.command_id,
                batch_id=batch.batch_id,
                action=ChangeAction.ADJUST.value,
                quantity_before=before,
                quantity_after=batch.quantity,
                unit=batch.unit,
                certainty=batch.quantity_certainty,
            )
        )

    batch.last_confirmed_at = datetime.now(UTC)
    if batch.quantity is not None and batch.quantity <= 0:
        batch.depleted_at = datetime.now(UTC)

    await session.commit()
    logger.info("Edited batch {} in household {}", batch_id, household_id)
    return await _own_batch(session, household_id, batch_id)


async def discard_batch(
    session: AsyncSession, *, household_id: int, batch_id: int
) -> None:
    """묶음을 버린다.

    행을 지우지 않고 `deleted_at` 을 세운다 — 기록이 참조하고 있으며, 지우면 기록 화면의
    과거 줄이 이름을 잃는다.
    """
    batch = await _own_batch(session, household_id, batch_id)
    if batch.deleted_at is not None:
        return

    command = Command(
        command_id=uuid4(),
        household_id=household_id,
        utterance=translate("history.manual_discard"),
        intent=CommandIntent.ADJUST.value,
        status=CommandStatus.APPLIED.value,
    )
    session.add(command)
    session.add(
        ChangeEvent(
            command_id=command.command_id,
            batch_id=batch.batch_id,
            action=ChangeAction.DISCARD.value,
            quantity_before=batch.quantity,
            quantity_after=Decimal(0) if batch.quantity is not None else None,
            unit=batch.unit,
            certainty=batch.quantity_certainty,
        )
    )
    batch.deleted_at = datetime.now(UTC)
    await session.commit()
    logger.info("Discarded batch {} in household {}", batch_id, household_id)


async def _own_batch(
    session: AsyncSession, household_id: int, batch_id: int
) -> IngredientBatch:
    """이 가구의 묶음. 남의 것이면 **없다고 답한다.**

    권한 없음(403)과 없음(404)을 구분하면 남의 가구에 어떤 묶음이 있는지 알 수 있다.
    """
    batch = await crud.get_batch(session, batch_id)
    if batch is None or batch.household_id != household_id or batch.deleted_at:
        raise NotFoundError(f"batch not found: {batch_id}")
    return batch


def _apply_quantity(batch: IngredientBatch, edit: BatchEdit) -> None:
    """잔량을 고친다.

    비우면 `unknown` 으로 둔다 — 0 으로 적으면 "다 썼다" 는 다른 사실이 된다.
    """
    if edit.clear_quantity:
        batch.quantity = None
        batch.quantity_certainty = QuantityCertainty.UNKNOWN.value
        return
    if edit.quantity is None:
        return
    batch.quantity = edit.quantity
    # 사용자가 손으로 적은 값이다. 추정이 아니다.
    batch.quantity_certainty = QuantityCertainty.EXACT.value
    if edit.unit is not None and edit.unit.strip():
        batch.unit = edit.unit.strip()


def _apply_storage(
    session: AsyncSession,
    batch: IngredientBatch,
    edit: BatchEdit,
    *,
    command_id: object,
) -> None:
    """보관 위치를 옮긴다. 옮긴 사실을 상태 이벤트로 남긴다."""
    target = edit.storage_location
    if target is None or target.value == batch.storage_location:
        return
    session.add(
        BatchStateEvent(
            batch_id=batch.batch_id,
            command_id=command_id,
            kind=StateEventKind.MOVED.value,
            occurred_at=datetime.now(UTC),
            from_location=batch.storage_location,
            to_location=target.value,
        )
    )
    batch.storage_location = target.value


def _apply_date(batch: IngredientBatch, edit: BatchEdit) -> None:
    """날짜를 고친다.

    같은 종류의 줄이 있으면 그것을 고치고, 없으면 새로 만든다. 다른 종류의 줄은 **그대로
    둔다** — 제조일과 소비기한이 함께 있을 수 있고, 하나를 고쳤다고 다른 것이 틀린 것은
    아니다.
    """
    if edit.clear_date and edit.date_kind is not None:
        for row in batch.dates:
            if row.kind == edit.date_kind.value:
                row.date_value = None
                row.is_confirmed = False
                row.source = DateSource.MANUAL.value
        return

    if edit.date_kind is None or edit.date_value is None:
        return

    for row in batch.dates:
        if row.kind == edit.date_kind.value:
            row.date_value = edit.date_value
            row.is_confirmed = True
            row.source = DateSource.MANUAL.value
            return

    batch.dates.append(
        BatchDate(
            batch_id=batch.batch_id,
            kind=edit.date_kind.value,
            date_value=edit.date_value,
            is_confirmed=True,
            source=DateSource.MANUAL.value,
        )
    )
