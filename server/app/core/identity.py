"""호출자 식별.

`Authorization: Bearer <token>` 의 세션으로 판정한다. 토큰이 없으면 **게스트**이며 기본
가구를 쓴다 — 로그인 없이 둘러보는 경로를 유지하기 위한 것이고, 그 가구에는 시연 데이터만
둔다.

WARNING: 이전 판본은 `X-User-Id`·`X-Household-Id` 헤더를 검증 없이 믿었다. 계정마다 다른
가구를 갖게 된 뒤로는 그 헤더 하나로 남의 냉장고를 읽을 수 있으므로 **더 이상 읽지
않는다.** 가구를 지정하는 유일한 방법은 로그인이다.

CAUTION: 아직 남은 것 — 세션 토큰은 HTTPS 가 아니면 그대로 노출된다. 공개 배포 전에
전송 구간 암호화를 확인한다. 게스트가 쓰는 기본 가구는 누구나 읽고 쓸 수 있다.
"""

from dataclasses import dataclass
from typing import Annotated

from fastapi import Depends, Header
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.core.database import get_session
from app.core.exceptions import UnauthorizedError


@dataclass(frozen=True, slots=True)
class Caller:
    """요청을 보낸 주체.

    Attributes:
        household_id: 데이터를 읽고 쓸 가구.
        user_id: 로그인한 사용자. 게스트면 `None`.
    """

    household_id: int
    user_id: int | None

    @property
    def is_guest(self) -> bool:
        return self.user_id is None


def bearer_token(authorization: str | None) -> str | None:
    """`Authorization` 헤더에서 토큰을 꺼낸다. 형식이 아니면 `None`.

    헤더 앞뒤와 구분 공백을 정리한다 — 프록시가 공백을 덧붙여도 로그인이 풀리면 안 된다.
    """
    if not authorization:
        return None
    scheme, _, value = authorization.strip().partition(" ")
    if scheme.lower() != "bearer" or not value.strip():
        return None
    return value.strip()


async def get_caller(
    settings: Annotated[Settings, Depends(get_settings)],
    session: Annotated[AsyncSession, Depends(get_session)],
    authorization: Annotated[str | None, Header(alias="Authorization")] = None,
) -> Caller:
    """세션 토큰으로 호출자를 판정한다.

    토큰이 **없으면** 게스트로 기본 가구를 쓴다. 토큰이 **있는데 유효하지 않으면**
    401 을 올린다 — 만료된 토큰을 조용히 게스트로 떨어뜨리면, 사용자는 자기 냉장고를
    보고 있다고 믿으면서 남의 데이터를 본다.
    """
    token = bearer_token(authorization)
    if token is None:
        return Caller(household_id=settings.default_household_id, user_id=None)

    # 순환 임포트를 피해 함수 안에서 읽는다 — 도메인이 core 를 임포트한다.
    from app.domain.auth import service as auth_service

    user = await auth_service.resolve(session, token)
    if user is None:
        raise UnauthorizedError(
            "session token is unknown, expired or revoked",
            message_key="error.session_expired",
        )
    return Caller(household_id=user.household_id, user_id=user.user_id)


async def require_user(caller: Annotated[Caller, Depends(get_caller)]) -> Caller:
    """로그인이 반드시 필요한 엔드포인트용.

    게스트를 막는다. 재고 조회처럼 로그인 없이 되는 경로에는 쓰지 않는다.
    """
    if caller.is_guest:
        raise UnauthorizedError("this endpoint requires a signed-in user")
    return caller


async def get_token(
    authorization: Annotated[str | None, Header(alias="Authorization")] = None,
) -> str:
    """토큰 원문이 필요한 엔드포인트용. 로그아웃이 쓴다."""
    token = bearer_token(authorization)
    if token is None:
        raise UnauthorizedError("missing bearer token")
    return token


CallerDep = Annotated[Caller, Depends(get_caller)]
UserDep = Annotated[Caller, Depends(require_user)]
TokenDep = Annotated[str, Depends(get_token)]
