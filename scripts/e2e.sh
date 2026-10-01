#!/bin/sh
# 실기기 통합 검증. 검증용 서버를 띄우고 `app/integration_test` 를 연결된 기기에서 돌린다.
#
# 시연 DB 와 모델 호출을 건드리지 않는다.
#   - 별도 DB(`today_meal_e2e`)를 쓴다. 기본 가구의 재고를 테스트가 비우고 채운다.
#   - 모델 키를 비워 **가짜 게이트웨이**로 뜬다. 비용이 0 이고 결과가 흔들리지 않는다.
#
# WARNING: 무선 adb 에서는 Dart VM service 연결이 끊긴다. **USB 로 연결한다.**
#
# 사용법
#   sh scripts/e2e.sh                     # 연결된 기기 하나에서 전체 실행
#   sh scripts/e2e.sh <device-id>         # 기기를 지정해 실행
#   E2E_ONLY=c_menu_cook sh scripts/e2e.sh  # 스위트 하나만
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
device=$1
port=${E2E_PORT:-8001}
db=${E2E_DB:-today_meal_e2e}

if ! command -v flutter >/dev/null 2>&1; then
  echo "e2e: flutter is not on PATH" >&2
  echo "  macOS/Linux : export PATH=\"\$HOME/dev/flutter/bin:\$PATH\"" >&2
  exit 1
fi

# 기기가 앱에서 서버를 볼 수 있어야 한다. localhost 는 기기의 자기 자신이다.
host=${E2E_HOST:-$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')}
if [ -z "$host" ]; then
  echo "e2e: could not detect the LAN address; set E2E_HOST" >&2
  exit 1
fi

echo "== 검증용 DB($db) 준비 =="
(
  cd "$root/server"
  # 이미 있으면 그대로 쓴다. 스키마만 맞춘다.
  TODAY_MEAL_DB_NAME="$db" poetry run python - <<'PY' || true
import asyncio

import asyncpg

from app.core.config import get_settings


async def main() -> None:
    settings = get_settings()
    admin = await asyncpg.connect(
        host=settings.db_host,
        port=settings.db_port,
        user=settings.db_user,
        password=settings.db_password,
        database="postgres",
    )
    try:
        await admin.execute(f'create database "{settings.db_name}"')
        print(f"created {settings.db_name}")
    except asyncpg.DuplicateDatabaseError:
        print(f"{settings.db_name} already exists")
    finally:
        await admin.close()


asyncio.run(main())
PY
  TODAY_MEAL_DB_NAME="$db" poetry run alembic upgrade head
  TODAY_MEAL_DB_NAME="$db" poetry run python -m app.core.seed
)

echo "== 검증용 서버 기동 (가짜 모델, :$port) =="
(
  cd "$root/server"
  TODAY_MEAL_ENV=dev \
  TODAY_MEAL_LOG_LEVEL=INFO \
  TODAY_MEAL_DB_NAME="$db" \
  TODAY_MEAL_GEMINI_API_KEY= \
    poetry run uvicorn app.main:app --host 0.0.0.0 --port "$port" \
    > "$root/.e2e-server.log" 2>&1 &
  echo $! > "$root/.e2e-server.pid"
)
trap 'kill "$(cat "$root/.e2e-server.pid" 2>/dev/null)" 2>/dev/null || true' EXIT INT TERM

# 뜰 때까지 기다린다. 가짜 모델인지도 확인한다 — 실제 키로 떴으면 비용이 든다.
ready=0
i=0
while [ "$i" -lt 30 ]; do
  if curl -fsS "http://127.0.0.1:$port/health" 2>/dev/null | grep -q '"llm_fake":true'; then
    ready=1
    break
  fi
  i=$((i + 1))
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  echo "e2e: verification server did not come up as fake; see .e2e-server.log" >&2
  exit 1
fi
echo "서버 준비됨: http://$host:$port/"

target_args=""
if [ -n "$device" ]; then
  target_args="-d $device"
fi

status=0
for suite in "$root"/app/integration_test/*_test.dart; do
  name=$(basename "$suite" .dart)
  if [ -n "$E2E_ONLY" ] && [ "$name" != "$E2E_ONLY" ]; then
    continue
  fi
  echo "== $name =="
  # shellcheck disable=SC2086
  ( cd "$root/app" && flutter test "$suite" $target_args \
      --dart-define=E2E_BASE_URL="http://$host:$port/" ) || status=1
done

if [ "$status" -ne 0 ]; then
  echo "e2e: some suites failed" >&2
  exit 1
fi
echo "e2e: done"
