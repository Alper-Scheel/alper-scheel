# syntax=docker/dockerfile:1.7
#
# AdLuna Platform API — Container-Image
#
# Multi-Stage:
#   1) builder  → pip install in venv
#   2) runtime  → schlankes Image mit venv
#
# Entrypoint startet erst `alembic upgrade head` (Migrations), dann uvicorn.

FROM python:3.12-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        libffi-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY requirements.txt ./
RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip \
    && /opt/venv/bin/pip install -r requirements.txt


# ---------- Runtime ----------
FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    LICENSE_SERVER_DB_PATH=/data/license.db

RUN apt-get update && apt-get install -y --no-install-recommends \
        tini \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /usr/sbin/nologin --uid 10001 adluna

COPY --from=builder /opt/venv /opt/venv

WORKDIR /app
COPY --chown=adluna:adluna alembic.ini ./alembic.ini
COPY --chown=adluna:adluna alembic ./alembic
COPY --chown=adluna:adluna app ./app
COPY --chown=adluna:adluna seed.py ./seed.py

RUN mkdir -p /data && chown adluna:adluna /data
VOLUME ["/data"]

USER adluna
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import httpx,sys; r=httpx.get('http://127.0.0.1:8080/health',timeout=3); sys.exit(0 if r.status_code==200 else 1)"

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sh", "-c", "alembic upgrade head && python -m seed && uvicorn app.main:app --host 0.0.0.0 --port 8080 --workers 2 --proxy-headers --forwarded-allow-ips='*'"]
