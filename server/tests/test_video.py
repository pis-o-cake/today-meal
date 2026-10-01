"""영상 레시피: 링크 해석과 "지어내지 않는다" 규칙.

DB 없이 도는 것만 둔다 — 링크 파싱, 본문 길이 문턱, 가짜 게이트웨이의 정리 결과다.
"""

import pytest

from app.core.exceptions import ValidationRejectedError
from app.core.llm.fake import FakeLlmGateway
from app.core.llm.gateway import VideoSource
from app.domain.video import youtube


class TestParseVideoId:
    @pytest.mark.parametrize(
        "url",
        [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtu.be/dQw4w9WgXcQ",
            "https://www.youtube.com/shorts/dQw4w9WgXcQ",
            "https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=30s",
            "youtube.com/watch?v=dQw4w9WgXcQ",
        ],
    )
    def test_accepts_youtube_forms(self, url):
        assert youtube.parse_video_id(url) == "dQw4w9WgXcQ"

    @pytest.mark.parametrize(
        "url",
        [
            "",
            "https://vimeo.com/123456",
            "https://www.youtube.com/",
            "https://www.youtube.com/watch?v=short",
            "https://evil.example.com/watch?v=dQw4w9WgXcQ",
        ],
    )
    def test_rejects_everything_else(self, url):
        """유튜브가 아닌 링크를 모델에 넘기지 않는다."""
        with pytest.raises(ValidationRejectedError):
            youtube.parse_video_id(url)

    def test_normalized_url_drops_tracking(self):
        assert youtube.watch_url("dQw4w9WgXcQ") == (
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        )


class TestBodyThreshold:
    def test_title_only_is_not_enough(self):
        """제목만으로는 정리하지 않는다 — 모델이 지어내는 수밖에 없다."""
        assert not VideoSource("초간단 두부조림", "").has_body

    def test_long_enough_body_passes(self):
        body = "재료: 두부 1모, 간장 2큰술\n1. 두부를 썬다\n2. 3분간 조린다\n" * 2
        assert VideoSource("두부조림", body).has_body


class TestFakeGateway:
    @pytest.mark.asyncio
    async def test_no_numbered_lines_is_not_a_recipe(self):
        """순서를 못 찾으면 비운 결과다. 가짜라고 늘 성공하지 않는다."""
        gateway = FakeLlmGateway()
        result = await gateway.analyze_video(
            VideoSource("여행 브이로그", "오늘은 부산에 갔어요. " * 10)
        )
        assert result.proposal.is_recipe is False
        assert result.proposal.steps == []

    @pytest.mark.asyncio
    async def test_reads_steps_and_written_timers(self):
        gateway = FakeLlmGateway()
        body = (
            "재료: 두부, 계란, 소금\n"
            "1. 두부를 1cm 두께로 썬다\n"
            "2. 키친타월에 올려 3분간 물기를 뺀다\n"
            "3. 중약불에서 노릇하게 부친다\n"
        )
        result = await gateway.analyze_video(VideoSource("두부계란전", body))
        proposal = result.proposal

        assert proposal.is_recipe is True
        assert [step.text for step in proposal.steps] == [
            "두부를 1cm 두께로 썬다",
            "키친타월에 올려 3분간 물기를 뺀다",
            "중약불에서 노릇하게 부친다",
        ]
        # 적힌 시간만 담는다. 3번 단계에는 시간이 없으므로 비어 있어야 한다.
        assert [step.timer_seconds for step in proposal.steps] == [None, 180, None]

    @pytest.mark.asyncio
    async def test_amounts_stay_unknown_when_not_written(self):
        """분량이 적혀 있지 않으면 숫자를 만들지 않는다."""
        gateway = FakeLlmGateway()
        body = "재료: 두부, 계란\n1. 두부를 썬다\n2. 계란을 푼다\n"
        result = await gateway.analyze_video(VideoSource("두부계란전", body))

        assert [item.raw_name for item in result.proposal.ingredients] == ["두부", "계란"]
        assert all(item.amount is None for item in result.proposal.ingredients)
        assert all(item.is_amount_unknown for item in result.proposal.ingredients)


class TestRetryAfterNoScript:
    """글을 못 읽은 실패는 다시 시도한다.

    키가 없거나 유튜브가 잠깐 막혀 생긴 실패를 영구 판정으로 굳히면, 사정이 풀린 뒤에도
    그 영상은 영원히 열리지 않는다.
    """

    def _row(self, status: str, reason: str | None):
        from app.domain.video.models import VideoRecipe

        return VideoRecipe(
            video_id="abc",
            url="https://youtu.be/abc",
            ingredients=[],
            steps=[],
            unresolved=[],
            status=status,
            failure_reason=reason,
            model="m",
            prompt_version="v",
        )

    def test_no_script_is_retried(self):
        from app.core.enums import VideoRecipeStatus
        from app.domain.video.service import _is_retryable

        assert _is_retryable(self._row(VideoRecipeStatus.FAILED.value, "no_script"))

    def test_not_recipe_is_not_retried(self):
        """모델을 다시 불러도 같은 답이다. 비용만 든다."""
        from app.core.enums import VideoRecipeStatus
        from app.domain.video.service import _is_retryable

        assert not _is_retryable(
            self._row(VideoRecipeStatus.FAILED.value, "not_recipe")
        )

    def test_analyzed_is_not_retried(self):
        from app.core.enums import VideoRecipeStatus
        from app.domain.video.service import _is_retryable

        assert not _is_retryable(self._row(VideoRecipeStatus.ANALYZED.value, None))
