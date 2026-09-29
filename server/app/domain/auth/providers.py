"""소셜 제공자 토큰 검증.

앱이 보낸 토큰을 **제공자에게 직접 물어** 확인한다. 앱이 준 사용자 ID 를 그대로 믿으면
아무나 남의 계정으로 들어올 수 있다 — 그 값은 앱이 만들어 보낸 것이고, 앱은 우리가
통제하지 않는다.

IMPORTANT: 검증의 결과는 **제공자가 준 사용자 ID** 하나다. 닉네임·이메일은 참고값이며,
계정을 가르는 것은 `(provider, provider_user_id)` 다.

지금 구현된 것은 카카오뿐이다. Google·Apple 은 키가 없어 붙이지 않았다.
"""

from dataclasses import dataclass

import httpx
from loguru import logger

from app.core.enums import AuthProvider
from app.core.exceptions import UnauthorizedError, UpstreamError

#: 카카오가 액세스 토큰으로 사용자를 알려주는 곳.
_KAKAO_ME = "https://kapi.kakao.com/v2/user/me"

#: 제공자에게 물을 때의 한계. 로그인 한 번이 여기 매달리면 안 된다.
_TIMEOUT = 5.0


@dataclass(frozen=True, slots=True)
class ProviderIdentity:
    """제공자가 확인해 준 사람.

    Attributes:
        provider: 어느 제공자인지.
        provider_user_id: 그 제공자 안에서의 고유 ID. **계정을 가르는 값이다.**
        nickname: 화면에 쓸 이름. 없으면 `None`.
        email: 제공자가 준 이메일. 동의하지 않았으면 `None`.
    """

    provider: AuthProvider
    provider_user_id: str
    nickname: str | None = None
    email: str | None = None


async def verify(provider: AuthProvider, access_token: str) -> ProviderIdentity:
    """제공자 토큰을 검증하고 사람을 알아낸다.

    Raises:
        UnauthorizedError: 토큰이 유효하지 않다.
        UpstreamError: 제공자에게 닿지 못했다. **로그인 실패와 구분한다** — 사용자가
            고칠 수 있는 것이 아니라 잠시 뒤에 다시 해야 하는 상황이다.
    """
    if provider is AuthProvider.KAKAO:
        return await _verify_kakao(access_token)
    raise UnauthorizedError(f"provider not supported: {provider.value}")


async def _verify_kakao(access_token: str) -> ProviderIdentity:
    """카카오 액세스 토큰으로 사용자를 읽는다.

    토큰이 유효하지 않으면 카카오가 401 을 준다. 그대로 401 로 넘긴다.
    """
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
            response = await client.get(
                _KAKAO_ME,
                headers={"Authorization": f"Bearer {access_token}"},
            )
    except httpx.HTTPError as error:
        logger.warning("Kakao verification unreachable: {}", error)
        raise UpstreamError(f"kakao unreachable: {error}") from error

    if response.status_code == 401:
        logger.info("Kakao rejected the access token")
        raise UnauthorizedError("kakao rejected the access token")
    if response.status_code != 200:
        logger.warning("Kakao returned {}", response.status_code)
        raise UpstreamError(f"kakao returned {response.status_code}")

    body = response.json()
    user_id = body.get("id")
    if user_id is None:
        raise UpstreamError("kakao response has no id")

    # 동의하지 않은 항목은 아예 오지 않는다. 없으면 없는 대로 둔다 — 지어내지 않는다.
    account = body.get("kakao_account") or {}
    profile = account.get("profile") or {}

    return ProviderIdentity(
        provider=AuthProvider.KAKAO,
        provider_user_id=str(user_id),
        nickname=profile.get("nickname"),
        email=account.get("email"),
    )
