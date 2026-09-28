"""표준 재료 스키마."""

from pydantic import BaseModel, ConfigDict, Field


class IngredientRead(BaseModel):
    """재료 사전 항목."""

    model_config = ConfigDict(from_attributes=True)

    ingredient_id: int
    canonical_name: str
    aliases: list[str] = Field(description="음성 표현. 대파와 파를 같은 재료로 잇는다")
    category: str | None = None
    default_unit: str | None = None
    is_pantry_staple: bool
