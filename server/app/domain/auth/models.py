"""사용자와 세션.

이메일·비밀번호 로그인과 세션 토큰을 담는다. 이전 판본은 `X-User-Id` 헤더를 그대로
믿었고 이 테이블에 비밀번호도 세션도 없었다. 계정마다 다른 가구를 갖게 되면서 헤더
하나로 남의 냉장고를 읽을 수 있게 되므로, 검증하는 세션을 둔다.

비밀번호 원문은 저장하지 않는다. 세션 토큰도 원문이 아니라 해시를 둔다 — 근거는
`app/core/security.py` 에 있다.
"""

from datetime import datetime

from sqlalchemy import (
    BigInteger,
    DateTime,
    ForeignKey,
    Identity,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.core.enums import AuthProvider
from app.core.models import Base, CreatedAtMixin, TimestampMixin, enum_check


class AppUser(Base, TimestampMixin):
    """계정 하나.

    한 사용자는 가구 하나에 속한다. 가입하면 그 사용자만의 가구를 만든다 — 기본 가구에
    묶으면 가입한 사람들이 같은 냉장고를 보게 된다.

    `provider` 가 `email` 이면 [email] 과 [password_hash] 가 있고 `provider_user_id` 는
    이메일과 같다. 소셜 제공자는 아직 연동하지 않았다.
    """

    __tablename__ = "app_user"
    __table_args__ = (
        UniqueConstraint(
            "provider", "provider_user_id", name="uq_app_user_provider_provider_user_id"
        ),
        UniqueConstraint("email", name="uq_app_user_email"),
        enum_check("provider", AuthProvider, "provider"),
    )

    user_id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    household_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("household.household_id", ondelete="CASCADE"), nullable=False
    )
    provider: Mapped[str] = mapped_column(String(20), nullable=False)
    provider_user_id: Mapped[str] = mapped_column(String(100), nullable=False)

    # 이메일 가입에만 있다. 소셜 계정은 제공자가 이메일을 주기 전까지 비어 있다.
    email: Mapped[str | None] = mapped_column(String(320))

    # WARNING: 해시만 담는다. 원문은 어디에도 남기지 않는다.
    password_hash: Mapped[str | None] = mapped_column(String(100))

    display_name: Mapped[str | None] = mapped_column(String(50))
    last_signed_in_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class UserSession(Base, CreatedAtMixin):
    """로그인 한 번.

    토큰을 되돌릴 수 있어야 로그아웃이 실제로 세션을 끝낸다. JWT 처럼 상태 없는 토큰을
    쓰면 로그아웃해도 만료 전까지 유효하므로, 서버가 가진 행으로 판정한다.
    """

    __tablename__ = "user_session"

    session_id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    user_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("app_user.user_id", ondelete="CASCADE"), nullable=False
    )

    # 토큰 원문이 아니라 SHA-256 해시다. 조회 키이므로 유일하다.
    token_hash: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)

    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    # 로그아웃한 시각. 있으면 만료 전이라도 쓸 수 없다.
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    last_used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
