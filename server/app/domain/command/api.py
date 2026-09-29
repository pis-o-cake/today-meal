"""음성 명령 API. `/api/command` 에 마운트된다."""

from datetime import date
from typing import Annotated
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.identity import CallerDep
from app.core.llm.gateway import LlmGateway
from app.core.llm.provider import get_gateway
from app.domain.command import service
from app.domain.command.schemas import CommandRequest, CommandResponse, HistoryRow
from app.domain.command.service import CommandResult
from app.domain.household import service as household_service

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


@router.get("/history", response_model=list[HistoryRow], summary="변경 이력")
async def history(
    caller: CallerDep,
    session: SessionDep,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    on: Annotated[date | None, Query(description="이 날 하루치만. 가구의 시간대로 자른다")] = None,
) -> list[HistoryRow]:
    """입고·사용·보정·정정·취소·개봉·이동을 최근 순으로 돌려준다.

    수량 변경과 상태 변경을 한 타임라인에 섞으며, 상태 변경은 잔량 칸이 비어 있다 —
    개봉과 이동은 수량을 바꾸지 않는다는 사실이 화면에 드러나야 한다.

    `on` 을 주면 그 날 하루치만 돌려준다. 기록 화면이 날짜별로 보여주기 위한 것이다.
    """
    household = await household_service.get_household(session, caller.household_id)
    return await service.history(
        session,
        household_id=caller.household_id,
        limit=limit,
        on=on,
        timezone=household.timezone,
    )


@router.get("/history/days", response_model=list[date], summary="기록이 있는 날짜")
async def history_days(
    caller: CallerDep,
    session: SessionDep,
    limit: Annotated[int, Query(ge=1, le=365)] = 60,
) -> list[date]:
    """기록이 남은 날짜를 최근 순으로 돌려준다.

    달력이 **기록이 있는 날만** 고르게 하기 위한 것이다. 없는 날을 고르면 빈 화면이 나오고,
    사용자는 자기가 잘못 골랐는지 기록이 없는지 알 수 없다.
    """
    household = await household_service.get_household(session, caller.household_id)
    return await service.history_days(
        session, household_id=caller.household_id, timezone=household.timezone, limit=limit
    )
