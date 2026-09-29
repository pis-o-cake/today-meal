"""사용자와 세션 조회·저장.

쿼리만 담는다. 비밀번호 검사와 세션 수명 판정은 `service.py` 가 한다.
"""

from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.auth.models import AppUser, UserSession
from app.domain.household.models import Household


async def find_user_by_email(session: AsyncSession, email: str) -> AppUser | None:
    """이메일로 계정을 찾는다. 대소문자를 구분하지 않는다."""
    result = await session.execute(
        select(AppUser).where(AppUser.email == email.strip().lower())
    )
    return result.scalar_one_or_none()


async def find_user_by_provider(
    session: AsyncSession, *, provider: str, provider_user_id: str
) -> AppUser | None:
    """제공자 ID 로 계정을 찾는다.

    이메일이 아니라 이 쌍이 계정을 가른다 — 카카오 계정의 이메일은 바뀔 수도, 없을
    수도 있지만 제공자 안의 ID 는 변하지 않는다.
    """
    result = await session.execute(
        select(AppUser).where(
            AppUser.provider == provider,
            AppUser.provider_user_id == provider_user_id,
        )
    )
    return result.scalar_one_or_none()


async def create_social_user(
    session: AsyncSession,
    *,
    household_id: int,
    provider: str,
    provider_user_id: str,
    nickname: str,
    email: str | None,
) -> AppUser:
    """소셜 계정을 만든다. 비밀번호가 없다.

    이메일은 제공자가 준 경우에만 담는다. 이미 다른 계정이 쓰는 이메일이면 비워 둔다 —
    유일 제약에 걸려 가입 자체가 막히면 안 된다.
    """
    taken = email is not None and await find_user_by_email(session, email) is not None
    user = AppUser(
        household_id=household_id,
        provider=provider,
        provider_user_id=provider_user_id,
        email=None if taken else (email.strip().lower() if email else None),
        password_hash=None,
        display_name=nickname,
    )
    session.add(user)
    await session.flush()
    return user


async def create_household(session: AsyncSession, name: str) -> Household:
    """가입한 사람의 가구를 만든다.

    기본 가구에 묶지 않는 이유는, 그러면 가입한 사람들이 같은 냉장고를 함께 보기
    때문이다. 가구 공유는 별도 초대 흐름이 있어야 한다.
    """
    household = Household(name=name)
    session.add(household)
    await session.flush()
    return household


async def create_user(
    session: AsyncSession,
    *,
    household_id: int,
    email: str,
    password_hash: str,
    nickname: str,
    provider: str,
) -> AppUser:
    user = AppUser(
        household_id=household_id,
        provider=provider,
        provider_user_id=email.strip().lower(),
        email=email.strip().lower(),
        password_hash=password_hash,
        display_name=nickname,
    )
    session.add(user)
    await session.flush()
    return user


async def create_session(
    session: AsyncSession,
    *,
    user_id: int,
    token_hash: str,
    expires_at: datetime,
) -> UserSession:
    row = UserSession(user_id=user_id, token_hash=token_hash, expires_at=expires_at)
    session.add(row)
    await session.flush()
    return row


async def find_live_session(
    session: AsyncSession, token_hash: str
) -> tuple[UserSession, AppUser] | None:
    """살아 있는 세션과 그 사용자.

    만료됐거나 로그아웃한 세션은 없는 것으로 다룬다 — 호출자가 그 차이를 알아야 할
    이유가 없고, 구분해 돌려주면 토큰의 존재 여부가 드러난다.
    """
    result = await session.execute(
        select(UserSession, AppUser)
        .join(AppUser, AppUser.user_id == UserSession.user_id)
        .where(
            UserSession.token_hash == token_hash,
            UserSession.revoked_at.is_(None),
            UserSession.expires_at > datetime.now(UTC),
        )
    )
    row = result.first()
    return (row[0], row[1]) if row else None


async def revoke_session(session: AsyncSession, token_hash: str) -> bool:
    """세션을 끝낸다. 이미 없거나 끝난 세션이면 거짓을 돌려준다."""
    found = await find_live_session(session, token_hash)
    if found is None:
        return False
    found[0].revoked_at = datetime.now(UTC)
    return True


async def touch(session: AsyncSession, row: UserSession, user: AppUser) -> None:
    """마지막 사용 시각을 남긴다. 버려진 세션을 골라내는 근거다."""
    now = datetime.now(UTC)
    row.last_used_at = now
    user.last_signed_in_at = now
