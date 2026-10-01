"""단위 정규화와 환산.

이 파일이 검증하는 것은 **근거 없는 환산을 하지 않는다**는 규칙이다.
"""

from decimal import Decimal

import pytest

from app.core.units import Quantity, convert, is_qualitative, normalize_unit, shortage, unit_domain


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("개", "ea"), ("알", "ea"), ("모", "mo"), ("팩", "pack"),
        ("큰술", "tbsp"), ("작은술", "tsp"), ("컵", "cup"),
        ("g", "g"), ("킬로그램", "kg"), ("ML", "ml"),
        ("  g  ", "g"),
        ("자루", None), ("", None), (None, None),
    ],
)
def test_normalize_unit(raw, expected):
    assert normalize_unit(raw) == expected


def test_qualitative_amounts_are_not_numbers():
    assert is_qualitative("조금")
    assert is_qualitative("반")
    assert not is_qualitative("2")


@pytest.mark.parametrize(
    ("unit", "domain"),
    [("g", "mass"), ("kg", "mass"), ("ml", "volume"), ("cup", "volume"), ("mo", "count")],
)
def test_unit_domain(unit, domain):
    assert unit_domain(unit) == domain


def test_convert_within_mass():
    result = convert(Quantity(Decimal("2"), "kg"), "g")
    assert not result.needs_confirm
    assert result.quantity == Quantity(Decimal("2000"), "g")


def test_convert_within_volume_uses_fixed_spoon_sizes():
    result = convert(Quantity(Decimal("2"), "tbsp"), "ml")
    assert result.quantity.amount == Decimal("30")


def test_convert_same_unit_is_identity():
    quantity = Quantity(Decimal("1.5"), "mo")
    assert convert(quantity, "mo").quantity == quantity


def test_countable_units_are_never_converted():
    """'모'와 '개'는 제품마다 크기가 달라 환산 근거가 없다."""
    result = convert(Quantity(Decimal("1"), "mo"), "ea")
    assert result.needs_confirm
    assert result.quantity is None


def test_mass_to_volume_needs_confirm():
    """밀도를 모르면 g 과 ml 를 오갈 수 없다."""
    assert convert(Quantity(Decimal("100"), "g"), "ml").needs_confirm


def test_count_to_mass_needs_confirm():
    """'두부 1모 = 300g' 은 근거가 없다. 숫자를 만들지 않는다."""
    result = convert(Quantity(Decimal("1"), "mo"), "g")
    assert result.needs_confirm
    assert result.quantity is None


def test_unknown_unit_needs_confirm():
    assert convert(Quantity(Decimal("1"), "자루"), "g").needs_confirm


def test_shortage_without_stock_is_full_requirement():
    result = shortage(Quantity(Decimal("20"), "g"), None)
    assert result.quantity == Quantity(Decimal("20"), "g")


def test_shortage_converts_compatible_units():
    result = shortage(Quantity(Decimal("200"), "g"), Quantity(Decimal("0.05"), "kg"))
    assert not result.needs_confirm
    assert result.quantity.amount == Decimal("150")


def test_shortage_never_returns_negative():
    result = shortage(Quantity(Decimal("100"), "g"), Quantity(Decimal("500"), "g"))
    assert result.quantity.amount == Decimal("0")


def test_shortage_needs_confirm_when_units_incompatible():
    result = shortage(Quantity(Decimal("20"), "g"), Quantity(Decimal("1"), "mo"))
    assert result.needs_confirm
    assert result.quantity is None


def test_decimal_avoids_float_drift():
    """`float` 를 쓰면 0.1 세 번이 0.30000000000000004 가 된다."""
    third = Quantity(Decimal("0.1"), "kg")
    total = sum((convert(third, "g").quantity.amount for _ in range(3)), Decimal("0"))
    assert total == Decimal("300")


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        # 모델이 조사를 단위에 붙여 보내는 일이 잦다. 못 떼면 멀쩡한 발화가 되묻기로 떨어진다.
        ("모랑", "mo"),
        ("개랑", "ea"),
        ("개와", "ea"),
        ("개하고", "ea"),
        ("그램은", "g"),
        ("컵을", "cup"),
        ("큰술도", "tbsp"),
        ("모이랑", "mo"),
        # 조사를 뗀 뒤에도 모르는 단위면 여전히 None 이다.
        ("자루랑", None),
        # 단위 자체가 조사처럼 끝나도 깨지지 않는다.
        ("단", "bunch"),
        ("장", "sheet"),
    ],
)
def test_normalize_unit_strips_trailing_particles(raw, expected):
    assert normalize_unit(raw) == expected


def test_unit_label_speaks_korean_units() -> None:
    from app.core.locale import unit_label

    # 저장은 기호로 하고 사용자에게는 표기만 내보낸다.
    assert unit_label("ea") == "개"
    assert unit_label("mo") == "모"
    assert unit_label("tbsp") == "큰술"
    assert unit_label(None) == ""
    # 메시지 팩에 없는 기호는 키가 아니라 기호 그대로 나온다.
    assert unit_label("barrel") == "barrel"


def test_every_unit_has_a_label() -> None:
    from app.core import units
    from app.core.locale import translate

    missing = [u for u in units.ALL_UNITS if translate(f"unit.{u}") == f"unit.{u}"]
    assert missing == []


@pytest.mark.parametrize(
    ("utterance", "name", "expected"),
    [
        ("계란 열 개 넣었어 유통기한은 10월 15일까지", "계란", (Decimal("10"), "ea")),
        ("두부 두 모 넣었어", "두부", (Decimal("2"), "mo")),
        ("두부 2모 샀어", "두부", (Decimal("2"), "mo")),
        ("계란은 열두 개 있어", "계란", (Decimal("12"), "ea")),
        ("대파 한 단이랑 양파 세 개 넣었어", "양파", (Decimal("3"), "ea")),
        # 되물은 질문의 답이 뒤에 이어 붙는다. 나중에 말한 것을 읽는다.
        ("계란 넣었어 유통기한은 10월 15일까지 계란 10개", "계란", (Decimal("10"), "ea")),
        # 수량을 말하지 않았으면 만들지 않는다.
        ("계란 유통기한은 10월 15일까지야", "계란", None),
        ("두부 조금 남았어", "두부", None),
        ("감자 넣었어", "계란", None),
    ],
)
def test_read_spoken_quantity(utterance, name, expected):
    from app.core.units import read_spoken_quantity

    read = read_spoken_quantity(utterance, name)
    assert (None if read is None else (read.amount, read.unit)) == expected


class TestAliasMatching:
    """말한 이름과 레시피 이름이 달라도 같은 재료로 본다.

    사용자는 "삼겹살" 로 넣고 레시피는 "돼지고기 200g" 을 요구한다. 말한 이름만 색인하면
    가진 재료를 없다고 판정해 "지금 가능" 이 나오지 않는다 — 시연에서 바로 보이는 결함이다.
    """

    #: 재료 사전이 답해 주는 이름 → 표준명. `ingredient.crud.canonical_names` 의 결과 모양이다.
    canonical = {"삼겹살": "돼지고기", "돼지고기": "돼지고기"}

    def _check(self, stock_name: str, recipe_name: str, *, amount: float = 200):
        from app.core.stock_match import (
            RequiredIngredient,
            check_ingredients,
            index_stock,
        )

        stock = index_stock(
            [(stock_name, Decimal("300"), "g")], canonical=self.canonical
        )
        checks, _ = check_ingredients(
            [RequiredIngredient(raw_name=recipe_name, amount=amount, unit_text="g")],
            stock,
            None,
            self.canonical,
        )
        return checks[0]

    def test_alias_stock_covers_a_canonical_recipe(self):
        assert self._check("삼겹살", "돼지고기").status == "have"

    def test_canonical_stock_covers_an_alias_recipe(self):
        """반대 방향도 같다. 레시피가 별칭을 쓸 수 있다."""
        assert self._check("돼지고기", "삼겹살").status == "have"

    def test_not_enough_is_still_missing(self):
        """이름이 이어졌다고 부족한 것이 채워지지는 않는다."""
        assert self._check("삼겹살", "돼지고기", amount=500).status == "missing"

    def test_unknown_name_is_not_tied_to_anything(self):
        """사전에 없는 이름은 아무 표준명에도 붙이지 않는다."""
        from app.core.stock_match import (
            RequiredIngredient,
            check_ingredients,
            index_stock,
        )

        stock = index_stock([("삼겹살", Decimal("300"), "g")], canonical=self.canonical)
        checks, _ = check_ingredients(
            [RequiredIngredient(raw_name="한우", amount=100, unit_text="g")],
            stock,
            None,
            self.canonical,
        )
        assert checks[0].status == "missing"

    def test_two_aliases_of_one_ingredient_are_summed(self):
        """삼겹살 300g 과 목살 200g 은 돼지고기 500g 이다."""
        from app.core.stock_match import (
            RequiredIngredient,
            check_ingredients,
            index_stock,
        )

        canonical = {"삼겹살": "돼지고기", "목살": "돼지고기", "돼지고기": "돼지고기"}
        stock = index_stock(
            [("삼겹살", Decimal("300"), "g"), ("목살", Decimal("200"), "g")],
            canonical=canonical,
        )
        checks, _ = check_ingredients(
            [RequiredIngredient(raw_name="돼지고기", amount=500, unit_text="g")],
            stock,
            None,
            canonical,
        )
        assert checks[0].status == "have"

    def test_priority_hits_through_an_alias(self):
        """먼저 쓸 재료가 "삼겹살" 이면 "돼지고기" 를 쓰는 레시피도 그것을 쓴 것이다."""
        from app.core.stock_match import (
            RequiredIngredient,
            check_ingredients,
            index_stock,
        )

        stock = index_stock(
            [("삼겹살", Decimal("300"), "g")], canonical=self.canonical
        )
        _, hits = check_ingredients(
            [RequiredIngredient(raw_name="돼지고기", amount=200, unit_text="g")],
            stock,
            {"삼겹살"},
            self.canonical,
        )
        assert hits == ["삼겹살"]
