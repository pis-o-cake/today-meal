"""메뉴 추천 API. `/api/menu` 에 마운트된다."""

from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import dates as date_utils
from app.core.database import get_session
from app.core.identity import CallerDep
from app.core.llm.gateway import LlmGateway
from app.core.llm.provider import get_gateway
from app.domain.household import service as household_service
from app.domain.menu import crud, service
from app.domain.menu.schemas import (
    IngredientCheckRead,
    MenuDetailRead,
    MenuSuggestionRead,
    RecipeStep,
)

router = APIRouter()

SessionDep = Annotated[AsyncSession, Depends(get_session)]
GatewayDep = Annotated[LlmGateway, Depends(get_gateway)]


@router.post(
    "/suggestions",
    response_model=list[MenuSuggestionRead],
    summary="지금 가능한 메뉴 추천",
)
async def create_suggestions(
    caller: CallerDep,
    session: SessionDep,
    gateway: GatewayDep,
    servings: Annotated[int | None, Query(ge=1, le=12)] = None,
    max_minutes: Annotated[int | None, Query(ge=1, le=600)] = None,
) -> list[MenuSuggestionRead]:
    """현재 재고로 가능한 메뉴를 최대 3개 만든다.

    모델이 후보를 만들고 **가능 여부는 서버가 판정한다.** 필수 재료가 하나라도 없으면
    `availability` 가 `ready` 가 아니며, 화면은 그때 '지금 바로 만들기' 에 올리지 않는다.

    기한이 지난 재료는 후보 재료에서 제외한다. 추천만으로 재고를 바꾸지 않는다.
    """
    household = await household_service.get_household(session, caller.household_id)
    today = date_utils.today_in(household.timezone)
    saved = await service.suggest(
        session,
        gateway,
        household=household,
        today=today,
        servings=servings,
        max_minutes=max_minutes,
    )
    return [
        MenuSuggestionRead(
            suggestion_id=suggestion.suggestion_id,
            recipe_id=suggestion.recipe_id,
            name=scored.recipe.name,
            rank_order=suggestion.rank_order,
            servings=suggestion.servings,
            estimated_minutes=scored.recipe.estimated_minutes,
            reason=suggestion.reason,
            availability=suggestion.availability,
            priority_ingredients=scored.priority_hits,
            missing_ingredients=scored.missing,
            uncertain_ingredients=scored.uncertain,
        )
        for suggestion, scored in saved
    ]


@router.get(
    "/suggestions",
    response_model=list[MenuSuggestionRead],
    summary="가장 최근 추천 다시 보기",
)
async def read_suggestions(caller: CallerDep, session: SessionDep) -> list[MenuSuggestionRead]:
    """마지막 추천 묶음을 돌려준다.

    CAUTION: `availability` 는 **추천 시점의 스냅샷**이다. 그 뒤 재고가 바뀌었으면 실제와
    다를 수 있으므로, 화면은 새 추천을 받거나 재고를 함께 확인해야 한다.
    """
    rows = await crud.latest_suggestions(session, caller.household_id, service.MAX_SUGGESTIONS)
    out: list[MenuSuggestionRead] = []
    for suggestion in rows:
        recipe = await crud.get_recipe(session, caller.household_id, suggestion.recipe_id)
        out.append(
            MenuSuggestionRead(
                suggestion_id=suggestion.suggestion_id,
                recipe_id=suggestion.recipe_id,
                name=recipe.name,
                rank_order=suggestion.rank_order,
                servings=suggestion.servings,
                estimated_minutes=recipe.estimated_minutes,
                reason=suggestion.reason,
                availability=suggestion.availability,
            )
        )
    return out


@router.get("/recipes/{recipe_id}", response_model=MenuDetailRead, summary="메뉴 상세")
async def recipe_detail(
    recipe_id: int,
    caller: CallerDep,
    session: SessionDep,
    servings: Annotated[int | None, Query(ge=1, le=12)] = None,
) -> MenuDetailRead:
    """인분에 맞는 재료와 조리 순서를 돌려준다.

    분량을 모르는 재료는 환산하지 않고 `null` 로 둔다 — 숫자를 만들지 않는다.
    조회만으로 재고를 바꾸지 않는다.
    """
    recipe, ingredients, target = await service.detail(
        session,
        household_id=caller.household_id,
        recipe_id=recipe_id,
        servings=servings,
    )
    rows: list[IngredientCheckRead] = []
    for item in ingredients:
        scaled = service.scale(item.quantity, recipe.base_servings, target)
        rows.append(
            IngredientCheckRead(
                name=item.raw_name,
                required_amount=None if scaled is None else str(scaled.normalize()),
                unit=item.unit,
                is_essential=item.is_essential,
                # 상세 화면은 재고 대조를 하지 않는다. 대조는 추천이 한다.
                status="needs_check" if item.is_amount_unknown else "have",
            )
        )
    steps = [
        RecipeStep(order=int(step.get("order", index)), text=str(step.get("text", "")))
        for index, step in enumerate(recipe.steps or [], start=1)
    ]
    return MenuDetailRead(
        recipe_id=recipe.recipe_id,
        name=recipe.name,
        servings=target,
        base_servings=recipe.base_servings,
        estimated_minutes=recipe.estimated_minutes,
        ingredients=rows,
        steps=steps,
    )
