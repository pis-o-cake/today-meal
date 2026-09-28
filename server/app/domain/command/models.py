"""발화 하나의 해석과 수량 변경 원장.

이 도메인은 데이터가 아니라 **판정**을 갖는다. 모델의 출력은 실행 제안이며, 서버 검증을 통과한
뒤에만 재고가 바뀐다.
"""

from decimal import Decimal
from typing import Any
from uuid import UUID as PyUUID

from sqlalchemy import (
    BigInteger,
    ForeignKey,
    Identity,
    Index,
    Integer,
    Numeric,
    String,
    Text,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.enums import ChangeAction, CommandIntent, CommandStatus, QuantityCertainty
from app.core.models import Base, CreatedAtMixin, TimestampMixin, enum_check


class Command(Base, TimestampMixin):
    """발화 하나.

    IMPORTANT: `command_id` 를 앱이 만들어 보내고 그것을 PK 로 쓴다. 네트워크 재시도는 PK
    충돌이 되어 `INSERT … ON CONFLICT DO NOTHING` 으로 자연히 막힌다. 서버가 ID 를 만들면
    같은 발화의 재시도를 구분할 방법이 없다.
    """

    __tablename__ = "command"
    __table_args__ = (
        enum_check("intent", CommandIntent, "intent"),
        enum_check("status", CommandStatus, "status"),
        Index("ix_command_household_id_created_at", "household_id", "created_at"),
        Index("ix_command_target_command_id", "target_command_id"),
    )

    command_id: Mapped[PyUUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    household_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("household.household_id", ondelete="CASCADE"), nullable=False
    )
    utterance: Mapped[str] = mapped_column(Text, nullable=False)
    intent: Mapped[str] = mapped_column(
        String(20), nullable=False, server_default=CommandIntent.UNKNOWN.value
    )
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, server_default=CommandStatus.PENDING.value
    )
    proposal: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    validation_error: Mapped[str | None] = mapped_column(Text)
    clarification_question: Mapped[str | None] = mapped_column(Text)
    spoken_response: Mapped[str | None] = mapped_column(Text)
    target_command_id: Mapped[PyUUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("command.command_id")
    )
    llm_model: Mapped[str | None] = mapped_column(String(50))
    prompt_version: Mapped[str | None] = mapped_column(String(20))
    latency_ms: Mapped[int | None] = mapped_column(Integer)


class ChangeEvent(Base, CreatedAtMixin):
    """수량 변경 원장. append-only.

    정정과 취소는 행을 고치지 않고 역산 행을 **추가한다.** `UPDATE` 나 `DELETE` 를 하지 않는다.

    `CONSUME` 과 `ADJUST` 를 다른 `action` 으로 둔 것이 F-08 의 완료 기준이다 — "두 개 썼어"와
    "두 개 남았어"는 결과 잔량이 같아도 다른 사실이고 이력에서 구분되어야 한다.
    """

    __tablename__ = "change_event"
    __table_args__ = (
        enum_check("action", ChangeAction, "action"),
        enum_check("certainty", QuantityCertainty, "certainty"),
        Index("ix_change_event_batch_id_created_at", "batch_id", "created_at"),
        Index("ix_change_event_command_id", "command_id"),
    )

    change_event_id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    command_id: Mapped[PyUUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("command.command_id"), nullable=False
    )
    batch_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("ingredient_batch.batch_id"), nullable=False
    )
    action: Mapped[str] = mapped_column(String(20), nullable=False)
    quantity_delta: Mapped[Decimal | None] = mapped_column(Numeric(10, 3))
    quantity_before: Mapped[Decimal | None] = mapped_column(Numeric(10, 3))
    quantity_after: Mapped[Decimal | None] = mapped_column(Numeric(10, 3))
    unit: Mapped[str | None] = mapped_column(String(20))
    certainty: Mapped[str] = mapped_column(
        String(20), nullable=False, server_default=QuantityCertainty.EXACT.value
    )
    reverses_event_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("change_event.change_event_id")
    )
    note: Mapped[str | None] = mapped_column(Text)
