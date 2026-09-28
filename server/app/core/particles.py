"""한국어 조사 선택.

사용자에게 보이는 문구에 재료명을 끼워 넣을 때 쓴다. "돼지고기을"처럼 조사가 틀리면 앱이
한국어를 모르는 것처럼 읽힌다.

받침 유무만 본다. 실제 발음 규칙은 더 복잡하지만, 재료명에 필요한 범위는 이것으로 덮인다.
"""

_HANGUL_START = 0xAC00
_HANGUL_END = 0xD7A3
_JONGSUNG_COUNT = 28

# 숫자를 읽는 소리의 받침 유무. "3개를" 처럼 숫자로 끝나는 이름에 쓴다.
_DIGIT_HAS_FINAL = {"0": True, "1": True, "3": True, "6": True, "7": True, "8": True}


def has_final(word: str) -> bool:
    """마지막 글자에 받침이 있는지.

    Args:
        word: 판정할 낱말.

    Returns:
        받침이 있으면 `True`. 한글도 숫자도 아니면 `False`.

    Example:
        >>> has_final("돼지고기")
        False
        >>> has_final("계란")
        True
    """
    if not word:
        return False
    last = word[-1]
    if last.isdigit():
        return _DIGIT_HAS_FINAL.get(last, False)
    code = ord(last)
    if not _HANGUL_START <= code <= _HANGUL_END:
        return False
    return (code - _HANGUL_START) % _JONGSUNG_COUNT != 0


def with_object(word: str) -> str:
    """목적격 조사를 붙인다 — 을 / 를."""
    return f"{word}{'을' if has_final(word) else '를'}"


def with_topic(word: str) -> str:
    """주제 조사를 붙인다 — 은 / 는."""
    return f"{word}{'은' if has_final(word) else '는'}"


def with_subject(word: str) -> str:
    """주격 조사를 붙인다 — 이 / 가."""
    return f"{word}{'이' if has_final(word) else '가'}"
