#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

LIMIT="${SUB2API_AUDIT_KEY_LIMIT:-200}"
QUERY=""
STATUS_FILTER="${SUB2API_AUDIT_KEY_STATUS:-}"
MODEL="${SUB2API_AUDIT_MODEL:-}"
CHAT_BASE_URL="${SUB2API_CHAT_BASE_URL:-}"
MODELS_ONLY=0
INCLUDE_UNUSABLE=0

usage() {
  cat <<'EOF'
Usage:
  scripts/check.sh --audit-keys [options]

Audits downstream consumer keys without exposing raw keys to the shell.
Default mode enumerates admin /consumer-keys metadata and server-side tests
each usable key with /v1/models + /v1/chat/completions.

Options:
  --base-url URL       App base URL, e.g. https://sub2api.tengokukk.com
  --chat-base-url URL  Optional gateway base URL override; must match app host
  --limit N            Max keys to enumerate, default 200, max 1000
  --query TEXT         Filter by key name
  --status STATUS      Filter listed keys by status
  --model MODEL        Force chat model instead of selecting from /v1/models
  --models-only        Only test /v1/models; cheaper and avoids chat spend
  --include-unusable   Also test keys marked unusable by metadata
  --timeout SEC        Per-request timeout
  -h, --help           Show this help

Environment:
  SUB2API_APP_BASE_URL, SUB2API_AUDIT_BASE_URL, SUB2API_AUDIT_TIMEOUT,
  SUB2API_AUDIT_KEY_LIMIT, SUB2API_AUDIT_KEY_STATUS, SUB2API_AUDIT_MODEL,
  SUB2API_CHAT_BASE_URL
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --base-url)
      APP_BASE_URL="${2:?--base-url requires a value}"
      shift 2
      ;;
    --chat-base-url)
      CHAT_BASE_URL="${2:?--chat-base-url requires a value}"
      shift 2
      ;;
    --limit)
      LIMIT="${2:?--limit requires a value}"
      shift 2
      ;;
    --query)
      QUERY="${2:?--query requires a value}"
      shift 2
      ;;
    --status)
      STATUS_FILTER="${2:?--status requires a value}"
      shift 2
      ;;
    --model)
      MODEL="${2:?--model requires a value}"
      shift 2
      ;;
    --models-only)
      MODELS_ONLY=1
      shift
      ;;
    --include-unusable)
      INCLUDE_UNUSABLE=1
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

audit_init_base_url
audit_require_tools

printf 'Sub2API consumer key audit app=%s limit=%s models_only=%s timeout=%ss\n' "$APP_BASE_URL" "$LIMIT" "$(json_bool "$MODELS_ONLY")" "$TIMEOUT"
if [ "$MODELS_ONLY" -eq 0 ]; then
  audit_warn "This audit performs real gateway chat requests and may consume quota/usage."
fi

admin_bootstrap

query_url="$APP_BASE_URL/api/v1/admin/consumer-keys?limit=$(urlencode "$LIMIT")"
if [ -n "$QUERY" ]; then
  query_url="$query_url&q=$(urlencode "$QUERY")"
fi
if [ -n "$STATUS_FILTER" ]; then
  query_url="$query_url&status=$(urlencode "$STATUS_FILTER")"
fi

json="$(curl_body GET "$query_url" "$ADMIN_TOKEN")" || {
  audit_fail "consumer-keys/list: $json"
  exit 1
}

if ! printf '%s' "$json" | jq -e '.code == 0 and (.data.items | type == "array")' >/dev/null; then
  audit_fail "consumer-keys/list: unexpected response $(truncate "$json")"
  exit 1
fi

total="$(printf '%s' "$json" | jq -r '.data.items | length')"
truncated="$(printf '%s' "$json" | jq -r '.data.truncated // false')"
printf 'Found %s consumer keys (truncated=%s)\n' "$total" "$truncated"

pass_count=0
fail_count=0
skip_count=0

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

  if [ "$usable" != "true" ] && [ "$INCLUDE_UNUSABLE" -eq 0 ]; then
    audit_skip "$label reason=${reason:-unusable}"
    skip_count=$((skip_count + 1))
    continue
  fi

  body="$(
    jq -n \
      --arg model "$MODEL" \
      --arg chat_base_url "$CHAT_BASE_URL" \
      --argjson models_only "$(json_bool "$MODELS_ONLY")" \
      --argjson timeout_sec "$TIMEOUT" \
      '{
        model: $model,
        chat_base_url: $chat_base_url,
        models_only: $models_only,
        timeout_sec: $timeout_sec
      } | with_entries(select(.value != ""))'
  )"

  if result="$(curl_body POST "$APP_BASE_URL/api/v1/admin/consumer-keys/$id/test" "$ADMIN_TOKEN" "$body" 2>&1)"; then
    if printf '%s' "$result" | jq -e '.code == 0 and .data.success == true' >/dev/null; then
      selected="$(printf '%s' "$result" | jq -r '.data.selected_model // ""')"
      model_count="$(printf '%s' "$result" | jq -r '.data.model_count // 0')"
      audit_pass "$label models=$model_count selected_model=$selected"
      pass_count=$((pass_count + 1))
    else
      summary="$(printf '%s' "$result" | jq -r '[.data.model_list.error, .data.chat.error] | map(select(. != null and . != "")) | join(" | ")' 2>/dev/null || true)"
      audit_fail "$label ${summary:-unexpected response $(truncate "$result")}"
      fail_count=$((fail_count + 1))
    fi
  else
    audit_fail "$label $result"
    fail_count=$((fail_count + 1))
  fi
done < <(printf '%s' "$json" | jq -c '.data.items[]')

printf 'SUMMARY consumer-keys pass=%d fail=%d skip=%d total=%s\n' "$pass_count" "$fail_count" "$skip_count" "$total"

if [ "$fail_count" -gt 0 ]; then
  exit 1
fi

printf 'ALL PASSED\n'
