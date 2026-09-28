"""재고 API. `/api/inventory` 에 마운트된다."""

from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import dates as date_utils
from app.core.database import get_session
from app.core.identity import CallerDep
from app.domain.household import service as household_service
from app.domain.inventory import service
from app.domain.inventory.schemas import BatchRead, PriorityBatchRead

router = APIRouter()

SessionDep = Annotated[AsyncSession, Depends(get_session)]


@router.get("/batches", response_model=list[BatchRead], summary="현재 재고 묶음")
async def list_batches(
    caller: CallerDep,
    session: SessionDep,
    limit: Annotated[int, Query(ge=1, le=500)] = 200,
) -> list[BatchRead]:
    """가구의 현재 재고를 돌려준다.

    잔량을 모르는 묶음은 숫자를 지어내지 않고 `quantity_certainty` 로 표시한다.
    """
    rows = await service.list_batches(session, caller.household_id, limit)
    return [BatchRead.model_validate(row) for row in rows]


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
                batch=BatchRead.model_validate(item.batch),
                reason=item.reason.value,
                days_left=item.days_left,
                expiry_kind=expiry[0].value if expiry else None,
                is_cookable=item.is_cookable,
            )
        )
    return rows
