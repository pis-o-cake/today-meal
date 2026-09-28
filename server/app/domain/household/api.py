"""가구 설정 API. `/api/household` 에 마운트된다."""

from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.identity import CallerDep
from app.domain.household import service
from app.domain.household.schemas import HouseholdRead

router = APIRouter()

SessionDep = Annotated[AsyncSession, Depends(get_session)]


@router.get("/me", response_model=HouseholdRead, summary="호출자의 가구 설정")
async def read_my_household(caller: CallerDep, session: SessionDep) -> HouseholdRead:
    """호출자가 속한 가구의 설정을 돌려준다.

    호출자는 `X-User-Id` · `X-Household-Id` 헤더로 식별하며 **검증하지 않는다.**
    헤더가 없으면 기본 가구로 처리한다.
    """
    household = await service.get_household(session, caller.household_id)
    return HouseholdRead.model_validate(household)
