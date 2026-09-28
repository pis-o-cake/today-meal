"""상태값 상수.

DB 의 CHECK 제약과 **같은 목록을 공유한다.** 코드 테이블을 두지 않기로 했으므로
([데이터 모델 설계](../../../docs/design/0002-database.md)) 값의 정본이 이 파일이다.
값을 추가할 때는 Alembic 마이그레이션의 CHECK 제약도 함께 고친다.
"""

from enum import StrEnum


class StorageLocation(StrEnum):
    FRIDGE = "fridge"
    FREEZER = "freezer"
    PANTRY = "pantry"
    UNKNOWN = "unknown"


class DateKind(StrEnum):
    """날짜 종류. 서로 변환하지 않는다 — 제조일을 소비기한으로 승격하지 않는다."""

    USE_BY = "use_by"
    SELL_BY = "sell_by"
    BEST_BEFORE = "best_before"
    MANUFACTURED = "manufactured"
    PACKED = "packed"
    CHECK_REMINDER = "check_reminder"


class DateSource(StrEnum):
    VOICE = "voice"
    LABEL_PHOTO = "label_photo"
    MANUAL = "manual"
    UNKNOWN = "unknown"


class QuantityCertainty(StrEnum):
    EXACT = "exact"
    ESTIMATED = "estimated"
    QUALITATIVE = "qualitative"
    UNKNOWN = "unknown"


class StateEventKind(StrEnum):
    PURCHASED = "purchased"
    STOCKED_IN = "stocked_in"
    OPENED = "opened"
    PORTIONED = "portioned"
    FROZEN = "frozen"
    THAWED = "thawed"
    MOVED = "moved"


class CommandIntent(StrEnum):
    REGISTER = "register"
    CONSUME = "consume"
    ADJUST = "adjust"
    # 수량이 아니라 상태가 바뀌는 발화. "우유 오늘 열었어" · "고기 냉동실로 옮겼어"
    OPEN = "open"
    MOVE = "move"
    QUERY = "query"
    CORRECT = "correct"
    CANCEL = "cancel"
    RECOMMEND = "recommend"
    PLAN_FUTURE = "plan_future"
    UNKNOWN = "unknown"


class CommandStatus(StrEnum):
    PENDING = "pending"
    CLARIFYING = "clarifying"
    APPLIED = "applied"
    REJECTED = "rejected"
    FAILED = "failed"
    SUPERSEDED = "superseded"
    REVERTED = "reverted"


class ChangeAction(StrEnum):
    """`CONSUME` 과 `ADJUST` 를 가르는 것이 F-08 의 완료 기준이다.

    "두 개 썼어"와 "두 개 남았어"는 결과 잔량이 같아도 다른 사실이다.
    """

    STOCK_IN = "stock_in"
    CONSUME = "consume"
    ADJUST = "adjust"
    DISCARD = "discard"
    MOVE = "move"
    SPLIT = "split"
    REVERT = "revert"


class RecipeSource(StrEnum):
    SEED = "seed"
    LLM = "llm"
    VIDEO = "video"


class MenuAvailability(StrEnum):
    READY = "ready"
    NEEDS_CHECK = "needs_check"
    NEEDS_PURCHASE = "needs_purchase"


class PreferenceKind(StrEnum):
    AVOIDED = "avoided"
    ALLERGY = "allergy"
    PANTRY_STAPLE = "pantry_staple"


class VideoRecipeStatus(StrEnum):
    PENDING = "pending"
    ANALYZED = "analyzed"
    FAILED = "failed"


class VideoInputKind(StrEnum):
    VIDEO_URL = "video_url"
    PASTED_TEXT = "pasted_text"


class ShoppingStatus(StrEnum):
    PENDING = "pending"
    SEARCHED = "searched"
    PURCHASED = "purchased"
    STOCKED_IN = "stocked_in"
    DISMISSED = "dismissed"


class PriorityReason(StrEnum):
    """먼저 확인할 이유.

    `EXPIRED` 는 '오늘 요리할 재료' 후보에서 빼고 별도 확인 대상으로 둔다. 나머지는 후보에
    남기며 순서만 앞으로 당긴다.
    """

    EXPIRED = "expired"
    EXPIRING = "expiring"
    OPENED = "opened"
    QUANTITY_UNKNOWN = "quantity_unknown"


class FreshnessGrade(StrEnum):
    """재료 한 묶음의 신선도 등급.

    **기한 축만 담는다.** 잔량 미확인은 별도 신호로 분리한다 — 둘을 한 등급에 섞으면
    "기한은 멀지만 양을 모르는" 재료와 "곧 상하는" 재료가 같은 칸에 들어간다.

    IMPORTANT: 안전 여부를 판정하는 값이 아니다. `EXPIRED` 는 표시기한이 지났다는 사실만
    말하며, 먹을 수 있는지는 사용자가 판단한다.
    """

    FRESH = "fresh"
    SOON = "soon"
    URGENT = "urgent"
    EXPIRED = "expired"
    UNKNOWN = "unknown"


class FridgeCondition(StrEnum):
    """냉장고 전체 컨디션.

    화면 맨 위에 한 낱말로 뜨는 값이다. 계산은 서버가 하고 앱은 담기만 한다 —
    기준이 앱에 있으면 화면마다 달라진다.
    """

    RELAXED = "relaxed"
    ATTENTION = "attention"
    URGENT = "urgent"


class HistoryKind(StrEnum):
    """이력 한 줄의 종류. 수량 변경과 상태 변경을 한 타임라인에 섞어 보여준다."""

    QUANTITY = "quantity"
    STATE = "state"


class AuthProvider(StrEnum):
    KAKAO = "kakao"
    GOOGLE = "google"
    APPLE = "apple"
    DEVICE = "device"


def values(enum_cls: type[StrEnum]) -> list[str]:
    """CHECK 제약 생성에 쓰는 값 목록."""
    return [member.value for member in enum_cls]
