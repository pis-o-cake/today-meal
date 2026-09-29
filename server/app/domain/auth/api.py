"""인증 API. `/api/auth` 에 마운트된다.

이메일·비밀번호 가입과 로그인, 로그아웃, 내 계정 조회를 제공한다.

로그인은 **기능을 막는 관문이 아니다.** 토큰 없이 부르면 게스트로 기본 가구를 쓰며
재고 조회와 명령이 모두 동작한다. 로그인은 자기 가구를 갖기 위한 것이다.

소셜 로그인(카카오·Google·Apple)은 아직 연동하지 않았다. 제공자 토큰을 검증할 수
없으므로 성공으로 처리하지 않고 501 을 돌려준다.
"""

from typing import Annotated

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.exceptions import UnauthorizedError
from app.core.identity import CallerDep, TokenDep
from app.core.pending import not_implemented
from app.domain.auth import service
from app.domain.auth.models import AppUser
from app.domain.auth.schemas import SessionRead, SignInRequest, SignUpRequest, UserRead

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


@router.post("/sign-in/{provider}", summary="간편 로그인 — 미연동")
async def sign_in_with_provider(provider: str) -> dict[str, object]:
    """카카오·Google·Apple 로그인.

    CAUTION: 제공자 토큰을 검증할 수단이 없어 구현하지 않았다. 빈 성공을 돌려주면 앱이
    인증된 것으로 착각하므로 501 을 돌려준다.
    """
    raise not_implemented("S-15", "F-22")
