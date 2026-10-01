"""재료 사전 조회."""

from collections.abc import Iterable

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


async def canonical_names(
    session: AsyncSession, names: Iterable[str]
) -> dict[str, str]:
    """말한 이름들을 재료 사전의 표준명으로 잇는다.

    사용자는 "삼겹살" 로 넣고 레시피는 "돼지고기" 를 요구한다. 대조가 말한 이름만 보면
    가진 재료를 없다고 판정하므로, 양쪽을 같은 표준명으로 모아야 한다.

    사전에 없는 이름은 **맵에 넣지 않는다.** 호출하는 쪽이 말한 이름을 그대로 쓴다 —
    모르는 재료를 아무 표준명에 붙이면 남의 재료를 가진 것으로 판정한다.

    Args:
        names: 재고나 레시피에 나온 이름들.

    Returns:
        말한 이름 → 표준명. 표준명 자신도 키로 들어간다.
    """
    wanted = {name.strip() for name in names if name and name.strip()}
    if not wanted:
        return {}
    listed = sorted(wanted)
    result = await session.execute(
        select(Ingredient.canonical_name, Ingredient.aliases).where(
            or_(
                Ingredient.canonical_name.in_(listed),
                Ingredient.aliases.overlap(listed),
            )
        )
    )
    resolved: dict[str, str] = {}
    for canonical, aliases in result:
        resolved[canonical] = canonical
        for alias in aliases or []:
            if alias in wanted:
                resolved[alias] = canonical
    return resolved
