#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

ensure_cmd tar xz cp chmod mkdir mktemp

BIN="${1:?用法: package-tar.sh BIN TARGET TAG DISTDIR}"
TARGET="${2:?用法: package-tar.sh BIN TARGET TAG DISTDIR}"
TAG="${3:?用法: package-tar.sh BIN TARGET TAG DISTDIR}"
DISTDIR="${4:?用法: package-tar.sh BIN TARGET TAG DISTDIR}"

mkdir -p "$DISTDIR"
DISTDIR="$(CDPATH='' cd -- "$DISTDIR" && pwd)"

VERSION="$(version_from_tag "$TAG")"
ARCHIVE="$DISTDIR/jcode-$VERSION-$TARGET.tar.xz"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp "$BIN" "$STAGE/jcode"
chmod 0755 "$STAGE/jcode"
touch -d '@0' "$STAGE/jcode"

tar \
  --sort=name \
  --mtime='UTC 1970-01-01' \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  -cf - \
  -C "$STAGE" \
  jcode | xz -T0 -9e > "$ARCHIVE"

printf '%s\n' "$ARCHIVE"
