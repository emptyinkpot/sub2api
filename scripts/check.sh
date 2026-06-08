#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${BASH:-}" == */* ]]; then
  BASH_BIN_DIR="${BASH%/*}"
  case ":$PATH:" in
    *":$BASH_BIN_DIR:"*) ;;
    *) PATH="$BASH_BIN_DIR:$PATH"; export PATH ;;
  esac
fi

SCRIPT_SOURCE="${BASH_SOURCE[0]}"
SCRIPT_SOURCE_DIR="${SCRIPT_SOURCE%/*}"
if [ "$SCRIPT_SOURCE_DIR" = "$SCRIPT_SOURCE" ]; then
  SCRIPT_SOURCE_DIR="."
fi
SCRIPT_DIR="$(cd "$SCRIPT_SOURCE_DIR" && pwd)"
CHECK_DIR="$SCRIPT_DIR/check"

usage() {
  printf '%s\n' \
'Usage:' \
'  scripts/check.sh [mode] [options]' \
'' \
'Modes:' \
'  --smoke           Deployment acceptance; default when no mode is provided' \
'  --release         Release acceptance against the deployed server image' \
'  --audit-keys      Audit all downstream consumer keys' \
'  --audit-upstream  Audit all upstream accounts/providers' \
'  --audit-routing   Audit routing health for consumer-key groups' \
'  --full            Run smoke, key audit, upstream audit, and routing audit' \
'' \
'Examples:' \
'  scripts/check.sh' \
'  scripts/check.sh --release --full' \
'  scripts/check.sh --smoke --full' \
'  scripts/check.sh --audit-keys --models-only' \
'  scripts/check.sh --audit-upstream --platform openai' \
'  scripts/check.sh --audit-routing' \
'  scripts/check.sh --full --base-url https://sub2api.tengokukk.com' \
'' \
'Notes:' \
'  --release validates the Coolify-deployed server image over real HTTP.' \
'  --full at top level means "run every check module".' \
'  To run the full smoke profile only, use: scripts/check.sh --smoke --full' \
'  Top-level --full accepts only options shared by every module: --base-url and --timeout.'
}

run_module() {
  local module="$1"
  shift
  local path="$CHECK_DIR/$module"
  if [ ! -f "$path" ]; then
    echo "Missing check module: $path" >&2
    exit 2
  fi
  "${BASH:-bash}" "$path" "$@"
}

run_full() {
  local shared_args=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --base-url|--timeout)
        shared_args+=("$1" "${2:?$1 requires a value}")
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unsupported top-level --full option: $1" >&2
        echo "Use module mode for module-specific options, e.g. scripts/check.sh --audit-keys --models-only" >&2
        exit 2
        ;;
    esac
  done

  run_module smoke.sh --full "${shared_args[@]}"
  run_module audit-keys.sh "${shared_args[@]}"
  run_module audit-upstream.sh "${shared_args[@]}"
  run_module audit-routing.sh "${shared_args[@]}"
}

if [ "$#" -eq 0 ]; then
  run_module smoke.sh
  exit 0
fi

mode="$1"
shift

case "$mode" in
  --release)
    run_module release.sh "$@"
    ;;
  --smoke)
    run_module smoke.sh "$@"
    ;;
  --audit-keys)
    run_module audit-keys.sh "$@"
    ;;
  --audit-upstream)
    run_module audit-upstream.sh "$@"
    ;;
  --audit-routing)
    run_module audit-routing.sh "$@"
    ;;
  --full)
    run_full "$@"
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "Unknown mode: $mode" >&2
    usage >&2
    exit 2
    ;;
esac
