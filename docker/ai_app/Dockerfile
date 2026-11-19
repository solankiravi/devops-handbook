# syntax=docker/dockerfile:1
#
# Three images for ai_app, one container per tier. Build with --target:
#   docker build -f docker/ai_app/Dockerfile --target backend -t ai-app-backend:latest .
#   docker build -f docker/ai_app/Dockerfile --target frontend -t ai-app-frontend:latest .
#   docker build -f docker/ai_app/Dockerfile --target postgres -t ai-app-postgres:latest .
# Load them into kind, then apply deployment/k8s/ai_app.

FROM python:3.14-slim-bookworm AS backend

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/app/.venv \
    PATH="/app/.venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN useradd --create-home --uid 10001 appuser

COPY ai_app/backend/app/pyproject.toml ai_app/backend/app/uv.lock ai_app/backend/app/README.md ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project

COPY ai_app/backend/app/src ./src
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev \
    && chown -R appuser:appuser /app

USER appuser
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]


FROM node:24-alpine AS frontend-build

WORKDIR /src
COPY ai_app/frontend/app/package.json ai_app/frontend/app/package-lock.json ./
RUN npm ci
COPY ai_app/frontend/app/ ./
RUN npm run build

FROM nginx:1.28-alpine AS frontend

COPY --from=frontend-build /src/dist /usr/share/nginx/html
EXPOSE 80


FROM postgres:18-alpine AS postgres

EXPOSE 5432
