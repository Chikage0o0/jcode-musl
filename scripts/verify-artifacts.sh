#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

SUBCOMMAND="${1:?用法: verify-artifacts.sh <features|binary> ...}"
shift

verify_features() {
  ensure_cmd cargo mktemp
  local src="$1"
  local target="$2"
  local output
  local tmp_dir
  local stdout_file
  local stderr_file
  local status

  tmp_dir="$(mktemp -d)"
  stdout_file="$tmp_dir/cargo-tree.stdout"
  stderr_file="$tmp_dir/cargo-tree.stderr"

  if (cd "$src" && cargo tree -e features,no-dev -p jcode --target "$target" --locked --no-default-features >"$stdout_file" 2>"$stderr_file"); then
    output="$(<"$stdout_file")"
  else
    status=$?
    echo "cargo tree 执行失败" >&2
    echo '--- cargo tree stdout ---' >&2
    [ ! -s "$stdout_file" ] || cat "$stdout_file" >&2
    echo '--- cargo tree stderr ---' >&2
    [ ! -s "$stderr_file" ] || cat "$stderr_file" >&2
    rm -rf "$tmp_dir"
    return "$status"
  fi

  rm -rf "$tmp_dir"

  case "$output" in
    *jcode-embedding*|*jcode-pdf*|*tokenizers*|*pdf-extract*)
      echo "$output" >&2
      echo "检测到被禁用的特性/依赖仍在构建图中" >&2
      exit 1
      ;;
  esac

  printf 'OK: %s 未启用 pdf/embeddings 相关依赖\n' "$target"
}

verify_binary() {
  ensure_cmd file readelf
  local bin="$1"
  local target="$2"
  local file_output
  local header_output
  local dynamic_output

  [ -f "$bin" ] || { echo "缺少二进制: $bin" >&2; exit 1; }

  file_output="$(file "$bin")"
  header_output="$(readelf -h "$bin")"

  case "$target" in
    x86_64-unknown-linux-musl)
      case "$file_output" in
        *x86-64*|*x86_64*) ;;
        *) echo "$file_output" >&2; echo "二进制架构校验失败" >&2; exit 1 ;;
      esac
      ;;
    aarch64-unknown-linux-musl)
      case "$file_output" in
        *aarch64*|*ARM\ aarch64*|*ARM64*) ;;
        *) echo "$file_output" >&2; echo "二进制架构校验失败" >&2; exit 1 ;;
      esac
      ;;
    *)
      echo "不支持的 target: $target" >&2
      exit 1
      ;;
  esac

  if readelf -l "$bin" | grep -q 'Requesting program interpreter'; then
    echo "检测到 INTERP 段，二进制不是纯静态" >&2
    exit 1
  fi

  dynamic_output="$(readelf -d "$bin" 2>&1 || true)"
  case "$dynamic_output" in
    *NEEDED*|*Shared\ library*)
      echo "$dynamic_output" >&2
      echo "检测到动态依赖" >&2
      exit 1
      ;;
  esac

  case "$target" in
    x86_64-unknown-linux-musl)
      "$bin" --version >/dev/null
      ;;
    aarch64-unknown-linux-musl)
      if command -v qemu-aarch64 >/dev/null 2>&1; then
        qemu-aarch64 "$bin" --version >/dev/null
      elif command -v qemu-aarch64-static >/dev/null 2>&1; then
        qemu-aarch64-static "$bin" --version >/dev/null
      else
        echo "警告: 未找到 qemu-aarch64，跳过 aarch64 --version 运行校验" >&2
      fi
      ;;
  esac

  printf '%s\n' "$file_output"
  printf '%s\n' "$header_output"
}

case "$SUBCOMMAND" in
  features)
    verify_features "$@"
    ;;
  binary)
    verify_binary "$@"
    ;;
  *)
    echo "未知子命令: $SUBCOMMAND" >&2
    exit 1
    ;;
esac
