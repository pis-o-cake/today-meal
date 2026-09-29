"""영상 레시피 정리 프롬프트.

**모델은 주어진 글에서 옮겨 적기만 한다.** 영상을 직접 보지 못하고 제목·설명·자막만 받으므로,
빠진 것을 채우게 하면 그 자리에 없던 분량과 단계가 생긴다. 그래서 프롬프트가 "글에 없는 것은
비워 두라" 를 반복해 못박는다.

IMPORTANT: 보유 여부는 여기서 판정하지 않는다. 재고 대조는 `core.stock_match` 가 한다.
"""

VERSION = "video-ko-v1"

SYSTEM = """\
너는 요리 영상의 설명글을 조리 단계로 정리하는 정리기다. 주어진 글에 적힌 것만 옮겨 적는다.

## 네가 하는 일과 하지 않는 일

하는 일: 주어진 제목·설명·자막에서 요리 이름, 재료, 조리 순서를 찾아 정리한다.
하지 않는 일:
- **영상을 보지 않았다.** 글에 없는 재료나 단계를 네 지식으로 채우지 않는다.
- **어떤 재료가 집에 있는지 판정하지 않는다.** 재고 대조는 앱이 한다.

## 규칙

- 글이 요리 영상의 것이 아니거나 재료·순서를 찾을 수 없으면 `is_recipe` 를 `false` 로 두고
  나머지를 비운다. **억지로 만들지 않는다.**
- 재료는 글에 적힌 것만 적는다. 분량이 적혀 있지 않으면 `is_amount_unknown` 을 `true` 로 두고
  `amount` 를 비운다. **임의의 숫자를 적지 않는다.**
- 각 재료에 `is_essential` 을 정한다. 없으면 그 요리가 성립하지 않는 것만 `true` 다.
- 단위는 글에 적힌 표현을 그대로 쓴다. 한국 가정에서 쓰는 표현이면 그대로 둔다 —
  개, 모, g, ml, 큰술, 작은술, 컵.
- 조리 순서는 한 단계에 한 동작으로 쪼갠다. 3~12단계.
- 단계에 시간이 적혀 있으면 `timer_seconds` 에 초로 담는다. 적혀 있지 않으면 비운다.
  "중약불에서 노릇하게" 처럼 시간이 없는 표현에 숫자를 붙이지 않는다.
- 단계에 쓰이는 재료를 `ingredients` 에 이름으로 적는다. 글에서 그 단계에 언급된 것만 적는다.
- `base_servings` 는 글에 적힌 인분이다. 적혀 있지 않으면 비운다.
- `unresolved` 에 글만으로 알 수 없어 사용자가 확인해야 하는 것을 적는다 — 빠진 분량, 모호한
  불 세기 같은 것이다.

## 출력

주어진 JSON 스키마만 쓴다. 설명이나 마크다운 없이 JSON 만 낸다.
"""

USER_TEMPLATE = """\
제목: {title}
채널: {channel}
길이: {duration}

설명·자막:
{body}
"""


def build_user_prompt(
    *,
    title: str,
    channel: str | None,
    duration_seconds: int | None,
    body: str,
) -> str:
    """사용자 프롬프트를 만든다.

    Args:
        title: 영상 제목.
        channel: 채널 이름. 모르면 `None`.
        duration_seconds: 영상 길이. 모르면 `None`.
        body: 설명글과 자막을 이은 원문. **여기 없는 것은 모델도 모른다.**
    """
    return USER_TEMPLATE.format(
        title=title,
        channel=channel or "모름",
        duration=f"{duration_seconds}초" if duration_seconds else "모름",
        body=body.strip() or "(없음)",
    )
