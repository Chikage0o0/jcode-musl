#!/usr/bin/env bash
set -euo pipefail

COMMON_SH_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

repo_root() {
  dirname -- "$COMMON_SH_DIR"
}

ensure_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "缺少命令: $cmd" >&2
      exit 1
    fi
  done
}

version_from_tag() {
  local tag="${1:-}"
  tag="${tag##refs/tags/}"
  tag="${tag#v}"
  if [ -z "$tag" ]; then
    echo "无法从空 tag 提取版本" >&2
    exit 1
  fi
  printf '%s\n' "$tag"
}

target_to_zig_target() {
  case "$1" in
    x86_64-unknown-linux-musl) printf '%s\n' 'x86_64-linux-musl' ;;
    aarch64-unknown-linux-musl) printf '%s\n' 'aarch64-linux-musl' ;;
    *)
      echo "不支持的 target: $1" >&2
      exit 1
      ;;
  esac
}

target_to_opkg_arch() {
  case "$1" in
    x86_64-unknown-linux-musl) printf '%s\n' 'x86_64' ;;
    aarch64-unknown-linux-musl) printf '%s\n' 'aarch64_generic' ;;
    *)
      echo "不支持的 target: $1" >&2
      exit 1
      ;;
  esac
}

target_to_apk_arch() {
  case "$1" in
    x86_64-unknown-linux-musl) printf '%s\n' 'x86_64' ;;
    aarch64-unknown-linux-musl) printf '%s\n' 'aarch64' ;;
    *)
      echo "不支持的 target: $1" >&2
      exit 1
      ;;
  esac
}

target_to_asset_arch() {
  case "$1" in
    x86_64-unknown-linux-musl) printf '%s\n' 'x86_64' ;;
    aarch64-unknown-linux-musl) printf '%s\n' 'aarch64' ;;
    *)
      echo "不支持的 target: $1" >&2
      exit 1
      ;;
  esac
}

target_env_key() {
  printf '%s\n' "$1" | tr '[:lower:]-.' '[:upper:]__'
}
