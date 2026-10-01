"""영상 레시피 API 의 HTTP 왕복 통합 테스트.

**실제 PostgreSQL 이 필요하다.** 없으면 건너뛴다. 유튜브와 모델은 부르지 않는다 —
메타 수집을 가짜로 갈고 `FakeLlmGateway` 를 쓴다. 이 파일이 확인하는 것은 정리 결과가
아니라 **경로의 계약**이다.

검증 기준 V-14(F-18·19)에 대응한다. 유튜브가 아닌 링크의 거절, 영상에 없는 수량을
만들지 않는 것, 저장된 분석도 최신 재고로 다시 대조하는 것, 그리고 **분석만으로 재고가
바뀌지 않는 것**을 확인한다.
"""

from __future__ import annotations

from typing import Any
from uuid import uuid4

import pytest
from fastapi import status
from sqlalchemy import create_engine, text

from app.core.config import get_settings

_VIDEO_ID = "abcdefghijk"
_URL = f"https://www.youtube.com/watch?v={_VIDEO_ID}"

#: 재료와 번호 붙은 순서가 있는 설명글. `FakeLlmGateway` 가 이 모양을 단계로 읽는다.
_BODY = """
재료: 계란, 두부, 없는재료

1. 두부를 물기를 빼고 썬다
2. 계란을 풀어 3분 부친다
3. 두부와 계란을 함께 낸다
"""


def _database_ready() -> bool:
    try:
        engine = create_engine(get_settings().alembic_url, pool_pre_ping=True)
        with engine.connect() as connection:
            return bool(
                connection.execute(
                    text(
                        "select count(*) from information_schema.tables "
                        "where table_name='video_recipe'"
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
    """가짜 게이트웨이와 가짜 유튜브를 쓰는 테스트 클라이언트."""
    from fastapi.testclient import TestClient

    from app.core.llm import provider
    from app.core.llm.fake import FakeLlmGateway
    from app.domain.video import service as video_service
    from app.domain.video.youtube import VideoMeta

    fake = FakeLlmGateway()
    original = provider.get_gateway
    original.cache_clear()
    monkeypatch.setattr(provider, "get_gateway", lambda: fake)

    async def fetch_meta(video_id: str, settings: Any) -> VideoMeta:
        return VideoMeta(
            video_id=video_id,
            url=f"https://www.youtube.com/watch?v={video_id}",
            title="두부 계란 볶음",
            channel="테스트 채널",
            duration_seconds=180,
            description=_BODY,
        )

    monkeypatch.setattr(video_service.youtube, "fetch_meta", fetch_meta)

    from app.main import create_app

    app = create_app()
    app.dependency_overrides[original] = lambda: fake

    with TestClient(app) as test_client:
        yield test_client
    original.cache_clear()


@pytest.fixture
def household():
    """테스트마다 새 가구를 만들고 분석 결과까지 지운다."""
    engine = create_engine(get_settings().alembic_url)
    with engine.begin() as connection:
        household_id = connection.execute(
            text(
                "insert into household (name, timezone, default_servings, tools, "
                "expiry_alert_days) values ('영상테스트', 'Asia/Seoul', 2, '{}', "
                "'{3,1,0}') returning household_id"
            )
        ).scalar_one()
    yield household_id
    with engine.begin() as connection:
        # 분석 결과는 가구에 매이지 않는다. 영상 ID 로 지운다 — 남기면 다음 테스트가
        # 저장된 결과를 재사용해 모델 경로를 타지 않는다.
        connection.execute(
            text("delete from video_recipe where video_id = :v"), {"v": _VIDEO_ID}
        )
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


@pytest.fixture
def token(client, household):
    """이 가구를 쓰는 세션 토큰.

    `X-Household-Id` 는 운영에서 읽지 않으므로 가구를 고르는 방법은 로그인뿐이다.
    가입이 만든 가구를 쓰는 대신, 만들어 둔 가구에 계정을 직접 붙인다.
    """
    from app.core.security import hash_token, new_session_token, session_expiry

    raw = new_session_token()
    engine = create_engine(get_settings().alembic_url)
    with engine.begin() as connection:
        user_id = connection.execute(
            text(
                "insert into app_user (household_id, provider, provider_user_id, "
                "email, password_hash, display_name) values (:h, 'email', :e, :e, "
                "'x', '영상') returning user_id"
            ),
            {"h": household, "e": f"video-{uuid4().hex[:10]}@example.com"},
        ).scalar_one()
        connection.execute(
            text(
                "insert into user_session (user_id, token_hash, expires_at) "
                "values (:u, :t, :x)"
            ),
            {"u": user_id, "t": hash_token(raw), "x": session_expiry()},
        )
    yield raw
    with engine.begin() as connection:
        connection.execute(
            text("delete from user_session where user_id = :u"), {"u": user_id}
        )
        connection.execute(text("delete from app_user where user_id = :u"), {"u": user_id})


def auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def say(client, token: str, utterance: str) -> dict[str, Any]:
    response = client.post(
        "/api/command/interpret",
        json={"command_id": str(uuid4()), "utterance": utterance},
        headers=auth(token),
    )
    assert response.status_code == status.HTTP_200_OK, response.text
    return response.json()


def analyze(client, token: str, url: str = _URL):
    return client.post("/api/video/analyze", json={"url": url}, headers=auth(token))


def stock_names(client, token: str) -> list[str]:
    response = client.get("/api/inventory/batches", headers=auth(token))
    assert response.status_code == status.HTTP_200_OK, response.text
    return [row["raw_name"] for row in response.json()]


# --- 링크 해석 -------------------------------------------------------------


@pytest.mark.parametrize(
    "url",
    ["https://example.com/watch?v=abcdefghijk", "그냥 문장", "https://vimeo.com/123456"],
)
def test_links_that_are_not_youtube_are_refused(client, token, url):
    response = analyze(client, token, url)
    assert response.status_code == 422, response.text


def test_blank_url_is_refused_before_the_service(client, token):
    response = analyze(client, token, "")
    assert response.status_code == 422, response.text


# --- 정리 결과 -------------------------------------------------------------


def test_analyze_reads_ingredients_and_steps(client, token):
    response = analyze(client, token)
    assert response.status_code == status.HTTP_200_OK, response.text

    body = response.json()
    assert body["video_id"] == _VIDEO_ID
    assert [step["order"] for step in body["steps"]] == [1, 2, 3]
    assert {row["name"] for row in body["ingredients"]} >= {"계란", "두부"}


def test_written_timer_is_kept_and_others_stay_empty(client, token):
    """영상에 적힌 시간만 담는다. 없는 단계에 시간을 만들지 않는다."""
    steps = analyze(client, token).json()["steps"]

    timers = [step["timer_seconds"] for step in steps]
    assert 180 in timers, "3분 이라고 적힌 단계는 타이머를 갖는다"
    assert None in timers, "시간이 없는 단계에는 타이머를 만들지 않는다"


def test_amounts_that_were_not_written_stay_unknown(client, token):
    """분량이 적히지 않은 재료는 미확인으로 남는다."""
    rows = {row["name"]: row for row in analyze(client, token).json()["ingredients"]}

    assert rows["없는재료"]["required_amount"] is None


def test_missing_ingredients_are_named(client, token):
    """재고에 없는 재료를 이름으로 알린다."""
    say(client, token, "계란 열 개 넣었어")

    body = analyze(client, token).json()

    assert body["availability"] != "ready"
    assert "두부" in body["missing_ingredients"]
    assert "두부" not in [
        row["name"] for row in body["ingredients"] if row["status"] == "have"
    ]


def test_stock_under_an_alias_covers_a_canonical_ingredient(client, token, monkeypatch):
    """"삼겹살" 로 넣은 재고가 "돼지고기" 를 요구하는 레시피를 덮는다.

    재료 사전에 삼겹살은 돼지고기의 별칭으로 등록돼 있다. 말한 이름만 대조하면 가진 고기를
    없다고 판정해 "지금 가능" 이 나오지 않는다 — 시연에서 바로 보이는 결함이었다.
    """
    from app.domain.video import service as video_service
    from app.domain.video.youtube import VideoMeta

    async def pork(video_id: str, settings: Any) -> VideoMeta:
        return VideoMeta(
            video_id=video_id,
            url=f"https://www.youtube.com/watch?v={video_id}",
            title="돼지고기 김치볶음",
            duration_seconds=120,
            description="재료: 돼지고기, 김치\n\n1. 고기를 볶는다\n2. 김치를 넣는다",
        )

    monkeypatch.setattr(video_service.youtube, "fetch_meta", pork)
    say(client, token, "삼겹살 300그램 넣었어")

    body = analyze(client, token).json()

    rows = {row["name"]: row["status"] for row in body["ingredients"]}
    assert rows["돼지고기"] != "missing", (
        "삼겹살을 가지고 있는데 돼지고기가 없다고 하면 안 된다"
    )
    assert "돼지고기" not in body["missing_ingredients"]


# --- 저장된 분석과 최신 재고 -----------------------------------------------


def test_stored_analysis_is_matched_against_the_latest_stock(client, token):
    """두 번째 호출은 저장된 결과를 쓰지만 재고 판정은 다시 한다."""
    first = analyze(client, token).json()
    assert "계란" in first["missing_ingredients"]

    say(client, token, "계란 열 개 넣었어")
    second = analyze(client, token).json()

    assert "계란" not in second["missing_ingredients"], (
        "저장된 판정을 그대로 돌려주면 재고가 바뀐 뒤에도 옛 답이 화면에 남는다"
    )
    # 영상이 분량을 적지 않았으므로 보유해도 `have` 가 아니다 — 있다고 단정하지 않고
    # 확인 대상으로 둔다. F-19 의 "근거 없는 판정을 하지 않는다" 가 이 값이다.
    rows = {row["name"]: row["status"] for row in second["ingredients"]}
    assert rows["계란"] == "needs_check"
    assert "계란" in second["uncertain_ingredients"]


def test_analysis_does_not_change_stock(client, token):
    """분석 경로에는 재고 변경 권한이 없다."""
    say(client, token, "계란 열 개 넣었어")
    before = stock_names(client, token)

    analyze(client, token)
    analyze(client, token)

    assert stock_names(client, token) == before
    history = client.get("/api/command/history", headers=auth(token)).json()
    commands = {row["command_id"] for row in history}
    assert len(commands) == 1, "분석이 명령 원장에 기록을 남기면 안 된다"


# --- 아직 없는 것 ---------------------------------------------------------


def test_video_search_is_not_a_fake_success(client, token):
    """영상 검색(F-17)은 붙지 않았다. 가짜 링크를 돌려주지 않는다."""
    response = client.get(
        "/api/video/search", params={"q": "두부 요리"}, headers=auth(token)
    )
    assert response.status_code == status.HTTP_501_NOT_IMPLEMENTED, response.text
    assert "youtube.com/watch" not in response.text


def test_guest_can_analyze_without_signing_in(client):
    """로그인은 관문이 아니다. 게스트도 기본 가구로 정리할 수 있다."""
    response = client.post("/api/video/analyze", json={"url": _URL})
    assert response.status_code == status.HTTP_200_OK, response.text
