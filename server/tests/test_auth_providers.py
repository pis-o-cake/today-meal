"""제공자 토큰 검증.

**카카오를 실제로 부르지 않는다.** 확인하려는 것은 응답을 어떻게 읽고 실패를 어떻게
가르는가이며, 네트워크는 `httpx.MockTransport` 로 대신한다.

여기서 지키는 것은 셋이다.

1. 앱이 준 값이 아니라 **제공자가 준 ID** 로 사람을 가른다.
2. 동의하지 않은 항목을 지어내지 않는다.
3. 토큰이 틀린 것(401)과 제공자에 닿지 못한 것(502)을 구분한다.
"""

import httpx
import pytest

from app.core.enums import AuthProvider
from app.core.exceptions import UnauthorizedError, UpstreamError
from app.domain.auth import providers


def _with_transport(monkeypatch, handler):
    """카카오 호출을 가짜 응답으로 바꾼다."""
    original = httpx.AsyncClient

    def factory(*args, **kwargs):
        kwargs["transport"] = httpx.MockTransport(handler)
        return original(*args, **kwargs)

    monkeypatch.setattr(providers.httpx, "AsyncClient", factory)


@pytest.mark.asyncio
async def test_kakao_reads_id_and_profile(monkeypatch):
    def handler(request):
        assert request.headers["Authorization"] == "Bearer tok"
        return httpx.Response(
            200,
            json={
                "id": 1234567890,
                "kakao_account": {
                    "email": "kakao@example.com",
                    "profile": {"nickname": "철"},
                },
            },
        )

    _with_transport(monkeypatch, handler)
    identity = await providers.verify(AuthProvider.KAKAO, "tok")

    assert identity.provider is AuthProvider.KAKAO
    # 숫자로 오지만 문자열로 다룬다 — 계정 키이므로 형이 흔들리면 안 된다.
    assert identity.provider_user_id == "1234567890"
    assert identity.nickname == "철"
    assert identity.email == "kakao@example.com"


@pytest.mark.asyncio
async def test_kakao_without_consent_gives_no_email(monkeypatch):
    """동의하지 않은 항목은 아예 오지 않는다. 없으면 없는 대로 둔다."""

    def handler(request):
        return httpx.Response(200, json={"id": 42})

    _with_transport(monkeypatch, handler)
    identity = await providers.verify(AuthProvider.KAKAO, "tok")

    assert identity.provider_user_id == "42"
    assert identity.nickname is None
    assert identity.email is None


@pytest.mark.asyncio
async def test_kakao_rejects_bad_token(monkeypatch):
    def handler(request):
        return httpx.Response(401, json={"msg": "invalid token"})

    _with_transport(monkeypatch, handler)
    with pytest.raises(UnauthorizedError):
        await providers.verify(AuthProvider.KAKAO, "bad")


@pytest.mark.asyncio
async def test_kakao_outage_is_not_a_login_failure(monkeypatch):
    """제공자가 죽은 것을 "로그인 실패" 로 말하면 사용자가 비밀번호를 의심한다."""

    def handler(request):
        return httpx.Response(500)

    _with_transport(monkeypatch, handler)
    with pytest.raises(UpstreamError):
        await providers.verify(AuthProvider.KAKAO, "tok")


@pytest.mark.asyncio
async def test_kakao_unreachable_is_upstream(monkeypatch):
    def handler(request):
        raise httpx.ConnectError("no route")

    _with_transport(monkeypatch, handler)
    with pytest.raises(UpstreamError):
        await providers.verify(AuthProvider.KAKAO, "tok")


@pytest.mark.asyncio
async def test_kakao_response_without_id_is_upstream(monkeypatch):
    """ID 가 없으면 계정을 가를 수 없다. 임의의 값을 만들지 않는다."""

    def handler(request):
        return httpx.Response(200, json={"kakao_account": {}})

    _with_transport(monkeypatch, handler)
    with pytest.raises(UpstreamError):
        await providers.verify(AuthProvider.KAKAO, "tok")


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "provider", [AuthProvider.GOOGLE, AuthProvider.APPLE, AuthProvider.DEVICE]
)
async def test_unsupported_providers_are_refused(provider):
    """붙이지 않은 제공자를 성공으로 처리하지 않는다."""
    with pytest.raises(UnauthorizedError):
        await providers.verify(provider, "tok")
