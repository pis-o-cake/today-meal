"""도메인 예외와 HTTP 매핑.

예외 메시지는 **영어로 고정한다.** 검색 가능한 로그를 위해서다. 사용자에게 보일 문구는
`app/core/locale` 의 메시지 팩에서 온다.
"""

from fastapi import FastAPI, Request, status
from fastapi.responses import JSONResponse
from loguru import logger


class DomainError(Exception):
    """도메인 규칙 위반. 서버 결함이 아니다.

    Attributes:
        message_key: 사용자에게 보일 문구를 찾는 메시지 팩 키.
        status_code: 응답 코드.
        detail: 로그에 남길 영어 설명.
    """

    message_key = "error.unexpected"
    status_code = status.HTTP_400_BAD_REQUEST

    def __init__(self, detail: str, *, message_key: str | None = None) -> None:
        super().__init__(detail)
        self.detail = detail
        if message_key is not None:
            self.message_key = message_key


class NotFoundError(DomainError):
    message_key = "error.not_found"
    status_code = status.HTTP_404_NOT_FOUND


class ValidationRejectedError(DomainError):
    """모델의 제안이 서버 검증을 통과하지 못했다.

    LLM 출력은 실행 제안이며 구조가 맞아도 내용이 사실이라는 뜻은 아니다.
    """

    message_key = "error.command_rejected"
    status_code = status.HTTP_422_UNPROCESSABLE_CONTENT


class UnitConversionError(DomainError):
    """단위 변환 근거가 없다. 숫자를 만들지 않고 확인을 요청한다."""

    message_key = "error.unit_needs_confirm"
    status_code = status.HTTP_422_UNPROCESSABLE_CONTENT


class InsufficientQuantityError(DomainError):
    """사용량이 기록된 잔량보다 많다. 음수 재고를 저장하지 않는다."""

    message_key = "error.quantity_insufficient"
    status_code = status.HTTP_409_CONFLICT


class UpstreamError(DomainError):
    """모델·외부 API 실패. 명령을 완료한 것처럼 알리지 않는다."""

    message_key = "error.upstream_failed"
    status_code = status.HTTP_502_BAD_GATEWAY


def register_exception_handlers(app: FastAPI) -> None:
    """도메인 예외를 사용자 문구가 담긴 JSON 응답으로 바꾼다."""
    from app.core.locale import translate

    @app.exception_handler(DomainError)
    async def _handle_domain_error(request: Request, exc: DomainError) -> JSONResponse:
        logger.warning("Domain error on {} {}: {}", request.method, request.url.path, exc.detail)
        return JSONResponse(
            status_code=exc.status_code,
            content={
                "message": translate(exc.message_key),
                "code": exc.message_key,
            },
        )
