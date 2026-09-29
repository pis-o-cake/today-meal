"""영상 레시피 API. `/api/video` 에 마운트된다."""

from typing import Annotated

from fastapi import APIRouter, Body, Depends
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import dates as date_utils
from app.core.config import Settings, get_settings
from app.core.database import get_session
from app.core.identity import CallerDep
from app.core.llm.gateway import LlmGateway
from app.core.llm.provider import get_gateway
from app.core.pending import not_implemented
from app.domain.household import service as household_service
from app.domain.video import service
from app.domain.video.schemas import VideoRecipeRead

router = APIRouter()

SessionDep = Annotated[AsyncSession, Depends(get_session)]
GatewayDep = Annotated[LlmGateway, Depends(get_gateway)]
SettingsDep = Annotated[Settings, Depends(get_settings)]


class AnalyzeRequest(BaseModel):
    """분석할 영상 링크."""

    url: str = Field(min_length=1, max_length=500, description="유튜브 시청 주소")


@router.get("/search", summary="추천 메뉴의 영상 검색")
async def search(q: str, caller: CallerDep) -> list[dict[str, object]]:
    """검색 API 가 준 실제 영상 ID 로만 링크를 만든다. 모델이 URL 을 만들지 않는다."""
    raise not_implemented("S-11", "F-17")


@router.post(
    "/analyze",
    response_model=VideoRecipeRead,
    summary="영상 레시피 분석",
)
async def analyze(
    caller: CallerDep,
    session: SessionDep,
    gateway: GatewayDep,
    settings: SettingsDep,
    body: Annotated[AnalyzeRequest, Body()],
) -> VideoRecipeRead:
    """공개 영상의 제목·설명·자막에서 재료와 조리 단계를 정리한다.

    분량이 적혀 있지 않은 재료는 **미확인으로 남긴다.** 보유 여부는 응답을 만드는 시점의
    재고로 판정하며 저장하지 않는다.

    IMPORTANT: 이 경로에는 재고 변경 권한이 없다. 분석·시청만으로 재고가 바뀌지 않는다.

    Raises:
        422: 유튜브 링크가 아니거나, 읽을 글이 없거나, 요리 순서를 찾지 못했다.
        502: 유튜브나 모델에 닿지 못했다.
    """
    household = await household_service.get_household(session, caller.household_id)
    return await service.analyze(
        session,
        household_id=household.household_id,
        url=body.url,
        gateway=gateway,
        settings=settings,
        today=date_utils.today_in(household.timezone),
    )
