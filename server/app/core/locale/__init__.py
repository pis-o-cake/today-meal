"""사용자에게 보이는 문구의 메시지 팩.

로그와 내부 예외는 영어로 고정하고, 이 모듈이 다루는 것은 **사용자에게 보이는 문구뿐**이다.
지금은 한국어만 있으나 파일을 추가하면 언어가 늘어난다.
"""

import json
from functools import lru_cache
from pathlib import Path

DEFAULT_LOCALE = "ko"
_LOCALE_DIR = Path(__file__).parent


@lru_cache
def _messages(locale: str) -> dict[str, str]:
    path = _LOCALE_DIR / f"{locale}.json"
    if not path.exists():
        path = _LOCALE_DIR / f"{DEFAULT_LOCALE}.json"
    return json.loads(path.read_text(encoding="utf-8"))


def translate(key: str, locale: str = DEFAULT_LOCALE) -> str:
    """메시지 키를 문구로 바꾼다.

    Args:
        key: 메시지 키. 예 `error.not_found`.
        locale: 언어 코드. 없는 언어는 기본 언어로 대체한다.

    Returns:
        찾은 문구. 키가 없으면 키 자체를 돌려주어 누락을 드러낸다.
    """
    return _messages(locale).get(key, key)


def unit_label(symbol: str | None, locale: str = DEFAULT_LOCALE) -> str:
    """단위 기호를 사용자에게 읽어주고 보여줄 표기로 바꾼다.

    저장과 계산은 `ea`·`mo` 같은 기호로 하고, 사용자에게는 이 표기만 내보낸다. 기호를
    그대로 읽으면 "계란 2ea" 가 된다.

    Args:
        symbol: 정규화된 단위 기호. 예 `ea`, `mo`.
        locale: 언어 코드. 없는 언어는 기본 언어로 대체한다.

    Returns:
        표기. 기호가 없으면 빈 문자열, 메시지 팩에 없는 기호는 기호 그대로.
    """
    if not symbol:
        return ""
    key = f"unit.{symbol}"
    label = translate(key, locale)
    return symbol if label == key else label
