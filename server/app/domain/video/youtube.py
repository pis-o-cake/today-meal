"""유튜브 링크 해석과 메타데이터 수집.

여기서 하는 일은 셋이다.

1. 링크에서 **영상 ID 를 뽑는다.** 아니면 거절한다 — 아무 URL 을 받아 모델에 넘기면 요리와
   무관한 글로 레시피를 만들어 낸다.
2. 제목·채널·길이·설명을 가져온다.
3. 자막이 공개돼 있으면 함께 가져온다.

IMPORTANT: **글을 만들어 내지 않는다.** 설명도 자막도 없으면 빈 본문을 돌려주고, 판단은
`service` 가 한다. 제목만으로 레시피를 정리하면 그것은 모델의 지식이지 그 영상이 아니다.

CAUTION: 자막 경로(`timedtext`)는 공개 문서가 없는 내부 경로다. 막히면 자막 없이 진행하고
실패로 다루지 않는다.
"""

from __future__ import annotations

import html
import re
from dataclasses import dataclass
from urllib.parse import parse_qs, urlparse

import httpx
from loguru import logger

from app.core.config import Settings
from app.core.exceptions import UpstreamError, ValidationRejectedError

#: 영상 ID 의 모양. 유튜브가 쓰는 11자 키다.
_VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")

#: 영상 ID 가 경로에 오는 형태들.
_PATH_PREFIXES = ("/shorts/", "/embed/", "/live/", "/v/")

#: 유튜브로 인정하는 호스트. 다른 호스트는 거절한다.
_HOSTS = frozenset(
    {
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "music.youtube.com",
        "youtu.be",
        "www.youtu.be",
    }
)

_OEMBED = "https://www.youtube.com/oembed"
_DATA_API = "https://www.googleapis.com/youtube/v3/videos"
_TIMEDTEXT = "https://www.youtube.com/api/timedtext"

#: 제공자에게 물을 때의 한계. 정리 한 번이 여기 매달리면 안 된다.
_TIMEOUT = 8.0

#: 모델에 넘길 본문 길이 상한. 긴 설명글에는 광고와 타임스탬프 목록이 붙어 있다.
_BODY_LIMIT = 6_000

#: ISO-8601 기간(`PT12M40S`).
_DURATION = re.compile(r"^P(?:\d+D)?T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$")


@dataclass(frozen=True, slots=True)
class VideoMeta:
    """영상 하나의 글.

    Attributes:
        video_id: 유튜브 영상 ID. 이 값이 분석 결과의 키다.
        url: 정규화한 시청 주소. 사용자가 넣은 추적 파라미터는 버린다.
        title: 제목.
        channel: 채널 이름. 모르면 `None`.
        duration_seconds: 길이. 모르면 `None`.
        description: 설명글. 없으면 빈 문자열.
        captions: 자막 원문. 없으면 빈 문자열.
    """

    video_id: str
    url: str
    title: str
    channel: str | None = None
    duration_seconds: int | None = None
    description: str = ""
    captions: str = ""

    @property
    def body(self) -> str:
        """모델에 넘길 본문. 설명글과 자막을 잇고 길이를 묶는다."""
        parts = [part for part in (self.description, self.captions) if part.strip()]
        return "\n\n".join(parts)[:_BODY_LIMIT]


def parse_video_id(url: str) -> str:
    """링크에서 영상 ID 를 뽑는다.

    Args:
        url: 사용자가 붙여넣은 주소.

    Returns:
        11자 영상 ID.

    Raises:
        ValidationRejectedError: 유튜브 링크가 아니거나 ID 를 찾을 수 없다.
    """
    candidate = url.strip()
    if not candidate:
        raise ValidationRejectedError(
            "video url is empty", message_key="error.video_bad_link"
        )
    if "//" not in candidate:
        candidate = f"https://{candidate}"

    parsed = urlparse(candidate)
    host = (parsed.hostname or "").lower()
    if host not in _HOSTS:
        raise ValidationRejectedError(
            f"not a youtube host: {host or 'none'}", message_key="error.video_bad_link"
        )

    found = _extract(parsed.path, parsed.query, short=host.endswith("youtu.be"))
    if found is None or not _VIDEO_ID.match(found):
        raise ValidationRejectedError(
            "youtube url has no video id", message_key="error.video_bad_link"
        )
    return found


def watch_url(video_id: str) -> str:
    """정규화한 시청 주소. 추적 파라미터를 버리고 ID 만 남긴다."""
    return f"https://www.youtube.com/watch?v={video_id}"


def _extract(path: str, query: str, *, short: bool) -> str | None:
    if short:
        return path.lstrip("/").split("/")[0] or None
    values = parse_qs(query).get("v")
    if values:
        return values[0]
    for prefix in _PATH_PREFIXES:
        if path.startswith(prefix):
            return path[len(prefix) :].split("/")[0] or None
    return None


async def fetch_meta(video_id: str, settings: Settings) -> VideoMeta:
    """영상의 글을 모아 온다.

    키가 있으면 Data API 로 설명글까지 받는다. 없으면 oEmbed 로 제목만 받는다 — 그때는 본문이
    비어 자막이 없는 한 정리하지 못하며, 그 사실을 `service` 가 사용자에게 알린다.

    Raises:
        UpstreamError: 유튜브에 닿지 못했다.
        NotFoundError: 그런 영상이 없다.
    """
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        meta = (
            await _via_data_api(client, video_id, settings.youtube_api_key)
            if settings.youtube_api_key
            else await _via_oembed(client, video_id)
        )
        captions = await _captions(client, video_id)

    return VideoMeta(
        video_id=meta.video_id,
        url=meta.url,
        title=meta.title,
        channel=meta.channel,
        duration_seconds=meta.duration_seconds,
        description=meta.description,
        captions=captions,
    )


async def _via_data_api(
    client: httpx.AsyncClient, video_id: str, api_key: str
) -> VideoMeta:
    """Data API 로 제목·채널·길이·설명을 받는다."""
    params = {"part": "snippet,contentDetails", "id": video_id, "key": api_key}
    try:
        response = await client.get(_DATA_API, params=params)
    except httpx.HTTPError as error:
        logger.warning("YouTube data api unreachable: {}", error)
        raise UpstreamError(f"youtube unreachable: {error}") from error

    if response.status_code != 200:
        # 키 문제와 영상 문제를 로그에서 가릴 수 있어야 한다.
        logger.warning("YouTube data api returned {}", response.status_code)
        raise UpstreamError(f"youtube returned {response.status_code}")

    items = response.json().get("items") or []
    if not items:
        raise ValidationRejectedError(
            f"youtube has no such video: {video_id}",
            message_key="error.video_not_found",
        )

    snippet = items[0].get("snippet") or {}
    details = items[0].get("contentDetails") or {}
    return VideoMeta(
        video_id=video_id,
        url=watch_url(video_id),
        title=snippet.get("title") or "",
        channel=snippet.get("channelTitle"),
        duration_seconds=_seconds(details.get("duration")),
        description=snippet.get("description") or "",
    )


async def _via_oembed(client: httpx.AsyncClient, video_id: str) -> VideoMeta:
    """키 없이 제목과 채널만 받는다. 설명글은 오지 않는다."""
    params = {"url": watch_url(video_id), "format": "json"}
    try:
        response = await client.get(_OEMBED, params=params)
    except httpx.HTTPError as error:
        logger.warning("YouTube oembed unreachable: {}", error)
        raise UpstreamError(f"youtube unreachable: {error}") from error

    if response.status_code == 404:
        raise ValidationRejectedError(
            f"youtube has no such video: {video_id}",
            message_key="error.video_not_found",
        )
    if response.status_code != 200:
        logger.warning("YouTube oembed returned {}", response.status_code)
        raise UpstreamError(f"youtube returned {response.status_code}")

    body = response.json()
    return VideoMeta(
        video_id=video_id,
        url=watch_url(video_id),
        title=body.get("title") or "",
        channel=body.get("author_name"),
    )


async def _captions(client: httpx.AsyncClient, video_id: str) -> str:
    """공개 자막. 없거나 막히면 빈 문자열이다.

    자막이 있으면 설명글보다 훨씬 좋은 재료다 — 실제로 말한 순서와 시간이 담겨 있다. 다만
    비공개 경로라 실패를 정상으로 다룬다.
    """
    for lang in ("ko", "en"):
        params = {"v": video_id, "lang": lang, "fmt": "json3"}
        try:
            response = await client.get(_TIMEDTEXT, params=params)
        except httpx.HTTPError as error:
            logger.debug("Captions unreachable for {}: {}", video_id, error)
            return ""
        if response.status_code != 200 or not response.content:
            continue
        text = _from_json3(response)
        if text:
            return text
    return ""


def _from_json3(response: httpx.Response) -> str:
    """`json3` 자막의 글자만 이어 붙인다."""
    try:
        events = response.json().get("events") or []
    except ValueError:
        return ""
    lines: list[str] = []
    for event in events:
        segments = event.get("segs") or []
        line = "".join(segment.get("utf8", "") for segment in segments).strip()
        if line:
            lines.append(html.unescape(line))
    return "\n".join(lines)


def _seconds(duration: str | None) -> int | None:
    """ISO-8601 기간을 초로. 읽을 수 없으면 `None` 이며 짐작하지 않는다."""
    if not duration:
        return None
    found = _DURATION.match(duration)
    if found is None:
        return None
    hours, minutes, secs = (int(value or 0) for value in found.groups())
    total = hours * 3600 + minutes * 60 + secs
    return total or None
