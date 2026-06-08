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
ALLOW_LOCALHOST=0
CHECK_ARGS=()
ADMIN_TOKEN=""

usage() {
  cat <<'EOF'
Usage:
  scripts/check.sh --release [--full|--smoke|--audit-keys|--audit-models|--audit-upstream|--audit-routing] [options]

Release acceptance for the Coolify-deployed server image. This mode does not
start local containers, source dev servers, mocks, or dry runs. It waits for
the deployed HTTP endpoint, then runs the selected real HTTP check module.

Examples:
  scripts/check.sh --release --full
  scripts/check.sh --release --smoke --full
  scripts/check.sh --release --audit-keys --models-only
  scripts/check.sh --release --audit-models --model-filter gpt-5
  scripts/check.sh --release --base-url https://staging.example.com --full

Options:
  --base-url URL       Deployed app URL, default https://sub2api.tengokukk.com
  --timeout SEC        Per-request timeout passed to check modules, default 45
  --wait-timeout SEC   Seconds to wait for deployed /health, default 180
  --wait-interval SEC  Poll interval while waiting for /health, default 5
  --expect-commit SHA  Wait until deployed /admin/system/version reports SHA
  --allow-localhost    Permit localhost/127.0.0.1 targets for explicit debugging
  -h, --help           Show this help

Environment:
  SUB2API_RELEASE_BASE_URL, SUB2API_APP_BASE_URL, SUB2API_RELEASE_TIMEOUT,
  SUB2API_RELEASE_WAIT_TIMEOUT, SUB2API_RELEASE_WAIT_INTERVAL,
  SUB2API_RELEASE_EXPECT_COMMIT
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

curl_json() {
  local method="$1"
  local url="$2"
  local token="${3:-}"
  local tmp status

  tmp="$(mktemp)"
  local args=(-sS --max-time "$TIMEOUT" -o "$tmp" -w '%{http_code}' -X "$method" -H "Accept: application/json")
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
