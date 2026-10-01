"""Add restore payload to change events

화면에서 고친 이름·기한·보관 위치를 되돌릴 수 있게 한다. 이전 판본은 수량만 원장에
남겨서, 이름이나 날짜를 고친 뒤 되돌리기를 눌러도 그 값이 돌아오지 않았다.

`restore_payload` 는 **바꾸기 전의 값**이다. 되돌리기는 이 값을 그대로 다시 쓴다.
수량은 기존 컬럼이 이미 갖고 있으므로 여기 담지 않는다.

Revision ID: 0004
Revises: 0003
Create Date: 2026-09-29
"""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0004"
down_revision: str | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "change_event",
        sa.Column(
            "restore_payload",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=True,
            comment="되돌릴 때 복원할 이전 값. 수량 외 필드용",
        ),
    )


def downgrade() -> None:
    op.drop_column("change_event", "restore_payload")
