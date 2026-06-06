#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

if ! command -v apk >/dev/null 2>&1; then
  echo "缺少 apk 命令；请在 Alpine edge / apk-tools v3 环境中运行，或使用 workflow 内的容器步骤。" >&2
  exit 1
fi

if ! { apk mkpkg --help 2>&1 || true; } | grep -q 'Usage: apk mkpkg'; then
  echo "当前 apk 不支持 mkpkg；需要 apk-tools v3。" >&2
  exit 1
fi

ensure_cmd cp chmod mkdir mktemp touch

BIN="${1:?用法: package-apk.sh BIN TARGET TAG DISTDIR [PKGREL]}"
TARGET="${2:?用法: package-apk.sh BIN TARGET TAG DISTDIR [PKGREL]}"
TAG="${3:?用法: package-apk.sh BIN TARGET TAG DISTDIR [PKGREL]}"
DISTDIR="${4:?用法: package-apk.sh BIN TARGET TAG DISTDIR [PKGREL]}"
PKGREL="${5:-1}"

mkdir -p "$DISTDIR"
DISTDIR="$(CDPATH='' cd -- "$DISTDIR" && pwd)"

VERSION="$(version_from_tag "$TAG")"
ARCH="$(target_to_apk_arch "$TARGET")"
PKGVER="${VERSION}-r${PKGREL}"
OUTFILE="$DISTDIR/jcode-${VERSION}-r${PKGREL}.${ARCH}.apk"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/usr/bin"
cp "$BIN" "$STAGE/usr/bin/jcode"
chmod 0755 "$STAGE" "$STAGE/usr" "$STAGE/usr/bin" "$STAGE/usr/bin/jcode"
touch -t 197001010000.00 "$STAGE" "$STAGE/usr" "$STAGE/usr/bin" "$STAGE/usr/bin/jcode"

apk mkpkg \
  --compat 3.0 \
  --compression deflate:9 \
  --files "$STAGE" \
  --output "$OUTFILE" \
  --info "name:jcode" \
  --info "version:$PKGVER" \
  --info "description:Static musl build of jcode without default pdf/embeddings features" \
  --info "url:https://github.com/Chikage0o0/jcode-musl" \
  --info "arch:$ARCH" \
  --info "license:MIT" \
  --info "origin:jcode" \
  --info "maintainer:jcode-musl maintainers" \
  --info "depends:ca-certificates"

printf '%s\n' "$OUTFILE"
