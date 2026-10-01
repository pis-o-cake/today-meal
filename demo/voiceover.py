"""발표용 90초 영상의 사용자 목소리만 AI 음성으로 바꾼다(후시 녹음).

앱 응답·띠딩 소리는 원본 녹화의 폰 재생음 트랙(long/*.mp4 a:2)을 그대로 쓰고, 별도로 녹음한
사용자 마이크 트랙은 버린다. AI 음성은 원래 발화의 구절 시작·길이에 맞춰 놓는다 — 화면의 받아쓰기가
구절 단위로 뜨므로 구절이 늦으면 글자가 말보다 먼저 보인다.

    export GEMINI_API_KEY=...
    .venv/bin/python voiceover.py candidates   # 계란 구간 목소리 후보 → final/voiceover/candidates/
    .venv/bin/python voiceover.py short B      # 90초 전체(B Leda) → final/voiceover/

그림은 v3 그림판(work/today-meal-90s-v3-picture.mp4)에 "AI 후시 녹음" 표시만 얹고,
배경음악은 v3 에 깐 음악 트랙(work/today-meal-90s-v3-music.wav)을 그대로 쓴다.
long/·edit/·final/ 의 기존 파일은 읽기만 한다. 결과는 final/voiceover/ 에 쓴다.
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
import wave
from dataclasses import dataclass, field
from itertools import combinations
from pathlib import Path

import numpy as np
from loguru import logger
from PIL import Image, ImageDraw

import render

ROOT = Path(__file__).resolve().parent
LONG = ROOT / "long"
EDIT = ROOT / "edit"
WORK = ROOT / "work" / "voice"
TTS_CACHE = WORK / "tts"
OUT = ROOT / "final" / "voiceover"
PICTURE = ROOT / "work" / "today-meal-90s-v3-picture.mp4"
MUSIC = ROOT / "work" / "today-meal-90s-v3-music.wav"
MUSIC_SRC = ROOT / "music" / "Life of Riley.mp3"  # v3 곡(render.MUSIC_CREDIT)
ORIGINAL = ROOT / "final" / "today-meal-90s-v3.mp4"
WHISPER_MODEL = ROOT / "models" / "ggml-small.bin"

SR = 48000
# 원본 녹화(record.sh) 트랙 순서 (목소리, 폰 재생음). 앱 TTS·띠딩 원음은 폰 재생음에 있다.
# IMPORTANT: 01 만 이전 record.sh 로 찍어 소리 트랙이 3개(혼합·폰 재생음·마이크 원본)다.
TRACKS = {3: (2, 1), 4: (1, 2), 5: (1, 2)}

TTS_MODEL = "gemini-3.8-flash-tts"
TTS_SR = 24000
TTS_RETRIES = 4
TTS_BACKOFF = 20.0
# IMPORTANT: 말투 지시문을 붙이면 지시까지 소리 내어 읽거나 대사를 빼먹었다(한국어·영어 모두).
# 대사만 보내고, 밝은 말투는 목소리 선택으로 정한다. 결과는 받아쓰기로 검사한다.

FRAME = 0.01
VOICED_DB = -45.0  # 잡음 제거본 바닥 약 -66dB, 말소리 -20dB 안팎
MERGE_GAP = 0.1  # 이보다 짧은 끊김은 한 덩어리(받침·파열음 사이)
PAD = 0.03  # 구절 앞뒤로 남기는 숨
EDGE_FADE = 0.01
TEMPO_MIN, TEMPO_MAX = 0.92, 1.10  # 이 범위 밖으로 늘이고 줄이면 말투가 어색해진다
MIN_PAUSE = 0.22  # 구절 사이 최소 쉼
NOISE_FLATNESS = 0.6
NOISE_DB = -15.0  # 끝 잡음은 -6dB 로 말소리(-9dB 이하)보다 크다
TAIL_KEEP = 0.15  # 마지막 말소리 뒤로 남기는 여운

BADGE = "사용자 음성 · AI 후시 녹음"


class VoiceoverError(RuntimeError):
    pass


@dataclass(frozen=True)
class Voice:
    key: str
    name: str  # Gemini 프리셋 목소리
    label: str


VOICES = [
    Voice("A", "Zephyr", "Zephyr · 밝은 여성"),
    Voice("B", "Leda", "Leda · 젊은 여성"),
    Voice("C", "Puck", "Puck · 경쾌한 남성"),
]


@dataclass(frozen=True)
class Line:
    """90초 영상의 한 구간(render.SHORT 순번) 안에서 사용자가 한 말.

    window 는 구간 시작 기준 초. 그 안의 원래 목소리를 구절 수만큼 나눠 각 구절 자리에 AI 음성을 놓는다.
    phrases 는 TTS 에 보낼 글. 숫자는 읽는 법이 갈리지 않게 한글로 쓴다.
    """

    seg: int
    window: tuple[float, float]
    phrases: tuple[str, ...]
    check: tuple[str, ...] = ()  # 받아쓰기에 모두 나와야 하는 말. "a|b" 는 둘 중 하나(공백·대소문자 무시)


LINES = [
    Line(5, (0.0, 9.8), ("헤이 키친.", "계란 열 개 넣었어.", "유통기한은 시월 사일까지야."),
         ("키친|kitchen", "계란", "넣었어", "유통기한", "4일|사일")),
    Line(7, (0.2, 1.75), ("계란 두 개 썼어.",), ("계란", "썼어")),
    Line(9, (0.0, 1.69), ("계란 네 개 남았어.",), ("계란", "남았어")),
    # 0.2s·2.3s 의 짧은 소리는 숨·잡음이라 창에서 뺀다.
    Line(12, (0.45, 2.25), ("삼겹살로 뭐 해 먹을까?",), ("삼겹살", "먹을까")),
    Line(18, (0.3, 1.9), ("타이머 삼 분.",), ("타이머", "3분|삼분")),
]


@dataclass
class Placed:
    text: str
    orig: tuple[float, float]  # 구간 기준 원래 구절
    start: float
    dur: float
    tempo: float
    notes: list[str] = field(default_factory=list)


# ---------------------------------------------------------------- 소리 입출력

def run(cmd: list[str]) -> subprocess.CompletedProcess:
    r = subprocess.run(cmd, capture_output=True)
    if r.returncode != 0:
        raise VoiceoverError(f"command failed: {cmd[0]} {r.stderr.decode(errors='replace')[-600:]}")
    return r


def pcm(path: Path, stream: int, ss: float | None = None, t: float | None = None,
        sr: int = SR, ch: int = 1) -> np.ndarray:
    cmd = ["ffmpeg", "-v", "error"]
    if ss is not None:
        cmd += ["-ss", f"{ss:.4f}"]
    if t is not None:
        cmd += ["-t", f"{t:.4f}"]
    cmd += ["-i", str(path), "-map", f"0:a:{stream}", "-ac", str(ch), "-ar", str(sr), "-f", "f32le", "-"]
    a = np.frombuffer(run(cmd).stdout, dtype=np.float32).copy()
    return a.reshape(-1, ch) if ch > 1 else a


def write_wav(path: Path, a: np.ndarray, sr: int = SR) -> None:
    ch = 1 if a.ndim == 1 else a.shape[1]
    r = subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(sr), "-ac", str(ch),
                        "-i", "-", "-c:a", "pcm_s16le", str(path)],
                       input=np.ascontiguousarray(a, dtype=np.float32).tobytes(), capture_output=True)
    if r.returncode != 0:
        raise VoiceoverError(f"wav write failed: {r.stderr.decode(errors='replace')[-300:]}")


def duration(path: Path) -> float:
    out = run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0",
               str(path)]).stdout
    return float(out)


def frame_db(a: np.ndarray, sr: int = SR) -> np.ndarray:
    n = int(FRAME * sr)
    k = len(a) // n
    rms = np.sqrt(np.mean(a[: k * n].reshape(k, n) ** 2, axis=1) + 1e-12)
    return 20 * np.log10(rms)


def voiced_spans(a: np.ndarray, sr: int = SR) -> list[tuple[float, float]]:
    on = frame_db(a, sr) > VOICED_DB
    spans: list[list[float]] = []
    for i, v in enumerate(on):
        if not v:
            continue
        t = i * FRAME
        if spans and t - spans[-1][1] <= MERGE_GAP:
            spans[-1][1] = t + FRAME
        else:
            spans.append([t, t + FRAME])
    return [(s, e) for s, e in spans if e - s >= 0.06]


def split_phrases(spans: list[tuple[float, float]], n: int,
                  ref: list[float] | None = None) -> list[tuple[float, float]]:
    """소리 덩어리를 구절 n 개로 묶는다.

    ref 가 없으면 가장 긴 쉼 n-1 곳에서 끊는다(사람 녹음은 구절 사이 쉼이 뚜렷하다).
    ref(원래 구절 길이)가 있으면 구절 길이 비율이 원래와 가장 비슷한 끊는 자리를 고른다 —
    TTS 는 문장 안에서도 쉬어 가장 긴 쉼이 구절 경계가 아닐 때가 있다.
    """
    if len(spans) < n:
        raise VoiceoverError(f"expected {n} phrases, found {len(spans)} voiced spans")

    def group(cuts: tuple[int, ...]) -> list[tuple[float, float]]:
        bounds = [0, *cuts, len(spans)]
        return [(spans[bounds[i]][0], spans[bounds[i + 1] - 1][1]) for i in range(n)]

    gap = {i: spans[i][0] - spans[i - 1][1] for i in range(1, len(spans))}
    if ref is None:
        return group(tuple(sorted(sorted(gap, key=gap.get, reverse=True)[: n - 1])))

    def cost(cuts: tuple[int, ...]) -> float:
        logs = np.log([(e - s) / r for (s, e), r in zip(group(cuts), ref)])
        # 쉼이 길수록 조금 유리하게. 비율이 비슷한 후보끼리만 가른다.
        return float(np.var(logs)) - 0.02 * sum(gap[c] for c in cuts)

    return group(min(combinations(range(1, len(spans)), n - 1), key=cost))


def voiced_rms_db(a: np.ndarray) -> float:
    db = frame_db(a)
    on = db > VOICED_DB
    if not on.any():
        raise VoiceoverError("no voiced frames")
    return float(20 * np.log10(np.sqrt(np.mean((10 ** (db[on] / 20)) ** 2))))


# ---------------------------------------------------------------- 원본 위치

def chapter_files(src: str) -> tuple[Path, Path]:
    edit = render.SRC[src]
    return edit, LONG / edit.name.replace("-cut.mp4", ".mp4")


def segment_durations() -> list[float]:
    """그림판에 실제로 들어간 구간 길이.

    IMPORTANT: 30fps 로 떨어지지 않는 구간(1.35s 등)은 한 틀 길어진다. 명목 길이로 소리를 붙이면
    뒤로 갈수록 화면보다 소리가 앞선다. 그림판을 만든 구간 파일(work/render/shortbgm-NNN.mp4)의 길이를 쓴다.
    """
    out = []
    for i, seg in enumerate(render.SHORT):
        part = ROOT / "work" / "render" / f"shortbgm-{i:03d}.mp4"
        if not part.exists():
            raise VoiceoverError(f"missing picture segment {part.name}; run render.py short-bgm")
        out.append(video_duration(part))
    return out


def segment_times() -> list[float]:
    """render.SHORT 각 구간이 90초 영상에서 시작하는 시각."""
    return [float(t) for t in np.concatenate([[0.0], np.cumsum(segment_durations())[:-1]])]


def keeps(src: str) -> list[tuple[float, float]]:
    """편집본(edit/)이 원본(long/)에서 남긴 구간. cut.py 와 같은 계산을 쓴다.

    IMPORTANT: 02 는 cut.py 로 만든 뒤 앞을 12초 더 잘랐다(edit/cuts.md 끝). 계산한 길이보다
    편집본 영상이 짧으면 그만큼 앞에서 자른 것으로 본다.
    """
    edit, long_ = chapter_files(src)
    cache = WORK / "keeps.json"
    known = json.loads(cache.read_text()) if cache.exists() else {}
    name = long_.stem
    if name not in known:
        import cut
        spec = next(c for c in cut.CHAPTERS if c[0] == name)
        known[name] = cut.plan(long_, spec[1], spec[2])[0]
        WORK.mkdir(parents=True, exist_ok=True)
        cache.write_text(json.dumps(known, indent=1, ensure_ascii=False))
    ranges = [tuple(r) for r in known[name]]
    lead = sum(b - a for a, b in ranges) - video_duration(edit)
    if lead > 0.1:
        ranges[0] = (ranges[0][0] + lead, ranges[0][1])
    return ranges


def video_duration(path: Path) -> float:
    out = run(["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "stream=duration",
               "-of", "csv=p=0", str(path)]).stdout
    return float(out)


def pieces(i: int) -> list[tuple[float, float]]:
    """구간 i 의 편집본 시간을 원본 시간 조각(시작, 길이)으로 옮긴다. 컷을 걸치면 여러 조각이다."""
    seg = render.SHORT[i]
    out, t = [], 0.0
    for a, b in keeps(seg.src):
        lo, hi = max(seg.start, t), min(seg.end, t + b - a)
        if hi - lo > 1e-3:
            out.append((a + lo - t, hi - lo))
        t += b - a
    if abs(sum(d for _, d in out) - (seg.end - seg.start)) > 0.01:
        raise VoiceoverError(f"segment {i} outside edit range")
    return out


def frames(path: Path, ss: float, t: float) -> np.ndarray:
    r = run(["ffmpeg", "-v", "error", "-ss", f"{ss:.3f}", "-t", f"{t:.3f}", "-i", str(path),
             "-vf", "fps=60,scale=36:80,format=gray", "-f", "rawvideo", "-"])
    return np.frombuffer(r.stdout, np.uint8).reshape(-1, 36 * 80).astype(np.float32)


def verify(i: int) -> None:
    """원본 위치를 화면으로 검산한다. 화면이 움직이는 구간에서 한 틀(1/60초) 넘게 어긋나면 멈춘다."""
    seg = render.SHORT[i]
    edit, long_ = chapter_files(seg.src)
    start, dur = pieces(i)[0]
    dur = min(dur, 3.0)
    span = 0.3
    e = frames(edit, seg.start, dur)
    lf = frames(long_, start - span, dur + 2 * span)
    errs = np.array([np.mean(np.abs(lf[k: k + len(e)] - e)) for k in range(len(lf) - len(e) + 1)])
    k = int(np.argmin(errs))
    diff = k / 60 - span
    distinct = errs[k] * 3 < np.median(errs)
    logger.info("verify seg={} diff={:+.3f}s err={:.2f} median={:.2f}", i, diff, errs[k], np.median(errs))
    if not distinct or abs(diff) <= 1.5 / 60:
        return
    # 반복 애니메이션(스플래시)은 엉뚱한 자리와도 맞는다. 목소리를 놓는 구간만 멈춘다.
    if any(line.seg == i for line in LINES):
        raise VoiceoverError(f"segment {i} off by {diff:+.3f}s against picture")
    logger.warning("verify seg={} ambiguous match {:+.3f}s (no voice line, kept edit timing)", i, diff)


def tracks(path: Path) -> tuple[int, int]:
    """(목소리, 폰 재생음) 소리 트랙 번호."""
    out = run(["ffprobe", "-v", "error", "-select_streams", "a", "-show_entries", "stream=index",
               "-of", "csv=p=0", str(path)]).stdout.split()
    if len(out) not in TRACKS:
        raise VoiceoverError(f"unexpected audio track count {len(out)} in {path.name}")
    return TRACKS[len(out)]


def source(path: Path, stream: int, parts: list[tuple[float, float]], ch: int = 1) -> np.ndarray:
    return np.concatenate([pcm(path, stream, a, d, ch=ch)[: int(round(d * SR))] for a, d in parts])


# ---------------------------------------------------------------- TTS

def tts(text: str, voice: str) -> Path:
    """대사를 합성해 24kHz 모노 wav 로 저장한다. 같은 대사·목소리는 다시 부르지 않는다."""
    TTS_CACHE.mkdir(parents=True, exist_ok=True)
    key = hashlib.sha1(f"{TTS_MODEL}|{voice}|{text}".encode()).hexdigest()[:10]
    out = TTS_CACHE / f"{voice}-{key}.wav"
    if out.exists():
        return out
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        raise VoiceoverError("GEMINI_API_KEY is not set")
    body = {
        "contents": [{"parts": [{"text": text}]}],
        "generationConfig": {
            "responseModalities": ["AUDIO"],
            "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": voice}}},
        },
    }
    req = urllib.request.Request(
        f"https://generativelanguage.googleapis.com/v1beta/models/{TTS_MODEL}:generateContent",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "x-goog-api-key": api_key})
    pcm_bytes = b""
    for attempt in range(TTS_RETRIES):
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                data = json.load(r)
            pcm_bytes = base64.b64decode(data["candidates"][0]["content"]["parts"][0]["inlineData"]["data"])
            break
        except urllib.error.HTTPError as e:
            # 분당 호출 한도(429)는 잠시 뒤 풀린다. 다른 오류는 바로 알린다.
            if e.code != 429 or attempt == TTS_RETRIES - 1:
                raise VoiceoverError(f"TTS failed for voice={voice}: HTTP {e.code}") from e
            logger.warning("TTS rate limited voice={} attempt={}", voice, attempt + 1)
            time.sleep(TTS_BACKOFF * (attempt + 1))
        except (KeyError, IndexError, ValueError, OSError) as e:
            raise VoiceoverError(f"TTS failed for voice={voice}: {e}") from e
    with wave.open(str(out), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(TTS_SR)
        w.writeframes(pcm_bytes)
    return out


def transcribe(a: np.ndarray) -> str:
    tmp = WORK / "asr-check.wav"
    write_wav(tmp, a)
    r = run(["whisper-cli", "-m", str(WHISPER_MODEL), "-l", "ko", "-nt", "-np", "-f", str(tmp)])
    return r.stdout.decode().strip()


def flatness(a: np.ndarray, sr: int = SR) -> np.ndarray:
    """10ms 틀별 스펙트럼 평탄도. 말소리 0.1 안팎, 잡음 0.5 이상."""
    n = int(FRAME * sr)
    k = len(a) // n
    # TTS 는 24kHz 를 올려 받은 소리라 11kHz 위가 비어 있다. 그 아래 대역만 본다.
    spec = np.abs(np.fft.rfft(a[: k * n].reshape(k, n) * np.hanning(n), axis=1))[:, 1: n * 11000 // sr] + 1e-9
    return np.exp(np.mean(np.log(spec), axis=1)) / np.mean(spec, axis=1)


def strip_tail_noise(a: np.ndarray) -> np.ndarray:
    """TTS 끝에 붙어 나오는 깨진 데이터를 잘라낸다.

    WARNING: Gemini TTS 출력은 목소리와 상관없이 끝 약 120ms 가 같은 바이트의 -6dB 잡음(평탄도 0.8)이었다.
    그대로 두면 문장 끝마다 "지직" 소리가 난다. 끝에서부터 잡음·무음 틀을 걷어낸다.
    """
    db, flat = frame_db(a), flatness(a)
    noise = (flat > NOISE_FLATNESS) & (db > NOISE_DB)
    g = len(db)  # 끝 잡음이 시작하는 틀
    while g > 0 and (noise[g - 1] or db[g - 1] < VOICED_DB):
        g -= 1
    if noise[:g].any():
        raise VoiceoverError(f"TTS has {int(noise[:g].sum())} noise frames inside speech")
    tail = g
    while tail < len(db) and not noise[tail]:
        tail += 1
    # 말끝 여운은 남기되 잡음 앞에서 끊는다.
    keep = min(g + int(TAIL_KEEP / FRAME), tail)
    logger.info("TTS tail noise stripped: kept {:.2f}s of {:.2f}s", keep * FRAME, len(a) / SR)
    return a[: int(keep * FRAME * SR)]


def line_audio(line: Line, voice: Voice, ref: list[float]) -> list[np.ndarray]:
    """한 줄을 한 번에 합성하고 구절별로 나눈다.

    구절마다 따로 합성하면 문장 억양이 끊기고, "헤이 키친" 만 보내면 영어식으로 읽는다.
    받아쓰기에 필요한 말이 빠지면 다시 합성한다(같은 글도 매번 조금씩 다르게 나온다).
    """
    text = " ".join(line.phrases)
    for attempt in range(TTS_RETRIES):
        path = tts(text, voice.name)
        a = strip_tail_noise(pcm(path, 0))
        norm = transcribe(a).replace(" ", "").lower()
        missing = [w for w in line.check if not any(alt in norm for alt in w.split("|"))]
        if not missing:
            break
        logger.warning("TTS mismatch voice={} attempt={} missing={} heard={}", voice.name,
                       attempt + 1, missing, norm)
        path.unlink()
    else:
        raise VoiceoverError(f"TTS text mismatch voice={voice.name}")
    parts = split_phrases(voiced_spans(a), len(line.phrases), ref)
    out = []
    for s, e in parts:
        clip = a[max(0, int((s - PAD) * SR)): int((e + PAD) * SR)].copy()
        f = int(EDGE_FADE * SR)
        clip[:f] *= np.linspace(0, 1, f)
        clip[-f:] *= np.linspace(1, 0, f)
        out.append(clip)
    return out


def tempo(a: np.ndarray, rate: float) -> np.ndarray:
    if abs(rate - 1) < 0.005:
        return a
    src, dst = WORK / "tempo-in.wav", WORK / "tempo-out.wav"
    write_wav(src, a)
    run(["ffmpeg", "-v", "error", "-y", "-i", str(src), "-af", f"atempo={rate:.4f}", str(dst)])
    return pcm(dst, 0)


# ---------------------------------------------------------------- 구간 소리

def segment_audio(i: int, voice: Voice | None, report: list[Placed]) -> np.ndarray:
    """구간 i 의 대사 트랙(스테레오). 앱 원음 + AI 음성. voice=None 이면 원래 혼합 트랙."""
    seg = render.SHORT[i]
    clip = seg.end - seg.start
    edit, long_ = chapter_files(seg.src)
    if voice is None:
        out = pcm(edit, 0, seg.start, clip, ch=2)
    else:
        verify(i)
        parts = pieces(i)
        voice_t, app_t = tracks(long_)
        out = source(long_, app_t, parts, ch=2)
        mic = source(long_, voice_t, parts)
        for line in (x for x in LINES if x.seg == i):
            a, b = line.window
            win = mic[int(a * SR): int(b * SR)]
            spans = [(s + a, e + a) for s, e in voiced_spans(win)]
            orig = split_phrases(spans, len(line.phrases))
            # 첫 구절도 창 앞·구간 첫 페이드 안으로는 당기지 않는다.
            prev_end = max(a, 0.06) - MIN_PAUSE
            ref = [e - s for s, e in orig]
            for text, (os_, oe), ph in zip(line.phrases, orig, line_audio(line, voice, ref)):
                target = voiced_rms_db(mic[int(os_ * SR): int(oe * SR)])
                body = len(ph) / SR - 2 * PAD
                rate = float(np.clip(body / (oe - os_), TEMPO_MIN, TEMPO_MAX))
                ph = tempo(ph, rate)
                ph *= 10 ** ((target - voiced_rms_db(ph)) / 20)
                fit = body / rate
                # IMPORTANT: 화면 받아쓰기는 말이 끝난 뒤에 글자를 띄운다. 구절 끝이 원래보다 늦으면
                # 글자가 말보다 먼저 보이므로, 긴 구절은 끝을 맞추고 앞 구절과의 쉼만큼 당긴다.
                begin = os_ if fit <= oe - os_ else max(oe - fit, prev_end + MIN_PAUSE)
                start = begin - PAD
                p = Placed(text, (os_, oe), begin, fit, rate)
                if begin + fit - oe > 0.05:
                    p.notes.append(f"원래보다 {begin + fit - oe:.2f}s 늦게 끝남")
                prev_end = begin + fit
                report.append(p)
                k = int(start * SR)
                end = min(len(out), k + len(ph))
                out[k:end] += ph[: end - k, None]
    n = len(out)
    fade = int(min(0.04, clip / 4) * SR)
    out[:fade] *= np.linspace(0, 1, fade)[:, None]
    out[n - fade:] *= np.linspace(1, 0, fade)[:, None]
    want = int(round(segment_durations()[i] * SR))
    out = np.concatenate([out, np.zeros((max(0, want - n), 2), np.float32)])[:want]
    return out


# ---------------------------------------------------------------- 그림

def badge_png() -> Path:
    img = Image.new("RGBA", (render.W, render.H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = render.font(28, 700)
    tw = d.textlength(BADGE, font=f)
    x1 = render.W - 80
    x0 = x1 - tw - 64
    y0, y1 = 56, 106
    d.rounded_rectangle((x0, y0, x1, y1), 25, fill=(*render.NOTE_BG, 255))
    # 녹음 표시 점: 실제 녹음이 아니라 덧입힌 소리라는 뜻으로 속을 비운다.
    d.ellipse((x0 + 20, y0 + 17, x0 + 36, y0 + 33), outline=(*render.NOTE_INK, 255), width=3)
    d.text((x0 + 46, y0 + 9), BADGE, font=f, fill=(*render.NOTE_INK, 255))
    out = WORK / "badge.png"
    img.save(out)
    return out


def mux(picture_ss: float, dur: float, dialog: np.ndarray, out: Path, badge: bool,
        music: Path = MUSIC) -> None:
    WORK.mkdir(parents=True, exist_ok=True)
    dia = WORK / f"{out.stem}-dialog.wav"
    write_wav(dia, dialog)
    vf = "[0:v]null[v]"
    inputs = ["-ss", f"{picture_ss:.3f}", "-t", f"{dur:.3f}", "-i", str(PICTURE)]
    if badge:
        inputs += ["-i", str(badge_png())]
        vf = "[0:v][3:v]overlay=0:0,format=yuv420p[v]"
    out.parent.mkdir(parents=True, exist_ok=True)
    run(["ffmpeg", "-v", "error", "-y", *inputs[:6],
         "-i", str(dia), "-ss", f"{picture_ss:.3f}", "-t", f"{dur:.3f}", "-i", str(music), *inputs[6:],
         "-filter_complex",
         f"{vf};[1:a][2:a]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.89:level=false[a]",
         "-map", "[v]", "-map", "[a]", "-t", f"{dur:.3f}",
         "-c:v", "libx264", "-crf", "18", "-preset", "fast", "-c:a", "aac", "-b:a", "192k",
         "-movflags", "+faststart", str(out)])


def picture_lag() -> float:
    """그림판 화면이 원본 화면보다 늦는 시간(초). 목소리 구간의 폰 화면을 원본과 맞대어 잰다.

    IMPORTANT: render.py 의 30fps 변환으로 그림판은 원본보다 약 60ms 늦다. 원본 소리를 그대로 붙이면
    소리가 화면보다 앞선다.
    """
    rate, lags = 120, []
    for i in sorted({line.seg for line in LINES}):
        _, long_ = chapter_files(render.SHORT[i].src)
        ls, d = pieces(i)[0]
        d = min(d, 6.0) - 0.4
        crop = f"crop={render.PHONE_W}:{render.PHONE_H}:{render.PHONE_X}:{render.PHONE_Y},"
        grab = lambda path, ss, t, pre="": np.frombuffer(run([  # noqa: E731
            "ffmpeg", "-v", "error", "-ss", f"{ss:.3f}", "-t", f"{t:.3f}", "-i", str(path),
            "-vf", f"{pre}fps={rate},scale=36:80,format=gray", "-f", "rawvideo", "-"]).stdout,
            np.uint8).reshape(-1, 36 * 80).astype(np.float32)
        pic = grab(PICTURE, segment_times()[i] + 0.2, d, crop)
        src = grab(long_, ls + 0.2 - 0.25, d + 0.5)
        errs = np.array([np.mean(np.abs(src[k: k + len(pic)] - pic)) for k in range(len(src) - len(pic) + 1)])
        lags.append(0.25 - int(np.argmin(errs)) / rate)
    lag = float(np.median(lags))
    logger.info("picture lag {:.3f}s (per segment {})", lag, [round(x, 3) for x in lags])
    if not 0 <= lag < 0.2:
        raise VoiceoverError(f"unexpected picture lag {lag:.3f}s")
    return lag


def music_bed(dialog: Path, total: float) -> Path:
    """v3 와 같은 곡·설정으로 음악을 깔되, 줄이는 구간은 새 대사 트랙에서 다시 찾는다.

    IMPORTANT: v3 음악은 그림판 소리에서 말 구간을 찾았는데, 그 소리가 화면보다 0.4~0.8초 앞서 있었다.
    """
    import mix_bgm
    mix_bgm.PICTURE = dialog
    chain = mix_bgm.music_chain(MUSIC_SRC, total, total)
    out = WORK / "v4-music.wav"
    run(["ffmpeg", "-v", "error", "-y", "-i", str(dialog), "-i", str(MUSIC_SRC), "-i", str(MUSIC_SRC),
         "-filter_complex", chain, "-map", "[m]", "-t", f"{total:.3f}", str(out)])
    return out


# ---------------------------------------------------------------- 명령

def candidates() -> None:
    i = 5
    t0 = segment_times()[i]
    seg = render.SHORT[i]
    dur = segment_durations()[i]
    out_dir = OUT / "candidates"
    lines = ["# 목소리 후보 — 계란 등록 구간", "",
             f"90초 영상 {t0:.1f}~{t0 + dur:.1f}초. 앱 응답·띠딩은 원본 폰 재생음, 배경음악은 v3 와 같다.", ""]
    mux(t0, dur, segment_audio(i, None, []), out_dir / "0-원본.mp4", badge=False)
    for v in VOICES:
        report: list[Placed] = []
        mux(t0, dur, segment_audio(i, v, report), out_dir / f"{v.key}-{v.name}.mp4", badge=True)
        lines.append(f"## {v.key} · {v.label}")
        for p in report:
            lines.append(f"- “{p.text}” 원래 {p.orig[0]:.2f}~{p.orig[1]:.2f}s → AI "
                         f"{p.start:.2f}~{p.start + p.dur:.2f}s · 속도 ×{p.tempo:.2f} "
                         f"{' '.join(p.notes)}".rstrip())
        lines.append("")
        logger.info("candidate {} done", v.key)
    (out_dir / "README.md").write_text("\n".join(lines), encoding="utf-8")


def short(voice: Voice) -> None:
    """90초 전체. 모든 구간을 폰 재생음 + AI 음성으로 다시 깐다(목소리가 없는 구간은 앱 원음만)."""
    report: list[tuple[int, Placed]] = []
    parts = []
    for i, _ in enumerate(render.SHORT):
        placed: list[Placed] = []
        parts.append(segment_audio(i, voice, placed))
        report += [(i, p) for p in placed]
    dialog = np.concatenate(parts)
    total = len(dialog) / SR
    pic = video_duration(PICTURE)
    if abs(total - pic) > 0.05:
        raise VoiceoverError(f"dialog {total:.3f}s != picture {pic:.3f}s")
    lag = int(round(picture_lag() * SR))
    dialog = np.concatenate([np.zeros((lag, 2), np.float32), dialog])[: len(dialog)]
    dia = WORK / "v4-dialog.wav"
    write_wav(dia, dialog)
    out = OUT / f"today-meal-90s-v4-ai-voice-{voice.name.lower()}.mp4"
    mux(0.0, pic, dialog, out, badge=True, music=music_bed(dia, pic))
    starts = segment_times()
    lines = [f"# 90초 · AI 후시 녹음 ({voice.label})", "",
             f"`{out.name}` — v3 그림·배경음악 그대로, 사용자 목소리만 Gemini TTS({TTS_MODEL}, {voice.name}).",
             "앱 응답·띠딩은 원본 녹화의 폰 재생음. 시각은 90초 영상 기준.", ""]
    for i, p in report:
        t = starts[i]
        lines.append(f"- {t + p.orig[0]:5.2f}s “{p.text}” 원래 {t + p.orig[0]:.2f}~{t + p.orig[1]:.2f} → AI "
                     f"{t + p.start:.2f}~{t + p.start + p.dur:.2f} · 속도 ×{p.tempo:.2f} {' '.join(p.notes)}".rstrip())
    (OUT / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    logger.info("saved {}", out)


def main() -> None:
    which = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        if which == "candidates":
            candidates()
            return
        if which == "short":
            key = sys.argv[2] if len(sys.argv) > 2 else "B"
            short(next(v for v in VOICES if v.key == key))
            return
    except VoiceoverError as e:
        logger.error("voiceover failed: {}", e)
        raise SystemExit(1) from e
    raise SystemExit("usage: voiceover.py candidates | short [A|B|C]")


if __name__ == "__main__":
    main()
