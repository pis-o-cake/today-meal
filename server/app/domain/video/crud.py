"""영상 분석 결과 조회·저장.

쿼리만 담는다. 링크 해석과 모델 호출은 `service.py` 가 한다.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.enums import VideoInputKind, VideoRecipeStatus
from app.domain.video.models import VideoRecipe


async def find(
    session: AsyncSession, *, video_id: str, prompt_version: str
) -> VideoRecipe | None:
    """이미 정리해 둔 결과.

    같은 영상을 같은 프롬프트로 두 번 분석하지 않는다. 프롬프트가 바뀌면 결과도 달라지므로
    버전까지 키에 넣는다 — 옛 프롬프트의 결과를 새 프롬프트의 것처럼 쓰면 안 된다.
    """
    result = await session.execute(
        select(VideoRecipe).where(
            VideoRecipe.video_id == video_id,
            VideoRecipe.prompt_version == prompt_version,
        )
    )
    return result.scalar_one_or_none()


async def save_analyzed(
    session: AsyncSession,
    *,
    video_id: str,
    url: str,
    title: str | None,
    channel: str | None,
    dish_name: str | None,
    base_servings: int | None,
    ingredients: list[dict[str, Any]],
    steps: list[dict[str, Any]],
    unresolved: list[str],
    model: str,
    prompt_version: str,
) -> VideoRecipe:
    """정리에 성공한 결과를 남긴다."""
    row = VideoRecipe(
        video_id=video_id,
        url=url,
        title=title,
        channel=channel,
        dish_name=dish_name,
        base_servings=base_servings,
        ingredients=ingredients,
        steps=steps,
        unresolved=[{"note": note} for note in unresolved],
        status=VideoRecipeStatus.ANALYZED.value,
        input_kind=VideoInputKind.VIDEO_URL.value,
        model=model,
        prompt_version=prompt_version,
        analyzed_at=datetime.now(UTC),
    )
    session.add(row)
    await session.flush()
    return row


async def forget(session: AsyncSession, row: VideoRecipe) -> None:
    """정리 기록 하나를 지운다.

    다시 시도할 실패를 지워 새 분석이 같은 자리에 들어가게 한다. `(video_id,
    prompt_version)` 이 유일하므로 지우지 않으면 새 행을 넣을 수 없다.
    """
    await session.delete(row)
    await session.flush()


async def save_failed(
    session: AsyncSession,
    *,
    video_id: str,
    url: str,
    title: str | None,
    channel: str | None,
    reason: str,
    model: str,
    prompt_version: str,
) -> VideoRecipe:
    """정리하지 못한 사실을 남긴다.

    실패도 남긴다. 남기지 않으면 같은 영상을 누를 때마다 모델을 다시 부르고, 사용자는 같은
    실패를 같은 시간만큼 기다린다.

    CAUTION: `failure_reason` 은 로그·운영용 영어 문구다. 사용자에게 보이는 문구는 메시지
    팩에서 온다.
    """
    row = VideoRecipe(
        video_id=video_id,
        url=url,
        title=title,
        channel=channel,
        ingredients=[],
        steps=[],
        unresolved=[],
        status=VideoRecipeStatus.FAILED.value,
        input_kind=VideoInputKind.VIDEO_URL.value,
        model=model,
        prompt_version=prompt_version,
        failure_reason=reason,
        analyzed_at=datetime.now(UTC),
    )
    session.add(row)
    await session.flush()
    return row
