#!/bin/sh
# 프로젝트 native 검증. server / app 중 존재하는 것만 실행한다.
#
# engsys 가 `commands.verify` 로 부르는 진입점이다. 실패하면 0 이 아닌 코드로 끝난다.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)

python3 "$root/scripts/check-repository.py"
python3 -m unittest discover -s "$root/scripts" -p 'test_*.py'

if [ -f "$root/server/pyproject.toml" ]; then
  echo "== server =="
  # 통합 테스트는 PostgreSQL 이 없으면 스스로 건너뛴다. 나머지는 DB 없이 돈다.
  ( cd "$root/server" && poetry run pytest -q && poetry run ruff check . )
fi

if [ -f "$root/app/pubspec.yaml" ]; then
  echo "== app =="
  # Windows 의 Git Bash 에서도 돌아야 한다. flutter 는 PATH 에서 찾는다.
  if ! command -v flutter >/dev/null 2>&1; then
    echo "verify: flutter is not on PATH" >&2
    echo "  macOS/Linux : export PATH=\"\$HOME/dev/flutter/bin:\$PATH\"" >&2
    echo "  Windows     : Flutter 설치 경로의 bin 을 PATH 에 넣는다" >&2
    exit 1
  fi

  ( cd "$root/app" && flutter analyze && flutter test )
fi

echo "verify: done"
