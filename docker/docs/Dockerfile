# syntax=docker/dockerfile:1
#
# Static handbook site. MkDocs builds the HTML; nginx serves it.
#   docker build -f docker/docs/Dockerfile -t ai-app-docs:latest .
#   kind load docker-image ai-app-docs:latest
#   kubectl apply -k deployment/k8s/ai_app

FROM python:3.14-slim-bookworm AS build

WORKDIR /src
RUN pip install --no-cache-dir mkdocs

COPY mkdocs.yml ./
COPY docs ./docs
COPY setup.md ./setup.md
COPY tool-installation.md ./tool-installation.md
COPY ai_app/setup.md ai_app/requirements.md ./ai_app/
RUN mkdocs build

FROM nginx:1.28-alpine AS docs

COPY --from=build /src/site /usr/share/nginx/html
EXPOSE 80
