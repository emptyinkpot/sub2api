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
NGINX_SITE="${SUB2API_NGINX_SITE:-/etc/nginx/sites-enabled/sub2api.tengokukk.com}"
NGINX_SNIPPET_SRC="${SUB2API_NGINX_SNIPPET_SRC:-$APP_ROOT/deploy/ops/nginx/sub2api-gateway-locations.conf}"
NGINX_SNIPPET_DST="${SUB2API_NGINX_SNIPPET_DST:-/etc/nginx/snippets/sub2api-gateway-locations.conf}"

sync_nginx_gateway_routes() {
  if [ ! -f "$NGINX_SNIPPET_SRC" ]; then
    echo "Missing nginx gateway snippet: $NGINX_SNIPPET_SRC" >&2
    exit 2
  fi
  if ! sudo test -f "$NGINX_SITE"; then
    echo "Missing nginx site config: $NGINX_SITE" >&2
    exit 2
  fi

  sudo install -d -m 0755 "$(dirname "$NGINX_SNIPPET_DST")"
  sudo install -m 0644 "$NGINX_SNIPPET_SRC" "$NGINX_SNIPPET_DST"

  if ! sudo grep -Fq "include $NGINX_SNIPPET_DST;" "$NGINX_SITE"; then
    TMP_NGINX_SITE="$(mktemp)"
    NGINX_BACKUP="$NGINX_SITE.bak.$(date -u +%Y%m%d%H%M%S)"
    if ! sudo awk -v inc="    include $NGINX_SNIPPET_DST;" '
      BEGIN { inserted = 0 }
      /^[[:space:]]*location[[:space:]]+\/[[:space:]]*\{/ && inserted == 0 {
        print inc
        print ""
        inserted = 1
      }
      { print }
      END { if (inserted == 0) exit 10 }
    ' "$NGINX_SITE" > "$TMP_NGINX_SITE"; then
      rm -f "$TMP_NGINX_SITE"
      echo "Could not insert nginx gateway snippet into $NGINX_SITE" >&2
      exit 2
    fi

    sudo cp "$NGINX_SITE" "$NGINX_BACKUP"
    sudo install -m 0644 "$TMP_NGINX_SITE" "$NGINX_SITE"
    rm -f "$TMP_NGINX_SITE"

    if ! sudo nginx -t; then
      sudo cp "$NGINX_BACKUP" "$NGINX_SITE"
      sudo nginx -t >/dev/null 2>&1 || true
      echo "nginx validation failed; restored $NGINX_BACKUP" >&2
      exit 1
    fi
  else
    sudo nginx -t
  fi

  sudo systemctl reload nginx
}

cd "$APP_ROOT"

git fetch origin
git checkout -B integration/upstream-rebase "$SOURCE_REF"

COMMIT="$(git rev-parse --short HEAD)"
sync_nginx_gateway_routes

sudo docker build \
  --target app \
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
