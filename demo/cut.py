"""챕터 원본에서 멈춰 있는 대기 구간을 잘라 편집본을 만든다.

원본(long/)은 읽기만 한다. 결과는 edit/NN-이름-cut.mp4 와 잘라낸 구간 기록(cuts.md).

자르는 규칙
- 화면이 멈춰 있고(freezedetect) 소리도 없는(silencedetect) 구간만 자른다.
- 맨 앞 대기는 움직이기 1초 전부터 남긴다. 맨 끝은 마지막 화면을 2.5초 남긴다.
- 중간 대기는 앞 2.5초(결과를 읽을 시간)와 뒤 0.5초를 남기고 가운데를 뺀다.
- 말소리나 앱 음성이 있는 구간은 화면이 멈춰 있어도 자르지 않는다.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
FREEZE_NOISE = 0.003  # 대기 화면의 숨쉬기 애니메이션은 무시하는 값. 0.001 은 깜빡임에 끊긴다.
FREEZE_MIN = 2.5
SILENCE_DB = -38
HOLD_HEAD = 2.5
HOLD_TAIL = 0.5
LEAD_KEEP = 1.0
END_KEEP = 2.5
MIN_GAIN = 1.0  # 이보다 적게 줄면 자르지 않는다. 잦은 컷은 오히려 튄다.

# 원본, 최소 시작 시각, 말하는 챕터인지.
# IMPORTANT: 말하는 챕터는 소리가 있는 구간을 남긴다. "헤이 키친"은 멈춘 홈 화면 위에서
# 말한다. 말이 없는 챕터는 화면만 본다 — 마이크의 작은 잡음에 대기 구간이 끊겨 남았다.
CHAPTERS = [
    ("01-시작-take01", 0.0, False),
    # 앞 10초에 마이페이지 "재료를 버렸어요" 알림이 찍혀 있다.
    ("02-등록-take02", 10.0, True),
    # 04·05·08 은 마이크를 기다리거나 홈 메뉴 알약이 돌아 화면이 멈춘 것으로 잡히지 않는다.
    # 첫 호출 화면이 뜨기 4초 전부터 쓴다("헤이 키친" 발화를 남긴다).
    ("03-냉장고-take01", 0.0, False),
    ("04-사용정정-take01", 136.4, True),
    ("05-추천조리-take02", 46.6, True),
    ("06-영상레시피-take01", 0.0, False),
    ("07-설정-take01", 0.0, False),
    ("08-마무리-take01", 43.1, True),
]


def run(args: list[str]) -> str:
    return subprocess.run(args, capture_output=True, text=True).stderr


def duration(path: Path) -> float:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True,
    ).stdout
    return float(out.strip())


def intervals(log: str, kind: str, end: float) -> list[tuple[float, float]]:
    starts = [float(x) for x in re.findall(rf"{kind}_start: ([0-9.]+)", log)]
    ends = [float(x) for x in re.findall(rf"{kind}_end: ([0-9.]+)", log)]
    if len(ends) < len(starts):
        ends.append(end)
    return list(zip(starts, ends))


def intersect(a: list[tuple[float, float]], b: list[tuple[float, float]]) -> list[tuple[float, float]]:
    out = []
    for s1, e1 in a:
        for s2, e2 in b:
            s, e = max(s1, s2), min(e1, e2)
            if e - s >= FREEZE_MIN:
                out.append((s, e))
    return out


def plan(
    src: Path, min_start: float, spoken: bool
) -> tuple[list[tuple[float, float]], list[str]]:
    total = duration(src)
    frozen = intervals(
        run(["ffmpeg", "-i", str(src), "-map", "0:v", "-vf",
             f"scale=270:-1,freezedetect=n={FREEZE_NOISE}:d={FREEZE_MIN}", "-f", "null", "-"]),
        "freeze", total,
    )
    silent = intervals(
        run(["ffmpeg", "-i", str(src), "-map", "0:a:0", "-af",
             f"silencedetect=n={SILENCE_DB}dB:d=1", "-f", "null", "-"]),
        "silence", total,
    ) if spoken else [(0.0, total)]
    idle = intersect(frozen, silent)

    start, end = min_start, total
    notes = []
    cuts: list[tuple[float, float]] = []
    for s, e in idle:
        if s <= max(min_start, 0.5):
            start = max(start, e - LEAD_KEEP)
            continue
        if e >= total - 0.5:
            end = min(end, s + END_KEEP)
            continue
        a, b = s + HOLD_HEAD, e - HOLD_TAIL
        if b - a >= MIN_GAIN and a >= start:
            cuts.append((a, b))

    keep, cursor = [], start
    for a, b in cuts:
        if a > cursor:
            keep.append((cursor, a))
        cursor = max(cursor, b)
    if end > cursor:
        keep.append((cursor, end))

    notes.append(f"- 원본 {total:.1f}s → 편집 {sum(e - s for s, e in keep):.1f}s")
    notes.append(f"- 시작 {start:.1f}s, 끝 {end:.1f}s")
    for a, b in cuts:
        notes.append(f"- 대기 삭제 {a:.1f}s ~ {b:.1f}s ({b - a:.1f}s)")
    return keep, notes


def render(src: Path, dst: Path, keep: list[tuple[float, float]]) -> None:
    parts, labels = [], []
    for i, (s, e) in enumerate(keep):
        parts.append(f"[0:v]trim=start={s:.3f}:end={e:.3f},setpts=PTS-STARTPTS[v{i}]")
        parts.append(f"[0:a:0]atrim=start={s:.3f}:end={e:.3f},asetpts=PTS-STARTPTS[a{i}]")
        labels.append(f"[v{i}][a{i}]")
    parts.append(f"{''.join(labels)}concat=n={len(keep)}:v=1:a=1[v][a]")
    cmd = [
        "ffmpeg", "-v", "error", "-y", "-i", str(src),
        "-filter_complex", ";".join(parts), "-map", "[v]", "-map", "[a]",
        "-r", "60", "-c:v", "libx264", "-crf", "18", "-preset", "veryfast",
        "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart",
        str(dst),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg failed for {src.name}: {result.stderr[-500:]}")


def main() -> None:
    only = set(sys.argv[1:])
    (ROOT / "edit").mkdir(exist_ok=True)
    report = ["# 챕터 편집본 컷 기록", "", "원본은 `long/`, 백업은 `backup-originals-20261001/`.", ""]
    for name, min_start, spoken in CHAPTERS:
        if only and not any(name.startswith(o) for o in only):
            continue
        src = ROOT / "long" / f"{name}.mp4"
        dst = ROOT / "edit" / f"{name}-cut.mp4"
        keep, notes = plan(src, min_start, spoken)
        render(src, dst, keep)
        report += [f"## {dst.name}", *notes, ""]
        print(f"{dst.name}: {notes[0][2:]}", flush=True)
    if not only:
        (ROOT / "edit" / "cuts.md").write_text("\n".join(report), encoding="utf-8")


if __name__ == "__main__":
    main()
