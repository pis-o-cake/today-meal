"""애플리케이션 설정. 비밀값은 환경변수와 `.env` 에서만 온다."""

from functools import lru_cache
from typing import Literal

from pydantic import Field, PostgresDsn
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """환경변수로 주입되는 실행 설정.

    Attributes:
        env: 실행 환경. 로그 형식과 Swagger 노출 여부를 가른다.
        gemini_model: 모델 식별자. 코드에 박지 않고 설정으로 교체한다.
    """

    model_config = SettingsConfigDict(
        env_prefix="TODAY_MEAL_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    env: Literal["local", "dev", "prod"] = "local"
    log_level: str = "INFO"

    db_host: str = "localhost"
    db_port: int = 5432
    db_name: str = "today_meal"
    db_user: str = "today_meal"
    db_password: str = ""

    gemini_api_key: str = ""
    gemini_model: str = "gemini-3.8-flash"

    # 구조화 추출에는 사고 과정이 필요 없고, 켜면 출력 토큰이 몇 배로 늘어난다.
    gemini_thinking_budget: int = 0
    gemini_timeout_seconds: float = 30.0

    # 정상 사용량은 3일 전체가 $2 규모다. 상한은 재시도 루프를 막기 위한 것이다.
    llm_max_usd: float = Field(default=5.0, description="누적 추정 비용 상한")
    llm_max_calls: int = Field(default=1500, description="창 안의 호출 수 상한")
    llm_min_interval_seconds: float = Field(
        default=3.0,
        description=(
            "연속 호출 최소 간격. 재시도 루프를 잡는다. 무료 티어는 분당 요청 수가 "
            "제한되므로 그 한도보다 넉넉하게 둔다"
        ),
    )

    youtube_api_key: str = ""

    default_household_id: int = Field(
        default=1,
        description="X-User-Id 가 없을 때 쓰는 가구. MVP 는 태블릿 한 대라 로그인이 관문이 아니다.",
    )

    @property
    def database_url(self) -> str:
        """SQLAlchemy async 엔진용 DSN."""
        return str(
            PostgresDsn.build(
                scheme="postgresql+asyncpg",
                username=self.db_user,
                password=self.db_password,
                host=self.db_host,
                port=self.db_port,
                path=self.db_name,
            )
        )

    @property
    def alembic_url(self) -> str:
        """Alembic 용 동기 DSN. 앱은 asyncpg, 마이그레이션은 psycopg 를 쓴다."""
        return self.database_url.replace("+asyncpg", "+psycopg")

    @property
    def docs_enabled(self) -> bool:
        """운영에서는 Swagger UI 를 닫는다."""
        return self.env != "prod"


@lru_cache
def get_settings() -> Settings:
    """설정을 한 번만 읽어 재사용한다."""
    return Settings()
