#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

ensure_cmd tar gzip stat cp chmod mkdir mktemp python3

BIN="${1:?用法: package-opkg.sh BIN TARGET TAG DISTDIR [PKGREL]}"
TARGET="${2:?用法: package-opkg.sh BIN TARGET TAG DISTDIR [PKGREL]}"
TAG="${3:?用法: package-opkg.sh BIN TARGET TAG DISTDIR [PKGREL]}"
DISTDIR="${4:?用法: package-opkg.sh BIN TARGET TAG DISTDIR [PKGREL]}"
PKGREL="${5:-1}"

mkdir -p "$DISTDIR"
DISTDIR="$(CDPATH='' cd -- "$DISTDIR" && pwd)"

VERSION="$(version_from_tag "$TAG")"
ARCH="$(target_to_opkg_arch "$TARGET")"
PKGVER="${VERSION}-r${PKGREL}"
OUTFILE="$DISTDIR/jcode_${PKGVER}_${ARCH}.ipk"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/control" "$STAGE/data/usr/bin" "$STAGE/pkg"
cp "$BIN" "$STAGE/data/usr/bin/jcode"
chmod 0755 "$STAGE/data/usr/bin/jcode"
touch -d '@0' "$STAGE/data/usr/bin/jcode"

installed_bytes="$(stat -c '%s' "$STAGE/data/usr/bin/jcode")"
installed_size="$(( (installed_bytes + 1023) / 1024 ))"
cat > "$STAGE/control/control" <<EOF
Package: jcode
Version: $PKGVER
Architecture: $ARCH
Maintainer: jcode-musl maintainers
Section: utils
Priority: optional
License: MIT
Depends: ca-bundle
Installed-Size: $installed_size
Description: Static musl build of jcode without default pdf/embeddings features.
EOF
touch -d '@0' "$STAGE/control/control"

printf '2.0\n' > "$STAGE/pkg/debian-binary"
touch -d '@0' "$STAGE/pkg/debian-binary"

tar \
  --sort=name \
  --mtime='UTC 1970-01-01' \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  -czf "$STAGE/pkg/control.tar.gz" \
  -C "$STAGE/control" \
  control

tar \
  --sort=name \
  --mtime='UTC 1970-01-01' \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  -czf "$STAGE/pkg/data.tar.gz" \
  -C "$STAGE/data" \
  usr

rm -f "$OUTFILE"
python3 - "$OUTFILE" "$STAGE/pkg/debian-binary" "$STAGE/pkg/control.tar.gz" "$STAGE/pkg/data.tar.gz" <<'PY'
from __future__ import annotations

import pathlib
import sys

outfile = pathlib.Path(sys.argv[1])
members = [pathlib.Path(path) for path in sys.argv[2:]]

with outfile.open("wb") as fh:
    fh.write(b"!<arch>\n")
    for member in members:
        data = member.read_bytes()
        name = f"{member.name}/"
        if len(name) > 16:
            raise SystemExit(f"ar member name too long: {member.name}")
        header = (
            name.ljust(16)
            + "0".ljust(12)
            + "0".ljust(6)
            + "0".ljust(6)
            + "100644".ljust(8)
            + str(len(data)).ljust(10)
            + "`\n"
        )
        fh.write(header.encode("ascii"))
        fh.write(data)
        if len(data) % 2 == 1:
            fh.write(b"\n")
PY

printf '%s\n' "$OUTFILE"
