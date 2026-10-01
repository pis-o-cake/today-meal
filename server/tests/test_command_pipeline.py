"""명령 파이프라인 통합 테스트.

**실제 PostgreSQL 이 필요하다.** 모델은 가짜를 쓴다 — 검증과 실행이 이 파일의 대상이고,
그것은 입력이 정해지면 출력도 정해져야 한다.

핵심 시나리오를 HTTP 로 실행한다. 재고 무결성이 전부 여기 걸려 있다.
"""

from __future__ import annotations

from decimal import Decimal
from typing import Annotated
from uuid import uuid4

import pytest
from fastapi import Header
from sqlalchemy import create_engine, text

from app.core.config import get_settings
from app.core.identity import Caller, get_caller


def _database_ready() -> bool:
    try:
        engine = create_engine(get_settings().alembic_url, pool_pre_ping=True)
        with engine.connect() as connection:
            return bool(
                connection.execute(
                    text(
                        "select count(*) from information_schema.tables "
                        "where table_name='command'"
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
    """가짜 게이트웨이를 쓰는 테스트 클라이언트.

    **테스트가 모델 토큰을 쓰면 안 된다.** 두 곳을 모두 막아야 한다 — 라우트는 import
    시점에 원본 함수를 바인딩하므로 `dependency_overrides` 의 키가 원본이어야 하고,
    `/health` 의 `is_fake()` 는 모듈 전역을 부르므로 그쪽도 갈아야 한다.

    호출자도 갈아 끼운다. 운영에서는 `X-Household-Id` 를 **읽지 않는다** — 그 헤더로
    남의 가구를 지정할 수 있었던 것이 이번에 막은 구멍이다. 이 파일이 확인하는 것은
    재고 무결성이지 신원 확인이 아니므로, 가구만 헤더로 고르게 하고 로그인은 건너뛴다.
    신원 확인 자체는 `tests/test_auth.py` 가 본다.

    WARNING: `Annotated`·`Header` 를 **모듈 전역에서** 임포트해야 한다. 이 파일은
    `from __future__ import annotations` 를 쓰므로 주석이 문자열이고, FastAPI 가 이름을
    모듈 전역에서 찾는다. 함수 안에서 임포트하면 해석하지 못해 헤더가 조용히 None 이 된다.
    """
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
        test_client.fake = fake
        yield test_client
    original.cache_clear()


@pytest.fixture
def household(client):
    """테스트마다 새 가구를 만들어 격리한다."""
    household_id = _create_household()
    yield household_id
    _drop_household(household_id)


@pytest.fixture
def neighbor(client):
    """다른 가구. 한 가구의 일괄 처리가 남의 재고를 건드리지 않는지 본다."""
    household_id = _create_household()
    yield household_id
    _drop_household(household_id)


def _create_household() -> int:
    engine = create_engine(get_settings().alembic_url)
    with engine.begin() as connection:
        return connection.execute(
            text(
                "insert into household (name, timezone, default_servings, tools, "
                "expiry_alert_days) values ('테스트', 'Asia/Seoul', 2, '{}', '{3,1,0}') "
                "returning household_id"
            )
        ).scalar_one()


def _drop_household(household_id: int) -> None:
    # 원장이 명령과 묶음을 참조하므로 의존 순서대로 지운다. 운영에서는 명령을 삭제하지
    # 않으므로 이 순서가 필요한 곳은 테스트 정리뿐이다.
    engine = create_engine(get_settings().alembic_url)
    with engine.begin() as connection:
        for statement in (
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


def say(client, household_id: int, utterance: str, follows: str | None = None) -> dict:
    """한 발화를 보낸다. 명령 ID 는 호출마다 새로 만든다."""
    body = {"command_id": str(uuid4()), "utterance": utterance}
    if follows is not None:
        body["follows"] = follows
    response = client.post(
        "/api/command/interpret",
        json=body,
        headers={"X-Household-Id": str(household_id)},
    )
    assert response.status_code == 200, response.text
    return response.json()


def quantity_of(household_id: int, name: str) -> Decimal | None:
    engine = create_engine(get_settings().alembic_url)
    with engine.connect() as connection:
        return connection.execute(
            text(
                "select quantity from ingredient_batch where household_id = :h "
                "and raw_name = :n and deleted_at is null order by batch_id desc limit 1"
            ),
            {"h": household_id, "n": name},
        ).scalar_one_or_none()


def actions_of(household_id: int) -> list[str]:
    engine = create_engine(get_settings().alembic_url)
    with engine.connect() as connection:
        return list(
            connection.execute(
                text(
                    "select e.action from change_event e join command c "
                    "on c.command_id = e.command_id where c.household_id = :h "
                    "order by e.change_event_id"
                ),
                {"h": household_id},
            ).scalars()
        )


def test_register_creates_batch_with_quantity(client, household):
    result = say(client, household, "계란 열 개 넣었어")
    assert result["status"] == "applied"
    assert result["intent"] == "register"
    assert quantity_of(household, "계란") == Decimal("10.000")
    # 단위 기호를 그대로 읽으면 "계란 10ea" 가 된다.
    assert "10개" in result["spoken"]
    assert "ea" not in result["spoken"]
    # 말하지 않은 기한을 채우지 않고, 입력되지 않았다고 알린다.
    assert "기한은 입력하지 않았어요" in result["spoken"]
    assert result["screen"]["changes"][0]["date_value"] is None


def test_register_tells_the_expiry_that_was_said(client, household):
    result = say(client, household, "계란 열 개 넣었어 유통기한은 10월 15일까지야")
    assert result["status"] == "applied"
    # 음성에서는 연도까지 읽는다.
    assert "유통기한 2026년 10월 15일까지" in result["spoken"]
    assert "입력하지 않았어요" not in result["spoken"]
    change = result["screen"]["changes"][0]
    assert (change["date_kind"], change["date_value"]) == ("sell_by", "2026-10-15")


def test_using_does_not_mention_a_missing_expiry(client, household):
    say(client, household, "두부 두 모 넣었어")
    result = say(client, household, "두부 한 모 썼어")
    assert result["status"] == "applied"
    # 쓴 것을 알릴 때는 기한을 말하지 않는다. 넣을 때 말하는 값이다.
    assert "입력하지 않았어요" not in result["spoken"]


def test_consume_deducts(client, household):
    say(client, household, "계란 열 개 넣었어")
    result = say(client, household, "계란 두 개 썼어")
    assert result["intent"] == "consume"
    assert quantity_of(household, "계란") == Decimal("8.000")


def test_remaining_is_absolute_adjustment_not_deduction(client, household):
    """'네 개 남았어' 는 차감이 아니라 보정이다."""
    say(client, household, "계란 열 개 넣었어")
    result = say(client, household, "계란 네 개 남았어")
    assert result["intent"] == "adjust"
    assert quantity_of(household, "계란") == Decimal("4.000")
    assert "adjust" in actions_of(household)


def test_consuming_more_than_stock_asks_instead_of_going_negative(client, household):
    say(client, household, "계란 두 개 넣었어")
    result = say(client, household, "계란 다섯 개 썼어")
    assert result["status"] == "clarifying"
    assert result["clarification_question"] is not None
    # 아무것도 바꾸지 않았다.
    assert quantity_of(household, "계란") == Decimal("2.000")


def test_unknown_ingredient_asks_instead_of_creating_negative_stock(client, household):
    result = say(client, household, "버터 두 개 썼어")
    assert result["status"] == "clarifying"
    assert "버터" in result["clarification_question"]


@pytest.fixture
def heard(monkeypatch) -> list[str]:
    """모델에 넘어간 발화. 앞 발화에 이었는지를 여기서 본다."""
    from app.core.llm.fake import FakeLlmGateway

    seen: list[str] = []
    original = FakeLlmGateway.interpret

    async def spy(self, utterance, context):
        seen.append(utterance)
        return await original(self, utterance, context)

    monkeypatch.setattr(FakeLlmGateway, "interpret", spy)
    return seen


def test_answer_in_same_conversation_continues_question(client, household, heard):
    """되물은 대화 안의 짧은 답은 앞 발화에 이어 해석한다."""
    say(client, household, "계란 두 개 넣었어")
    asked = say(client, household, "계란 다섯 개 썼어")
    assert asked["status"] == "clarifying"
    say(client, household, "두 개", follows=asked["command_id"])
    assert heard[-1] == "계란 다섯 개 썼어 두 개"


def test_new_conversation_does_not_inherit_unanswered_utterance(client, household, heard):
    """대화를 닫고 새로 부르면 지난 발화가 이번 발화에 붙지 않는다."""
    say(client, household, "계란 두 개 넣었어")
    asked = say(client, household, "계란 다섯 개 썼어")
    assert asked["status"] == "clarifying"
    say(client, household, "두 개")
    assert heard[-1] == "두 개"


def test_idempotent_replay_does_not_apply_twice(client, household):
    """같은 명령 ID 재요청이 재고를 두 번 바꾸지 않는다."""
    say(client, household, "계란 열 개 넣었어")
    command_id = str(uuid4())
    body = {"command_id": command_id, "utterance": "계란 두 개 썼어"}
    headers = {"X-Household-Id": str(household)}

    first = client.post("/api/command/interpret", json=body, headers=headers).json()
    second = client.post("/api/command/interpret", json=body, headers=headers).json()

    assert first["command_id"] == second["command_id"]
    assert quantity_of(household, "계란") == Decimal("8.000")


def test_undo_restores_previous_quantity(client, household):
    say(client, household, "계란 열 개 넣었어")
    consumed = say(client, household, "계란 두 개 썼어")
    assert quantity_of(household, "계란") == Decimal("8.000")

    response = client.post(
        f"/api/command/{consumed['undo_token']}/undo",
        headers={"X-Household-Id": str(household)},
    )
    assert response.status_code == 200, response.text
    assert quantity_of(household, "계란") == Decimal("10.000")
    assert "revert" in actions_of(household)


def test_future_plan_does_not_change_stock(client, household):
    """'내일 살 거야' 를 현재 재고로 반영하지 않는다."""
    result = say(client, household, "내일 양파 세 개 살 거야")
    assert result["intent"] == "plan_future"
    assert quantity_of(household, "양파") is None


def test_core_scenario(client, household):
    """기능 범위 문서의 핵심 통합 시나리오.

    `계란 10개 등록 → 2개 사용(8) → 3개로 정정(7) → 정정 취소(8) → 4개 남음으로 보정(4)`
    """
    say(client, household, "계란 열 개 넣었어")
    assert quantity_of(household, "계란") == Decimal("10.000")

    say(client, household, "계란 두 개 썼어")
    assert quantity_of(household, "계란") == Decimal("8.000")

    corrected = say(client, household, "아니 계란 세 개 썼어")
    assert corrected["intent"] == "correct"
    # 3개를 추가로 차감하지 않는다. 되돌린 뒤 다시 적용했다.
    assert quantity_of(household, "계란") == Decimal("7.000")

    response = client.post(
        f"/api/command/{corrected['undo_token']}/undo",
        headers={"X-Household-Id": str(household)},
    )
    assert response.status_code == 200, response.text
    assert quantity_of(household, "계란") == Decimal("8.000")

    say(client, household, "계란 네 개 남았어")
    assert quantity_of(household, "계란") == Decimal("4.000")

    # 이력이 사실을 구분해 남았는지 확인한다.
    actions = actions_of(household)
    assert actions[0] == "stock_in"
    assert "adjust" in actions
    assert actions.count("revert") >= 2


def test_voice_cancel_without_items_reverts_last_change(client, household, monkeypatch):
    """실제 모델은 "방금 거 취소" 를 항목 없는 취소로 준다. 그래도 직전 변경을 되돌린다."""
    from app.core.enums import CommandIntent
    from app.core.llm.fake import FakeLlmGateway

    original = FakeLlmGateway.interpret

    async def like_gemini(self, utterance, context):
        result = await original(self, utterance, context)
        if "취소" not in utterance:
            return result
        proposal = result.proposal.model_copy(
            update={"intent": CommandIntent.CANCEL, "items": []}
        )
        return result.model_copy(update={"proposal": proposal})

    monkeypatch.setattr(FakeLlmGateway, "interpret", like_gemini)
    say(client, household, "계란 열 개 넣었어")
    say(client, household, "계란 두 개 썼어")
    assert quantity_of(household, "계란") == Decimal("8.000")

    result = say(client, household, "방금 거 취소")
    assert result["status"] == "applied"
    assert quantity_of(household, "계란") == Decimal("10.000")


@pytest.fixture
def dated_without_amount(monkeypatch):
    """실제 모델처럼 "두부 유통기한은 10월 5일까지야" 를 수량 없는 등록으로 준다."""
    from app.core.enums import CommandIntent
    from app.core.llm.fake import FakeLlmGateway
    from app.core.llm.schemas import ProposedDate, ProposedItem

    original = FakeLlmGateway.interpret

    async def like_gemini(self, utterance, context):
        result = await original(self, utterance, context)
        if "유통기한은" not in utterance:
            return result
        proposal = result.proposal.model_copy(
            update={
                "intent": CommandIntent.REGISTER,
                "items": [
                    ProposedItem(
                        raw_name="두부",
                        dates=[ProposedDate(raw_text="10월 5일", month=10, day=5)],
                    )
                ],
                "needs_clarification": False,
                "question": None,
            }
        )
        return result.model_copy(update={"proposal": proposal})

    monkeypatch.setattr(FakeLlmGateway, "interpret", like_gemini)


def _dates_of(household_id: int, name: str) -> list[tuple[int, str, str | None]]:
    engine = create_engine(get_settings().alembic_url)
    with engine.connect() as connection:
        rows = connection.execute(
            text(
                "select b.batch_id, d.kind, d.date_value::text from ingredient_batch b "
                "left join batch_date d on d.batch_id = b.batch_id "
                "where b.household_id = :h and b.raw_name = :n and b.deleted_at is null "
                "order by b.batch_id, d.kind"
            ),
            {"h": household_id, "n": name},
        )
        return [tuple(row) for row in rows]


def test_expiry_for_stocked_item_sets_date_instead_of_asking(
    client, household, dated_without_amount
):
    """있는 재료의 기한만 말하면 수량을 묻지 않고 그 묶음의 기한을 고친다."""
    say(client, household, "두부 두 모 넣었어")

    result = say(client, household, "두부 유통기한은 10월 5일까지야")
    assert result["status"] == "applied", result
    assert result["clarification_question"] is None
    assert "유통기한 2026년 10월 5일까지" in result["spoken"]
    assert quantity_of(household, "두부") == Decimal("2.000")
    rows = _dates_of(household, "두부")
    assert len({batch_id for batch_id, _, _ in rows}) == 1, "새 묶음을 만들지 않는다"
    assert [(kind, value) for _, kind, value in rows] == [("sell_by", "2026-10-05")]

    undo = client.post(
        f"/api/command/{result['undo_token']}/undo",
        headers={"X-Household-Id": str(household)},
    )
    assert undo.status_code == 200, undo.text
    assert [value for _, _, value in _dates_of(household, "두부")] == [None]
    assert quantity_of(household, "두부") == Decimal("2.000")


def test_expiry_replaces_existing_date_of_stocked_item(
    client, household, dated_without_amount
):
    """이미 기한이 있으면 같은 종류의 기한을 새 날짜로 바꾼다."""
    say(client, household, "두부 두 모 넣었어 유통기한은 10월 3일까지야")

    result = say(client, household, "두부 유통기한은 10월 5일까지야")
    assert result["status"] == "applied", result
    rows = _dates_of(household, "두부")
    assert [(kind, value) for _, kind, value in rows] == [("sell_by", "2026-10-05")]


def test_expiry_for_unstocked_item_still_asks_quantity(
    client, household, dated_without_amount
):
    """없는 재료의 기한만 말하면 지금처럼 수량을 되묻는다."""
    result = say(client, household, "두부 유통기한은 10월 5일까지야")
    assert result["status"] == "clarifying"
    assert "얼마나" in result["clarification_question"]
    assert _dates_of(household, "두부") == []


def test_history_shows_undo_tap_as_localized_label(client, household):
    """되돌리기 버튼이 만든 기록에 "undo" 가 말한 것처럼 보이지 않는다."""
    from app.core.locale import translate

    consumed = say(client, household, "계란 열 개 넣었어")
    undo = client.post(
        f"/api/command/{consumed['undo_token']}/undo",
        headers={"X-Household-Id": str(household)},
    )
    assert undo.status_code == 200, undo.text

    rows = client.get(
        "/api/command/history", headers={"X-Household-Id": str(household)}
    ).json()
    reverted = [row for row in rows if row["action"] == "revert"]
    assert reverted
    assert all(row["utterance"] == translate("history.undo") for row in reverted)
    assert all(row["utterance"] != "undo" for row in rows)


def test_ledger_total_matches_current_quantity(client, household):
    """잔량 현재값과 이벤트 누적이 어긋나면 버그다."""
    say(client, household, "계란 열 개 넣었어")
    say(client, household, "계란 두 개 썼어")

    engine = create_engine(get_settings().alembic_url)
    with engine.connect() as connection:
        total = connection.execute(
            text(
                "select coalesce(sum(e.quantity_delta), 0) from change_event e "
                "join ingredient_batch b on b.batch_id = e.batch_id "
                "where b.household_id = :h"
            ),
            {"h": household},
        ).scalar_one()
    assert total == quantity_of(household, "계란")


def test_no_tokens_were_spent(client, household):
    """테스트가 실제 모델을 부르지 않았는지 확인한다."""
    say(client, household, "계란 열 개 넣었어")
    body = client.get("/health").json()
    assert body["llm_usage"]["calls"] == 0
    assert body["llm_fake"] is True


def storage_of(household_id: int, name: str) -> str | None:
    engine = create_engine(get_settings().alembic_url)
    with engine.connect() as connection:
        return connection.execute(
            text(
                "select storage_location from ingredient_batch where household_id = :h "
                "and raw_name = :n and deleted_at is null order by batch_id desc limit 1"
            ),
            {"h": household_id, "n": name},
        ).scalar_one_or_none()


def state_events_of(household_id: int) -> list[str]:
    engine = create_engine(get_settings().alembic_url)
    with engine.connect() as connection:
        return list(
            connection.execute(
                text(
                    "select e.kind from batch_state_event e join ingredient_batch b "
                    "on b.batch_id = e.batch_id where b.household_id = :h "
                    "order by e.state_event_id"
                ),
                {"h": household_id},
            ).scalars()
        )


def test_opening_does_not_change_quantity(client, household):
    """개봉은 먹은 것이 아니다. 차감하지 않고 상태만 남긴다."""
    say(client, household, "우유 한 개 넣었어")
    before = quantity_of(household, "우유")

    result = say(client, household, "우유 오늘 열었어")
    assert result["intent"] == "open"
    assert result["status"] == "applied"
    assert quantity_of(household, "우유") == before
    assert "opened" in state_events_of(household)
    # 수량 원장에는 아무것도 남지 않는다.
    assert actions_of(household) == ["stock_in"]


def test_moving_changes_location_without_extending_dates(client, household):
    """냉동 전환을 이유로 기한을 연장하지 않는다."""
    say(client, household, "돼지고기 한 개 넣었어")
    engine = create_engine(get_settings().alembic_url)
    with engine.begin() as connection:
        connection.execute(
            text(
                "insert into batch_date (batch_id, kind, date_value, is_confirmed, source) "
                "select batch_id, 'use_by', date '2026-10-01', true, 'voice' "
                "from ingredient_batch where household_id = :h"
            ),
            {"h": household},
        )

    result = say(client, household, "돼지고기 냉동실로 옮겼어")
    assert result["intent"] == "move"
    assert storage_of(household, "돼지고기") == "freezer"
    assert "moved" in state_events_of(household)

    with engine.connect() as connection:
        remaining = connection.execute(
            text(
                "select date_value from batch_date d join ingredient_batch b "
                "on b.batch_id = d.batch_id where b.household_id = :h"
            ),
            {"h": household},
        ).scalar_one()
    assert str(remaining) == "2026-10-01"


def test_partial_move_asks_instead_of_splitting(client, household):
    """'반은 냉동실로' 는 묶음 분할이 필요하다. 이 슬라이스 범위가 아니므로 되묻는다."""
    say(client, household, "돼지고기 두 개 넣었어")
    result = say(client, household, "돼지고기 한 개 냉동실로 옮겼어")
    assert result["status"] == "clarifying"
    assert storage_of(household, "돼지고기") == "unknown"


def test_query_answers_with_actual_quantity(client, household):
    """조회는 실제 잔량으로 답하고 재고를 바꾸지 않는다."""
    say(client, household, "계란 열 개 넣었어")
    result = say(client, household, "계란 몇 개 있어?")
    assert result["intent"] == "query"
    assert result["status"] == "applied"
    assert "10" in result["spoken"]
    # 조회에는 되돌릴 것이 없다.
    assert result["undo_token"] is None
    assert quantity_of(household, "계란") == Decimal("10.000")


def test_query_for_missing_ingredient_says_so(client, household):
    result = say(client, household, "버터 몇 개 있어?")
    assert result["intent"] == "query"
    assert "버터" in result["spoken"]


def test_history_mixes_quantity_and_state_changes(client, household):
    say(client, household, "우유 한 개 넣었어")
    say(client, household, "우유 오늘 열었어")

    response = client.get(
        "/api/command/history", headers={"X-Household-Id": str(household)}
    )
    assert response.status_code == 200, response.text
    rows = response.json()
    kinds = {row["kind"] for row in rows}
    assert kinds == {"quantity", "state"}

    state_row = next(row for row in rows if row["kind"] == "state")
    # 상태 변경은 수량을 바꾸지 않는다는 사실이 화면에 드러나야 한다.
    assert state_row["quantity_before"] is None
    assert state_row["quantity_after"] is None
    assert state_row["action"] in {"opened", "stocked_in"}


def test_history_marks_estimated_values(client, household):
    say(client, household, "대파 한 단 넣었어")
    say(client, household, "대파 조금 썼어")

    rows = client.get(
        "/api/command/history", headers={"X-Household-Id": str(household)}
    ).json()
    quantity_rows = [row for row in rows if row["kind"] == "quantity"]
    assert any(row["is_estimated"] for row in quantity_rows)


def test_priority_excludes_expired_from_cookable(client, household):
    """기한이 지난 재료는 목록에 남기되 요리 후보에서 뺀다."""
    say(client, household, "두부 두 모 넣었어")
    engine = create_engine(get_settings().alembic_url)
    with engine.begin() as connection:
        connection.execute(
            text(
                "insert into batch_date (batch_id, kind, date_value, is_confirmed, source) "
                "select batch_id, 'use_by', "
                "(now() at time zone 'Asia/Seoul')::date - 2, true, 'voice' "
                "from ingredient_batch where household_id = :h"
            ),
            {"h": household},
        )

    rows = client.get(
        "/api/inventory/batches/expiring", headers={"X-Household-Id": str(household)}
    ).json()
    expired = next(row for row in rows if row["reason"] == "expired")
    assert expired["is_cookable"] is False
    assert expired["days_left"] < 0
    # 판정에 쓴 기한 종류를 밝혀야 한다.
    assert expired["expiry_kind"] == "use_by"


def test_priority_flags_expiring_soon_as_cookable(client, household):
    say(client, household, "두부 두 모 넣었어")
    engine = create_engine(get_settings().alembic_url)
    with engine.begin() as connection:
        connection.execute(
            text(
                "insert into batch_date (batch_id, kind, date_value, is_confirmed, source) "
                "select batch_id, 'use_by', "
                "(now() at time zone 'Asia/Seoul')::date + 1, true, 'voice' "
                "from ingredient_batch where household_id = :h"
            ),
            {"h": household},
        )
    rows = client.get(
        "/api/inventory/batches/expiring", headers={"X-Household-Id": str(household)}
    ).json()
    soon = next(row for row in rows if row["reason"] == "expiring")
    assert soon["is_cookable"] is True
    assert soon["days_left"] == 1


def test_manufactured_date_is_not_used_as_expiry(client, household):
    """제조일을 기한으로 쓰지 않는다."""
    say(client, household, "두부 두 모 넣었어")
    engine = create_engine(get_settings().alembic_url)
    with engine.begin() as connection:
        connection.execute(
            text(
                "insert into batch_date (batch_id, kind, date_value, is_confirmed, source) "
                "select batch_id, 'manufactured', "
                "(now() at time zone 'Asia/Seoul')::date - 30, true, 'voice' "
                "from ingredient_batch where household_id = :h"
            ),
            {"h": household},
        )
    rows = client.get(
        "/api/inventory/batches/expiring", headers={"X-Household-Id": str(household)}
    ).json()
    assert all(row["reason"] != "expired" for row in rows)


def test_essential_missing_ingredient_blocks_ready(client, household):
    """필수 재료가 없는 메뉴를 '지금 가능' 으로 표시하지 않는다. F-13 의 완료 기준."""
    say(client, household, "두부 두 모 넣었어")
    response = client.post(
        "/api/menu/suggestions?servings=2", headers={"X-Household-Id": str(household)}
    )
    assert response.status_code == 200, response.text
    menus = response.json()
    assert menus, "후보가 비어 있으면 판정할 것이 없다"

    for menu in menus:
        if menu["availability"] == "ready":
            assert menu["missing_ingredients"] == []
    # 가짜 게이트웨이는 없는 재료를 쓰는 후보를 하나 낸다. 그것이 ready 가 되면 안 된다.
    with_missing = [m for m in menus if m["missing_ingredients"]]
    assert with_missing, "없는 재료를 쓰는 후보가 있어야 판정을 시험할 수 있다"
    assert all(m["availability"] != "ready" for m in with_missing)


def test_suggestions_do_not_change_stock(client, household):
    say(client, household, "두부 두 모 넣었어")
    before = quantity_of(household, "두부")
    client.post("/api/menu/suggestions", headers={"X-Household-Id": str(household)})
    assert quantity_of(household, "두부") == before
    assert actions_of(household) == ["stock_in"]


def test_recipe_detail_scales_by_servings(client, household):
    say(client, household, "두부 두 모 넣었어")
    menus = client.post(
        "/api/menu/suggestions?servings=2", headers={"X-Household-Id": str(household)}
    ).json()
    recipe_id = menus[0]["recipe_id"]

    two = client.get(
        f"/api/menu/recipes/{recipe_id}?servings=2",
        headers={"X-Household-Id": str(household)},
    ).json()
    four = client.get(
        f"/api/menu/recipes/{recipe_id}?servings=4",
        headers={"X-Household-Id": str(household)},
    ).json()
    assert four["servings"] == 4
    first_two = Decimal(two["ingredients"][0]["required_amount"])
    first_four = Decimal(four["ingredients"][0]["required_amount"])
    assert first_four == first_two * 2
    assert four["steps"], "조리 순서가 있어야 한다"


def test_freshness_is_computed_by_server_not_app(client, household):
    """등급 계산은 서버가 하고 앱은 담기만 한다. 앱에 기준을 두면 화면마다 다른 말을 한다."""
    say(client, household, '두부 두 모 넣었어')
    engine = create_engine(get_settings().alembic_url)
    with engine.begin() as connection:
        connection.execute(
            text(
                'insert into batch_date (batch_id, kind, date_value, is_confirmed, source) '
                "select batch_id, 'use_by', "
                "(now() at time zone 'Asia/Seoul')::date + 1, true, 'voice' "
                'from ingredient_batch where household_id = :h'
            ),
            {'h': household},
        )
    rows = client.get(
        '/api/inventory/batches', headers={'X-Household-Id': str(household)}
    ).json()
    batch = rows[0]
    assert batch['freshness'] == 'urgent'
    assert batch['days_left'] == 1
    assert batch['expiry_kind'] == 'use_by'


def test_freshness_does_not_mix_in_unknown_quantity(client, household):
    """기한 축만 담는다. 잔량 미확인은 별도 신호다."""
    say(client, household, '대파 조금 넣었어')
    rows = client.get(
        '/api/inventory/batches', headers={'X-Household-Id': str(household)}
    ).json()
    batch = rows[0]
    # 기한 정보가 없으니 신선도는 unknown 이고, 잔량 미확인은 따로 표시된다.
    assert batch['freshness'] == 'unknown'
    assert batch['quantity_uncertain'] is True


def test_condition_is_urgent_when_something_expires_tomorrow(client, household):
    say(client, household, '두부 두 모 넣었어')
    engine = create_engine(get_settings().alembic_url)
    with engine.begin() as connection:
        connection.execute(
            text(
                'insert into batch_date (batch_id, kind, date_value, is_confirmed, source) '
                "select batch_id, 'use_by', "
                "(now() at time zone 'Asia/Seoul')::date + 1, true, 'voice' "
                'from ingredient_batch where household_id = :h'
            ),
            {'h': household},
        )
    body = client.get(
        '/api/inventory/condition', headers={'X-Household-Id': str(household)}
    ).json()
    assert body['condition'] == 'urgent'
    assert body['urgent_count'] == 1
    assert body['total_count'] == 1


def test_condition_is_relaxed_with_no_near_dates(client, household):
    say(client, household, '계란 열 개 넣었어')
    body = client.get(
        '/api/inventory/condition', headers={'X-Household-Id': str(household)}
    ).json()
    assert body['condition'] == 'relaxed'
    assert body['urgent_count'] == 0
    # 기한을 말하지 않았으니 잔량은 확실하지만 기한은 모른다. 둘을 섞지 않는다.
    assert body['unknown_quantity_count'] == 0


def _suggest(client, household_id: int) -> dict:
    response = client.post(
        '/api/menu/suggestions?servings=2',
        headers={'X-Household-Id': str(household_id)},
    )
    assert response.status_code == 200, response.text
    menus = response.json()
    assert menus, '후보가 있어야 조리 확인을 시험할 수 있다'
    return menus[0]


def test_cooked_deducts_recipe_ingredients(client, household):
    """해먹었어요가 레시피 재료를 재고에서 뺀다."""
    say(client, household, '두부 두 모 넣었어')
    menu = _suggest(client, household)

    response = client.post(
        f"/api/menu/suggestions/{menu['suggestion_id']}/cooked",
        headers={'X-Household-Id': str(household)},
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body['already_applied'] is False
    # 가짜 게이트웨이의 후보는 두부 1개를 쓴다.
    assert quantity_of(household, '두부') == Decimal('1.000')


def _quantities(household_id: int, name: str) -> list[Decimal]:
    """그 재료의 묶음별 잔량. 기한이 이른 것부터, 기한 없는 것은 뒤에 온다."""
    engine = create_engine(get_settings().alembic_url)
    with engine.connect() as connection:
        rows = connection.execute(
            text(
                "select b.quantity from ingredient_batch b "
                "left join batch_date d on d.batch_id = b.batch_id "
                "where b.household_id = :h and b.raw_name = :n "
                "order by d.date_value nulls last, b.created_at"
            ),
            {"h": household_id, "n": name},
        ).scalars()
        return list(rows)


def test_cooked_uses_the_batch_that_expires_first(client, household):
    """묶음이 여럿이면 되묻지 않고 기한이 이른 것부터 뺀다.

    되물었더니 조리를 마친 화면에는 답할 자리가 없어 아무것도 빠지지 않았다.
    """
    say(client, household, "두부 두 모 넣었어 소비기한은 10월 20일까지야")
    say(client, household, "두부 두 모 넣었어 소비기한은 10월 5일까지야")
    menu = _suggest(client, household)

    body = client.post(
        f"/api/menu/suggestions/{menu['suggestion_id']}/cooked",
        headers={"X-Household-Id": str(household)},
    ).json()

    assert body["clarification_question"] is None
    # 가짜 게이트웨이의 후보는 두부 1개를 쓴다. 10월 5일 것이 먼저 줄어든다.
    assert _quantities(household, "두부") == [Decimal("1.000"), Decimal("2.000")]
    # 무엇을 얼마나 뺐는지 돌려준다. 돌려주지 않으면 화면이 뺀 것을 보여줄 수 없다.
    assert body["changes"] == [
        {"name": "두부", "before": "2", "after": "1", "unit": "mo"}
    ]


def test_usage_spills_over_to_the_next_batch(client, household):
    """한 묶음으로 모자라면 다음으로 이른 묶음에서 마저 뺀다."""
    say(client, household, "계란 두 개 넣었어 유통기한은 10월 5일까지야")
    say(client, household, "계란 열 개 넣었어 유통기한은 10월 20일까지야")

    result = say(client, household, "계란 다섯 개 썼어")

    assert result["status"] == "applied"
    assert _quantities(household, "계란") == [Decimal("0.000"), Decimal("7.000")]


def test_spoken_usage_is_not_applied_when_stock_is_short(client, household):
    """말한 양이 재고보다 많으면 빼지 않는다. 사용자가 말한 숫자가 어긋난 것이다."""
    say(client, household, "계란 두 개 넣었어")
    say(client, household, "계란 세 개 넣었어")

    result = say(client, household, "계란 열 개 썼어")

    assert result["status"] == "clarifying"
    assert "5개밖에 없어요" in result["clarification_question"]
    assert _quantities(household, "계란") == [Decimal("2.000"), Decimal("3.000")]


def test_cooked_twice_does_not_deduct_twice(client, household):
    """버튼을 두 번 눌러도 재고가 두 번 줄지 않는다."""
    say(client, household, '두부 두 모 넣었어')
    menu = _suggest(client, household)
    url = f"/api/menu/suggestions/{menu['suggestion_id']}/cooked"
    headers = {'X-Household-Id': str(household)}

    first = client.post(url, headers=headers).json()
    second = client.post(url, headers=headers).json()

    assert first['already_applied'] is False
    assert second['already_applied'] is True
    assert quantity_of(household, '두부') == Decimal('1.000')


def test_cooked_marks_deduction_as_estimated(client, household):
    """레시피에서 온 차감은 사용자가 말한 숫자가 아니다. 추정값으로 남는다."""
    say(client, household, '두부 두 모 넣었어')
    menu = _suggest(client, household)
    client.post(
        f"/api/menu/suggestions/{menu['suggestion_id']}/cooked",
        headers={'X-Household-Id': str(household)},
    )

    rows = client.get(
        '/api/command/history', headers={'X-Household-Id': str(household)}
    ).json()
    consumed = [r for r in rows if r['action'] == 'consume']
    assert consumed, '차감 이력이 있어야 한다'
    assert all(r['is_estimated'] for r in consumed)


def test_cooked_skips_ingredients_without_amount(client, household):
    """분량을 모르는 재료는 숫자를 지어내지 않고 건너뛴다."""
    say(client, household, '두부 두 모 넣었어')
    menu = _suggest(client, household)
    engine = create_engine(get_settings().alembic_url)
    with engine.begin() as connection:
        connection.execute(
            text(
                'update recipe_ingredient set is_amount_unknown = true, quantity = null '
                'where recipe_id = :r'
            ),
            {'r': menu['recipe_id']},
        )

    body = client.post(
        f"/api/menu/suggestions/{menu['suggestion_id']}/cooked",
        headers={'X-Household-Id': str(household)},
    ).json()
    assert body['skipped_ingredients'], '건너뛴 재료를 알려줘야 한다'
    # 아무것도 차감하지 않았다.
    assert quantity_of(household, '두부') == Decimal('2.000')


def test_suggestion_of_other_household_is_rejected(client, household):
    say(client, household, '두부 두 모 넣었어')
    menu = _suggest(client, household)
    response = client.post(
        f"/api/menu/suggestions/{menu['suggestion_id']}/cooked",
        headers={'X-Household-Id': str(household + 99999)},
    )
    assert response.status_code == 404


def _batch_of(client, household_id: int, name: str) -> dict:
    """화면이 보는 묶음 하나. 재료 상세가 쓰는 경로와 같다."""
    rows = client.get(
        '/api/inventory/batches', headers={'X-Household-Id': str(household_id)}
    ).json()
    found = [row for row in rows if row['raw_name'] == name]
    assert found, f'{name} 묶음이 있어야 한다'
    return found[0]


def test_manual_edit_undo_restores_name_and_date(client, household):
    """화면에서 고친 **이름과 기한**도 되돌리기로 복원된다.

    수량만 되돌리면 사용자는 되돌렸다고 믿는데 이름은 바뀐 채로 남는다.
    """
    say(client, household, '두부 두 모 넣었어. 소비기한 10월 3일')
    batch = _batch_of(client, household, '두부')

    command_id = str(uuid4())
    response = client.patch(
        f"/api/inventory/batches/{batch['batch_id']}",
        json={
            'command_id': command_id,
            'name': '순두부',
            'date_kind': 'use_by',
            'date_value': '2026-11-30',
        },
        headers={'X-Household-Id': str(household)},
    )
    assert response.status_code == 200, response.text
    edited = response.json()
    assert edited['raw_name'] == '순두부'
    assert any(d['date_value'] == '2026-11-30' for d in edited['dates'])

    undo = client.post(
        f'/api/command/{command_id}/undo',
        headers={'X-Household-Id': str(household)},
    )
    assert undo.status_code == 200, undo.text

    restored = _batch_of(client, household, '두부')
    assert restored['raw_name'] == '두부'
    assert all(d['date_value'] != '2026-11-30' for d in restored['dates'])


def test_manual_discard_undo_revives_batch(client, household):
    """버린 묶음이 되돌리기로 되살아난다."""
    say(client, household, '두부 두 모 넣었어')
    batch = _batch_of(client, household, '두부')

    command_id = str(uuid4())
    response = client.delete(
        f"/api/inventory/batches/{batch['batch_id']}?command_id={command_id}",
        headers={'X-Household-Id': str(household)},
    )
    assert response.status_code == 204, response.text
    assert quantity_of(household, '두부') is None, '버린 묶음은 목록에서 빠진다'

    undo = client.post(
        f'/api/command/{command_id}/undo',
        headers={'X-Household-Id': str(household)},
    )
    assert undo.status_code == 200, undo.text
    assert quantity_of(household, '두부') == Decimal('2.000')


def test_manual_edit_is_idempotent(client, household):
    """같은 요청 ID 로 다시 보내도 한 번만 적용된다."""
    say(client, household, '계란 열 개 넣었어')
    batch = _batch_of(client, household, '계란')

    command_id = str(uuid4())
    body = {'command_id': command_id, 'quantity': '4'}
    for _ in range(2):
        response = client.patch(
            f"/api/inventory/batches/{batch['batch_id']}",
            json=body,
            headers={'X-Household-Id': str(household)},
        )
        assert response.status_code == 200, response.text

    assert quantity_of(household, '계란') == Decimal('4.000')
    rows = client.get(
        '/api/command/history', headers={'X-Household-Id': str(household)}
    ).json()
    edits = [row for row in rows if row['command_id'] == command_id]
    assert len(edits) == 1, '재시도가 이력을 두 줄로 만들지 않는다'


def test_discard_retry_succeeds(client, household):
    """이미 버린 묶음에 다시 보내도 실패로 답하지 않는다.

    재시도가 404 로 돌아오면 사용자는 버려지지 않았다고 믿는다.
    """
    say(client, household, '두부 두 모 넣었어')
    batch = _batch_of(client, household, '두부')
    url = f"/api/inventory/batches/{batch['batch_id']}"

    assert client.delete(
        url, headers={'X-Household-Id': str(household)}
    ).status_code == 204
    retry = client.delete(url, headers={'X-Household-Id': str(household)})
    assert retry.status_code == 204, retry.text


def test_cooked_uses_screen_servings(client, household):
    """차감 기준은 **화면에서 조리한 인분**이다.

    저장된 추천 인분으로 빼면 4인분을 만든 사람에게 2인분이 빠진다.
    """
    say(client, household, '두부 열 모 넣었어')
    menu = _suggest(client, household)

    doubled = client.post(
        f"/api/menu/suggestions/{menu['suggestion_id']}/cooked?servings=4",
        headers={'X-Household-Id': str(household)},
    )
    assert doubled.status_code == 200, doubled.text
    body = doubled.json()
    assert body['undo_token'], '되돌릴 수 있어야 한다'

    left = quantity_of(household, '두부')
    assert left is not None
    # 2인분 기준으로 뺐다면 남은 양이 더 많다. 화면 인분(4)으로 뺀 것을 확인한다.
    assert left < Decimal('10.000')

    undo = client.post(
        f"/api/command/{body['undo_token']}/undo",
        headers={'X-Household-Id': str(household)},
    )
    assert undo.status_code == 200, undo.text
    assert quantity_of(household, '두부') == Decimal('10.000')


def test_recipe_detail_does_not_print_scientific_notation(client, household):
    """300 을 `3E+2` 로 내보내지 않는다.

    `Decimal.normalize()` 의 문자열이 그대로 화면에 찍혀 "삼겹살 3E+2g" 가 나왔다.
    사용자는 이것을 읽을 수 없다.
    """
    say(client, household, "삼겹살 300그램 넣었어")
    menus = client.post(
        "/api/menu/suggestions?servings=2", headers={"X-Household-Id": str(household)}
    ).json()
    recipe_id = menus[0]["recipe_id"]

    for servings in (1, 2, 4, 8):
        detail = client.get(
            f"/api/menu/recipes/{recipe_id}?servings={servings}",
            headers={"X-Household-Id": str(household)},
        ).json()
        amounts = [
            row["required_amount"]
            for row in detail["ingredients"]
            if row["required_amount"] is not None
        ]
        assert amounts, "수량이 있는 재료가 하나는 있어야 판정할 수 있다"
        for amount in amounts:
            assert "E" not in amount.upper(), (
                f"{servings}인분에서 지수 표기가 나왔다: {amount}"
            )


def _add(client, household_id: int, **body) -> dict:
    """화면에서 재료 하나를 넣는다. 재료 추가 화면이 쓰는 경로와 같다."""
    response = client.post(
        '/api/inventory/batches',
        json=body,
        headers={'X-Household-Id': str(household_id)},
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_manual_add_creates_batch_and_history(client, household):
    """손으로 넣은 재료가 재고와 기록에 함께 남는다.

    기록이 없으면 기록 화면에서 재료가 저절로 생긴 것처럼 보이고 되돌릴 수도 없다.
    """
    command_id = str(uuid4())
    added = _add(
        client,
        household,
        command_id=command_id,
        name='두부',
        quantity='2',
        unit='모',
        storage_location='fridge',
        date_kind='use_by',
        date_value='2026-11-30',
    )
    assert added['raw_name'] == '두부'
    # 표기로 보내도 기호로 저장한다. 레시피 차감이 기호로 환산한다.
    assert added['unit'] == 'mo'
    assert added['quantity_certainty'] == 'exact'
    assert [(d['kind'], d['date_value']) for d in added['dates']] == [
        ('use_by', '2026-11-30')
    ]
    assert quantity_of(household, '두부') == Decimal('2.000')

    rows = client.get(
        '/api/command/history', headers={'X-Household-Id': str(household)}
    ).json()
    mine = [row for row in rows if row['command_id'] == command_id]
    assert any(row['action'] == 'stock_in' for row in mine), '기록에 넣은 줄이 있어야 한다'

    undo = client.post(
        f'/api/command/{command_id}/undo', headers={'X-Household-Id': str(household)}
    )
    assert undo.status_code == 200, undo.text
    assert quantity_of(household, '두부') is None, '되돌리면 넣은 묶음이 빠진다'


def test_manual_add_is_idempotent(client, household):
    """같은 요청 ID 로 다시 보내도 한 번만 넣는다."""
    command_id = str(uuid4())
    first = _add(client, household, command_id=command_id, name='계란', quantity='10', unit='ea')
    again = _add(client, household, command_id=command_id, name='계란', quantity='10', unit='ea')

    assert again['batch_id'] == first['batch_id']
    rows = client.get(
        '/api/inventory/batches', headers={'X-Household-Id': str(household)}
    ).json()
    assert len([row for row in rows if row['raw_name'] == '계란']) == 1


def test_manual_add_requires_quantity(client, household):
    """수량 없이는 넣지 않는다. 잔량 없는 묶음은 저장할 수 없다."""
    response = client.post(
        '/api/inventory/batches',
        json={'name': '김치'},
        headers={'X-Household-Id': str(household)},
    )
    assert response.status_code == 422, response.text
    assert actions_of(household) == []


def test_manual_add_rejects_unknown_unit(client, household):
    """모르는 단위는 저장하지 않는다. 환산할 수 없는 수량이 된다."""
    response = client.post(
        '/api/inventory/batches',
        json={'name': '두부', 'quantity': '2', 'unit': '자루'},
        headers={'X-Household-Id': str(household)},
    )
    assert response.status_code == 422, response.text
    assert quantity_of(household, '두부') is None


def test_discard_all_empties_only_this_household(client, household, neighbor):
    """냉장고 비우기는 이 가구의 살아 있는 묶음만 모두 버린다."""
    say(client, household, '두부 두 모 넣었어')
    say(client, household, '계란 열 개 넣었어')
    say(client, neighbor, '두부 세 모 넣었어')

    command_id = str(uuid4())
    response = client.post(
        '/api/inventory/batches/discard-all',
        json={'command_id': command_id},
        headers={'X-Household-Id': str(household)},
    )
    assert response.status_code == 200, response.text
    assert response.json() == {'command_id': command_id, 'discarded_count': 2}

    rows = client.get(
        '/api/inventory/batches', headers={'X-Household-Id': str(household)}
    ).json()
    assert rows == []
    assert quantity_of(neighbor, '두부') == Decimal('3.000'), '다른 가구는 그대로다'

    # 재시도는 다시 비우지 않는다. 그 사이 넣은 재료까지 버리면 안 된다.
    say(client, household, '우유 한 개 넣었어')
    retry = client.post(
        '/api/inventory/batches/discard-all',
        json={'command_id': command_id},
        headers={'X-Household-Id': str(household)},
    )
    assert retry.json()['discarded_count'] == 2
    assert quantity_of(household, '우유') == Decimal('1.000')


def test_discard_all_is_one_action_in_history(client, household):
    """모두 버린 일이 명령 하나로 남고, 한 번 되돌리면 모두 돌아온다."""
    say(client, household, '두부 두 모 넣었어')
    say(client, household, '계란 열 개 넣었어')

    body = client.post(
        '/api/inventory/batches/discard-all',
        headers={'X-Household-Id': str(household)},
    ).json()
    assert body['discarded_count'] == 2

    rows = client.get(
        '/api/command/history', headers={'X-Household-Id': str(household)}
    ).json()
    discards = [row for row in rows if row['action'] == 'discard']
    assert len(discards) == 2
    assert {row['command_id'] for row in discards} == {body['command_id']}

    undo = client.post(
        f"/api/command/{body['command_id']}/undo",
        headers={'X-Household-Id': str(household)},
    )
    assert undo.status_code == 200, undo.text
    assert quantity_of(household, '두부') == Decimal('2.000')
    assert quantity_of(household, '계란') == Decimal('10.000')


def test_discard_all_on_empty_fridge_records_nothing(client, household):
    """버릴 것이 없으면 기록을 남기지 않는다."""
    body = client.post(
        '/api/inventory/batches/discard-all',
        json={},
        headers={'X-Household-Id': str(household)},
    ).json()
    assert body == {'command_id': None, 'discarded_count': 0}
    assert actions_of(household) == []
