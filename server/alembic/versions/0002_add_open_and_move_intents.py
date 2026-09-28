"""Add open and move command intents

상태만 바꾸는 발화를 위한 의도 둘을 허용값에 더한다 — "우유 오늘 열었어"(개봉)와
"고기 냉동실로 옮겼어"(이동). 기획서 §5.1 에 있던 발화인데 초기 스키마의 CHECK 제약이
두 값을 갖지 않아 막혔다.

상태값의 정본은 `app/core/enums.py` 다. 그 목록을 고칠 때 이 제약도 함께 고친다 —
둘이 어긋나면 런타임이 아니라 DB 가 막는다.

Revision ID: 0002
Revises: 0001
Create Date: 2026-09-28
"""

from collections.abc import Sequence

from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# IMPORTANT: 이름 규약(`ck_%(table_name)s_%(constraint_name)s`)이 접두사를 붙인다.
# 여기에는 규약이 감쌀 짧은 이름만 준다. 전체 이름을 주면 ck_command_ck_command_intent 가 된다.
_CONSTRAINT = "intent"
_TABLE = "command"

_BEFORE = (
    "register", "consume", "adjust", "query", "correct",
    "cancel", "recommend", "plan_future", "unknown",
)
_AFTER = (
    "register", "consume", "adjust", "open", "move", "query",
    "correct", "cancel", "recommend", "plan_future", "unknown",
)


def _allowed(values: Sequence[str]) -> str:
    joined = ", ".join(f"'{value}'" for value in values)
    return f"intent IN ({joined})"


def upgrade() -> None:
    op.drop_constraint(_CONSTRAINT, _TABLE, type_="check")
    op.create_check_constraint(_CONSTRAINT, _TABLE, _allowed(_AFTER))


def downgrade() -> None:
    # WARNING: 되돌리기 전에 open·move 로 기록된 명령이 있으면 제약 생성이 실패한다.
    # 개발 DB 에서만 되돌린다.
    op.drop_constraint(_CONSTRAINT, _TABLE, type_="check")
    op.create_check_constraint(_CONSTRAINT, _TABLE, _allowed(_BEFORE))
