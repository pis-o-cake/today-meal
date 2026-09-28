"""async 엔진과 세션. 요청마다 세션 하나를 쓴다."""

from collections.abc import AsyncGenerator

from loguru import logger
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import get_settings

_settings = get_settings()

engine = create_async_engine(
    _settings.database_url,
    echo=_settings.env == "local",
    pool_pre_ping=True,
)

SessionFactory = async_sessionmaker(engine, expire_on_commit=False, autoflush=False)


async def get_session() -> AsyncGenerator[AsyncSession, None]:
    """FastAPI 의존성. 예외가 나면 롤백하고 원인을 남긴다."""
    async with SessionFactory() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            logger.exception("Session rolled back due to an unhandled error")
            raise
        finally:
            await session.close()


async def dispose_engine() -> None:
    """애플리케이션 종료 시 커넥션 풀을 닫는다."""
    await engine.dispose()
