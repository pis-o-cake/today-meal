"""테스트 공통 설정. DB 없이 도는 것만 둔다."""

import os

import pytest

# WARNING: 환경변수는 `.env` 보다 우선한다. 여기서 DB 접속값을 setdefault 하면 로컬 `.env` 를
# 덮어써 통합 테스트가 조용히 건너뛰어진다. 접속값은 `.env` 가 갖는다.
os.environ.setdefault("TODAY_MEAL_ENV", "local")


@pytest.fixture(scope="session")
def metadata():
    """모든 도메인 모델이 적재된 `Base.metadata`."""
    from app.core.models import Base
    from app.core.router import import_domain_models

    import_domain_models()
    return Base.metadata
