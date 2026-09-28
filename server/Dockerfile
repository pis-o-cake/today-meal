# 빌드: uv 로 의존성만 먼저 설치해 레이어 캐시를 살린다.
FROM python:3.12-slim AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_LINK_MODE=copy

RUN pip install --no-cache-dir uv

WORKDIR /build
COPY pyproject.toml ./
RUN uv pip install --system --no-cache -r <(uv pip compile pyproject.toml --quiet -o -)

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

USER app
EXPOSE 8000

# Gunicorn + Uvicorn worker. 워커 수는 배포에서 조정한다.
CMD ["gunicorn", "app.main:app", \
     "--worker-class", "uvicorn.workers.UvicornWorker", \
     "--workers", "2", \
     "--bind", "0.0.0.0:8000", \
     "--access-logfile", "-", \
     "--error-logfile", "-"]
