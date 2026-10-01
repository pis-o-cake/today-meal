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


def test_unit_keeps_only_the_spoken_word():
    """모델이 단위 뒤에 혼잣말을 이어 적어도 발화 전체를 버리지 않는다."""
    rambling = "모 European, check Korean units -> '모' valid schema ok"
    assert item(unit_text=rambling).unit_text == "모"
    # 띄어 쓰지 않고 이어 적기도 한다. 실제로 받은 응답이다.
    assert item(unit_text="개Single-word unit, no particle").unit_text == "개"
    assert item(unit_text="ml (milliliter, metric)").unit_text == "ml"
    assert item(unit_text="-> not a unit at all").unit_text is None
    # 짧은 값은 그대로 둔다. 띄어 쓴 단위를 자르면 아는 단위를 모르게 된다.
    assert item(unit_text=" 큰 술 ").unit_text == "큰 술"
    assert item(unit_text="").unit_text is None
    assert item(unit_text=None).unit_text is None


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


def test_date_without_kind_is_sell_by_without_asking():
    """제품 용어는 유통기한 하나다. 종류를 말하지 않은 기한은 되묻지 않고 유통기한으로 둔다."""
    result = validate(
        proposal(items=[item(amount=2, unit_text="모", raw_name="두부",
                             dates=[ProposedDate(month=10, day=3, raw_text="10월 3일")])]),
        today=TODAY,
        require_amount=True,
    )
    assert result.question is None
    assert result.items[0].dates[0].kind is DateKind.SELL_BY


def test_date_is_read_from_what_was_said():
    """모델이 말한 그대로만 옮기고 숫자 칸을 비운 응답을 실제로 받았다."""
    result = validate(
        proposal(
            items=[
                item(
                    raw_name="두부",
                    amount=2,
                    unit_text="모",
                    dates=[ProposedDate(kind=DateKind.SELL_BY, raw_text="10월 1일")],
                )
            ]
        ),
        today=TODAY,
        require_amount=True,
    )
    assert result.question is None
    assert result.items[0].dates[0].value == date(2026, 10, 1)


def test_same_kind_of_date_is_kept_once():
    """모델이 같은 기한을 두 번 적은 응답을 받았다. 저장 제약에 걸려 서버가 죽었다."""
    said = ProposedDate(kind=DateKind.SELL_BY, raw_text="10월 15일")
    result = validate(
        proposal(items=[item(amount=10, unit_text="개", dates=[said, said])]),
        today=TODAY,
        require_amount=True,
    )
    assert result.question is None
    assert [d.value for d in result.items[0].dates] == [date(2026, 10, 15)]


@pytest.mark.parametrize(
    ("said", "expected"),
    [
        ("일주일 남았어", date(2026, 10, 5)),
        ("내일까지", date(2026, 9, 29)),
        ("모레", date(2026, 9, 30)),
        ("3일 남았어", date(2026, 10, 1)),
        ("사흘 뒤", date(2026, 10, 1)),
        ("2주 뒤", date(2026, 10, 12)),
    ],
)
def test_remaining_time_is_a_spoken_date(said, expected):
    """남은 기간으로 말한 기한은 사용자가 말한 날짜다. 되묻지 않는다."""
    result = validate(
        proposal(
            items=[
                item(
                    amount=10,
                    unit_text="개",
                    dates=[ProposedDate(kind=DateKind.SELL_BY, raw_text=said)],
                )
            ]
        ),
        today=TODAY,
        require_amount=True,
    )
    assert result.question is None
    assert result.items[0].dates[0].value == expected


def test_missing_amount_is_read_from_the_utterance():
    """모델이 기한만 옮기고 수량을 비운 응답을 실제로 받았다."""
    result = validate(
        proposal(
            items=[item(dates=[ProposedDate(kind=DateKind.SELL_BY, raw_text="10월 15일")])]
        ),
        today=TODAY,
        require_amount=True,
        utterance="계란 열 개 넣었어 유통기한은 10월 15일까지",
    )
    assert result.question is None
    assert result.items[0].amount == Decimal("10")
    assert result.items[0].unit == "ea"


def test_amount_is_still_asked_when_it_was_not_said():
    result = validate(
        proposal(items=[item()]),
        today=TODAY,
        require_amount=True,
        utterance="계란 넣었어",
    )
    assert result.question is not None


def test_day_without_month_is_still_asked():
    """원문을 읽더라도 말하지 않은 월을 채우지 않는다."""
    result = validate(
        proposal(
            items=[
                item(
                    amount=2,
                    unit_text="개",
                    dates=[ProposedDate(kind=DateKind.USE_BY, raw_text="3일")],
                )
            ]
        ),
        today=TODAY,
        require_amount=True,
    )
    assert result.question is not None
    assert "몇 월" in result.question


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

    거절하지는 않는다 — 단위를 맞게 읽고도 발화 전체가 실패한다. 말한 단위만 남긴다.
    """
    rambling = "모 single-form stripped of particle: wait, need raw string not comment"
    kept = item(amount=2, unit_text=rambling, raw_name="두부")
    assert kept.unit_text == "모"

    result = validate(proposal(items=[kept]), today=TODAY, require_amount=True)
    assert result.question is None
    assert result.items[0].unit == "mo"


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
