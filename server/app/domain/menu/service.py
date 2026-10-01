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

from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from datetime import UTC, date, datetime
from decimal import Decimal
from uuid import UUID

from loguru import logger
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import stock_match
from app.core import units as unit_utils
from app.core.enums import (
    CommandIntent,
    CommandStatus,
    MenuAvailability,
    QuantityCertainty,
    RecipeSource,
    StorageLocation,
)
from app.core.llm.gateway import LlmGateway, MenuRequest
from app.core.llm.prompts import menu_ko
from app.core.llm.schemas import ProposedRecipe
from app.core.stock_match import IngredientCheck, RequiredIngredient, StockIndex
from app.domain.command.models import Command
from app.domain.command.validation import ValidatedItem
from app.domain.household.models import Household
from app.domain.ingredient import crud as ingredient_crud
from app.domain.ingredient import service as ingredient_service
from app.domain.inventory import service as inventory_service
from app.domain.inventory.models import IngredientBatch
from app.domain.inventory.service import AppliedChange
from app.domain.menu import crud
from app.domain.menu.models import MenuSuggestion, Recipe, RecipeIngredient

# 화면에 보여줄 후보 수. 더 많으면 고르는 것이 일이 된다.
MAX_SUGGESTIONS = 3

# 모델에 넘길 재고 항목 수. 전부 넘기면 토큰이 비용이다.
_CONTEXT_LIMIT = 30


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
    focus: Sequence[str] = (),
) -> list[tuple[MenuSuggestion, ScoredSuggestion]]:
    """메뉴를 추천하고 결과를 저장한다.

    저장된 행과 재고 대조 결과를 함께 돌려준다. `availability` 는 추천 시점의 스냅샷이므로
    화면이 부족·확인 재료를 그릴 때는 이 대조 결과를 쓴다.

    Args:
        focus: 사용자가 지목한 재료. 있으면 그 재료가 주재료인 메뉴만 만든다. 집에 없는
            재료여도 받는다 — 보유 여부는 재고 대조가 판정해 `availability` 로 알린다.
    """
    named = [name.strip()[:20] for name in focus if name and name.strip()][:3]
    usable = await inventory_service.cookable_batches(session, household.household_id, today=today)
    priority = await inventory_service.list_priority_batches(
        session,
        household.household_id,
        today=today,
        alert_days=household.expiry_alert_days,
    )
    priority_names = [p.batch.raw_name for p in priority if p.is_cookable]
    priority_set = set(priority_names)

    if not usable and not named:
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
        focus=named,
    )

    result = await gateway.suggest_menus(request)
    # IMPORTANT: 재고와 레시피 재료를 **같은 표준명으로** 모아 대조한다. 사용자는
    # "삼겹살" 로 넣고 레시피는 "돼지고기" 를 요구하므로, 말한 이름만 보면 가진 재료를
    # 없다고 판정한다.
    canonical = await ingredient_crud.canonical_names(
        session,
        [batch.raw_name for batch in usable]
        + [
            item.raw_name
            for recipe in result.proposal.recipes
            for item in recipe.ingredients
        ],
    )
    stock = _stock_index(usable, staples, canonical)

    scored = [
        _score(recipe, stock, priority_set, canonical)
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
    batches: Sequence[IngredientBatch],
    staples: Sequence[str],
    canonical: Mapping[str, str] | None = None,
) -> StockIndex:
    """재고 묶음을 이름 색인으로 바꾼다. 판정 규칙은 `core.stock_match` 가 갖는다."""
    return stock_match.index_stock(
        ((b.raw_name, b.quantity, b.unit) for b in batches), staples, canonical
    )


def _score(
    recipe: ProposedRecipe,
    stock: StockIndex,
    priority: set[str],
    canonical: Mapping[str, str] | None = None,
) -> ScoredSuggestion:
    """레시피 재료를 재고와 대조한다. 규칙은 `core.stock_match` 가 갖는다."""
    checks, hits = stock_match.check_ingredients(
        (
            RequiredIngredient(
                raw_name=item.raw_name,
                amount=item.amount,
                unit_text=item.unit_text,
                is_essential=item.is_essential,
                is_amount_unknown=item.is_amount_unknown,
            )
            for item in recipe.ingredients
        ),
        stock,
        priority,
        canonical,
    )
    return ScoredSuggestion(
        recipe=recipe,
        checks=checks,
        availability=_availability(checks),
        priority_hits=hits,
    )


def _availability(checks: Sequence[IngredientCheck]) -> MenuAvailability:
    """가능 여부를 판정한다. 규칙은 `core.stock_match` 가 갖는다."""
    return stock_match.availability(checks)


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


async def check_stock(
    session: AsyncSession,
    *,
    household_id: int,
    ingredients: Sequence[RecipeIngredient],
    base_servings: int,
    servings: int,
    today: date,
) -> list[IngredientCheck]:
    """레시피 재료를 **지금** 그 가구의 재고와 대조한다. 결과는 [ingredients] 와 같은 순서다.

    IMPORTANT: 상세 화면의 재료 상태는 이 결과만 쓴다. 대조 없이 `have` 로 채우면 냉장고에
    없는 재료까지 '있어요' 로 보인다. 기본 양념은 가구가 **선언한 것만** 보유로 보며 수량을
    모르므로 `needs_check` 가 된다 — 실제 재고처럼 `have` 로 말하지 않는다.

    Args:
        ingredients: 대조할 레시피 재료.
        base_servings: 레시피 원본 인분.
        servings: 화면이 보는 인분. 필요량을 이 인분으로 환산해 대조한다.
        today: 가구 시간대의 오늘. 기한이 지난 묶음은 보유로 보지 않는다.
    """
    usable = await inventory_service.cookable_batches(session, household_id, today=today)
    staples, _ = await crud.preferences(session, household_id)
    canonical = await ingredient_crud.canonical_names(
        session,
        [batch.raw_name for batch in usable] + [item.raw_name for item in ingredients],
    )
    stock = _stock_index(usable, staples, canonical)
    required: list[RequiredIngredient] = []
    for item in ingredients:
        scaled = scale(item.quantity, base_servings, servings)
        required.append(
            RequiredIngredient(
                raw_name=item.raw_name,
                amount=None if scaled is None else float(scaled),
                unit_text=item.unit,
                is_essential=item.is_essential,
                is_amount_unknown=item.is_amount_unknown,
            )
        )
    checks, _ = stock_match.check_ingredients(required, stock, None, canonical)
    return checks


def scale(amount: Decimal | None, base_servings: int, target_servings: int) -> Decimal | None:
    """분량을 인분에 맞춰 환산한다. 모르는 분량은 만들지 않는다."""
    if amount is None or base_servings <= 0:
        return None
    return (amount * Decimal(target_servings) / Decimal(base_servings)).quantize(Decimal("0.001"))


__all__ = [
    "MAX_SUGGESTIONS",
    "IngredientCheck",
    "ScoredSuggestion",
    "check_stock",
    "detail",
    "scale",
    "suggest",
]


async def mark_cooked(
    session: AsyncSession,
    *,
    household_id: int,
    suggestion_id: int,
    command_id: UUID,
    today: date,
    servings: int | None = None,
) -> tuple[MenuSuggestion, list[str], str | None, list[AppliedChange]]:
    """추천 메뉴를 실제로 만들었다고 확인하고 사용량을 반영한다.

    IMPORTANT: `consumption_applied` 가 **중복 차감을 막는다.** 같은 추천에 확인이 두 번
    오면 두 번째는 아무것도 바꾸지 않는다. 사용자가 버튼을 두 번 누르거나 네트워크가
    재시도해도 재고가 두 번 줄지 않아야 한다.

    IMPORTANT: 차감 기준은 **화면에서 조리한 인분**이다. [servings] 를 받으면 그 값을
    추천에 반영하고 그것으로 환산한다. 저장된 인분으로 빼면 사용자가 4인분을 보며 조리하고
    2인분이 빠지는 일이 생긴다.

    레시피 필요량을 그대로 빼지 않고 **재고와 맞출 수 있는 것만** 뺀다. 단위 변환 근거가
    없거나 분량을 모르는 재료는 건너뛰고 건너뛴 이름을 돌려준다 — 숫자를 지어내지 않는다.

    Args:
        session: 열려 있는 세션.
        household_id: 가구.
        suggestion_id: 확인할 추천.
        command_id: 이 변경을 묶을 명령 ID.
        today: 가구 시간대의 오늘.
        servings: 화면에서 조리한 인분. 없으면 저장된 인분을 쓴다.

    Returns:
        `(갱신된 추천, 차감하지 못한 재료 이름, 되물을 질문, 뺀 내역)`. 질문이 있으면
        **아무것도 반영하지 않았고** 확인 표시도 남기지 않았다는 뜻이다.

    Raises:
        NotFoundError: 그 추천이 없거나 다른 가구의 것일 때.
    """
    suggestion = await crud.get_suggestion(session, household_id, suggestion_id)
    if suggestion.consumption_applied:
        logger.info("Suggestion {} already applied; skipping", suggestion_id)
        return suggestion, [], None, []

    # 화면에서 바꾼 인분이 왔으면 그것이 정본이다. 추천에도 남겨 이력·재조회가 같은 수를 본다.
    if servings is not None and servings != suggestion.servings:
        logger.info(
            "Suggestion {} cooked at {} servings (stored {})",
            suggestion_id,
            servings,
            suggestion.servings,
        )
        suggestion.servings = servings

    ingredients = await crud.recipe_ingredients(session, suggestion.recipe_id)
    recipe = await crud.get_recipe(session, household_id, suggestion.recipe_id)
    staples, _ = await crud.preferences(session, household_id)
    staple_names = set(staples)

    items: list[ValidatedItem] = []
    skipped: list[str] = []
    deducted: list[AppliedChange] = []
    for item in ingredients:
        # 기본 양념은 재고 묶음으로 관리하지 않는다. 차감 대상이 아니다.
        if item.raw_name in staple_names:
            continue
        if item.is_amount_unknown or item.quantity is None or item.unit is None:
            skipped.append(item.raw_name)
            continue
        amount = scale(item.quantity, recipe.base_servings, suggestion.servings)
        if amount is None or amount <= 0:
            skipped.append(item.raw_name)
            continue
        items.append(
            ValidatedItem(
                raw_name=item.raw_name,
                amount=amount,
                unit=item.unit,
                qualitative_amount=None,
                # 레시피에서 온 값이라 사용자가 말한 숫자가 아니다.
                certainty=QuantityCertainty.ESTIMATED,
                storage=StorageLocation.UNKNOWN,
                is_remaining=False,
            )
        )

    if items:
        # IMPORTANT: 조리 확인도 재고를 바꾸는 명령이다. 명령 행을 남겨야 이력에 뜨고
        # 되돌릴 수 있다. 실수로 눌렀을 때 복구할 길이 없으면 안 된다.
        session.add(
            Command(
                command_id=command_id,
                household_id=household_id,
                utterance=f"{recipe.name} 해먹었어요",
                intent=CommandIntent.CONSUME.value,
                status=CommandStatus.APPLIED.value,
            )
        )
        await session.flush()

        # 기한이 이른 묶음부터 묻지 않고 뺀다. 조리를 마친 뒤에는 답을 들을 자리가 없어,
        # 되물으면 아무것도 빠지지 않은 채로 끝난다.
        outcome = await inventory_service.apply_usage(
            session,
            household_id=household_id,
            command_id=command_id,
            items=items,
            lenient=True,
        )
        skipped.extend(outcome.skipped)
        deducted = outcome.changes
        if not outcome.ok:
            # 되물을 일이 있으면 아무것도 반영하지 않는다. 확인 표시도 남기지 않는다.
            # 건너뛴 재료와 다른 사실이므로 칸을 나눠 돌려준다.
            logger.info("Cooked confirmation needs clarification: {}", outcome.question)
            return suggestion, skipped, outcome.question, []

    suggestion.cooked_at = datetime.now(UTC)
    suggestion.consumption_applied = True
    await session.commit()
    logger.info(
        "Suggestion {} marked cooked: {} deducted, {} skipped",
        suggestion_id,
        len(deducted),
        len(skipped),
    )
    return suggestion, skipped, None, deducted
