"""Alembic 환경.

DB URL 은 `pydantic-settings` 에서 읽는다. `alembic.ini` 에 비밀값을 두지 않는다.
모델은 `app.core.router.import_domain_models` 로 모아 `Base.metadata` 를 채운다 —
도메인을 추가할 때 이 파일을 고치지 않는다.
"""

from logging.config import fileConfig

from sqlalchemy import engine_from_config, pool

from alembic import context
from app.core.config import get_settings
from app.core.models import Base
from app.core.router import import_domain_models

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

import_domain_models()
target_metadata = Base.metadata

config.set_main_option("sqlalchemy.url", get_settings().alembic_url)


def run_migrations_offline() -> None:
    """DB 없이 SQL 만 렌더링한다. `--sql` 로 마이그레이션을 검증할 때 쓴다."""
    context.configure(
        url=config.get_main_option("sqlalchemy.url"),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """실제 DB 에 적용한다."""
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
