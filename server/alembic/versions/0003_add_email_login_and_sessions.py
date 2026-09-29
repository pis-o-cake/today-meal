"""Add email login and verified sessions

`app_user` 에 이메일과 비밀번호 해시를 더하고 `user_session` 을 만든다. 이전 판본은
`X-User-Id` 헤더를 검증 없이 믿었고, 계정마다 다른 가구를 갖게 되면서 그 헤더 하나로
남의 냉장고를 읽을 수 있게 되므로 검증하는 세션이 필요하다.

`provider` 허용값에 `email` 을 더한다. 상태값의 정본은 `app/core/enums.py` 이며 그
목록을 고칠 때 이 제약도 함께 고친다.

비밀번호 원문과 토큰 원문은 DB 에 두지 않는다 — 해시만 담는다.

Revision ID: 0003
Revises: 0002
Create Date: 2026-09-29
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# IMPORTANT: 이름 규약(`ck_%(table_name)s_%(constraint_name)s`)이 접두사를 붙인다.
# drop 에도 같은 규약이 걸리므로 **짧은 이름**을 준다. 전체 이름을 주면
# ck_app_user_ck_app_user_provider 를 찾는다.
_PROVIDER_CHECK = "provider"
_OLD_PROVIDERS = ("kakao", "google", "apple", "device")
_NEW_PROVIDERS = ("email", *_OLD_PROVIDERS)


def _provider_check(values: tuple[str, ...]) -> str:
    joined = ", ".join(f"'{value}'" for value in values)
    return f"provider IN ({joined})"


def upgrade() -> None:
    op.add_column("app_user", sa.Column("email", sa.String(length=320), nullable=True))
    op.add_column(
        "app_user", sa.Column("password_hash", sa.String(length=100), nullable=True)
    )
    op.create_unique_constraint("uq_app_user_email", "app_user", ["email"])

    op.drop_constraint(_PROVIDER_CHECK, "app_user", type_="check")
    op.create_check_constraint(_PROVIDER_CHECK, "app_user", _provider_check(_NEW_PROVIDERS))

    op.create_table(
        "user_session",
        sa.Column("session_id", sa.BigInteger(), sa.Identity(), nullable=False),
        sa.Column("user_id", sa.BigInteger(), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["app_user.user_id"],
            name="fk_user_session_user_id",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("session_id", name="pk_user_session"),
        sa.UniqueConstraint("token_hash", name="uq_user_session_token_hash"),
    )
    # 요청마다 토큰으로 조회한다. 살아 있는 세션만 보므로 만료도 같이 읽는다.
    op.create_index(
        "ix_user_session_token_hash_expires_at",
        "user_session",
        ["token_hash", "expires_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_user_session_token_hash_expires_at", table_name="user_session")
    op.drop_table("user_session")

    # 이메일 계정이 남아 있으면 되돌릴 수 없다. 조용히 지우지 않고 막는다.
    op.execute(
        "DO $$ BEGIN "
        "IF EXISTS (SELECT 1 FROM app_user WHERE provider = 'email') THEN "
        "RAISE EXCEPTION 'email accounts exist; remove them before downgrading'; "
        "END IF; END $$;"
    )
    op.drop_constraint(_PROVIDER_CHECK, "app_user", type_="check")
    op.create_check_constraint(_PROVIDER_CHECK, "app_user", _provider_check(_OLD_PROVIDERS))

    op.drop_constraint("uq_app_user_email", "app_user", type_="unique")
    op.drop_column("app_user", "password_hash")
    op.drop_column("app_user", "email")
