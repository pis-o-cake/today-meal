"""웹 배포용 덱을 server/app/deck 에 만든다.

    python3 build_deck.py

이미지·폰트를 HTML 안에 data URI 로 넣는다. 서버 응답이 요청마다 느릴 때
이미지가 늦게 도착해 빈 화면이 보이는 일을 막는다. 영상만 따로 받는다.
로컬 원본(index.html·presenter.html)은 파일 경로 그대로 둔다.
"""

from __future__ import annotations

import base64
import re
import shutil
from pathlib import Path

SRC = Path(__file__).resolve().parent
OUT = SRC.parents[1] / "server" / "app" / "deck"
MIME = {".png": "image/png", ".woff2": "font/woff2", ".jpg": "image/jpeg", ".svg": "image/svg+xml"}
ASSET = re.compile(r"assets/(?:img|fonts)/[\w.-]+\.(?:png|jpg|svg|woff2)")


def inline(html: str) -> str:
    def data_uri(match: re.Match[str]) -> str:
        path = SRC / match.group(0)
        if not path.is_file():
            raise FileNotFoundError(f"Missing deck asset: {path}")
        encoded = base64.b64encode(path.read_bytes()).decode()
        return f"data:{MIME[path.suffix]};base64,{encoded}"

    return ASSET.sub(data_uri, html)


def main() -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    (OUT / "assets" / "video").mkdir(parents=True)
    for name in ("index.html", "presenter.html"):
        (OUT / name).write_text(inline((SRC / name).read_text()))
    shutil.copy2(SRC / "assets" / "video" / "demo.mp4", OUT / "assets" / "video" / "demo.mp4")
    shutil.copy2(SRC / "og.png", OUT / "og.png")  # 링크 미리보기 이미지(1200×628, 1장 화면)
    for path in sorted(OUT.rglob("*")):
        if path.is_file():
            print(f"{path.stat().st_size:>10,}  {path.relative_to(OUT)}")


if __name__ == "__main__":
    main()
