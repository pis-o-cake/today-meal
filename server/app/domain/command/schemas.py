"""음성 명령 스키마.

`command_id` 는 **앱이 발화마다 만들어 보낸다.** 서버가 만들면 재시도를 구분할 수 없다.
"""

from typing import Any
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class CommandRequest(BaseModel):
    """전사된 발화 하나."""

    command_id: UUID = Field(description="앱이 발화마다 생성하는 멱등 키. 재시도해도 같은 값")
    utterance: str = Field(min_length=1, max_length=2000, description="전사 원문")
    locale: str = Field(default="ko", description="응답 문구 언어")


class CommandResponse(BaseModel):
    """처리 결과.

    `spoken` 은 짧게 읽어줄 한 문장이고 상세 내역은 `screen` 에 남긴다.
    """

    model_config = ConfigDict(from_attributes=True)

    command_id: UUID
    status: str = Field(description="applied · clarifying · rejected · failed")
    intent: str
    spoken: str | None = Field(default=None, description="TTS 로 읽어줄 한 문장")
    clarification_question: str | None = Field(default=None, description="되물을 한 가지")
    screen: dict[str, Any] = Field(default_factory=dict, description="화면에 남길 상세")
    undo_token: UUID | None = Field(default=None, description="되돌리기 대상 명령")
