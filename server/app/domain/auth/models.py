"""사용자 식별. 추가 범위.

**보안은 전부 배제했다.** 이 테이블에 **없는 것이 설계의 요점이다** — 비밀번호·해시·솔트·토큰·
세션·만료·역할·권한이 전부 없다. 근거는 `docs/design/0001-mvp-technical-design.md` 의
「인증 — 하지 않는다」에 있다.

CAUTION: 이 상태로 공개 배포하지 않는다.
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
from app.core.models import Base, TimestampMixin, enum_check


class AppUser(Base, TimestampMixin):
    """간편 로그인으로 식별된 사용자.

    세션 테이블이 없는 이유는 세션이 없기 때문이다. 요청마다 `X-User-Id` 헤더로 식별하고,
    헤더가 없으면 기본 가구로 처리한다.
    """

    __tablename__ = "app_user"
    __table_args__ = (
        UniqueConstraint(
            "provider", "provider_user_id", name="uq_app_user_provider_provider_user_id"
        ),
        enum_check("provider", AuthProvider, "provider"),
    )

    user_id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    household_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("household.household_id", ondelete="CASCADE"), nullable=False
    )
    provider: Mapped[str] = mapped_column(String(20), nullable=False)
    # WARNING: 이 값을 검증하지 않는다. 서명도 만료도 확인하지 않고 그대로 신뢰한다.
    provider_user_id: Mapped[str] = mapped_column(String(100), nullable=False)
    display_name: Mapped[str | None] = mapped_column(String(50))
    last_signed_in_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
