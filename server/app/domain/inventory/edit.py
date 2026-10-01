"""화면에서 고친 재고.

말이 아니라 **손으로** 고치는 경로다. 목업의 재료 상세(`FridgeItem`)가 쓴다. 손으로 넣기와
냉장고 비우기도 여기 있다 — 목업 밖의 기능이지만 기록을 남기는 규칙은 같다.

말로 고치는 경로(`domain/command`)와 같은 자리에 기록을 남긴다 — `command` 한 줄과
`change_event` 한 줄이다. 기록을 남기지 않으면 기록 화면에서 재고가 저절로 바뀐 것처럼
보이고, 되돌릴 수도 없다.

IMPORTANT: 기한 종류를 **서로 바꾸지 않는다.** 사용자가 종류를 고르면 그 종류로 저장하며,
제조일을 소비기한으로 승격하지 않는다.

CAUTION: `utterance` 는 발화가 아니라 "화면에서 고쳤다" 는 표시다. 발화를 지어내면 기록
화면이 사용자가 하지 않은 말을 보여준다.

IMPORTANT: 바꾸기 전 값을 `ChangeEvent.restore_payload` 에 담는다. 수량만 남기면 이름이나
날짜를 고친 뒤 되돌려도 그 값이 돌아오지 않는다 — 되돌리기가 반쪽이면 사용자는 무엇이
복구됐는지 알 수 없다.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, date, datetime
from decimal import Decimal
from uuid import UUID, uuid4

from loguru import logger
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import units as unit_utils
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
from app.core.exceptions import NotFoundError, UnitConversionError
from app.core.locale import translate
from app.domain.command.models import ChangeEvent, Command
from app.domain.command.validation import ValidatedDate, ValidatedItem
from app.domain.ingredient import service as ingredient_service
from app.domain.inventory import crud
from app.domain.inventory import service as inventory_service
from app.domain.inventory.models import BatchStateEvent, IngredientBatch


@dataclass(slots=True)
class BatchDraft:
    """화면에서 손으로 넣는 재료.

    Attributes:
        unit: 사용자가 고른 단위. 기호(`ea`)와 표기(`개`)를 모두 받는다.
        date_value: 모르면 `None`. 날짜 줄을 만들지 않는다.
    """

    name: str
    quantity: Decimal
    unit: str
    storage_location: StorageLocation
    date_kind: DateKind
    date_value: date | None = None


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


async def add_batch(
    session: AsyncSession,
    *,
    household_id: int,
    draft: BatchDraft,
    command_id: UUID | None = None,
) -> IngredientBatch:
    """재료 하나를 화면에서 넣는다.

    말로 넣는 경로(`register_items`)를 그대로 쓴다 — 넣는 규칙이 두 벌이면 같은 재료가
    경로에 따라 다르게 저장된다. 기록도 같은 모양으로 남아 되돌리면 묶음이 숨는다.

    Args:
        household_id: 호출자의 가구.
        draft: 넣을 재료.
        command_id: 앱이 만든 요청 ID. 같은 ID 가 이미 적용됐으면 그때 넣은 묶음을 돌려준다.

    Returns:
        새 묶음.

    Raises:
        UnitConversionError: 모르는 단위다.
        NotFoundError: 재시도한 요청 ID 가 다른 가구의 것이다.
    """
    request_id = command_id or uuid4()
    if await _already_applied(session, request_id):
        # 네트워크가 같은 요청을 다시 보냈다. 두 번 넣지 않는다.
        logger.info("Add {} already applied; returning its batch", request_id)
        return await _batch_of_command(session, household_id, request_id)

    item = _validated(draft)
    command = Command(
        command_id=request_id,
        household_id=household_id,
        utterance=translate("history.manual_add"),
        intent=CommandIntent.REGISTER.value,
        status=CommandStatus.APPLIED.value,
    )
    session.add(command)
    await session.flush()

    outcome = await inventory_service.register_items(
        session, household_id=household_id, command_id=command.command_id, items=[item]
    )
    batch_id = outcome.changes[0].batch_id
    await session.commit()
    logger.info("Added batch {} in household {}", batch_id, household_id)
    return await _own_batch(session, household_id, batch_id)


async def discard_all(
    session: AsyncSession,
    *,
    household_id: int,
    command_id: UUID | None = None,
) -> tuple[UUID | None, int]:
    """가구의 살아 있는 묶음을 모두 버린다.

    묶음 하나를 버릴 때와 같은 표시·기록을 남기되 **명령은 하나다.** 기록 화면에 한 번의
    일로 보이고, 한 번 되돌리면 모두 돌아온다.

    Args:
        household_id: 호출자의 가구. 다른 가구의 묶음은 건드리지 않는다.
        command_id: 앱이 만든 요청 ID. 같은 ID 가 이미 적용됐으면 다시 비우지 않는다.

    Returns:
        명령 ID 와 버린 묶음 수. 버릴 것이 없으면 명령을 남기지 않아 `(None, 0)` 이다.
    """
    request_id = command_id or uuid4()
    if await _already_applied(session, request_id):
        # IMPORTANT: 재시도를 다시 적용하면 그 사이에 새로 넣은 재료까지 버린다.
        events = await crud.list_events_of_command(session, request_id)
        logger.info("Discard-all {} already applied", request_id)
        return request_id, len(events)

    batches = await crud.list_with_dates(session, household_id)
    if not batches:
        return None, 0

    command = Command(
        command_id=request_id,
        household_id=household_id,
        utterance=translate("history.manual_discard_all"),
        intent=CommandIntent.ADJUST.value,
        status=CommandStatus.APPLIED.value,
    )
    session.add(command)
    moment = datetime.now(UTC)
    for batch in batches:
        session.add(
            ChangeEvent(
                command_id=command.command_id,
                batch_id=batch.batch_id,
                action=ChangeAction.DISCARD.value,
                quantity_before=batch.quantity,
                quantity_after=Decimal(0) if batch.quantity is not None else None,
                unit=batch.unit,
                certainty=batch.quantity_certainty,
                restore_payload=inventory_service.snapshot_of(batch),
            )
        )
        batch.deleted_at = moment
    await session.commit()
    logger.info("Discarded {} batches in household {}", len(batches), household_id)
    return request_id, len(batches)


async def edit_batch(
    session: AsyncSession,
    *,
    household_id: int,
    batch_id: int,
    edit: BatchEdit,
    command_id: UUID | None = None,
) -> IngredientBatch:
    """묶음 하나를 화면에서 고친다.

    IMPORTANT: 바꾸기 전 값을 원장에 함께 남긴다. 되돌리기가 이름·기한·보관 위치까지
    복원해야 사용자가 "되돌렸다" 는 말을 믿을 수 있다.

    Args:
        household_id: 호출자의 가구. 남의 가구 묶음은 없는 것으로 다룬다.
        batch_id: 고칠 묶음.
        edit: 바꿀 칸.
        command_id: 앱이 만든 요청 ID. 같은 ID 가 이미 적용됐으면 다시 적용하지 않는다.

    Returns:
        고쳐진 묶음.

    Raises:
        NotFoundError: 그 묶음이 없거나 다른 가구의 것이다.
    """
    request_id = command_id or uuid4()
    if await _already_applied(session, request_id):
        # 네트워크가 같은 요청을 다시 보냈다. 두 번 고치지 않는다.
        logger.info("Edit {} already applied; returning current batch", request_id)
        return await _own_batch(session, household_id, batch_id)

    batch = await _own_batch(session, household_id, batch_id)
    before = batch.quantity
    snapshot = inventory_service.snapshot_of(batch)

    command = Command(
        command_id=request_id,
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

    # 수량이 그대로여도 이름·날짜·위치가 바뀌었으면 원장에 남긴다. 남기지 않으면
    # 기록 화면에서 값이 저절로 바뀐 것처럼 보이고 되돌릴 수도 없다.
    if batch.quantity != before or snapshot != inventory_service.snapshot_of(batch):
        session.add(
            ChangeEvent(
                command_id=command.command_id,
                batch_id=batch.batch_id,
                action=ChangeAction.ADJUST.value,
                quantity_before=before,
                quantity_after=batch.quantity,
                unit=batch.unit,
                certainty=batch.quantity_certainty,
                restore_payload=snapshot,
            )
        )

    batch.last_confirmed_at = datetime.now(UTC)
    if batch.quantity is not None and batch.quantity <= 0:
        batch.depleted_at = datetime.now(UTC)

    await session.commit()
    logger.info("Edited batch {} in household {}", batch_id, household_id)
    return await _own_batch(session, household_id, batch_id)


async def discard_batch(
    session: AsyncSession,
    *,
    household_id: int,
    batch_id: int,
    command_id: UUID | None = None,
) -> None:
    """묶음을 버린다.

    행을 지우지 않고 `deleted_at` 을 세운다 — 기록이 참조하고 있으며, 지우면 기록 화면의
    과거 줄이 이름을 잃는다. 되돌리기는 이 표시를 풀어 묶음을 되살린다.

    IMPORTANT: **이미 버린 묶음에 다시 보내도 성공이다.** 네트워크 재시도가 실패로
    돌아오면 사용자는 버려지지 않았다고 믿는다.
    """
    request_id = command_id or uuid4()
    if await _already_applied(session, request_id):
        logger.info("Discard {} already applied", request_id)
        return

    batch = await _any_own_batch(session, household_id, batch_id)
    if batch.deleted_at is not None:
        return

    command = Command(
        command_id=request_id,
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
            restore_payload=inventory_service.snapshot_of(batch),
        )
    )
    batch.deleted_at = datetime.now(UTC)
    await session.commit()
    logger.info("Discarded batch {} in household {}", batch_id, household_id)


async def _own_batch(
    session: AsyncSession, household_id: int, batch_id: int
) -> IngredientBatch:
    """이 가구의 **살아 있는** 묶음. 남의 것이면 없다고 답한다.

    권한 없음(403)과 없음(404)을 구분하면 남의 가구에 어떤 묶음이 있는지 알 수 있다.
    """
    batch = await _any_own_batch(session, household_id, batch_id)
    if batch.deleted_at:
        raise NotFoundError(f"batch not found: {batch_id}")
    return batch


async def _any_own_batch(
    session: AsyncSession, household_id: int, batch_id: int
) -> IngredientBatch:
    """버린 것을 포함한 이 가구의 묶음.

    버리기 재시도는 이미 버린 묶음도 찾아야 한다 — 없다고 답하면 재시도가 실패가 된다.
    """
    batch = await crud.get_batch(session, batch_id)
    if batch is None or batch.household_id != household_id:
        raise NotFoundError(f"batch not found: {batch_id}")
    return batch


async def _batch_of_command(
    session: AsyncSession, household_id: int, command_id: UUID
) -> IngredientBatch:
    """한 요청이 넣은 묶음. 넣기 재시도가 같은 묶음을 돌려받게 한다.

    되돌려 숨긴 묶음도 찾는다 — 재시도가 404 로 돌아오면 넣지 못한 것으로 읽힌다.
    """
    events = await crud.list_events_of_command(session, command_id)
    if not events:
        raise NotFoundError(f"no batch registered by command {command_id}")
    return await _any_own_batch(session, household_id, events[0].batch_id)


def _validated(draft: BatchDraft) -> ValidatedItem:
    """화면 입력을 말로 넣을 때와 같은 형태로 바꾼다.

    IMPORTANT: 단위를 모르면 저장하지 않는다. 모르는 단위로 적힌 수량은 레시피 차감에서
    환산할 수 없어 없는 재료처럼 다뤄진다.

    Raises:
        UnitConversionError: 모르는 단위다.
    """
    unit = unit_utils.normalize_unit(draft.unit)
    if unit is None:
        raise UnitConversionError(f"unknown unit: {draft.unit}")

    dates: list[ValidatedDate] = []
    if draft.date_value is not None:
        dates.append(
            ValidatedDate(
                kind=draft.date_kind,
                value=draft.date_value,
                raw_text=None,
                source=DateSource.MANUAL,
            )
        )
    return ValidatedItem(
        raw_name=draft.name.strip(),
        amount=draft.quantity,
        unit=unit,
        qualitative_amount=None,
        # 사용자가 손으로 적은 값이다. 추정이 아니다.
        certainty=QuantityCertainty.EXACT,
        storage=draft.storage_location,
        is_remaining=False,
        dates=dates,
    )


async def _already_applied(session: AsyncSession, command_id: UUID) -> bool:
    """같은 요청 ID 가 이미 적용됐는지. 재시도를 두 번 적용하지 않는다."""
    return await session.get(Command, command_id) is not None


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

    inventory_service.put_date(
        batch, kind=edit.date_kind, value=edit.date_value, source=DateSource.MANUAL
    )
