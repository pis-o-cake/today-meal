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


async def find_by_name_or_alias(session: AsyncSession, name: str) -> Ingredient | None:
    """표준명이 정확히 같거나 별칭에 포함된 재료를 찾는다.

    부분 일치를 쓰지 않는 이유는 `파` 가 `양파` 에 걸려 잘못된 재료를 고르기 때문이다.
    별칭은 사람이 등록한 값이라 정확히 비교한다.
    """
    result = await session.execute(
        select(Ingredient)
        .where(or_(Ingredient.canonical_name == name, Ingredient.aliases.any(name)))
        .order_by(Ingredient.ingredient_id)
        .limit(1)
    )
    return result.scalar_one_or_none()
