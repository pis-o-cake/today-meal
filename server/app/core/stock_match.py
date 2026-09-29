"""레시피 재료와 재고의 대조.

메뉴 추천(`domain/menu`)과 영상 레시피(`domain/video`)가 같은 판정을 써야 하므로 여기 둔다.
두 곳에 같은 규칙을 적으면 한쪽만 고쳐져 "없는 재료로 만들 수 있다" 는 화면이 나온다.

IMPORTANT: **모델은 재료를 내고 보유 여부는 이 모듈이 판정한다.** 모델이 판정하면 없는
재료로 만들 수 있다고 말하는 화면이 나온다.

CAUTION: 판정 결과를 저장하지 않는다. 재고는 계속 바뀌므로 저장하면 옛 판정이 화면에 남는다.
조회 시점의 재고로 매번 다시 계산한다.
"""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from decimal import Decimal

from app.core import units as unit_utils
from app.core.enums import MenuAvailability

#: 재고 색인의 한 칸. 수량을 모르는 보유는 `(None, unit)` 이다.
StockIndex = dict[str, tuple[Decimal | None, str | None]]


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
class RequiredIngredient:
    """대조할 재료 한 줄.

    모델 스키마(`ProposedRecipeIngredient`)와 DB 모델을 모두 여기로 옮겨 담는다 — 그래야
    이 모듈이 어느 도메인에도 기대지 않는다.
    """

    raw_name: str
    amount: float | None = None
    unit_text: str | None = None
    is_essential: bool = True
    is_amount_unknown: bool = False


def index_stock(
    entries: Iterable[tuple[str, Decimal | None, str | None]],
    staples: Sequence[str] = (),
) -> StockIndex:
    """이름으로 찾을 수 있는 재고 색인.

    같은 이름의 묶음이 여럿이면 합친다. 기본 양념은 수량을 모르는 보유로 둔다 — 사용자가
    보유한다고 **선언한 것만** 넣으며, 선언하지 않은 양념을 있다고 가정하지 않는다.

    Args:
        entries: `(이름, 수량, 단위)`. 수량을 모르면 `None`.
        staples: 사용자가 늘 있다고 선언한 양념 이름.
    """
    index: StockIndex = {}
    for name, quantity, unit in entries:
        current = index.get(name)
        if current is None:
            index[name] = (quantity, unit)
            continue
        amount, held_unit = current
        if amount is not None and quantity is not None and held_unit == unit:
            index[name] = (amount + quantity, held_unit)
        else:
            index[name] = (None, held_unit or unit)
    for name in staples:
        index.setdefault(name, (None, None))
    return index


def check_ingredients(
    ingredients: Iterable[RequiredIngredient],
    stock: StockIndex,
    priority: set[str] | None = None,
) -> tuple[list[IngredientCheck], list[str]]:
    """재료를 하나씩 재고와 대조한다.

    Returns:
        대조 결과와, `priority` 에 든 재료 가운데 이 레시피가 쓰는 것들.
    """
    priority = priority or set()
    checks: list[IngredientCheck] = []
    hits: list[str] = []

    for item in ingredients:
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

    return checks, hits


def availability(checks: Sequence[IngredientCheck]) -> MenuAvailability:
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
