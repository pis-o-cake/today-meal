#!/bin/sh
# 온디바이스 한국어 ASR 모델을 내려받는다.
#
# 모델을 git 에 넣지 않는 이유는 인코더가 126MB 로 GitHub 의 파일당 100MB 제한을 넘기
# 때문이다. 대신 개발 환경마다 한 번 받는다.
#
# 앱에는 여전히 **번들**한다 — 시연에서 네트워크 없이 떠야 하므로 실행 시 내려받기에
# 기대지 않는다. 이 스크립트는 빌드 전 준비 단계다.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
target="$root/app/assets/asr"
base="https://huggingface.co/k2-fsa/sherpa-onnx-streaming-zipformer-korean-2024-06-16/resolve/main"

mkdir -p "$target"

for name in tokens.txt bpe.model \
            decoder-epoch-99-avg-1.int8.onnx \
            joiner-epoch-99-avg-1.int8.onnx \
            encoder-epoch-99-avg-1.int8.onnx
do
  if [ -s "$target/$name" ]; then
    echo "이미 있음: $name"
    continue
  fi
  echo "받는 중: $name"
  curl -fsSL --retry 3 -o "$target/$name" "$base/$name"
done

echo
echo "모델 준비 완료:"
du -sh "$target"
