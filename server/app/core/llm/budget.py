"""모델 호출 예산 가드.

정상 사용량은 작다 — 3일 전체가 $2 규모다. **실제 위험은 재시도 루프**다. 버그 하나가
같은 호출을 초당 수십 번 반복하면 한도를 몇 분에 태운다.

그래서 제공자의 청구 한도와 별개로 프로세스 안에도 문을 둔다. 청구 한도는 사후에 막고
이 가드는 사전에 막는다.

CAUTION: 프로세스 메모리에만 있는 집계다. 워커가 여럿이면 워커마다 따로 센다.
운영에서 정확한 총량이 필요하면 DB 나 Redis 로 옮긴다. MVP 는 단일 기기 시연이라
이 범위로 둔다.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from threading import Lock

from loguru import logger

from app.core.exceptions import DomainError


class BudgetExceededError(DomainError):
    """예산을 넘었다. 호출하지 않고 거부한다."""

    message_key = "error.upstream_failed"
    status_code = 429


@dataclass(slots=True)
class BudgetSnapshot:
    """지금까지 쓴 양.

    Attributes:
        calls: 호출 수.
        input_tokens: 누적 입력 토큰.
        output_tokens: 누적 출력 토큰.
        estimated_usd: 단가로 환산한 추정 비용. 청구서와 일치한다고 보장하지 않는다.
    """

    calls: int = 0
    input_tokens: int = 0
    output_tokens: int = 0
    estimated_usd: float = 0.0


@dataclass(slots=True)
class CallBudget:
    """호출 예산.

    셋을 동시에 본다 — 창 안의 호출 수, 누적 추정 비용, 초당 호출 속도. 어느 하나라도
    넘으면 호출하지 않는다.

    Attributes:
        max_calls_per_window: 창 안에서 허용할 호출 수.
        window_seconds: 창 길이. 기본은 하루다.
        max_usd: 누적 추정 비용 상한.
        min_interval_seconds: 연속 호출 사이의 최소 간격. 재시도 루프를 잡는다.
        price_per_million_input: 입력 100만 토큰 단가.
        price_per_million_output: 출력 100만 토큰 단가.
    """

    max_calls_per_window: int = 2_000
    window_seconds: float = 86_400.0
    max_usd: float = 10.0
    min_interval_seconds: float = 0.5
    price_per_million_input: float = 0.75
    price_per_million_output: float = 3.75

    _lock: Lock = field(default_factory=Lock, repr=False)
    _snapshot: BudgetSnapshot = field(default_factory=BudgetSnapshot, repr=False)
    _window_started_at: float = field(default_factory=time.monotonic, repr=False)
    _last_call_at: float = field(default=0.0, repr=False)

    def snapshot(self) -> BudgetSnapshot:
        """현재 사용량을 복사해 돌려준다."""
        with self._lock:
            return BudgetSnapshot(
                calls=self._snapshot.calls,
                input_tokens=self._snapshot.input_tokens,
                output_tokens=self._snapshot.output_tokens,
                estimated_usd=self._snapshot.estimated_usd,
            )

    def check(self) -> None:
        """호출 직전에 부른다.

        Raises:
            BudgetExceededError: 호출 수·비용 상한을 넘었거나 호출이 너무 촘촘할 때.
        """
        now = time.monotonic()
        with self._lock:
            if now - self._window_started_at >= self.window_seconds:
                logger.info(
                    "Budget window rolled over: {} calls, ${:.4f} used",
                    self._snapshot.calls,
                    self._snapshot.estimated_usd,
                )
                self._snapshot = BudgetSnapshot()
                self._window_started_at = now

            if self._snapshot.estimated_usd >= self.max_usd:
                raise BudgetExceededError(
                    f"llm budget exhausted: ${self._snapshot.estimated_usd:.4f} "
                    f">= ${self.max_usd:.2f}"
                )
            if self._snapshot.calls >= self.max_calls_per_window:
                raise BudgetExceededError(
                    f"llm call budget exhausted: {self._snapshot.calls} "
                    f">= {self.max_calls_per_window}"
                )
            if self._last_call_at and now - self._last_call_at < self.min_interval_seconds:
                # IMPORTANT: 정상 사용에서는 사람이 말하는 속도라 절대 걸리지 않는다.
                # 걸렸다면 재시도 루프다.
                raise BudgetExceededError(
                    f"llm calls too frequent: {now - self._last_call_at:.3f}s "
                    f"< {self.min_interval_seconds}s"
                )
            self._last_call_at = now

    def record(self, input_tokens: int, output_tokens: int) -> BudgetSnapshot:
        """호출이 끝난 뒤 실제 사용량을 더한다.

        Args:
            input_tokens: 제공자가 보고한 입력 토큰.
            output_tokens: 제공자가 보고한 출력 토큰.

        Returns:
            반영 후 사용량.
        """
        delta = (
            input_tokens / 1_000_000 * self.price_per_million_input
            + output_tokens / 1_000_000 * self.price_per_million_output
        )
        with self._lock:
            self._snapshot.calls += 1
            self._snapshot.input_tokens += input_tokens
            self._snapshot.output_tokens += output_tokens
            self._snapshot.estimated_usd += delta
            used = self._snapshot.estimated_usd
            calls = self._snapshot.calls

        # 매 호출의 실측을 남긴다. 예상과 실제의 차이를 사후에 비교할 수 있어야 한다.
        logger.info(
            "LLM call recorded: in={} out={} cost=${:.6f} total=${:.4f} calls={}",
            input_tokens,
            output_tokens,
            delta,
            used,
            calls,
        )
        if used >= self.max_usd * WARN_RATIO:
            logger.warning(
                "LLM budget at {:.0%}: ${:.4f} of ${:.2f}", used / self.max_usd, used, self.max_usd
            )
        return self.snapshot()


WARN_RATIO = 0.8
