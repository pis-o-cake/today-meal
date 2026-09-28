"""재료 사전 서비스."""

from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.ingredient import crud
from app.domain.ingredient.models import Ingredient


async def search_ingredients(
    session: AsyncSession, keyword: str | None = None, limit: int = 50
) -> list[Ingredient]:
    """재료를 검색한다. 키워드가 없으면 앞에서부터 돌려준다."""
    return await crud.search(session, keyword, limit)
