"""표준 재료 사전.

`inventory` · `menu` · `shopping` 셋이 모두 표준 재료명으로 조인하므로 독립 도메인으로 둔다.
"""

from sqlalchemy import BigInteger, Boolean, Identity, Index, String, text
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.orm import Mapped, mapped_column

from app.core.models import Base, TimestampMixin


class Ingredient(Base, TimestampMixin):
    """표준 재료명과 별칭.

    별칭을 별도 테이블로 두지 않고 배열로 둔다. 조인해 쓰지 않고 항상 통째로 읽으며 GIN
    인덱스로 포함 검색이 된다. 문자열만으로 재고를 매칭하면 `대파` 와 `파` 에서 깨지므로
    이 테이블이 필요하다.
    """

    __tablename__ = "ingredient"
    __table_args__ = (
        Index("ix_ingredient_aliases", "aliases", postgresql_using="gin"),
    )

    ingredient_id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    canonical_name: Mapped[str] = mapped_column(String(100), nullable=False, unique=True)
    aliases: Mapped[list[str]] = mapped_column(
        ARRAY(String(100)), nullable=False, server_default=text("'{}'")
    )
    category: Mapped[str | None] = mapped_column(String(30))
    default_unit: Mapped[str | None] = mapped_column(String(20))
    is_pantry_staple: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default=text("false")
    )
