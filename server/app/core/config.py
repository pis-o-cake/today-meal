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
        prompt_version: 프롬프트 버전. `command` 행에 기록해 재현에 쓴다.
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
    gemini_model: str = "gemini-2.5-flash"
    prompt_version: str = "v1"

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
