"""장보기 API. 추가 범위. `/api/shopping` 에 마운트된다."""

from fastapi import APIRouter

from app.core.identity import CallerDep
from app.core.pending import not_implemented

router = APIRouter()


@router.get("/items", summary="부족한 재료 목록")
async def items(caller: CallerDep) -> list[dict[str, object]]:
    """부족량과 확인 필요 항목을 돌려준다. 단위 변환 근거가 없으면 숫자를 만들지 않는다."""
    raise not_implemented("S-13", "F-20")
