#!/usr/bin/env bash
set -Eeuo pipefail

APP_BASE_URL="${SUB2API_APP_BASE_URL:-${SUB2API_AUDIT_BASE_URL:-}}"
TIMEOUT="${SUB2API_AUDIT_TIMEOUT:-45}"
HTTP_HOST="${SUB2API_HTTP_HOST:-}"
ADMIN_TOKEN=""

trim_slash() {
  local value="$1"
  while [ "${value%/}" != "$value" ]; do
    value="${value%/}"
  done
  printf '%s' "$value"
}

audit_init_base_url() {
  if [ -z "$APP_BASE_URL" ]; then
    APP_BASE_URL="https://sub2api.tengokukk.com"
  fi
  APP_BASE_URL="$(trim_slash "$APP_BASE_URL")"
}

require_bin() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 2
  fi
}

audit_require_tools() {
  require_bin curl
  require_bin jq
}

urlencode() {
  jq -rn --arg value "$1" '$value | @uri'
}

truncate() {
  local text="$1"
  text="${text//$'\n'/ }"
  if [ "${#text}" -gt 240 ]; then
    printf '%s...' "${text:0:240}"
  else
    printf '%s' "$text"
  fi
}

audit_pass() {
  printf '[PASS] %s\n' "$1"
}

audit_fail() {
  printf '[FAIL] %s\n' "$1" >&2
}

audit_skip() {
  printf '[SKIP] %s\n' "$1"
}

audit_warn() {
  printf '[WARN] %s\n' "$1" >&2
}

curl_body() {
  local method="$1"
  local url="$2"
  local token="${3:-}"
  local body="${4:-}"
  local accept="${5:-application/json}"
  local tmp status

  tmp="$(mktemp)"
  local args=(-sS --max-time "$TIMEOUT" -o "$tmp" -w '%{http_code}' -X "$method" -H "Accept: $accept")
  if [ -n "$HTTP_HOST" ]; then
    args+=(-H "Host: $HTTP_HOST")
  fi
  if [ -n "$token" ]; then
    args+=(-H "Authorization: Bearer $token")
  fi
  if [ -n "$body" ]; then
    args+=(-H "Content-Type: application/json" --data "$body")
  fi

  if status="$(curl "${args[@]}" "$url")"; then
    :
  else
    local curl_status=$?
    local text
    text="$(cat "$tmp" 2>/dev/null || true)"
    rm -f "$tmp"
    echo "curl exit $curl_status: $(truncate "$text")" >&2
    return 1
  fi

  local text
  text="$(cat "$tmp")"
  rm -f "$tmp"
  if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
    echo "HTTP $status: $(truncate "$text")" >&2
    return 1
  fi
  printf '%s' "$text"
}

admin_bootstrap() {
  local json
  if ! json="$(curl_body POST "$APP_BASE_URL/api/v1/auth/bootstrap" "" "" "application/json" 2>&1)"; then
    audit_fail "auth/bootstrap: $json"
    exit 1
  fi
  ADMIN_TOKEN="$(printf '%s' "$json" | jq -r '.data.access_token // empty')"
  if [ -z "$ADMIN_TOKEN" ]; then
    audit_fail "auth/bootstrap: missing access_token"
    exit 1
  fi
  audit_pass "auth/bootstrap"
}

json_bool() {
  if [ "$1" -eq 1 ]; then
    printf 'true'
  else
    printf 'false'
  fi
}
