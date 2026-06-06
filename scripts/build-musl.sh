#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

ensure_cmd cargo rustc zig python3 cp chmod mkdir

SRC="${1:?用法: build-musl.sh SRC TARGET OUTDIR}"
TARGET="${2:?用法: build-musl.sh SRC TARGET OUTDIR}"
OUTDIR="${3:?用法: build-musl.sh SRC TARGET OUTDIR}"

REPO_ROOT="$(repo_root)"
WORKDIR="$REPO_ROOT/work/toolchains/$TARGET"
mkdir -p "$WORKDIR" "$OUTDIR"

ZIG_TARGET="$(target_to_zig_target "$TARGET")"
TARGET_CC_KEY="${TARGET//-/_}"
TARGET_CARGO_KEY="$(target_env_key "$TARGET")"
HOST_TRIPLE="$(rustc -vV | awk '/^host: / { print $2 }')"
SYSROOT="$(rustc --print sysroot)"
RUST_LLD="$SYSROOT/lib/rustlib/$HOST_TRIPLE/bin/rust-lld"
RUST_LLVM_STRIP="$SYSROOT/lib/rustlib/$HOST_TRIPLE/bin/llvm-strip"

if [ ! -x "$RUST_LLD" ]; then
  echo "找不到 rust-lld: $RUST_LLD" >&2
  exit 1
fi

cat > "$WORKDIR/zig-cc" <<EOF
#!/usr/bin/env bash
set -euo pipefail
args=()
skip_next=0
for arg in "\$@"; do
  if [ "\$skip_next" -eq 1 ]; then
    skip_next=0
    continue
  fi
  case "\$arg" in
    --target=*|-target=*)
      continue
      ;;
    --target|-target)
      skip_next=1
      continue
      ;;
    -Wp,-U_FORTIFY_SOURCE)
      args+=("-U_FORTIFY_SOURCE")
      ;;
    *)
      args+=("\$arg")
      ;;
  esac
done
args+=("-fno-sanitize=undefined")
exec zig cc -target "$ZIG_TARGET" "\${args[@]}"
EOF

cat > "$WORKDIR/zig-cxx" <<EOF
#!/usr/bin/env bash
set -euo pipefail
args=()
skip_next=0
for arg in "\$@"; do
  if [ "\$skip_next" -eq 1 ]; then
    skip_next=0
    continue
  fi
  case "\$arg" in
    --target=*|-target=*)
      continue
      ;;
    --target|-target)
      skip_next=1
      continue
      ;;
    -Wp,-U_FORTIFY_SOURCE)
      args+=("-U_FORTIFY_SOURCE")
      ;;
    *)
      args+=("\$arg")
      ;;
  esac
done
args+=("-fno-sanitize=undefined")
exec zig c++ -target "$ZIG_TARGET" "\${args[@]}"
EOF

cat > "$WORKDIR/zig-ar" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec zig ar "$@"
EOF

cat > "$WORKDIR/zig-ranlib" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec zig ranlib "$@"
EOF

chmod +x "$WORKDIR/zig-cc" "$WORKDIR/zig-cxx" "$WORKDIR/zig-ar" "$WORKDIR/zig-ranlib"

export CARGO_INCREMENTAL=0

# Cargo 环境变量无法可靠表达带连字符的 profile 名（`release-lto` 会被拆成
# `profile.release.lto...`）。这里用 `--config` 覆盖上游 profile，避免 CI
# 在解析 `CARGO_PROFILE_RELEASE_LTO_*` 时误认为存在 `profile.release` 对象。
PROFILE_CONFIG=(
  --config 'profile.release-lto.opt-level="z"'
  --config 'profile.release-lto.lto="fat"'
  --config 'profile.release-lto.codegen-units=1'
  --config 'profile.release-lto.panic="abort"'
  --config 'profile.release-lto.strip="symbols"'
  --config 'profile.release-lto.incremental=false'
)

export "CC_${TARGET_CC_KEY}=$WORKDIR/zig-cc"
export "CXX_${TARGET_CC_KEY}=$WORKDIR/zig-cxx"
export "AR_${TARGET_CC_KEY}=$WORKDIR/zig-ar"
export "RANLIB_${TARGET_CC_KEY}=$WORKDIR/zig-ranlib"
export "CARGO_TARGET_${TARGET_CARGO_KEY}_AR=$WORKDIR/zig-ar"
export "CARGO_TARGET_${TARGET_CARGO_KEY}_LINKER=$RUST_LLD"
export PKG_CONFIG_ALLOW_CROSS=1
export PKG_CONFIG_ALL_STATIC=1

export "CARGO_TARGET_${TARGET_CARGO_KEY}_RUSTFLAGS=-C target-feature=+crt-static -C linker-flavor=ld.lld -C link-self-contained=yes -C strip=symbols"

(
  cd "$SRC"
  cargo build \
    "${PROFILE_CONFIG[@]}" \
    --locked \
    --profile release-lto \
    --target "$TARGET" \
    --no-default-features \
    -p jcode \
    --bin jcode
)

BIN_SRC="$SRC/target/$TARGET/release-lto/jcode"
if [ ! -f "$BIN_SRC" ]; then
  echo "未找到构建产物: $BIN_SRC" >&2
  exit 1
fi

if [ -x "$RUST_LLVM_STRIP" ]; then
  "$RUST_LLVM_STRIP" --strip-all "$BIN_SRC"
elif command -v llvm-strip >/dev/null 2>&1; then
  llvm-strip --strip-all "$BIN_SRC"
fi

cp "$BIN_SRC" "$OUTDIR/jcode-$TARGET"
chmod +x "$OUTDIR/jcode-$TARGET"
