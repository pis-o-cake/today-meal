"""영상 레시피 정리.

순서가 이 모듈의 설계다.

<pre>{@code
1 youtube 가 링크에서 영상 ID 를 뽑는다 — 유튜브가 아니면 여기서 끝난다
2 이미 정리한 결과가 있으면 모델을 부르지 않는다
3 youtube 가 제목·설명·자막을 모아 온다
4 영상도 글도 없으면 정리하지 않는다 — 제목만으로는 지어내는 수밖에 없다
5 LlmGateway 가 영상과 글을 단계로 정리한다
6 stock_match 가 재료를 지금 재고와 대조한다
}</pre>

IMPORTANT: 4번을 건너뛰면 모델이 자기 지식으로 레시피를 만든다. 그것은 그 영상의 레시피가
아니며, 사용자는 영상을 봤다고 믿는다.

CAUTION: 영상을 보내면 길이가 곧 비용이다. 1분이 약 3천 토큰이며, 상한
(`settings.video_max_seconds`)을 넘는 영상은 설명글만 보낸다.

CAUTION: 이 경로에는 **재고 변경 권한이 없다.** 분석만으로 재고가 바뀌지 않으며, 차감은
사용자가 조리를 마쳤을 때 `menu.service.mark_cooked` 가 한다.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from datetime import date
from decimal import Decimal
from typing import Any

from loguru import logger
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import stock_match
from app.core.config import Settings
from app.core.enums import VideoRecipeStatus
from app.core.exceptions import ValidationRejectedError
from app.core.llm.gateway import LlmGateway, VideoSource
from app.core.llm.prompts import video_ko
from app.core.llm.schemas import ProposedVideoRecipe
from app.core.stock_match import RequiredIngredient
from app.domain.ingredient import crud as ingredient_crud
from app.domain.inventory import service as inventory_service
from app.domain.menu import crud as menu_crud
from app.domain.video import crud, youtube
from app.domain.video.models import VideoRecipe
from app.domain.video.schemas import (
    VideoIngredientRead,
    VideoRecipeRead,
    VideoStepRead,
)


async def analyze(
    session: AsyncSession,
    *,
    household_id: int,
    url: str,
    gateway: LlmGateway,
    settings: Settings,
    today: date,
) -> VideoRecipeRead:
    """유튜브 링크를 조리 단계로 정리한다.

    Args:
        household_id: 재고를 대조할 가구.
        url: 사용자가 붙여넣은 링크.
        today: 기한 판정 기준일.

    Returns:
        정리 결과와 **조회 시점의** 재고 대조.

    Raises:
        ValidationRejectedError: 유튜브 링크가 아니거나, 읽을 글이 없거나, 요리 순서를
            찾지 못했다. 세 경우의 `message_key` 가 다르다 — 사용자가 할 수 있는 일이 다르다.
        UpstreamError: 유튜브나 모델에 닿지 못했다.
    """
    video_id = youtube.parse_video_id(url)

    stored = await crud.find(
        session, video_id=video_id, prompt_version=video_ko.VERSION
    )
    if stored is not None:
        # IMPORTANT: 글을 못 읽은 것은 그 영상의 성질이 아니라 **그때의 사정**일 수 있다 —
        # API 키가 없었거나 유튜브가 잠깐 막았을 수 있다. 그 실패를 그대로 재사용하면
        # 사정이 풀린 뒤에도 같은 영상이 영원히 실패한다. 다시 모아 본다.
        #
        # 반면 "레시피가 아니다" 는 모델을 다시 불러도 같은 답이므로 그대로 쓴다.
        if _is_retryable(stored):
            logger.info("Retrying video {} after earlier no_script", video_id)
            await crud.forget(session, stored)
        else:
            names = [str(item.get("name", "")) for item in stored.ingredients]
            index, canonical = await _stock(
                session, household_id, today=today, names=names
            )
            return _read(stored, index, canonical)

    meta = await youtube.fetch_meta(video_id, settings)

    # 영상을 함께 보낸다. 한국 요리 채널의 설명글은 재료만 적고 순서는 영상 안에만 두는
    # 경우가 많아, 글만으로는 대부분의 영상을 정리하지 못한다.
    #
    # CAUTION: 길이가 비용이다. 1분이 약 3천 토큰이므로 상한을 넘는 영상은 글만 쓴다.
    too_long = (
        meta.duration_seconds is not None
        and meta.duration_seconds > settings.video_max_seconds
    )
    if too_long:
        logger.info(
            "Video {} is {}s; sending description only",
            video_id,
            meta.duration_seconds,
        )
    source = VideoSource(
        meta.title,
        meta.body,
        channel=meta.channel,
        duration_seconds=meta.duration_seconds,
        video_url=None if too_long else youtube.watch_url(video_id),
    )

    if not source.can_analyze:
        await crud.save_failed(
            session,
            video_id=video_id,
            url=meta.url,
            title=meta.title or None,
            channel=meta.channel,
            reason="no_script",
            model=settings.gemini_model,
            prompt_version=video_ko.VERSION,
        )
        await session.commit()
        logger.info("Video {} has neither video nor usable script", video_id)
        raise ValidationRejectedError(
            f"video has no usable script: {video_id}",
            message_key="error.video_no_script",
        )

    result = await gateway.analyze_video(source)
    proposal = result.proposal

    if not proposal.is_recipe or not proposal.steps:
        await crud.save_failed(
            session,
            video_id=video_id,
            url=meta.url,
            title=meta.title or None,
            channel=meta.channel,
            reason="not_recipe",
            model=result.usage.model,
            prompt_version=video_ko.VERSION,
        )
        await session.commit()
        logger.info("Video {} is not a recipe", video_id)
        raise ValidationRejectedError(
            f"video is not a recipe: {video_id}",
            message_key="error.video_not_recipe",
        )

    row = await crud.save_analyzed(
        session,
        video_id=video_id,
        url=meta.url,
        title=meta.title or None,
        channel=meta.channel,
        dish_name=proposal.dish_name,
        base_servings=proposal.base_servings,
        ingredients=_ingredient_rows(proposal),
        steps=_step_rows(proposal),
        unresolved=proposal.unresolved,
        model=result.usage.model,
        prompt_version=video_ko.VERSION,
    )
    await session.commit()
    logger.info(
        "Analyzed video {} into {} steps", video_id, len(proposal.steps)
    )
    index, canonical = await _stock(
        session,
        household_id,
        today=today,
        names=[item.raw_name for item in proposal.ingredients],
    )
    return _read(row, index, canonical)


def _ingredient_rows(proposal: ProposedVideoRecipe) -> list[dict[str, Any]]:
    """재료를 JSONB 에 담을 형태로. **분량을 모르면 비운 채로 남긴다.**"""
    return [
        {
            "name": item.raw_name.strip(),
            "amount": None if item.is_amount_unknown else item.amount,
            "unit": item.unit_text,
            "is_essential": item.is_essential,
        }
        for item in proposal.ingredients
    ]


def _step_rows(proposal: ProposedVideoRecipe) -> list[dict[str, Any]]:
    return [
        {
            "order": index,
            "text": step.text,
            "timer_seconds": step.timer_seconds,
            "timer_label": step.timer_label,
            "ingredients": step.ingredients,
        }
        for index, step in enumerate(proposal.steps, start=1)
    ]


async def _stock(
    session: AsyncSession, household_id: int, *, today: date, names: Sequence[str] = ()
) -> tuple[stock_match.StockIndex, dict[str, str]]:
    """지금 재고의 이름 색인과 표준명 맵.

    기한이 지난 것은 쓸 수 있는 재료로 보지 않는다.

    IMPORTANT: 재고와 [names](영상이 요구하는 재료)를 **같은 표준명으로** 모은다.
    사용자는 "삼겹살" 로 넣고 영상은 "돼지고기" 를 적으므로, 말한 이름만 보면 가진 재료를
    없다고 판정한다.
    """
    usable = await inventory_service.cookable_batches(
        session, household_id, today=today
    )
    staples, _ = await menu_crud.preferences(session, household_id)
    canonical = await ingredient_crud.canonical_names(
        session, [batch.raw_name for batch in usable] + list(names)
    )
    index = stock_match.index_stock(
        ((batch.raw_name, batch.quantity, batch.unit) for batch in usable),
        staples,
        canonical,
    )
    return index, canonical


def _is_retryable(row: VideoRecipe) -> bool:
    """다시 시도해 볼 실패인지.

    글을 모으지 못한 실패(`no_script`)만 해당한다. 유튜브 설명을 읽으려면 Data API 키가
    있어야 하고, 키가 없거나 유튜브가 일시적으로 막으면 같은 실패가 남는다. 그것을 영구
    판정으로 굳히면 키를 넣은 뒤에도 그 영상은 열리지 않는다.
    """
    return (
        row.status == VideoRecipeStatus.FAILED.value
        and row.failure_reason == "no_script"
    )


def _read(
    row: VideoRecipe,
    stock: stock_match.StockIndex,
    canonical: Mapping[str, str] | None = None,
) -> VideoRecipeRead:
    """저장된 결과에 **지금** 재고 판정을 붙인다.

    Raises:
        ValidationRejectedError: 저장된 것이 실패 기록이다. 같은 이유를 다시 돌려준다 —
            모델을 다시 불러도 결과가 같다. 다시 시도할 만한 실패는 [_is_retryable] 이
            먼저 걸러 여기까지 오지 않는다.
    """
    if row.status == VideoRecipeStatus.FAILED.value:
        reason = row.failure_reason or "not_recipe"
        key = (
            "error.video_no_script"
            if reason == "no_script"
            else "error.video_not_recipe"
        )
        raise ValidationRejectedError(
            f"video analysis failed earlier: {row.video_id} ({reason})",
            message_key=key,
        )

    required = [
        RequiredIngredient(
            raw_name=str(item.get("name", "")),
            amount=item.get("amount"),
            unit_text=item.get("unit"),
            is_essential=bool(item.get("is_essential", True)),
            is_amount_unknown=item.get("amount") is None,
        )
        for item in row.ingredients
        if item.get("name")
    ]
    checks, _ = stock_match.check_ingredients(required, stock, None, canonical)

    steps = [
        VideoStepRead(
            order=int(step.get("order", index)),
            text=str(step.get("text", "")),
            timer_seconds=step.get("timer_seconds"),
            timer_label=step.get("timer_label"),
            ingredients=[str(name) for name in step.get("ingredients") or []],
        )
        for index, step in enumerate(row.steps, start=1)
    ]

    return VideoRecipeRead(
        video_id=row.video_id,
        url=row.url,
        title=row.title,
        channel=row.channel,
        dish_name=row.dish_name,
        base_servings=row.base_servings,
        estimated_minutes=_minutes(steps),
        availability=stock_match.availability(checks).value,
        ingredients=[
            VideoIngredientRead(
                name=check.raw_name,
                required_amount=_fmt(check.required_amount),
                unit=check.unit,
                is_essential=check.is_essential,
                status=check.status,
            )
            for check in checks
        ],
        steps=steps,
        missing_ingredients=[c.raw_name for c in checks if c.status == "missing"],
        uncertain_ingredients=[
            c.raw_name for c in checks if c.status == "needs_check"
        ],
        unresolved=[
            str(note.get("note", "")) for note in row.unresolved if note.get("note")
        ],
    )


def _minutes(steps: list[VideoStepRead]) -> int | None:
    """단계에 적힌 시간의 합.

    **적힌 시간만 더한다.** 시간이 없는 단계에 평균값을 얹으면 그 수가 영상에서 온 것처럼
    보인다. 시간이 적힌 단계가 하나도 없으면 `None` 이다.
    """
    seconds = sum(step.timer_seconds or 0 for step in steps)
    if seconds == 0:
        return None
    return max(1, round(seconds / 60))


def _fmt(value: Decimal | None) -> str | None:
    if value is None:
        return None
    normalized = value.normalize()
    if normalized == normalized.to_integral_value():
        return str(int(normalized))
    return str(normalized)
