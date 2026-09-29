"""인증의 불변 조건.

DB 없이 도는 것(해시·토큰·비밀번호 규칙·헤더 해석)과 실제 PostgreSQL 이 필요한 것
(가입·로그인·세션·가구 격리)을 나눈다. 후자는 DB 가 없으면 건너뛴다.

여기서 지키는 것은 넷이다.

1. 비밀번호 원문과 토큰 원문이 **저장되지 않는다.**
2. 로그인 실패가 **이메일의 존재 여부를 알려주지 않는다.**
3. 로그아웃한 토큰이 **더는 통하지 않는다.**
4. 계정은 **자기 가구만** 본다. 헤더로 남의 가구를 지정할 수 없다.
"""

import asyncio
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from app.core.config import get_settings
from app.core.identity import bearer_token
from app.core.security import (
    hash_password,
    hash_token,
    new_session_token,
    session_expiry,
    verify_password,
)
from app.domain.auth.schemas import SignUpRequest

# --- DB 없이 도는 것 -------------------------------------------------------


def test_password_hash_is_not_the_password():
    hashed = hash_password("kitchen123")
    assert hashed != "kitchen123"
    assert "kitchen123" not in hashed
    assert verify_password("kitchen123", hashed)
    assert not verify_password("kitchen124", hashed)


def test_same_password_gets_different_hashes():
    # 솔트가 없으면 같은 비밀번호를 쓰는 계정이 드러난다.
    assert hash_password("kitchen123") != hash_password("kitchen123")


def test_broken_hash_is_a_mismatch_not_a_crash():
    # 저장된 값이 깨졌다고 예외가 새면 어느 계정이 손상됐는지가 드러난다.
    assert not verify_password("kitchen123", "not-a-bcrypt-hash")


def test_token_hash_is_not_the_token():
    token = new_session_token()
    assert hash_token(token) != token
    assert hash_token(token) == hash_token(token)
    assert hash_token(token) != hash_token(new_session_token())


def test_tokens_do_not_repeat():
    assert len({new_session_token() for _ in range(200)}) == 200


def test_session_expiry_is_in_the_future():
    assert session_expiry() > datetime.now(UTC) + timedelta(days=1)


@pytest.mark.parametrize(
    "header,expected",
    [
        ("Bearer abc123", "abc123"),
        ("bearer abc123", "abc123"),
        ("  Bearer   abc123  ", "abc123"),
        ("Basic abc123", None),
        ("Bearer", None),
        ("Bearer   ", None),
        ("", None),
        (None, None),
    ],
)
def test_bearer_token_parsing(header, expected):
    assert bearer_token(header) == expected


@pytest.mark.parametrize("bad", ["short1", "nodigitshere", "12345678", "aB1"])
def test_weak_passwords_are_rejected(bad):
    with pytest.raises(ValueError):
        SignUpRequest(email="a@b.com", password=bad, nickname="철")


def test_strong_password_is_accepted():
    body = SignUpRequest(email="a@b.com", password="kitchen123", nickname="  철  ")
    assert body.nickname == "철", "닉네임의 앞뒤 공백은 지운다"


def test_blank_nickname_is_rejected():
    with pytest.raises(ValueError):
        SignUpRequest(email="a@b.com", password="kitchen123", nickname="   ")


# --- 실제 DB 가 필요한 것 ---------------------------------------------------


@pytest.fixture(scope="module")
def database_ready():
    """마이그레이션이 적용된 DB. 없으면 이 모듈의 통합 테스트를 건너뛴다."""
    settings = get_settings()
    candidate = create_engine(settings.alembic_url, pool_pre_ping=True)
    try:
        with candidate.connect() as connection:
            applied = connection.execute(
                text(
                    "select count(*) from information_schema.tables "
                    "where table_name='user_session'"
                )
            ).scalar_one()
    except Exception as error:  # noqa: BLE001
        pytest.skip(f"PostgreSQL unavailable: {error}")
    finally:
        candidate.dispose()
    if not applied:
        pytest.skip("migrations not applied: run 'alembic upgrade head'")
    return True


@pytest.fixture
def run(database_ready):
    """세션 하나를 열어 비동기 작업을 돌리고 **끝나면 되돌린다.**

    커밋을 지우기 위해 바깥 트랜잭션 안에서 돌린다 — 서비스가 스스로 커밋하므로
    테스트가 남긴 계정이 DB 에 쌓이면 다음 실행의 유일 제약을 건드린다.
    """

    async def _run(work):
        engine = create_async_engine(get_settings().database_url)
        try:
            async with engine.connect() as connection:
                outer = await connection.begin()
                maker = sessionmaker(
                    bind=connection, class_=AsyncSession, expire_on_commit=False
                )
                async with maker() as session:
                    try:
                        return await work(session)
                    finally:
                        await outer.rollback()
        finally:
            await engine.dispose()

    return lambda work: asyncio.run(_run(work))


def _email() -> str:
    return f"test-{new_session_token()[:12].lower()}@example.com"


def test_sign_up_creates_its_own_household(run):
    from app.domain.auth import service

    async def work(session):
        result = await service.sign_up(
            session, email=_email(), password="kitchen123", nickname="철"
        )
        default = get_settings().default_household_id
        assert result.user.household_id != default, (
            "가입한 계정은 기본 가구에 묶이지 않는다 — 묶이면 가입한 사람들이 "
            "같은 냉장고를 함께 본다"
        )
        assert result.access_token
        return result

    run(work)


def test_stored_row_holds_no_secrets(run):
    from app.domain.auth import crud, service

    password = "kitchen123"

    async def work(session):
        email = _email()
        result = await service.sign_up(
            session, email=email, password=password, nickname="철"
        )
        user = await crud.find_user_by_email(session, email)
        assert user is not None
        assert user.password_hash != password
        assert password not in (user.password_hash or "")

        row = await crud.find_live_session(session, hash_token(result.access_token))
        assert row is not None
        assert row[0].token_hash != result.access_token

    run(work)


def test_sign_in_rejects_wrong_password_and_unknown_email_the_same_way(run):
    from app.core.exceptions import UnauthorizedError
    from app.domain.auth import service

    async def work(session):
        email = _email()
        await service.sign_up(session, email=email, password="kitchen123", nickname="철")

        with pytest.raises(UnauthorizedError) as wrong:
            await service.sign_in(session, email=email, password="kitchen124")
        with pytest.raises(UnauthorizedError) as unknown:
            await service.sign_in(session, email=_email(), password="kitchen123")

        assert wrong.value.message_key == unknown.value.message_key
        assert wrong.value.status_code == unknown.value.status_code

    run(work)


def test_duplicate_email_is_refused_case_insensitively(run):
    from app.core.exceptions import ConflictError
    from app.domain.auth import service

    async def work(session):
        email = _email()
        await service.sign_up(session, email=email, password="kitchen123", nickname="철")
        with pytest.raises(ConflictError):
            await service.sign_up(
                session, email=email.upper(), password="kitchen123", nickname="철2"
            )

    run(work)


def test_sign_out_kills_the_token(run):
    from app.domain.auth import service

    async def work(session):
        email = _email()
        opened = await service.sign_up(
            session, email=email, password="kitchen123", nickname="철"
        )
        assert await service.resolve(session, opened.access_token) is not None

        await service.sign_out(session, opened.access_token)
        assert await service.resolve(session, opened.access_token) is None, (
            "로그아웃한 토큰이 계속 통하면 로그아웃이 세션을 끝내지 못한 것이다"
        )

        # 두 번 눌러도 실패로 다루지 않는다.
        await service.sign_out(session, opened.access_token)

    run(work)


def test_expired_session_does_not_resolve(run):
    from app.domain.auth import crud, service

    async def work(session):
        email = _email()
        opened = await service.sign_up(
            session, email=email, password="kitchen123", nickname="철"
        )
        found = await crud.find_live_session(session, hash_token(opened.access_token))
        assert found is not None
        found[0].expires_at = datetime.now(UTC) - timedelta(seconds=1)
        await session.commit()

        assert await service.resolve(session, opened.access_token) is None

    run(work)


def test_unknown_token_does_not_resolve(run):
    from app.domain.auth import service

    async def work(session):
        assert await service.resolve(session, new_session_token()) is None

    run(work)


def test_email_check_reports_taken(run):
    from app.domain.auth import service

    async def work(session):
        email = _email()
        free = await service.check_email(session, email)
        assert free.available is True
        assert free.reason == "ok"

        await service.sign_up(session, email=email, password="kitchen123", nickname="철")

        taken = await service.check_email(session, email)
        assert taken.available is False
        assert taken.reason == "taken"

        # 대소문자와 앞뒤 공백은 같은 계정으로 본다.
        same = await service.check_email(session, f"  {email.upper()}  ")
        assert same.reason == "taken"

    run(work)


def test_email_check_separates_invalid_from_taken(run):
    """형식이 틀린 것과 이미 쓰는 것은 사용자가 고쳐야 할 것이 다르다."""
    from app.domain.auth import service

    async def work(session):
        for bad in ["notanemail", "", "   ", "a@", "@b.com"]:
            result = await service.check_email(session, bad)
            assert result.available is False
            assert result.reason == "invalid", bad

    run(work)


def test_email_check_creates_nothing(run):
    """확인은 조회일 뿐이다. 이것만으로 계정이 생기면 안 된다."""
    from app.domain.auth import crud, service

    async def work(session):
        email = _email()
        await service.check_email(session, email)
        assert await crud.find_user_by_email(session, email) is None

    run(work)


def test_nickname_may_repeat(run):
    """닉네임은 중복을 허용한다. 본인에게만 보이는 이름이라 막을 이유가 없다."""
    from app.domain.auth import service

    async def work(session):
        one = await service.sign_up(
            session, email=_email(), password="kitchen123", nickname="철"
        )
        two = await service.sign_up(
            session, email=_email(), password="kitchen123", nickname="철"
        )
        assert one.user.display_name == two.user.display_name == "철"
        assert one.user.user_id != two.user.user_id

    run(work)


# --- 소셜 로그인 ------------------------------------------------------------
#
# 카카오를 실제로 부르지 않는다. 확인하려는 것은 "제공자가 확인해 준 사람을 어떻게
# 계정에 잇는가" 이고, 제공자 응답을 읽는 부분은 아래 파싱 테스트가 따로 본다.


def _kakao(user_id: str, nickname: str | None = "철", email: str | None = None):
    from app.core.enums import AuthProvider
    from app.domain.auth.providers import ProviderIdentity

    async def _verify(provider, access_token):
        return ProviderIdentity(
            provider=AuthProvider.KAKAO,
            provider_user_id=user_id,
            nickname=nickname,
            email=email,
        )

    return _verify


def test_first_social_sign_in_creates_account_and_household(run, monkeypatch):
    from app.core.enums import AuthProvider
    from app.domain.auth import providers, service

    monkeypatch.setattr(providers, "verify", _kakao("kakao-1"))

    async def work(session):
        opened = await service.sign_in_with_provider(
            session, provider=AuthProvider.KAKAO, access_token="whatever"
        )
        assert opened.user.provider == "kakao"
        assert opened.user.household_id != get_settings().default_household_id
        assert opened.access_token
        return opened

    run(work)


def test_second_social_sign_in_reuses_the_account(run, monkeypatch):
    from app.core.enums import AuthProvider
    from app.domain.auth import providers, service

    monkeypatch.setattr(providers, "verify", _kakao("kakao-2"))

    async def work(session):
        first = await service.sign_in_with_provider(
            session, provider=AuthProvider.KAKAO, access_token="whatever"
        )
        second = await service.sign_in_with_provider(
            session, provider=AuthProvider.KAKAO, access_token="whatever"
        )
        assert first.user.user_id == second.user.user_id, (
            "두 번째 로그인이 계정을 새로 만들면 냉장고가 둘로 갈린다"
        )
        assert first.access_token != second.access_token, "세션은 매번 새로 연다"

    run(work)


def test_social_account_has_no_password(run, monkeypatch):
    from app.core.enums import AuthProvider
    from app.domain.auth import crud, providers, service

    monkeypatch.setattr(providers, "verify", _kakao("kakao-3"))

    async def work(session):
        opened = await service.sign_in_with_provider(
            session, provider=AuthProvider.KAKAO, access_token="whatever"
        )
        user = await crud.find_user_by_provider(
            session, provider="kakao", provider_user_id="kakao-3"
        )
        assert user is not None
        assert user.user_id == opened.user.user_id
        assert user.password_hash is None, "소셜 계정에는 비밀번호가 없다"

    run(work)


def test_social_sign_in_does_not_steal_an_existing_email(run, monkeypatch):
    """제공자가 준 이메일을 이미 다른 계정이 쓰면 비워 둔다.

    그대로 담으면 유일 제약에 걸려 로그인 자체가 막힌다. 두 계정을 합치는 것은 별도
    정책이므로 여기서 임의로 잇지 않는다.
    """
    from app.core.enums import AuthProvider
    from app.domain.auth import crud, providers, service

    async def work(session):
        email = _email()
        await service.sign_up(session, email=email, password="kitchen123", nickname="철")

        monkeypatch.setattr(providers, "verify", _kakao("kakao-4", email=email))
        opened = await service.sign_in_with_provider(
            session, provider=AuthProvider.KAKAO, access_token="whatever"
        )

        owner = await crud.find_user_by_email(session, email)
        assert owner is not None
        assert owner.user_id != opened.user.user_id, "남의 계정에 붙지 않는다"
        assert opened.user.email is None

    run(work)


def test_social_sign_in_without_nickname_still_works(run, monkeypatch):
    from app.core.enums import AuthProvider
    from app.domain.auth import providers, service

    monkeypatch.setattr(providers, "verify", _kakao("kakao-5", nickname=None))

    async def work(session):
        opened = await service.sign_in_with_provider(
            session, provider=AuthProvider.KAKAO, access_token="whatever"
        )
        assert opened.user.display_name, "이름이 없어도 빈 문자열로 두지 않는다"

    run(work)


def test_two_accounts_get_two_households(run):
    from app.domain.auth import service

    async def work(session):
        one = await service.sign_up(
            session, email=_email(), password="kitchen123", nickname="철"
        )
        two = await service.sign_up(
            session, email=_email(), password="kitchen123", nickname="영"
        )
        assert one.user.household_id != two.user.household_id, (
            "가구가 같으면 두 계정이 같은 냉장고를 본다"
        )

    run(work)
