"""가구와 가구별 재료 성향."""

from sqlalchemy import BigInteger, ForeignKey, Identity, Integer, SmallInteger, String, text
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.orm import Mapped, mapped_column

from app.core.enums import PreferenceKind
from app.core.models import Base, CreatedAtMixin, TimestampMixin, enum_check


class Household(Base, TimestampMixin):
    """가구 하나와 그 설정.

    MVP 는 행 하나로 운영한다. 가구 공유가 후속 범위여도 `household_id` 를 지금 두는 이유는,
    나중에 붙이면 모든 테이블과 모든 조회를 함께 고쳐야 하기 때문이다.
    """

    __tablename__ = "household"

    household_id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    name: Mapped[str | None] = mapped_column(String(50))
    timezone: Mapped[str] = mapped_column(String(50), nullable=False, server_default="Asia/Seoul")
    default_servings: Mapped[int] = mapped_column(
        SmallInteger, nullable=False, server_default=text("2")
    )
    tools: Mapped[list[str]] = mapped_column(
        ARRAY(String(30)), nullable=False, server_default=text("'{}'")
    )
    expiry_alert_days: Mapped[list[int]] = mapped_column(
        ARRAY(Integer), nullable=False, server_default=text("'{3,1,0}'")
    )


class HouseholdIngredientPreference(Base, CreatedAtMixin):
    """가구별 재료 성향.

    기피 재료와 기본 양념을 한 테이블로 합쳤다. 둘 다 `가구 × 재료` N:M 이고 구분은 `kind`
    하나다. `pantry_staple` 로 선언한 재료만 보유로 취급하고, 선언하지 않은 양념을 있다고
    가정하지 않는다.
    """

    __tablename__ = "household_ingredient_preference"
    __table_args__ = (enum_check("kind", PreferenceKind, "kind"),)

    household_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("household.household_id", ondelete="CASCADE"), primary_key=True
    )
    ingredient_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("ingredient.ingredient_id", ondelete="CASCADE"), primary_key=True
    )
    kind: Mapped[str] = mapped_column(String(20), primary_key=True)
