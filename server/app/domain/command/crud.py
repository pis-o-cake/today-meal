"""명령과 변경 이벤트 조회. 트랜잭션은 service 가 관리한다."""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.enums import CommandStatus, HistoryKind
from app.domain.command.models import ChangeEvent, Command
from app.domain.inventory.models import BatchStateEvent, IngredientBatch


async def get(session: AsyncSession, command_id: UUID) -> Command | None:
    """명령 하나를 읽는다. 멱등 확인의 첫 단계다."""
    result = await session.execute(select(Command).where(Command.command_id == command_id))
    return result.scalar_one_or_none()


async def latest_applied(session: AsyncSession, household_id: int) -> Command | None:
    """되돌리거나 고칠 대상이 되는 직전 명령.

    `applied` 만 본다. 되물었다 끝난 명령이나 실패한 명령은 되돌릴 것이 없다. 이미
    `superseded`·`reverted` 된 명령도 대상이 아니다 — 같은 것을 두 번 되돌리면 잔량이 틀어진다.
    """
    result = await session.execute(
        select(Command)
        .where(
            Command.household_id == household_id,
            Command.status == CommandStatus.APPLIED.value,
        )
        .order_by(Command.created_at.desc(), Command.command_id)
        .limit(1)
    )
    return result.scalar_one_or_none()


async def list_history(
    session: AsyncSession, household_id: int, limit: int
) -> list[tuple[HistoryKind, object]]:
    """수량 변경과 상태 변경을 한 타임라인으로 돌려준다.

    두 테이블을 `UNION` 하지 않고 각각 읽어 Python 에서 합친다. 컬럼이 달라 `UNION` 이
    읽기 어려워지고, 이력은 최근 것만 보므로 두 번 읽는 비용이 작다.
    """
    quantity = await session.execute(
        select(ChangeEvent)
        .join(Command, Command.command_id == ChangeEvent.command_id)
        .where(Command.household_id == household_id)
        # 화면이 "말한 문장 → 바뀐 결과" 로 보여주므로 명령을 함께 읽는다.
        .options(selectinload(ChangeEvent.batch), selectinload(ChangeEvent.command))
        .order_by(ChangeEvent.change_event_id.desc())
        .limit(limit)
    )
    state = await session.execute(
        select(BatchStateEvent)
        .join(IngredientBatch, IngredientBatch.batch_id == BatchStateEvent.batch_id)
        .where(IngredientBatch.household_id == household_id)
        .options(selectinload(BatchStateEvent.batch))
        .order_by(BatchStateEvent.state_event_id.desc())
        .limit(limit)
    )
    rows: list[tuple[HistoryKind, object]] = [
        (HistoryKind.QUANTITY, row) for row in quantity.scalars()
    ]
    rows += [(HistoryKind.STATE, row) for row in state.scalars()]
    rows.sort(key=lambda pair: pair[1].created_at, reverse=True)
    return rows[:limit]
