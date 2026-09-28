"""제안 검증. DB 없이 돈다.

이 파일이 지키는 것은 **숫자를 만들지 않는다**는 규칙이다.
"""

from datetime import date
from decimal import Decimal

import pytest

from app.core.enums import CommandIntent, DateKind, QuantityCertainty, StorageLocation
from app.core.llm.schemas import CommandProposal, ProposedDate, ProposedItem
from app.domain.command.validation import validate

TODAY = date(2026, 9, 28)


def proposal(**kwargs) -> CommandProposal:
    kwargs.setdefault("intent", CommandIntent.REGISTER)
    return CommandProposal(**kwargs)


def item(**kwargs) -> ProposedItem:
    kwargs.setdefault("raw_name", "계란")
    return ProposedItem(**kwargs)


def test_model_self_reported_ambiguity_is_honoured():
    """모델이 모호하다고 신고하면 그대로 되묻는다."""
    result = validate(
        proposal(needs_clarification=True, question="반이 뭐의 반인가요?"),
        today=TODAY,
        require_amount=True,
    )
    assert result.question == "반이 뭐의 반인가요?"
    assert result.items == []


def test_numeric_amount_with_korean_unit_is_normalized():
    result = validate(
        proposal(items=[item(amount=2, unit_text="모", raw_name="두부")]),
        today=TODAY,
        require_amount=True,
    )
    assert result.ok
    (validated,) = result.items
    assert validated.amount == Decimal("2")
    assert validated.unit == "mo"
    assert validated.certainty is QuantityCertainty.EXACT


def test_missing_unit_defaults_to_countable():
    result = validate(
        proposal(items=[item(amount=10)]), today=TODAY, require_amount=True
    )
    assert result.items[0].unit == "ea"


def test_unknown_unit_asks_instead_of_guessing():
    """모르는 단위를 개로 바꾸면 잔량이 틀어진다."""
    result = validate(
        proposal(items=[item(amount=1, unit_text="자루", raw_name="대파")]),
        today=TODAY,
        require_amount=True,
    )
    assert result.question is not None
    assert "자루" in result.question


def test_qualitative_amount_is_never_converted_to_number():
    result = validate(
        proposal(items=[item(qualitative_amount="조금", raw_name="대파")]),
        today=TODAY,
        require_amount=True,
    )
    assert result.ok
    validated = result.items[0]
    assert validated.amount is None
    assert validated.qualitative_amount == "조금"
    assert validated.certainty is QuantityCertainty.QUALITATIVE


def test_missing_amount_asks_when_required():
    result = validate(proposal(items=[item()]), today=TODAY, require_amount=True)
    assert result.question is not None


def test_negative_amount_is_rejected():
    # Pydantic 이 먼저 막는다. 모델이 음수를 내면 스키마에서 걸린다.
    with pytest.raises(ValueError, match="greater_than_equal|ge"):
        item(amount=-1)


def test_date_without_kind_asks_which_kind():
    """종류를 모르는 날짜를 소비기한으로 승격하지 않는다."""
    result = validate(
        proposal(items=[item(amount=2, unit_text="모", raw_name="두부",
                             dates=[ProposedDate(month=10, day=3, raw_text="10월 3일")])]),
        today=TODAY,
        require_amount=True,
    )
    assert result.question is not None
    assert "소비기한" in result.question


def test_date_with_kind_and_month_resolves():
    result = validate(
        proposal(items=[item(amount=2, unit_text="모", raw_name="두부",
                             dates=[ProposedDate(kind=DateKind.USE_BY, month=10, day=3)])]),
        today=TODAY,
        require_amount=True,
    )
    assert result.ok
    (validated_date,) = result.items[0].dates
    assert validated_date.value == date(2026, 10, 3)
    assert validated_date.kind is DateKind.USE_BY


def test_day_only_date_asks_for_month():
    """'3일까지야' 를 이번 달로 확정하지 않는다."""
    result = validate(
        proposal(items=[item(amount=2, unit_text="모", raw_name="두부",
                             dates=[ProposedDate(kind=DateKind.USE_BY, day=3, raw_text="3일")])]),
        today=TODAY,
        require_amount=True,
    )
    assert result.question is not None
    assert "몇 월" in result.question


def test_far_past_date_asks_for_year():
    """한참 지난 날짜는 연도를 빠뜨린 발화다. 임의로 올해로 확정하지 않는다."""
    result = validate(
        proposal(items=[item(amount=2, unit_text="모", raw_name="두부",
                             dates=[ProposedDate(kind=DateKind.USE_BY, month=1, day=5)])]),
        today=TODAY,
        require_amount=True,
    )
    assert result.question is not None
    assert "몇 년" in result.question


def test_storage_defaults_to_unknown_not_fridge():
    """말하지 않은 보관 위치를 냉장으로 단정하지 않는다."""
    result = validate(
        proposal(items=[item(amount=10)]), today=TODAY, require_amount=True
    )
    assert result.items[0].storage is StorageLocation.UNKNOWN


def test_empty_proposal_is_rejected_not_silently_accepted():
    result = validate(proposal(items=[]), today=TODAY, require_amount=True)
    assert result.rejection is not None
    assert result.question is None


def test_one_bad_item_blocks_the_whole_utterance():
    """절반만 반영하면 사용자가 무엇이 남았는지 알 수 없다."""
    result = validate(
        proposal(items=[item(amount=2, unit_text="모", raw_name="두부"),
                        item(amount=1, unit_text="자루", raw_name="대파")]),
        today=TODAY,
        require_amount=True,
    )
    assert result.question is not None
    assert result.items == []


def test_model_scratchpad_in_unit_is_not_echoed_to_user():
    """모델이 단위 칸에 사고 과정을 흘려 넣은 응답을 실제로 받았다.

    그 문자열이 되묻는 질문에 그대로 나갔다. 모델 출력을 사용자 문구에 그대로 넣지 않는다.
    """
    rambling = "모 single-form stripped of particle: wait, need raw string not comment"
    with pytest.raises(ValueError, match="at most 10 characters|max_length"):
        item(amount=2, unit_text=rambling)


def test_long_unit_text_falls_back_to_generic_question():
    """스키마를 통과했더라도 읽기 어려운 단위는 언급하지 않는다."""
    result = validate(
        proposal(items=[item(amount=2, unit_text="ABCDEFGHIJ", raw_name="두부")]),
        today=TODAY,
        require_amount=True,
    )
    assert result.question is not None
    assert "ABCDEFGHIJ" in result.question or "다시 말해주세요" in result.question


def test_model_question_is_sanitized():
    """모델이 준 질문도 정제한다. 줄바꿈과 과도한 길이를 걷어낸다."""
    result = validate(
        proposal(needs_clarification=True, question="반이\n  뭐의   반인가요?"),
        today=TODAY,
        require_amount=True,
    )
    assert result.question == "반이 뭐의 반인가요?"


def test_unit_with_particle_is_normalized_not_asked():
    """'모랑' 은 조사가 붙은 것이다. 되묻지 않고 처리한다."""
    result = validate(
        proposal(items=[item(amount=2, unit_text="모랑", raw_name="두부")]),
        today=TODAY,
        require_amount=True,
    )
    assert result.ok, result.question
    assert result.items[0].unit == "mo"
