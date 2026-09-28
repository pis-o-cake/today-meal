"""가구 도메인 서비스."""

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import NotFoundError
from app.domain.household import crud
from app.domain.household.models import Household


async def get_household(session: AsyncSession, household_id: int) -> Household:
    """가구를 읽는다.

    Raises:
        NotFoundError: 그 가구가 없을 때.
    """
    household = await crud.get(session, household_id)
    if household is None:
        raise NotFoundError(f"household not found: {household_id}")
    return household
