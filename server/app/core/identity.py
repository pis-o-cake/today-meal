"""호출자 식별.

**보안은 전부 배제했다.** `X-User-Id` 헤더를 그대로 신뢰하며 서명도 만료도 세션도 검증하지
않는다. 값을 바꿔 보내면 다른 가구의 데이터에 접근할 수 있고, 그것이 의도한 상태다. 근거는
`docs/design/0001-mvp-technical-design.md` 의 「인증 — 하지 않는다」에 있다.

CAUTION: 이 상태로 공개 배포하지 않는다. 실제 사용자를 받기 전에 인증을 다시 설계한다.
"""

from dataclasses import dataclass
from typing import Annotated

from fastapi import Depends, Header

from app.core.config import Settings, get_settings


@dataclass(frozen=True, slots=True)
class Caller:
    """요청을 보낸 주체.

    Attributes:
        household_id: 데이터를 읽고 쓸 가구.
        user_id: 식별된 사용자. 헤더가 없으면 `None`.
    """

    household_id: int
    user_id: int | None


async def get_caller(
    settings: Annotated[Settings, Depends(get_settings)],
    x_user_id: Annotated[int | None, Header(alias="X-User-Id")] = None,
    x_household_id: Annotated[int | None, Header(alias="X-Household-Id")] = None,
) -> Caller:
    """헤더에서 호출자를 읽는다. 검증하지 않는다.

    헤더가 없으면 기본 가구로 처리한다. MVP 는 주방에 고정한 태블릿 한 대에서 쓰므로
    **로그인은 기능을 막는 관문이 아니다.**
    """
    return Caller(
        household_id=x_household_id or settings.default_household_id,
        user_id=x_user_id,
    )


CallerDep = Annotated[Caller, Depends(get_caller)]
