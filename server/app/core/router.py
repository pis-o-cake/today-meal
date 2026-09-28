"""도메인 자동 등록.

`app/domain/<name>/api.py` 를 스캔해 `/api/<name>` 에 마운트한다. 도메인을 추가할 때
`main.py` 를 고치지 않는다. 같은 스캔으로 `models.py` 도 불러와 `Base.metadata` 를 채운다.
"""

import importlib
import pkgutil
from types import ModuleType

from fastapi import APIRouter, FastAPI
from loguru import logger

import app.domain as domain_package

_DOMAIN_PREFIX = "/api"


def discover_domains() -> list[str]:
    """`app/domain` 하위 패키지 이름을 이름순으로 돌려준다."""
    return sorted(
        module.name
        for module in pkgutil.iter_modules(domain_package.__path__)
        if module.ispkg
    )


def _import_submodule(domain: str, submodule: str) -> ModuleType | None:
    """도메인의 하위 모듈을 불러온다. 없으면 `None`."""
    try:
        return importlib.import_module(f"app.domain.{domain}.{submodule}")
    except ModuleNotFoundError as error:
        # 그 도메인이 해당 모듈을 갖지 않은 경우와 내부 import 실패를 구분한다.
        if error.name in (f"app.domain.{domain}.{submodule}", submodule):
            return None
        raise


def import_domain_models() -> list[str]:
    """모든 도메인의 `models.py` 를 불러온다.

    Alembic autogenerate 와 `create_all` 이 `Base.metadata` 를 보기 전에 호출해야 한다.

    Returns:
        모델 모듈을 가진 도메인 이름 목록.
    """
    loaded = [d for d in discover_domains() if _import_submodule(d, "models") is not None]
    logger.debug("Loaded models for domains: {}", loaded)
    return loaded


def register_routers(app: FastAPI) -> list[str]:
    """모든 도메인의 `api.py` 의 `router` 를 마운트한다.

    Args:
        app: 라우터를 붙일 FastAPI 인스턴스.

    Returns:
        마운트된 도메인 이름 목록.

    Raises:
        AttributeError: `api.py` 가 `router` 를 노출하지 않은 경우.
    """
    mounted: list[str] = []
    for name in discover_domains():
        module = _import_submodule(name, "api")
        if module is None:
            continue
        router = getattr(module, "router", None)
        if not isinstance(router, APIRouter):
            raise AttributeError(f"app.domain.{name}.api must expose an APIRouter named 'router'")
        app.include_router(router, prefix=f"{_DOMAIN_PREFIX}/{name}", tags=[name])
        mounted.append(name)
    logger.info("Mounted domain routers: {}", mounted)
    return mounted
