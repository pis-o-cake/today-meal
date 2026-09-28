"""재고 묶음과 그 날짜·상태.

같은 두부라도 기한이나 개봉 상태가 다르면 다른 묶음이다.
"""

from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Identity,
    Index,
    Numeric,
    String,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.enums import (
    DateKind,
    DateSource,
    QuantityCertainty,
    StateEventKind,
    StorageLocation,
)
from app.core.models import Base, CreatedAtMixin, TimestampMixin, enum_check


class IngredientBatch(Base, TimestampMixin):
    """재료 묶음.

    잔량을 이 테이블의 현재값과 `change_event` 의 이력 **둘 다** 갖는다. 현재값만 두면 되돌릴 수
    없고, 이벤트만 두면 대시보드 조회마다 전체를 재생해야 한다. 둘이 어긋나면 이벤트가 정본이다.
    """

    __tablename__ = "ingredient_batch"
    __table_args__ = (
        # IMPORTANT: 음수 잔량 방어를 코드가 아니라 DB 가 막는다.
        CheckConstraint(
            "quantity IS NULL OR quantity >= 0",
            name="ck_ingredient_batch_quantity_non_negative",
        ),
        CheckConstraint(
            "quantity IS NOT NULL OR qualitative_amount IS NOT NULL",
            name="ck_ingredient_batch_amount_present",
        ),
        CheckConstraint(
            "quantity IS NULL OR unit IS NOT NULL", name="ck_ingredient_batch_unit_present"
        ),
        enum_check("quantity_certainty", QuantityCertainty, "quantity_certainty"),
        enum_check("storage_location", StorageLocation, "storage_location"),
        Index("ix_ingredient_batch_household_active", "household_id", "deleted_at"),
        Index("ix_ingredient_batch_household_ingredient", "household_id", "ingredient_id"),
    )

    batch_id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    household_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("household.household_id", ondelete="CASCADE"), nullable=False
    )
    ingredient_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("ingredient.ingredient_id"), nullable=False
    )
    raw_name: Mapped[str] = mapped_column(String(100), nullable=False)
    quantity: Mapped[Decimal | None] = mapped_column(Numeric(10, 3))
    unit: Mapped[str | None] = mapped_column(String(20))
    qualitative_amount: Mapped[str | None] = mapped_column(String(20))
    quantity_certainty: Mapped[str] = mapped_column(
        String(20), nullable=False, server_default=QuantityCertainty.EXACT.value
    )
    storage_location: Mapped[str] = mapped_column(
        String(20), nullable=False, server_default=StorageLocation.UNKNOWN.value
    )
    split_from_batch_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("ingredient_batch.batch_id")
    )
    last_confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    depleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    dates: Mapped[list["BatchDate"]] = relationship(
        back_populates="batch", cascade="all, delete-orphan", lazy="selectin"
    )
    state_events: Mapped[list["BatchStateEvent"]] = relationship(
        back_populates="batch", cascade="all, delete-orphan"
    )


class BatchDate(Base, TimestampMixin):
    """묶음의 날짜 정보. 종류마다 한 행.

    행이 없으면 그 종류의 정보가 없다는 뜻이고, 행이 있고 `date_value` 가 NULL 이면 종류는
    알지만 날짜를 모른다는 뜻이다. 둘을 구분해야 "날짜는 모르겠어"와 "아무 말도 안 했다"가 갈린다.
    """

    __tablename__ = "batch_date"
    __table_args__ = (
        UniqueConstraint("batch_id", "kind", name="uq_batch_date_batch_id_kind"),
        enum_check("kind", DateKind, "kind"),
        enum_check("source", DateSource, "source"),
        Index("ix_batch_date_kind_date_value", "kind", "date_value"),
    )

    batch_date_id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    batch_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("ingredient_batch.batch_id", ondelete="CASCADE"), nullable=False
    )
    kind: Mapped[str] = mapped_column(String(20), nullable=False)
    date_value: Mapped[date | None] = mapped_column(Date)
    is_confirmed: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("false")
    )
    source: Mapped[str] = mapped_column(
        String(20), nullable=False, server_default=DateSource.UNKNOWN.value
    )
    raw_text: Mapped[str | None] = mapped_column(String(200))
    source_image_uri: Mapped[str | None] = mapped_column(String(500))

    batch: Mapped["IngredientBatch"] = relationship(back_populates="dates")


class BatchStateEvent(Base, CreatedAtMixin):
    """수량이 아닌 상태 변화. append-only.

    `occurred_at` 을 `created_at` 과 따로 두는 이유는 "우유 어제 열었어"를 처리해야 하기
    때문이다.
    """

    __tablename__ = "batch_state_event"
    __table_args__ = (
        enum_check("kind", StateEventKind, "kind"),
        Index("ix_batch_state_event_batch_id_occurred_at", "batch_id", "occurred_at"),
    )

    state_event_id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    batch_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("ingredient_batch.batch_id", ondelete="CASCADE"), nullable=False
    )
    command_id: Mapped[str | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("command.command_id")
    )
    kind: Mapped[str] = mapped_column(String(20), nullable=False)
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    from_location: Mapped[str | None] = mapped_column(String(20))
    to_location: Mapped[str | None] = mapped_column(String(20))
    note: Mapped[str | None] = mapped_column(String(500))

    batch: Mapped["IngredientBatch"] = relationship(back_populates="state_events")
