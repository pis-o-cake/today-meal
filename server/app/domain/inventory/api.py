"""재고 API. `/api/inventory` 에 마운트된다."""

from datetime import date
from decimal import Decimal
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Body, Depends, Query, Response, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import dates as date_utils
from app.core.database import get_session
from app.core.enums import DateKind, QuantityCertainty, StorageLocation
from app.core.identity import CallerDep
from app.domain.household import service as household_service
from app.domain.inventory import edit as edit_service
from app.domain.inventory import service
from app.domain.inventory.schemas import (
    BatchCreateRequest,
    BatchRead,
    ConditionRead,
    DiscardAllRead,
    DiscardAllRequest,
    PriorityBatchRead,
)

router = APIRouter()

SessionDep = Annotated[AsyncSession, Depends(get_session)]


class BatchEditRequest(BaseModel):
    """화면에서 고친 재고.

    **보낸 칸만 바뀐다.** 값을 지우려면 `clear_quantity`·`clear_date` 를 쓴다 — `null` 만으로는
    "그대로 둬라" 와 "비워라" 를 구별할 수 없다.

    IMPORTANT: 기한 종류는 서로 변환되지 않는다. 고른 종류로 그대로 저장한다.
    """

    model_config = ConfigDict(extra="forbid")

    name: str | None = Field(default=None, min_length=1, max_length=100)
    quantity: Decimal | None = Field(default=None, ge=0, le=100_000)
    clear_quantity: bool = Field(
        default=False, description="잔량을 미확인으로 되돌린다. 0 과 다르다"
    )
    unit: str | None = Field(default=None, max_length=20)
    storage_location: StorageLocation | None = None
    date_kind: DateKind | None = None
    date_value: date | None = None
    clear_date: bool = Field(
        default=False, description="`date_kind` 의 날짜를 미확인으로 되돌린다"
    )
    command_id: UUID | None = Field(
        default=None,
        description="앱이 만든 요청 ID. 같은 ID 로 다시 보내도 한 번만 적용된다",
    )


@router.get("/batches", response_model=list[BatchRead], summary="현재 재고 묶음")
async def list_batches(
    caller: CallerDep,
    session: SessionDep,
    limit: Annotated[int, Query(ge=1, le=500)] = 200,
) -> list[BatchRead]:
    """가구의 현재 재고를 돌려준다.

    잔량을 모르는 묶음은 숫자를 지어내지 않고 `quantity_certainty` 로 표시한다.
    """
    household = await household_service.get_household(session, caller.household_id)
    today = date_utils.today_in(household.timezone)
    rows = await service.list_batches(session, caller.household_id, limit)
    return [_to_batch_read(row, today=today) for row in rows]


@router.get(
    "/batches/expiring",
    summary="먼저 쓸 재료",
    response_model=list[PriorityBatchRead],
)
async def list_expiring(caller: CallerDep, session: SessionDep) -> list[PriorityBatchRead]:
    """기한 임박·개봉·잔량 미확인 재료를 우선순위대로 돌려준다.

    기한이 지난 항목은 `is_cookable=false` 로 표시해 '오늘 요리할 재료' 후보에서 빼되
    목록에는 남긴다 — 사용자가 한 번 보고 판단해야 한다. 안전 여부는 판정하지 않는다.
    """
    household = await household_service.get_household(session, caller.household_id)
    today = date_utils.today_in(household.timezone)
    found = await service.list_priority_batches(
        session,
        caller.household_id,
        today=today,
        alert_days=household.expiry_alert_days,
    )
    rows: list[PriorityBatchRead] = []
    for item in found:
        expiry = service.soonest_expiry(item.batch)
        rows.append(
            PriorityBatchRead(
                batch=_to_batch_read(item.batch, today=today),
                reason=item.reason.value,
                days_left=item.days_left,
                expiry_kind=expiry[0].value if expiry else None,
                is_cookable=item.is_cookable,
            )
        )
    return rows


@router.get("/condition", response_model=ConditionRead, summary="냉장고 컨디션")
async def read_condition(caller: CallerDep, session: SessionDep) -> ConditionRead:
    """냉장고 전체 컨디션을 돌려준다.

    화면 맨 위에 한 낱말로 뜨는 값이다. 등급 기준을 서버에 두는 이유는 화면이 여럿이기
    때문이다 — 앱에 두면 홈과 냉장고 화면이 서로 다른 말을 한다.

    잔량 미확인 수를 따로 세는 이유는 신선도와 다른 사실이기 때문이다. 둘을 한 등급에
    섞으면 "기한은 멀지만 양을 모르는" 재료와 "곧 상하는" 재료가 같은 칸에 들어간다.
    """
    household = await household_service.get_household(session, caller.household_id)
    today = date_utils.today_in(household.timezone)
    summary = await service.condition_summary(session, caller.household_id, today=today)
    return ConditionRead(
        condition=summary.condition.value,
        urgent_count=summary.urgent_count,
        soon_count=summary.soon_count,
        expired_count=summary.expired_count,
        unknown_quantity_count=summary.unknown_quantity_count,
        total_count=summary.total_count,
    )


def _to_batch_read(batch: object, *, today: date) -> BatchRead:
    """묶음을 응답 스키마로 옮기며 신선도를 함께 담는다."""
    grade, days_left = service.freshness_of(batch, today=today)
    expiry = service.soonest_expiry(batch)
    read = BatchRead.model_validate(batch)
    return read.model_copy(
        update={
            "freshness": grade.value,
            "days_left": days_left,
            "expiry_kind": expiry[0].value if expiry else None,
            "quantity_uncertain": batch.quantity is None
            or batch.quantity_certainty
            in {QuantityCertainty.UNKNOWN.value, QuantityCertainty.ESTIMATED.value},
        }
    )


@router.post(
    "/batches",
    response_model=BatchRead,
    status_code=status.HTTP_201_CREATED,
    summary="재료 손으로 넣기",
)
async def add_batch(
    caller: CallerDep,
    session: SessionDep,
    body: Annotated[BatchCreateRequest, Body()],
) -> BatchRead:
    """화면에서 적은 재료를 새 묶음으로 넣는다.

    말로 넣을 때와 같은 기록을 남긴다 — 기록 화면에 나타나고, 되돌리면 묶음이 빠진다.
    같은 `command_id` 로 다시 보내면 그때 넣은 묶음을 돌려준다.

    Raises:
        422: 모르는 단위다.
    """
    household = await household_service.get_household(session, caller.household_id)
    created = await edit_service.add_batch(
        session,
        household_id=caller.household_id,
        command_id=body.command_id,
        draft=edit_service.BatchDraft(
            name=body.name,
            quantity=body.quantity,
            unit=body.unit,
            storage_location=body.storage_location,
            date_kind=body.date_kind,
            date_value=body.date_value,
        ),
    )
    return _to_batch_read(created, today=date_utils.today_in(household.timezone))


@router.post(
    "/batches/discard-all",
    response_model=DiscardAllRead,
    summary="냉장고 비우기",
)
async def discard_all(
    caller: CallerDep,
    session: SessionDep,
    body: Annotated[DiscardAllRequest | None, Body()] = None,
) -> DiscardAllRead:
    """가구의 재료를 모두 버린다.

    묶음 하나를 버릴 때와 같이 행을 지우지 않고 버린 것으로 표시한다. 한 명령으로 묶으므로
    그 `command_id` 를 되돌리면 모두 돌아온다. 버릴 것이 없으면 기록을 남기지 않는다.
    """
    command_id, count = await edit_service.discard_all(
        session,
        household_id=caller.household_id,
        command_id=body.command_id if body is not None else None,
    )
    return DiscardAllRead(command_id=command_id, discarded_count=count)


@router.patch(
    "/batches/{batch_id}",
    response_model=BatchRead,
    summary="재고 묶음 고치기",
)
async def edit_batch(
    batch_id: int,
    caller: CallerDep,
    session: SessionDep,
    body: Annotated[BatchEditRequest, Body()],
) -> BatchRead:
    """화면에서 고친 내용을 저장한다.

    말로 고치는 경로와 **같은 자리에 기록을 남긴다** — 기록 화면에서 재고가 저절로 바뀐 것처럼
    보이면 안 되고, 되돌릴 수도 있어야 한다.

    Raises:
        404: 그 묶음이 없거나 다른 가구의 것이다.
    """
    household = await household_service.get_household(session, caller.household_id)
    updated = await edit_service.edit_batch(
        session,
        household_id=caller.household_id,
        batch_id=batch_id,
        command_id=body.command_id,
        edit=edit_service.BatchEdit(
            name=body.name,
            quantity=body.quantity,
            clear_quantity=body.clear_quantity,
            unit=body.unit,
            storage_location=body.storage_location,
            date_kind=body.date_kind,
            date_value=body.date_value,
            clear_date=body.clear_date,
        ),
    )
    return _to_batch_read(
        updated, today=date_utils.today_in(household.timezone)
    )


@router.delete(
    "/batches/{batch_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="재고 묶음 버리기",
)
async def discard_batch(
    batch_id: int,
    caller: CallerDep,
    session: SessionDep,
    command_id: Annotated[
        UUID | None,
        Query(description="앱이 만든 요청 ID. 같은 ID 로 다시 보내도 한 번만 적용된다"),
    ] = None,
) -> Response:
    """묶음을 버린다.

    행을 지우지 않고 버린 것으로 표시한다 — 기록이 그 이름을 참조한다. 이미 버린 묶음에
    보내도 실패로 다루지 않는다.

    Raises:
        404: 그 묶음이 없거나 다른 가구의 것이다.
    """
    await edit_service.discard_batch(
        session,
        household_id=caller.household_id,
        batch_id=batch_id,
        command_id=command_id,
    )
    return Response(status_code=status.HTTP_204_NO_CONTENT)
