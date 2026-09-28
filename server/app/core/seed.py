"""시연과 개발에 쓰는 초기 데이터.

기본 가구 하나와 흔한 재료 사전을 넣는다. 멱등이므로 여러 번 실행해도 중복되지 않는다.
시연 데이터가 아니라 **사전과 가구 골격**이다 — 재고는 음성으로 넣는다.
"""

import asyncio

from loguru import logger
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.database import SessionFactory, dispose_engine
from app.core.router import import_domain_models
from app.core.seed_recipes import seed_recipes

# (표준명, 별칭, 분류, 기본 단위, 양념 여부)
_INGREDIENTS: list[tuple[str, list[str], str, str, bool]] = [
    ("계란", ["달걀", "알"], "달걀", "ea", False),
    ("두부", ["부침두부", "찌개두부", "순두부"], "콩류", "mo", False),
    ("대파", ["파", "쪽파", "실파"], "채소", "bunch", False),
    ("양파", ["어니언"], "채소", "ea", False),
    ("감자", [], "채소", "ea", False),
    ("당근", [], "채소", "ea", False),
    ("애호박", ["호박"], "채소", "ea", False),
    ("마늘", ["깐마늘", "다진마늘"], "채소", "clove", False),
    ("배추", ["알배추"], "채소", "ea", False),
    ("김치", ["배추김치", "묵은지"], "반찬", "g", False),
    ("우유", ["멸균우유"], "유제품", "ml", False),
    ("버터", ["무염버터", "가염버터"], "유제품", "g", False),
    ("치즈", ["슬라이스치즈", "모짜렐라"], "유제품", "g", False),
    ("돼지고기", ["삼겹살", "목살", "앞다리살"], "육류", "g", False),
    ("소고기", ["불고기감", "등심", "차돌박이"], "육류", "g", False),
    ("닭고기", ["닭가슴살", "닭다리"], "육류", "g", False),
    ("새우", ["칵테일새우"], "수산", "g", False),
    ("멸치", ["국물용멸치"], "수산", "g", False),
    ("밥", ["쌀밥", "즉석밥"], "곡류", "g", False),
    ("쌀", [], "곡류", "g", False),
    ("라면", ["봉지라면"], "면류", "ea", False),
    ("소면", ["국수"], "면류", "g", False),
    ("식용유", ["카놀라유", "포도씨유"], "양념", "ml", True),
    ("참기름", [], "양념", "ml", True),
    ("간장", ["진간장", "국간장"], "양념", "ml", True),
    ("소금", [], "양념", "g", True),
    ("설탕", [], "양념", "g", True),
    ("후추", ["후춧가루"], "양념", "g", True),
    ("고추장", [], "양념", "g", True),
    ("된장", [], "양념", "g", True),
    ("고춧가루", [], "양념", "g", True),
    ("식초", [], "양념", "ml", True),
]


async def seed_household(session: AsyncSession) -> int:
    """기본 가구를 만들거나 찾는다."""
    from app.domain.household.models import Household

    settings = get_settings()
    existing = await session.execute(
        select(Household).where(Household.household_id == settings.default_household_id)
    )
    household = existing.scalar_one_or_none()
    if household is not None:
        return household.household_id

    # IMPORTANT: 기본 가구의 id 를 설정값으로 고정한다. IDENTITY 가 주는 값을 쓰면
    # `X-Household-Id` 헤더가 없을 때 참조할 가구가 어긋난다.
    household = Household(
        household_id=settings.default_household_id,
        name="우리 집",
        default_servings=2,
        tools=["프라이팬", "냄비", "전자레인지"],
    )
    session.add(household)
    await session.flush()
    # 명시 id 로 넣었으므로 시퀀스를 그 뒤로 옮긴다. 안 하면 다음 INSERT 가 PK 충돌한다.
    await session.execute(
        text(
            "SELECT setval(pg_get_serial_sequence('household', 'household_id'), "
            "GREATEST((SELECT MAX(household_id) FROM household), 1))"
        )
    )
    logger.info("Seeded household id={}", household.household_id)
    return household.household_id


async def seed_ingredients(session: AsyncSession) -> int:
    """없는 재료만 넣는다."""
    from app.domain.ingredient.models import Ingredient

    result = await session.execute(select(Ingredient.canonical_name))
    known = set(result.scalars())
    added = 0
    for name, aliases, category, unit, staple in _INGREDIENTS:
        if name in known:
            continue
        session.add(
            Ingredient(
                canonical_name=name,
                aliases=aliases,
                category=category,
                default_unit=unit,
                is_pantry_staple=staple,
            )
        )
        added += 1
    await session.flush()
    logger.info("Seeded {} ingredients ({} already present)", added, len(known))
    return added


async def seed_pantry_staples(session: AsyncSession, household_id: int) -> int:
    """양념류를 그 가구의 보유 기본 양념으로 선언한다.

    선언하지 않은 양념을 있다고 가정하지 않는 것이 정책이므로, 기본값을 명시적으로 넣는다.
    """
    from app.core.enums import PreferenceKind
    from app.domain.household.models import HouseholdIngredientPreference
    from app.domain.ingredient.models import Ingredient

    staples = await session.execute(
        select(Ingredient.ingredient_id).where(Ingredient.is_pantry_staple.is_(True))
    )
    existing = await session.execute(
        select(HouseholdIngredientPreference.ingredient_id).where(
            HouseholdIngredientPreference.household_id == household_id,
            HouseholdIngredientPreference.kind == PreferenceKind.PANTRY_STAPLE.value,
        )
    )
    known = set(existing.scalars())
    added = 0
    for ingredient_id in staples.scalars():
        if ingredient_id in known:
            continue
        session.add(
            HouseholdIngredientPreference(
                household_id=household_id,
                ingredient_id=ingredient_id,
                kind=PreferenceKind.PANTRY_STAPLE.value,
            )
        )
        added += 1
    await session.flush()
    return added


async def run() -> None:
    """전체 시드를 한 트랜잭션으로 실행한다."""
    import_domain_models()
    async with SessionFactory() as session:
        household_id = await seed_household(session)
        await seed_ingredients(session)
        staples = await seed_pantry_staples(session, household_id)
        recipes = await seed_recipes(session)
        await session.commit()
    logger.info(
        "Seed complete (household={}, pantry staples={}, recipes={})",
        household_id,
        staples,
        recipes,
    )
    await dispose_engine()


if __name__ == "__main__":
    from app.core.logging import configure_logging

    configure_logging()
    asyncio.run(run())
