"""DB 제약이 실제로 불변 조건을 막는지 확인한다.

**실제 PostgreSQL 이 필요하다.** 없으면 건너뛴다 — `docker compose up -d db` 로 띄운다.
설계 문서가 "코드가 아니라 DB 가 막는다"고 적은 것을 여기서 증명한다.
"""

from datetime import UTC, datetime
from decimal import Decimal
from uuid import uuid4

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import get_settings


@pytest.fixture(scope="module")
def engine():
    """마이그레이션이 적용된 DB 에 붙는다. 붙지 못하면 모듈 전체를 건너뛴다."""
    candidate = create_engine(get_settings().alembic_url, pool_pre_ping=True)
    try:
        with candidate.connect() as connection:
            applied = connection.execute(
                text("select count(*) from information_schema.tables where table_name='command'")
            ).scalar_one()
    except Exception as error:  # noqa: BLE001
        pytest.skip(f"PostgreSQL unavailable: {error}")
    if not applied:
        pytest.skip("migrations not applied: run 'alembic upgrade head'")
    return candidate


@pytest.fixture
def session(engine):
    """테스트마다 롤백한다. 데이터를 남기지 않는다."""
    with engine.connect() as connection:
        transaction = connection.begin()
        with Session(bind=connection) as bound:
            yield bound
        # IntegrityError 가 나면 트랜잭션이 이미 끊긴다. 살아 있을 때만 되돌린다.
        if transaction.is_active:
            transaction.rollback()


def _household(session) -> int:
    from app.domain.household.models import Household

    household = Household(name="테스트 가구")
    session.add(household)
    session.flush()
    return household.household_id


def _ingredient(session, name: str) -> int:
    """재료를 찾거나 만든다. 시드가 이미 넣어둔 이름과 충돌하지 않게 한다."""
    from sqlalchemy import select

    from app.domain.ingredient.models import Ingredient

    found = session.execute(
        select(Ingredient.ingredient_id).where(Ingredient.canonical_name == name)
    ).scalar_one_or_none()
    if found is not None:
        return found

    ingredient = Ingredient(canonical_name=name, aliases=[name])
    session.add(ingredient)
    session.flush()
    return ingredient.ingredient_id


def _batch(session, household_id: int, ingredient_id: int, quantity: str | None = "10"):
    from app.domain.inventory.models import IngredientBatch

    batch = IngredientBatch(
        household_id=household_id,
        ingredient_id=ingredient_id,
        raw_name="계란",
        quantity=Decimal(quantity) if quantity is not None else None,
        unit="ea" if quantity is not None else None,
        qualitative_amount=None if quantity is not None else "조금",
    )
    session.add(batch)
    session.flush()
    return batch


def test_negative_quantity_is_rejected_by_database(session):
    """음수 잔량 방어. 코드를 우회해도 DB 가 막는다."""
    household_id = _household(session)
    ingredient_id = _ingredient(session, "계란")
    batch = _batch(session, household_id, ingredient_id)
    batch.quantity = Decimal("-1")
    with pytest.raises(IntegrityError, match="quantity_non_negative"):
        session.flush()


def test_batch_without_any_amount_is_rejected(session):
    """수량도 정성 표현도 없으면 잔량을 모른다는 뜻조차 안 된다."""
    from app.domain.inventory.models import IngredientBatch

    household_id = _household(session)
    ingredient_id = _ingredient(session, "두부")
    session.add(
        IngredientBatch(
            household_id=household_id, ingredient_id=ingredient_id, raw_name="두부"
        )
    )
    with pytest.raises(IntegrityError, match="amount_present"):
        session.flush()


def test_numeric_quantity_requires_unit(session):
    """숫자에는 단위가 붙어야 한다."""
    from app.domain.inventory.models import IngredientBatch

    household_id = _household(session)
    ingredient_id = _ingredient(session, "우유")
    session.add(
        IngredientBatch(
            household_id=household_id,
            ingredient_id=ingredient_id,
            raw_name="우유",
            quantity=Decimal("1"),
        )
    )
    with pytest.raises(IntegrityError, match="unit_present"):
        session.flush()


def test_same_date_kind_twice_is_rejected(session):
    """한 묶음에 소비기한이 둘일 수 없다."""
    from app.core.enums import DateKind
    from app.domain.inventory.models import BatchDate

    household_id = _household(session)
    ingredient_id = _ingredient(session, "두부")
    batch = _batch(session, household_id, ingredient_id)
    for day in (3, 5):
        session.add(
            BatchDate(
                batch_id=batch.batch_id,
                kind=DateKind.USE_BY.value,
                date_value=datetime(2026, 10, day, tzinfo=UTC).date(),
            )
        )
    with pytest.raises(IntegrityError, match="batch_date_batch_id_kind"):
        session.flush()


def test_different_date_kinds_coexist(session):
    """소비기한과 제조일은 서로 다른 값이다. 둘 다 남는다."""
    from app.core.enums import DateKind
    from app.domain.inventory.models import BatchDate

    household_id = _household(session)
    ingredient_id = _ingredient(session, "두부")
    batch = _batch(session, household_id, ingredient_id)
    session.add_all(
        [
            BatchDate(batch_id=batch.batch_id, kind=DateKind.USE_BY.value,
                      date_value=datetime(2026, 10, 3, tzinfo=UTC).date()),
            BatchDate(batch_id=batch.batch_id, kind=DateKind.MANUFACTURED.value,
                      date_value=datetime(2026, 9, 25, tzinfo=UTC).date()),
        ]
    )
    session.flush()
    assert len(batch.dates) == 2


def test_unconfirmed_date_can_have_no_value(session):
    """"날짜는 모르겠어"는 종류만 있고 날짜가 없는 상태다."""
    from app.core.enums import DateKind
    from app.domain.inventory.models import BatchDate

    household_id = _household(session)
    ingredient_id = _ingredient(session, "두부")
    batch = _batch(session, household_id, ingredient_id)
    session.add(BatchDate(batch_id=batch.batch_id, kind=DateKind.USE_BY.value, date_value=None))
    session.flush()
    assert batch.dates[0].is_confirmed is False


def test_duplicate_command_id_is_rejected(session):
    """멱등성. 같은 발화의 재시도가 PK 충돌로 막힌다."""
    from app.domain.command.models import Command

    household_id = _household(session)
    command_id = uuid4()
    for _ in range(2):
        session.add(
            Command(command_id=command_id, household_id=household_id, utterance="계란 두 개 썼어")
        )
    with pytest.raises(IntegrityError, match="pk_command"):
        session.flush()


def test_invalid_enum_value_is_rejected(session):
    """상태값은 CHECK 제약이 지킨다. 코드 테이블 없이도 값이 고정된다."""
    household_id = _household(session)
    ingredient_id = _ingredient(session, "계란")
    batch = _batch(session, household_id, ingredient_id)
    batch.storage_location = "우주"
    with pytest.raises(IntegrityError, match="storage_location"):
        session.flush()


def test_correction_does_not_double_deduct(session):
    """설계 문서의 정정 표를 그대로 실행한다.

    `계란 10개 등록 → 2개 사용(8) → 3개로 정정(7) → 정정 취소(8) → 4개 남음으로 보정(4)`
    """
    from app.core.enums import ChangeAction, CommandIntent
    from app.domain.command.models import ChangeEvent, Command

    household_id = _household(session)
    ingredient_id = _ingredient(session, "계란")
    batch = _batch(session, household_id, ingredient_id, quantity="0")

    def run(intent: str) -> Command:
        command = Command(command_id=uuid4(), household_id=household_id,
                          utterance=intent, intent=intent)
        session.add(command)
        session.flush()
        return command

    def apply(command: Command, action: str, delta: Decimal, reverses: int | None = None) -> int:
        before = batch.quantity
        batch.quantity = before + delta
        event = ChangeEvent(
            command_id=command.command_id, batch_id=batch.batch_id, action=action,
            quantity_delta=delta, quantity_before=before, quantity_after=batch.quantity,
            unit="ea", reverses_event_id=reverses,
        )
        session.add(event)
        session.flush()
        return event.change_event_id

    e1 = apply(run(CommandIntent.REGISTER.value), ChangeAction.STOCK_IN.value, Decimal("10"))
    assert batch.quantity == Decimal("10")

    e2 = apply(run(CommandIntent.CONSUME.value), ChangeAction.CONSUME.value, Decimal("-2"))
    assert batch.quantity == Decimal("8")

    correct = run(CommandIntent.CORRECT.value)
    e3 = apply(correct, ChangeAction.REVERT.value, Decimal("2"), reverses=e2)
    e4 = apply(correct, ChangeAction.CONSUME.value, Decimal("-3"))
    # 3개를 추가로 차감하지 않는다. 되돌린 뒤 다시 적용했다.
    assert batch.quantity == Decimal("7")

    cancel = run(CommandIntent.CANCEL.value)
    apply(cancel, ChangeAction.REVERT.value, Decimal("3"), reverses=e4)
    apply(cancel, ChangeAction.REVERT.value, Decimal("-2"), reverses=e3)
    assert batch.quantity == Decimal("8")

    before_adjust = batch.quantity
    batch.quantity = Decimal("4")
    session.add(
        ChangeEvent(
            command_id=run(CommandIntent.ADJUST.value).command_id, batch_id=batch.batch_id,
            action=ChangeAction.ADJUST.value, quantity_delta=Decimal("4") - before_adjust,
            quantity_before=before_adjust, quantity_after=Decimal("4"), unit="ea",
        )
    )
    session.flush()
    assert batch.quantity == Decimal("4")

    # 이력이 사실을 구분해 남았는지 확인한다.
    actions = session.execute(
        text(
            "select action from change_event where batch_id = :b order by change_event_id"
        ),
        {"b": batch.batch_id},
    ).scalars().all()
    assert actions == ["stock_in", "consume", "revert", "consume", "revert", "revert", "adjust"]
    assert e1 is not None


def test_ledger_total_matches_current_quantity(session):
    """잔량 현재값과 이벤트 누적이 어긋나면 버그다. 정합성 확인 쿼리를 둔다."""
    from app.core.enums import ChangeAction, CommandIntent
    from app.domain.command.models import ChangeEvent, Command

    household_id = _household(session)
    ingredient_id = _ingredient(session, "두부")
    batch = _batch(session, household_id, ingredient_id, quantity="0")
    command = Command(command_id=uuid4(), household_id=household_id, utterance="두부 두 모",
                      intent=CommandIntent.REGISTER.value)
    session.add(command)
    session.flush()
    batch.quantity = Decimal("2")
    session.add(
        ChangeEvent(command_id=command.command_id, batch_id=batch.batch_id,
                    action=ChangeAction.STOCK_IN.value, quantity_delta=Decimal("2"),
                    quantity_before=Decimal("0"), quantity_after=Decimal("2"), unit="mo")
    )
    session.flush()

    ledger_total = session.execute(
        text("select coalesce(sum(quantity_delta), 0) from change_event where batch_id = :b"),
        {"b": batch.batch_id},
    ).scalar_one()
    assert ledger_total == batch.quantity
