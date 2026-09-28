"""가구 조회. 트랜잭션을 열거나 커밋하지 않는다 — service 가 한다."""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.household.models import Household


async def get(session: AsyncSession, household_id: int) -> Household | None:
    """가구 하나를 읽는다."""
    result = await session.execute(
        select(Household).where(Household.household_id == household_id)
    )
    return result.scalar_one_or_none()
