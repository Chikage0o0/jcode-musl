#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

ensure_cmd git

TAG="${1:?用法: checkout-upstream.sh TAG DEST}"
DEST="${2:?用法: checkout-upstream.sh TAG DEST}"
PARENT="$(dirname -- "$DEST")"

mkdir -p "$PARENT"

if [ -d "$DEST/.git" ]; then
  git -C "$DEST" remote set-url origin https://github.com/1jehuang/jcode.git
else
  rm -rf "$DEST"
  git clone --filter=blob:none --no-checkout https://github.com/1jehuang/jcode.git "$DEST" >/dev/null 2>&1
fi

git -C "$DEST" fetch --force --tags --depth 1 origin "refs/tags/$TAG:refs/tags/$TAG" >/dev/null 2>&1
git -C "$DEST" checkout --force --detach "refs/tags/$TAG" >/dev/null 2>&1
git -C "$DEST" submodule update --init --recursive --depth 1 >/dev/null 2>&1 || true
git -C "$DEST" rev-parse HEAD
