"""영상 레시피 API. 추가 범위. `/api/video` 에 마운트된다."""

from fastapi import APIRouter

from app.core.identity import CallerDep
from app.core.pending import not_implemented

router = APIRouter()


@router.get("/search", summary="추천 메뉴의 영상 검색")
async def search(q: str, caller: CallerDep) -> list[dict[str, object]]:
    """검색 API 가 준 실제 영상 ID 로만 링크를 만든다. 모델이 URL 을 만들지 않는다."""
    raise not_implemented("S-11", "F-17")


@router.post("/analyze", summary="영상 레시피 분석")
async def analyze(url: str, caller: CallerDep) -> dict[str, object]:
    """공개 영상에서 재료·분량을 추출한다. 없는 분량은 미확인으로 남긴다.

    IMPORTANT: 이 경로에는 재고 변경 권한이 없다. 분석·시청만으로 재고가 바뀌지 않는다.
    """
    raise not_implemented("S-12", "F-18")
