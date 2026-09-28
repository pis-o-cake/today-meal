"""부족 재료와 외부 검색 연결. 추가 범위."""

from decimal import Decimal

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    ForeignKey,
    Identity,
    Index,
    Numeric,
    String,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.core.enums import ShoppingStatus
from app.core.models import Base, TimestampMixin, enum_check


class ShoppingItem(Base, TimestampMixin):
    """장보기 한 줄.

    `needs_confirm` 이 참이면 `shortage_quantity` 를 NULL 로 둔다. 숫자를 지어내는 것보다 확인을
    요청하는 편이 낫다.

    IMPORTANT: `status` 가 `purchased` 가 되어도 **재고는 바뀌지 않는다.** 입고는 "버터 200g
    왔어"라는 별도 발화로만 일어난다.
    """

    __tablename__ = "shopping_item"
    __table_args__ = (
        CheckConstraint(
            "shortage_quantity IS NULL OR shortage_quantity >= 0",
            name="ck_shopping_item_shortage_non_negative",
        ),
        enum_check("status", ShoppingStatus, "status"),
        Index("ix_shopping_item_household_id_status", "household_id", "status"),
    )

    shopping_item_id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    household_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("household.household_id", ondelete="CASCADE"), nullable=False
    )
    ingredient_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("ingredient.ingredient_id")
    )
    raw_name: Mapped[str] = mapped_column(String(100), nullable=False)
    required_quantity: Mapped[Decimal | None] = mapped_column(Numeric(10, 3))
    available_quantity: Mapped[Decimal | None] = mapped_column(Numeric(10, 3))
    shortage_quantity: Mapped[Decimal | None] = mapped_column(Numeric(10, 3))
    unit: Mapped[str | None] = mapped_column(String(20))
    needs_confirm: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("false")
    )
    # 문자열 FK. menu 도메인을 Python 수준에서 import 하지 않는다.
    source_recipe_id: Mapped[int | None] = mapped_column(BigInteger, ForeignKey("recipe.recipe_id"))
    search_query: Mapped[str | None] = mapped_column(String(200))
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, server_default=ShoppingStatus.PENDING.value
    )
