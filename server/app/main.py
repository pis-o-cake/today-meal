"""FastAPI 진입점.

도메인 라우터는 `app/domain/*/api.py` 를 스캔해 자동 등록한다. 도메인을 추가할 때 이 파일을
고치지 않는다.
"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
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

    # 설치 안내 페이지. QR 과 APK 를 함께 둔다 — 심사하는 사람이 폰으로 바로 받는다.
    static_dir = Path(__file__).resolve().parent / "static"

    # IMPORTANT: 설치 파일은 `.apk` 가 아닌 이름으로 둔다. 저장소의 `.gitignore` 가
    # `*.apk` 를 지우고 배포 업로드가 그 규칙을 그대로 따라, `.apk` 로 두면 이미지에
    # 실리지 않아 404 가 된다. 내려받을 때의 이름과 형식은 여기서 정한다.
    #
    # WARNING: 경로를 `/install` 밖에 둔다. 그 아래에 두면 정적 마운트가 먼저 잡아
    # 파일이 없다며 404 를 돌려준다 — 라우트 등록 순서로는 막지 못한다.
    @application.get(
        "/download/today-meal.apk",
        tags=["install"],
        summary="안드로이드 설치 파일",
        response_class=FileResponse,
    )
    async def download_apk() -> FileResponse:
        """설치 파일을 내려준다. 없으면 404 로 답한다."""
        apk = static_dir / "app-release.bin"
        if not apk.is_file():
            raise HTTPException(status_code=404, detail="install file is not bundled")
        return FileResponse(
            apk,
            media_type="application/vnd.android.package-archive",
            filename="today-meal.apk",
        )

    # `html=True` 라야 `/install/` 이 `index.html` 을 준다. 파일이 없는 배포(개발용
    # 실행 등)에서는 건너뛴다 — 없다고 서버가 뜨지 못하면 안 된다.
    #
    # 마운트는 위 라우트보다 **뒤**에 등록한다. 앞서면 정적 처리기가 먼저 가로챈다.
    if static_dir.is_dir():
        application.mount(
            "/install", StaticFiles(directory=static_dir, html=True), name="install"
        )

    # 발표 자료(웹 슬라이드). 링크 하나로 열어 볼 수 있게 서버에 같이 싣는다.
    # 원본은 `presentation/slides/`, 여기는 `build_deck.py` 가 만든 공개용 빌드다.
    deck_dir = Path(__file__).resolve().parent / "deck"
    if deck_dir.is_dir():
        application.mount("/deck", StaticFiles(directory=deck_dir, html=True), name="deck")

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
