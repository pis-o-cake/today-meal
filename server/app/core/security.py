"""비밀번호 해시와 세션 토큰.

암호 관련 값을 다루는 유일한 자리다. 도메인 코드가 직접 해시를 만들거나 토큰을 비교하지
않게 한다 — 흩어지면 한 곳만 고쳐도 다른 곳이 남는다.

CAUTION: **비밀번호 원문과 세션 토큰 원문을 로그에 남기지 않는다.** 이 모듈은 아무것도
로깅하지 않으며, 호출자도 반환값을 로그에 넣지 않는다.
"""

import hashlib
import secrets
from datetime import UTC, datetime, timedelta

import bcrypt

#: 세션이 유효한 기간. 조리 중에 만료되지 않을 만큼 길고, 기기를 잃었을 때 영원히
#: 살아 있지 않을 만큼 짧게 둔다.
SESSION_LIFETIME = timedelta(days=30)

#: 토큰의 바이트 수. URL-safe base64 로 약 43자가 된다.
_TOKEN_BYTES = 32


def hash_password(password: str) -> str:
    """비밀번호를 bcrypt 해시로 만든다.

    Args:
        password: 사용자가 입력한 원문.

    Returns:
        솔트를 포함한 bcrypt 해시 문자열.
    """
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def verify_password(password: str, password_hash: str) -> bool:
    """비밀번호가 해시와 맞는지 확인한다.

    해시 형식이 깨졌어도 예외를 올리지 않고 불일치로 다룬다 — 저장된 값이 손상된 것을
    로그인 실패와 다르게 취급할 이유가 없고, 예외가 새면 어느 계정이 손상됐는지가 드러난다.
    """
    try:
        return bcrypt.checkpw(password.encode(), password_hash.encode())
    except ValueError:
        return False


def new_session_token() -> str:
    """새 세션 토큰. **원문은 이때 한 번만 존재한다.**"""
    return secrets.token_urlsafe(_TOKEN_BYTES)


def hash_token(token: str) -> str:
    """세션 토큰의 저장용 해시.

    IMPORTANT: 토큰 원문을 DB 에 두지 않는다. DB 가 새도 그 값으로 로그인할 수 없어야 한다.
    비밀번호와 달리 SHA-256 을 쓰는 이유는, 토큰이 이미 256비트 난수라 사전 공격의 대상이
    아니고 요청마다 조회해야 해서 느린 해시를 쓸 수 없기 때문이다.
    """
    return hashlib.sha256(token.encode()).hexdigest()


def session_expiry(now: datetime | None = None) -> datetime:
    """새 세션의 만료 시각."""
    return (now or datetime.now(UTC)) + SESSION_LIFETIME
