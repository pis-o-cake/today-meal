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

    # 화면이 등급을 다시 계산하지 않도록 서버가 담아 보낸다. 앱에 기준을 두면 화면마다
    # 다른 말을 한다.
    freshness: str = Field(
        default="unknown", description="fresh · soon · urgent · expired · unknown"
    )
    days_left: int | None = Field(default=None, description="표시기한까지 남은 날. 지났으면 음수")
    expiry_kind: str | None = Field(default=None, description="등급 판정에 쓴 기한 종류")
    # IMPORTANT: 잔량 미확인을 신선도 등급에 섞지 않는다. 별도 신호로 둔다.
    quantity_uncertain: bool = Field(
        default=False, description="잔량을 모르거나 추정인지. 숫자를 지어내지 않는다"
    )


class PriorityBatchRead(BaseModel):
    """먼저 확인할 재료 한 줄.

    `reason` 과 `expiry_kind` 를 함께 돌려주는 이유는 화면이 **무엇 때문인지 밝혀야** 하기
    때문이다. 색만으로 상태를 구분하지 않는다.
    """

    model_config = ConfigDict(from_attributes=True)

    batch: BatchRead
    reason: str = Field(description="expired · expiring · opened · quantity_unknown")
    days_left: int | None = Field(default=None, description="표시기한까지 남은 날. 지났으면 음수")
    expiry_kind: str | None = Field(default=None, description="판정에 쓴 기한 종류")
    is_cookable: bool = Field(
        description="오늘 요리 후보로 쓸 수 있는지. 기한이 지난 항목은 거짓"
    )


class ConditionRead(BaseModel):
    """냉장고 전체 컨디션.

    화면 맨 위에 한 낱말로 뜬다. 계산은 서버가 하고 앱은 담기만 한다.
    """

    model_config = ConfigDict(from_attributes=True)

    condition: str = Field(description="relaxed · attention · urgent")
    urgent_count: int = Field(description="오늘·내일 안에 써야 하는 묶음 수")
    soon_count: int
    expired_count: int
    unknown_quantity_count: int = Field(
        description="잔량을 모르는 묶음 수. 신선도 등급과 섞지 않는다"
    )
    total_count: int
