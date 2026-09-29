"""모델이 PostgreSQL DDL 로 렌더링되는지, 설계 문서의 불변 조건이 스키마에 있는지 확인한다.

DB 없이 돈다 — `CreateTable` 을 PostgreSQL dialect 로 컴파일한다.
"""

from sqlalchemy import Numeric
from sqlalchemy.dialects import postgresql
from sqlalchemy.schema import CreateTable

EXPECTED_TABLES = {
    "household",
    "household_ingredient_preference",
    "ingredient",
    "ingredient_batch",
    "batch_date",
    "batch_state_event",
    "command",
    "change_event",
    "recipe",
    "recipe_ingredient",
    "menu_suggestion",
    "video_recipe",
    "shopping_item",
    "app_user",
    "user_session",
}


def test_all_designed_tables_exist(metadata):
    assert set(metadata.tables) == EXPECTED_TABLES


def test_every_table_compiles_to_postgresql(metadata):
    for table in metadata.tables.values():
        ddl = str(CreateTable(table).compile(dialect=postgresql.dialect()))
        assert f"CREATE TABLE {table.name}" in ddl


def _ddl(metadata, name: str) -> str:
    return str(CreateTable(metadata.tables[name]).compile(dialect=postgresql.dialect()))


def test_command_id_is_uuid_primary_key(metadata):
    """멱등성이 PK 로 걸려 있어야 한다. 재시도가 PK 충돌이 되어 막힌다."""
    command = metadata.tables["command"]
    assert [c.name for c in command.primary_key] == ["command_id"]
    assert isinstance(command.c.command_id.type, postgresql.UUID)


def test_negative_quantity_is_blocked_by_db(metadata):
    """음수 잔량 방어를 코드가 아니라 DB 가 막는다."""
    assert "quantity >= 0" in _ddl(metadata, "ingredient_batch")


def test_batch_date_kind_is_unique_per_batch(metadata):
    """한 묶음에 같은 종류 날짜는 하나. 기한 종류를 보존한다."""
    assert "UNIQUE (batch_id, kind)" in _ddl(metadata, "batch_date")


def test_date_value_is_nullable_for_unconfirmed_dates(metadata):
    """미확인 기한을 확정값으로 승격하지 않으려면 날짜가 NULL 일 수 있어야 한다."""
    assert metadata.tables["batch_date"].c.date_value.nullable is True


def test_change_event_can_reverse_itself(metadata):
    """정정·취소는 행을 고치지 않고 역산 행을 추가한다."""
    fks = metadata.tables["change_event"].c.reverses_event_id.foreign_keys
    assert {fk.target_fullname for fk in fks} == {"change_event.change_event_id"}


def test_append_only_ledgers_have_no_updated_at(metadata):
    """고치지 않는 원장에 `updated_at` 을 두면 거짓말이 된다."""
    for name in ("change_event", "batch_state_event"):
        assert "updated_at" not in metadata.tables[name].c


def test_quantities_use_numeric_not_float(metadata):
    """`float` 는 누적 오차가 잔량에 남는다."""
    for table, column in (
        ("ingredient_batch", "quantity"),
        ("change_event", "quantity_delta"),
        ("recipe_ingredient", "quantity"),
        ("shopping_item", "shortage_quantity"),
    ):
        assert isinstance(metadata.tables[table].c[column].type, Numeric)


def test_timestamps_are_timezone_aware(metadata):
    """UTC 로 저장하고 가구 시간대로 해석한다."""
    assert metadata.tables["command"].c.created_at.type.timezone is True


def test_app_user_stores_no_plaintext_secret(metadata):
    """비밀번호 원문을 담는 칸이 **없어야 한다.**

    해시는 있다. 이전 판본은 자격 증명을 아예 두지 않는 것이 설계였고, 계정마다 다른
    가구를 갖게 되면서 검증하는 로그인을 두었다 — 근거는 `docs/adr/0001` 에 있다.
    """
    columns = set(metadata.tables["app_user"].c.keys())
    assert "password" not in columns, "원문 비밀번호 칸을 두지 않는다"
    assert "password_hash" in columns


def test_session_stores_token_hash_not_token(metadata):
    """토큰 원문을 담지 않는다. DB 가 새도 그 값으로 로그인할 수 없어야 한다."""
    columns = set(metadata.tables["user_session"].c.keys())
    assert "token" not in columns
    assert "token_hash" in columns
    # 되돌릴 수 있어야 로그아웃이 실제로 세션을 끝낸다.
    assert "revoked_at" in columns
    assert "expires_at" in columns


def test_only_batch_has_soft_delete(metadata):
    """취소로 숨긴 묶음만 복구 대상이다. 나머지는 삭제하지 않는다."""
    with_soft_delete = {
        name for name, table in metadata.tables.items() if "deleted_at" in table.c
    }
    assert with_soft_delete == {"ingredient_batch"}
