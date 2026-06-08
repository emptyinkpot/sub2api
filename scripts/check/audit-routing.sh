#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

LIMIT="${SUB2API_AUDIT_ROUTING_LIMIT:-500}"
KEY_QUERY=""
ACCOUNT_LIMIT="${SUB2API_AUDIT_ACCOUNT_LIMIT:-1000}"

usage() {
  cat <<'EOF'
Usage:
  scripts/check.sh --audit-routing [options]

Performs a read-only routing audit:
  1. Enumerates downstream consumer keys.
  2. Finds groups that are actually referenced by usable keys.
  3. Enumerates upstream accounts.
  4. Verifies each referenced group has at least one schedulable upstream account.

This is a routing health audit, not a weight/round-robin proof. It does not
mutate scheduler state or force traffic to specific accounts.

Options:
  --base-url URL       App base URL, e.g. https://sub2api.tengokukk.com
  --limit N            Max consumer keys to inspect, default 500
  --account-limit N    Max upstream accounts to inspect, default 1000
  --query TEXT         Filter consumer key name
  --timeout SEC        Per-request timeout
  -h, --help           Show this help

Environment:
  SUB2API_APP_BASE_URL, SUB2API_AUDIT_BASE_URL, SUB2API_AUDIT_TIMEOUT,
  SUB2API_AUDIT_ROUTING_LIMIT, SUB2API_AUDIT_ACCOUNT_LIMIT
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
    --account-limit)
      ACCOUNT_LIMIT="${2:?--account-limit requires a value}"
      shift 2
      ;;
    --query)
      KEY_QUERY="${2:?--query requires a value}"
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

audit_init_base_url
audit_require_tools

printf 'Sub2API routing audit app=%s key_limit=%s account_limit=%s timeout=%ss\n' "$APP_BASE_URL" "$LIMIT" "$ACCOUNT_LIMIT" "$TIMEOUT"
admin_bootstrap

keys_url="$APP_BASE_URL/api/v1/admin/consumer-keys?limit=$(urlencode "$LIMIT")"
if [ -n "$KEY_QUERY" ]; then
  keys_url="$keys_url&q=$(urlencode "$KEY_QUERY")"
fi

keys_json="$(curl_body GET "$keys_url" "$ADMIN_TOKEN")" || {
  audit_fail "consumer-keys/list: $keys_json"
  exit 1
}
if ! printf '%s' "$keys_json" | jq -e '.code == 0 and (.data.items | type == "array")' >/dev/null; then
  audit_fail "consumer-keys/list: unexpected response $(truncate "$keys_json")"
  exit 1
fi

accounts_url="$APP_BASE_URL/api/v1/admin/accounts?page=1&page_size=$(urlencode "$ACCOUNT_LIMIT")&sort_by=id&sort_order=desc"
accounts_json="$(curl_body GET "$accounts_url" "$ADMIN_TOKEN")" || {
  audit_fail "accounts/list: $accounts_json"
  exit 1
}
if ! printf '%s' "$accounts_json" | jq -e '.code == 0 and (.data.items | type == "array")' >/dev/null; then
  audit_fail "accounts/list: unexpected response $(truncate "$accounts_json")"
  exit 1
fi

readarray -t groups < <(
  printf '%s' "$keys_json" |
    jq -r '.data.items[] | select(.usable == true and .group_id != null) | [.group_id, (.group_name // ""), (.platform // "")] | @tsv' |
    sort -n -u
)

if [ "${#groups[@]}" -eq 0 ]; then
  audit_fail "routing: no usable consumer-key groups found"
  exit 1
fi

pass_count=0
fail_count=0

for row in "${groups[@]}"; do
  IFS=$'\t' read -r group_id group_name platform <<< "$row"
  label="group#$group_id name=$group_name platform=$platform"

  available="$(
    printf '%s' "$accounts_json" |
      jq --argjson gid "$group_id" '
        [
          .data.items[]
          | (.account // .) as $a
          | select(($a.group_ids // []) | index($gid))
          | select(($a.status // "") == "active")
          | select(($a.schedulable // false) == true)
          | select(($a.rate_limited_at // null) == null)
          | select(($a.overload_until // null) == null)
          | select(($a.temp_unschedulable_until // null) == null)
        ]'
  )"
  count="$(printf '%s' "$available" | jq -r 'length')"
  sample="$(printf '%s' "$available" | jq -r '.[0:5] | map("#" + ((.account // .).id | tostring) + ":" + ((.account // .).name // "")) | join(", ")')"
  if [ "$count" -gt 0 ]; then
    audit_pass "$label schedulable_accounts=$count sample=$sample"
    pass_count=$((pass_count + 1))
  else
    total_bound="$(
      printf '%s' "$accounts_json" |
        jq --argjson gid "$group_id" '[.data.items[] | (.account // .) as $a | select(($a.group_ids // []) | index($gid))] | length'
    )"
    audit_fail "$label schedulable_accounts=0 bound_accounts=$total_bound"
    fail_count=$((fail_count + 1))
  fi
done

printf 'SUMMARY routing groups_pass=%d groups_fail=%d groups_total=%d\n' "$pass_count" "$fail_count" "${#groups[@]}"

if [ "$fail_count" -gt 0 ]; then
  exit 1
fi

printf 'ALL PASSED\n'
