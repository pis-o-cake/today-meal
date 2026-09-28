"""가구 설정 스키마."""

from pydantic import BaseModel, ConfigDict, Field


class HouseholdRead(BaseModel):
    """가구 설정 조회 응답."""

    model_config = ConfigDict(from_attributes=True)

    household_id: int
    name: str | None = None
    timezone: str = Field(description="발화 시점 해석 기준")
    default_servings: int
    tools: list[str]
    expiry_alert_days: list[int] = Field(description="기한 알림 시점(D-n)")
