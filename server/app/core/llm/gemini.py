"""Gemini 구현.

REST 를 직접 부른다. SDK 를 쓰지 않는 이유는 필요한 것이 한 엔드포인트뿐이고, 응답의
`usageMetadata` 를 예산 가드에 그대로 넘겨야 하기 때문이다.

IMPORTANT: 호출 직전에 [CallBudget.check] 를 부르고 끝난 뒤 [CallBudget.record] 를 부른다.
그 사이에 예외가 나면 사용량이 누락되지만, 실패한 호출도 토큰을 쓴다 — 응답을 받았으면
성공 여부와 무관하게 기록한다.
"""

from __future__ import annotations

import asyncio
import json
import re
from typing import Any, TypeVar

import httpx
from loguru import logger
from pydantic import BaseModel, ValidationError

from app.core.config import Settings
from app.core.exceptions import UpstreamError
from app.core.llm.budget import CallBudget
from app.core.llm.gateway import InventoryContext, MenuRequest, VideoSource
from app.core.llm.prompts import command_ko, menu_ko, video_ko
from app.core.llm.schemas import (
    CommandProposal,
    InterpretResult,
    LlmUsage,
    MenuProposal,
    MenuResult,
    ProposedVideoRecipe,
    VideoResult,
)

_BASE_URL = "https://generativelanguage.googleapis.com/v1beta"

_T = TypeVar("_T", bound=BaseModel)

# 과부하 재시도. 정상 사용에서는 거의 걸리지 않으므로 짧고 적게 둔다.
_MAX_ATTEMPTS = 4
_BACKOFF_SECONDS = 3.0

# 무료 티어는 분당 요청 수가 제한된다. 429 응답이 알려주는 대기 시간을 그대로 따른다 —
# 우리가 고른 값보다 제공자가 아는 값이 정확하다.
_RETRY_DELAY_PATTERN = re.compile(r"retry in ([0-9.]+)s", re.IGNORECASE)
_MAX_RETRY_DELAY_SECONDS = 60.0
_TRANSIENT_CODES = ("429", "500", "502", "503", "504")


def _suggested_delay(error: UpstreamError) -> float | None:
    """제공자가 알려준 대기 시간. 없으면 `None`."""
    match = _RETRY_DELAY_PATTERN.search(error.detail)
    if match is None:
        return None
    return min(float(match.group(1)) + 1.0, _MAX_RETRY_DELAY_SECONDS)


def _is_transient(error: UpstreamError) -> bool:
    """물러섰다 다시 시도할 만한 실패인지. 400 은 우리 요청이 틀린 것이라 재시도하지 않는다."""
    return any(code in error.detail for code in _TRANSIENT_CODES)


class GeminiGateway:
    """Gemini 로 발화를 해석한다."""

    def __init__(
        self,
        settings: Settings,
        budget: CallBudget,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        if not settings.gemini_api_key:
            raise ValueError("gemini api key is not configured")
        self._settings = settings
        self._budget = budget
        self._client = client
        self._schema = _response_schema()

    async def interpret(self, utterance: str, context: InventoryContext) -> InterpretResult:
        """발화 하나를 해석한다. 예산을 넘으면 호출하지 않는다."""
        self._budget.check()

        payload = {
            "systemInstruction": {"parts": [{"text": command_ko.SYSTEM}]},
            "contents": [
                {
                    "role": "user",
                    "parts": [
                        {
                            "text": command_ko.build_user_prompt(
                                utterance, context.as_prompt_block()
                            )
                        }
                    ],
                }
            ],
            "generationConfig": {
                "responseMimeType": "application/json",
                "responseSchema": self._schema,
                "temperature": 0.0,
                "thinkingConfig": {"thinkingBudget": self._settings.gemini_thinking_budget},
            },
        }

        raw = await self._post(payload)
        usage = _usage(raw, self._settings.gemini_model)
        self._budget.record(usage.input_tokens, usage.output_tokens)

        proposal = self._parse(raw)
        return InterpretResult(proposal=proposal, usage=usage, raw=raw)

    async def suggest_menus(self, request: MenuRequest) -> MenuResult:
        """메뉴 후보를 만든다. 예산을 넘으면 호출하지 않는다."""
        self._budget.check()

        payload = {
            "systemInstruction": {"parts": [{"text": menu_ko.SYSTEM}]},
            "contents": [
                {
                    "role": "user",
                    "parts": [
                        {
                            "text": menu_ko.build_user_prompt(
                                request.as_prompt_block(),
                                request.servings,
                                request.constraints(),
                            )
                        }
                    ],
                }
            ],
            "generationConfig": {
                "responseMimeType": "application/json",
                "responseSchema": _menu_schema(),
                # 창의성이 조금 필요하지만 재료를 지어내면 안 된다. 낮게 둔다.
                "temperature": 0.3,
                "thinkingConfig": {"thinkingBudget": self._settings.gemini_thinking_budget},
            },
        }
        raw = await self._post(payload)
        usage = _usage(raw, self._settings.gemini_model)
        self._budget.record(usage.input_tokens, usage.output_tokens)

        proposal = self._parse_into(raw, MenuProposal)
        return MenuResult(proposal=proposal, usage=usage, raw=raw)

    async def analyze_video(self, request: VideoSource) -> VideoResult:
        """영상의 글을 조리 단계로 정리한다. 예산을 넘으면 호출하지 않는다."""
        self._budget.check()

        payload = {
            "systemInstruction": {"parts": [{"text": video_ko.SYSTEM}]},
            "contents": [
                {
                    "role": "user",
                    "parts": [
                        {
                            "text": video_ko.build_user_prompt(
                                title=request.title,
                                channel=request.channel,
                                duration_seconds=request.duration_seconds,
                                body=request.body,
                            )
                        }
                    ],
                }
            ],
            "generationConfig": {
                "responseMimeType": "application/json",
                "responseSchema": _video_schema(),
                # 옮겨 적는 일이다. 창의성이 끼면 글에 없는 단계가 생긴다.
                "temperature": 0.0,
                "thinkingConfig": {"thinkingBudget": self._settings.gemini_thinking_budget},
            },
        }
        raw = await self._post(payload)
        usage = _usage(raw, self._settings.gemini_model)
        self._budget.record(usage.input_tokens, usage.output_tokens)

        proposal = self._parse_into(raw, ProposedVideoRecipe)
        return VideoResult(proposal=proposal, usage=usage, raw=raw)

    async def _post(self, payload: dict[str, Any]) -> dict[str, Any]:
        """제공자를 부른다. 일시적 과부하만 물러섰다 다시 시도한다.

        503·429 는 토큰을 쓰지 않으므로 재시도해도 비용이 늘지 않는다. 대기 시간을 예산
        가드의 최소 간격보다 크게 두어 재시도가 루프 판정에 걸리지 않게 한다.
        """
        last: Exception | None = None
        for attempt in range(_MAX_ATTEMPTS):
            try:
                return await self._post_once(payload)
            except UpstreamError as error:
                last = error
                if not _is_transient(error) or attempt == _MAX_ATTEMPTS - 1:
                    raise
                delay = _suggested_delay(error) or _BACKOFF_SECONDS * (attempt + 1)
                logger.warning(
                    "Gemini transient failure ({}), retrying in {}s", error.detail, delay
                )
                await asyncio.sleep(delay)
        raise last if last else UpstreamError("gemini request failed")

    async def _post_once(self, payload: dict[str, Any]) -> dict[str, Any]:
        url = f"{_BASE_URL}/models/{self._settings.gemini_model}:generateContent"
        headers = {
            "x-goog-api-key": self._settings.gemini_api_key,
            "content-type": "application/json",
        }
        timeout = self._settings.gemini_timeout_seconds
        try:
            if self._client is not None:
                response = await self._client.post(
                    url, json=payload, headers=headers, timeout=timeout
                )
            else:
                async with httpx.AsyncClient(timeout=timeout) as client:
                    response = await client.post(url, json=payload, headers=headers)
        except httpx.HTTPError as error:
            raise UpstreamError(f"gemini request failed: {error}") from error

        if response.status_code >= 400:
            # 응답 본문을 로그에만 남긴다. 사용자 화면에는 노출하지 않는다.
            logger.error(
                "Gemini returned {}: {}", response.status_code, response.text[:500]
            )
            raise UpstreamError(f"gemini returned {response.status_code}: {response.text[:300]}")
        return response.json()

    def _parse(self, raw: dict[str, Any]) -> CommandProposal:
        return self._parse_into(raw, CommandProposal)

    def _parse_into(self, raw: dict[str, Any], model: type[_T]) -> _T:
        """응답의 텍스트를 지정한 모델로 검증한다."""
        try:
            text = raw["candidates"][0]["content"]["parts"][0]["text"]
        except (KeyError, IndexError, TypeError) as error:
            raise UpstreamError(f"gemini response has no text part: {error}") from error

        try:
            data = json.loads(text)
        except json.JSONDecodeError as error:
            raise UpstreamError(f"gemini response is not json: {error}") from error

        try:
            return model.model_validate(data)
        except ValidationError as error:
            # 스키마 위반은 모델 결함이다. 원본을 남겨 재현할 수 있게 한다.
            logger.error("Gemini proposal failed schema validation: {}", error)
            raise UpstreamError(f"gemini proposal violates schema: {error}") from error


def _usage(raw: dict[str, Any], model: str) -> LlmUsage:
    """응답의 `usageMetadata` 를 읽는다. 없으면 0 으로 둔다."""
    meta = raw.get("usageMetadata") or {}
    return LlmUsage(
        input_tokens=int(meta.get("promptTokenCount", 0)),
        output_tokens=int(
            meta.get("candidatesTokenCount", 0) + meta.get("thoughtsTokenCount", 0)
        ),
        model=model,
    )


def _response_schema() -> dict[str, Any]:
    """Gemini 의 responseSchema 로 쓸 형태.

    Pydantic 의 JSON Schema 를 그대로 넘길 수 없다 — `$ref`·`anyOf`·`const` 를 받지 않으므로
    필요한 부분만 손으로 적는다. 이 스키마와 `schemas.py` 가 어긋나면 파싱에서 걸린다.
    """
    from app.core.enums import CommandIntent, DateKind, StorageLocation, values

    date_schema = {
        "type": "object",
        "properties": {
            "kind": {"type": "string", "enum": values(DateKind), "nullable": True},
            "raw_text": {"type": "string", "nullable": True},
            "year": {"type": "integer", "nullable": True},
            "month": {"type": "integer", "nullable": True},
            "day": {"type": "integer", "nullable": True},
        },
    }
    item_schema = {
        "type": "object",
        "properties": {
            "raw_name": {"type": "string", "maxLength": 50},
            "amount": {"type": "number", "nullable": True},
            # 모델이 이 칸에 사고 과정을 흘려 넣는 일이 있어 길이를 묶는다.
            "unit_text": {"type": "string", "maxLength": 10, "nullable": True},
            "qualitative_amount": {"type": "string", "maxLength": 10, "nullable": True},
            "storage": {"type": "string", "enum": values(StorageLocation), "nullable": True},
            "dates": {"type": "array", "items": date_schema},
            "is_remaining": {"type": "boolean"},
        },
        "required": ["raw_name", "is_remaining"],
    }
    return {
        "type": "object",
        "properties": {
            "intent": {"type": "string", "enum": values(CommandIntent)},
            "items": {"type": "array", "items": item_schema},
            "needs_clarification": {"type": "boolean"},
            "question": {"type": "string", "nullable": True},
            "servings": {"type": "integer", "nullable": True},
            "max_minutes": {"type": "integer", "nullable": True},
            "correction_of_previous": {"type": "boolean"},
            "notes": {"type": "string", "nullable": True},
        },
        "required": ["intent", "items", "needs_clarification", "correction_of_previous"],
    }


def _menu_schema() -> dict[str, Any]:
    """추천 응답의 responseSchema.

    `schemas.py` 의 `MenuProposal` 과 같은 모양이어야 한다. 어긋나면 파싱에서 걸린다.
    """
    ingredient_schema = {
        "type": "object",
        "properties": {
            "raw_name": {"type": "string"},
            "amount": {"type": "number", "nullable": True},
            "unit_text": {"type": "string", "nullable": True},
            "is_essential": {"type": "boolean"},
            "is_amount_unknown": {"type": "boolean"},
        },
        "required": ["raw_name", "is_essential", "is_amount_unknown"],
    }
    recipe_schema = {
        "type": "object",
        "properties": {
            "name": {"type": "string"},
            "servings": {"type": "integer"},
            "estimated_minutes": {"type": "integer", "nullable": True},
            "reason": {"type": "string", "nullable": True},
            "ingredients": {"type": "array", "items": ingredient_schema},
            "steps": {"type": "array", "items": {"type": "string"}},
        },
        "required": ["name", "servings", "ingredients", "steps"],
    }
    return {
        "type": "object",
        "properties": {
            "recipes": {"type": "array", "items": recipe_schema},
            "notes": {"type": "string", "nullable": True},
        },
        "required": ["recipes"],
    }


def _video_schema() -> dict[str, Any]:
    """영상 정리 응답의 responseSchema.

    `schemas.py` 의 `ProposedVideoRecipe` 와 같은 모양이어야 한다. 어긋나면 파싱에서 걸린다.
    """
    ingredient_schema = {
        "type": "object",
        "properties": {
            "raw_name": {"type": "string"},
            "amount": {"type": "number", "nullable": True},
            "unit_text": {"type": "string", "nullable": True},
            "is_essential": {"type": "boolean"},
            "is_amount_unknown": {"type": "boolean"},
        },
        "required": ["raw_name", "is_essential", "is_amount_unknown"],
    }
    step_schema = {
        "type": "object",
        "properties": {
            "text": {"type": "string"},
            "timer_seconds": {"type": "integer", "nullable": True},
            "timer_label": {"type": "string", "nullable": True},
            "ingredients": {"type": "array", "items": {"type": "string"}},
        },
        "required": ["text"],
    }
    return {
        "type": "object",
        "properties": {
            "is_recipe": {"type": "boolean"},
            "dish_name": {"type": "string", "nullable": True},
            "base_servings": {"type": "integer", "nullable": True},
            "estimated_minutes": {"type": "integer", "nullable": True},
            "ingredients": {"type": "array", "items": ingredient_schema},
            "steps": {"type": "array", "items": step_schema},
            "unresolved": {"type": "array", "items": {"type": "string"}},
        },
        "required": ["is_recipe", "ingredients", "steps"],
    }
