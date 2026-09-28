"""재고 도메인 서비스."""

from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.inventory import crud
from app.domain.inventory.models import IngredientBatch


async def list_batches(
    session: AsyncSession, household_id: int, limit: int = 200
) -> list[IngredientBatch]:
    """가구의 현재 재고를 돌려준다."""
    return await crud.list_active(session, household_id, limit)
