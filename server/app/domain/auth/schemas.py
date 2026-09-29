"""인증 요청·응답 스키마.

비밀번호는 요청에만 있고 응답에는 없다. 세션 토큰은 만들 때 한 번만 돌려주며 이후
어떤 응답에도 담기지 않는다.
"""

import re
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

#: 목업이 표시하는 비밀번호 조건. 앱도 같은 조건을 미리 알려준다.
MIN_PASSWORD_LENGTH = 8

_HAS_LETTER = re.compile(r"[A-Za-z]")
_HAS_DIGIT = re.compile(r"[0-9]")


def _check_password(value: str) -> str:
    """영문·숫자·8자 이상.

    앱도 같은 검사를 하지만 **판정의 정본은 서버다** — 앱 검사는 입력을 돕는 것이고,
    API 를 직접 부르는 경로에서는 서버만 남는다.
    """
    if len(value) < MIN_PASSWORD_LENGTH:
        raise ValueError(f"password must be at least {MIN_PASSWORD_LENGTH} characters")
    if not _HAS_LETTER.search(value) or not _HAS_DIGIT.search(value):
        raise ValueError("password must contain both letters and digits")
    return value


class SignUpRequest(BaseModel):
    """이메일 가입."""

    email: EmailStr = Field(description="로그인에 쓰는 이메일. 대소문자를 구분하지 않는다")
    password: str = Field(description="영문·숫자를 포함한 8자 이상")
    nickname: str = Field(min_length=1, max_length=50, description="화면에 보일 이름")

    @field_validator("password")
    @classmethod
    def validate_password(cls, value: str) -> str:
        return _check_password(value)

    @field_validator("nickname")
    @classmethod
    def strip_nickname(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("nickname must not be blank")
        return stripped


class AvailabilityRead(BaseModel):
    """이메일을 쓸 수 있는지.

    형식이 틀린 것과 이미 쓰는 것을 구분해 돌려준다 — 사용자가 고쳐야 할 것이 다르다.
    """

    available: bool
    reason: Literal["ok", "taken", "invalid"] = Field(
        description="available 이 거짓일 때의 이유"
    )


class SignInRequest(BaseModel):
    """이메일 로그인."""

    email: EmailStr
    password: str


class UserRead(BaseModel):
    """로그인한 사람. **비밀번호와 토큰은 담지 않는다.**"""

    model_config = ConfigDict(from_attributes=True)

    user_id: int
    household_id: int
    provider: str = Field(description="계정을 만든 경로. 지금은 email 만 구현했다")
    email: str | None = None
    display_name: str | None = Field(default=None, description="화면에 보일 이름")


class SessionRead(BaseModel):
    """로그인 결과.

    [access_token] 은 **이 응답에만** 들어 있다. 서버는 해시만 갖고 있어 다시 알려줄 수
    없으므로, 앱이 받아서 저장한다.
    """

    access_token: str = Field(description="Authorization: Bearer 로 보낼 값")
    token_type: str = Field(default="bearer")
    expires_at: datetime
    user: UserRead
