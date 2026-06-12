#!/bin/bash
set -e

CONTAINER_NAME="sub2api-admin-mcp"
IMAGE_NAME="sub2api-admin-mcp:latest"
NETWORK="sub2api-network"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCP_DIR="${MCP_DIR:-$SCRIPT_DIR}"
REPO_ROOT="${REPO_ROOT:-$(cd "$MCP_DIR/.." && pwd)}"
ENV_FILE="${MCP_ENV_FILE:-$MCP_DIR/.env}"
STATE_FILE="${PATROL_STATE_FILE_HOST:-$MCP_DIR/patrol_state.json}"

if [ -f "$ENV_FILE" ]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

: "${SUB2API_BASE:=http://sub2api:8080/api/v1}"
: "${MCP_PORT:=8765}"
: "${PATROL_STATE_FILE:=/data/patrol_state.json}"
: "${TZ:=Asia/Shanghai}"

if [ -z "${SUB2API_ADMIN_TOKEN:-}" ]; then
  echo "SUB2API_ADMIN_TOKEN is required. Create $ENV_FILE from .env.example." >&2
  exit 2
fi

if [ ! -f "$STATE_FILE" ]; then
  printf '{"accounts":{},"last_daily_report":null,"reported_slow":{},"handled_ids":[]}\n' > "$STATE_FILE"
fi

echo "Building image..."
# Keep the MCP image build scoped to the MCP owner. On legacy Docker builders,
# using the full repository context for --target mcp can stall before it reaches
# the tiny Python stage, even though the image only needs this directory.
printf '%s\n' \
  'FROM python:3.12-slim' \
  'WORKDIR /app' \
  'COPY requirements.txt .' \
  'RUN pip install --no-cache-dir -r requirements.txt' \
  'COPY sub2api-admin-mcp.py .' \
  'EXPOSE 8765' \
  'CMD ["python", "sub2api-admin-mcp.py"]' \
  | sudo docker build -t "$IMAGE_NAME" -f - "$MCP_DIR"

echo "Stopping existing container (if any)..."
sudo docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

echo "Starting container..."
# nginx proxies /mcp/ to host loopback, so keep the MCP port host-bound.
sudo docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  --network "$NETWORK" \
  -p "127.0.0.1:${MCP_PORT}:${MCP_PORT}" \
  -v "$STATE_FILE:$PATROL_STATE_FILE" \
  -e SUB2API_BASE="$SUB2API_BASE" \
  -e SUB2API_ADMIN_TOKEN="$SUB2API_ADMIN_TOKEN" \
  -e MCP_AUTH_TOKEN="${MCP_AUTH_TOKEN:-}" \
  -e MCP_PORT="$MCP_PORT" \
  -e PATROL_STATE_FILE="$PATROL_STATE_FILE" \
  -e TZ="$TZ" \
  "$IMAGE_NAME"

echo "Waiting for health..."
sleep 3
sudo docker logs "$CONTAINER_NAME" --tail 10
echo ""
echo "Testing health endpoint..."
sudo docker exec "$CONTAINER_NAME" python -c "import urllib.request; r=urllib.request.urlopen('http://localhost:8765/health', timeout=3); print(r.read().decode())"
echo "Done."
