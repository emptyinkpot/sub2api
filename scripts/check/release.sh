#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_ENTRY="$(cd "$SCRIPT_DIR/.." && pwd)/check.sh"

RELEASE_BASE_URL="${SUB2API_RELEASE_BASE_URL:-${SUB2API_APP_BASE_URL:-https://sub2api.tengokukk.com}}"
CHECK_MODE="--full"
CHECK_MODE_SET=0
TIMEOUT="${SUB2API_RELEASE_TIMEOUT:-45}"
WAIT_TIMEOUT="${SUB2API_RELEASE_WAIT_TIMEOUT:-180}"
WAIT_INTERVAL="${SUB2API_RELEASE_WAIT_INTERVAL:-5}"
EXPECT_COMMIT="${SUB2API_RELEASE_EXPECT_COMMIT:-}"
REMOTE_HOST="${SUB2API_RELEASE_REMOTE_HOST:-}"
COOLIFY_RESOURCE_UUID="${SUB2API_COOLIFY_RESOURCE_UUID:-${COOLIFY_RESOURCE_UUID:-}}"
RELEASE_NETWORK="${SUB2API_RELEASE_NETWORK:-coolify}"
IMAGE="${SUB2API_RELEASE_IMAGE:-}"
REMOTE_PORT="${SUB2API_RELEASE_REMOTE_PORT:-0}"
LOCAL_PORT="${SUB2API_RELEASE_LOCAL_PORT:-0}"
KEEP_CONTAINER=0
ENDPOINT_ONLY=0
ALLOW_LOCALHOST=0
CHECK_ARGS=()
ADMIN_TOKEN=""
REMOTE_CONTAINER=""
TUNNEL_PID=""

usage() {
  cat <<'EOF'
Usage:
  scripts/check.sh --release [--full|--smoke|--audit-keys|--audit-models|--audit-upstream|--audit-routing] [options]

Release acceptance for the Coolify-deployed server image. With
--coolify-resource-uuid it resolves the Coolify env/image on the deployment
host, starts the finished image as a temporary container, and runs real HTTP
checks against that candidate. It never starts source dev servers, mocks, or
dry runs.

Examples:
  scripts/check.sh --release --remote-host rainyun --coolify-resource-uuid <uuid> --full
  scripts/check.sh --release --remote-host rainyun --coolify-resource-uuid <uuid> --image sub2api:<sha> --smoke --full
  scripts/check.sh --release --endpoint-only --base-url https://sub2api.tengokukk.com --smoke --full

Options:
  --base-url URL       Deployed app URL, default https://sub2api.tengokukk.com
  --remote-host HOST   SSH host that runs the Coolify application
  --coolify-resource-uuid UUID
                       Coolify application UUID; required for release authority
  --image IMAGE        Candidate image to run; defaults to current Coolify image
  --release-network N  Docker network for the candidate, default coolify
  --remote-port PORT   Remote loopback port for candidate HTTP; default auto
  --local-port PORT    Local loopback port for SSH tunnel; default auto
  --keep-container     Leave the temporary candidate container running
  --endpoint-only      Only check an already exposed endpoint; not release-authoritative
  --timeout SEC        Per-request timeout passed to check modules, default 45
  --wait-timeout SEC   Seconds to wait for deployed /health, default 180
  --wait-interval SEC  Poll interval while waiting for /health, default 5
  --expect-commit SHA  Wait until deployed /admin/system/version reports SHA
  --allow-localhost    Permit localhost/127.0.0.1 targets for explicit debugging
  -h, --help           Show this help

Environment:
  SUB2API_RELEASE_BASE_URL, SUB2API_APP_BASE_URL, SUB2API_RELEASE_TIMEOUT,
  SUB2API_RELEASE_WAIT_TIMEOUT, SUB2API_RELEASE_WAIT_INTERVAL,
  SUB2API_RELEASE_EXPECT_COMMIT, SUB2API_RELEASE_REMOTE_HOST,
  SUB2API_COOLIFY_RESOURCE_UUID, SUB2API_RELEASE_IMAGE,
  SUB2API_RELEASE_NETWORK, SUB2API_RELEASE_REMOTE_PORT,
  SUB2API_RELEASE_LOCAL_PORT
EOF
}

trim_slash() {
  local value="$1"
  while [ "${value%/}" != "$value" ]; do
    value="${value%/}"
  done
  printf '%s' "$value"
}

require_bin() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 2
  fi
}

quote_bash_arg() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\"\'\"\'}"
}

remote_bash() {
  local script="$1"
  shift
  local quoted=()
  local arg
  for arg in "$@"; do
    quoted+=("$(quote_bash_arg "$arg")")
  done
  if [ "${#quoted[@]}" -gt 0 ]; then
    printf '%s\n' "$script" | ssh "$REMOTE_HOST" "tr -d '\r' | bash -s -- ${quoted[*]}"
  else
    printf '%s\n' "$script" | ssh "$REMOTE_HOST" "tr -d '\r' | bash -s"
  fi
}

curl_json() {
  local method="$1"
  local url="$2"
  local token="${3:-}"
  local tmp status

  tmp="$(mktemp)"
  local args=(-sS --max-time "$TIMEOUT" -o "$tmp" -w '%{http_code}' -X "$method" -H "Accept: application/json")
  if [ -n "${HTTP_HOST:-}" ]; then
    args+=(-H "Host: $HTTP_HOST")
  fi
  if [ -n "$token" ]; then
    args+=(-H "Authorization: Bearer $token")
  fi

  if ! status="$(curl "${args[@]}" "$url")"; then
    rm -f "$tmp"
    return 1
  fi

  local text
  text="$(cat "$tmp")"
  rm -f "$tmp"
  if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
    return 1
  fi
  printf '%s' "$text"
}

resolve_remote_env_file() {
  if [ -z "$COOLIFY_RESOURCE_UUID" ]; then
    echo "--release requires --coolify-resource-uuid unless --endpoint-only is used" >&2
    exit 2
  fi
  printf '/data/coolify/applications/%s/.env' "$COOLIFY_RESOURCE_UUID"
}

resolve_current_coolify_image() {
  local env_file="$1"
  local script
  script='
set -euo pipefail
uuid="$1"
env_file="$2"
app_dir="/data/coolify/applications/$uuid"
compose_file="$app_dir/docker-compose.yaml"
sudo -n test -f "$env_file"
sudo -n test -f "$compose_file"
image="$(sudo -n docker ps --filter "name=${uuid}" --format "{{.Image}}" | head -n 1)"
if [ -z "$image" ]; then
  image="$(sudo -n grep -m1 -E "^[[:space:]]*image:" "$compose_file" | sed -E "s/^[[:space:]]*image:[[:space:]]*['\''\"]?//; s/['\''\"]?[[:space:]]*$//")"
fi
if [ -z "$image" ]; then
  echo "could not resolve Coolify image for $uuid" >&2
  exit 1
fi
printf "%s\n" "$image"
'
  remote_bash "$script" "$COOLIFY_RESOURCE_UUID" "$env_file" | head -n 1
}

read_remote_env_value() {
  local env_file="$1"
  local key="$2"
  local script
  script='
set -euo pipefail
env_file="$1"
key="$2"
sudo -n test -f "$env_file"
sudo -n grep -E "^[[:space:]]*${key}[[:space:]]*=" "$env_file" \
  | tail -n 1 \
  | sed -E "s/^[^=]*=//; s/^[[:space:]]+//; s/[[:space:]]+$//; s/^\"//; s/\"$//; s/^'\''//; s/'\''$//" || true
'
  remote_bash "$script" "$env_file" "$key" | head -n 1
}

resolve_remote_port() {
  if [ "$REMOTE_PORT" != "0" ]; then
    printf '%s' "$REMOTE_PORT"
    return
  fi
  local script
  script='
set -euo pipefail
for port in $(seq 18080 18179); do
  if ! ss -ltn | awk "{print \$4}" | grep -Eq "(^|:)${port}$"; then
    printf "%s\n" "$port"
    exit 0
  fi
done
echo "no free remote release port in 18080-18179" >&2
exit 1
'
  remote_bash "$script" | head -n 1
}

local_port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn | awk '{print $4}' | grep -Eq "(^|:)${port}$"
    return
  fi
  netstat -an 2>/dev/null | grep -E "[\.:]${port}[[:space:]].*LISTEN" >/dev/null
}

resolve_local_port() {
  if [ "$LOCAL_PORT" != "0" ]; then
    printf '%s' "$LOCAL_PORT"
    return
  fi
  local port
  for port in $(seq 18080 18179); do
    if ! local_port_in_use "$port"; then
      printf '%s' "$port"
      return
    fi
  done
  echo "no free local release tunnel port in 18080-18179" >&2
  exit 1
}

start_remote_candidate() {
  local env_file="$1"
  local image="$2"
  local source_commit="$3"
  local remote_port="$4"
  REMOTE_CONTAINER="sub2api-release-check-$$-$remote_port"
  local script
  script='
set -euo pipefail
container_name="$1"
port="$2"
env_file="$3"
image="$4"
source_commit="$5"
network="$6"
sudo -n test -f "$env_file"
sudo -n docker rm -f "$container_name" >/dev/null 2>&1 || true
network_args=()
if [ -n "$network" ]; then
  sudo -n docker network inspect "$network" >/dev/null
  network_args=(--network "$network")
fi
sudo -n docker run -d \
  --name "$container_name" \
  "${network_args[@]}" \
  -p "127.0.0.1:${port}:8080" \
  --env-file "$env_file" \
  -e "SOURCE_COMMIT=${source_commit}" \
  "$image" >/dev/null
'
  remote_bash "$script" "$REMOTE_CONTAINER" "$remote_port" "$env_file" "$image" "$source_commit" "$RELEASE_NETWORK"
}

cleanup_release_resources() {
  if [ -n "$TUNNEL_PID" ]; then
    kill "$TUNNEL_PID" >/dev/null 2>&1 || true
  fi
  if [ -n "$REMOTE_CONTAINER" ] && [ "$KEEP_CONTAINER" -ne 1 ] && [ -n "$REMOTE_HOST" ]; then
    remote_bash 'sudo -n docker rm -f "$1" >/dev/null 2>&1 || true' "$REMOTE_CONTAINER" >/dev/null 2>&1 || true
  fi
}

wait_local_health() {
  local base_url="$1"
  local elapsed=0
  local health
  while [ "$elapsed" -le "$WAIT_TIMEOUT" ]; do
    local args=(-fsS --max-time "$TIMEOUT")
    if [ -n "${HTTP_HOST:-}" ]; then
      args+=(-H "Host: $HTTP_HOST")
    fi
    if health="$(curl "${args[@]}" "$base_url/health" 2>/dev/null)" &&
      printf '%s' "$health" | jq -e '.status == "ok"' >/dev/null 2>&1; then
      printf '[PASS] release/candidate-health target=%s\n' "$base_url"
      return 0
    fi
    sleep "$WAIT_INTERVAL"
    elapsed=$((elapsed + WAIT_INTERVAL))
  done
  return 1
}

run_coolify_image_acceptance() {
  require_bin ssh
  if [ -z "$REMOTE_HOST" ]; then
    echo "--release with --coolify-resource-uuid requires --remote-host" >&2
    exit 2
  fi

  local env_file image source_commit remote_port local_port candidate_url internal_http_host
  env_file="$(resolve_remote_env_file)"
  image="$IMAGE"
  if [ -z "$image" ]; then
    image="$(resolve_current_coolify_image "$env_file")"
  fi
  source_commit="$EXPECT_COMMIT"
  if [ -z "$source_commit" ]; then
    source_commit="$(read_remote_env_value "$env_file" SOURCE_COMMIT)"
  fi
  if [ -z "$source_commit" ]; then
    echo "Coolify release env is missing SOURCE_COMMIT; cannot prove source/image identity" >&2
    exit 1
  fi

  remote_port="$(resolve_remote_port)"
  local_port="$(resolve_local_port)"
  trap cleanup_release_resources EXIT INT TERM

  printf 'Sub2API release acceptance remote=%s uuid=%s image=%s commit=%s mode=%s\n' \
    "$REMOTE_HOST" "$COOLIFY_RESOURCE_UUID" "$image" "$source_commit" "$CHECK_MODE"
  start_remote_candidate "$env_file" "$image" "$source_commit" "$remote_port"

  ssh -N -L "127.0.0.1:${local_port}:127.0.0.1:${remote_port}" "$REMOTE_HOST" &
  TUNNEL_PID="$!"
  candidate_url="http://127.0.0.1:${local_port}"
  internal_http_host="${REMOTE_CONTAINER}:8080"
  HTTP_HOST="$internal_http_host"
  if ! wait_local_health "$candidate_url"; then
    echo "Candidate image did not become healthy: $candidate_url/health" >&2
    exit 1
  fi

  EXPECT_COMMIT="$source_commit"
  RELEASE_BASE_URL="$candidate_url"
  ALLOW_LOCALHOST=1
  commit_matches || {
    echo "candidate image commit did not match expected SOURCE_COMMIT=$source_commit" >&2
    exit 1
  }
  SUB2API_HTTP_HOST="$internal_http_host" SUB2API_NO_SECRET_DISCOVERY=1 "${BASH:-bash}" "$CHECK_ENTRY" "$CHECK_MODE" --base-url "$candidate_url" --timeout "$TIMEOUT" "${CHECK_ARGS[@]}"
  printf 'RELEASE ACCEPTANCE PASSED image=%s commit=%s mode=%s\n' "$image" "$source_commit" "$CHECK_MODE"
}

admin_bootstrap() {
  local json
  json="$(curl_json POST "$RELEASE_BASE_URL/api/v1/auth/bootstrap")" || return 1
  ADMIN_TOKEN="$(printf '%s' "$json" | jq -r '.data.access_token // empty')"
  [ -n "$ADMIN_TOKEN" ]
}

commit_matches() {
  local info actual
  if [ -z "$EXPECT_COMMIT" ]; then
    return 0
  fi
  if [ -z "$ADMIN_TOKEN" ]; then
    admin_bootstrap || return 1
  fi
  info="$(curl_json GET "$RELEASE_BASE_URL/api/v1/admin/system/version" "$ADMIN_TOKEN")" || {
    ADMIN_TOKEN=""
    return 1
  }
  actual="$(printf '%s' "$info" | jq -r '.data.commit // empty')"
  if [ "$actual" = "$EXPECT_COMMIT" ] ||
    { [ "${#actual}" -ge 7 ] && [[ "$EXPECT_COMMIT" == "$actual"* ]]; } ||
    { [ "${#EXPECT_COMMIT}" -ge 7 ] && [[ "$actual" == "$EXPECT_COMMIT"* ]]; }; then
    printf '[PASS] release/commit commit=%s\n' "$actual"
    return 0
  fi
  printf 'Waiting for deployed commit: expected=%s actual=%s\n' "$EXPECT_COMMIT" "${actual:-unknown}" >&2
  return 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --full|--smoke|--audit-keys|--audit-models|--audit-upstream|--audit-routing)
      if [ "$CHECK_MODE_SET" -eq 0 ]; then
        CHECK_MODE="$1"
        CHECK_MODE_SET=1
      else
        CHECK_ARGS+=("$1")
      fi
      shift
      ;;
    --base-url)
      RELEASE_BASE_URL="${2:?--base-url requires a value}"
      shift 2
      ;;
    --remote-host)
      REMOTE_HOST="${2:?--remote-host requires a value}"
      shift 2
      ;;
    --coolify-resource-uuid)
      COOLIFY_RESOURCE_UUID="${2:?--coolify-resource-uuid requires a value}"
      shift 2
      ;;
    --image)
      IMAGE="${2:?--image requires a value}"
      shift 2
      ;;
    --release-network)
      RELEASE_NETWORK="${2:?--release-network requires a value}"
      shift 2
      ;;
    --remote-port)
      REMOTE_PORT="${2:?--remote-port requires a value}"
      shift 2
      ;;
    --local-port)
      LOCAL_PORT="${2:?--local-port requires a value}"
      shift 2
      ;;
    --keep-container)
      KEEP_CONTAINER=1
      shift
      ;;
    --endpoint-only)
      ENDPOINT_ONLY=1
      shift
      ;;
    --timeout)
      TIMEOUT="${2:?--timeout requires a value}"
      shift 2
      ;;
    --wait-timeout)
      WAIT_TIMEOUT="${2:?--wait-timeout requires a value}"
      shift 2
      ;;
    --wait-interval)
      WAIT_INTERVAL="${2:?--wait-interval requires a value}"
      shift 2
      ;;
    --expect-commit)
      EXPECT_COMMIT="${2:?--expect-commit requires a value}"
      shift 2
      ;;
    --allow-localhost)
      ALLOW_LOCALHOST=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      CHECK_ARGS+=("$1")
      shift
      ;;
  esac
done

require_bin curl
require_bin jq

if [ "$ENDPOINT_ONLY" -eq 0 ] && [ -z "$COOLIFY_RESOURCE_UUID" ]; then
  echo "--release is image acceptance and requires --coolify-resource-uuid." >&2
  echo "Use --endpoint-only only for temporary legacy HTTP checks; it is not release-authoritative." >&2
  exit 2
fi

if [ -n "$COOLIFY_RESOURCE_UUID" ]; then
  run_coolify_image_acceptance
  exit 0
fi

RELEASE_BASE_URL="$(trim_slash "$RELEASE_BASE_URL")"
case "$RELEASE_BASE_URL" in
  http://localhost*|https://localhost*|http://127.*|https://127.*|http://0.0.0.0*|https://0.0.0.0*)
    if [ "$ALLOW_LOCALHOST" -ne 1 ]; then
      echo "--release targets the deployed server image; refusing localhost URL: $RELEASE_BASE_URL" >&2
      echo "Use --allow-localhost only for explicit debugging, not deployment acceptance." >&2
      exit 2
    fi
    ;;
esac

health_url="$RELEASE_BASE_URL/health"
elapsed=0
printf 'Sub2API release acceptance target=%s mode=%s timeout=%ss wait=%ss\n' \
  "$RELEASE_BASE_URL" "$CHECK_MODE" "$TIMEOUT" "$WAIT_TIMEOUT"

while [ "$elapsed" -le "$WAIT_TIMEOUT" ]; do
  if health="$(curl -fsS --max-time "$TIMEOUT" "$health_url" 2>/dev/null)" &&
    printf '%s' "$health" | jq -e '.status == "ok"' >/dev/null 2>&1 &&
    commit_matches; then
    printf '[PASS] release/health target=%s\n' "$RELEASE_BASE_URL"
    "${BASH:-bash}" "$CHECK_ENTRY" "$CHECK_MODE" --base-url "$RELEASE_BASE_URL" --timeout "$TIMEOUT" "${CHECK_ARGS[@]}"
    printf 'RELEASE ACCEPTANCE PASSED target=%s mode=%s\n' "$RELEASE_BASE_URL" "$CHECK_MODE"
    exit 0
  fi
  sleep "$WAIT_INTERVAL"
  elapsed=$((elapsed + WAIT_INTERVAL))
done

echo "Deployed server did not become healthy: $health_url" >&2
exit 1
