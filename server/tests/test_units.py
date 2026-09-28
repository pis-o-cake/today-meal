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
