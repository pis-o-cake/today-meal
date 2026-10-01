"""발표 덱의 Pretendard 서브셋을 다시 만든다.

    pip install fonttools brotli
    python3 presentation/subset_font.py presentation/slides presentation/slides-v2

덱마다 `index.html` 에 쓰인 글자(스크립트가 띄우는 안내 문구 포함)만 남겨
`assets/fonts/` 아래 덱 글꼴로 쓴다. 페이지가 참조하는 글꼴만 만든다.

- `Pretendard-deck.woff2`: 본문. 굵기 축(wght)은 그대로 둔다.
- `Jua-deck.woff2`: v2 제목용 배민 주아체(OFL 1.1). 원본 라이선스를 덱 폴더에 함께 둔다.

WARNING: 슬라이드 문구를 바꾼 뒤 다시 돌리지 않으면 새 글자만 다른 글꼴로 보인다.
"""

from __future__ import annotations

import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
FONTS = {
    "Pretendard-deck.woff2": ROOT / "app" / "assets" / "fonts" / "PretendardVariable.ttf",
    "Jua-deck.woff2": ROOT / "docs" / "assets" / "fonts" / "Jua-Regular.ttf",
}
# 주소·숫자·기호가 바뀌어도 깨지지 않게 ASCII 는 항상 넣는다.
BASE = "".join(chr(code) for code in range(0x20, 0x7F))


def build(deck: Path) -> None:
    """덱 하나의 서브셋 글꼴을 만든다.

    Args:
        deck: `index.html` 이 있는 덱 폴더.

    Raises:
        FileNotFoundError: 덱 또는 원본 글꼴이 없을 때.
    """
    page = deck / "index.html"
    if not page.is_file():
        raise FileNotFoundError(f"Missing deck page: {page}")
    html = page.read_text(encoding="utf-8")
    text = BASE + html
    for name, source in FONTS.items():
        if f"assets/fonts/{name}" not in html:
            continue
        if not source.is_file():
            raise FileNotFoundError(f"Missing source font: {source}")
        options = subset.Options()
        options.flavor = "woff2"
        options.layout_features = ["*"]
        font = TTFont(source)
        subsetter = subset.Subsetter(options=options)
        subsetter.populate(text=text)
        subsetter.subset(font)
        out = deck / "assets" / "fonts" / name
        out.parent.mkdir(parents=True, exist_ok=True)
        font.flavor = "woff2"
        font.save(out)
        print(f"{out.stat().st_size:>9,}  {out.relative_to(ROOT)}")


def main() -> None:
    decks = [Path(arg).resolve() for arg in sys.argv[1:]]
    if not decks:
        raise SystemExit("usage: subset_font.py <deck-dir> [<deck-dir> ...]")
    for deck in decks:
        build(deck)


if __name__ == "__main__":
    main()
