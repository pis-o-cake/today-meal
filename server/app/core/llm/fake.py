"""결정적인 가짜 게이트웨이.

**모델 없이 검증과 실행 로직을 전부 테스트하기 위한 것이다.** 버그는 해석보다 그 뒤에 있고,
그 부분은 입력이 정해지면 출력도 정해져야 한다. 호출 비용이 0 이고 결과가 흔들리지 않는다.

WARNING: 규칙 기반이라 실제 한국어 발화의 폭을 담지 못한다. 해석 품질 평가에 쓰지 않는다 —
그것은 실제 모델로 측정한다. 이 구현이 답하는 질문은 "제안이 이렇게 오면 서버가 맞게
처리하는가"다.
"""

from __future__ import annotations

import re

from app.core.enums import CommandIntent, DateKind, StorageLocation
from app.core.llm.gateway import InventoryContext
from app.core.llm.schemas import (
    CommandProposal,
    InterpretResult,
    LlmUsage,
    ProposedDate,
    ProposedItem,
)

_KOREAN_NUMBERS: dict[str, float] = {
    "한": 1, "하나": 1, "두": 2, "둘": 2, "세": 3, "셋": 3, "네": 4, "넷": 4,
    "다섯": 5, "여섯": 6, "일곱": 7, "여덟": 8, "아홉": 9, "열": 10,
    "반": 0.5,
}
_UNITS = "모|개|알|장|쪽|팩|봉|단|줌|컵|큰술|작은술|g|kg|ml|l|그램|킬로|리터"

# 의도를 가리는 신호. 순서가 곧 우선순위다 — 먼저 걸린 것이 이긴다.
_INTENT_PATTERNS: list[tuple[CommandIntent, re.Pattern[str]]] = [
    (CommandIntent.CANCEL, re.compile(r"취소|되돌려|되돌리")),
    (CommandIntent.CORRECT, re.compile(r"아니(라|고|야)?\b|아니라|이 아니라|가 아니라")),
    (CommandIntent.PLAN_FUTURE, re.compile(r"살 ?거|사야|사올|내일|다음에")),
    (CommandIntent.OPEN, re.compile(r"열었|개봉|뜯었")),
    (CommandIntent.MOVE, re.compile(r"옮겼|옮김|옮겨")),
    (CommandIntent.ADJUST, re.compile(r"남았|남아|있어\b|있다")),
    (CommandIntent.CONSUME, re.compile(r"썼|쓸|사용|넣었는데|먹었|해먹")),
    (CommandIntent.REGISTER, re.compile(r"넣었|샀|왔|들어왔|채웠")),
    (CommandIntent.RECOMMEND, re.compile(r"뭐 ?먹|추천|해먹지|만들까")),
    (CommandIntent.QUERY, re.compile(r"몇 ?개|얼마나|뭐 ?있|있나|남은")),
]

_STORAGE_PATTERNS: list[tuple[StorageLocation, re.Pattern[str]]] = [
    (StorageLocation.FREEZER, re.compile(r"냉동")),
    (StorageLocation.FRIDGE, re.compile(r"냉장")),
    (StorageLocation.PANTRY, re.compile(r"실온|상온")),
]

_DATE_KIND_PATTERNS: list[tuple[DateKind, re.Pattern[str]]] = [
    (DateKind.USE_BY, re.compile(r"소비기한")),
    (DateKind.SELL_BY, re.compile(r"유통기한")),
    (DateKind.BEST_BEFORE, re.compile(r"품질유지")),
    (DateKind.MANUFACTURED, re.compile(r"제조일")),
    (DateKind.PACKED, re.compile(r"포장일")),
]

# 수량 없이 상태만 말하는 의도. 재료명만 뽑아도 실행할 수 있다.
_BARE_NAME_INTENTS = frozenset(
    {CommandIntent.OPEN, CommandIntent.MOVE, CommandIntent.QUERY, CommandIntent.CONSUME}
)
_WAKE_WORD = re.compile(r"^\s*헤이\s*냉장고[,.]?\s*")
_NON_NAME_TOKENS = frozenset({"오늘", "어제", "아까", "방금", "지금", "내일", "전부", "다"})
_NON_NAME_PREFIXES = ("냉장", "냉동", "실온", "상온")

_ITEM_PATTERN = re.compile(
    rf"(?P<name>[가-힣A-Za-z]+?)\s*(?P<amount>\d+(?:\.\d+)?|[가-힣]{{1,3}})\s*(?P<unit>{_UNITS})"
)
_QUALITATIVE = re.compile(r"(?P<name>[가-힣A-Za-z]+?)\s*(?P<amount>조금|약간|많이|적당히)")
_DATE_PATTERN = re.compile(r"(?:(?P<month>\d{1,2})월\s*)?(?P<day>\d{1,2})일")


class FakeLlmGateway:
    """규칙으로 제안을 만든다. 호출 비용이 없다."""

    def __init__(self, *, force_clarification: bool = False) -> None:
        self._force_clarification = force_clarification
        self.calls: list[str] = []

    async def interpret(self, utterance: str, context: InventoryContext) -> InterpretResult:
        """발화를 규칙으로 해석한다."""
        self.calls.append(utterance)
        text = utterance.strip()

        intent = self._detect_intent(text)
        items = self._extract_items(text, intent)
        needs, question = self._needs_clarification(text, items)

        proposal = CommandProposal(
            intent=intent,
            items=items,
            needs_clarification=needs,
            question=question,
            correction_of_previous=intent is CommandIntent.CORRECT,
        )
        return InterpretResult(
            proposal=proposal,
            usage=LlmUsage(input_tokens=0, output_tokens=0, model="fake"),
            raw={"utterance": utterance},
        )

    def _detect_intent(self, text: str) -> CommandIntent:
        for intent, pattern in _INTENT_PATTERNS:
            if pattern.search(text):
                return intent
        return CommandIntent.UNKNOWN

    def _extract_items(self, text: str, intent: CommandIntent) -> list[ProposedItem]:
        storage = next(
            (value for value, pattern in _STORAGE_PATTERNS if pattern.search(text)), None
        )
        dates = self._extract_dates(text)
        # '남았어' 는 항목 단위로 붙는 사실이라 의도에서 내려 준다.
        is_remaining = intent is CommandIntent.ADJUST

        items: list[ProposedItem] = []
        for match in _ITEM_PATTERN.finditer(text):
            amount = self._parse_amount(match.group("amount"))
            if amount is None:
                continue
            items.append(
                ProposedItem(
                    raw_name=match.group("name"),
                    amount=amount,
                    unit_text=match.group("unit"),
                    storage=storage,
                    dates=dates if len(items) == 0 else [],
                    is_remaining=is_remaining,
                )
            )
        if not items and intent in _BARE_NAME_INTENTS:
            # 수량 없이 상태만 말한 발화다. 재료명만 뽑아 준다.
            name = self._bare_name(text)
            if name:
                items.append(ProposedItem(raw_name=name, storage=storage, dates=dates))
            return items

        for match in _QUALITATIVE.finditer(text):
            items.append(
                ProposedItem(
                    raw_name=match.group("name"),
                    qualitative_amount=match.group("amount"),
                    storage=storage,
                    is_remaining=is_remaining,
                )
            )
        return items

    def _extract_dates(self, text: str) -> list[ProposedDate]:
        match = _DATE_PATTERN.search(text)
        if match is None:
            return []
        kind = next((value for value, pattern in _DATE_KIND_PATTERNS if pattern.search(text)), None)
        month = match.group("month")
        return [
            ProposedDate(
                kind=kind,
                raw_text=match.group(0),
                month=int(month) if month else None,
                day=int(match.group("day")),
            )
        ]

    @staticmethod
    def _bare_name(text: str) -> str | None:
        """수량 없는 발화에서 재료명 하나를 뽑는다.

        호출어와 시점·위치 표현을 걷어내고 첫 낱말을 쓴다. 규칙 기반이라 좁지만, 이
        구현의 목적은 해석 품질이 아니라 뒤 단계를 시험하는 것이다.
        """
        cleaned = _WAKE_WORD.sub("", text)
        for token in cleaned.split():
            word = token.strip(",.?!").rstrip("은는이가을를도")
            if not word or word in _NON_NAME_TOKENS:
                continue
            if any(word.startswith(prefix) for prefix in _NON_NAME_PREFIXES):
                continue
            return word
        return None

    @staticmethod
    def _parse_amount(token: str) -> float | None:
        try:
            return float(token)
        except ValueError:
            return _KOREAN_NUMBERS.get(token)

    def _needs_clarification(
        self, text: str, items: list[ProposedItem]
    ) -> tuple[bool, str | None]:
        if self._force_clarification:
            return True, "확인이 필요해요."
        # '반 썼어' 처럼 기준이 없는 '반' 은 되묻는다. '두부 반 모' 는 단위가 있어 분명하다.
        if re.search(r"반\s*(?:썼|먹었|사용)", text):
            return True, "한 팩의 반인가요, 남은 양의 반인가요?"
        return False, None
