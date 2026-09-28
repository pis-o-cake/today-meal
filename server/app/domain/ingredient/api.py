"""표준 재료 사전 API. `/api/ingredient` 에 마운트된다."""

from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.domain.ingredient import service
from app.domain.ingredient.schemas import IngredientRead

router = APIRouter()

SessionDep = Annotated[AsyncSession, Depends(get_session)]


@router.get("", response_model=list[IngredientRead], summary="재료 사전 검색")
async def search_ingredients(
    session: SessionDep,
    q: Annotated[str | None, Query(description="표준명 또는 별칭")] = None,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
) -> list[IngredientRead]:
    """표준명이나 별칭으로 재료를 찾는다."""
    rows = await service.search_ingredients(session, q, limit)
    return [IngredientRead.model_validate(row) for row in rows]
