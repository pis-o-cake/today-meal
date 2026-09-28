"""단위 정규화와 변환 가능 판정.

**이 파일의 유일한 규칙은 근거 없는 환산을 하지 않는 것이다.** `g↔kg` 처럼 정의상 고정된
환산만 하고, `모→g` 처럼 제품마다 다른 환산은 하지 않는다. 변환할 수 없으면 숫자를 만들지 않고
확인이 필요하다고 답한다.

이 판정이 재고 차감과 부족량 계산에 동시에 걸려 있어, 여기서 근거 없이 환산하면 잘못된 숫자가
조용히 퍼진다.
"""

from dataclasses import dataclass
from decimal import Decimal

# 정의상 고정된 환산만 둔다. 재료마다 달라지는 값은 넣지 않는다.
_MASS_TO_GRAM: dict[str, Decimal] = {
    "mg": Decimal("0.001"),
    "g": Decimal("1"),
    "kg": Decimal("1000"),
}
_VOLUME_TO_MILLILITER: dict[str, Decimal] = {
    "ml": Decimal("1"),
    "l": Decimal("1000"),
    # 조리 계량은 한국 표준 계량을 따른다. 제품이 아니라 도구의 정의라 고정값으로 둔다.
    "tsp": Decimal("5"),
    "tbsp": Decimal("15"),
    "cup": Decimal("200"),
}

# 셀 수 있는 단위. 서로 환산하지 않는다 — '모'와 '개'와 '팩'은 크기가 제품마다 다르다.
_COUNTABLE: frozenset[str] = frozenset({"ea", "mo", "pack", "bunch", "sheet", "clove"})

# 정성 표현. 숫자로 바꾸지 않는다.
QUALITATIVE_AMOUNTS: frozenset[str] = frozenset({"조금", "약간", "반", "많이", "적당히"})

_ALIASES: dict[str, str] = {
    "개": "ea", "알": "ea", "장": "sheet", "쪽": "clove",
    "모": "mo", "팩": "pack", "봉": "pack", "단": "bunch", "줌": "bunch",
    "그램": "g", "킬로": "kg", "킬로그램": "kg", "밀리": "ml", "리터": "l",
    "컵": "cup", "큰술": "tbsp", "작은술": "tsp", "티스푼": "tsp", "테이블스푼": "tbsp",
}

ALL_UNITS: frozenset[str] = frozenset(_MASS_TO_GRAM) | frozenset(_VOLUME_TO_MILLILITER) | _COUNTABLE


@dataclass(frozen=True, slots=True)
class Quantity:
    """수량과 단위 한 쌍.

    Attributes:
        amount: 수량. `NUMERIC` 과 맞추기 위해 `Decimal` 을 쓴다. `float` 는 누적 오차가 남는다.
        unit: 정규화된 단위 기호.
    """

    amount: Decimal
    unit: str


@dataclass(frozen=True, slots=True)
class ConversionResult:
    """환산 시도의 결과.

    Attributes:
        quantity: 환산에 성공한 수량. 실패하면 `None`.
        needs_confirm: 근거가 없어 확인이 필요한지. `True` 면 숫자를 만들지 않았다는 뜻이다.
        reason: 로그에 남길 영어 설명.
    """

    quantity: Quantity | None
    needs_confirm: bool
    reason: str = ""


def normalize_unit(raw: str | None) -> str | None:
    """사용자 표현을 표준 단위 기호로 바꾼다.

    Args:
        raw: 발화나 레시피에 나온 단위 표기. 예 `개`, `큰술`, `g`.

    Returns:
        표준 기호. 아는 단위가 아니면 `None`.

    Example:
        >>> normalize_unit("큰술")
        'tbsp'
        >>> normalize_unit("모")
        'mo'
        >>> normalize_unit("자루")
    """
    if raw is None:
        return None
    token = raw.strip().lower()
    if not token:
        return None
    token = _ALIASES.get(token, token)
    return token if token in ALL_UNITS else None


def is_qualitative(raw: str | None) -> bool:
    """'조금'·'반' 같은 정성 표현인지 판정한다."""
    return raw is not None and raw.strip() in QUALITATIVE_AMOUNTS


def unit_domain(unit: str) -> str | None:
    """단위가 속한 차원을 돌려준다.

    Returns:
        `mass` · `volume` · `count` 중 하나. 아는 단위가 아니면 `None`.
    """
    if unit in _MASS_TO_GRAM:
        return "mass"
    if unit in _VOLUME_TO_MILLILITER:
        return "volume"
    if unit in _COUNTABLE:
        return "count"
    return None


def convert(quantity: Quantity, target_unit: str) -> ConversionResult:
    """같은 차원 안에서만 환산한다.

    질량끼리, 부피끼리는 정의상 고정된 비율이라 환산한다. 차원이 다르거나 셀 수 있는 단위
    사이라면 **환산하지 않고** `needs_confirm=True` 를 돌려준다. `모→g` 는 제품마다 다르고,
    `ml→g` 는 밀도를 알아야 한다.

    Args:
        quantity: 바꿀 수량.
        target_unit: 목표 단위. 정규화된 기호여야 한다.

    Returns:
        환산 결과. `needs_confirm` 이 참이면 호출자는 사용자에게 양을 확인해야 한다.

    Example:
        >>> convert(Quantity(Decimal("2"), "kg"), "g").quantity.amount
        Decimal('2000')
        >>> convert(Quantity(Decimal("1"), "mo"), "g").needs_confirm
        True
    """
    source_domain = unit_domain(quantity.unit)
    target_domain = unit_domain(target_unit)

    if source_domain is None or target_domain is None:
        return ConversionResult(None, True, f"unknown unit: {quantity.unit} -> {target_unit}")

    if quantity.unit == target_unit:
        return ConversionResult(quantity, False)

    if source_domain != target_domain:
        return ConversionResult(
            None, True, f"dimension mismatch: {source_domain} -> {target_domain}"
        )

    if source_domain == "count":
        # '모'와 '팩'과 '개'는 제품마다 크기가 다르다. 근거가 없으므로 환산하지 않는다.
        return ConversionResult(None, True, f"no basis to convert {quantity.unit} -> {target_unit}")

    table = _MASS_TO_GRAM if source_domain == "mass" else _VOLUME_TO_MILLILITER
    base = quantity.amount * table[quantity.unit]
    return ConversionResult(Quantity(base / table[target_unit], target_unit), False)


def shortage(required: Quantity, available: Quantity | None) -> ConversionResult:
    """부족량을 계산한다. 같은 단위로 맞출 수 없으면 계산하지 않는다.

    보유량이 없으면 필요량 전부가 부족량이다. 음수 부족량은 만들지 않는다.

    Args:
        required: 레시피가 필요로 하는 양.
        available: 확인된 보유량. 재고가 없으면 `None`.

    Returns:
        부족량. 단위를 맞출 근거가 없으면 `needs_confirm=True`.
    """
    if available is None:
        return ConversionResult(required, False)

    converted = convert(available, required.unit)
    if converted.needs_confirm or converted.quantity is None:
        return ConversionResult(None, True, converted.reason)

    remaining = required.amount - converted.quantity.amount
    return ConversionResult(Quantity(max(remaining, Decimal("0")), required.unit), False)
