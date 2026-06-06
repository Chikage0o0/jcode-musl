#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

ensure_cmd git rustc python3 mkdir

SRC="${1:?用法: make-buildinfo.sh SRC TAG OUTFILE}"
TAG="${2:?用法: make-buildinfo.sh SRC TAG OUTFILE}"
OUTFILE="${3:?用法: make-buildinfo.sh SRC TAG OUTFILE}"

mkdir -p "$(dirname -- "$OUTFILE")"

UPSTREAM_COMMIT="$(git -C "$SRC" rev-parse HEAD)"
RUSTC_VERSION="$(rustc --version)"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python3 - "$TAG" "$UPSTREAM_COMMIT" "$RUSTC_VERSION" "$TIMESTAMP" "$OUTFILE" <<'PY'
import json
import sys

tag, commit, rustc_version, timestamp, outfile = sys.argv[1:6]
payload = {
    "upstream_repo": "1jehuang/jcode",
    "tag": tag,
    "commit": commit,
    "features": "--no-default-features",
    "targets": [
        "x86_64-unknown-linux-musl",
        "aarch64-unknown-linux-musl",
    ],
    "optimization": {
        "profile": "release-lto",
        "lto": "fat",
        "opt_level": "z",
        "panic": "abort",
        "codegen_units": 1,
        "strip": "symbols",
        "incremental": False,
    },
    "rustc": rustc_version,
    "built_at_utc": timestamp,
}

with open(outfile, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY
