"""인증 API 의 HTTP 왕복 통합 테스트.

**실제 PostgreSQL 이 필요하다.** 없으면 건너뛴다.

`tests/test_auth.py` 는 서비스 계층에서 해시·세션·가구 분리를 본다. 여기서 보는 것은
**헤더에서 화면까지의 왕복**이다 — 앱이 실제로 쓰는 것은 서비스 함수가 아니라 이 경로이고,
토큰을 헤더로 실어 보낸 뒤 자기 가구의 재고가 오는지는 여기서만 드러난다.

검증 기준 V-13(F-22)에 대응한다. 계정마다 다른 가구, 가입 직후 빈 냉장고, 로그아웃한
토큰의 401, 미연동 제공자를 성공으로 처리하지 않는 것을 확인한다.
"""

from __future__ import annotations

from typing import Any
from uuid import uuid4

import pytest
from fastapi import status
from sqlalchemy import create_engine, text

from app.core.config import get_settings
from app.core.enums import AuthProvider


def _database_ready() -> bool:
    try:
        engine = create_engine(get_settings().alembic_url, pool_pre_ping=True)
        with engine.connect() as connection:
            return bool(
                connection.execute(
                    text(
                        "select count(*) from information_schema.tables "
                        "where table_name='app_user'"
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

    호출자는 **갈아 끼우지 않는다.** 이 파일이 확인하는 것이 신원 확인 자체이므로
    `get_caller` 를 그대로 태워 토큰이 실제로 가구를 고르는지 본다.
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

    with TestClient(app) as test_client:
        yield test_client
    original.cache_clear()


@pytest.fixture
def accounts():
    """이 테스트가 만든 계정과 가구를 지운다.

    운영에서는 계정을 지우지 않으므로 이 정리 순서가 필요한 곳은 테스트뿐이다.
    가구를 지우면 `app_user` 가 CASCADE 로 함께 사라지지만, 원장이 명령과 묶음을
    참조하므로 의존 순서를 따라야 한다.
    """
    created: list[str] = []
    yield created

    if not created:
        return
    engine = create_engine(get_settings().alembic_url)
    with engine.begin() as connection:
        household_ids = list(
            connection.execute(
                text("select household_id from app_user where email = any(:emails)"),
                {"emails": created},
            ).scalars()
        )
        for household_id in household_ids:
            for statement in (
                "delete from change_event where command_id in "
                "(select command_id from command where household_id = :h)",
                "delete from batch_state_event where command_id in "
                "(select command_id from command where household_id = :h)",
                "delete from batch_date where batch_id in "
                "(select batch_id from ingredient_batch where household_id = :h)",
                "delete from ingredient_batch where household_id = :h",
                "delete from command where household_id = :h",
                "delete from user_session where user_id in "
                "(select user_id from app_user where household_id = :h)",
                "delete from app_user where household_id = :h",
                "delete from household where household_id = :h",
            ):
                connection.execute(text(statement), {"h": household_id})


def _email() -> str:
    return f"e2e-{uuid4().hex[:12]}@example.com"


def sign_up(client, accounts, *, nickname: str = "철") -> tuple[str, str]:
    """가입하고 (이메일, 토큰) 을 돌려준다."""
    email = _email()
    response = client.post(
        "/api/auth/sign-up",
        json={"email": email, "password": "kitchen123", "nickname": nickname},
    )
    assert response.status_code == status.HTTP_201_CREATED, response.text
    accounts.append(email)
    token = response.json()["access_token"]
    assert token
    return email, token


def auth(token: str | None) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"} if token else {}


def say(client, token: str | None, utterance: str) -> dict[str, Any]:
    response = client.post(
        "/api/command/interpret",
        json={"command_id": str(uuid4()), "utterance": utterance},
        headers=auth(token),
    )
    assert response.status_code == status.HTTP_200_OK, response.text
    return response.json()


def batches(client, token: str | None) -> list[dict[str, Any]]:
    response = client.get("/api/inventory/batches", headers=auth(token))
    assert response.status_code == status.HTTP_200_OK, response.text
    return response.json()


# --- 가입과 로그인 ---------------------------------------------------------


def test_sign_up_returns_a_usable_token(client, accounts):
    _, token = sign_up(client, accounts)

    me = client.get("/api/auth/me", headers=auth(token))
    assert me.status_code == status.HTTP_200_OK, me.text
    assert me.json()["provider"] == AuthProvider.EMAIL.value


def test_new_account_starts_with_an_empty_fridge(client, accounts):
    """가입 직후에는 기본 가구의 시연 재고가 보이지 않는다."""
    _, token = sign_up(client, accounts)

    assert batches(client, token) == []


def test_sign_in_again_reaches_the_same_household(client, accounts):
    email, first = sign_up(client, accounts)
    say(client, first, "계란 열 개 넣었어")

    again = client.post(
        "/api/auth/sign-in", json={"email": email, "password": "kitchen123"}
    )
    assert again.status_code == status.HTTP_200_OK, again.text
    second = again.json()["access_token"]
    assert second != first, "로그인마다 새 세션을 연다"

    names = [row["raw_name"] for row in batches(client, second)]
    assert "계란" in names


def test_wrong_password_and_unknown_email_look_the_same(client, accounts):
    email, _ = sign_up(client, accounts)

    wrong = client.post(
        "/api/auth/sign-in", json={"email": email, "password": "kitchen124"}
    )
    unknown = client.post(
        "/api/auth/sign-in", json={"email": _email(), "password": "kitchen123"}
    )

    assert wrong.status_code == status.HTTP_401_UNAUTHORIZED
    assert unknown.status_code == status.HTTP_401_UNAUTHORIZED
    # 본문까지 같아야 한다. 다르면 가입된 이메일인지 확인할 수 있다.
    assert wrong.json() == unknown.json()


def test_duplicate_email_is_refused(client, accounts):
    email, _ = sign_up(client, accounts)

    again = client.post(
        "/api/auth/sign-up",
        json={"email": email.upper(), "password": "kitchen123", "nickname": "다른사람"},
    )
    assert again.status_code == status.HTTP_409_CONFLICT, again.text


def test_availability_reports_a_taken_email(client, accounts):
    email, _ = sign_up(client, accounts)

    taken = client.get("/api/auth/available", params={"email": email})
    free = client.get("/api/auth/available", params={"email": _email()})

    assert taken.status_code == status.HTTP_200_OK, taken.text
    assert taken.json()["available"] is False
    assert free.json()["available"] is True


def test_weak_password_is_refused_before_the_database(client):
    response = client.post(
        "/api/auth/sign-up",
        json={"email": _email(), "password": "short", "nickname": "철"},
    )
    assert response.status_code == 422, response.text


# --- 세션의 수명 -----------------------------------------------------------


def test_signed_out_token_stops_working(client, accounts):
    _, token = sign_up(client, accounts)

    out = client.post("/api/auth/sign-out", headers=auth(token))
    assert out.status_code == status.HTTP_204_NO_CONTENT, out.text

    assert (
        client.get("/api/auth/me", headers=auth(token)).status_code
        == status.HTTP_401_UNAUTHORIZED
    )
    # 재고 조회도 막힌다. 조용히 게스트로 떨어지면 남의 냉장고를 자기 것으로 본다.
    assert (
        client.get("/api/inventory/batches", headers=auth(token)).status_code
        == status.HTTP_401_UNAUTHORIZED
    )


def test_signing_out_leaves_other_sessions_alone(client, accounts):
    email, phone = sign_up(client, accounts)
    tablet = client.post(
        "/api/auth/sign-in", json={"email": email, "password": "kitchen123"}
    ).json()["access_token"]

    client.post("/api/auth/sign-out", headers=auth(phone))

    assert (
        client.get("/api/auth/me", headers=auth(tablet)).status_code
        == status.HTTP_200_OK
    )


def test_unknown_token_is_not_treated_as_a_guest(client):
    response = client.get("/api/inventory/batches", headers=auth("not-a-real-token"))
    assert response.status_code == status.HTTP_401_UNAUTHORIZED, response.text


def test_guest_without_a_token_still_reads_the_default_household(client):
    response = client.get("/api/inventory/batches")
    assert response.status_code == status.HTTP_200_OK, response.text


def test_guest_has_no_account(client):
    assert client.get("/api/auth/me").status_code == status.HTTP_401_UNAUTHORIZED


def test_sign_out_without_a_token_is_refused(client):
    assert (
        client.post("/api/auth/sign-out").status_code == status.HTTP_401_UNAUTHORIZED
    )


# --- 가구 격리 -------------------------------------------------------------


def test_two_accounts_do_not_see_each_other(client, accounts):
    _, mine = sign_up(client, accounts, nickname="나")
    _, theirs = sign_up(client, accounts, nickname="남")

    say(client, mine, "계란 열 개 넣었어")

    assert [row["raw_name"] for row in batches(client, mine)] == ["계란"]
    assert batches(client, theirs) == [], "남의 계정에 내 재고가 보이면 안 된다"


def test_household_header_cannot_pick_another_household(client, accounts):
    """이전 판본의 구멍이다. `X-Household-Id` 는 더 이상 읽지 않는다."""
    _, mine = sign_up(client, accounts)
    say(client, mine, "계란 열 개 넣었어")

    default = get_settings().default_household_id
    response = client.get(
        "/api/inventory/batches",
        headers={**auth(mine), "X-Household-Id": str(default)},
    )

    assert response.status_code == status.HTTP_200_OK, response.text
    assert [row["raw_name"] for row in response.json()] == ["계란"], (
        "헤더가 가구를 바꿨다면 기본 가구의 시연 재고가 왔을 것이다"
    )


def test_history_is_separated_by_account(client, accounts):
    _, mine = sign_up(client, accounts)
    _, theirs = sign_up(client, accounts)
    say(client, mine, "계란 열 개 넣었어")

    ours = client.get("/api/command/history", headers=auth(mine))
    others = client.get("/api/command/history", headers=auth(theirs))

    assert ours.status_code == status.HTTP_200_OK, ours.text
    assert ours.json(), "내 기록은 남아 있다"
    assert others.json() == [], "남의 기록에 내 발화가 보이면 안 된다"


def test_each_account_gets_its_own_household_settings(client, accounts):
    _, mine = sign_up(client, accounts)

    response = client.get("/api/household/me", headers=auth(mine))
    assert response.status_code == status.HTTP_200_OK, response.text
    assert response.json()["household_id"] != get_settings().default_household_id


# --- 미연동 제공자 ---------------------------------------------------------


@pytest.mark.parametrize("provider", ["google", "apple"])
def test_unlinked_providers_are_not_a_success(client, provider):
    response = client.post(
        f"/api/auth/sign-in/{provider}", json={"access_token": "whatever"}
    )
    assert response.status_code >= status.HTTP_400_BAD_REQUEST, response.text
    assert "access_token" not in response.text


def test_email_provider_is_sent_to_the_email_route(client):
    response = client.post(
        "/api/auth/sign-in/email", json={"access_token": "whatever"}
    )
    assert response.status_code == status.HTTP_401_UNAUTHORIZED, response.text
