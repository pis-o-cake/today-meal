"""테스트 공통 설정. DB 없이 도는 것만 둔다."""

import os

import pytest

# WARNING: 환경변수는 `.env` 보다 우선한다. 여기서 DB 접속값을 setdefault 하면 로컬 `.env` 를
# 덮어써 통합 테스트가 조용히 건너뛰어진다. 접속값은 `.env` 가 갖는다.
# SQL echo 는 local 에서만 켜진다. 테스트 출력이 쿼리에 묻히지 않게 dev 로 둔다.
os.environ.setdefault("TODAY_MEAL_ENV", "dev")
# 구조화 로그가 테스트 출력을 덮지 않게 한다.
os.environ.setdefault("TODAY_MEAL_LOG_LEVEL", "WARNING")


@pytest.fixture(scope="session")
def metadata():
    """모든 도메인 모델이 적재된 `Base.metadata`."""
    from app.core.models import Base
    from app.core.router import import_domain_models

    import_domain_models()
    return Base.metadata
