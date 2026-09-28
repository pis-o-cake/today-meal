"""명령과 변경 이벤트 조회. 트랜잭션은 service 가 관리한다."""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.enums import CommandStatus
from app.domain.command.models import Command


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
