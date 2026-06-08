#!/bin/sh
# Build and deploy the server-170 runtime image from the canonical Git source.
set -eu

APP_ROOT="${APP_ROOT:-/srv/sub2api}"
SOURCE_REF="${SOURCE_REF:-origin/integration/upstream-rebase}"
IMAGE_TAG="${SUB2API_IMAGE:-sub2api:integration}"
DOCKERFILE="${DOCKERFILE:-Dockerfile}"
GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
GOSUMDB="${GOSUMDB:-sum.golang.google.cn}"
CONTAINER_NAME="${CONTAINER_NAME:-sub2api}"
NETWORK_NAME="${SUB2API_NETWORK:-sub2api-network}"
DATA_DIR="${SUB2API_DATA_DIR:-$APP_ROOT/deploy/data}"

cd "$APP_ROOT"

git fetch origin
git checkout -B integration/upstream-rebase "$SOURCE_REF"

COMMIT="$(git rev-parse --short HEAD)"

sudo docker build \
  -f "$DOCKERFILE" \
  -t "$IMAGE_TAG" \
  --build-arg GOPROXY="$GOPROXY" \
  --build-arg GOSUMDB="$GOSUMDB" \
  --build-arg COMMIT="$COMMIT" \
  .

cd "$APP_ROOT/deploy"

if command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
elif sudo docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
else
  COMPOSE=""
fi

if [ -n "$COMPOSE" ]; then
  SUB2API_IMAGE="$IMAGE_TAG" $COMPOSE -f docker-compose.yml up -d --no-deps sub2api
else
  TMP_ENV="$(mktemp)"
  PREVIOUS_CONTAINER="${CONTAINER_NAME}.previous"
  trap 'rm -f "$TMP_ENV"' EXIT

  if sudo docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    sudo docker inspect "$CONTAINER_NAME" --format '{{range .Config.Env}}{{println .}}{{end}}' > "$TMP_ENV"
  elif [ -f "$APP_ROOT/deploy/.env" ]; then
    cp "$APP_ROOT/deploy/.env" "$TMP_ENV"
  else
    echo "No compose command, current container, or deploy/.env found for docker run fallback." >&2
    exit 2
  fi

  HOST_PORT="$(grep '^SERVER_PORT=' "$TMP_ENV" | tail -n 1 | cut -d= -f2-)"
  BIND_HOST="$(grep '^BIND_HOST=' "$TMP_ENV" | tail -n 1 | cut -d= -f2-)"
  HOST_PORT="${HOST_PORT:-8080}"
  BIND_HOST="${BIND_HOST:-0.0.0.0}"

  sudo docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 || sudo docker network create "$NETWORK_NAME" >/dev/null
  mkdir -p "$DATA_DIR"
  sudo docker rm -f "$PREVIOUS_CONTAINER" >/dev/null 2>&1 || true

  if sudo docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    sudo docker stop "$CONTAINER_NAME" >/dev/null
    sudo docker rename "$CONTAINER_NAME" "$PREVIOUS_CONTAINER"
  fi

  if ! sudo docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    --network "$NETWORK_NAME" \
    --ulimit nofile=100000:100000 \
    -p "$BIND_HOST:$HOST_PORT:8080" \
    -v "$DATA_DIR:/app/data" \
    --env-file "$TMP_ENV" \
    "$IMAGE_TAG"; then
    sudo docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    if sudo docker inspect "$PREVIOUS_CONTAINER" >/dev/null 2>&1; then
      sudo docker rename "$PREVIOUS_CONTAINER" "$CONTAINER_NAME"
      sudo docker start "$CONTAINER_NAME" >/dev/null
    fi
    exit 1
  fi
fi

sleep 8
sudo docker inspect sub2api --format 'image={{.Config.Image}} started={{.State.StartedAt}}'
if ! curl -fsS http://127.0.0.1:8080/health; then
  if [ "${PREVIOUS_CONTAINER:-}" ] && sudo docker inspect "$PREVIOUS_CONTAINER" >/dev/null 2>&1; then
    sudo docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    sudo docker rename "$PREVIOUS_CONTAINER" "$CONTAINER_NAME"
    sudo docker start "$CONTAINER_NAME" >/dev/null
  fi
  exit 1
fi

if [ "${PREVIOUS_CONTAINER:-}" ]; then
  sudo docker rm -f "$PREVIOUS_CONTAINER" >/dev/null 2>&1 || true
fi
