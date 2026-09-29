"""인증 API. `/api/auth` 에 마운트된다.

이메일·비밀번호 가입과 로그인, 로그아웃, 내 계정 조회를 제공한다.

로그인은 **기능을 막는 관문이 아니다.** 토큰 없이 부르면 게스트로 기본 가구를 쓰며
재고 조회와 명령이 모두 동작한다. 로그인은 자기 가구를 갖기 위한 것이다.

소셜 로그인은 카카오만 붙었다. 앱이 받은 제공자 토큰을 서버가 **제공자에게 직접 물어**
확인한다. Google·Apple 은 키가 없어 501 이며, 빈 성공을 돌려주지 않는다.
"""

from typing import Annotated

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.enums import AuthProvider
from app.core.exceptions import UnauthorizedError
from app.core.identity import CallerDep, TokenDep
from app.core.pending import not_implemented
from app.domain.auth import service
from app.domain.auth.models import AppUser
from app.domain.auth.schemas import (
    AvailabilityRead,
    ProviderSignInRequest,
    SessionRead,
    SignInRequest,
    SignUpRequest,
    UserRead,
)

router = APIRouter()

SessionDep = Annotated[AsyncSession, Depends(get_session)]


@router.post(
    "/sign-up",
    response_model=SessionRead,
    status_code=status.HTTP_201_CREATED,
    summary="이메일 가입",
)
async def sign_up(body: SignUpRequest, session: SessionDep) -> SessionRead:
    """계정과 가구를 만들고 바로 로그인시킨다.

    새 가구로 시작하므로 **냉장고가 비어 있다.** 게스트로 둘러보던 재고는 기본 가구의
    것이며 가입한 계정으로 옮겨오지 않는다 — 가구 간 이관 정책은 따로 정한다.

    비밀번호는 영문·숫자를 포함한 8자 이상이어야 한다. 이미 가입된 이메일이면 409 다.
    """
    return await service.sign_up(
        session,
        email=body.email,
        password=body.password,
        nickname=body.nickname,
    )


@router.get(
    "/available",
    response_model=AvailabilityRead,
    summary="이메일 중복 확인",
)
async def check_email(
    session: SessionDep,
    email: Annotated[str, Query(description="확인할 이메일")],
) -> AvailabilityRead:
    """가입 전에 이 이메일을 쓸 수 있는지 확인한다.

    **확정이 아니다.** 확인과 가입 사이에 남이 먼저 가입할 수 있으므로 가입 시점에
    서버가 다시 막는다. 여기서 available 이 참이어도 `/sign-up` 이 409 를 줄 수 있다.

    닉네임은 확인하지 않는다 — 중복을 허용하므로 막을 것이 없다.
    """
    return await service.check_email(session, email)


@router.post("/sign-in", response_model=SessionRead, summary="이메일 로그인")
async def sign_in(body: SignInRequest, session: SessionDep) -> SessionRead:
    """세션을 연다.

    이메일이 없는 것과 비밀번호가 틀린 것을 **같은 401 로** 돌려준다. 구분하면 아무나
    가입된 이메일인지 확인할 수 있다.

    `access_token` 은 이 응답에만 있다. 서버는 해시만 갖고 있어 다시 알려줄 수 없다.
    """
    return await service.sign_in(session, email=body.email, password=body.password)


@router.post(
    "/sign-out",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="로그아웃",
)
async def sign_out(token: TokenDep, session: SessionDep) -> None:
    """이 토큰의 세션을 끝낸다. 다른 기기의 세션은 그대로 둔다."""
    await service.sign_out(session, token)


@router.get("/me", response_model=UserRead, summary="내 계정")
async def read_me(caller: CallerDep, session: SessionDep) -> UserRead:
    """로그인한 사람. 게스트면 401 이다.

    앱이 저장해 둔 토큰이 아직 유효한지 확인하는 데 쓴다.
    """
    if caller.user_id is None:
        raise UnauthorizedError("guest has no account")
    user = await session.get(AppUser, caller.user_id)
    if user is None:
        raise UnauthorizedError("account no longer exists")
    return UserRead.model_validate(user)


@router.post(
    "/sign-in/{provider}",
    response_model=SessionRead,
    summary="간편 로그인",
)
async def sign_in_with_provider(
    provider: AuthProvider,
    body: ProviderSignInRequest,
    session: SessionDep,
) -> SessionRead:
    """제공자 토큰으로 로그인한다. 처음이면 계정을 만든다.

    **앱이 보낸 토큰을 제공자에게 직접 물어 확인한다.** 앱이 준 사용자 ID 를 믿으면
    아무나 남의 계정으로 들어올 수 있다.

    지금 붙은 것은 카카오뿐이다. Google·Apple 은 키가 없어 401 이며, 빈 성공을
    돌려주지 않는다 — 앱이 인증된 것으로 착각하면 안 된다.
    """
    if provider is AuthProvider.EMAIL:
        raise UnauthorizedError("use /sign-in for email accounts")
    if provider is not AuthProvider.KAKAO:
        raise not_implemented("S-15", "F-22")
    return await service.sign_in_with_provider(
        session, provider=provider, access_token=body.access_token
    )
