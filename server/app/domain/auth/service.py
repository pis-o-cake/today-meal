"""가입·로그인·로그아웃.

세션 토큰 원문은 만들 때 한 번만 존재한다. DB 에는 해시만 남으므로 잃어버리면 다시
로그인해야 한다.

IMPORTANT: 실패 이유를 **로그인과 가입에서 다르게 다룬다.**

- 가입: 이미 쓰는 이메일이면 그대로 알린다. 알리지 않으면 왜 가입이 안 되는지 알 수 없다.
- 로그인: 이메일이 없는 것과 비밀번호가 틀린 것을 **같은 응답**으로 돌려준다. 구분하면
  아무나 이메일 목록을 확인할 수 있다.
"""

from email_validator import EmailNotValidError, validate_email
from loguru import logger
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.enums import AuthProvider
from app.core.exceptions import ConflictError, UnauthorizedError
from app.core.security import (
    hash_password,
    hash_token,
    new_session_token,
    session_expiry,
    verify_password,
)
from app.domain.auth import crud, providers
from app.domain.auth.models import AppUser
from app.domain.auth.schemas import AvailabilityRead, SessionRead, UserRead


async def sign_up(
    session: AsyncSession, *, email: str, password: str, nickname: str
) -> SessionRead:
    """계정을 만들고 바로 로그인시킨다.

    가입 직후 다시 로그인하게 할 이유가 없다. 같은 트랜잭션에서 가구·사용자·세션을
    함께 만든다 — 하나라도 실패하면 반쪽짜리 계정이 남지 않는다.
    """
    normalized = email.strip().lower()
    if await crud.find_user_by_email(session, normalized) is not None:
        raise ConflictError(
            f"email already registered: {normalized}",
            message_key="error.email_taken",
        )

    household = await crud.create_household(session, name=nickname)
    user = await crud.create_user(
        session,
        household_id=household.household_id,
        email=normalized,
        password_hash=hash_password(password),
        nickname=nickname,
        provider=AuthProvider.EMAIL.value,
    )
    result = await _open_session(session, user)
    await session.commit()
    logger.info("Signed up user {} into household {}", user.user_id, household.household_id)
    return result


async def check_email(session: AsyncSession, email: str) -> AvailabilityRead:
    """이 이메일로 가입할 수 있는지.

    **아무것도 만들지 않는다.** 가입 버튼을 누르기 전에 미리 알려주기 위한 것이며,
    확인과 가입 사이에 남이 먼저 가입할 수 있으므로 가입 시점에 서버가 다시 막는다
    (DB 의 유일 제약이 최종 판정이다).

    CAUTION: 이 엔드포인트는 **가입된 이메일인지 알려준다.** 가입 화면에서 그 사실을
    숨길 수 없으므로(누르면 어차피 409) 여기서도 숨기지 않는다. 로그인 실패는 다르다 —
    거기서는 알려주지 않는다.
    """
    normalized = email.strip().lower()
    try:
        validate_email(normalized, check_deliverability=False)
    except EmailNotValidError:
        return AvailabilityRead(available=False, reason="invalid")

    taken = await crud.find_user_by_email(session, normalized) is not None
    return AvailabilityRead(
        available=not taken,
        reason="taken" if taken else "ok",
    )


async def sign_in(session: AsyncSession, *, email: str, password: str) -> SessionRead:
    """이메일과 비밀번호로 세션을 연다."""
    user = await crud.find_user_by_email(session, email)

    # 계정이 없을 때도 비밀번호를 검사한다. 바로 돌려주면 응답 시간 차이로 이메일이
    # 있는지 알 수 있다.
    stored = user.password_hash if user is not None else _DUMMY_HASH
    matched = verify_password(password, stored or _DUMMY_HASH)

    if user is None or user.password_hash is None or not matched:
        logger.info("Sign-in rejected for {}", email.strip().lower())
        raise UnauthorizedError(
            "email or password does not match",
            message_key="error.sign_in_failed",
        )

    result = await _open_session(session, user)
    await session.commit()
    logger.info("Signed in user {}", user.user_id)
    return result


async def sign_in_with_provider(
    session: AsyncSession, *, provider: AuthProvider, access_token: str
) -> SessionRead:
    """소셜 로그인. 처음이면 계정을 만들고 바로 로그인시킨다.

    **앱이 준 사용자 ID 를 믿지 않는다.** 토큰을 제공자에게 직접 물어 확인한 뒤 그
    결과의 ID 로 계정을 가른다.

    가입과 로그인을 나누지 않는다 — 제공자 로그인에서 사용자는 "가입했는지" 를 모르고,
    물어볼 것도 없다. 처음 보는 ID 면 가구와 계정을 만든다.
    """
    identity = await providers.verify(provider, access_token)

    user = await crud.find_user_by_provider(
        session,
        provider=identity.provider.value,
        provider_user_id=identity.provider_user_id,
    )
    if user is None:
        nickname = identity.nickname or _DEFAULT_NICKNAME
        household = await crud.create_household(session, name=nickname)
        user = await crud.create_social_user(
            session,
            household_id=household.household_id,
            provider=identity.provider.value,
            provider_user_id=identity.provider_user_id,
            nickname=nickname,
            email=identity.email,
        )
        logger.info(
            "Created {} account {} in household {}",
            identity.provider.value,
            user.user_id,
            household.household_id,
        )

    result = await _open_session(session, user)
    await session.commit()
    logger.info("Signed in {} user {}", identity.provider.value, user.user_id)
    return result


async def sign_out(session: AsyncSession, token: str) -> None:
    """세션을 끝낸다.

    이미 끝난 세션이어도 실패로 다루지 않는다 — 로그아웃의 목적은 '그 토큰이 더는 통하지
    않는 것'이고, 두 번 눌렀다고 오류를 보일 이유가 없다.
    """
    revoked = await crud.revoke_session(session, hash_token(token))
    await session.commit()
    if revoked:
        logger.info("Signed out one session")


async def resolve(session: AsyncSession, token: str) -> AppUser | None:
    """토큰이 가리키는 사용자. 없거나 만료·폐기됐으면 `None`."""
    found = await crud.find_live_session(session, hash_token(token))
    if found is None:
        return None
    row, user = found
    await crud.touch(session, row, user)
    await session.commit()
    return user


async def _open_session(session: AsyncSession, user: AppUser) -> SessionRead:
    token = new_session_token()
    expires_at = session_expiry()
    await crud.create_session(
        session,
        user_id=user.user_id,
        token_hash=hash_token(token),
        expires_at=expires_at,
    )
    return SessionRead(
        access_token=token,
        expires_at=expires_at,
        user=UserRead.model_validate(user),
    )


#: 제공자가 닉네임을 주지 않았을 때. 사용자가 마이페이지에서 바꾼다.
_DEFAULT_NICKNAME = "우리 집"

#: 계정이 없을 때도 같은 비용을 치르기 위한 해시. 어떤 비밀번호와도 맞지 않는다.
_DUMMY_HASH = hash_password("today-meal-timing-guard")
