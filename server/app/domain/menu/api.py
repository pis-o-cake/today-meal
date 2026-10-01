"""메뉴 추천 API. `/api/menu` 에 마운트된다."""

from decimal import Decimal
from typing import Annotated
from uuid import uuid4

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import dates as date_utils
from app.core.database import get_session
from app.core.identity import CallerDep
from app.core.llm.gateway import LlmGateway
from app.core.llm.provider import get_gateway
from app.core.locale import translate
from app.domain.household import service as household_service
from app.domain.inventory.service import AppliedChange
from app.domain.menu import crud, service
from app.domain.menu.schemas import (
    CookedChange,
    CookedResult,
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
    focus: Annotated[
        list[str] | None,
        Query(max_length=3, description="꼭 쓸 재료. 그 재료가 주재료인 메뉴만 만든다"),
    ] = None,
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
        focus=focus or (),
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
    조회만으로 재고를 바꾸지 않는다. 재료 상태는 **호출한 가구의 지금 재고**로 매번 대조한다.
    """
    recipe, ingredients, target = await service.detail(
        session,
        household_id=caller.household_id,
        recipe_id=recipe_id,
        servings=servings,
    )
    household = await household_service.get_household(session, caller.household_id)
    checks = await service.check_stock(
        session,
        household_id=caller.household_id,
        ingredients=ingredients,
        base_servings=recipe.base_servings,
        servings=target,
        today=date_utils.today_in(household.timezone),
    )
    rows: list[IngredientCheckRead] = []
    for item, check in zip(ingredients, checks, strict=True):
        scaled = service.scale(item.quantity, recipe.base_servings, target)
        rows.append(
            IngredientCheckRead(
                name=item.raw_name,
                # WARNING: `str(Decimal.normalize())` 를 쓰면 안 된다. 300 이 `3E+2` 로
                # 나가 화면에 그대로 찍힌다. `_plain` 이 정수·소수를 사람이 읽는 꼴로 만든다.
                required_amount=None if scaled is None else _plain(scaled),
                unit=item.unit,
                is_essential=item.is_essential,
                status=check.status,
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


def _merge(deducted: list[AppliedChange]) -> list[CookedChange]:
    """같은 재료를 한 줄로 합친다.

    기한이 이른 묶음부터 빼므로 한 재료가 여러 묶음에서 줄 수 있다. 묶음마다 적으면 같은
    이름이 되풀이돼 무엇을 얼마나 썼는지 읽기 어렵다.
    """
    merged: dict[tuple[str, str | None], list[Decimal]] = {}
    for change in deducted:
        if change.quantity_before is None or change.quantity_after is None:
            continue
        totals = merged.setdefault(
            (change.display_name, change.unit), [Decimal("0"), Decimal("0")]
        )
        totals[0] += change.quantity_before
        totals[1] += change.quantity_after
    return [
        CookedChange(name=name, before=_plain(before), after=_plain(after), unit=unit)
        for (name, unit), (before, after) in merged.items()
    ]


def _plain(value: Decimal) -> str:
    """`10.000` 을 `10` 으로. 소수부가 의미 있는 값은 남긴다."""
    normalized = value.normalize()
    if normalized == normalized.to_integral_value():
        return str(int(normalized))
    return str(normalized)


@router.post(
    "/suggestions/{suggestion_id}/cooked",
    response_model=CookedResult,
    summary="해먹었어요 — 사용량 반영",
)
async def mark_cooked(
    suggestion_id: int,
    caller: CallerDep,
    session: SessionDep,
    servings: Annotated[
        int | None,
        Query(ge=1, le=12, description="화면에서 조리한 인분. 차감 기준이다"),
    ] = None,
) -> CookedResult:
    """추천 메뉴를 실제로 만들었다고 확인하고 재고에서 뺀다.

    IMPORTANT: 같은 추천에 확인이 두 번 와도 **재고가 두 번 줄지 않는다.** 버튼을 두 번
    누르거나 네트워크가 재시도해도 안전하다.

    레시피 필요량을 그대로 빼지 않고 **재고와 맞출 수 있는 것만** 뺀다. 분량을 모르거나
    단위 변환 근거가 없는 재료는 건너뛰고 그 이름을 돌려준다 — 숫자를 지어내지 않는다.

    차감량은 레시피에서 온 값이라 사용자가 말한 숫자가 아니다. 이력에 **추정값**으로
    남는다.

    `servings` 를 주면 그 인분으로 환산하고 추천에도 반영한다 — 화면에서 4인분으로 조리한
    사람에게 2인분을 빼면 안 된다.
    """
    household = await household_service.get_household(session, caller.household_id)
    today = date_utils.today_in(household.timezone)
    before = await crud.get_suggestion(session, caller.household_id, suggestion_id)
    already = before.consumption_applied
    command_id = uuid4()

    suggestion, skipped, question, deducted = await service.mark_cooked(
        session,
        household_id=caller.household_id,
        suggestion_id=suggestion_id,
        command_id=command_id,
        today=today,
        servings=servings,
    )
    applied = not already and question is None
    return CookedResult(
        suggestion_id=suggestion.suggestion_id,
        already_applied=already,
        changes=_merge(deducted),
        skipped_ingredients=skipped,
        clarification_question=question,
        undo_token=str(command_id) if applied else None,
        spoken=translate("menu.cooked", "ko") if applied else None,
    )
