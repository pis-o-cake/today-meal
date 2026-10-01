"""발화에서 읽은 날짜를 실제 날짜로 확정한다.

**임의로 넘기지 않는 것이 이 모듈의 규칙이다.** "3일까지야"처럼 월이나 연도가 빠진 발화에서
없는 값을 채워 소비기한을 만들면, 사용자가 말하지 않은 안전 판정을 앱이 지어내는 것이 된다.
확정할 수 없으면 확인을 요청한다.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from loguru import logger

# 이 일수보다 과거인 기한은 확정하지 않고 되묻는다. 지난 기한을 말할 이유가 없고,
# 대개 월을 빠뜨린 발화다 — "3일까지야" 를 지난 달 3일로 확정하면 안 된다.
PAST_TOLERANCE_DAYS = 3

# 말한 날짜의 모양. "2026년 10월 3일"·"10월 3일"·"3일" 을 읽는다.
_SPOKEN = re.compile(r"(?:(\d{4})\s*년\s*)?(?:(\d{1,2})\s*월\s*)?(\d{1,2})\s*일")


@dataclass(frozen=True, slots=True)
class ResolvedDate:
    """날짜 확정 결과.

    Attributes:
        value: 확정된 날짜. 확정하지 못하면 `None`.
        question: 되물을 한 가지. 확정했으면 `None`.
    """

    value: date | None
    question: str | None = None

    @property
    def needs_clarification(self) -> bool:
        return self.value is None and self.question is not None


def today_in(timezone: str) -> date:
    """가구 시간대의 오늘.

    발화 시점 해석의 기준이다. 서버가 UTC 로 돌아도 "오늘"은 사용자의 오늘이어야 한다.
    """
    try:
        return datetime.now(ZoneInfo(timezone)).date()
    except Exception:  # noqa: BLE001
        # 시간대 이름이 잘못되어 있어도 날짜 처리가 멈추면 안 된다.
        logger.warning("Unknown timezone {}, falling back to UTC", timezone)
        return datetime.now(ZoneInfo("UTC")).date()


def resolve(
    year: int | None,
    month: int | None,
    day: int | None,
    *,
    today: date,
    raw_text: str | None = None,
) -> ResolvedDate:
    """부분적으로 말한 날짜를 확정한다.

    Args:
        year: 말한 연도. 없으면 `None`.
        month: 말한 월.
        day: 말한 일.
        today: 가구 시간대의 오늘.
        raw_text: 되묻는 문구에 쓸 원문.

    Returns:
        확정된 날짜이거나, 확정할 수 없는 이유를 담은 질문.

    Example:
        >>> resolve(None, 10, 3, today=date(2026, 9, 28)).value
        datetime.date(2026, 10, 3)
        >>> resolve(None, None, 3, today=date(2026, 9, 28)).needs_clarification
        True
    """
    if day is None and month is None:
        ahead = _days_ahead(raw_text or "")
        if ahead is not None:
            return ResolvedDate(today + timedelta(days=ahead))

    # 모델이 말한 그대로([raw_text])만 옮기고 숫자 칸을 비우는 일이 잦다. 원문에 적힌
    # 숫자는 사용자가 말한 것이므로 읽어 쓴다 — 없는 값을 채우는 것과 다르다.
    if day is None:
        spoken = _SPOKEN.search(raw_text or "")
        if spoken is not None:
            said_year, said_month, said_day = spoken.groups()
            year = year if year is not None else _number(said_year)
            month = month if month is not None else _number(said_month)
            day = int(said_day)

    if day is None:
        return ResolvedDate(None, "며칠까지인지 알려주세요.")

    if month is None:
        # 일만 말했다. 이번 달인지 다음 달인지 추측하지 않는다.
        label = raw_text or f"{day}일"
        return ResolvedDate(None, f"{label}이 몇 월인가요?")

    resolved_year = year if year is not None else today.year
    try:
        candidate = date(resolved_year, month, day)
    except ValueError:
        return ResolvedDate(None, "날짜를 다시 말해주세요.")

    if year is not None:
        return ResolvedDate(candidate)

    # 연도를 말하지 않았다. 올해로 두되, 한참 지난 날짜면 되묻는다.
    if (today - candidate).days > PAST_TOLERANCE_DAYS:
        label = raw_text or f"{month}월 {day}일"
        return ResolvedDate(None, f"{label}이 몇 년인가요?")
    return ResolvedDate(candidate)


def _number(text: str | None) -> int | None:
    return int(text) if text else None


# 오늘부터 센 날. "내일까지"·"사흘 남았어"·"일주일 뒤" 는 사용자가 말한 날짜다.
_NAMED_DAYS: tuple[tuple[str, int], ...] = (
    ("내일모레", 2), ("모레", 2), ("글피", 3), ("내일", 1), ("오늘", 0),
    ("하루", 1), ("이틀", 2), ("사흘", 3), ("나흘", 4), ("닷새", 5), ("엿새", 6),
    ("이레", 7), ("열흘", 10), ("보름", 15),
    ("일주일", 7), ("한 주", 7), ("한주", 7), ("이주일", 14), ("삼주일", 21),
    ("한 달", 30), ("한달", 30),
)
_DAYS_AHEAD = re.compile(r"(\d+)\s*일\s*(?:남|뒤|후|있|안)")
_WEEKS_AHEAD = re.compile(r"(\d+)\s*주")
_MONTHS_AHEAD = re.compile(r"(\d+)\s*(?:개월|달)")


def _days_ahead(text: str) -> int | None:
    """남은 기간으로 말한 기한이 오늘부터 며칠 뒤인지. 그런 말이 아니면 `None`.

    "3일까지" 는 남은 기간이 아니라 날짜다 — 여기서 읽지 않고 월을 되묻는다.
    """
    days = _DAYS_AHEAD.search(text)
    if days is not None:
        return int(days.group(1))
    weeks = _WEEKS_AHEAD.search(text)
    if weeks is not None:
        return int(weeks.group(1)) * 7
    months = _MONTHS_AHEAD.search(text)
    if months is not None:
        return int(months.group(1)) * 30
    for word, ahead in _NAMED_DAYS:
        if word in text:
            return ahead
    return None
