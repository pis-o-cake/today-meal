"""재료 사전 조회."""

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.ingredient.models import Ingredient


async def search(session: AsyncSession, keyword: str | None, limit: int) -> list[Ingredient]:
    """표준명 또는 별칭으로 재료를 찾는다.

    별칭은 배열이므로 `ANY` 로 비교한다. GIN 인덱스가 이 조회를 받는다.
    """
    statement = select(Ingredient).order_by(Ingredient.canonical_name).limit(limit)
    if keyword:
        statement = statement.where(
            or_(
                Ingredient.canonical_name.ilike(f"%{keyword}%"),
                Ingredient.aliases.any(keyword),
            )
        )
    result = await session.execute(statement)
    return list(result.scalars())
