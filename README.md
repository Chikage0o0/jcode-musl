# jcode-musl

这个仓库用于为上游 [`1jehuang/jcode`](https://github.com/1jehuang/jcode) 生成独立的 musl 静态发布产物，本仓库**不承载上游源码开发**，只负责：

- 同步上游 latest release/tag
- checkout 对应上游 tag
- 应用 musl 兼容 patch
- 以 `--no-default-features` 构建静态 `jcode`
- 产出 `tar.xz`、OpenWrt `opkg .ipk`、Alpine/apk-tools v3 `apk`
- 可手动触发发布，也可定时自动同步

## 构建定位

- 上游仓库：`1jehuang/jcode`
- 默认构建参数：`--no-default-features`
- **不包含** `pdf` / `embeddings`
- 目标平台：
  - `x86_64-unknown-linux-musl`
  - `aarch64-unknown-linux-musl`

这样可以尽量得到更小、依赖更少、适合容器/OpenWrt/Alpine 场景的静态二进制。

## 产物类型

每个上游 tag 默认生成以下产物：

- `jcode-<version>-<target>.tar.xz`
- `jcode_<version>-r<pkgrel>_<arch>.ipk`
- `jcode-<version>-r<pkgrel>.<arch>.apk`
- `SHA256SUMS`
- `jcode-<target>-buildinfo.json`

其中：

- `tar.xz`：仅包含一个 `jcode` 可执行文件
- `ipk`：适合 OpenWrt 手动安装
- `apk`：使用新版 `apk-tools v3` 的 `apk mkpkg` 生成

## Workflow

### 手动发布

执行 `.github/workflows/release.yml`：

- `upstream_tag`：必填，例如 `v0.23.0`
- `package_release`：包修订号，默认 `1`
- `publish`：默认 `true`，为 `false` 时只保留 draft release
- `overwrite_assets`：默认 `false`，若同名 release 已存在则直接失败

### 自动同步

`.github/workflows/sync.yml`：

- 每 6 小时检查一次上游 latest release
- 也支持手动触发并指定 `upstream_tag`
- 若本仓库已有同名 release，则直接退出
- 若没有，则触发 `release.yml`

## 安装示例

### tar.xz

```bash
tar -xJf jcode-0.23.0-x86_64-unknown-linux-musl.tar.xz
install -m 0755 jcode ~/.local/bin/jcode
```

### OpenWrt `.ipk`

```bash
opkg install ./jcode_0.23.0-r1_aarch64_generic.ipk
```

### Alpine `.apk`

当前默认是**未签名包**，安装时通常需要：

```bash
apk add --allow-untrusted ./jcode-0.23.0-r1.x86_64.apk
```

如果你自行签名，也可以接入自己的 key 流程后再分发。

## 体积优化策略

构建脚手架默认启用以下缩减策略：

- `--no-default-features`
- `profile = release-lto`
- `lto = fat`
- `opt-level = z`
- `panic = abort`
- `codegen-units = 1`
- `strip = symbols`
- 静态 musl 链接
- `tar.xz` 使用高压缩 `xz -9e`

明确**不使用 UPX**，避免启动/兼容性/误报问题。

## 已知限制

- `jcode` 的自更新逻辑仍可能指向上游 `1jehuang/jcode` release，而不是这个派生仓库。
- OpenWrt 的 `aarch64` 包按常见约定映射为 `aarch64_generic`。
- 本仓库只生成单独包文件，**不维护完整 OpenWrt feed/index**。
- Alpine `apk` 默认未签名，目标设备安装时通常需要 `--allow-untrusted`。
- `patches/0001-musl-malloc-gnu-only.patch` 主要作为兼容兜底；即使上游未来已修复，也可以继续保留。

## 仓库结构

- `patches/`：记录 musl 兼容 patch
- `scripts/`：checkout、patch、构建、校验、打包脚本
- `packaging/`：`opkg` / `apk` 元数据模板说明
- `.github/workflows/`：发布与同步自动化

## 本地脚本冒烟测试

```bash
bash scripts/test-scripts.sh
```

该测试不会真的构建上游，只验证脚本映射、patch 幂等性，以及 tar/ipk/apk 打包基本行为。
