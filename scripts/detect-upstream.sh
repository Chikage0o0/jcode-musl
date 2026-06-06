#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

if [ "${1:-}" != "" ]; then
  printf '%s\n' "$1"
  exit 0
fi

ensure_cmd gh
gh release view --repo 1jehuang/jcode --json tagName --jq .tagName
