"""챕터 편집본(edit/)으로 전체 시연본과 발표용 90초 영상을 만든다.

edit/ 와 long/ 은 읽기만 한다. 결과는 final/ 에 쓴다.

    .venv/bin/python render.py full    # final/today-meal-full.mp4
    .venv/bin/python render.py short   # final/today-meal-90s.mp4

화면 구성: 1920x1080 가로. 왼쪽에 폰 화면, 오른쪽에 챕터 제목과 기능 자막.
자막은 **촬영에서 실제로 성공한 동작만** 적는다(편집 근거는 final/EDIT-NOTES.md).
"""

from __future__ import annotations

import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent
EDIT = ROOT / "edit"
OUT = ROOT / "final"
WORK = ROOT / "work" / "render"
FONT_DIR = ROOT.parent / "app" / "assets" / "fonts"
PRETENDARD = FONT_DIR / "PretendardVariable.ttf"
JUA = FONT_DIR / "Jua-Regular.ttf"

W, H = 1920, 1080
FPS = 30
PHONE_H = 1000
PHONE_W = round(1080 * PHONE_H / 2408 / 2) * 2  # 448
PHONE_X, PHONE_Y = 260, (H - PHONE_H) // 2
RADIUS = 44
TEXT_X = 880
TEXT_W = 900
BLOCK_CENTER_Y = 530  # 오른쪽 설명 묶음의 세로 중심(1080 화면)

BG_TOP = (246, 247, 255)
BG_BOTTOM = (232, 234, 252)
INK = (31, 35, 64)
INK_SOFT = (74, 79, 110)
ACCENT = (83, 92, 230)
NOTE = (128, 132, 160)
NOTE_BG = (220, 224, 252)
NOTE_INK = (52, 58, 150)
CREDIT = (200, 203, 228)

SRC = {
    "01": EDIT / "01-시작-take01-cut.mp4",
    "02": EDIT / "02-등록-take02-cut.mp4",
    "03": EDIT / "03-냉장고-take01-cut.mp4",
    "04": EDIT / "04-사용정정-take01-cut.mp4",
    "05": EDIT / "05-추천조리-take02-cut.mp4",
    "06": EDIT / "06-영상레시피-take01-cut.mp4",
    "07": EDIT / "07-설정-take01-cut.mp4",
    "08": EDIT / "08-마무리-take01-cut.mp4",
}

# 회원가입 화면의 이메일·비밀번호 칸(원본 1080x2408 좌표). 계정 정보를 가린다.
ACCOUNT_FIELDS = (0, 560, 1080, 780)


@dataclass
class Seg:
    src: str | None  # None 이면 카드(폰 화면 없음)
    start: float
    end: float
    kicker: str = ""
    title: str = ""
    lines: list[str] = field(default_factory=list)
    note: str = ""
    mute: bool = False
    blur: tuple[int, int, int, int] | None = None
    hold: float = 0.0  # 마지막 화면을 이만큼 멈춰 보여준다(읽을 시간)
    credit: list[str] = field(default_factory=list)  # 배경음악 출처 표기(CC BY)


def font(size: int, weight: int = 500, jua: bool = False) -> ImageFont.FreeTypeFont:
    if jua:
        return ImageFont.truetype(str(JUA), size)
    f = ImageFont.truetype(str(PRETENDARD), size)
    f.set_variation_by_axes([weight])
    return f


def background() -> Image.Image:
    img = Image.new("RGB", (W, H))
    px = img.load()
    for y in range(H):
        t = y / (H - 1)
        c = tuple(round(BG_TOP[i] * (1 - t) + BG_BOTTOM[i] * t) for i in range(3))
        for x in range(W):
            px[x, y] = c
    return img


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=255)
    return mask


def wrap(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.FreeTypeFont, width: int) -> list[str]:
    out, line = [], ""
    for word in text.split(" "):
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=f) <= width or not line:
            line = trial
        else:
            out.append(line)
            line = word
    if line:
        out.append(line)
    return out


def panel(seg: Seg, base: Image.Image, phone: bool) -> Image.Image:
    img = base.copy()
    d = ImageDraw.Draw(img)
    if phone:
        # 폰 그림자
        shadow = Image.new("L", (W, H), 0)
        ImageDraw.Draw(shadow).rounded_rectangle(
            (PHONE_X + 6, PHONE_Y + 14, PHONE_X + PHONE_W + 6, PHONE_Y + PHONE_H + 14), RADIUS, fill=90
        )
        shadow = shadow.filter(ImageFilter.GaussianBlur(22))
        dark = Image.new("RGB", (W, H), (60, 64, 120))
        img = Image.composite(dark, img, shadow)
        d = ImageDraw.Draw(img)

    if seg.src is None:
        # 카드: 가운데 정렬
        y = 360
        brand = font(110, jua=True)
        tw = d.textlength(seg.title, font=brand)
        d.text(((W - tw) / 2, y), seg.title, font=brand, fill=INK)
        y += 160
        for line in seg.lines:
            f = font(44, 500)
            tw = d.textlength(line, font=f)
            d.text(((W - tw) / 2, y), line, font=f, fill=INK_SOFT)
            y += 66
        if seg.kicker:
            f = font(30, 600)
            tw = d.textlength(seg.kicker, font=f)
            d.text(((W - tw) / 2, 250), seg.kicker, font=f, fill=ACCENT)
        return img

    # 분류명·제목·본문을 한 묶음으로 보고, 실제 글자 범위의 가운데를 BLOCK_CENTER_Y 에 맞춘다.
    # 본문 줄 수에 따라 묶음 높이가 달라지므로 먼저 배치만 계산한 뒤 시작 위치를 정한다.
    ops: list[tuple[str, int, int, str, object, tuple]] = []  # (종류, x, y, 글자, 글꼴, 색)
    y = 0
    if seg.kicker:
        ops.append(("text", TEXT_X, y, seg.kicker, font(30, 700), ACCENT))
        y += 58
    title_f = font(66, 800)
    for line in wrap(d, seg.title, title_f, TEXT_W):
        ops.append(("text", TEXT_X, y, line, title_f, INK))
        y += 86
    y += 30
    body_f = font(40, 500)
    for text in seg.lines:
        for i, line in enumerate(wrap(d, text, body_f, TEXT_W - 40)):
            if i == 0:
                ops.append(("bullet", TEXT_X, y, "", None, ACCENT))
            ops.append(("text", TEXT_X + 30, y, line, body_f, INK_SOFT))
            y += 58
        y += 14
    boxes = [d.textbbox((x, oy), txt, font=f) for kind, x, oy, txt, f, _ in ops if kind == "text"]
    shift = 0
    if boxes:
        top, bottom = min(b[1] for b in boxes), max(b[3] for b in boxes)
        shift = round(BLOCK_CENTER_Y - (top + bottom) / 2)
    for kind, x, oy, txt, f, color in ops:
        if kind == "bullet":
            d.rounded_rectangle((x, oy + shift + 14, x + 10, oy + shift + 34), 5, fill=color)
        else:
            d.text((x, oy + shift), txt, font=f, fill=color)
    if seg.note:
        # 발표장 화면에서도 읽히게 연한 글씨 대신 진한 글씨를 색 띠 위에 얹는다.
        nf = font(32, 700)
        tw = d.textlength(seg.note, font=nf)
        d.rounded_rectangle((TEXT_X, 888, TEXT_X + tw + 44, 944), 28, fill=NOTE_BG)
        d.text((TEXT_X + 22, 896), seg.note, font=nf, fill=NOTE_INK)
    for i, line in enumerate(seg.credit):
        # 발표용이라 눈에 띄지 않게 아주 작고 흐리게 둔다. 출처는 발표 자료에도 적는다.
        d.text((TEXT_X, 1044 + i * 16), line, font=font(13, 400), fill=CREDIT)
    brand = font(40, jua=True)
    tw = d.textlength("오늘 뭐 먹지?", font=brand)
    d.text((W - 80 - tw, H - 100), "오늘 뭐 먹지?", font=brand, fill=(150, 154, 200))
    return img


def corner_overlay(base: Image.Image) -> Image.Image:
    """폰 화면 모서리를 둥글게 덮는 겉면. 배경 그림을 모서리에만 남긴다."""
    over = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    mask = rounded_mask((PHONE_W, PHONE_H), RADIUS)
    inv = Image.eval(mask, lambda v: 255 - v)
    crop = base.crop((PHONE_X, PHONE_Y, PHONE_X + PHONE_W, PHONE_Y + PHONE_H)).convert("RGBA")
    crop.putalpha(inv)
    over.paste(crop, (PHONE_X, PHONE_Y))
    return over


def run(cmd: list[str]) -> None:
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"ffmpeg failed: {r.stderr[-800:]}")


def render_seg(i: int, seg: Seg, base: Image.Image, corners: Path, tag: str) -> Path:
    png = WORK / f"{tag}-{i:03d}.png"
    panel(seg, base, phone=seg.src is not None).save(png)
    out = WORK / f"{tag}-{i:03d}.mp4"
    clip = seg.end - seg.start
    dur = clip + seg.hold
    fade = min(0.04, clip / 4)
    if seg.src is None:
        run([
            "ffmpeg", "-v", "error", "-y", "-loop", "1", "-t", f"{dur:.3f}", "-i", str(png),
            "-f", "lavfi", "-t", f"{dur:.3f}", "-i", "anullsrc=r=48000:cl=stereo",
            "-r", str(FPS), "-c:v", "libx264", "-crf", "18", "-preset", "fast", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "192k", "-shortest", str(out),
        ])
        return out

    vchain = "[0:v]"
    pre = ""
    if seg.blur:
        x, y, w, h = seg.blur
        pre = (f"[0:v]split[a][b];[b]crop={w}:{h}:{x}:{y},boxblur=40:4[bl];"
               f"[a][bl]overlay={x}:{y}[src];")
        vchain = "[src]"
    hold = f",tpad=stop_mode=clone:stop_duration={seg.hold:.3f}" if seg.hold else ""
    vf = (f"{pre}{vchain}scale={PHONE_W}:{PHONE_H},setsar=1{hold}[ph];"
          f"[1:v][ph]overlay={PHONE_X}:{PHONE_Y}[t];[t][2:v]overlay=0:0,fps={FPS},format=yuv420p[v]")
    if seg.mute:
        audio_in = ["-f", "lavfi", "-t", f"{dur:.3f}", "-i", "anullsrc=r=48000:cl=stereo"]
        af = "[3:a]anull[aout]"
    else:
        audio_in = []
        af = (f"[0:a:0]aresample=48000,aformat=channel_layouts=stereo,"
              f"afade=t=in:d={fade:.3f},afade=t=out:st={clip - fade:.3f}:d={fade:.3f},"
              f"apad=whole_dur={dur:.3f}[aout]")
    run([
        "ffmpeg", "-v", "error", "-y",
        "-ss", f"{seg.start:.3f}", "-t", f"{clip:.3f}", "-i", str(SRC[seg.src]),
        "-loop", "1", "-t", f"{dur:.3f}", "-i", str(png),
        "-loop", "1", "-t", f"{dur:.3f}", "-i", str(corners),
        *audio_in,
        "-filter_complex", f"{vf};{af}", "-map", "[v]", "-map", "[aout]",
        "-t", f"{dur:.3f}", "-c:v", "libx264", "-crf", "18", "-preset", "fast",
        "-c:a", "aac", "-b:a", "192k", "-ar", "48000", str(out),
    ])
    return out


def build(segs: list[Seg], name: str, tag: str) -> Path:
    WORK.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(exist_ok=True)
    base = background()
    corners = WORK / "corners.png"
    # 모서리는 그림자가 깔린 판에서 떠야 테두리 색이 맞는다.
    corner_overlay(panel(Seg("01", 0, 0), base, phone=True)).save(corners)
    parts = []
    for i, seg in enumerate(segs):
        parts.append(render_seg(i, seg, base, corners, tag))
        print(f"  {tag} {i + 1}/{len(segs)}", flush=True)
    listing = WORK / f"{tag}-list.txt"
    listing.write_text("".join(f"file '{p}'\n" for p in parts), encoding="utf-8")
    out = OUT / name
    run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(listing),
         "-c", "copy", "-movflags", "+faststart", str(out)])
    return out


# ---------------------------------------------------------------- 전체 시연본
K = {
    "01": "CHAPTER 01", "02": "CHAPTER 02", "03": "CHAPTER 03", "04": "CHAPTER 04",
    "05": "CHAPTER 05", "06": "CHAPTER 06", "07": "CHAPTER 07", "08": "CHAPTER 08",
}
T = {
    "01": "오늘 뭐 먹지?",
    "02": "말로 재료 기록",
    "03": "먼저 쓸 재료 확인",
    "04": "사용·잔량 보정",
    "05": "냉장고 재료가 오늘의 메뉴로",
    "06": "유튜브 레시피도 조리 안내로",
    "07": "내 사용 방식에 맞추기",
    "08": "복구와 마무리",
}


def c(src: str, s: float, e: float, *lines: str, note: str = "", mute: bool = False,
      blur: tuple[int, int, int, int] | None = None) -> Seg:
    return Seg(src, s, e, K[src], T[src], list(lines), note, mute, blur)


FULL = [
    Seg(None, 0, 3.5, "전체 기능 시연", "오늘 뭐 먹지?",
        ["말로 관리하는 냉장고, 남은 재료로 오늘의 한 끼"]),
    # 01 시작 — 계정 입력은 생략하고 가입 버튼 장면만 가린 채 남긴다.
    c("01", 0.3, 3.0, "앱을 열면 캐릭터가 맞이해요"),
    c("01", 3.0, 5.6, "이메일 로그인 또는 회원가입"),
    c("01", 6.0, 6.9, "이메일 로그인 또는 회원가입", note="계정 입력 과정 생략"),
    c("01", 30.5, 31.9, "가입을 마치면 바로 시작", note="계정 정보는 가림 처리", blur=ACCOUNT_FIELDS),
    c("01", 32.0, 38.7, "말로 쓰려면 마이크 권한이 필요해요"),
    c("01", 38.9, 42.5, "홈에서 “헤이 키친”으로 부를 준비 완료"),
    # 02 등록 — 첫 등록은 끊지 않고, 나머지는 말·결과·홈 이동만 남긴다.
    c("02", 1.0, 12.0, "“헤이 키친” → 띠딩 소리 → 말하기",
      "“계란 열 개 넣었어. 유통기한은 10월 4일까지야.”"),
    c("02", 12.0, 22.2, "수량과 유통기한을 그대로 반영", "결과를 읽어 주고 되돌리기도 바로 가능"),
    c("02", 22.2, 25.5, "홈이 방금 넣은 재료의 기한 칸으로 이동"),
    c("02", 25.5, 35.0, "“삼겹살 300그램 넣었어. 유통기한은 10월 2일까지야.”"),
    c("02", 40.8, 51.6, "삼겹살 300g · 10월 2일 반영", "홈은 ‘빨리 먹어야 해요’ 칸으로",
      note="확인 대기 일부 생략"),
    c("02", 51.6, 59.4, "“두부 두 모 넣었어. 유통기한은 10월 3일까지야.”"),
    c("02", 65.3, 74.4, "두부 2모 · 10월 3일 반영", note="확인 대기 일부 생략"),
    c("02", 74.4, 79.8, "“대파 한 단 넣었어.” — 날짜는 말하지 않음"),
    c("02", 85.4, 94.8, "말하지 않은 날짜는 만들지 않아요", "‘기한 미입력’ → 홈: 언제까지 먹어야 해요?",
      note="확인 대기 일부 생략"),
    # 03 냉장고
    c("03", 0.0, 16.0, "기한별로 재료를 나눠 보여줘요",
      "날짜 모름 · 여유 · 며칠 안에 · 빨리 · 기한 지남"),
    c("03", 19.0, 23.0, "가장 급한 삼겹살(D-1)부터 메뉴를 권해요"),
    c("03", 24.0, 35.0, "냉장고: 등록한 재료 4가지", "이름으로 검색"),
    # 04 사용·잔량 보정
    c("04", 0.5, 17.5, "“계란 두 개 썼어.”", "계란 10개 → 8개"),
    c("04", 17.5, 35.0, "“계란 네 개 남았어.”", "쓴 양이 아니라 남은 양으로 보정 → 4개"),
    c("04", 35.5, 39.0, "기록에 사용·보정이 전후 수량과 함께 남아요"),
    c("04", 39.0, 42.0, "냉장고: 계란 4개"),
    # 05 추천·조리
    c("05", 0.0, 17.8, "먼저 쓸 삼겹살이 ‘빨리 먹어야 해요’ 칸에", "“삼겹살로 뭐 해먹을까?”"),
    c("05", 17.8, 23.9, "냉장고 재료로 메뉴 3가지 추천"),
    c("05", 24.4, 30.5, "냉장고 재료로 메뉴 3가지 추천", "두부 삼겹살 조림: 재료와 조리 순서"),
    # 촬영은 3인분으로 바꿨다가 35.5초에 2인분으로 되돌리고 조리를 시작했다.
    Seg("05", 30.5, 35.45, K["05"], T["05"],
        ["인분을 바꾸면 필요한 양도 바뀌어요", "2인분 → 3인분: 삼겹살 200g → 300g",
         "확인 후 2인분으로 조리"], hold=1.2),
    c("05", 35.6, 49.2, "조리 모드: 단계를 읽어 줘요", "“다음” — 말로 다음 단계"),
    c("05", 51.2, 66.4, "“타이머 3분”", "3분 타이머 시작", note="조리 단계 이동 일부 생략"),
    c("05", 74.9, 84.3, "“다시 읽어 줘”", note="조리 단계 이동 일부 생략"),
    c("05", 86.8, 101.5, "마지막 단계까지 읽어 주며 안내"),
    c("05", 101.5, 106.0, "‘다 만들었어요’ → 쓴 재료를 냉장고에서 차감",
      "삼겹살 300g → 100g · 두부 2모 → 1모", note="조리 단계 이동 일부 생략"),
    # 06 영상 레시피 — 유튜브 앱 화면은 소리를 끈다.
    c("06", 24.5, 31.9, "조리 탭 · 영상 레시피 링크 입력"),
    c("06", 32.0, 35.5, "유튜브에서 레시피 영상 링크 복사", mute=True),
    c("06", 39.0, 42.5, "유튜브에서 레시피 영상 링크 복사", mute=True),
    c("06", 42.5, 53.6, "영상을 재료와 조리 단계로 정리", "없는 재료(양파·청양고추)도 알려줘요"),
    c("06", 53.6, 68.8, "분석한 레시피로 조리 시작", "단계마다 읽어 주며 안내"),
    c("06", 68.8, 73.0, "완료", "영상 레시피 조리는 재고를 자동 차감하지 않아요"),
    # 07 설정
    c("07", 4.5, 9.6, "화면 테마 변경"),
    c("07", 21.0, 25.6, "홈에 바로 반영"),
    c("07", 31.5, 35.2, "기본 인분 2인분 → 4인분"),
    c("07", 35.2, 42.8, "새로 받은 추천이 4인분 기준"),
    c("07", 44.0, 50.8, "기한 알림 설정"),
    # 08 복구와 마무리
    c("08", 0.5, 21.0, "보유량보다 많이 쓴다고 하면 저장하지 않고 되물어요",
      "“계란 스무 개 썼어.” → 계란 4개 그대로"),
    c("08", 21.0, 27.5, "먼저 써야 할 재료가 오늘의 한 끼로."),
    Seg(None, 0, 4.0, "", "오늘 뭐 먹지?", ["말로 관리하고, 남은 재료로 오늘의 식사를 정합니다."]),
]

# ---------------------------------------------------------------- 발표용 90초
# IMPORTANT: 등록을 기한별 슬라이드보다 먼저 둔다. 로그인 직후 홈은 빈 냉장고라,
# 슬라이드(재료 4가지)를 먼저 보이고 빈 냉장고에서 등록하면 순서가 모순된다.


def s(src: str, a: float, b: float, kicker: str, title: str, *lines: str,
      blur: tuple[int, int, int, int] | None = None, note: str = "", hold: float = 0.0) -> Seg:
    return Seg(src, a, b, kicker, title, list(lines), note=note, blur=blur, hold=hold)


WAIT = "대기 구간 단축"
SKIP = "조리 단계 일부 생략"


SHORT = [
    s("01", 0.4, 2.9, "오늘 뭐 먹지?", "냉장고 재료로 오늘의 한 끼"),
    s("01", 3.2, 4.2, "오늘 뭐 먹지?", "냉장고 재료로 오늘의 한 끼"),
    s("01", 30.8, 31.8, "오늘 뭐 먹지?", "냉장고 재료로 오늘의 한 끼", blur=ACCOUNT_FIELDS),
    s("01", 32.2, 33.0, "오늘 뭐 먹지?", "냉장고 재료로 오늘의 한 끼"),
    s("01", 38.9, 40.6, "오늘 뭐 먹지?", "냉장고 재료로 오늘의 한 끼"),
    s("02", 1.4, 21.4, "말로 등록", "손으로 입력하지 않아요",
      "“계란 열 개 넣었어. 유통기한은 10월 4일까지야.”", "수량과 유통기한 그대로 반영"),
    s("03", 4.7, 12.7, "먼저 쓸 재료부터", "기한별로 한눈에", "재료 4가지 등록 후 홈 화면"),
    # 소리 경계(50ms 창 RMS): 명령 5.20~6.25, 결과 12.4~14.1, 명령 22.3~23.6, 결과 29.70~31.35.
    s("04", 4.8, 6.6, "쓴 만큼, 남은 만큼", "사용량 반영", "“계란 두 개 썼어.” → 8개", note=WAIT),
    s("04", 12.2, 14.3, "쓴 만큼, 남은 만큼", "사용량 반영", "“계란 두 개 썼어.” → 8개", note=WAIT),
    s("04", 22.1, 23.8, "쓴 만큼, 남은 만큼", "남은 양으로 보정", "“계란 네 개 남았어.” → 4개", note=WAIT),
    s("04", 29.0, 31.6, "쓴 만큼, 남은 만큼", "남은 양으로 보정", "“계란 네 개 남았어.” → 4개", note=WAIT),
    s("05", 0.3, 1.65, "남은 재료로 메뉴", "기한 임박 삼겹살부터", "“삼겹살로 뭐 해먹을까?”", note=WAIT),
    s("05", 5.4, 8.0, "남은 재료로 메뉴", "기한 임박 삼겹살부터", "“삼겹살로 뭐 해먹을까?”", note=WAIT),
    s("05", 13.7, 16.5, "남은 재료로 메뉴", "기한 임박 삼겹살부터", "“삼겹살로 뭐 해먹을까?”", note=WAIT),
    # 24.0~24.4 는 상세 화면 로딩(빈 화면)이라 뺀다.
    s("05", 19.5, 23.9, "남은 재료로 메뉴", "냉장고 재료로 추천", "두부 삼겹살 조림", note=WAIT),
    s("05", 24.4, 28.0, "남은 재료로 메뉴", "냉장고 재료로 추천", "두부 삼겹살 조림", note=WAIT),
    # 촬영은 3인분으로 바꿨다가 35.1초에 2인분으로 되돌렸다(35.6초부터 조리 화면 전환). 되돌린 화면을 멈춰 보여준다.
    s("05", 31.2, 35.45, "남은 재료로 메뉴", "인분에 맞춰 양 조절",
      "2인분 → 3인분: 삼겹살 200g → 300g", "확인 후 2인분으로 조리", hold=1.2),
    s("05", 49.2, 51.2, "요리 후 재고 반영", "말로 따라 하는 조리", "단계 안내 · 음성 명령", note=SKIP),
    # 타이머 응답은 54.45~56.25. 끝에 여유를 둔다.
    s("05", 51.2, 56.9, "요리 후 재고 반영", "말로 따라 하는 조리", "“타이머 3분”", note=SKIP),
    s("05", 102.0, 106.0, "요리 후 재고 반영", "다 만들면 쓴 재료 차감 (2인분)",
      "삼겹살 300g → 100g · 두부 2모 → 1모", note=SKIP),
    s("06", 46.0, 53.5, "유튜브 레시피도", "링크 하나로 조리 안내", "영상을 재료와 조리 단계로 정리",
      note=WAIT),
    s("08", 21.0, 25.5, "오늘 뭐 먹지?", "먼저 써야 할 재료가 오늘의 한 끼로"),
]


MUSIC_CREDIT = [
    "Music: Life of Riley · Kevin MacLeod (incompetech.com) · CC BY 4.0",
]


def with_credit(segs: list[Seg]) -> list[Seg]:
    """배경음악판은 마지막 화면에 출처를 적는다."""
    from dataclasses import replace
    return [*segs[:-1], replace(segs[-1], credit=MUSIC_CREDIT)]


def main() -> None:
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    if which in ("full", "all"):
        print(build(FULL, "today-meal-full-v3.mp4", "full"))
    if which == "short-bgm":
        # 배경음악을 깔 그림판. 소리는 mix_bgm.sh 가 섞는다.
        print(build(with_credit(SHORT), "../work/today-meal-90s-v3-picture.mp4", "shortbgm"))
    if which in ("short", "all"):
        print(build(SHORT, "today-meal-90s-v3-nobgm.mp4", "short"))


if __name__ == "__main__":
    main()
