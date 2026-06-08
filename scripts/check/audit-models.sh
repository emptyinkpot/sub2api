#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

LIMIT="${SUB2API_AUDIT_KEY_LIMIT:-200}"
QUERY=""
STATUS_FILTER="${SUB2API_AUDIT_KEY_STATUS:-}"
CHAT_BASE_URL="${SUB2API_CHAT_BASE_URL:-}"
INCLUDE_UNUSABLE=0
INCLUDE_IMAGE=0
MODEL_FILTER=""
SLEEP_MS="${SUB2API_AUDIT_SLEEP_MS:-500}"

usage() {
  cat <<'EOF'
Usage:
  scripts/check.sh --audit-models [options]

Audits every model exposed by every usable downstream consumer key. Raw keys
are never exposed to the shell; each model probe is performed server-side via
/api/v1/admin/consumer-keys/:id/test.

Options:
  --base-url URL       App base URL, e.g. https://sub2api.tengokukk.com
  --chat-base-url URL  Optional gateway base URL override; must match app host
  --limit N            Max keys to enumerate, default 200, max 1000
  --query TEXT         Filter by key name
  --status STATUS      Filter listed keys by status
  --model-filter TEXT  Only audit models containing this substring
  --include-image      Also run real image-generation probes for OpenAI/Gemini image models
  --include-unusable   Also audit keys marked unusable by metadata
  --sleep-ms N         Milliseconds to wait between real model probes, default 500
  --timeout SEC        Per-request timeout
  -h, --help           Show this help

Environment:
  SUB2API_APP_BASE_URL, SUB2API_AUDIT_BASE_URL, SUB2API_AUDIT_TIMEOUT,
  SUB2API_AUDIT_KEY_LIMIT, SUB2API_AUDIT_KEY_STATUS, SUB2API_CHAT_BASE_URL,
  SUB2API_AUDIT_SLEEP_MS
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
    --model-filter)
      MODEL_FILTER="${2:?--model-filter requires a value}"
      shift 2
      ;;
    --include-image)
      INCLUDE_IMAGE=1
      shift
      ;;
    --include-unusable)
      INCLUDE_UNUSABLE=1
      shift
      ;;
    --sleep-ms)
      SLEEP_MS="${2:?--sleep-ms requires a value}"
      shift 2
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

if ! [[ "$SLEEP_MS" =~ ^[0-9]+$ ]]; then
  echo "--sleep-ms must be a non-negative integer" >&2
  exit 2
fi

audit_init_base_url
audit_require_tools

printf 'Sub2API model audit app=%s limit=%s include_image=%s timeout=%ss sleep_ms=%s\n' "$APP_BASE_URL" "$LIMIT" "$(json_bool "$INCLUDE_IMAGE")" "$TIMEOUT" "$SLEEP_MS"
audit_warn "This audit performs real gateway requests for every audited model and may consume quota/usage."
if [ "$INCLUDE_IMAGE" -eq 0 ]; then
  audit_warn "Image models are classified and skipped by default; pass --include-image to generate real images."
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

total_keys="$(printf '%s' "$json" | jq -r '.data.items | length')"
truncated="$(printf '%s' "$json" | jq -r '.data.truncated // false')"
printf 'Found %s consumer keys (truncated=%s)\n' "$total_keys" "$truncated"

classify_model_capability() {
  local platform="$1"
  local model="$2"
  local lower
  lower="$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')"

  case "$lower" in
    *embedding*|*embed*|*rerank*)
      printf 'unsupported'
      return
      ;;
  esac

  if [ "$platform" = "openai" ] && [[ "$lower" == gpt-image-* ]]; then
    printf 'image'
    return
  fi

  if [ "$platform" = "gemini" ] && [[ "$lower" == *image* ]]; then
    printf 'gemini-image'
    return
  fi

  printf 'chat'
}

sleep_between_model_probes() {
  if [ "$SLEEP_MS" -le 0 ]; then
    return
  fi
  local seconds
  printf -v seconds '%d.%03d' "$((SLEEP_MS / 1000))" "$((SLEEP_MS % 1000))"
  sleep "$seconds"
}

key_count=0
model_count=0
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
  key_label="key#$id $masked name=$name status=$status group=$group platform=$platform"

  if [ "$usable" != "true" ] && [ "$INCLUDE_UNUSABLE" -eq 0 ]; then
    audit_skip "$key_label reason=${reason:-unusable}"
    skip_count=$((skip_count + 1))
    continue
  fi
  key_count=$((key_count + 1))

  list_body="$(
    jq -n \
      --arg chat_base_url "$CHAT_BASE_URL" \
      --argjson timeout_sec "$TIMEOUT" \
      '{
        models_only: true,
        chat_base_url: $chat_base_url,
        timeout_sec: $timeout_sec
      } | with_entries(select(.value != ""))'
  )"

  if ! list_result="$(curl_body POST "$APP_BASE_URL/api/v1/admin/consumer-keys/$id/test" "$ADMIN_TOKEN" "$list_body" 2>&1)"; then
    audit_fail "$key_label model-list $list_result"
    fail_count=$((fail_count + 1))
    continue
  fi
  if ! printf '%s' "$list_result" | jq -e '.code == 0 and (.data.models | type == "array")' >/dev/null; then
    audit_fail "$key_label model-list unexpected response $(truncate "$list_result")"
    fail_count=$((fail_count + 1))
    continue
  fi

  while IFS= read -r model; do
    model="${model//$'\r'/}"
    if [ -z "$model" ]; then
      continue
    fi
    if [ -n "$MODEL_FILTER" ] && [[ "$model" != *"$MODEL_FILTER"* ]]; then
      continue
    fi

    model_count=$((model_count + 1))
    capability="$(classify_model_capability "$platform" "$model")"
    model_label="$key_label model=$model capability=$capability"

    case "$capability" in
      unsupported)
        audit_skip "$model_label reason=unsupported-model-family"
        skip_count=$((skip_count + 1))
        continue
        ;;
      gemini-image|image)
        if [ "$INCLUDE_IMAGE" -eq 0 ]; then
          audit_skip "$model_label reason=image-generation-disabled"
          skip_count=$((skip_count + 1))
          continue
        fi
        ;;
    esac

    body="$(
      jq -n \
        --arg model "$model" \
        --arg capability "$capability" \
        --arg chat_base_url "$CHAT_BASE_URL" \
        --argjson timeout_sec "$TIMEOUT" \
        '{
          model: $model,
          capability: $capability,
          chat_base_url: $chat_base_url,
          timeout_sec: $timeout_sec
        } | with_entries(select(.value != ""))'
    )"

    if result="$(curl_body POST "$APP_BASE_URL/api/v1/admin/consumer-keys/$id/test" "$ADMIN_TOKEN" "$body" 2>&1)"; then
      if printf '%s' "$result" | jq -e '.code == 0 and .data.success == true' >/dev/null; then
        status_code="$(printf '%s' "$result" | jq -r '.data.chat.status_code // .data.image.status_code // ""')"
        audit_pass "$model_label status=${status_code:-ok}"
        pass_count=$((pass_count + 1))
      else
        summary="$(printf '%s' "$result" | jq -r '[.data.model_list.error, .data.chat.error, .data.image.error] | map(select(. != null and . != "")) | join(" | ")' 2>/dev/null || true)"
        audit_fail "$model_label ${summary:-unexpected response $(truncate "$result")}"
        fail_count=$((fail_count + 1))
      fi
    else
      audit_fail "$model_label $result"
      fail_count=$((fail_count + 1))
    fi
    sleep_between_model_probes
  done < <(printf '%s' "$list_result" | jq -r '.data.models[]')
done < <(printf '%s' "$json" | jq -c '.data.items[]')

printf 'SUMMARY models pass=%d fail=%d skip=%d keys=%d models=%d total_keys=%s\n' \
  "$pass_count" "$fail_count" "$skip_count" "$key_count" "$model_count" "$total_keys"

if [ "$fail_count" -gt 0 ]; then
  exit 1
fi

printf 'ALL PASSED\n'
