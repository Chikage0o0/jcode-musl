#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

ensure_cmd python3

SRC="${1:?用法: apply-patches.sh SRC}"

python3 - "$SRC" <<'PY'
from __future__ import annotations

import pathlib
import sys

src = pathlib.Path(sys.argv[1])
old = 'all(target_os = "linux", not(feature = "jemalloc"))'
new = 'all(target_os = "linux", target_env = "gnu", not(feature = "jemalloc"))'
targets = [
    src / 'src/main.rs',
    src / 'crates/jcode-base/src/embedding.rs',
]

for path in targets:
    if not path.is_file():
        raise SystemExit(f'缺少文件: {path}')

    content = path.read_text(encoding='utf-8')
    old_count = content.count(old)
    new_count = content.count(new)

    if old_count:
        content = content.replace(old, new)
        path.write_text(content, encoding='utf-8')
        print(f'patched {path.relative_to(src)} ({old_count} replacement(s))')
    elif new_count:
        print(f'already patched {path.relative_to(src)}')
    else:
        raise SystemExit(f'未识别的 cfg 模式: {path}')

    final = path.read_text(encoding='utf-8')
    if old in final:
        raise SystemExit(f'补丁未完全应用: {path}')
    if new not in final:
        raise SystemExit(f'补丁校验失败: {path}')
PY
