"""재고 묶음 조회."""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.domain.inventory.models import BatchDate, IngredientBatch


async def list_active(
    session: AsyncSession, household_id: int, limit: int
) -> list[IngredientBatch]:
    """취소로 숨기지 않은 묶음을 돌려준다.

    날짜 정보를 `selectinload` 로 함께 읽는다. 묶음마다 따로 질의하면 대시보드 갱신에서
    N+1 이 된다.
    """
    statement = (
        select(IngredientBatch)
        .where(
            IngredientBatch.household_id == household_id,
            IngredientBatch.deleted_at.is_(None),
        )
        .options(selectinload(IngredientBatch.dates))
        .order_by(IngredientBatch.created_at.desc())
        .limit(limit)
    )
    result = await session.execute(statement)
    return list(result.scalars())


async def list_dates(session: AsyncSession, batch_ids: list[int]) -> list[BatchDate]:
    """여러 묶음의 날짜 정보를 한 번에 읽는다."""
    if not batch_ids:
        return []
    result = await session.execute(select(BatchDate).where(BatchDate.batch_id.in_(batch_ids)))
    return list(result.scalars())
