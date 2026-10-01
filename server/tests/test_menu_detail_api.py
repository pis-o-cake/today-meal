"""메뉴 상세의 재료 상태 통합 테스트.

**실제 PostgreSQL 이 필요하다.** 없으면 건너뛴다.

상세 화면의 '있어요' 는 호출한 가구의 **지금 재고**로 대조한 결과여야 한다. 레시피 재료를
대조 없이 `have` 로 채우면 냉장고에 없는 김치·고추장까지 있다고 말한다.
"""

from __future__ import annotations

from typing import Annotated
from uuid import uuid4

import pytest
from fastapi import Header
from sqlalchemy import create_engine, text

from app.core.config import get_settings
from app.core.identity import Caller, get_caller

# (이름, 수량, 단위, 필수 여부)
_RECIPE: list[tuple[str, float, str, bool]] = [
    ("삼겹살", 300, "g", True),
    ("두부", 1, "mo", True),
    ("배추김치", 200, "g", True),
    ("고추장", 1, "tbsp", True),
    ("진간장", 1, "tbsp", False),
    ("올리고당", 1, "tbsp", False),
]


def _database_ready() -> bool:
    try:
        engine = create_engine(get_settings().alembic_url, pool_pre_ping=True)
        with engine.connect() as connection:
            return bool(
                connection.execute(
                    text(
                        "select count(*) from information_schema.tables "
                        "where table_name='recipe_ingredient'"
                    )
                ).scalar_one()
            )
    except Exception:  # noqa: BLE001
        return False


pytestmark = pytest.mark.skipif(
    not _database_ready(), reason="PostgreSQL unavailable or migrations not applied"
)


@pytest.fixture
def client(monkeypatch):
    """가짜 게이트웨이를 쓰고 가구를 헤더로 고르는 테스트 클라이언트."""
    from fastapi.testclient import TestClient

    from app.core.llm import provider
    from app.core.llm.fake import FakeLlmGateway

    fake = FakeLlmGateway()
    original = provider.get_gateway
    original.cache_clear()
    monkeypatch.setattr(provider, "get_gateway", lambda: fake)

    from app.main import create_app

    app = create_app()
    app.dependency_overrides[original] = lambda: fake

    def caller_from_header(
        x_household_id: Annotated[int | None, Header(alias="X-Household-Id")] = None,
    ) -> Caller:
        return Caller(
            household_id=x_household_id or get_settings().default_household_id,
            user_id=None,
        )

    app.dependency_overrides[get_caller] = caller_from_header

    with TestClient(app) as test_client:
        yield test_client
    original.cache_clear()


@pytest.fixture
def household(client):
    """테스트마다 새 가구를 만들고 끝나면 그 가구가 남긴 행을 지운다."""
    engine = create_engine(get_settings().alembic_url)
    with engine.begin() as connection:
        household_id = connection.execute(
            text(
                "insert into household (name, timezone, default_servings, tools, "
                "expiry_alert_days) values ('테스트', 'Asia/Seoul', 2, '{}', '{3,1,0}') "
                "returning household_id"
            )
        ).scalar_one()
    yield household_id
    with engine.begin() as connection:
        for statement in (
            "delete from recipe where household_id = :h",
            "delete from household_ingredient_preference where household_id = :h",
            "delete from change_event where command_id in "
            "(select command_id from command where household_id = :h)",
            "delete from batch_state_event where command_id in "
            "(select command_id from command where household_id = :h)",
            "delete from batch_date where batch_id in "
            "(select batch_id from ingredient_batch where household_id = :h)",
            "delete from ingredient_batch where household_id = :h",
            "delete from command where household_id = :h",
            "delete from household where household_id = :h",
        ):
            connection.execute(text(statement), {"h": household_id})


def _add(client, household_id: int, name: str, quantity: str, unit: str) -> None:
    response = client.post(
        "/api/inventory/batches",
        json={
            "command_id": str(uuid4()),
            "name": name,
            "quantity": quantity,
            "unit": unit,
        },
        headers={"X-Household-Id": str(household_id)},
    )
    assert response.status_code == 201, response.text


def _recipe(household_id: int) -> int:
    engine = create_engine(get_settings().alembic_url)
    with engine.begin() as connection:
        recipe_id = connection.execute(
            text(
                "insert into recipe (household_id, name, source, base_servings) "
                "values (:h, '김치찌개', 'llm', 2) returning recipe_id"
            ),
            {"h": household_id},
        ).scalar_one()
        for name, amount, unit, essential in _RECIPE:
            connection.execute(
                text(
                    "insert into recipe_ingredient "
                    "(recipe_id, raw_name, quantity, unit, is_essential) "
                    "values (:r, :n, :q, :u, :e)"
                ),
                {"r": recipe_id, "n": name, "q": amount, "u": unit, "e": essential},
            )
    return recipe_id


def _declare_staple(household_id: int, canonical_name: str) -> None:
    engine = create_engine(get_settings().alembic_url)
    with engine.begin() as connection:
        ingredient_id = connection.execute(
            text("select ingredient_id from ingredient where canonical_name = :n"),
            {"n": canonical_name},
        ).scalar_one_or_none()
        if ingredient_id is None:
            pytest.skip(f"ingredient dictionary not seeded: {canonical_name}")
        connection.execute(
            text(
                "insert into household_ingredient_preference "
                "(household_id, ingredient_id, kind) values (:h, :i, 'pantry_staple')"
            ),
            {"h": household_id, "i": ingredient_id},
        )


def _statuses(client, household_id: int, recipe_id: int, servings: int) -> dict[str, str]:
    response = client.get(
        f"/api/menu/recipes/{recipe_id}?servings={servings}",
        headers={"X-Household-Id": str(household_id)},
    )
    assert response.status_code == 200, response.text
    return {row["name"]: row["status"] for row in response.json()["ingredients"]}


def test_detail_does_not_claim_ingredients_the_household_lacks(client, household):
    """냉장고에 없는 재료를 '있어요' 로 보이지 않는다. 가진 재료만 `have` 다."""
    for name, quantity, unit in (
        ("삼겹살", "300", "g"),
        ("두부", "1", "모"),
        ("계란", "4", "개"),
        ("대파", "1", "단"),
    ):
        _add(client, household, name, quantity, unit)
    recipe_id = _recipe(household)

    statuses = _statuses(client, household, recipe_id, servings=2)

    assert statuses["삼겹살"] == "have"
    assert statuses["두부"] == "have"
    for name in ("배추김치", "고추장", "진간장", "올리고당"):
        assert statuses[name] == "missing", f"{name} 은 이 가구에 없다"


def test_detail_scales_required_amount_before_matching(client, household):
    """인분을 늘리면 늘어난 필요량으로 대조한다. 300g 으로 4인분(600g)은 모자란다."""
    _add(client, household, "삼겹살", "300", "g")
    recipe_id = _recipe(household)

    assert _statuses(client, household, recipe_id, servings=2)["삼겹살"] == "have"
    assert _statuses(client, household, recipe_id, servings=4)["삼겹살"] == "missing"


def test_declared_staple_is_not_reported_as_real_stock(client, household):
    """선언한 기본 양념은 없다고 하지 않지만, 수량을 모르므로 '있어요' 로도 말하지 않는다."""
    _declare_staple(household, "고추장")
    recipe_id = _recipe(household)

    statuses = _statuses(client, household, recipe_id, servings=2)

    assert statuses["고추장"] == "needs_check"
    assert statuses["배추김치"] == "missing"
