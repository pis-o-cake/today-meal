"""재고 API. `/api/inventory` 에 마운트된다."""

from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import dates as date_utils
from app.core.database import get_session
from app.core.enums import QuantityCertainty
from app.core.identity import CallerDep
from app.domain.household import service as household_service
from app.domain.inventory import service
from app.domain.inventory.schemas import BatchRead, ConditionRead, PriorityBatchRead

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
