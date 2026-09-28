"""유튜브 영상에서 추출한 레시피. 추가 범위.

**보유 여부를 저장하지 않는다.** 저장하면 재고가 바뀐 뒤에도 옛 판정이 화면에 남는다.
분석 결과는 재사용하고 보유 여부는 조회 시점의 재고로 매번 다시 계산한다.
"""

from datetime import datetime
from typing import Any

from sqlalchemy import (
    BigInteger,
    DateTime,
    Identity,
    SmallInteger,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.core.enums import VideoInputKind, VideoRecipeStatus
from app.core.models import Base, TimestampMixin, enum_check


class VideoRecipe(Base, TimestampMixin):
    """영상 하나의 분석 결과.

    재료를 `recipe_ingredient` 처럼 정규화하지 않고 JSONB 로 둔다. 원문을 그대로 보존해야 하고
    미확인 분량이 섞여 있어 정규화 이득이 작다.

    WARNING: `timestamps` 는 모델 추출값이다. 검증 전에는 정확성을 보장하지 않는다.
    """

    __tablename__ = "video_recipe"
    __table_args__ = (
        UniqueConstraint(
            "video_id", "prompt_version", name="uq_video_recipe_video_id_prompt_version"
        ),
        enum_check("status", VideoRecipeStatus, "status"),
        enum_check("input_kind", VideoInputKind, "input_kind"),
    )

    video_recipe_id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    video_id: Mapped[str] = mapped_column(String(20), nullable=False)
    url: Mapped[str] = mapped_column(String(500), nullable=False)
    channel: Mapped[str | None] = mapped_column(String(200))
    title: Mapped[str | None] = mapped_column(String(200))
    dish_name: Mapped[str | None] = mapped_column(String(100))
    base_servings: Mapped[int | None] = mapped_column(SmallInteger)
    ingredients: Mapped[list[dict[str, Any]]] = mapped_column(
        JSONB, nullable=False, server_default=text("'[]'::jsonb")
    )
    steps: Mapped[list[dict[str, Any]]] = mapped_column(
        JSONB, nullable=False, server_default=text("'[]'::jsonb")
    )
    timestamps: Mapped[list[dict[str, Any]] | None] = mapped_column(JSONB)
    unresolved: Mapped[list[dict[str, Any]]] = mapped_column(
        JSONB, nullable=False, server_default=text("'[]'::jsonb")
    )
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, server_default=VideoRecipeStatus.PENDING.value
    )
    input_kind: Mapped[str] = mapped_column(
        String(20), nullable=False, server_default=VideoInputKind.VIDEO_URL.value
    )
    model: Mapped[str | None] = mapped_column(String(50))
    prompt_version: Mapped[str | None] = mapped_column(String(20))
    analyzed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    failure_reason: Mapped[str | None] = mapped_column(Text)
