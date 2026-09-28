"""시연과 평가에 쓰는 기본 레시피.

**직접 검토한 레시피만 넣는다.** 모델이 만든 것을 seed 로 두면 검증한 것과 생성한 것의 구분이
사라진다. 전역(`household_id = NULL`)으로 넣어 어느 가구에서나 쓴다.

추천은 이 레시피를 변형하거나 새로 만든다. seed 가 있는 이유는 모델이 막혔을 때도 메뉴 화면이
비지 않게 하려는 것이다.
"""

import asyncio

from loguru import logger
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import SessionFactory, dispose_engine
from app.core.enums import RecipeSource
from app.core.router import import_domain_models

# 재료 한 줄: (이름, 수량, 단위, 필수 여부). 수량이 None 이면 분량 미확인이다.
_Ingredient = tuple[str, float | None, str | None, bool]
# 레시피 한 줄: (이름, 인분, 예상 분, 재료, 조리 단계)
_Recipe = tuple[str, int, int, list[_Ingredient], list[str]]

_RECIPES: list[_Recipe] = [
    ("두부계란전", 2, 15,
     [("두부", 1, "mo", True), ("계란", 2, "ea", True), ("소금", None, None, False),
      ("식용유", 2, "tbsp", True), ("대파", None, None, False)],
     ["두부를 1cm 두께로 썰어 물기를 뺀다", "계란을 풀어 소금으로 간한다",
      "두부에 계란물을 묻힌다", "달군 팬에 식용유를 두르고 양면을 노릇하게 부친다"]),
    ("계란볶음밥", 2, 15,
     [("밥", 400, "g", True), ("계란", 2, "ea", True), ("대파", 1, "bunch", False),
      ("간장", 1, "tbsp", True), ("식용유", 2, "tbsp", True), ("소금", None, None, False)],
     ["대파를 잘게 썬다", "팬에 기름을 두르고 대파를 볶아 향을 낸다",
      "계란을 넣어 스크램블한다", "밥을 넣고 간장으로 간해 볶는다"]),
    ("두부김치", 2, 20,
     [("두부", 1, "mo", True), ("김치", 200, "g", True), ("돼지고기", 150, "g", False),
      ("참기름", 1, "tbsp", True), ("설탕", None, None, False)],
     ["두부를 도톰하게 썰어 끓는 물에 데친다", "김치를 먹기 좋게 썬다",
      "팬에 참기름을 두르고 김치를 볶는다", "데친 두부와 함께 담아낸다"]),
    ("된장찌개", 2, 25,
     [("된장", 2, "tbsp", True), ("두부", 1, "mo", True), ("양파", 1, "ea", True),
      ("애호박", None, None, False), ("대파", 1, "bunch", False), ("마늘", 2, "clove", True)],
     ["물 500ml 에 된장을 풀어 끓인다", "양파와 애호박을 넣고 5분 끓인다",
      "두부와 마늘을 넣는다", "대파를 올려 한 번 더 끓인다"]),
    ("계란국", 2, 10,
     [("계란", 2, "ea", True), ("대파", 1, "bunch", False), ("소금", None, None, True),
      ("간장", 1, "tsp", False)],
     ["물 500ml 를 끓인다", "계란을 풀어 천천히 붓는다",
      "소금과 간장으로 간한다", "대파를 올린다"]),
    ("감자볶음", 2, 15,
     [("감자", 2, "ea", True), ("양파", 1, "ea", False), ("소금", None, None, True),
      ("식용유", 2, "tbsp", True)],
     ["감자를 얇게 채 썰어 물에 헹군다", "팬에 기름을 두르고 감자를 볶는다",
      "양파를 넣고 소금으로 간한다", "감자가 투명해지면 불을 끈다"]),
    ("돼지고기김치볶음", 2, 20,
     [("돼지고기", 200, "g", True), ("김치", 200, "g", True), ("양파", 1, "ea", False),
      ("고추장", 1, "tbsp", False), ("식용유", 1, "tbsp", True), ("설탕", None, None, False)],
     ["돼지고기를 먹기 좋게 썬다", "팬에 기름을 두르고 고기를 볶는다",
      "김치와 양파를 넣고 볶는다", "고추장과 설탕으로 간을 맞춘다"]),
    ("소고기무국", 2, 30,
     [("소고기", 150, "g", True), ("무", 200, "g", True), ("대파", 1, "bunch", False),
      ("간장", 1, "tbsp", True), ("마늘", 2, "clove", True), ("참기름", 1, "tsp", False)],
     ["소고기를 참기름에 볶는다", "물 600ml 와 무를 넣고 끓인다",
      "간장과 마늘로 간한다", "무가 투명해지면 대파를 넣는다"]),
    ("애호박새우볶음", 2, 15,
     [("애호박", 1, "ea", True), ("새우", 100, "g", True), ("마늘", 2, "clove", True),
      ("소금", None, None, True), ("식용유", 1, "tbsp", True)],
     ["애호박을 반달 모양으로 썬다", "팬에 기름을 두르고 마늘을 볶는다",
      "새우를 넣어 볶는다", "애호박을 넣고 소금으로 간한다"]),
    ("라면계란탕", 1, 10,
     [("라면", 1, "ea", True), ("계란", 1, "ea", False), ("대파", None, None, False)],
     ["물 550ml 를 끓인다", "면과 스프를 넣는다", "계란을 풀어 넣는다", "대파를 올린다"]),
]


async def seed_recipes(session: AsyncSession) -> int:
    """없는 레시피만 넣는다. 멱등이다."""
    from app.domain.ingredient import service as ingredient_service
    from app.domain.menu.models import Recipe, RecipeIngredient

    existing = await session.execute(
        select(Recipe.name).where(Recipe.household_id.is_(None))
    )
    known = set(existing.scalars())
    added = 0

    for name, servings, minutes, ingredients, steps in _RECIPES:
        if name in known:
            continue
        recipe = Recipe(
            household_id=None,
            name=name,
            source=RecipeSource.SEED.value,
            base_servings=servings,
            estimated_minutes=minutes,
            steps=[{"order": i, "text": step} for i, step in enumerate(steps, 1)],
        )
        session.add(recipe)
        await session.flush()

        for raw_name, amount, unit, essential in ingredients:
            ingredient = await ingredient_service.resolve_or_create(session, raw_name)
            session.add(
                RecipeIngredient(
                    recipe_id=recipe.recipe_id,
                    ingredient_id=ingredient.ingredient_id,
                    raw_name=raw_name,
                    quantity=amount,
                    unit=unit,
                    is_essential=essential,
                    # 분량을 정하지 않은 재료는 미확인으로 둔다. 숫자를 만들지 않는다.
                    is_amount_unknown=amount is None,
                )
            )
        added += 1

    await session.flush()
    logger.info("Seeded {} recipes ({} already present)", added, len(known))
    return added


async def run() -> None:
    """레시피만 따로 넣는다."""
    import_domain_models()
    async with SessionFactory() as session:
        await seed_recipes(session)
        await session.commit()
    await dispose_engine()


if __name__ == "__main__":
    from app.core.logging import configure_logging

    configure_logging()
    asyncio.run(run())
