"""영상 레시피 스키마.

IMPORTANT: 보유 여부(`status`)는 **저장하지 않고 조회 시점에 계산한다.** 저장하면 재고가 바뀐
뒤에도 옛 판정이 화면에 남는다.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class VideoIngredientRead(BaseModel):
    """영상 레시피의 재료 한 줄."""

    model_config = ConfigDict(from_attributes=True)

    name: str
    required_amount: str | None = Field(
        default=None, description="영상에 적힌 분량. 없으면 null"
    )
    unit: str | None = None
    is_essential: bool = Field(description="없으면 요리가 성립하지 않는 재료인지")
    status: str = Field(description="have · needs_check · missing. 조회 시점의 재고 판정")


class VideoStepRead(BaseModel):
    """영상 레시피의 단계 하나."""

    model_config = ConfigDict(from_attributes=True)

    order: int
    text: str
    timer_seconds: int | None = Field(
        default=None, description="영상에 적힌 시간만 담는다. 없으면 null"
    )
    timer_label: str | None = None
    ingredients: list[str] = Field(
        default_factory=list, description="이 단계에 쓰는 재료 이름"
    )


class VideoRecipeRead(BaseModel):
    """영상 하나의 정리 결과.

    `availability` 가 `ready` 가 아니어도 조리를 막지 않는다 — 영상 레시피는 사용자가 직접
    고른 것이고, 없는 재료는 화면이 알려 준다.
    """

    model_config = ConfigDict(from_attributes=True)

    video_id: str
    url: str
    title: str | None = None
    channel: str | None = None
    dish_name: str | None = None
    base_servings: int | None = None
    estimated_minutes: int | None = Field(
        default=None, description="추정치. 조리 환경에 따라 달라진다"
    )
    availability: str = Field(description="ready · needs_check · needs_purchase")
    ingredients: list[VideoIngredientRead] = Field(default_factory=list)
    steps: list[VideoStepRead] = Field(default_factory=list)
    missing_ingredients: list[str] = Field(default_factory=list)
    uncertain_ingredients: list[str] = Field(
        default_factory=list, description="양을 확인해야 하는 재료"
    )
    unresolved: list[str] = Field(
        default_factory=list, description="영상만으로 알 수 없어 확인이 필요한 것"
    )
