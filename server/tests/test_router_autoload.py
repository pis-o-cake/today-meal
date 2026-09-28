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
    """빈 성공 응답을 주면 앱이 동작한다고 착각한다.

    필수 범위는 모두 구현됐으므로 남은 501 은 추가 범위뿐이다.
    """
    from app.main import create_app

    with TestClient(create_app()) as client:
        response = client.get("/api/shopping/items")
    assert response.status_code == 501
    detail = response.json()["detail"]
    assert "slice S-13" in detail
    assert "F-20" in detail


def test_required_scope_endpoints_are_implemented():
    """필수 기능의 엔드포인트가 501 로 남아 있지 않은지 확인한다."""
    from app.main import create_app

    required = [
        ("GET", "/api/household/me"),
        ("GET", "/api/ingredient"),
        ("GET", "/api/inventory/batches"),
        ("GET", "/api/inventory/batches/expiring"),
        ("POST", "/api/command/interpret"),
        ("GET", "/api/command/history"),
        ("POST", "/api/menu/suggestions"),
        ("GET", "/api/menu/suggestions"),
        ("GET", "/api/menu/recipes/{recipe_id}"),
    ]
    with TestClient(create_app()) as client:
        paths = client.get("/openapi.json").json()["paths"]
    for method, path in required:
        assert path in paths, path
        assert method.lower() in paths[path], f"{method} {path}"
