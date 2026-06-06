#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

ensure_cmd bash python3 tar gzip

ROOT="$(repo_root)"
TMP_ROOT="$ROOT/tmp/test-scripts"
rm -rf "$TMP_ROOT"
mkdir -p "$TMP_ROOT"
trap 'rm -rf "$TMP_ROOT"' EXIT

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [ "$expected" != "$actual" ]; then
    echo "断言失败: $message" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    exit 1
  fi
}

assert_file() {
  local path="$1"
  [ -f "$path" ] || { echo "缺少文件: $path" >&2; exit 1; }
}

test_common_helpers() {
  assert_eq "1.2.3" "$(version_from_tag v1.2.3)" "version_from_tag strips leading v"
  assert_eq "1.2.3" "$(version_from_tag 1.2.3)" "version_from_tag keeps raw version"
  assert_eq "x86_64-linux-musl" "$(target_to_zig_target x86_64-unknown-linux-musl)" "zig target mapping"
  assert_eq "aarch64_generic" "$(target_to_opkg_arch aarch64-unknown-linux-musl)" "opkg arch mapping"
  assert_eq "aarch64" "$(target_to_apk_arch aarch64-unknown-linux-musl)" "apk arch mapping"
  assert_eq "X86_64_UNKNOWN_LINUX_MUSL" "$(target_env_key x86_64-unknown-linux-musl)" "target env key"
}

write_old_fixture() {
  local dir="$1"
  mkdir -p "$dir/src" "$dir/crates/jcode-base/src"
  cat > "$dir/src/main.rs" <<'EOF'
use anyhow::Result;

#[cfg(all(target_os = "linux", not(feature = "jemalloc")))]
fn configure_system_allocator() {
    unsafe extern "C" {
        fn mallopt(param: i32, value: i32) -> i32;
    }
}

#[cfg(not(all(target_os = "linux", not(feature = "jemalloc"))))]
fn configure_system_allocator() {}

fn main() -> Result<()> {
    Ok(())
}
EOF
  cat > "$dir/crates/jcode-base/src/embedding.rs" <<'EOF'
#[cfg(all(target_os = "linux", not(feature = "jemalloc")))]
fn trim_one() {}

#[cfg(all(target_os = "linux", not(feature = "jemalloc")))]
fn trim_two() {}
EOF
}

write_fixed_fixture() {
  local dir="$1"
  mkdir -p "$dir/src" "$dir/crates/jcode-base/src"
  cat > "$dir/src/main.rs" <<'EOF'
use anyhow::Result;

#[cfg(all(target_os = "linux", target_env = "gnu", not(feature = "jemalloc")))]
fn configure_system_allocator() {
    unsafe extern "C" {
        fn mallopt(param: i32, value: i32) -> i32;
    }
}

#[cfg(not(all(target_os = "linux", target_env = "gnu", not(feature = "jemalloc"))))]
fn configure_system_allocator() {}

fn main() -> Result<()> {
    Ok(())
}
EOF
  cat > "$dir/crates/jcode-base/src/embedding.rs" <<'EOF'
#[cfg(all(target_os = "linux", target_env = "gnu", not(feature = "jemalloc")))]
fn trim_one() {}

#[cfg(all(target_os = "linux", target_env = "gnu", not(feature = "jemalloc")))]
fn trim_two() {}
EOF
}

test_apply_patches() {
  local old_dir="$TMP_ROOT/fixture-old"
  local fixed_dir="$TMP_ROOT/fixture-fixed"
  write_old_fixture "$old_dir"
  write_fixed_fixture "$fixed_dir"

  bash "$SCRIPT_DIR/apply-patches.sh" "$old_dir"
  bash "$SCRIPT_DIR/apply-patches.sh" "$old_dir"
  bash "$SCRIPT_DIR/apply-patches.sh" "$fixed_dir"

  python3 - "$old_dir" "$fixed_dir" <<'PY'
import pathlib
import sys

for root in map(pathlib.Path, sys.argv[1:]):
    data = (root / "src/main.rs").read_text(encoding="utf-8") + (root / "crates/jcode-base/src/embedding.rs").read_text(encoding="utf-8")
    assert 'target_env = "gnu"' in data
    assert 'all(target_os = "linux", not(feature = "jemalloc"))' not in data
PY
}

test_tar_and_ipk() {
  local fake_bin="$TMP_ROOT/fake-jcode"
  local dist_dir="$TMP_ROOT/dist"
  local unpack_dir="$TMP_ROOT/unpack"
  mkdir -p "$dist_dir" "$unpack_dir"

  cat > "$fake_bin" <<'EOF'
#!/usr/bin/env sh
echo "jcode 0.0.0"
EOF
  chmod +x "$fake_bin"

  local tar_path
  tar_path="$(bash "$SCRIPT_DIR/package-tar.sh" "$fake_bin" x86_64-unknown-linux-musl v0.0.0 "$dist_dir")"
  assert_file "$tar_path"
  tar -xJf "$tar_path" -C "$unpack_dir"
  assert_file "$unpack_dir/jcode"

  local ipk_path
  ipk_path="$(bash "$SCRIPT_DIR/package-opkg.sh" "$fake_bin" aarch64-unknown-linux-musl v0.0.0 "$dist_dir" 7)"
  assert_file "$ipk_path"

  mkdir -p "$TMP_ROOT/ipk"
  python3 - "$ipk_path" "$TMP_ROOT/ipk" <<'PY'
from __future__ import annotations

import pathlib
import sys

archive = pathlib.Path(sys.argv[1])
dest = pathlib.Path(sys.argv[2])
data = archive.read_bytes()
if not data.startswith(b"!<arch>\n"):
    raise SystemExit("invalid ar archive")

offset = 8
while offset < len(data):
    header = data[offset:offset + 60]
    if len(header) < 60:
        break
    name = header[:16].decode("ascii").strip()
    size = int(header[48:58].decode("ascii").strip())
    payload_start = offset + 60
    payload_end = payload_start + size
    payload = data[payload_start:payload_end]
    clean_name = name.rstrip("/")
    (dest / clean_name).write_bytes(payload)
    offset = payload_end + (size % 2)
PY
  (
    cd "$TMP_ROOT/ipk"
    tar -xzf data.tar.gz
    tar -xzf control.tar.gz
  )
  assert_file "$TMP_ROOT/ipk/usr/bin/jcode"
  if ! grep -q '^Architecture: aarch64_generic$' "$TMP_ROOT/ipk/control"; then
    echo "ipk control 缺少 aarch64_generic 架构" >&2
    exit 1
  fi
}

test_apk_optional() {
  local fake_bin="$TMP_ROOT/fake-jcode-apk"
  local dist_dir="$TMP_ROOT/apk-dist"
  mkdir -p "$dist_dir"
  printf '#!/usr/bin/env sh\necho jcode\n' > "$fake_bin"
  chmod +x "$fake_bin"

  if command -v apk >/dev/null 2>&1 && { apk mkpkg --help 2>&1 || true; } | grep -q 'Usage: apk mkpkg'; then
    local apk_path
    apk_path="$(bash "$SCRIPT_DIR/package-apk.sh" "$fake_bin" x86_64-unknown-linux-musl v0.0.0 "$dist_dir" 3)"
    assert_file "$apk_path"
  else
    echo "SKIP: 未检测到 apk mkpkg，跳过 apk 打包测试"
  fi
}

test_verify_features_ignores_cargo_stderr() {
  local fake_root="$TMP_ROOT/verify-features"
  local fake_src="$fake_root/src"
  local fake_bin_dir="$fake_root/bin"
  local output
  mkdir -p "$fake_src" "$fake_bin_dir"

  cat > "$fake_bin_dir/cargo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "tree" ]; then
  printf 'jcode v0.0.0\n└── anyhow v1.0.100\n'
  printf 'Downloaded tokenizers v0.21.4\n' >&2
  printf 'Downloaded pdf-extract v0.8.2\n' >&2
  exit 0
fi

echo "unexpected cargo args: $*" >&2
exit 1
EOF
  chmod +x "$fake_bin_dir/cargo"

  if ! output="$(PATH="$fake_bin_dir:$PATH" bash "$SCRIPT_DIR/verify-artifacts.sh" features "$fake_src" x86_64-unknown-linux-musl 2>&1)"; then
    echo "verify-artifacts.sh features 误判了 cargo stderr" >&2
    echo "$output" >&2
    exit 1
  fi

  case "$output" in
    *"OK: x86_64-unknown-linux-musl 未启用 pdf/embeddings 相关依赖"*) ;;
    *)
      echo "verify-artifacts.sh features 误判了 cargo stderr" >&2
      echo "$output" >&2
      exit 1
      ;;
  esac
}

test_common_helpers
test_apply_patches
test_tar_and_ipk
test_apk_optional
test_verify_features_ignores_cargo_stderr

echo "OK: scripts smoke tests passed"
