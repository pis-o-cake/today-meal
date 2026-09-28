"""모델이 내는 구조화 출력.

**이 타입들은 실행 제안이다.** 구조가 맞아도 내용이 사실이라는 뜻은 아니며, 실제 재고 변경은
`command.service` 의 검증을 통과한 뒤에만 일어난다. 그래서 여기에는 `batch_id` 처럼 서버만
아는 식별자를 두지 않는다 — 모델은 사용자가 말한 것만 옮긴다.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field

from app.core.enums import CommandIntent, DateKind, StorageLocation


class ProposedDate(BaseModel):
    """발화에서 읽은 날짜 하나.

    날짜 종류를 모르면 [kind] 를 비운다. 서버가 소비기한으로 추측하지 않는다.
    """

    model_config = ConfigDict(extra="forbid")

    kind: DateKind | None = Field(default=None, description="말한 기한 종류. 불분명하면 비운다")
    raw_text: str | None = Field(default=None, description="말한 그대로. 예 '10월 3일'")
    year: int | None = None
    month: int | None = None
    day: int | None = None


class ProposedItem(BaseModel):
    """발화에 나온 재료 한 항목.

    수량을 숫자로 말하지 않았으면 [amount] 를 비우고 [qualitative_amount] 에 표현을 남긴다.
    '조금' 을 임의의 g 으로 바꾸지 않는다.
    """

    model_config = ConfigDict(extra="forbid")

    raw_name: str = Field(min_length=1, max_length=50, description="말한 재료명 원문")
    amount: float | None = Field(default=None, ge=0, description="수량. 말하지 않았으면 비운다")
    # WARNING: 상한이 없으면 모델이 이 칸을 혼잣말 메모지로 쓴다. 실제로 그런 응답을 받았다.
    unit_text: str | None = Field(
        default=None, max_length=10, description="말한 단위 원문. 예 '모', '개', '큰술'"
    )
    qualitative_amount: str | None = Field(
        default=None, max_length=10, description="'조금'·'반' 같은 표현"
    )
    storage: StorageLocation | None = Field(default=None, description="말한 보관 위치")
    dates: list[ProposedDate] = Field(default_factory=list)
    is_remaining: bool = Field(
        default=False,
        description="'네 개 남았어'처럼 남은 양을 말했는지. 사용량과 구분하는 핵심 값",
    )


class CommandProposal(BaseModel):
    """발화 하나에 대한 모델의 제안.

    IMPORTANT: [needs_clarification] 이 참이면 서버는 아무것도 반영하지 않고 [question] 만
    되묻는다. 모델이 모호함을 스스로 신고하게 두는 것이 조용히 추측하는 것보다 안전하다.
    """

    model_config = ConfigDict(extra="forbid")

    intent: CommandIntent = Field(description="발화의 의도")
    items: list[ProposedItem] = Field(default_factory=list)
    needs_clarification: bool = Field(default=False)
    question: str | None = Field(
        default=None, max_length=200, description="되물을 한 가지. 짧게"
    )
    servings: int | None = Field(default=None, ge=1, le=12, description="말한 인분")
    max_minutes: int | None = Field(default=None, ge=1, le=600, description="말한 조리 가능 시간")
    correction_of_previous: bool = Field(
        default=False,
        description="직전 명령을 고치는 발화인지. 새 사용이 아니라 교체로 처리한다",
    )
    notes: str | None = Field(
        default=None, description="모델이 남길 짧은 메모. 사용자에게 보이지 않는다"
    )


class LlmUsage(BaseModel):
    """제공자가 보고한 사용량. 예산 가드가 이 값을 누적한다."""

    model_config = ConfigDict(extra="forbid")

    input_tokens: int = 0
    output_tokens: int = 0
    model: str = ""


class InterpretResult(BaseModel):
    """해석 호출의 결과."""

    model_config = ConfigDict(extra="forbid")

    proposal: CommandProposal
    usage: LlmUsage
    raw: dict = Field(default_factory=dict, description="원본 응답. 검증 실패 재현에 쓴다")


class ProposedRecipeIngredient(BaseModel):
    """레시피 재료 한 줄.

    분량을 정할 수 없으면 [amount] 를 비우고 [is_amount_unknown] 을 세운다. 임의의 숫자를
    만들지 않는다.
    """

    model_config = ConfigDict(extra="forbid")

    raw_name: str = Field(min_length=1, max_length=100)
    amount: float | None = Field(default=None, ge=0)
    unit_text: str | None = None
    is_essential: bool = Field(
        default=True, description="없으면 요리가 성립하지 않는 재료만 참"
    )
    is_amount_unknown: bool = False


class ProposedRecipe(BaseModel):
    """메뉴 후보 하나.

    **보유 여부를 담지 않는다.** 재고 대조는 코드가 하며, 모델이 판정하면 없는 재료로 만들 수
    있다고 말하는 화면이 나온다.
    """

    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=1, max_length=100)
    servings: int = Field(ge=1, le=12)
    estimated_minutes: int | None = Field(default=None, ge=1, le=600)
    reason: str | None = Field(default=None, description="이 메뉴를 고른 이유 한 문장")
    ingredients: list[ProposedRecipeIngredient] = Field(default_factory=list)
    steps: list[str] = Field(default_factory=list, description="조리 순서. 한 단계에 한 동작")


class MenuProposal(BaseModel):
    """추천 호출의 제안."""

    model_config = ConfigDict(extra="forbid")

    recipes: list[ProposedRecipe] = Field(default_factory=list, max_length=5)
    notes: str | None = None


class MenuResult(BaseModel):
    """추천 호출의 결과."""

    model_config = ConfigDict(extra="forbid")

    proposal: MenuProposal
    usage: LlmUsage
    raw: dict = Field(default_factory=dict)
