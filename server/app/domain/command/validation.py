"""모델 제안의 검증.

**여기가 이 서버의 문이다.** 모델 출력은 구조가 맞아도 내용이 사실이라는 뜻이 아니다. 이
모듈은 실행 가능한 형태로 바꿀 수 있는 것만 통과시키고, 나머지는 되물을 질문으로 바꾼다.

숫자를 만들지 않는 것이 원칙이다. 단위를 모르면 확인하고, 날짜를 확정할 수 없으면 확인한다.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from decimal import Decimal, InvalidOperation

from app.core import dates as date_utils
from app.core import units as unit_utils
from app.core.enums import DateKind, DateSource, QuantityCertainty, StorageLocation
from app.core.llm.schemas import CommandProposal, ProposedItem
from app.core.particles import with_topic


@dataclass(slots=True)
class ValidatedDate:
    """확정된 날짜 하나."""

    kind: DateKind
    value: date | None
    raw_text: str | None
    source: DateSource = DateSource.VOICE
    is_confirmed: bool = True


@dataclass(slots=True)
class ValidatedItem:
    """실행할 수 있는 형태로 바뀐 항목.

    Attributes:
        amount: 수량. 정성 표현이면 `None`.
        unit: 정규화된 단위 기호. 정성 표현이면 `None`.
        is_remaining: 남은 양을 말한 것인지. 차감과 보정을 가른다.
    """

    raw_name: str
    amount: Decimal | None
    unit: str | None
    qualitative_amount: str | None
    certainty: QuantityCertainty
    storage: StorageLocation
    is_remaining: bool
    dates: list[ValidatedDate] = field(default_factory=list)


@dataclass(slots=True)
class ValidationOutcome:
    """검증 결과.

    Attributes:
        items: 통과한 항목.
        question: 되물을 한 가지. 있으면 **아무것도 실행하지 않는다.**
        rejection: 실행할 수 없는 이유. 로그용 영어.
    """

    items: list[ValidatedItem] = field(default_factory=list)
    question: str | None = None
    rejection: str | None = None

    @property
    def ok(self) -> bool:
        return self.question is None and self.rejection is None


def validate(
    proposal: CommandProposal,
    *,
    today: date,
    require_amount: bool,
) -> ValidationOutcome:
    """제안을 검증한다.

    Args:
        proposal: 모델이 낸 제안.
        today: 가구 시간대의 오늘. 날짜 확정 기준이다.
        require_amount: 수량이 반드시 있어야 하는지. 등록·차감·보정은 참, 조회는 거짓.

    Returns:
        통과한 항목이거나 되물을 질문. 질문이 있으면 항목은 비어 있다.
    """
    # 모델이 스스로 모호함을 신고했으면 그대로 따른다. 조용히 추측하는 것보다 안전하다.
    if proposal.needs_clarification:
        return ValidationOutcome(question=proposal.question or "한 가지만 더 알려주세요.")

    if not proposal.items:
        return ValidationOutcome(rejection="proposal has no items")

    validated: list[ValidatedItem] = []
    for item in proposal.items:
        outcome = _validate_item(item, today=today, require_amount=require_amount)
        if not outcome.ok:
            return outcome
        validated.extend(outcome.items)
    return ValidationOutcome(items=validated)


def _validate_item(
    item: ProposedItem, *, today: date, require_amount: bool
) -> ValidationOutcome:
    name = item.raw_name.strip()
    if not name:
        return ValidationOutcome(rejection="item has empty name")

    amount, unit, qualitative, certainty, problem = _validate_quantity(item, require_amount)
    if problem is not None:
        return problem

    resolved_dates: list[ValidatedDate] = []
    for proposed in item.dates:
        if proposed.kind is None:
            # 종류를 말하지 않았다. 소비기한으로 승격하지 않고 되묻는다.
            return ValidationOutcome(
                question=f"{name}의 그 날짜가 소비기한인가요, 유통기한인가요?"
            )
        resolved = date_utils.resolve(
            proposed.year, proposed.month, proposed.day, today=today, raw_text=proposed.raw_text
        )
        if resolved.needs_clarification:
            return ValidationOutcome(question=resolved.question)
        resolved_dates.append(
            ValidatedDate(kind=proposed.kind, value=resolved.value, raw_text=proposed.raw_text)
        )

    return ValidationOutcome(
        items=[
            ValidatedItem(
                raw_name=name,
                amount=amount,
                unit=unit,
                qualitative_amount=qualitative,
                certainty=certainty,
                storage=item.storage or StorageLocation.UNKNOWN,
                is_remaining=item.is_remaining,
                dates=resolved_dates,
            )
        ]
    )


def _validate_quantity(
    item: ProposedItem, require_amount: bool
) -> tuple[
    Decimal | None, str | None, str | None, QuantityCertainty, ValidationOutcome | None
]:
    """수량과 단위를 검증한다. 숫자를 만들지 않는다."""
    name = item.raw_name.strip()

    if item.qualitative_amount and unit_utils.is_qualitative(item.qualitative_amount):
        # '조금' 을 임의의 g 으로 바꾸지 않는다. 정성 잔량으로 그대로 남긴다.
        return None, None, item.qualitative_amount, QuantityCertainty.QUALITATIVE, None

    if item.amount is None:
        if require_amount:
            return None, None, None, QuantityCertainty.UNKNOWN, ValidationOutcome(
                question=f"{with_topic(name)} 얼마나인가요?"
            )
        return None, None, None, QuantityCertainty.UNKNOWN, None

    try:
        amount = Decimal(str(item.amount))
    except (InvalidOperation, ValueError):
        return None, None, None, QuantityCertainty.UNKNOWN, ValidationOutcome(
            rejection=f"unparsable amount for {name}: {item.amount!r}"
        )
    if amount < 0:
        return None, None, None, QuantityCertainty.UNKNOWN, ValidationOutcome(
            rejection=f"negative amount for {name}: {amount}"
        )

    unit = unit_utils.normalize_unit(item.unit_text)
    if unit is None:
        if item.unit_text:
            # 모르는 단위다. 짐작해서 개로 바꾸면 잔량이 틀어진다.
            return None, None, None, QuantityCertainty.UNKNOWN, ValidationOutcome(
                question=f"{name} {item.unit_text}가 어떤 단위인가요?"
            )
        # 단위를 말하지 않았다. 셀 수 있는 것으로 보고 '개' 로 둔다.
        unit = "ea"

    return amount, unit, None, QuantityCertainty.EXACT, None
