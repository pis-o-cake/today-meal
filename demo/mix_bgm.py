"""90초 영상에 배경음악을 깐다. 그림은 다시 인코딩하지 않는다.

    .venv/bin/python mix_bgm.py --music "music/Life of Riley.mp3" --until 30 --out final/preview/a.mp4
    .venv/bin/python mix_bgm.py --music "music/Life of Riley.mp3"     # 90초 전체 → final/today-meal-90s-v3.mp4

- 음악은 은은한 바닥(BED)으로 깐다. 말·띠딩·앱 음성 구간은 미리 알고 있으므로 말이 시작되기
  LEAD 초 전부터 DOWN 초에 걸쳐 코사인 곡선으로 낮추고, 끝나면 UP 초에 걸쳐 더 천천히 되돌린다.
  사이드체인처럼 말이 들린 뒤에 확 줄어드는 일이 없다.
- 짧은 말 사이 간격은 이어 붙여 출렁이지 않게 하고, 첫 "헤이 키친 → 띠딩 → 명령 → 결과"는 통째로 낮춘다.
- 시작 1.5초 페이드인. 마지막 장면(말 없음)에서 살짝 올린 뒤 페이드아웃.
- 곡이 영상보다 짧으면 SEAM_AT 에서 끊고 처음부터 잇는다(이음매는 음악이 낮아진 구간).
- 음악 박자에 맞추려고 영상을 자르지 않는다. 그림·말소리는 그대로 두고 소리만 섞는다.
"""

from __future__ import annotations

import argparse
import re
import subprocess
from pathlib import Path

import render

ROOT = Path(__file__).resolve().parent
PICTURE = ROOT / "work" / "today-meal-90s-v3-picture.mp4"

BED_LUFS = -24.0  # 말이 없을 때 음악 크기
DUCK_DB = -12.0  # 말이 나올 때 추가로 낮추는 양
LEAD = 0.8  # 말 시작보다 이만큼 먼저 낮추기 시작한다
DOWN = 0.8  # 내려가는 데 걸리는 시간(LEAD 와 같으면 말 시작 때 다 내려가 있다)
TAIL = 0.3  # 말 끝난 뒤 그대로 두는 시간
UP = 1.5  # 다시 올라오는 데 걸리는 시간. 내려갈 때보다 천천히.
MERGE_GAP = 2.5
END_LIFT_DB = 2.0
FADE_IN = 1.5
FADE_OUT = 2.5
XFADE = 2.5
SEAM_AT = 45.0


def duration(path: Path) -> float:
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "csv=p=0", str(path)], capture_output=True, text=True).stdout
    return float(out)


def speech_regions(path: Path, total: float) -> list[tuple[float, float]]:
    log = subprocess.run(["ffmpeg", "-i", str(path), "-map", "0:a:0", "-af",
                          "silencedetect=n=-40dB:d=0.3", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    starts = [float(x) for x in re.findall(r"silence_start: ([0-9.]+)", log)]
    ends = [float(x) for x in re.findall(r"silence_end: ([0-9.]+)", log)]
    regions, cursor = [], 0.0
    for s, e in zip(starts, ends + [total]):
        if s - cursor > 0.05:
            regions.append((cursor, s))
        cursor = e
    if total - cursor > 0.05:
        regions.append((cursor, total))
    return regions


def segment_window(src: str) -> tuple[float, float]:
    """출력 영상에서 한 챕터 원본이 처음 나오는 구간."""
    t, first, last = 0.0, None, None
    for seg in render.SHORT:
        d = seg.end - seg.start + seg.hold
        if seg.src == src:
            first = t if first is None else first
            last = t + d
        elif first is not None:
            break
        t += d
    return first or 0.0, last or 0.0


def plan(total: float) -> list[tuple[float, float]]:
    """음악을 다 낮춰 둘 구간."""
    regions = [(a, min(total, b + TAIL)) for a, b in speech_regions(PICTURE, total)]
    regions.append(segment_window("02"))  # 첫 음성 등록 전체
    regions.sort()
    merged: list[list[float]] = []
    for a, b in regions:
        if merged and a - merged[-1][1] <= MERGE_GAP:
            merged[-1][1] = max(merged[-1][1], b)
        else:
            merged.append([a, b])
    return [(a, b) for a, b in merged]


def duck_expr(regions: list[tuple[float, float]]) -> str:
    """0(평소)~1(낮춤) 덮개. 코사인 곡선이라 시작과 끝이 꺾이지 않는다."""
    parts = []
    for a, b in regions:
        down = f"(0.5-0.5*cos(PI*clip((t-{a - LEAD:.3f})/{DOWN},0,1)))"
        up = f"(0.5+0.5*cos(PI*clip((t-{b:.3f})/{UP},0,1)))"
        parts.append(f"min({down},{up})")
    cover = parts[0]
    for p in parts[1:]:
        cover = f"max({cover},{p})"
    gain = 10 ** (DUCK_DB / 20)
    return f"1-(1-{gain:.4f})*{cover}"


def music_chain(music: Path, total: float, full: float) -> str:
    regions = [(a, b) for a, b in plan(full) if a - LEAD < total]
    lift = 10 ** (END_LIFT_DB / 20)
    last_start = full - (render.SHORT[-1].end - render.SHORT[-1].start)
    if duration(music) >= total:
        source = "[1:a]asetpts=PTS-STARTPTS"
    else:
        # IMPORTANT: 이음매(첫 재생 끝)를 말소리로 음악이 낮아진 구간에 숨긴다.
        source = (f"[1:a]atrim=0:{SEAM_AT:.3f},asetpts=PTS-STARTPTS[m1];[2:a]asetpts=PTS-STARTPTS[m2];"
                  f"[m1][m2]acrossfade=d={XFADE}:c1=tri:c2=tri")
    return (
        f"{source},atrim=0:{total:.3f},asetpts=PTS-STARTPTS,aresample=48000,"
        f"aformat=channel_layouts=stereo,loudnorm=I={BED_LUFS}:TP=-6:LRA=7,"
        f"volume='{duck_expr(regions)}':eval=frame,"
        f"volume='if(gte(t,{last_start:.3f}),{lift:.4f},1)':eval=frame,"
        f"afade=t=in:d={FADE_IN},afade=t=out:st={total - FADE_OUT:.3f}:d={FADE_OUT}[m]"
    )


def run(cmd: list[str]) -> None:
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr[-800:])


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--music", required=True)
    ap.add_argument("--out", default=str(ROOT / "final" / "today-meal-90s-v3.mp4"))
    ap.add_argument("--until", type=float, default=0.0, help="미리보기 길이(초). 0 이면 전체")
    args = ap.parse_args()

    music = Path(args.music)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    full = duration(PICTURE)
    total = args.until or full
    chain = music_chain(music, total, full)
    inputs = ["-i", str(PICTURE), "-i", str(music), "-i", str(music)]
    music_only = ROOT / "work" / f"{out.stem}-music.wav"
    run(["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", chain,
         "-map", "[m]", "-t", f"{total:.3f}", str(music_only)])
    run(["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex",
         f"{chain};[0:a]atrim=0:{total:.3f},aresample=48000,aformat=channel_layouts=stereo[v];"
         f"[v][m]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.89:level=false[a]",
         "-map", "0:v", "-map", "[a]", "-t", f"{total:.3f}", "-c:v", "copy",
         "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", str(out)])
    print("SAVED", out)


if __name__ == "__main__":
    main()
