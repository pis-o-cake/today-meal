"""도메인 자동 등록. 도메인을 추가할 때 `main.py` 를 고치지 않는다."""

from fastapi.testclient import TestClient

from app.core.router import discover_domains, import_domain_models

REQUIRED_DOMAINS = {"household", "ingredient", "inventory", "command", "menu"}
OPTIONAL_DOMAINS = {"video", "shopping", "auth"}


def test_all_domains_discovered():
    assert set(discover_domains()) == REQUIRED_DOMAINS | OPTIONAL_DOMAINS


def test_every_domain_has_models():
    assert set(import_domain_models()) == REQUIRED_DOMAINS | OPTIONAL_DOMAINS


def test_health_answers_without_database():
    """태블릿의 왕복 확인은 DB 없이 통과해야 한다."""
    from app.main import create_app

    with TestClient(create_app()) as client:
        response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_every_domain_is_mounted_under_api():
    from app.main import create_app

    with TestClient(create_app()) as client:
        paths = client.get("/openapi.json").json()["paths"]
    for domain in REQUIRED_DOMAINS | OPTIONAL_DOMAINS:
        assert any(path.startswith(f"/api/{domain}") for path in paths), domain


def test_unimplemented_endpoints_return_501_not_empty_success():
    """빈 성공 응답을 주면 앱이 동작한다고 착각한다."""
    from app.main import create_app

    with TestClient(create_app()) as client:
        response = client.get("/api/menu/suggestions")
    assert response.status_code == 501
    assert "slice S-08" in response.json()["detail"]
