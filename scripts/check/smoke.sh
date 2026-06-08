#!/usr/bin/env bash
set -Eeuo pipefail

MODE="standard"
TIMEOUT="${SUB2API_SMOKE_TIMEOUT:-45}"
APP_BASE_URL="${SUB2API_APP_BASE_URL:-}"
CHAT_BASE_URL="${SUB2API_CHAT_BASE_URL:-${SUB2API_BASE_URL:-}}"
CHAT_BASE_URL_EXPLICIT=0
if [ -n "${SUB2API_CHAT_BASE_URL:-}" ] || [ -n "${SUB2API_BASE_URL:-}" ]; then
  CHAT_BASE_URL_EXPLICIT=1
fi
HTTP_HOST="${SUB2API_HTTP_HOST:-}"
API_KEY="${SUB2API_CLIENT_KEY:-}"
DEFAULT_MODEL="${SUB2API_MODEL:-claude-sonnet-4-6}"
MODEL_SET=0
if [ -n "${SUB2API_MODEL:-}" ]; then
  MODEL_SET=1
fi
SECRET_DIR="${SUB2API_CONSUMER_SECRET_DIR:-}"
NO_SECRET_DISCOVERY="${SUB2API_NO_SECRET_DISCOVERY:-0}"
SERVER_SIDE_KEY_AUDIT=1
SKIP_STREAM=0

ADMIN_TOKEN=""
ADMIN_EMAIL=""

usage() {
  cat <<'EOF'
Usage:
  scripts/check.sh --smoke [--quick|--full] [options]

Modes:
  default     Health + public settings + auth/bootstrap + auth/me + provider catalog + model list + chat completion
  --quick     Health + public settings + auth/bootstrap + auth/me + provider catalog
  --full      Default checks + stream completion + admin dashboard stats

Options:
  --base-url URL        App base URL, e.g. https://sub2api.tengokukk.com
  --chat-base-url URL   Gateway base URL, e.g. https://sub2api.tengokukk.com/v1
  --api-key KEY         Downstream sub2api-issued API key
  --model MODEL         Model for chat completion smoke
  --secret-dir DIR      Directory containing consumer *.env files
  --no-secret-discovery Do not discover keys from ~/.codex-secrets/sub2api/consumers
  --no-server-side-key-audit
                        Fail instead of using admin server-side key audit fallback
  --skip-stream         Skip stream check even in --full mode
  --timeout SEC         Per-request timeout
  -h, --help            Show this help

Environment:
  SUB2API_APP_BASE_URL, SUB2API_BASE_URL, SUB2API_CHAT_BASE_URL,
  SUB2API_CLIENT_KEY, SUB2API_MODEL, SUB2API_CONSUMER_SECRET_DIR
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --quick)
      MODE="quick"
      shift
      ;;
    --full)
      MODE="full"
      shift
      ;;
    --base-url)
      APP_BASE_URL="${2:?--base-url requires a value}"
      shift 2
      ;;
    --chat-base-url)
      CHAT_BASE_URL="${2:?--chat-base-url requires a value}"
      CHAT_BASE_URL_EXPLICIT=1
      shift 2
      ;;
    --api-key)
      API_KEY="${2:?--api-key requires a value}"
      shift 2
      ;;
    --model)
      DEFAULT_MODEL="${2:?--model requires a value}"
      MODEL_SET=1
      shift 2
      ;;
    --secret-dir)
      SECRET_DIR="${2:?--secret-dir requires a value}"
      shift 2
      ;;
    --no-secret-discovery)
      NO_SECRET_DISCOVERY=1
      shift
      ;;
    --no-server-side-key-audit)
      SERVER_SIDE_KEY_AUDIT=0
      shift
      ;;
    --skip-stream)
      SKIP_STREAM=1
      shift
      ;;
    --timeout)
      TIMEOUT="${2:?--timeout requires a value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

trim_slash() {
  local value="$1"
  while [ "${value%/}" != "$value" ]; do
    value="${value%/}"
  done
  printf '%s' "$value"
}

if [ -z "$APP_BASE_URL" ]; then
  if [ -n "$CHAT_BASE_URL" ]; then
    maybe_app="$(trim_slash "$CHAT_BASE_URL")"
    if [[ "$maybe_app" == */v1 ]]; then
      APP_BASE_URL="${maybe_app%/v1}"
    else
      APP_BASE_URL="$maybe_app"
    fi
  else
    APP_BASE_URL="https://sub2api.tengokukk.com"
  fi
fi

APP_BASE_URL="$(trim_slash "$APP_BASE_URL")"
if [ -z "$CHAT_BASE_URL" ]; then
  CHAT_BASE_URL="$APP_BASE_URL/v1"
fi
CHAT_BASE_URL="$(trim_slash "$CHAT_BASE_URL")"

require_bin() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 2
  fi
}

require_bin curl
require_bin jq

pass() {
  printf '[PASS] %s\n' "$1"
}

fail() {
  printf '[FAIL] %s: %s\n' "$1" "$2" >&2
  exit 1
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

mask_key() {
  local key="$1"
  if [ -z "$key" ]; then
    printf ''
  elif [ "${#key}" -le 12 ]; then
    printf '***'
  else
    printf '%s...%s' "${key:0:6}" "${key: -4}"
  fi
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

assert_jq() {
  local name="$1"
  local json="$2"
  local filter="$3"
  if ! printf '%s' "$json" | jq -e "$filter" >/dev/null; then
    fail "$name" "unexpected response: $(truncate "$json")"
  fi
}

step_health() {
  local json
  json="$(curl_body GET "$APP_BASE_URL/health")" || fail "health" "$json"
  assert_jq "health" "$json" '.status == "ok"'
  pass "health"
}

step_public_settings() {
  local json
  json="$(curl_body GET "$APP_BASE_URL/api/v1/settings/public")" || fail "settings/public" "$json"
  assert_jq "settings/public" "$json" '.code == 0 and (.data.site_name | type == "string")'
  pass "settings/public"
}

step_auth_bootstrap() {
  local json
  json="$(curl_body POST "$APP_BASE_URL/api/v1/auth/bootstrap")" || fail "auth/bootstrap" "$json"
  ADMIN_TOKEN="$(printf '%s' "$json" | jq -r '.data.access_token // empty')"
  ADMIN_EMAIL="$(printf '%s' "$json" | jq -r '.data.user.email // empty')"
  if [ -z "$ADMIN_TOKEN" ]; then
    fail "auth/bootstrap" "missing access_token"
  fi
  pass "auth/bootstrap"
}

step_auth_me() {
  local json email role
  json="$(curl_body GET "$APP_BASE_URL/api/v1/auth/me" "$ADMIN_TOKEN")" || fail "auth/me" "$json"
  email="$(printf '%s' "$json" | jq -r '.data.email // empty')"
  role="$(printf '%s' "$json" | jq -r '.data.role // empty')"
  if [ -z "$email" ] || [ "$role" != "admin" ]; then
    fail "auth/me" "expected admin user, got email=$email role=$role"
  fi
  pass "auth/me"
}

step_provider_catalog() {
  local json count
  json="$(curl_body GET "$APP_BASE_URL/api/v1/admin/provider-catalog" "$ADMIN_TOKEN")" || fail "provider-catalog" "$json"
  count="$(printf '%s' "$json" | jq -r '(.data // []) | length')"
  if [ "$count" -lt 1 ]; then
    fail "provider-catalog" "empty provider catalog"
  fi
  pass "provider-catalog"
}

step_admin_dashboard_stats() {
  local json
  json="$(curl_body GET "$APP_BASE_URL/api/v1/admin/dashboard/stats" "$ADMIN_TOKEN")" || fail "admin/dashboard-stats" "$json"
  assert_jq "admin/dashboard-stats" "$json" '.code == 0'
  pass "admin/dashboard-stats"
}

strip_env_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  value="${value%$'\r'}"
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "$value"
}

CANDIDATES=()

add_candidate() {
  local key="$1"
  local base="${2:-$CHAT_BASE_URL}"
  local model="${3:-$DEFAULT_MODEL}"
  local source="${4:-env}"
  local key_id="${5:-}"
  local group_id="${6:-}"
  local group_name="${7:-}"

  if [ -z "$key" ] || [[ "$key" == \<*\> ]]; then
    return 0
  fi
  base="$(trim_slash "$base")"
  if [ -z "$model" ]; then
    model="$DEFAULT_MODEL"
  fi
  CANDIDATES+=("$key|$base|$model|$source|$key_id|$group_id|$group_name")
}

load_env_file() {
  local file="$1"
  declare -A values=()
  local line name value

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      name="${BASH_REMATCH[1]}"
      value="$(strip_env_value "${BASH_REMATCH[2]}")"
      values["$name"]="$value"
    fi
  done < "$file"

  for name in "${!values[@]}"; do
    local prefix=""
    if [ "$name" = "SUB2API_CLIENT_KEY" ]; then
      prefix="SUB2API"
    elif [[ "$name" =~ ^SUB2API_(.+)_API_KEY$ ]]; then
      prefix="SUB2API_${BASH_REMATCH[1]}"
    else
      continue
    fi
    add_candidate \
      "${values[$name]}" \
      "${values[${prefix}_BASE_URL]:-$CHAT_BASE_URL}" \
      "${values[${prefix}_MODEL]:-$DEFAULT_MODEL}" \
      "$file:$name" \
      "${values[${prefix}_KEY_ID]:-}" \
      "${values[${prefix}_GROUP_ID]:-}" \
      "${values[${prefix}_GROUP_NAME]:-}"
  done
}

discover_candidates() {
  if [ -n "$API_KEY" ]; then
    add_candidate "$API_KEY" "$CHAT_BASE_URL" "$DEFAULT_MODEL" "env:SUB2API_CLIENT_KEY"
    return 0
  fi

  if [ "$NO_SECRET_DISCOVERY" -eq 1 ]; then
    return 0
  fi

  local dirs=()
  if [ -n "$SECRET_DIR" ]; then
    dirs+=("$SECRET_DIR")
  fi
  if [ -n "${HOME:-}" ]; then
    dirs+=("$HOME/.codex-secrets/sub2api/consumers")
  fi

  local dir file
  for dir in "${dirs[@]}"; do
    [ -d "$dir" ] || continue
    while IFS= read -r -d '' file; do
      load_env_file "$file"
    done < <(find "$dir" -maxdepth 1 -type f -name '*.env' -print0)
  done
}

try_model_list() {
  local key="$1"
  local base="$2"
  local json
  json="$(curl_body GET "$base/models" "$key")" || return 1
  if ! printf '%s' "$json" | jq -e 'type == "object" and (.error? | not)' >/dev/null; then
    echo "unexpected model-list response: $(truncate "$json")" >&2
    return 1
  fi
}

chat_body() {
  local model="$1"
  local stream="$2"
  jq -n \
    --arg model "$model" \
    --arg prompt "Reply with a short confirmation that sub2api smoke is OK." \
    --argjson stream "$stream" \
    '{model: $model, messages: [{role: "user", content: $prompt}], temperature: 0, max_tokens: 32, stream: $stream}'
}

try_chat_completion() {
  local key="$1"
  local base="$2"
  local model="$3"
  local body json content
  body="$(chat_body "$model" false)"
  json="$(curl_body POST "$base/chat/completions" "$key" "$body")" || return 1
  content="$(printf '%s' "$json" | jq -r '.choices[0].message.content // empty')"
  if [ -z "${content//[[:space:]]/}" ]; then
    echo "empty chat completion content: $(truncate "$json")" >&2
    return 1
  fi
}

try_stream_completion() {
  local key="$1"
  local base="$2"
  local model="$3"
  local body text frame_count content
  body="$(chat_body "$model" true)"
  text="$(curl_body POST "$base/chat/completions" "$key" "$body" "text/event-stream")" || return 1
  frame_count="$(printf '%s\n' "$text" | grep -c '^data:' || true)"
  if [ "$frame_count" -lt 1 ]; then
    echo "stream response did not contain SSE data frames" >&2
    return 1
  fi
  content="$(
    printf '%s\n' "$text" |
      sed -n 's/^data:[[:space:]]*//p' |
      grep -v '^\[DONE\]$' |
      jq -r '(.choices[0].delta.content // .choices[0].message.content // .content // empty)' 2>/dev/null |
      tr -d '\n' || true
  )"
  if [ -z "${content//[[:space:]]/}" ]; then
    echo "stream response had $frame_count SSE frames but no assistant content" >&2
    return 1
  fi
}

step_gateway_server_side() {
  if [ "$SERVER_SIDE_KEY_AUDIT" -ne 1 ]; then
    fail "downstream-key" "no candidate key found; set SUB2API_CLIENT_KEY or --secret-dir"
  fi

  local json total errors item id name masked status usable reason group platform label body result selected model_count summary audit_chat_base_url
  json="$(curl_body GET "$APP_BASE_URL/api/v1/admin/consumer-keys?limit=200" "$ADMIN_TOKEN")" || fail "consumer-keys/list" "$json"
  assert_jq "consumer-keys/list" "$json" '.code == 0 and (.data.items | type == "array")'
  total="$(printf '%s' "$json" | jq -r '.data.items | length')"
  if [ "$total" -lt 1 ]; then
    fail "downstream-key" "no downstream consumer keys found"
  fi

  errors=()
  while IFS= read -r item; do
    id="$(printf '%s' "$item" | jq -r '.id')"
    name="$(printf '%s' "$item" | jq -r '.name // ""')"
    masked="$(printf '%s' "$item" | jq -r '.masked_key // ""')"
    status="$(printf '%s' "$item" | jq -r '.status // ""')"
    usable="$(printf '%s' "$item" | jq -r '.usable // false')"
    reason="$(printf '%s' "$item" | jq -r '.block_reason // ""')"
    group="$(printf '%s' "$item" | jq -r '.group_name // ""')"
    platform="$(printf '%s' "$item" | jq -r '.platform // ""')"
    label="key#$id $masked name=$name status=$status group=$group platform=$platform"

    if [ "$usable" != "true" ]; then
      errors+=("$label skipped: ${reason:-unusable}")
      continue
    fi

    audit_chat_base_url=""
    if [ "$CHAT_BASE_URL_EXPLICIT" -eq 1 ]; then
      audit_chat_base_url="$CHAT_BASE_URL"
    fi

    body="$(
      jq -n \
        --arg model "$([ "$MODEL_SET" -eq 1 ] && printf '%s' "$DEFAULT_MODEL" || true)" \
        --arg chat_base_url "$audit_chat_base_url" \
        --argjson timeout_sec "$TIMEOUT" \
        '{
          model: $model,
          chat_base_url: $chat_base_url,
          timeout_sec: $timeout_sec
        } | with_entries(select(.value != ""))'
    )"

    if result="$(curl_body POST "$APP_BASE_URL/api/v1/admin/consumer-keys/$id/test" "$ADMIN_TOKEN" "$body" 2>&1)"; then
      if printf '%s' "$result" | jq -e '.code == 0 and .data.success == true' >/dev/null; then
        selected="$(printf '%s' "$result" | jq -r '.data.selected_model // ""')"
        model_count="$(printf '%s' "$result" | jq -r '.data.model_count // 0')"
        pass "model-list (server-side $label models=$model_count)"
        pass "chat completion (server-side $label selected_model=$selected)"
        if [ "$MODE" = "full" ] && [ "$SKIP_STREAM" -eq 0 ]; then
          printf '[SKIP] stream completion (server-side key audit keeps raw key hidden)\n'
        fi
        return 0
      fi
      summary="$(printf '%s' "$result" | jq -r '[.data.model_list.error, .data.chat.error] | map(select(. != null and . != "")) | join(" | ")' 2>/dev/null || true)"
      errors+=("$label ${summary:-unexpected response $(truncate "$result")}")
    else
      errors+=("$label $result")
    fi
  done < <(printf '%s' "$json" | jq -c '.data.items[]')

  printf '%s\n' "${errors[@]}" >&2
  fail "gateway" "no downstream key passed server-side gateway smoke"
}

step_gateway() {
  discover_candidates
  if [ "${#CANDIDATES[@]}" -lt 1 ]; then
    step_gateway_server_side
    return
  fi

  local require_stream=0
  if [ "$MODE" = "full" ] && [ "$SKIP_STREAM" -eq 0 ]; then
    require_stream=1
  fi

  local errors=()
  local raw key base model source key_id group_id group_name label err
  for raw in "${CANDIDATES[@]}"; do
    IFS='|' read -r key base model source key_id group_id group_name <<< "$raw"
    label="$(mask_key "$key") model=$model source=$source"
    if ! err="$(try_model_list "$key" "$base" 2>&1)"; then
      errors+=("$label model-list: $err")
      continue
    fi
    if ! err="$(try_chat_completion "$key" "$base" "$model" 2>&1)"; then
      errors+=("$label chat: $err")
      continue
    fi
    if [ "$require_stream" -eq 1 ]; then
      if ! err="$(try_stream_completion "$key" "$base" "$model" 2>&1)"; then
        errors+=("$label stream: $err")
        continue
      fi
    fi

    pass "model-list ($label)"
    pass "chat completion ($label)"
    if [ "$require_stream" -eq 1 ]; then
      pass "stream completion ($label)"
    fi
    return 0
  done

  printf '%s\n' "${errors[@]}" >&2
  fail "gateway" "no downstream key passed gateway smoke"
}

printf 'Sub2API smoke mode=%s app=%s chat=%s timeout=%ss\n' "$MODE" "$APP_BASE_URL" "$CHAT_BASE_URL" "$TIMEOUT"

step_health
step_public_settings
step_auth_bootstrap
step_auth_me
step_provider_catalog

if [ "$MODE" != "quick" ]; then
  step_gateway
fi

if [ "$MODE" = "full" ]; then
  step_admin_dashboard_stats
fi

printf 'ALL PASSED\n'
