"""사용자 식별 API. 추가 범위. `/api/auth` 에 마운트된다.

CAUTION: **보안은 전부 배제했다.** 토큰 서명·만료를 검증하지 않고 세션도 없다. 이 엔드포인트를
인증으로 소개하지 않는다.
"""

from fastapi import APIRouter

from app.core.pending import not_implemented

router = APIRouter()


@router.post("/sign-in", summary="간편 로그인 — 식별 전용")
async def sign_in(provider: str, provider_user_id: str) -> dict[str, object]:
    """제공자 사용자 ID 로 사용자를 찾거나 만든다.

    받은 값을 **검증하지 않고 그대로 신뢰한다.** 로그인은 기능을 막는 관문이 아니며, 헤더가
    없으면 기본 가구로 전 기능이 동작한다.
    """
    raise not_implemented("S-15", "F-22")
