#!/bin/sh
# 클라우드 배포용 진입점. 스키마를 맞추고 사전·레시피를 넣은 뒤 서버를 띄운다.
#
# 로컬 `docker-compose.yml` 은 이 파일을 쓰지 않는다 — 거기서는 compose 의 command 가
# 같은 일을 한다. 배포 플랫폼은 compose 를 읽지 않으므로 한 곳에 모아 둔다.
#
# WARNING: 플랫폼이 주는 포트(`$PORT`)로 바인딩해야 한다. 8000 에 고정하면 라우터가
# 붙지 못해 502 가 난다.
set -e

echo "[start] migrating"
alembic upgrade head

# 시드는 멱등이다. 재배포마다 돌아도 중복이 생기지 않는다.
echo "[start] seeding"
python -m app.core.seed

PORT="${PORT:-8000}"
echo "[start] serving on 0.0.0.0:${PORT}"
exec gunicorn app.main:app \
  --worker-class uvicorn.workers.UvicornWorker \
  --workers "${WEB_CONCURRENCY:-2}" \
  --bind "0.0.0.0:${PORT}" \
  --timeout "${WEB_TIMEOUT:-120}" \
  --access-logfile - \
  --error-logfile -
