"""음성 명령 API. `/api/command` 에 마운트된다."""

from fastapi import APIRouter

from app.core.identity import CallerDep
from app.core.pending import not_implemented
from app.domain.command.schemas import CommandRequest, CommandResponse

router = APIRouter()


@router.post("/interpret", response_model=CommandResponse, summary="발화 해석과 실행")
async def interpret(payload: CommandRequest, caller: CallerDep) -> CommandResponse:
    """전사된 발화를 해석해 재고에 반영한다.

    처리 순서는 여섯이다 — 수신 → 명령 ID 중복 확인 → 모델 해석 → 서버 검증 → 실행 →
    응답. 모델의 출력은 실행 제안이며 검증을 통과한 뒤에만 재고가 바뀐다.
    """
    raise not_implemented("S-02", "F-04")


@router.post("/{command_id}/undo", response_model=CommandResponse, summary="직전 변경 되돌리기")
async def undo(command_id: str, caller: CallerDep) -> CommandResponse:
    """명령 묶음 전체를 되돌린다. 행을 고치지 않고 역산 이벤트를 추가한다."""
    raise not_implemented("S-06", "F-10")


@router.get("/history", summary="변경 이력")
async def history(caller: CallerDep) -> list[dict[str, object]]:
    """입고·사용·보정·정정·취소를 시간순으로 돌려준다."""
    raise not_implemented("S-06", "F-11")
