"""FastAPI 진입점.

도메인 라우터는 `app/domain/*/api.py` 를 스캔해 자동 등록한다. 도메인을 추가할 때 이 파일을
고치지 않는다.
"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from loguru import logger

from app.core.config import get_settings
from app.core.database import dispose_engine
from app.core.exceptions import register_exception_handlers
from app.core.logging import configure_logging
from app.core.router import import_domain_models, register_routers

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """기동 시 모델을 적재하고 종료 시 커넥션 풀을 닫는다."""
    configure_logging()
    import_domain_models()
    logger.info("today-meal server starting (env={})", settings.env)
    yield
    await dispose_engine()
    logger.info("today-meal server stopped")


def create_app() -> FastAPI:
    """애플리케이션을 만들어 라우터와 예외 처리기를 붙인다."""
    application = FastAPI(
        title="오늘 뭐 먹지? 서버",
        description=(
            "음성 명령 해석과 재고 처리. 모델 출력은 실행 제안이며 실제 재고 변경은 "
            "서버 검증을 통과한 뒤에만 일어난다."
        ),
        version="0.1.0",
        docs_url="/docs" if settings.docs_enabled else None,
        redoc_url=None,
        openapi_url="/openapi.json" if settings.docs_enabled else None,
        lifespan=lifespan,
    )
    register_exception_handlers(application)
    register_routers(application)

    @application.get("/health", tags=["health"], summary="서버와 설정 상태")
    async def health() -> dict[str, object]:
        """의존성 없이 응답한다. 태블릿의 왕복 확인에 쓴다."""
        from app.core.llm.prompts import command_ko
        from app.core.llm.provider import get_budget, is_fake

        snapshot = get_budget().snapshot()
        return {
            "status": "ok",
            "env": settings.env,
            "model": settings.gemini_model,
            # 설정값이 아니라 실제로 쓰이는 프롬프트 버전을 알린다.
            "prompt_version": command_ko.VERSION,
            # 가짜로 돌고 있으면 드러낸다. 조용히 가짜를 쓰면 품질을 측정했다고 착각한다.
            "llm_fake": is_fake(),
            "llm_usage": {
                "calls": snapshot.calls,
                "estimated_usd": round(snapshot.estimated_usd, 6),
                "max_usd": settings.llm_max_usd,
            },
        }

    return application


app = create_app()
