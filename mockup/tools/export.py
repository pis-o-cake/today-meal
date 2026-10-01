#!/usr/bin/env python3
"""mockup/canvas(편집기 원본) → mockup/export(편집기 없이 열리는 렌더링본).

하는 일
  1. canvas/*.dc.html 의 편집기 자원 주소(/_blob/<id>)를 export/assets 상대 경로로 바꿔 screens/ 에 쓴다.
  2. canvas.json 의 보드 배치·제목으로 manifest.json 과 갤러리 index.html 을 만든다.
  3. 동봉 자원(support.js, 글꼴, 로고)이 있는지 확인한다. 이 파일들은 export 안에 그대로 둔다.

사용
  python3 mockup/tools/export.py            # 기본: mockup/canvas → mockup/export
  python3 mockup/tools/export.py --check    # 쓰지 않고 export 가 canvas 와 일치하는지만 확인
PNG 는 node mockup/tools/render_png.mjs 로 따로 만든다.
"""
from __future__ import annotations

import hashlib
import html
import json
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MOCKUP = HERE.parent
CANVAS = MOCKUP / "canvas"
EXPORT = MOCKUP / "export"

# 편집기 자산 id → export 안의 파일. 새 자산을 편집기에 올리면 여기에 추가한다.
BLOBS = {
    "1b43482c59fb171bdbae3b012829170f": "assets/fonts/PretendardVariable.woff2",
    "b80c3f239a19ae2ac0629973c9271ec7": "assets/fonts/Jua-Regular.woff2",
    "69ecee9619b1c88dd107131b69a677bc": "assets/img/kakao_login_kr_large.svg",
    "4067c758bf8f92094da22e1402c20ef2": "assets/img/google_g.svg",
}
VENDOR = [
    "screens/support.js",
    "assets/fonts/PretendardVariable.woff2",
    "assets/fonts/Pretendard-OFL.txt",
    "assets/fonts/Jua-Regular.woff2",
    "assets/fonts/Jua-OFL.txt",
    "assets/img/kakao_login_kr_large.svg",
    "assets/img/google_g.svg",
]
BLOB_RE = re.compile(r"/_blob/([0-9a-f]{32})")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def rewrite(text: str, name: str) -> str:
    def one(m: re.Match) -> str:
        blob = m.group(1)
        if blob not in BLOBS:
            raise SystemExit(f"{name}: 알 수 없는 편집기 자산 /_blob/{blob} — tools/export.py 의 BLOBS 에 추가하세요")
        return "../" + BLOBS[blob]
    out = BLOB_RE.sub(one, text)
    if "/_blob/" in out:
        raise SystemExit(f"{name}: /_blob/ 주소가 남아 있습니다")
    return out


def groups(canvas: dict) -> list[dict]:
    """캔버스 제목 메모(title1)를 기준으로 보드를 행 묶음으로 나눈다."""
    titles = [n for k, n in canvas["notes"].items() if n.get("kind") == "title1"]
    order = {name: i for i, name in enumerate(canvas.get("order", []))}
    out: dict[str, dict] = {}
    for name, b in canvas["boards"].items():
        best = None
        for t in titles:
            x0, x1 = t["x"], t["x"] + t.get("maxW", 0)
            if t["y"] <= b["y"] and x0 <= b["x"] <= x1 and (best is None or t["y"] > best["y"]):
                best = t
        label = best["text"] if best else b.get("title", name)
        key = (best["y"], best["x"]) if best else (b["y"], b["x"])
        g = out.setdefault(label, {"title": label, "key": key, "boards": []})
        g["boards"].append(name)
    result = sorted(out.values(), key=lambda g: g["key"])
    for g in result:
        g["boards"].sort(key=lambda n: (canvas["boards"][n]["y"], canvas["boards"][n]["x"], order.get(n, 0)))
        del g["key"]
    return result


def build(check: bool = False) -> int:
    missing = [p for p in VENDOR if not (EXPORT / p).is_file()]
    if missing:
        raise SystemExit("동봉 자원이 없습니다: " + ", ".join(missing))

    canvas = json.loads((CANVAS / "canvas.json").read_text(encoding="utf-8"))
    sources = sorted(p for p in CANVAS.glob("*.dc.html"))
    screens = EXPORT / "screens"
    screens.mkdir(parents=True, exist_ok=True)

    files = {}
    problems = []
    for src in sources:
        raw = src.read_bytes()
        text = rewrite(raw.decode("utf-8"), src.name)
        data = text.encode("utf-8")
        dst = screens / src.name
        if check:
            if not dst.is_file() or dst.read_bytes() != data:
                problems.append(f"다름: screens/{src.name}")
        elif not dst.is_file() or dst.read_bytes() != data:
            dst.write_bytes(data)
        files[src.name] = {"source_sha256": sha(raw), "export_sha256": sha(data)}

    stale = sorted(p.name for p in screens.glob("*.dc.html") if p.name not in files)
    for name in stale:
        problems.append(f"canvas 에 없는 화면: screens/{name}")

    boards = []
    for g in groups(canvas):
        for name in g["boards"]:
            if name not in files:
                problems.append(f"canvas.json 에만 있는 보드: {name}")
                continue
            b = canvas["boards"][name]
            stem = name[: -len(".dc.html")]
            boards.append({
                "file": "screens/" + name, "png": f"png/{stem}.png", "title": b.get("title", stem),
                "group": g["title"], "width": b["w"], "height": b["h"], **files[name],
            })
    placed = {b["file"][len("screens/"):] for b in boards}
    extra = [{"file": "screens/" + n, "png": None, "title": n[: -len(".dc.html")], "group": "캔버스에 배치되지 않은 파일",
              "width": None, "height": None, **files[n]} for n in sorted(files) if n not in placed]

    # 캔버스 메모는 한 장에 5000자까지라 둘로 나뉘어 있다.
    memo = "\n\n".join(canvas["notes"].get(k, {}).get("text", "") for k in ("flutter-memo", "flutter-memo-app")).strip()
    manifest = {
        "title": canvas.get("title", ""),
        "source": "mockup/canvas",
        "canvas_json_sha256": sha((CANVAS / "canvas.json").read_bytes()),
        "runtime_sha256": sha((EXPORT / "screens/support.js").read_bytes()),
        "boards": boards + extra,
    }
    manifest_text = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    index_text = render_index(manifest, memo)

    for rel, text in (("manifest.json", manifest_text), ("index.html", index_text)):
        path = EXPORT / rel
        if check:
            if not path.is_file() or path.read_text(encoding="utf-8") != text:
                problems.append(f"다름: {rel}")
        elif not path.is_file() or path.read_text(encoding="utf-8") != text:
            path.write_text(text, encoding="utf-8")

    if check:
        for b in boards:
            if not (EXPORT / b["png"]).is_file():
                problems.append(f"PNG 없음: {b['png']}")

    for p in problems:
        print("  -", p)
    verb = "확인" if check else "내보냄"
    print(f"{verb}: 화면 {len(files)}개 (보드 {len(boards)}, 미배치 {len(extra)}) → {EXPORT.relative_to(MOCKUP.parent)}")
    return 1 if (check and problems) else 0


def render_index(manifest: dict, memo: str) -> str:
    groups_html = []
    current = None
    cards: list[str] = []

    def flush():
        if current is not None:
            groups_html.append(
                f'<section><h2>{html.escape(current)}</h2><div class="grid">{"".join(cards)}</div></section>')

    for b in manifest["boards"]:
        if b["group"] != current:
            flush()
            current, cards = b["group"], []
        w, h = b["width"] or 390, b["height"] or 844
        wide = w > 600
        thumb = (f'<img loading="lazy" src="{b["png"]}" alt="" width="{w}" height="{h}">' if b["png"]
                 else '<span class="nopng">PNG 없음</span>')
        png_link = f' · <a href="{b["png"]}">PNG</a>' if b["png"] else ""
        cards.append(
            f'<figure class="{"wide" if wide else ""}"><a class="shot" href="{b["file"]}" target="_blank" rel="noopener">{thumb}</a>'
            f'<figcaption><b>{html.escape(b["title"])}</b><span><a href="{b["file"]}" target="_blank" rel="noopener">화면</a>{png_link}</span></figcaption></figure>')
    flush()

    memo_html = html.escape(memo)
    return INDEX_TEMPLATE.replace("@TITLE@", html.escape(manifest["title"])).replace(
        "@GROUPS@", "\n".join(groups_html)).replace("@MEMO@", memo_html).replace(
        "@COUNT@", str(len(manifest["boards"])))


INDEX_TEMPLATE = """<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>@TITLE@ · 내보내기</title>
<style>
@font-face{font-family:'Pretendard';src:url(assets/fonts/PretendardVariable.woff2) format('woff2');font-weight:45 920;font-display:swap}
@font-face{font-family:'Jua';src:url(assets/fonts/Jua-Regular.woff2) format('woff2');font-weight:400;font-display:swap}
:root{--bg:#F4F5F8;--card:#FFFFFF;--ink:#15181D;--ink2:#5F6670;--line:rgba(21,24,29,.08);--acc:#3F4FD1;--warn:#FFF4D6;--warnInk:#7A5200}
@media (prefers-color-scheme: dark){:root{--bg:#1B1C1F;--card:#26272B;--ink:#E8EAED;--ink2:#9AA0A6;--line:rgba(255,255,255,.08);--acc:#8AB4F8;--warn:#3A3321;--warnInk:#FDD663}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font-family:'Pretendard','Apple SD Gothic Neo',sans-serif;letter-spacing:-.01em}
header{padding:28px 24px 8px;max-width:1400px;margin:0 auto}
h1{font-family:'Jua','Pretendard',sans-serif;font-weight:400;font-size:32px;margin:0 0 6px}
header p{margin:0;color:var(--ink2);font-size:14px;line-height:1.6}
code{font-size:13px;background:var(--card);border:1px solid var(--line);border-radius:6px;padding:1px 6px}
.warn{display:none;margin:14px 0 0;padding:12px 14px;border-radius:12px;background:var(--warn);color:var(--warnInk);font-size:14px;line-height:1.6}
body.file .warn{display:block}
main{max-width:1400px;margin:0 auto;padding:0 24px 40px}
section{margin-top:28px}
h2{font-size:17px;margin:0 0 12px;font-weight:800}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:16px}
figure{margin:0;display:flex;flex-direction:column;gap:8px}
figure.wide{grid-column:1/-1}
.shot{display:block;border-radius:14px;overflow:hidden;background:var(--card);border:1px solid var(--line)}
.shot img{display:block;width:100%;height:auto}
figure.wide .shot{max-width:900px}
.nopng{display:flex;align-items:center;justify-content:center;aspect-ratio:390/844;color:var(--ink2);font-size:13px}
figcaption{display:flex;flex-direction:column;gap:2px;font-size:13px}
figcaption b{font-weight:700}
figcaption span{color:var(--ink2)}
a{color:var(--acc);text-decoration:none}
details{margin-top:32px;background:var(--card);border:1px solid var(--line);border-radius:14px;padding:14px 18px}
summary{cursor:pointer;font-weight:800}
pre{white-space:pre-wrap;font-family:inherit;font-size:14px;line-height:1.7;margin:12px 0 0}
</style>
</head>
<body>
<header>
  <h1>@TITLE@</h1>
  <p>편집기 없이 보는 목업 @COUNT@개. 썸네일은 PNG, ‘화면’은 실제로 움직이는 HTML입니다.
  HTML 화면은 이 폴더를 로컬 서버로 열어야 동작합니다: <code>python3 -m http.server 8080 -d mockup/export</code> → <code>http://localhost:8080</code></p>
  <p><b><a href="today-meal-mockup.html">today-meal-mockup.html</a></b> — Figma 처럼 보는 파일 하나. 캔버스 이동·확대, 레이어·속성 패널, 프레젠테이션(버튼을 눌러 화면 이동), 애니메이션까지 들어 있고 글꼴을 품고 있어 이 파일만 보내도 열립니다.</p>
  <p>서버 없이 움직임까지 보려면 <a href="animated/01-ios.html">animated/</a> 의 보드를 더블클릭해 여세요(버튼·화면 이동은 없음).</p>
  <p class="warn">지금 파일로 직접 열었습니다(file://). PNG 는 그대로 보이지만, ‘화면’을 file:// 로 열면 브라우저 보안 때문에 캐릭터 같은 불러오는 부품과 테마·Android 화면이 빠집니다. 위 명령으로 서버를 띄워 여세요.</p>
</header>
<main>
@GROUPS@
<details><summary>Flutter 구현 메모 (캔버스 메모 원문)</summary><pre>@MEMO@</pre></details>
<details><summary>이 폴더의 구성과 다시 만들기</summary><pre>screens/     화면 HTML(*.dc.html)과 런타임 support.js(React 포함, 외부 CDN 없이 동작)
assets/      글꼴(Pretendard·배민 주아체, OFL 라이선스 동봉)과 간편 로그인 로고
png/         화면별 2배율 PNG
today-meal-mockup.html  Figma 같은 단일 뷰어(확정안 83화면, 글꼴 포함, 이 파일만 보내도 열림)
figma/       Figma 가져오기용 정적 보드 6장(스크립트·애니메이션 없음, 행마다 한 장)
animated/    움직이는 보드 6장(애니메이션 그대로, 서버 없이 더블클릭으로 열림)
manifest.json  보드 제목·묶음·크기·원본/내보낸 파일 sha256

원본은 mockup/canvas(Design 편집기용)입니다. 캔버스를 고친 뒤 저장소 루트에서:
  python3 mockup/tools/export.py            화면·manifest·이 페이지 다시 쓰기
  python3 mockup/tools/export.py --check    export 가 canvas 와 같은지 확인
  node mockup/tools/render_png.js           PNG 다시 찍기 (Playwright 필요)
  node mockup/tools/figma_pack.js           figma/ 보드 다시 만들기 (Playwright 필요)
  node mockup/tools/figma_pack.js --animated   animated/ 보드 다시 만들기
  node mockup/tools/viewer.js               today-meal-mockup.html 다시 만들기</pre></details>
<details><summary>Figma 로 옮기기</summary><pre>편집 가능한 레이어로: Figma 에서 html.to.design 플러그인을 열고 figma/ 의 HTML 파일을 끌어 넣습니다.
  01-ios · 02-android · 03-white · 04-glass · 05-dark · 06-assets · 07-added 일곱 장이라 무료 한도(30일 10회) 안에 들어갑니다.
  글꼴: Pretendard 는 Figma 를 쓰는 컴퓨터에 설치, Jua 는 Figma 기본 Google Fonts 에 있습니다.
  유리 효과(backdrop blur)·움직임은 그대로 옮겨지지 않을 수 있습니다.
그림으로만: png/ 의 PNG 를 Figma 캔버스에 끌어 놓습니다.</pre></details>
</main>
<script>if (location.protocol === 'file:') document.body.classList.add('file');</script>
</body>
</html>
"""


if __name__ == "__main__":
    sys.exit(build(check="--check" in sys.argv))
