#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

LIMIT="${SUB2API_AUDIT_ACCOUNT_LIMIT:-200}"
PLATFORM="${SUB2API_AUDIT_PLATFORM:-}"
TYPE_FILTER="${SUB2API_AUDIT_ACCOUNT_TYPE:-}"
STATUS_FILTER="${SUB2API_AUDIT_ACCOUNT_STATUS:-}"
QUERY=""
MODEL="${SUB2API_AUDIT_MODEL:-}"
INCLUDE_DISABLED=0

usage() {
  cat <<'EOF'
Usage:
  scripts/check.sh --audit-upstream [options]

Audits upstream accounts by enumerating /admin/accounts and calling the
existing /admin/accounts/:id/test SSE endpoint for each candidate account.

Options:
  --base-url URL       App base URL, e.g. https://sub2api.tengokukk.com
  --limit N            Max accounts to enumerate, default 200
  --platform NAME      Filter platform, e.g. openai, anthropic, gemini
  --type TYPE          Filter account type, e.g. oauth, api-key
  --status STATUS      Filter account status in list query
  --query TEXT         Filter account name/search
  --model MODEL        Optional model_id sent to account test
  --include-disabled   Also test disabled/inactive accounts
  --timeout SEC        Per-request timeout
  -h, --help           Show this help

Environment:
  SUB2API_APP_BASE_URL, SUB2API_AUDIT_BASE_URL, SUB2API_AUDIT_TIMEOUT,
  SUB2API_AUDIT_ACCOUNT_LIMIT, SUB2API_AUDIT_PLATFORM,
  SUB2API_AUDIT_ACCOUNT_TYPE, SUB2API_AUDIT_ACCOUNT_STATUS, SUB2API_AUDIT_MODEL
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --base-url)
      APP_BASE_URL="${2:?--base-url requires a value}"
      shift 2
      ;;
    --limit)
      LIMIT="${2:?--limit requires a value}"
      shift 2
      ;;
    --platform)
      PLATFORM="${2:?--platform requires a value}"
      shift 2
      ;;
    --type)
      TYPE_FILTER="${2:?--type requires a value}"
      shift 2
      ;;
    --status)
      STATUS_FILTER="${2:?--status requires a value}"
      shift 2
      ;;
    --query)
      QUERY="${2:?--query requires a value}"
      shift 2
      ;;
    --model)
      MODEL="${2:?--model requires a value}"
      shift 2
      ;;
    --include-disabled)
      INCLUDE_DISABLED=1
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

printf 'Sub2API upstream account audit app=%s limit=%s timeout=%ss\n' "$APP_BASE_URL" "$LIMIT" "$TIMEOUT"
audit_warn "This audit calls real upstream account tests and may clear recoverable error/rate-limit state on success."

admin_bootstrap

query_url="$APP_BASE_URL/api/v1/admin/accounts?page=1&page_size=$(urlencode "$LIMIT")&sort_by=id&sort_order=desc"
if [ -n "$PLATFORM" ]; then
  query_url="$query_url&platform=$(urlencode "$PLATFORM")"
fi
if [ -n "$TYPE_FILTER" ]; then
  query_url="$query_url&type=$(urlencode "$TYPE_FILTER")"
fi
if [ -n "$STATUS_FILTER" ]; then
  query_url="$query_url&status=$(urlencode "$STATUS_FILTER")"
fi
if [ -n "$QUERY" ]; then
  query_url="$query_url&search=$(urlencode "$QUERY")"
fi

json="$(curl_body GET "$query_url" "$ADMIN_TOKEN")" || {
  audit_fail "accounts/list: $json"
  exit 1
}

if ! printf '%s' "$json" | jq -e '.code == 0 and (.data.items | type == "array")' >/dev/null; then
  audit_fail "accounts/list: unexpected response $(truncate "$json")"
  exit 1
fi

total="$(printf '%s' "$json" | jq -r '.data.total // (.data.items | length)')"
listed="$(printf '%s' "$json" | jq -r '.data.items | length')"
printf 'Listed %s/%s upstream accounts\n' "$listed" "$total"

pass_count=0
fail_count=0
skip_count=0

while IFS= read -r item; do
  id="$(printf '%s' "$item" | jq -r '.id // .account.id')"
  name="$(printf '%s' "$item" | jq -r '.name // .account.name // ""')"
  platform="$(printf '%s' "$item" | jq -r '.platform // .account.platform // ""')"
  account_type="$(printf '%s' "$item" | jq -r '.type // .account.type // ""')"
  status="$(printf '%s' "$item" | jq -r '.status // .account.status // ""')"
  schedulable="$(printf '%s' "$item" | jq -r '.schedulable // .account.schedulable // false')"
  group_count="$(printf '%s' "$item" | jq -r '(.group_ids // .account.group_ids // []) | length')"
  label="account#$id name=$name platform=$platform type=$account_type status=$status schedulable=$schedulable groups=$group_count"

  if [ "$INCLUDE_DISABLED" -eq 0 ] && { [ "$status" = "disabled" ] || [ "$status" = "inactive" ]; }; then
    audit_skip "$label reason=disabled"
    skip_count=$((skip_count + 1))
    continue
  fi

  body="$(
    jq -n \
      --arg model_id "$MODEL" \
      '{model_id: $model_id} | with_entries(select(.value != ""))'
  )"

  if sse="$(curl_body POST "$APP_BASE_URL/api/v1/admin/accounts/$id/test" "$ADMIN_TOKEN" "$body" "text/event-stream" 2>&1)"; then
    success="$(printf '%s\n' "$sse" | sed -n 's/^data:[[:space:]]*//p' | jq -r 'select(.type == "test_complete") | .success // false' 2>/dev/null | tail -n 1)"
    err_msg="$(printf '%s\n' "$sse" | sed -n 's/^data:[[:space:]]*//p' | jq -r 'select(.type == "error") | .error // empty' 2>/dev/null | tail -n 1)"
    content="$(printf '%s\n' "$sse" | sed -n 's/^data:[[:space:]]*//p' | jq -r 'select(.type == "content") | .text // empty' 2>/dev/null | tr -d '\n' || true)"
    if [ "$success" = "true" ] || [ -n "${content//[[:space:]]/}" ]; then
      audit_pass "$label"
      pass_count=$((pass_count + 1))
    else
      audit_fail "$label ${err_msg:-no test_complete success event}"
      fail_count=$((fail_count + 1))
    fi
  else
    audit_fail "$label $sse"
    fail_count=$((fail_count + 1))
  fi
done < <(printf '%s' "$json" | jq -c '.data.items[]')

printf 'SUMMARY upstream-accounts pass=%d fail=%d skip=%d listed=%s total=%s\n' "$pass_count" "$fail_count" "$skip_count" "$listed" "$total"

if [ "$fail_count" -gt 0 ]; then
  exit 1
fi

printf 'ALL PASSED\n'
