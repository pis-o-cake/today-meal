#!/bin/sh
# 시연 영상 챕터 녹화.
#   sh record.sh start <이름>   예) sh record.sh start long/02-등록  → long/02-등록-take01.mp4
#   대본: script.md
#   sh record.sh stop
#
# 결과 <이름>.mp4 트랙
#   a:0  목소리 + 앱 음성 믹스. 기본 트랙
#   a:1  헤드셋 잡음 제거본
#   a:2  폰 재생음 — 앱 TTS·신호음 원음
#   a:3  헤드셋 원본
#   a:4  맥북 마이크(예비) — 헤드셋이 끊겼을 때 쓴다
#
# IMPORTANT: 폰 마이크를 scrcpy로 함께 잡으면 앱의 호출어 인식("헤이 키친")이 막힌다
# (mic, mic-voice-recognition 둘 다 확인). 그래서 목소리는 맥 마이크로 받는다.
# IMPORTANT: 백그라운드 scrcpy는 SIGINT가 무시되므로 SIGTERM으로 끝낸다. kill -9 금지(mp4 손상).
set -eu

export PATH="$HOME/Library/Android/sdk/platform-tools:/opt/homebrew/bin:$PATH"
ROOT="$(cd "$(dirname "$0")" && pwd)"
SERIAL="${SERIAL:-R95R9013RFX}"
# 마이크는 헤드셋(G733) 하나만 쓴다. 앱 음성은 폰 재생음에서 받는다.
# WARNING: 아이폰 연속성 마이크는 도중에 무음으로 끊겼고, 마이크 둘을 동시에 잡으면 소리가 빠졌다.
MAC_MIC="${MAC_MIC:-G733 Gaming Headset}"
STATE="$ROOT/.recording"
# IMPORTANT: 마이크가 폰 스피커의 앱 음성까지 받는다. 앱 원음과 그대로 섞으면 두 번 들린다.
# 앱 음성이 나오는 동안 마이크를 눌러(sidechaincompress) 앱 소리는 원음 트랙만 남긴다.
# 가벼운 잡음 제거. 저역 험만 자르고 잡음을 약하게 걷은 뒤 말소리 크기를 고르게 올린다.
# WARNING: 게이트(agate)와 강한 afftdn 은 작은 말소리까지 지워 소리가 통째로 사라졌다. 쓰지 않는다.
DENOISE="highpass=f=90,afftdn=nr=12:nf=-50:tn=1,dynaudnorm=f=250:g=15"

now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }

# 파일에 첫 바이트가 쓰인 시각. 두 녹화의 시작점을 맞추는 기준이다.
first_write() {
  # 마이크가 죽어 있으면 파일이 비어 있다. 무한 대기하지 않고 5초 뒤 현재 시각을 쓴다.
  i=0
  while [ ! -s "$1" ] && [ $i -lt 250 ]; do sleep 0.02; i=$((i + 1)); done
  now
}

start() {
  [ ! -e "$STATE" ] || { echo "already recording: $(cat "$STATE")"; exit 1; }
  # 원본을 덮어쓰지 않는다. 테이크 번호를 올려 새 파일로 찍는다.
  n=1
  base="$ROOT/${1}-take01"
  while [ -e "$base.mp4" ] || [ -e "$base.raw" ]; do
    n=$((n + 1))
    base="$ROOT/${1}-take$(printf %02d "$n")"
  done
  raw="$base.raw"
  mkdir -p "$raw"
  echo "$base" > "$STATE"

  # IMPORTANT: 마이크를 둘 이상 동시에 잡으면 중간중간 소리가 빠져 영상보다 15초 짧아졌다.
  # 하나만 잡고, 빠진 구간은 벽시계 기준으로 무음을 채워 길이를 영상과 맞춘다.
  ffmpeg -v error -nostdin -use_wallclock_as_timestamps 1 -f avfoundation -i ":$MAC_MIC" \
    -af "aresample=async=1:first_pts=0" -c:a pcm_s16le "$raw/mic.wav" &
  echo $! > "$raw/mic.pid"
  scrcpy -s "$SERIAL" --no-window --show-touches --stay-awake \
    --audio-source=playback --audio-dup --audio-codec=aac --audio-bit-rate=192K \
    --video-bit-rate=16M --max-fps=60 \
    --record="$raw/phone.mp4" >"$raw/scrcpy.log" 2>&1 &
  echo $! > "$raw/scrcpy.pid"

  t_mic="$(first_write "$raw/mic.wav")"
  t_vid="$(first_write "$raw/phone.mp4")"
  echo "$t_mic $t_vid" > "$raw/sync"
  echo "REC -> $base.mp4"
  # IMPORTANT: 호출한 셸이 끝나면 하위 녹화도 정리되므로 녹화가 끝날 때까지 붙잡는다.
  # 이 명령은 백그라운드로 실행하고, 끝낼 때는 다른 셸에서 stop을 부른다.
  wait
}

# 실제로 디코딩한 길이(초). ADTS 는 헤더로 길이를 알 수 없어 끝까지 읽는다.
dur() {
  ffmpeg -i "$1" -map 0:a:0? -map 0:v:0? -f null - 2>&1 | grep -o "time=[0-9:.]*" | tail -1 \
    | cut -d= -f2 | awk -F: '{ printf "%.3f", $1 * 3600 + $2 * 60 + $3 }'
}

# IMPORTANT: 시작이 아니라 **끝**에 맞춘다. 세 녹음은 stop 에서 같은 순간에 끊기지만,
# 시작 시각은 ADTS 가 몇 초씩 모아 쓰는 탓에 파일이 늦게 생겨 수 초씩 틀렸다.
tail_offset() {
  awk -v a="$(dur "$1")" -v v="$(dur "$2")" 'BEGIN { d = a - v; printf "%.3f", (d > 0 ? d : 0) }'
}

mux() {
  set -- "$1" "$(tail_offset "$1/mic.wav" "$1/phone.mp4")" "$3"
  bak="$([ -s "$1/backup.aac" ] && tail_offset "$1/backup.aac" "$1/phone.mp4" || true)"
  if [ -n "$bak" ] && [ -s "$1/backup.aac" ]; then
    ffmpeg -v error -y -i "$1/phone.mp4" -ss "$2" -i "$1/mic.wav" -ss "$bak" -i "$1/backup.aac" \
      -filter_complex "[1:a]$DENOISE,asplit[clean][voice];[0:a]asplit=3[app][appmix][key];[voice][key]sidechaincompress=threshold=0.015:ratio=20:attack=5:release=350:makeup=1[ducked];[ducked][appmix]amix=inputs=2:duration=first:normalize=0[main];[2:a]$DENOISE[backup]" \
      -map 0:v -map "[main]" -map "[clean]" -map "[app]" -map 1:a -map "[backup]" \
      -c:v copy -c:a aac -b:a 192k \
      -metadata:s:a:0 title="voice+app-mix" -metadata:s:a:1 title="headset-denoised" \
      -metadata:s:a:2 title="phone-playback" -metadata:s:a:3 title="headset-raw" \
      -metadata:s:a:4 title="macbook-backup" \
      -disposition:a:0 default -disposition:a:1 0 -disposition:a:2 0 -disposition:a:3 0 \
      -disposition:a:4 0 \
      "$3"
    return
  fi
  ffmpeg -v error -y -i "$1/phone.mp4" -ss "$2" -i "$1/mic.wav" \
    -filter_complex "[1:a]$DENOISE,asplit[clean][voice];[0:a]asplit=3[app][appmix][key];[voice][key]sidechaincompress=threshold=0.015:ratio=20:attack=5:release=350:makeup=1[ducked];[ducked][appmix]amix=inputs=2:duration=first:normalize=0[main]" \
    -map 0:v -map "[main]" -map "[clean]" -map "[app]" -map 1:a -c:v copy -c:a aac -b:a 192k \
    -metadata:s:a:0 title="voice+app-mix" -metadata:s:a:1 title="mic-denoised" \
    -metadata:s:a:2 title="phone-playback" -metadata:s:a:3 title="mic-raw" \
    -disposition:a:0 default -disposition:a:1 0 -disposition:a:2 0 -disposition:a:3 0 \
    "$3"
}

# 이미 합친 챕터를 원본에서 다시 만든다. 예) sh record.sh remux long/01-start-account
remux() {
  base="$ROOT/$1"
  mux "$base.raw" "" "$base.mp4"
  echo "REMUXED $base.mp4"
}

# 녹음 중 마이크가 살아 있는지 본다. 아이폰 마이크가 도중에 무음으로 끊긴 적이 있다.
check() {
  [ -e "$STATE" ] || { echo "no recording"; exit 0; }
  raw="$(cat "$STATE").raw"
  ffmpeg -sseof -8 -i "$raw/mic.wav" -af astats=metadata=0 -f null - 2>&1 \
    | grep "RMS level dB" | tail -1 | awk '{print "mic", $NF}'
}

stop() {
  [ -e "$STATE" ] || { echo "no recording"; exit 0; }
  base="$(cat "$STATE")"
  raw="$base.raw"
  kill -TERM "$(cat "$raw/scrcpy.pid")" 2>/dev/null || true
  kill -INT "$(cat "$raw/mic.pid")" 2>/dev/null || true
  while kill -0 "$(cat "$raw/scrcpy.pid")" 2>/dev/null || kill -0 "$(cat "$raw/mic.pid")" 2>/dev/null; do
    sleep 0.3
  done
  rm -f "$STATE"

  mux "$raw" "" "$base.mp4"

  echo "SAVED $base.mp4"
  ffprobe -v error -show_entries format=duration -of default=nw=1 "$base.mp4"
  for t in 0 1; do
    printf "a:%s " "$t"
    ffmpeg -i "$base.mp4" -map 0:a:$t? -af volumedetect -f null - 2>&1 | grep "mean_volume" | awk '{print $(NF-1), $NF}'
  done
}

case "${1:-}" in
  start) start "${2:?name required}" ;;
  stop) stop ;;
  remux) remux "${2:?name required}" ;;
  check) check ;;
  *) echo "usage: $0 start <name> | stop | remux <name>"; exit 1 ;;
esac
