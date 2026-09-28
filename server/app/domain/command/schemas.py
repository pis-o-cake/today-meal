"""음성 명령 스키마.

`command_id` 는 **앱이 발화마다 만들어 보낸다.** 서버가 만들면 재시도를 구분할 수 없다.
"""

from datetime import datetime
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


class HistoryRow(BaseModel):
    """이력 한 줄.

    수량 변경과 상태 변경을 같은 타임라인에 섞는다. `kind` 로 구분하며, 명시값과 추정값을
    `is_estimated` 로 가른다 — 사용자가 말한 숫자와 앱이 추정한 숫자는 다른 사실이다.
    """

    model_config = ConfigDict(from_attributes=True)

    kind: str = Field(description="quantity · state")
    action: str = Field(description="변경 동작 또는 상태 종류")
    name: str = Field(description="재료명")
    batch_id: int
    quantity_before: str | None = None
    quantity_after: str | None = None
    unit: str | None = None
    is_estimated: bool = Field(default=False, description="추정값인지")
    occurred_at: datetime
    command_id: UUID | None = None
    reverses_event_id: int | None = Field(
        default=None, description="되돌린 대상. 있으면 역산 이벤트다"
    )
