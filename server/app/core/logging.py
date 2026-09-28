"""loguru 설정. `print` 를 쓰지 않는다."""

import sys

from loguru import logger

from app.core.config import get_settings

_FORMAT_LOCAL = (
    "<green>{time:HH:mm:ss.SSS}</green> | <level>{level: <8}</level> | "
    "<cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> - <level>{message}</level>"
)


def configure_logging() -> None:
    """기본 핸들러를 걷어내고 환경에 맞는 싱크를 붙인다.

    운영에서는 JSON 한 줄로 내보내 수집기가 파싱할 수 있게 한다.
    """
    settings = get_settings()
    logger.remove()

    # WARNING: 컨테이너에서 stderr 이 닫힐 수 있다. 없으면 stdout 으로 내린다.
    sink = sys.stderr if sys.stderr is not None else sys.stdout
    if sink is None:
        return

    logger.add(
        sink,
        level=settings.log_level,
        format=_FORMAT_LOCAL if settings.env == "local" else "{message}",
        serialize=settings.env != "local",
        backtrace=settings.env == "local",
        diagnose=False,
    )
