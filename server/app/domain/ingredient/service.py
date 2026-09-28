"""재료 사전 서비스."""

from loguru import logger
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.ingredient import crud
from app.domain.ingredient.models import Ingredient


async def search_ingredients(
    session: AsyncSession, keyword: str | None = None, limit: int = 50
) -> list[Ingredient]:
    """재료를 검색한다. 키워드가 없으면 앞에서부터 돌려준다."""
    return await crud.search(session, keyword, limit)


async def resolve_or_create(session: AsyncSession, raw_name: str) -> Ingredient:
    """발화에 나온 이름으로 표준 재료를 찾거나 만든다.

    찾는 순서는 표준명 → 별칭이다. 사전에 없으면 만든다 — 모르는 재료 때문에 등록을 막으면
    "말로 넣는다"는 제품 전제가 깨진다. 대신 별칭 없이 만들어 두고, 나중에 사람이 정리한다.

    Args:
        session: 열려 있는 세션. 커밋하지 않는다.
        raw_name: 사용자가 말한 재료명.

    Returns:
        찾았거나 새로 만든 재료. 새로 만든 경우 `flush` 까지만 한다.
    """
    name = raw_name.strip()
    found = await crud.find_by_name_or_alias(session, name)
    if found is not None:
        return found

    created = Ingredient(canonical_name=name, aliases=[])
    session.add(created)
    await session.flush()
    logger.info("Created ingredient from utterance: {}", name)
    return created
