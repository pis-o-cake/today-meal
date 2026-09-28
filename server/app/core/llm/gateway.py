"""모델 연결부.

구현은 Gemini 하나지만 인터페이스를 두는 이유는 둘이다 — 한국어 명령 해석 품질이 미달일 때
교체 지점이 필요하고, **키 없이 개발할 수 있어야** 한다. 검증과 실행 로직이 버그의 대부분이고
그것은 결정적인 가짜 구현으로 전부 테스트할 수 있다.
"""

from __future__ import annotations

from typing import Protocol, runtime_checkable

from app.core.llm.schemas import InterpretResult, MenuResult


@runtime_checkable
class LlmGateway(Protocol):
    """발화를 구조화된 제안으로 바꾼다."""

    async def interpret(self, utterance: str, context: InventoryContext) -> InterpretResult:
        """발화 하나를 해석한다.

        Args:
            utterance: 전사 원문.
            context: 모델이 참고할 현재 재고와 직전 명령.

        Returns:
            제안과 사용량. **제안은 실행 권한이 없다.**

        Raises:
            UpstreamError: 제공자 오류·타임아웃·스키마 위반.
            BudgetExceededError: 호출 예산을 넘었을 때.
        """
        ...

    async def suggest_menus(self, request: MenuRequest) -> MenuResult:
        """조건에 맞는 메뉴 후보를 만든다.

        **보유 여부는 판정하지 않는다.** 모델은 후보와 필요한 재료만 내고, 재고 대조는
        `menu.service` 가 한다.

        Args:
            request: 재고·먼저 쓸 재료·인분·제약.

        Returns:
            후보와 사용량.
        """
        ...


class InventoryContext:
    """모델에 넘기는 문맥.

    재고 전체를 넘기지 않는다. 토큰이 비용이고, 관련 없는 재료가 많으면 모델이 엉뚱한 항목을
    고른다. 이름과 잔량과 기한만 짧게 넘기며 `batch_id` 는 넘기지 않는다 — 대상 선택은
    서버가 한다.
    """

    __slots__ = ("items", "previous_utterance", "timezone", "today")

    def __init__(
        self,
        items: list[str],
        today: str,
        timezone: str = "Asia/Seoul",
        previous_utterance: str | None = None,
    ) -> None:
        self.items = items
        self.today = today
        self.timezone = timezone
        self.previous_utterance = previous_utterance

    def as_prompt_block(self) -> str:
        """프롬프트에 넣을 짧은 문맥 블록."""
        lines = [f"오늘: {self.today} ({self.timezone})"]
        if self.items:
            lines.append("현재 재고:")
            lines.extend(f"- {item}" for item in self.items)
        else:
            lines.append("현재 재고: 없음")
        if self.previous_utterance:
            lines.append(f"직전 발화: {self.previous_utterance}")
        return "\n".join(lines)


class MenuRequest:
    """추천 호출의 입력.

    `available` 과 `priority` 를 나누어 넘기는 이유는 **먼저 쓸 재료를 쓰는 메뉴를 우선**해야
    하기 때문이다. 목록을 하나로 합치면 모델이 그 우선순위를 알 수 없다.
    """

    __slots__ = ("available", "avoided", "max_minutes", "priority", "servings", "tools")

    def __init__(
        self,
        available: list[str],
        priority: list[str],
        servings: int,
        *,
        max_minutes: int | None = None,
        avoided: list[str] | None = None,
        tools: list[str] | None = None,
    ) -> None:
        self.available = available
        self.priority = priority
        self.servings = servings
        self.max_minutes = max_minutes
        self.avoided = avoided or []
        self.tools = tools or []

    def as_prompt_block(self) -> str:
        """프롬프트에 넣을 재고 블록."""
        lines = []
        if self.priority:
            lines.append("먼저 쓸 재료 (이걸 쓰는 메뉴를 우선):")
            lines.extend(f"- {item}" for item in self.priority)
        lines.append("그 밖의 보유 재료:")
        lines.extend(f"- {item}" for item in self.available) if self.available else lines.append(
            "- 없음"
        )
        return "\n".join(lines)

    def constraints(self) -> list[str]:
        """프롬프트에 넣을 제약 목록."""
        out: list[str] = []
        if self.max_minutes is not None:
            out.append(f"조리 시간 {self.max_minutes}분 이내")
        if self.avoided:
            out.append(f"쓰지 말 재료: {', '.join(self.avoided)}")
        if self.tools:
            out.append(f"보유 도구: {', '.join(self.tools)}")
        return out
