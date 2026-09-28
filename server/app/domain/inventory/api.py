"""재고 API. `/api/inventory` 에 마운트된다."""

from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.identity import CallerDep
from app.core.pending import not_implemented
from app.domain.inventory import service
from app.domain.inventory.schemas import BatchRead

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


@router.get("/batches/expiring", summary="먼저 쓸 재료", response_model=list[BatchRead])
async def list_expiring(caller: CallerDep, session: SessionDep) -> list[BatchRead]:
    """기한 임박·개봉·잔량 미확인 재료를 돌려준다."""
    raise not_implemented("S-07", "F-12")
