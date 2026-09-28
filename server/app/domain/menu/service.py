"""메뉴 추천.

순서가 이 모듈의 설계다.

<pre>{@code
1 inventory 가 사용 가능 / 먼저 쓸 재료를 가른다
2 LlmGateway 가 조건에 맞는 후보를 만든다
3 menu.service 가 각 재료를 재고와 대조한다
4 필수 재료가 없는 메뉴는 '지금 가능' 에서 빠진다
5 최대 3개를 이유와 함께 돌려준다
}</pre>

IMPORTANT: 2번과 3번의 순서를 뒤집으면 없는 재료로 만들 수 있다고 말하는 화면이 나온다.
**모델은 후보를 만들고 가능 여부는 코드가 판정한다.**
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import date
from decimal import Decimal

from loguru import logger
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import units as unit_utils
from app.core.enums import MenuAvailability, RecipeSource
from app.core.llm.gateway import LlmGateway, MenuRequest
from app.core.llm.prompts import menu_ko
from app.core.llm.schemas import ProposedRecipe
from app.domain.household.models import Household
from app.domain.ingredient import service as ingredient_service
from app.domain.inventory import service as inventory_service
from app.domain.inventory.models import IngredientBatch
from app.domain.menu import crud
from app.domain.menu.models import MenuSuggestion, Recipe, RecipeIngredient

# 화면에 보여줄 후보 수. 더 많으면 고르는 것이 일이 된다.
MAX_SUGGESTIONS = 3

# 모델에 넘길 재고 항목 수. 전부 넘기면 토큰이 비용이다.
_CONTEXT_LIMIT = 30


@dataclass(slots=True)
class IngredientCheck:
    """레시피 재료 한 줄의 재고 대조 결과.

    Attributes:
        status: `have` · `needs_check` · `missing`.
        reason: `needs_check` 인 이유. 로그와 화면 설명에 쓴다.
    """

    raw_name: str
    required_amount: Decimal | None
    unit: str | None
    is_essential: bool
    status: str
    reason: str | None = None


@dataclass(slots=True)
class ScoredSuggestion:
    """재고 대조를 마친 후보."""

    recipe: ProposedRecipe
    checks: list[IngredientCheck]
    availability: MenuAvailability
    priority_hits: list[str] = field(default_factory=list)

    @property
    def missing(self) -> list[str]:
        return [c.raw_name for c in self.checks if c.status == "missing"]

    @property
    def uncertain(self) -> list[str]:
        return [c.raw_name for c in self.checks if c.status == "needs_check"]

    @property
    def sort_key(self) -> tuple[int, int, int]:
        """지금 가능한 것 먼저, 먼저 쓸 재료를 많이 쓰는 것 먼저, 부족한 것이 적은 것 먼저."""
        order = {
            MenuAvailability.READY: 0,
            MenuAvailability.NEEDS_CHECK: 1,
            MenuAvailability.NEEDS_PURCHASE: 2,
        }[self.availability]
        return (order, -len(self.priority_hits), len(self.missing))


async def suggest(
    session: AsyncSession,
    gateway: LlmGateway,
    *,
    household: Household,
    today: date,
    servings: int | None = None,
    max_minutes: int | None = None,
) -> list[tuple[MenuSuggestion, ScoredSuggestion]]:
    """메뉴를 추천하고 결과를 저장한다.

    저장된 행과 재고 대조 결과를 함께 돌려준다. `availability` 는 추천 시점의 스냅샷이므로
    화면이 부족·확인 재료를 그릴 때는 이 대조 결과를 쓴다.
    """
    usable = await inventory_service.cookable_batches(session, household.household_id, today=today)
    priority = await inventory_service.list_priority_batches(
        session,
        household.household_id,
        today=today,
        alert_days=household.expiry_alert_days,
    )
    priority_names = [p.batch.raw_name for p in priority if p.is_cookable]
    priority_set = set(priority_names)

    if not usable:
        logger.info("No cookable stock for household {}", household.household_id)
        return []

    staples, avoided = await crud.preferences(session, household.household_id)
    request = MenuRequest(
        available=[
            _describe(batch)
            for batch in usable[:_CONTEXT_LIMIT]
            if batch.raw_name not in priority_set
        ]
        + [f"{name} (기본 양념)" for name in staples],
        priority=[_describe(p.batch) for p in priority if p.is_cookable][:8],
        servings=servings or household.default_servings,
        max_minutes=max_minutes,
        avoided=avoided,
        tools=list(household.tools or []),
    )

    result = await gateway.suggest_menus(request)
    stock = _stock_index(usable, staples)

    scored = [
        _score(recipe, stock, priority_set)
        for recipe in result.proposal.recipes
    ]
    scored.sort(key=lambda item: item.sort_key)
    top = scored[:MAX_SUGGESTIONS]

    saved: list[tuple[MenuSuggestion, ScoredSuggestion]] = []
    for rank, candidate in enumerate(top, start=1):
        recipe, priority_ids = await _persist_recipe(
            session, household.household_id, candidate, priority_set
        )
        suggestion = MenuSuggestion(
            household_id=household.household_id,
            recipe_id=recipe.recipe_id,
            rank_order=rank,
            reason=candidate.recipe.reason,
            servings=candidate.recipe.servings,
            priority_ingredient_ids=priority_ids,
            availability=candidate.availability.value,
        )
        session.add(suggestion)
        await session.flush()
        saved.append((suggestion, candidate))

    await session.commit()
    logger.info(
        "Suggested {} menus (model returned {}) for household {}",
        len(saved),
        len(result.proposal.recipes),
        household.household_id,
    )
    return saved


def _describe(batch: IngredientBatch) -> str:
    if batch.quantity is None:
        return f"{batch.raw_name} {batch.qualitative_amount or '잔량 미확인'}"
    return f"{batch.raw_name} {_fmt(batch.quantity)}{batch.unit or ''}"


def _stock_index(
    batches: Sequence[IngredientBatch], staples: Sequence[str]
) -> dict[str, tuple[Decimal | None, str | None]]:
    """이름으로 찾을 수 있는 재고 색인.

    같은 이름의 묶음이 여럿이면 합친다. 기본 양념은 수량을 모르는 보유로 둔다 — 사용자가
    보유한다고 선언한 것만 넣으며, 선언하지 않은 양념을 있다고 가정하지 않는다.
    """
    index: dict[str, tuple[Decimal | None, str | None]] = {}
    for batch in batches:
        current = index.get(batch.raw_name)
        if current is None:
            index[batch.raw_name] = (batch.quantity, batch.unit)
            continue
        amount, unit = current
        if amount is not None and batch.quantity is not None and unit == batch.unit:
            index[batch.raw_name] = (amount + batch.quantity, unit)
        else:
            index[batch.raw_name] = (None, unit or batch.unit)
    for name in staples:
        index.setdefault(name, (None, None))
    return index


def _score(
    recipe: ProposedRecipe,
    stock: dict[str, tuple[Decimal | None, str | None]],
    priority: set[str],
) -> ScoredSuggestion:
    """레시피 재료를 재고와 대조한다."""
    checks: list[IngredientCheck] = []
    hits: list[str] = []

    for item in recipe.ingredients:
        name = item.raw_name.strip()
        required = Decimal(str(item.amount)) if item.amount is not None else None
        unit = unit_utils.normalize_unit(item.unit_text)

        if name in priority:
            hits.append(name)

        held = stock.get(name)
        if held is None:
            checks.append(
                IngredientCheck(name, required, unit, item.is_essential, "missing")
            )
            continue

        held_amount, held_unit = held
        if item.is_amount_unknown or required is None or held_amount is None:
            # 필요량이나 보유량을 모른다. 있다고 단정하지 않고 확인 대상으로 둔다.
            checks.append(
                IngredientCheck(
                    name, required, unit, item.is_essential, "needs_check", "amount unknown"
                )
            )
            continue

        shortage = unit_utils.shortage(
            unit_utils.Quantity(required, unit or held_unit or "ea"),
            unit_utils.Quantity(held_amount, held_unit or unit or "ea"),
        )
        if shortage.needs_confirm:
            # 단위를 맞출 근거가 없다. 숫자를 만들지 않는다.
            checks.append(
                IngredientCheck(
                    name, required, unit, item.is_essential, "needs_check", shortage.reason
                )
            )
            continue
        status = "have" if shortage.quantity.amount == 0 else "missing"
        checks.append(IngredientCheck(name, required, unit, item.is_essential, status))

    return ScoredSuggestion(
        recipe=recipe,
        checks=checks,
        availability=_availability(checks),
        priority_hits=hits,
    )


def _availability(checks: Sequence[IngredientCheck]) -> MenuAvailability:
    """가능 여부를 판정한다.

    IMPORTANT: **필수 재료가 하나라도 없으면 '지금 가능' 이 아니다.** F-13 의 완료 기준이
    이 한 줄에 걸려 있다.
    """
    if any(c.status == "missing" and c.is_essential for c in checks):
        return MenuAvailability.NEEDS_PURCHASE
    if any(c.status == "needs_check" and c.is_essential for c in checks):
        return MenuAvailability.NEEDS_CHECK
    if any(c.status == "missing" for c in checks):
        # 선택 재료만 없다. 만들 수는 있지만 원래 레시피와 달라진다.
        return MenuAvailability.NEEDS_CHECK
    return MenuAvailability.READY


async def _persist_recipe(
    session: AsyncSession,
    household_id: int,
    candidate: ScoredSuggestion,
    priority: set[str],
) -> tuple[Recipe, list[int]]:
    """생성된 레시피를 저장한다. 재료는 표준명으로 이어 둔다.

    Returns:
        `(레시피, 먼저 쓰는 재료의 ingredient_id 목록)`.
    """
    recipe = Recipe(
        household_id=household_id,
        name=candidate.recipe.name,
        source=RecipeSource.LLM.value,
        base_servings=candidate.recipe.servings,
        estimated_minutes=candidate.recipe.estimated_minutes,
        steps=[{"order": i, "text": step} for i, step in enumerate(candidate.recipe.steps, 1)],
        note=menu_ko.VERSION,
    )
    session.add(recipe)
    await session.flush()

    priority_ids: list[int] = []
    for item in candidate.recipe.ingredients:
        ingredient = await ingredient_service.resolve_or_create(session, item.raw_name)
        if item.raw_name.strip() in priority:
            priority_ids.append(ingredient.ingredient_id)
        session.add(
            RecipeIngredient(
                recipe_id=recipe.recipe_id,
                ingredient_id=ingredient.ingredient_id,
                raw_name=item.raw_name,
                quantity=Decimal(str(item.amount)) if item.amount is not None else None,
                unit=unit_utils.normalize_unit(item.unit_text),
                is_essential=item.is_essential,
                is_amount_unknown=item.is_amount_unknown,
            )
        )
    await session.flush()
    return recipe, priority_ids


def _fmt(value: Decimal) -> str:
    normalized = value.normalize()
    if normalized == normalized.to_integral_value():
        return str(int(normalized))
    return str(normalized)


async def detail(
    session: AsyncSession, *, household_id: int, recipe_id: int, servings: int | None
) -> tuple[Recipe, list[RecipeIngredient], int]:
    """메뉴 상세를 인분에 맞춰 돌려준다.

    조회만으로 재고를 바꾸지 않는다. 인분 환산은 원본 대비 비율로 하며, 분량을 모르는 재료는
    환산하지 않고 미확인으로 남긴다.
    """
    recipe = await crud.get_recipe(session, household_id, recipe_id)
    ingredients = await crud.recipe_ingredients(session, recipe_id)
    target = servings or recipe.base_servings
    return recipe, ingredients, target


def scale(amount: Decimal | None, base_servings: int, target_servings: int) -> Decimal | None:
    """분량을 인분에 맞춰 환산한다. 모르는 분량은 만들지 않는다."""
    if amount is None or base_servings <= 0:
        return None
    return (amount * Decimal(target_servings) / Decimal(base_servings)).quantize(Decimal("0.001"))


__all__ = [
    "MAX_SUGGESTIONS",
    "IngredientCheck",
    "ScoredSuggestion",
    "detail",
    "scale",
    "suggest",
]
