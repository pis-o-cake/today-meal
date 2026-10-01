# 빌드: uv 로 의존성만 먼저 설치해 레이어 캐시를 살린다.
FROM python:3.12-slim AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_LINK_MODE=copy

RUN pip install --no-cache-dir uv

WORKDIR /build
COPY pyproject.toml ./
# WARNING: 프로세스 치환(`<(...)`)을 쓰지 않는다. `RUN` 의 기본 셸은 `/bin/sh` 이고
# 거기에는 그 문법이 없어 빌드가 통째로 실패한다 — 파일로 한 번 떨어뜨린다.
RUN uv pip compile pyproject.toml --quiet -o requirements.txt \
    && uv pip install --system --no-cache -r requirements.txt

FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TODAY_MEAL_ENV=prod

# 비루트로 돈다.
RUN groupadd --system app && useradd --system --gid app --home /app app

COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

WORKDIR /app
COPY --chown=app:app app ./app
COPY --chown=app:app alembic ./alembic
COPY --chown=app:app alembic.ini ./
COPY --chown=app:app deploy ./deploy

USER app
EXPOSE 8000

# 스키마를 맞추고 사전을 넣은 뒤 Gunicorn + Uvicorn worker 로 띄운다.
#
# IMPORTANT: 포트를 이미지 안에 고정하지 않는다. 배포 플랫폼은 `$PORT` 로 포트를
# 지정하며, 8000 에 묶어 두면 라우터가 붙지 못해 502 가 난다. 로컬 compose 는 자기
# `command` 로 이 CMD 를 덮으므로 개발 환경은 그대로다.
CMD ["sh", "deploy/start.sh"]
