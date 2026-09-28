"""게이트웨이 선택.

키가 없으면 가짜를 쓴다. **키 없이도 서버가 뜨고 검증 로직이 돌아야** 하기 때문이다 —
그러지 않으면 키가 없는 사람은 아무것도 확인할 수 없다.

CAUTION: 가짜로 돌고 있다는 사실이 로그와 `/health` 에 드러나야 한다. 조용히 가짜를 쓰면
해석 품질을 측정했다고 착각한다.
"""

from __future__ import annotations

from functools import lru_cache

from loguru import logger

from app.core.config import Settings, get_settings
from app.core.llm.budget import CallBudget
from app.core.llm.fake import FakeLlmGateway
from app.core.llm.gateway import LlmGateway


@lru_cache
def get_budget() -> CallBudget:
    """프로세스 단위 예산 가드. 설정에서 상한을 읽는다."""
    settings = get_settings()
    return CallBudget(
        max_calls_per_window=settings.llm_max_calls,
        max_usd=settings.llm_max_usd,
        min_interval_seconds=settings.llm_min_interval_seconds,
    )


@lru_cache
def get_gateway() -> LlmGateway:
    """설정에 맞는 게이트웨이를 하나 만들어 재사용한다."""
    settings: Settings = get_settings()
    if not settings.gemini_api_key:
        logger.warning(
            "LLM gateway is running in FAKE mode: no api key configured. "
            "Interpretation quality is not measurable in this mode."
        )
        return FakeLlmGateway()

    from app.core.llm.gemini import GeminiGateway

    logger.info(
        "LLM gateway: gemini model={} thinkingBudget={} budget=${}",
        settings.gemini_model,
        settings.gemini_thinking_budget,
        settings.llm_max_usd,
    )
    return GeminiGateway(settings, get_budget())


def is_fake() -> bool:
    """가짜로 돌고 있는지. `/health` 가 이 값을 노출한다."""
    return isinstance(get_gateway(), FakeLlmGateway)
