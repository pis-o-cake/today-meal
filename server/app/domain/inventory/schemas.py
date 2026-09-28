"""재고 조회 스키마."""

from datetime import date, datetime
from decimal import Decimal

from pydantic import BaseModel, ConfigDict, Field


class BatchDateRead(BaseModel):
    """묶음의 날짜 한 줄. 종류를 보존한다."""

    model_config = ConfigDict(from_attributes=True)

    kind: str = Field(
        description="use_by · sell_by · best_before · manufactured · packed · check_reminder"
    )
    date_value: date | None = Field(default=None, description="미확인이면 null")
    is_confirmed: bool
    source: str
    raw_text: str | None = None


class BatchRead(BaseModel):
    """재고 묶음 하나."""

    model_config = ConfigDict(from_attributes=True)

    batch_id: int
    ingredient_id: int
    raw_name: str
    quantity: Decimal | None = Field(default=None, description="정성 잔량이면 null")
    unit: str | None = None
    qualitative_amount: str | None = Field(default=None, description="조금 · 반 · 많이")
    quantity_certainty: str
    storage_location: str
    last_confirmed_at: datetime | None = None
    dates: list[BatchDateRead] = Field(default_factory=list)
