# =============================================================================
# Sub2API Multi-Stage Dockerfile
# =============================================================================
# Stage 1: MCP admin service image
# Stage 2: Build frontend
# Stage 3: Build Go backend with embedded frontend
# Stage 4: PostgreSQL client tools
# Stage 5: Shared runtime base
# Stage 6: GoReleaser prebuilt-binary image
# Stage 7: Final source-built image (default)
# =============================================================================

ARG NODE_IMAGE=node:24-alpine
ARG GOLANG_IMAGE=golang:1.26.3-alpine
ARG ALPINE_IMAGE=alpine:3.21
ARG POSTGRES_IMAGE=postgres:18-alpine
ARG PYTHON_IMAGE=python:3.12-slim
ARG GOPROXY=https://goproxy.cn,direct
ARG GOSUMDB=sum.golang.google.cn

# -----------------------------------------------------------------------------
# Stage 1: MCP Admin Service Image
# -----------------------------------------------------------------------------
FROM ${PYTHON_IMAGE} AS mcp

WORKDIR /app

COPY mcp/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY mcp/sub2api-admin-mcp.py .

EXPOSE 8765

CMD ["python", "sub2api-admin-mcp.py"]

# -----------------------------------------------------------------------------
# Stage 2: Frontend Builder
# -----------------------------------------------------------------------------
FROM ${NODE_IMAGE} AS frontend-builder

WORKDIR /app/frontend

# Install pnpm (pinned to v9 to match CI and keep builds reproducible)
RUN corepack enable && corepack prepare pnpm@9 --activate

# Install dependencies first (better caching)
COPY frontend/package.json frontend/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

# Copy frontend source and build
COPY frontend/ ./
RUN pnpm run build

# -----------------------------------------------------------------------------
# Stage 3: Backend Builder
# -----------------------------------------------------------------------------
FROM ${GOLANG_IMAGE} AS backend-builder

# Build arguments for version info (set by CI)
ARG VERSION=
ARG COMMIT=
ARG SOURCE_COMMIT=
ARG DATE
ARG GOPROXY
ARG GOSUMDB

ENV GOPROXY=${GOPROXY}
ENV GOSUMDB=${GOSUMDB}

# Install build dependencies
RUN apk add --no-cache git ca-certificates tzdata

WORKDIR /app/backend

# Copy go mod files first (better caching)
COPY backend/go.mod backend/go.sum ./
RUN go mod download

# Copy backend source first
COPY backend/ ./

# Copy frontend dist from previous stage (must be after backend copy to avoid being overwritten)
COPY --from=frontend-builder /app/backend/internal/web/dist ./internal/web/dist

# Build the binary (BuildType=release for CI builds, embed frontend)
# Version precedence: build arg VERSION > cmd/server/VERSION
RUN VERSION_VALUE="${VERSION}" && \
    if [ -z "${VERSION_VALUE}" ]; then VERSION_VALUE="$(tr -d '\r\n' < ./cmd/server/VERSION)"; fi && \
    COMMIT_VALUE="${COMMIT:-${SOURCE_COMMIT:-docker}}" && \
    DATE_VALUE="${DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}" && \
    CGO_ENABLED=0 GOOS=linux go build \
    -tags embed \
    -ldflags="-s -w -X main.Version=${VERSION_VALUE} -X main.Commit=${COMMIT_VALUE} -X main.Date=${DATE_VALUE} -X main.BuildType=release" \
    -trimpath \
    -o /app/sub2api \
    ./cmd/server

# -----------------------------------------------------------------------------
# Stage 4: PostgreSQL Client (version-matched with docker-compose)
# -----------------------------------------------------------------------------
FROM ${POSTGRES_IMAGE} AS pg-client

# -----------------------------------------------------------------------------
# Stage 5: Shared Runtime Base
# -----------------------------------------------------------------------------
FROM ${ALPINE_IMAGE} AS runtime-base

# Labels
LABEL maintainer="Wei-Shaw <github.com/Wei-Shaw>"
LABEL description="Sub2API - AI API Gateway Platform"
LABEL org.opencontainers.image.source="https://github.com/Wei-Shaw/sub2api"

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    su-exec \
    libpq \
    zstd-libs \
    lz4-libs \
    krb5-libs \
    libldap \
    libedit \
    && rm -rf /var/cache/apk/*

# Copy pg_dump and psql from the same postgres image used in docker-compose
# This ensures version consistency between backup tools and the database server
COPY --from=pg-client /usr/local/bin/pg_dump /usr/local/bin/pg_dump
COPY --from=pg-client /usr/local/bin/psql /usr/local/bin/psql
COPY --from=pg-client /usr/local/lib/libpq.so.5* /usr/local/lib/

# Create non-root user
RUN addgroup -g 1000 sub2api && \
    adduser -u 1000 -G sub2api -s /bin/sh -D sub2api

# Set working directory
WORKDIR /app

# Create data directory
RUN mkdir -p /app/data && chown sub2api:sub2api /app/data

# Copy entrypoint script (fixes volume permissions then drops to sub2api)
COPY deploy/docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

# Expose port (can be overridden by SERVER_PORT env var)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD wget -q -T 5 -O /dev/null http://localhost:${SERVER_PORT:-8080}/health || exit 1

# Run the application (entrypoint fixes /app/data ownership then execs as sub2api)
ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["/app/sub2api"]

# -----------------------------------------------------------------------------
# Stage 6: GoReleaser Runtime Image (prebuilt binary)
# -----------------------------------------------------------------------------
FROM runtime-base AS goreleaser

COPY --chown=sub2api:sub2api sub2api /app/sub2api
COPY --chown=sub2api:sub2api backend/resources /app/resources

# -----------------------------------------------------------------------------
# Stage 7: Final Runtime Image (default source build)
# -----------------------------------------------------------------------------
FROM runtime-base AS final

# Copy binary/resources with ownership to avoid extra full-layer chown copy
COPY --from=backend-builder --chown=sub2api:sub2api /app/sub2api /app/sub2api
COPY --from=backend-builder --chown=sub2api:sub2api /app/backend/resources /app/resources
