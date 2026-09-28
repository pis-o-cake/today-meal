"""레시피와 추천 결과."""

from datetime import datetime
from decimal import Decimal
from typing import Any
from uuid import UUID as PyUUID

from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    ForeignKey,
    Identity,
    Index,
    Numeric,
    SmallInteger,
    String,
    Text,
    text,
)
from sqlalchemy.dialects.postgresql import ARRAY, JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.enums import MenuAvailability, RecipeSource
from app.core.models import Base, CreatedAtMixin, TimestampMixin, enum_check


class Recipe(Base, TimestampMixin):
    """레시피.

    조리 단계를 별도 테이블로 두지 않고 `steps` JSONB 로 둔다. 단계를 개별로 조회하거나
    검색하지 않고 항상 통째로 읽는다. 반면 재료는 재고와 조인해야 하므로 정규화한다 —
    이 비대칭이 의도다.
    """

    __tablename__ = "recipe"
    __table_args__ = (
        enum_check("source", RecipeSource, "source"),
        Index("ix_recipe_household_id_source", "household_id", "source"),
    )

    recipe_id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    household_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("household.household_id", ondelete="CASCADE")
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    source: Mapped[str] = mapped_column(String(20), nullable=False)
    base_servings: Mapped[int] = mapped_column(
        SmallInteger, nullable=False, server_default=text("2")
    )
    estimated_minutes: Mapped[int | None] = mapped_column(SmallInteger)
    steps: Mapped[list[dict[str, Any]]] = mapped_column(
        JSONB, nullable=False, server_default=text("'[]'::jsonb")
    )
    note: Mapped[str | None] = mapped_column(Text)
    # 문자열 FK 를 써서 Python 수준 의존을 만들지 않는다.
    # video 도메인을 지워도 이 모듈은 import 된다.
    video_recipe_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("video_recipe.video_recipe_id")
    )


class RecipeIngredient(Base, CreatedAtMixin):
    """레시피의 재료 한 줄.

    `is_essential` 이 F-13 의 완료 기준을 지탱한다 — 필수 재료가 없는 메뉴를 '지금 가능'으로
    표시하는 사례가 0건이어야 하고 그 판정 근거가 이 컬럼이다.
    """

    __tablename__ = "recipe_ingredient"
    __table_args__ = (Index("ix_recipe_ingredient_recipe_id", "recipe_id"),)

    recipe_ingredient_id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    recipe_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("recipe.recipe_id", ondelete="CASCADE"), nullable=False
    )
    ingredient_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("ingredient.ingredient_id")
    )
    raw_name: Mapped[str] = mapped_column(String(100), nullable=False)
    quantity: Mapped[Decimal | None] = mapped_column(Numeric(10, 3))
    unit: Mapped[str | None] = mapped_column(String(20))
    is_essential: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("true"))
    is_amount_unknown: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("false")
    )


class MenuSuggestion(Base, CreatedAtMixin):
    """추천 결과와 실제 조리 확인.

    `consumption_applied` 가 중복 차감을 막는다. `availability` 는 추천 시점의 스냅샷이며
    **보유 여부의 정본이 아니다** — 화면에 그릴 때는 그 시점의 재고로 다시 계산한다.
    """

    __tablename__ = "menu_suggestion"
    __table_args__ = (
        enum_check("availability", MenuAvailability, "availability"),
        Index("ix_menu_suggestion_household_id_created_at", "household_id", "created_at"),
    )

    suggestion_id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    household_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("household.household_id", ondelete="CASCADE"), nullable=False
    )
    command_id: Mapped[PyUUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("command.command_id")
    )
    recipe_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("recipe.recipe_id"), nullable=False
    )
    rank_order: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    reason: Mapped[str | None] = mapped_column(Text)
    servings: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    priority_ingredient_ids: Mapped[list[int]] = mapped_column(
        ARRAY(BigInteger), nullable=False, server_default=text("'{}'")
    )
    availability: Mapped[str] = mapped_column(String(20), nullable=False)
    cooked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    consumption_applied: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("false")
    )
