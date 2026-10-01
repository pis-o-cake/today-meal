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


def with_means(word: str) -> str:
    """수단을 나타내는 조사를 붙인다 — 으로 / 로. ㄹ 받침 뒤에는 '로' 다."""
    last = word[-1:] if word else ""
    code = ord(last) if last else 0
    if _HANGUL_START <= code <= _HANGUL_END and (code - _HANGUL_START) % _JONGSUNG_COUNT == 8:
        return f"{word}로"
    return f"{word}{'으로' if has_final(word) else '로'}"


def with_topic(word: str) -> str:
    """주제 조사를 붙인다 — 은 / 는."""
    return f"{word}{'은' if has_final(word) else '는'}"


def with_subject(word: str) -> str:
    """주격 조사를 붙인다 — 이 / 가."""
    return f"{word}{'이' if has_final(word) else '가'}"


# 사용자에게 보이는 문구에 넣을 수 있는 최대 길이. 넘으면 잘라낸다.
MAX_SPEECH_FRAGMENT = 30


def sanitize_fragment(value: str | None, *, limit: int = MAX_SPEECH_FRAGMENT) -> str | None:
    """모델이 준 문자열을 사용자 문구에 넣을 수 있게 정제한다.

    IMPORTANT: **모델 출력을 사용자 문구에 그대로 넣지 않는다.** 실제로 모델이 단위 칸에
    영어 혼잣말을 흘려 넣었고 그것이 되묻는 질문에 그대로 나갔다.

    줄바꿈을 없애고 길이를 자른다. 정제 후 비면 `None` 을 돌려주어 호출자가 그 조각을 빼고
    문구를 만들게 한다.

    Args:
        value: 모델이 준 문자열.
        limit: 허용할 최대 길이.

    Returns:
        정제된 문자열이거나, 쓸 수 없으면 `None`.

    Example:
        >>> sanitize_fragment("모랑")
        '모랑'
        >>> sanitize_fragment("a" * 100) is None
        True
    """
    if value is None:
        return None
    flattened = " ".join(value.split())
    if not flattened:
        return None
    if len(flattened) > limit:
        # 길면 잘라 쓰지 않고 버린다. 잘린 혼잣말도 사용자에게는 뜻 없는 소리다.
        return None
    return flattened
