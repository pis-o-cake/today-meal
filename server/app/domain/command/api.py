"""음성 명령 API. `/api/command` 에 마운트된다."""

from typing import Annotated
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.identity import CallerDep
from app.core.llm.gateway import LlmGateway
from app.core.llm.provider import get_gateway
from app.core.pending import not_implemented
from app.domain.command import service
from app.domain.command.schemas import CommandRequest, CommandResponse
from app.domain.command.service import CommandResult

router = APIRouter()

SessionDep = Annotated[AsyncSession, Depends(get_session)]
GatewayDep = Annotated[LlmGateway, Depends(get_gateway)]


def _to_response(result: CommandResult) -> CommandResponse:
    return CommandResponse(
        command_id=result.command_id,
        status=result.status.value,
        intent=result.intent.value,
        spoken=result.spoken,
        clarification_question=result.clarification_question,
        screen=result.screen or {},
        undo_token=result.undo_token,
    )


@router.post("/interpret", response_model=CommandResponse, summary="발화 해석과 실행")
async def interpret(
    payload: CommandRequest,
    caller: CallerDep,
    session: SessionDep,
    gateway: GatewayDep,
) -> CommandResponse:
    """전사된 발화를 해석해 재고에 반영한다.

    `command_id` 는 **앱이 발화마다 만들어** 보낸다. 같은 값으로 다시 부르면 저장된 결과를
    그대로 돌려주므로 네트워크 재시도가 재고를 두 번 바꾸지 않는다.

    모델 출력은 실행 제안이며 서버 검증을 통과한 뒤에만 재고가 바뀐다. 검증에서 걸리면
    `clarification_question` 만 채워 돌려주고 **아무것도 반영하지 않는다.**
    """
    result = await service.interpret(
        session,
        gateway,
        household_id=caller.household_id,
        command_id=payload.command_id,
        utterance=payload.utterance,
        locale=payload.locale,
    )
    return _to_response(result)


@router.post("/{command_id}/undo", response_model=CommandResponse, summary="직전 변경 되돌리기")
async def undo(
    command_id: UUID,
    caller: CallerDep,
    session: SessionDep,
) -> CommandResponse:
    """명령 묶음 전체를 되돌린다.

    행을 고치지 않고 역산 이벤트를 추가하므로 되돌린 것을 다시 되돌릴 수 있고, 이력에
    무엇이 일어났는지가 남는다.
    """
    result = await service.undo(
        session,
        household_id=caller.household_id,
        command_id=uuid4(),
        target_command_id=command_id,
    )
    return _to_response(result)


@router.get("/history", summary="변경 이력")
async def history(caller: CallerDep) -> list[dict[str, object]]:
    """입고·사용·보정·정정·취소를 시간순으로 돌려준다."""
    raise not_implemented("S-06", "F-11")
