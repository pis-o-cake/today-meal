"""레시피와 추천 조회."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.enums import PreferenceKind
from app.core.exceptions import NotFoundError
from app.domain.household.models import HouseholdIngredientPreference
from app.domain.ingredient.models import Ingredient
from app.domain.menu.models import MenuSuggestion, Recipe, RecipeIngredient


async def preferences(
    session: AsyncSession, household_id: int
) -> tuple[list[str], list[str]]:
    """보유 기본 양념과 쓰지 말 재료의 이름 목록.

    Returns:
        `(기본 양념, 기피·알레르기 재료)`. 선언하지 않은 양념을 보유로 가정하지 않는다.
    """
    result = await session.execute(
        select(HouseholdIngredientPreference.kind, Ingredient.canonical_name)
        .join(
            Ingredient,
            Ingredient.ingredient_id == HouseholdIngredientPreference.ingredient_id,
        )
        .where(HouseholdIngredientPreference.household_id == household_id)
    )
    staples: list[str] = []
    avoided: list[str] = []
    for kind, name in result:
        if kind == PreferenceKind.PANTRY_STAPLE.value:
            staples.append(name)
        else:
            avoided.append(name)
    return staples, avoided


async def get_recipe(session: AsyncSession, household_id: int, recipe_id: int) -> Recipe:
    """레시피 하나를 읽는다. 전역 seed 레시피도 대상이다.

    Raises:
        NotFoundError: 없거나 다른 가구의 레시피일 때.
    """
    result = await session.execute(select(Recipe).where(Recipe.recipe_id == recipe_id))
    recipe = result.scalar_one_or_none()
    if recipe is None or (recipe.household_id not in (None, household_id)):
        raise NotFoundError(f"recipe not found: {recipe_id}")
    return recipe


async def recipe_ingredients(session: AsyncSession, recipe_id: int) -> list[RecipeIngredient]:
    """레시피의 재료를 등록 순서대로 읽는다."""
    result = await session.execute(
        select(RecipeIngredient)
        .where(RecipeIngredient.recipe_id == recipe_id)
        .order_by(RecipeIngredient.recipe_ingredient_id)
    )
    return list(result.scalars())


async def latest_suggestions(
    session: AsyncSession, household_id: int, limit: int
) -> list[MenuSuggestion]:
    """가장 최근 추천 묶음을 순위대로 읽는다."""
    newest = await session.execute(
        select(MenuSuggestion.created_at)
        .where(MenuSuggestion.household_id == household_id)
        .order_by(MenuSuggestion.created_at.desc())
        .limit(1)
    )
    moment = newest.scalar_one_or_none()
    if moment is None:
        return []
    result = await session.execute(
        select(MenuSuggestion)
        .where(
            MenuSuggestion.household_id == household_id,
            MenuSuggestion.created_at == moment,
        )
        .order_by(MenuSuggestion.rank_order)
        .limit(limit)
    )
    return list(result.scalars())
