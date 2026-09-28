"""메뉴 추천 스키마."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class IngredientCheckRead(BaseModel):
    """레시피 재료 한 줄의 재고 대조 결과."""

    model_config = ConfigDict(from_attributes=True)

    name: str
    required_amount: str | None = Field(default=None, description="필요량. 모르면 null")
    unit: str | None = None
    is_essential: bool = Field(description="없으면 요리가 성립하지 않는 재료인지")
    status: str = Field(description="have · needs_check · missing")


class MenuSuggestionRead(BaseModel):
    """추천 메뉴 카드 하나.

    `availability` 가 `ready` 가 아니면 '지금 바로 만들기' 에 올리지 않는다. 필수 재료가
    없는 메뉴를 가능하다고 표시하지 않는 것이 F-13 의 완료 기준이다.
    """

    model_config = ConfigDict(from_attributes=True)

    suggestion_id: int
    recipe_id: int
    name: str
    rank_order: int
    servings: int
    estimated_minutes: int | None = Field(
        default=None, description="추정치. 조리 환경에 따라 달라진다"
    )
    reason: str | None = None
    availability: str = Field(description="ready · needs_check · needs_purchase")
    priority_ingredients: list[str] = Field(
        default_factory=list, description="먼저 쓰는 재료"
    )
    missing_ingredients: list[str] = Field(default_factory=list)
    uncertain_ingredients: list[str] = Field(
        default_factory=list, description="양을 확인해야 하는 재료"
    )


class RecipeStep(BaseModel):
    """조리 단계 하나."""

    model_config = ConfigDict(from_attributes=True)

    order: int
    text: str


class MenuDetailRead(BaseModel):
    """메뉴 상세.

    `servings` 로 환산한 분량을 돌려주며, 분량을 모르는 재료는 환산하지 않고 `null` 로 둔다.
    조회만으로 재고를 바꾸지 않는다.
    """

    model_config = ConfigDict(from_attributes=True)

    recipe_id: int
    name: str
    servings: int
    base_servings: int
    estimated_minutes: int | None = None
    ingredients: list[IngredientCheckRead] = Field(default_factory=list)
    steps: list[RecipeStep] = Field(default_factory=list)
