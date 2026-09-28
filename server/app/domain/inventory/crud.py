"""재고 묶음 조회."""

from datetime import date
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.domain.command.models import ChangeEvent
from app.domain.inventory.models import BatchDate, IngredientBatch


async def list_active(
    session: AsyncSession, household_id: int, limit: int
) -> list[IngredientBatch]:
    """취소로 숨기지 않은 묶음을 돌려준다.

    날짜 정보를 `selectinload` 로 함께 읽는다. 묶음마다 따로 질의하면 대시보드 갱신에서
    N+1 이 된다.
    """
    statement = (
        select(IngredientBatch)
        .where(
            IngredientBatch.household_id == household_id,
            IngredientBatch.deleted_at.is_(None),
        )
        .options(selectinload(IngredientBatch.dates))
        .order_by(IngredientBatch.created_at.desc())
        .limit(limit)
    )
    result = await session.execute(statement)
    return list(result.scalars())


async def list_dates(session: AsyncSession, batch_ids: list[int]) -> list[BatchDate]:
    """여러 묶음의 날짜 정보를 한 번에 읽는다."""
    if not batch_ids:
        return []
    result = await session.execute(select(BatchDate).where(BatchDate.batch_id.in_(batch_ids)))
    return list(result.scalars())


async def find_target_batches(
    session: AsyncSession, household_id: int, ingredient_id: int
) -> list[IngredientBatch]:
    """차감·보정 대상이 될 수 있는 묶음을 우선순위대로 돌려준다.

    순서는 **먼저 먹어야 할 것**이다 — 표시기한이 이른 것, 없으면 먼저 들어온 것. 사용자가
    어느 팩인지 말하지 않았을 때 앱이 고르는 기준이며, 후보가 둘 이상이면 서비스가 되묻는다.
    """
    statement = (
        select(IngredientBatch)
        .where(
            IngredientBatch.household_id == household_id,
            IngredientBatch.ingredient_id == ingredient_id,
            IngredientBatch.deleted_at.is_(None),
        )
        .options(selectinload(IngredientBatch.dates))
        .order_by(IngredientBatch.created_at)
    )
    result = await session.execute(statement)
    batches = list(result.scalars())

    def sort_key(batch: IngredientBatch) -> tuple[int, date, int]:
        # 기한이 있는 묶음을 먼저, 그 안에서 이른 날짜를 먼저 쓴다.
        soonest = min(
            (d.date_value for d in batch.dates if d.date_value is not None),
            default=None,
        )
        has_date = 0 if soonest is not None else 1
        return (has_date, soonest or date.max, batch.batch_id)

    return sorted(batches, key=sort_key)


async def get_batch(session: AsyncSession, batch_id: int) -> IngredientBatch | None:
    """묶음 하나를 날짜 정보와 함께 읽는다."""
    result = await session.execute(
        select(IngredientBatch)
        .where(IngredientBatch.batch_id == batch_id)
        .options(selectinload(IngredientBatch.dates))
    )
    return result.scalar_one_or_none()


async def list_events_of_command(session: AsyncSession, command_id: UUID) -> list[ChangeEvent]:
    """한 명령이 만든 변경 이벤트를 적용 순서대로 돌려준다."""
    result = await session.execute(
        select(ChangeEvent)
        .where(ChangeEvent.command_id == command_id)
        .order_by(ChangeEvent.change_event_id)
    )
    return list(result.scalars())
