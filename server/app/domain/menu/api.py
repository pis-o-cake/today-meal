"""메뉴 추천 API. `/api/menu` 에 마운트된다."""

from fastapi import APIRouter

from app.core.identity import CallerDep
from app.core.pending import not_implemented

router = APIRouter()


@router.get("/suggestions", summary="지금 가능한 메뉴")
async def suggestions(caller: CallerDep) -> list[dict[str, object]]:
    """현재 재고로 가능한 메뉴를 최대 3개 돌려준다.

    모델이 후보를 만들고 가능 여부는 코드가 판정한다. 이 순서를 뒤집으면 없는 재료로 만들 수
    있다고 말하는 화면이 나온다.
    """
    raise not_implemented("S-08", "F-13")


@router.get("/recipes/{recipe_id}", summary="메뉴 상세")
async def recipe_detail(recipe_id: int, caller: CallerDep) -> dict[str, object]:
    """인분에 맞는 재료와 조리 순서를 돌려준다. 조회만으로 재고를 바꾸지 않는다."""
    raise not_implemented("S-08", "F-14")
