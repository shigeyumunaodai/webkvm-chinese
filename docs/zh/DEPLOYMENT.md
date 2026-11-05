# WebKVM 完整中文部署说明

> 适用版本：v0.1.9（以仓库当前 `main` 分支实际代码为准）  
> 目标读者：首次在 Linux 宿主机上部署 WebKVM 的运维人员。  
> 文档入口：[中文文档索引](README.md) · [English README](../../README.md) · [Español README](../../README.es.md) · [简体中文 README](../../README.zh.md)

本文所有命令、参数、路径与环境变量均已对照仓库中的安装脚本（`packaging/standalone/install.sh`、`scripts/install-webkvm.sh`、`scripts/setup-network.sh`、`docker-compose.yml`、`.env.example`）核对。命令可直接复制执行；标注 `sudo` 的命令需要 root 权限。

---

## 目录

1. [项目简介与组件架构](#1-项目简介与组件架构)
2. [环境要求与部署前检查](#2-环境要求与部署前检查)
3. [中国大陆网络准备](#3-中国大陆网络准备)
4. [安装方式](#4-安装方式)
5. [安装过程交互项说明与无人值守](#5-安装过程交互项说明与无人值守)
6. [首次登录与初始化](#6-首次登录与初始化)
7. [网络模式与 bridge/NAT 详解](#7-网络模式与-bridgenat-详解)
8. [创建第一台虚拟机 / 容器](#8-创建第一台虚拟机--容器)
9. [存储池 / ISO / 卷 / 备份目标配置](#9-存储池--iso--卷--备份目标配置)
10. [备份、恢复与保留策略](#10-备份恢复与保留策略)
11. [升级、回滚、卸载](#11-升级回滚卸载)
12. [安全加固](#12-安全加固)
13. [故障排查](#13-故障排查)
14. [附录](#14-附录)

---

## 1. 项目简介与组件架构

**WebKVM** 把一台现成的 Linux 服务器（Ubuntu、Debian、Fedora、Arch、AlmaLinux、Rocky 及其衍生版）变成本地私有云虚拟化平台：**不重装系统、不接管操作系统**，1 分钟内即可在浏览器中管理 **QEMU/KVM 虚拟机**与 **Incus/LXC 系统容器**。

核心特征：

- **单二进制**：Go 后端（CGO 绑定 `libvirt`）+ 内嵌 Svelte 5 前端，编译产物约 14 MB，空闲内存约 15 MB。
- **单端口**：Web UI、REST API、SSE、WebSocket（noVNC / 串口终端）全部通过 **8080** 端口提供（默认 HTTPS）。
- **统一管理**：KVM 虚拟机与 Incus 容器出现在同一个列表、同一套控制台与指标体系中。
- **状态即文件**：所有应用状态（用户、配置、密钥、备份注册表）都是 `DATA_DIR`（默认 `/opt/webkvm`）下的 JSON 文件，无外部数据库。

组件架构：

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                             WebKVM Web 界面                             │
│                   Svelte 5 • Tailwind v4 • WebGL 终端                   │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │ HTTPS / WSS / REST
┌────────────────────────────────────▼────────────────────────────────────┐
│                     WebKVM 服务端（单一 Go 二进制）                     │
│        认证 / JWT • WebSocket 代理 • 镜像中心 • 防火墙 • 存储池         │
└──────────────────┬──────────────────────────────────┬───────────────────┘
                   │ CGO / Unix Socket                │ REST / Unix Socket
┌──────────────────▼──────────────┐ ┌─────────────────▼───────────────────┐
│           QEMU / KVM            │ │             Incus / LXD             │
│           硬件虚拟化            │ │            LXC 系统容器             │
│  (Ubuntu, Windows, FreeBSD...)  │ │     (Alpine, Debian, Ubuntu...)     │
└─────────────────────────────────┘ └─────────────────────────────────────┘
```

各组件职责：

| 组件 | 说明 |
|---|---|
| `webkvm` 主二进制 | 后端 API + 内嵌前端，生产环境唯一进程；由 systemd 服务 `webkvm.service` 以 root 运行。 |
| `libvirtd` / `virtqemud` | KVM 虚拟机的真正管理者；WebKVM 通过 `qemu:///system` 连接（安装器会启用并启动它）。 |
| QEMU/KVM | 虚拟机监控器，要求宿主存在 `/dev/kvm`。 |
| Incus（可选） | 容器守护进程；安装器默认安装并启用，WebKVM 通过 Incus unix socket 通信（兼容旧 LXD）。 |
| `webkvm-cli` | 纯 Go 命令行工具，装在 `/usr/local/bin/webkvm-cli`；在宿主机以 root 运行时**零令牌**自动认证。 |
| `webkvm.service` | systemd 单元，位于 `/etc/systemd/system/webkvm.service`。 |
| `DATA_DIR`（默认 `/opt/webkvm`） | 唯一状态目录：用户、配置、证书、存储池、审计日志等。 |

三个平面：

1. **控制面**：Go 后端编排 libvirt/Incus 并对外提供 REST/WebSocket/SSE。
2. **数据面**：libvirt + QEMU/KVM 与 Incus 守护进程，虚拟机/容器真正运行在这里。
3. **状态面**：`DATA_DIR` 下的 JSON 文件，保存应用配置与元数据。

> 与 Proxmox VE 的差异：WebKVM 不接管操作系统、不依赖定制发行版，也不要求独占整机；它对宿主现有的发行版、桌面环境和其他 libvirt 使用方保持共存。

---

## 2. 环境要求与部署前检查

### 2.1 硬性与软件要求

| 项目 | 要求 | 说明 |
|---|---|---|
| 权限 | root / `sudo` | 安装、网络配置、systemd 单元均需 root。 |
| 操作系统 | Debian/Ubuntu 系（apt）、Fedora/RHEL 系（dnf/yum）、Arch 系（pacman） | 安装器按**包管理器**自动识别，不依赖发行版 ID 列表。 |
| CPU 架构 | **amd64 / x86_64** | 当前发布的安装器与二进制只支持 amd64；ARM64 需自行交叉编译（README/FAQ 提及能力，但官方发布未提供）。 |
| 虚拟化 | `/dev/kvm` 存在 | 需在 BIOS/UEFI 开启 Intel VT-x / AMD-V；若宿主本身是虚拟机，需在上级宿主机开启嵌套虚拟化。 |
| 内存 | ≥ **2 GiB** | 安装器读取 `/proc/meminfo` 的 `MemTotal` 校验（≥ 2097152 KiB）。 |
| 磁盘 | `DATA_DIR` 所在文件系统 ≥ **5 GiB** 可用 | 安装器用 `df -Pk` 校验（≥ 5242880 KiB）。镜像与虚拟磁盘会持续占用空间，生产环境建议单独挂载大盘。 |
| systemd | 必须 | 安装器与所有网络/服务持久化都依赖 systemd。 |
| 网络 | 至少一条可用路由（可出网更佳） | 安装器用 `ip route get` 探测 1.1.1.1/8.8.8.8/9.9.9.9，无路由会中止；在线安装还需能访问软件源与 GitHub。 |
| 端口 | **8080/tcp** 空闲 | 安装器在装包前就用 `ss -ltn` 检查，被占用会立即报错退出。启用 Let's Encrypt 时还需 80/443 对公网可达。 |
| 工具 | `curl`、`tar` | 一键脚本要求；独立安装器另需 `python3`、`openssl`、`virsh`、`qemu-img`、`zstd` 等（由安装器安装）。 |

> 关于最低发行版版本：仓库内 `docs/INSTALLATION.md` 标注 Debian 13+、Ubuntu 24+、Fedora 43/44、Arch；`Makefile` 注释标注 Debian 12+、Ubuntu 22.04+、Fedora 36+、RHEL 9。共性硬性条件是 **GLIBC ≥ 2.34 与 `libvirt.so.0`**。安装器在部署前会用 `ldd` 检查二进制动态链接兼容性，不兼容会明确报错而不是留下坏服务。

> 磁盘格式要求：KVM 安装需要 libvirt、QEMU、OVMF、swtpm 等运行时软件包；安装器会自动安装，**不要在目标服务器上编译**（无需 Go/Node）。

### 2.2 部署前检查清单（复制执行）

```bash
# 1) 当前用户与权限（普通用户需全程加 sudo）
id -u

# 2) KVM 是否可用
ls -l /dev/kvm
# 预期类似：crw-rw---- 1 root kvm 10, 232 ... /dev/kvm

# 3) 内存（安装器要求 >= 2 GiB）
awk '/MemTotal/ {printf "MemTotal: %.2f GiB\n", $2/1024/1024}' /proc/meminfo

# 4) 数据目录所在文件系统可用空间（安装器要求 >= 5 GiB）
df -h /opt

# 5) 架构
uname -m
# 预期：x86_64

# 6) systemd
systemctl --version | head -1

# 7) 网络路由
ip route get 1.1.1.1

# 8) 8080 端口是否空闲
ss -ltn 'sport = :8080' || true
# 预期：无输出（即端口空闲）

# 9) 出网情况（在线安装必需）
curl -sI -m 10 https://raw.githubusercontent.com/Slaker19/webkvm/main/scripts/install-webkvm.sh | head -1
curl -sI -m 10 https://api.github.com/repos/Slaker19/webkvm/releases/latest | head -1
# 预期：HTTP/2 200（国内网络超时见第 3 节与 CHINA-NETWORK.md）
```

全部通过后再开始安装。任何一项失败，请先按第 13 节「故障排查」处理，不要强行继续。

---

## 3. 中国大陆网络准备

WebKVM 安装过程会大量访问境外资源：系统软件源（apt/dnf/pacman）、GitHub（源码 tarball / release 资产 / `raw.githubusercontent.com`）、以及可选的 Docker Hub。国内直连常见表现是 `apt-get update` 超时、GitHub 下载卡住或 403。

### 3.1 三条推荐路径

1. **安装器一键换源（推荐）**：安装器支持在装包前调用 `scripts/cn-mirrors.sh` 切换到国内镜像源（见 [CHINA-NETWORK.md](CHINA-NETWORK.md)）。
2. **先手动换源再安装**：先执行 `scripts/cn-mirrors.sh`（或按 [CHINA-NETWORK.md](CHINA-NETWORK.md) 手动配置），然后正常安装。适合想先确认源可用性的场景。
3. **离线 / 内网分发**：在外网机器构建 tarball 或使用预编译二进制，内网分发安装（见 4.5 节），完全不依赖境外网络。

### 3.2 安装器国内加速参数

```bash
# 从「克隆/解压后的仓库」运行独立安装器（可完整使用换源参数）
sudo bash packaging/standalone/install.sh \
  --cn-mirrors=auto \
  --cn-components=os,pip,npm,go,docker \
  --github-proxy=https://ghfast.top/
```

可选项（与 `scripts/cn-mirrors.sh` 对齐，详见 [CHINA-NETWORK.md](CHINA-NETWORK.md)）：

| 参数 | 取值 | 说明 |
|---|---|---|
| `--cn-mirrors[=...]` | `auto`、`tuna`、`ustc`、`aliyun`、`tencent`、`huawei` | 启用换源并指定镜像站（**默认不启用**；省略值 = `auto`）。 |
| `--cn-components=LIST` | `os,pip,npm,go,docker,cargo,git` 的逗号组合 | 只切换指定组件，缺失工具会自动跳过并提示。 |
| `--github-proxy=URL` | 例如 `https://ghfast.top/` | 为 `github.com` / `raw.githubusercontent.com` 的下载加代理前缀（release tarball、CLI、更新脚本）；同时透传给换源脚本的 git 组件。 |
| 环境变量 | `WEBKVM_CN_MIRRORS`、`WEBKVM_CN_COMPONENTS`、`WEBKVM_GH_PROXY` | 与命令行参数等价。 |

> 安装器会在**刷新包索引、安装运行时依赖之前**执行换源；换源成功/失败都不影响默认安装路径：未启用时行为与改动前完全一致，换源脚本缺失或失败时只告警并继续使用原源。换源脚本本身**不会**自动执行 `apt-get update`，但安装器在换源后会自行刷新包索引。`https://api.github.com` 不经过 GitHub 代理前缀（查询最新 release 用），若该 API 不可达请用 `WEBKVM_BINARY_URL` + `WEBKVM_BINARY_SHA256` 指定二进制。国内换源的详细行为（apt 保留原协议、`ports.ubuntu.com` 保留 `/ubuntu-ports`、RHEL 无公共镜像等）见 [CHINA-NETWORK.md](CHINA-NETWORK.md)。

> 一键脚本 `scripts/install-webkvm.sh` 会把 `WEBKVM_CN_MIRRORS` / `WEBKVM_CN_COMPONENTS` / `WEBKVM_GH_PROXY` 透传给独立安装器（作为对应命令行参数），并支持用 `WEBKVM_INSTALL_TARBALL_URL` 直接指定源码 tarball（http(s) 直链或本地文件路径）。例如：

```bash
curl -fsSL https://raw.githubusercontent.com/Slaker19/webkvm/main/scripts/install-webkvm.sh -o /tmp/webkvm-install.sh
sudo WEBKVM_CN_MIRRORS=auto \
     WEBKVM_CN_COMPONENTS=os,pip,npm,go,docker \
     WEBKVM_GH_PROXY=https://ghfast.top/ \
     bash /tmp/webkvm-install.sh
```

### 3.3 GitHub 加速的常见形式

| 用途 | 原始地址 | 加速思路 |
|---|---|---|
| 克隆仓库 | `https://github.com/Slaker19/webkvm.git` | 使用代理前缀：`https://ghfast.top/https://github.com/Slaker19/webkvm.git`；或配置 `git config --global url."https://ghfast.top/https://github.com/".insteadOf "https://github.com/"`（`--components=git` + `--github-proxy` 会自动写入）。 |
| 源码 tarball | `https://github.com/Slaker19/webkvm/archive/refs/heads/main.tar.gz` | 同样加代理前缀，或用 `WEBKVM_INSTALL_TARBALL_URL` 指向已缓存/内网地址（也支持本地 tarball 文件路径）。 |
| release 资产 | `https://github.com/Slaker19/webkvm/releases/download/<tag>/webkvm-<ver>-linux_amd64` | 浏览器/下载器加速，或用 `WEBKVM_BINARY_URL` + `WEBKVM_BINARY_SHA256` 指向国内对象存储镜像。 |
| 最新 release API | `https://api.github.com/repos/Slaker19/webkvm/releases/latest` | **不走**代理前缀；不可达时改用 `WEBKVM_BINARY_URL`，或用 `WEBKVM_UPDATE_REF=<tag>` 指定已知 release tag。 |

> 加速地址的可用性会随时间变化，`CHINA-NETWORK.md` 给出自检方法与“避免硬编码”的注意事项；本文不写死某个代理域名，示例仅为格式演示。安装器对通过代理下载的二进制/ release tarball 仍强制 SHA-256 校验（校验和来自官方 `SHA256SUMS`）。

### 3.4 安装前的网络自检

```bash
# 系统源是否可达
sudo apt-get update            # Debian/Ubuntu
sudo dnf makecache             # Fedora/RHEL
sudo pacman -Sy                # Arch

# GitHub 与 release API 是否可达
curl -sI -m 10 https://raw.githubusercontent.com/Slaker19/webkvm/main/scripts/install-webkvm.sh | head -1
curl -sI -m 10 https://api.github.com/repos/Slaker19/webkvm/releases/latest | head -1

# Docker 镜像仓库是否可达（可选）
docker pull hello-world
```

如果 `apt-get update` 报 GPG / 签名错误，或镜像同步延迟，按 [CHINA-NETWORK.md](CHINA-NETWORK.md) 的「常见问题」处理；安装器对包索引刷新和装包自带重试（`WEBKVM_PKG_RETRIES`，默认 3 次），短暂抖动通常可自动恢复。

---

## 4. 安装方式

安装方式共 5 种，按推荐顺序：一键脚本 → 克隆仓库 → 预编译二进制 → Docker → 离线/内网。

### 4.1 方式一：一键脚本（推荐，最简单）

**前提**：root、`curl`、`tar`、systemd、`/dev/kvm`、2 GiB 内存、5 GiB 磁盘、8080 端口空闲。

```bash
# 管道执行 = 全无人值守（全部使用默认值）
curl -fsSL https://raw.githubusercontent.com/Slaker19/webkvm/main/scripts/install-webkvm.sh | sudo bash
```

该脚本会：

1. 把仓库克隆（无 git 时下载 tarball）到 **`/opt/webkvm-repo`**；
2. 调用 `packaging/standalone/install.sh` 完成真正的安装。

若希望**交互式**选择 HTTPS / 网卡 / 网络模式，请先下载再执行（stdin 是终端时安装器会逐项询问）：

```bash
curl -fsSL https://raw.githubusercontent.com/Slaker19/webkvm/main/scripts/install-webkvm.sh -o /tmp/webkvm-install.sh
sudo bash /tmp/webkvm-install.sh
```

安装结束的预期输出（示意，IP 与版本以实际为准）：

```text
=== webkvm installed successfully ===

  Web UI:  https://192.168.1.10:8080
           https://localhost:8080
  Certificate: /opt/webkvm/certs/webkvm.crt  (download it from the UI at /api/system/cert ...)
  Admin password: stored in /opt/webkvm/admin-password.initial (root-only, 0600); ...
  Networks:
    - vmbr0: physical bridge on the real LAN (shared Layer-2, IPs from the router)
    - vmbr1: NAT bridge (100.0.0.0/24) — isolated tenants with internet via MASQUERADE

  Commands:
    systemctl status webkvm   # service status
    journalctl -u webkvm -f   # follow logs
```

**验证**：

```bash
systemctl status webkvm --no-pager
curl -kfsS https://127.0.0.1:8080/api/health
```

**日志**：一键脚本自身的步骤日志写入 `/var/log/webkvm-install.log`（可用 `WEBKVM_INSTALL_LOG` 覆盖）；独立安装器的完整输出建议自行留存：

```bash
sudo bash /tmp/webkvm-install.sh 2>&1 | sudo tee -a /var/log/webkvm-install.log
```

> 注意：默认情况下安装器把服务绑定到 **127.0.0.1**（仅本机）。远程访问需要 SSH 隧道、反向代理，或在安装时选择 `0.0.0.0` / LAN IP（务必同时启用 HTTPS）。详见第 6 节。

### 4.2 方式二：克隆仓库安装

**前提**：同方式一，另外需要 `git`（可选，没有 git 也能用 tarball）。

```bash
git clone https://github.com/Slaker19/webkvm.git
cd webkvm

# 完整安装（交互式；会先做前置检查）
sudo ./install.sh

# 只预演、不产生任何系统改动
sudo ./packaging/standalone/install.sh --dry-run

# 无人值守安装（全默认；网络模式 both、Incus 启用）
sudo ./packaging/standalone/install.sh --yes
```

`install.sh` 只做两件事：检查 `/dev/kvm` 与 systemd，然后 `exec` 到 `packaging/standalone/install.sh` 并透传参数。

**验证**：

```bash
sudo ./packaging/standalone/install.sh --dry-run | head -30   # 会列出将安装的 runtime 包
/usr/local/bin/webkvm version
```

> 升级时重复执行同一条安装命令即可（见第 11 节）。

### 4.3 方式三：预编译二进制（无需在目标机安装 Go/Node）

**构建机**（有 Go/Node 与 libvirt 开发库）：

```bash
make dist
ls -l dist/
# dist/webkvm-<version>.tar.gz
# dist/webkvm-<version>-linux_amd64
# dist/webkvm-cli-<version>-linux_amd64
# dist/SHA256SUMS
```

**目标服务器**（从 tarball 安装）：

```bash
scp dist/webkvm-<version>.tar.gz root@SERVER:/tmp/
```

```bash
cd /tmp
tar xzf webkvm-<version>.tar.gz
cd /tmp
sudo WEBKVM_BINARY=/tmp/backend/webkvm bash /tmp/packaging/standalone/install.sh --yes
```

> `WEBKVM_BINARY` 指向本地二进制即可跳过 GitHub 下载；安装器会顺带安装同目录的 `webkvm-cli`（若存在）。

**通过 HTTPS URL 安装（强制校验 SHA-256）**：

```bash
# 自行下载并计算校验和
sha256sum webkvm-<version>-linux_amd64

sudo WEBKVM_BINARY_URL=https://your-server.example.com/webkvm-<version>-linux_amd64 \
     WEBKVM_BINARY_SHA256=<64位十六进制SHA256> \
     bash packaging/standalone/install.sh --yes
```

安装器约束：

- `WEBKVM_BINARY_URL` **必须为 HTTPS**，且 `WEBKVM_BINARY_SHA256` 必须是 64 位十六进制 SHA-256，否则拒绝下载/安装；
- 校验失败立即中止（防止把无法验证的二进制以 root 运行）；
- 未提供 `WEBKVM_BINARY`/URL 时，安装器会回退到 GitHub Releases 拉取 release tarball 并校验 `SHA256SUMS`。

### 4.4 方式四：Docker

**关键前提**：Docker 模式**不打包** libvirtd/QEMU/Incus，容器只是宿主 libvirt 的客户端。宿主机必须已安装并运行 libvirt/QEMU（Docker 安装脚本会代装）。详见 [DOCKER.md](DOCKER.md) / [docs/DOCKER.md](../DOCKER.md)。

**一键（脚本代装宿主 libvirt + Docker，再部署容器）**：

```bash
curl -fsSL https://raw.githubusercontent.com/Slaker19/webkvm/main/scripts/install-docker.sh -o /tmp/webkvm-docker-install.sh
sudo bash /tmp/webkvm-docker-install.sh
```

**从仓库 checkout 手动部署**：

```bash
# 1) 宿主机已具备 libvirt/QEMU/KVM（参考 docs/DOCKER.md 的 Host packages）
sudo systemctl enable --now libvirtd     # 新版 libvirt 也可用 virtqemud

# 2) 启动 compose（默认拉取 slaker1908/webkvm:latest）
docker compose up -d

# 3) 验证
docker compose ps
curl -kfsS https://127.0.0.1:8080/api/health
```

其他常用命令：

```bash
sudo ./docker-install.sh              # 拉取已发布镜像并部署
sudo ./docker-install.sh --source     # 本地构建镜像（需 Go/Node）
sudo ./docker-install.sh --dry-run    # 只预演
docker compose build && docker compose up -d   # 源码构建镜像
docker compose pull && docker compose up -d    # 更新
```

**注意**：

- 必须 `network_mode: host` + `privileged: true`（`docker-compose.yml` 已配置），否则桥接与防火墙不可用；
- `DATA_DIR` 在容器内外必须是**同一绝对路径**（默认 `/opt/webkvm`），否则 libvirt 存储池路径错位；
- **不要**在 Docker 模式使用界面里的“更新”按钮，请用 `docker compose pull && docker compose up -d`；
- 同一台宿主机**不要**同时运行原生安装与容器实例，也不要让两个实例（不同 `DATA_DIR`）连接同一个 libvirtd。

### 4.5 方式五：离线 / 内网部署

**适用**：完全隔离网络、公司内网镜像、或 GitHub/软件源均不可达。

**路径 A：tarball + 预装运行时依赖**

```bash
# 外网构建机
make dist

# 内网目标机（提前通过本地源/离线包安装 libvirt、qemu、ovmf、swtpm、xorriso、dnsmasq 等）
# 运行时包清单与 packaging/standalone/install.sh 中 RUNTIME_PACKAGES 一致
tar xzf webkvm-<version>.tar.gz
sudo WEBKVM_BINARY=./backend/webkvm \
     WEBKVM_NONINTERACTIVE=1 \
     WEBKVM_HTTPS=yes \
     NETWORK_MODE=bridge \
     bash packaging/standalone/install.sh
```

**路径 B：内网 HTTPS 分发**

```bash
# 内网对象存储/文件服务器（必须 HTTPS）
sudo WEBKVM_BINARY_URL=https://mirror.intra/webkvm/webkvm-<version>-linux_amd64 \
     WEBKVM_BINARY_SHA256=<sha256> \
     WEBKVM_NONINTERACTIVE=1 NETWORK_MODE=both \
     bash packaging/standalone/install.sh
```

**路径 C：Docker 镜像离线导入**

```bash
# 外网：保存镜像
docker pull slaker1908/webkvm:latest
docker save slaker1908/webkvm:latest -o webkvm-image.tar

# 内网：导入并启动
docker load -i webkvm-image.tar
docker compose up -d
```

**离线注意事项**：

- 安装器不会“凭空”提供系统软件包：若本地没有可用包源，请预先装好 `RUNTIME_PACKAGES` 中的全部依赖，或配置内网 apt/dnf/pacman 镜像；
- 安装器的包索引刷新失败只会告警并继续（`pkg_update || log warning`），但**装包失败会中止安装**；
- 离线时，安装器顺带下载的 `update.sh`（界面“更新”按钮依赖）会失败但**不中断安装**，界面更新按钮会报错；升级请用新 tarball 重新执行安装器；
- 一键脚本下载源码 tarball 时可用 `WEBKVM_INSTALL_TARBALL_URL` 指向内网地址或本地 tarball 文件路径；仓库地址可用 `WEBKVM_INSTALL_REPO`、`WEBKVM_INSTALL_BRANCH` 覆盖；GitHub 下载/克隆可用 `WEBKVM_GH_PROXY` 加代理前缀。

---

## 5. 安装过程交互项说明与无人值守

### 5.1 交互项总览

独立安装器在**终端中交互式运行**时逐项询问；通过管道运行（`curl ... | sudo bash`）或设置 `WEBKVM_NONINTERACTIVE=1` / `--yes` 时自动使用默认值。

| 交互项 | 提示原文（安装器输出） | 交互模式默认 | `--yes` / 管道默认 | 参数 | 环境变量 |
|---|---|---|---|---|---|
| 端口 | `Backend HTTP/HTTPS port` | `8080` | `8080` | `--port=8080` | `WEBKVM_PORT` |
| 监听地址 | `Bind address (127.0.0.1 = local only; 0.0.0.0 = all interfaces)` | `127.0.0.1` | `127.0.0.1` | `--bind=0.0.0.0` | `WEBKVM_BIND_ADDR` |
| HTTPS | `How do you want to access WebKVM?` → 1) IP only (plain HTTP) 2) With SSL | `yes`（选项 2） | `yes` | `--https=yes\|no` | `WEBKVM_HTTPS` |
| 证书域名 | `Certificate domain (optional — e.g. webkvm.example.com ...)` | 空（仅 IP/主机名） | 空 | `--domain=webkvm.example.com` | `WEBKVM_TLS_DOMAIN` |
| 网络模式 | `How should instances reach the network?` → 1) bridge 2) NAT 3) Both | `bridge` | **`both`** | `--network=bridge\|nat\|both\|none` | `NETWORK_MODE` |
| 网桥 IP | `Bridge IP: pin current as STATIC (recommended) or DHCP?` | `static`（把当前 DHCP 租约固定为静态） | `static` | `--bridge-dhcp` / `--bridge-static=CIDR` | `BRIDGE_DHCP` / `BRIDGE_STATIC_IP` |
| 网关 / DNS | `Gateway:` / `DNS (comma-separated):` | 自动探测 | 自动探测 | `--gateway=IP` / `--dns=IPs` | `BRIDGE_STATIC_GW` / `BRIDGE_STATIC_DNS` |
| Incus 容器 | 不询问 | **安装并启用** | **安装并启用** | `--incus=yes\|no` | `WEBKVM_INSTALL_INCUS` |
| 数据目录 | 不询问 | `/opt/webkvm` | `/opt/webkvm` | `--data-dir=PATH` | `WEBKVM_DATA_DIR` |
| 安装前缀 | 不询问 | `/usr/local` | `/usr/local` | `--prefix=PATH` | `WEBKVM_PREFIX` |
| 初始管理员密码 | 不询问 | 随机生成 | 随机生成 | `--admin-password=PASS` | `WEBKVM_ADMIN_PASSWORD` |

> 交互模式下若选择 `bridge`/`both`，安装器还会追问网桥 IP 的静态/DHCP 选择；默认把**当前** IP 固定为静态，避免桥接后地址漂移。若路由器会把该地址再分配给别人，请务必在路由器上加 DHCP 保留（安装器会打印醒目提示）。

### 5.2 无人值守示例

```bash
# 最简：全部默认（HTTPS 开、网络 both、Incus 开、绑定 127.0.0.1）
sudo ./packaging/standalone/install.sh --yes

# 面向生产：局域网可访问（0.0.0.0）+ 双网络 + 指定端口
sudo ./packaging/standalone/install.sh \
  --yes \
  --bind=0.0.0.0 \
  --port=8080 \
  --https=yes \
  --network=both \
  --incus=yes

# 纯环境变量形式（适合 CI / 配置管理）
sudo WEBKVM_NONINTERACTIVE=1 \
     WEBKVM_BIND_ADDR=0.0.0.0 \
     WEBKVM_PORT=8080 \
     WEBKVM_HTTPS=yes \
     WEBKVM_TLS_DOMAIN=webkvm.example.com \
     NETWORK_MODE=both \
     WEBKVM_INSTALL_INCUS=1 \
     bash ./packaging/standalone/install.sh
```

`--dry-run` 只做前置检查并打印将要执行的操作，不写任何系统文件：

```bash
sudo ./packaging/standalone/install.sh --dry-run
```

```text
[webkvm] ── DRY-RUN (no se ha instalado nada) ────────────
[webkvm] familia de paquetes : apt
[webkvm] runtime packages that would be installed:
[webkvm]   · ca-certificates
...
[webkvm] dry-run OK — sistema intacto.
```

### 5.3 安装器内部步骤（了解原理即可）

1. 前置检查（root、包管理器、amd64、systemd、`/dev/kvm`、内存、磁盘、网络路由）。
2. 安装运行时依赖（libvirt、QEMU、OVMF、swtpm、xorriso、dnsmasq、磁盘管理工具等），失败会重试。
3. 可选安装并初始化 Incus（写 subuid/subgid、`incus admin init --auto`、`security.nesting=true`）。
4. 启用 libvirt 守护进程（`libvirtd`，较新发行版为 `virtqemud`）。
5. 创建 `DATA_DIR`、`/etc/webkvm` 等目录。
6. 部署预编译二进制（+ 可选 `webkvm-cli`、`webkvm-backup.sh`、`webkvm-update`）。
7. 写入 `/etc/systemd/system/webkvm.service` 并预写 `config.json` 的 `server.bind_addr` / `server.port`。
8. 按选择生成自签名证书并写入 `server.tls_cert` / `server.tls_key`（+ `server.tls_domain`）。
9. 启动服务，调用 `scripts/setup-network.sh` 配置网络。
10. 尝试放行防火墙端口，轮询 `/api/health` 最多 30 秒，失败则自动回滚。

---

## 6. 首次登录与初始化

### 6.1 找到初始管理员密码

安装器不会把密码打印到屏幕上（避免被日志/终端历史记录收集），而是以 root-only（0600）写入文件：

```bash
sudo cat /opt/webkvm/admin-password.initial
```

- 该文件在**首次修改密码后会被删除**；
- 如果文件不存在：说明已经改过密码，或使用了 `--admin-password` 指定了初始密码；
- 忘记密码时可用 CLI 重置（见 6.6）。

### 6.2 访问 Web UI

按安装时的监听地址选择方式：

**A. 本机访问（默认绑定 127.0.0.1）**

```bash
# 在服务器本机浏览器或 SSH 隧道
https://localhost:8080
```

**B. SSH 隧道（推荐，无需暴露 8080）**

```bash
# 在你的电脑上执行
ssh -L 8080:127.0.0.1:8080 user@SERVER_IP
# 然后浏览器打开
https://localhost:8080
```

**C. 局域网直连（需绑定 0.0.0.0 或 LAN IP）**

安装时通过 `--bind=0.0.0.0`（交互/脚本方式）或环境变量 `WEBKVM_BIND_ADDR=0.0.0.0`（一键管道方式）指定监听地址，或登录后在「设置（Settings）→ 服务器（Server）→ Bind address」修改并重启服务：

```bash
sudo systemctl restart webkvm
```

> 修改为 `0.0.0.0` 时**务必保持 HTTPS 开启**，否则密码与会话 Cookie 会以明文经过网络（安装器会打印警告）。

### 6.3 自签名证书告警

默认 HTTPS 使用 RSA-2048 自签名证书（有效期 10 年），SAN 覆盖：

```text
DNS:webkvm, DNS:localhost, DNS:<hostname>.local, IP:127.0.0.1, IP:<LAN IP>[, DNS:<你填写的域名>]
```

浏览器首次访问会提示证书不受信任，属预期行为。消除告警：

1. 打开 `https://<服务器IP>:8080/api/system/cert` 下载证书（或取 `/opt/webkvm/certs/webkvm.crt`）；
2. 导入操作系统/浏览器信任库；
3. 重新加载页面。

### 6.4 首次登录流程

1. 用户名：`admin`
2. 密码：`/opt/webkvm/admin-password.initial` 中的内容
3. 系统会**强制要求修改密码**（`must_change_password` 会拦截除认证/健康检查外的所有接口），改完才能正常使用。

### 6.5 放行防火墙

安装器会尝试自动放行（检测到 firewalld/ufw 时）。若没有自动放行或自行改过端口，手动执行：

```bash
# ufw（Debian/Ubuntu）
sudo ufw allow 8080/tcp
sudo ufw reload
sudo ufw status numbered

# firewalld（Fedora/RHEL）
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
sudo firewall-cmd --list-ports
```

> 若只是通过 SSH 隧道/反向代理访问，**不需要**对外放行 8080。

### 6.6 健康检查与初始化验证

```bash
# 服务状态
systemctl status webkvm --no-pager

# 健康端点（默认 HTTPS；HTTP 安装则去掉 -k 并用 http://）
curl -kfsS https://127.0.0.1:8080/api/health
```

预期返回（字段以实际为准）：

```json
{"status":"ok","libvirt":"ok","uptime":42,"data_dir":"/opt/webkvm","version":"0.1.9","build_time":"...","disk_free":...,"disk_total":...}
```

- `"status":"degraded"` 通常表示 libvirt 不可达或数据盘可用空间 < 5%；
- `"libvirt":"down"` 时先检查 `systemctl status libvirtd`（或 `virtqemud`）。

其他验证命令：

```bash
# 二进制版本
/usr/local/bin/webkvm version

# CLI 健康检查（零令牌）
sudo webkvm-cli status

# libvirt 连接与存储池
sudo virsh -c qemu:///system list --all
sudo virsh -c qemu:///system pool-list --all
```

### 6.7 忘记管理员密码

```bash
# 方式一：CLI 直接改密（需要 root 权限；零令牌本地认证）
sudo webkvm-cli users update admin --password '新的强密码'

# 方式二（会丢失用户数据，谨慎）：删除用户库后重启，重新生成初始管理员
sudo systemctl stop webkvm
sudo mv /opt/webkvm/users.json /opt/webkvm/users.json.bak.$(date +%s)
sudo systemctl start webkvm
sudo cat /opt/webkvm/admin-password.initial
```

> 方式二会重新生成 admin 账户与随机密码，其他用户/分组数据随之丢失（`users.json` 内所有账户）。生产环境请优先用方式一。

---

## 7. 网络模式与 bridge/NAT 详解

WebKVM 的实例网络模型是 **真实操作系统级 Linux 网桥**（Proxmox 风格）：libvirt 自带的 `default`/`virbr0` 等虚拟网络不再作为实例网络使用；KVM 虚拟机以 `<interface type='bridge'><source bridge='vmbrX'/>` 接入，Incus 容器以 `nictype=bridged parent=vmbrX` 接入。

### 7.1 四种模式

| 模式 | 参数 | 行为 | 默认值 |
|---|---|---|---|
| `bridge` | `--network=bridge` | 创建/复用物理网桥 `vmbr0`（绑定真实网卡），实例从路由器 DHCP 或静态获得**真实 LAN IP**。**交互式默认**。 | 交互模式默认 |
| `both` | `--network=both` | 同时提供 `vmbr0`（LAN）与 `vmbr1`（隔离 NAT）。 | `--yes`/无人值守默认 |
| `nat` | `--network=nat` | 仅启用 libvirt `default` NAT 网络（`192.168.122.x`），不创建物理桥；历史模式，新部署不建议使用。若目标是 Proxmox 风格的隔离桥 `vmbr1`，请用 `both`（或 bridge + `WEBKVM_NAT_BRIDGE=1`）。 | 手动选择 |
| `none` | `--network=none` | 不做任何网络配置（适用于已有现成网桥或自行管理网络的场景）。 | 手动选择 |

> 注意：`bridge` 模式**不会**创建 `vmbr1` 及其 dnsmasq（避免意外在 LAN 上启动 100.0.0.0/24 DHCP）。需要 NAT 桥时用 `--network=both`，或在 bridge 安装上设置 `WEBKVM_NAT_BRIDGE=1` 重新运行网络脚本。

### 7.2 `vmbr0`：共享二层物理网桥

- 安装器优先**复用**已存在的 `vmbr0`/`br0`；没有则按宿主实际环境创建：**netplan**（Ubuntu，且有 `/etc/netplan`）→ **NetworkManager（`nmcli`）** → **systemd-networkd** → **ifupdown**（`/etc/network/interfaces`）。创建前会校验配置（如 `netplan generate`），失败即回滚并打印手工配置指引，避免把宿主网络改坏。
- 默认把宿主机**当前 IP 固定为静态**到网桥（避免重启后地址漂移）；也可选择 DHCP（`--bridge-dhcp`）或显式指定（`--bridge-static=192.168.1.10/24 --gateway=192.168.1.1 --dns=1.1.1.1,8.8.8.8`）。
- 物理网卡被 enslave 进网桥后**不再持有独立 IP**；宿主机通过 `vmbr0` 上网。
- **务必在路由器上为该 MAC 添加 DHCP 保留或把该 IP 排除出 DHCP 池**，否则租约到期后路由器可能把同一 IP 分给其他设备（安装器会打印该警告）。

验证：

```bash
ip -br addr show vmbr0
ip -br link show
bridge link show
# 预期：vmbr0 有 inet 地址；物理网卡 master vmbr0，状态 UP
```

### 7.3 `vmbr1`：隔离 NAT 网桥

当网络模式为 `both`（或 `WEBKVM_NAT_BRIDGE=1`）时创建：

| 项目 | 值 |
|---|---|
| 网桥 | `vmbr1` |
| 承载接口 | 内核 `dummy0`（`dummy` 设备，提供稳定载体） |
| 网关地址 | `100.0.0.1/24` |
| DHCP | dnsmasq，地址池 `100.0.0.100 – 100.0.0.200`，租约 12 小时 |
| DNS（下发给实例） | `1.1.1.1` |
| 出网 | `MASQUERADE`（firewalld internal 区 / ufw before.rules / iptables，按宿主实际防火墙选择） |
| 持久化 | netplan（Ubuntu）/ NetworkManager / systemd-networkd，按宿主环境自动选择 |
| 相关文件 | `/etc/webkvm/vmbr1-dnsmasq.conf`、systemd 单元 `webkvm-vmbr1-dnsmasq.service`、`webkvm-dummy0.service` |

验证：

```bash
ip -br addr show vmbr1
# 预期：vmbr1 UP 100.0.0.1/24
systemctl status webkvm-vmbr1-dnsmasq.service --no-pager
cat /etc/webkvm/vmbr1-dnsmasq.conf
# 在实例内：ip addr；ping 100.0.0.1；ping 1.1.1.1
```

### 7.4 常见拓扑建议

| 场景 | 推荐模式 | 说明 |
|---|---|---|
| 单网卡服务器，实例要像物理机一样出现在 LAN | `bridge` | 实例由路由器分配 IP，局域网可直接访问。 |
| 做隔离测试环境 / 不想让实例暴露在 LAN | `both`（或 bridge + `WEBKVM_NAT_BRIDGE=1`） | 通过 `vmbr1` NAT 出网；如需从外网访问，用端口转发或反向代理。旧式 `nat` 模式只配 libvirt `192.168.122.x`，不创建 `vmbr1`。 |
| 既有 LAN 需求又有隔离需求 | `both` | 创建实例时按需选择 `vmbr0` / `vmbr1`。 |
| Wi-Fi 笔记本 | `both`，实例选 `vmbr1` | 普通 Wi-Fi 网卡无法做多 MAC 二层桥接（AP 只认无线网卡自己的 MAC），桥接型实例可能拿不到地址；实例选 NAT（`vmbr1`）最稳妥。 |
| 已有自管网桥 / 云厂商网络 | `none` | WebKVM 不碰网络，实例直接挂你已有的网桥。 |

### 7.5 修改或重建网络

- **重跑安装器**：`sudo ./packaging/standalone/install.sh --network=both`（会重新执行 `scripts/setup-network.sh`，幂等）。
- **单独执行网络脚本**（仓库路径：一键安装为 `/opt/webkvm-repo`，克隆安装为仓库根目录）：

```bash
# 仅预览会做什么，不修改系统
sudo WEBKVM_DETECT_ONLY=1 bash scripts/setup-network.sh

# 重建物理桥（固定静态 IP）
sudo BRIDGE_APPLY=1 NET_MODE=bridge \
     BRIDGE_STATIC_IP=192.168.1.10/24 \
     BRIDGE_STATIC_GW=192.168.1.1 \
     BRIDGE_STATIC_DNS=1.1.1.1,8.8.8.8 \
     bash scripts/setup-network.sh --bridge --static

# 额外创建 NAT 桥（在 bridge 安装上）
sudo WEBKVM_NAT_BRIDGE=1 BRIDGE_APPLY=1 bash scripts/setup-network.sh --bridge
```

- **UI 管理**：「网络（Networking）」页可新建额外宿主网桥（可配 IP 与 DHCP 范围）、启停网桥、查看 DHCP 租约，并为虚拟机配置 nftables 防火墙规则。
- **网络改坏无法 SSH**：从物理控制台/IPMI 运行仓库自带恢复脚本：

```bash
sudo bash scripts/recover-network.sh
```

> 网络脚本会备份它管理的文件（例如 `/etc/systemd/network/*.bak`、被 netplan 合并的旧配置重命名为 `*.webkvm-removed`），必要时可手工回退。

---

## 8. 创建第一台虚拟机 / 容器

### 8.1 准备镜像

**云镜像（推荐）**：内置镜像中心可直接拉取官方 `.qcow2`：

- UI：左侧「镜像中心（Image Hub）」→ 选择 Ubuntu/Debian/Alpine/Fedora/Rocky/AlmaLinux 等 → 下载；
- CLI：

```bash
webkvm-cli images list
webkvm-cli images cloud
webkvm-cli images pull-cloud ubuntu-24.04
webkvm-cli images pull-cloud debian-12
```

**ISO 安装介质**：在「存储（Storage）→ ISO」上传 ISO（支持进度显示），或把 ISO 文件放到 ISO 池目录后在界面刷新。

### 8.2 创建 KVM 虚拟机

UI 步骤：

1. 「虚拟机（VMs）」→「新建虚拟机（New VM）」；
2. 选择操作系统预设（自动套用 UEFI/BIOS、TPM/安全启动、磁盘总线、内存/vCPU 等推荐值）；
3. 选择引导介质：云镜像（cloud-init）或 ISO；
4. 选择网络：`vmbr0`（LAN）或 `vmbr1`（隔离 NAT）；
5. 高级选项：磁盘性能（推荐 `cache=none, io=native`）、TRIM/discard、CPU 型号与拓扑（sockets/cores/threads）、virtio RNG（默认自动附加）；
6. 创建后自动启动，打开控制台即可。

CLI 等价操作（示例来自仓库 README/CLI 帮助）：

```bash
# 5 秒内部署一台 Debian 12 虚拟机（云镜像 + COW）
webkvm-cli vms create --name debian-prod --ram 2048 --vcpus 2 --disk 20 --image debian-12

# 查看状态与列表
webkvm-cli vms list
webkvm-cli vms show debian-prod
```

**cloud-init**：从模板/云镜像实例化时可注入用户名、密码、SSH 公钥与主机名；系统会自动生成 NoCloud seed ISO，客户机首次启动时自配置。云镜像模板通常预装 `qemu-guest-agent`，便于获取 IP、执行关机与一致性快照。

### 8.3 创建容器（Incus/LXC）

前提：安装时启用了 Incus（默认启用；`--incus=no` 可关闭），且服务端 `WEBKVM_INCUS_ENABLED=1`（安装器已写入 systemd 单元）。

UI 步骤：

1. 「新建虚拟机」→ 实例类型选择 **容器（Container / Incus / LXC）**；
2. 选择发行版镜像（或“自定义”）；
3. 选择网络（与虚拟机相同的 `vmbr0` / `vmbr1`）；
4. 设置 Incus 容器凭据（用户名可留空，留空时密码应用于 `root`）；
5. 资源池只能选择 purpose 为 `container` 的池（默认 `webkvm-incus`），**不会**出现磁盘池/ISO 池。

CLI：

```bash
webkvm-cli vms create --name alpine-ct --ram 512 --vcpus 1 --type container --image images:alpine/3.21
webkvm-cli vms list        # 容器与虚拟机同列表，TYPE 列区分
```

容器支持根盘扩容、增删改网卡、串口控制台与实时 CPU/内存指标；跨容器池迁移用详情页「移动存储（Move storage）」，且要求容器已停止。

### 8.4 打开控制台

- **VNC 控制台**：虚拟机详情页内嵌 noVNC，可调画质/压缩、点阵光标，并直接执行重启/关机/强制关闭；
- **串口控制台**：内嵌 xterm（80×24），客户机重启不丢失；
- **外部客户端**：可下载 `.vv`（SPICE）或 `.rdp` 文件，文件内 IP 来自 `PUBLIC_HOST` 或宿主机第一个非回环地址；
- **宿主机终端**：侧边栏「宿主机终端（Host Console）」，通过 PAM 用真实系统账户登录（WebGL 加速，切换页面不中断）。

> 所有内嵌控制台都使用短时临时凭证认证：串口/宿主终端为 30 秒一次性 `?ticket=`，VNC 为 1 小时、限定单台虚拟机可重用的 `?vt=`；长期 JWT 不会出现在 URL 中。

### 8.5 验证实例

```bash
# WebKVM 侧
sudo webkvm-cli vms list
sudo webkvm-cli vms show <名称或ID>

# libvirt 侧
sudo virsh -c qemu:///system list --all

# Incus 侧
sudo incus list

# 网络验证（vmbr0 实例应获得 LAN 网段 IP；vmbr1 实例应获得 100.0.0.x）
ip -br addr show vmbr0
sudo virsh -c qemu:///system net-dhcp-leases default 2>/dev/null || true
```

---

## 9. 存储池 / ISO / 卷 / 备份目标配置

### 9.1 默认存储布局

| 池名 | 用途（purpose） | 默认路径 | 说明 |
|---|---|---|---|
| `webkvm-disks` | `disk` | `/opt/webkvm/pools/webkvm-disks` | VM 磁盘（qcow2/raw）。 |
| `webkvm-isos` | `iso` | `/opt/webkvm/pools/webkvm-isos` | ISO 库（旧版本名为 `ISOS`，首次启动自动迁移）。 |
| `webkvm-incus` | `container` | `/opt/webkvm/pools/webkvm-incus` | 容器 rootfs（启用 Incus 时自动创建）。 |

池用途（purpose）是强约束：`disk`、`container`、`iso`、`backup`、`template`；UI 中每个选择器都按用途过滤，容器不会落进磁盘池，qcow2 也不会进 ISO 库（后端 fail-closed 校验）。

验证：

```bash
sudo webkvm-cli storage pools
sudo virsh -c qemu:///system pool-list --all
ls -la /opt/webkvm/pools/
```

### 9.2 新建存储池

- **本地目录池（`dir`）**：UI「存储」→「新建池」→ 类型 `dir` → 指定宿主路径；或 CLI：

```bash
webkvm-cli storage pool-create fast-ssd --type dir --purpose disk --path /mnt/fast-ssd
```

- **网络池（`netfs`）**：NFS / SMB(CIFS) 共享。SMB 需要凭据时：类型 `netfs`、格式 `cifs`，填写 `source_host`、`source_dir`、`source_username`、`source_password`；密码以 libvirt secret 形式保存（API 永不回显，磁盘上只存 UUID 于 `/opt/webkvm/cifs-secrets.json`，0600）。凭据轮换用 `PUT /api/storage/pools/{name}`（池需先停止）；libvirtd 重装导致 secret 丢失时，用 `cifs-needs-reauth: true` + 当前凭据恢复。
- CLI 也支持 `--type zfs|btrfs|lvm`（取决于宿主已具备对应工具/内核支持）。

> 从 Storage → 主机磁盘（Host Disks）可直接对物理盘分区、格式化（ext4/xfs/btrfs/f2fs）、挂载并自动注册为存储池；**格式化是破坏性操作**，CLI 需 `--yes` 确认。

### 9.3 ISO 与卷管理

```bash
# ISO
webkvm-cli storage isos
webkvm-cli storage download-iso --url https://example.com/ubuntu.iso --name ubuntu.iso --pool webkvm-isos

# 卷（磁盘）
webkvm-cli storage volumes
webkvm-cli storage volumes webkvm-disks
```

UI 额外支持：上传磁盘镜像（`.qcow2`/`.img`/`.raw`/`.qed`，直接落盘、libvirt 刷新时自动识别格式，无需转换）、卷扩容/删除、ISO 上传/下载/删除。

**迁移存储**：

- VM 磁盘：「存储 → 磁盘 → 移动（Move）」；
- 容器 rootfs：容器详情页「移动存储」；
- 跨 hypervisor（KVM 池 ⇄ Incus 池）迁移被拒绝，需导出后重新导入。

### 9.4 备份目标

「备份（Backup）→ 目标（Targets）→ 新建」，支持类型：

| 类型 | 必填/说明 |
|---|---|
| `local` | 本地目录路径。 |
| `nfs` | NFS 已挂载的本地挂载点路径。 |
| `smb` | SMB/CIFS 已挂载的本地挂载点路径。 |
| `sftp` | 主机、用户名、密钥/密码，远程上传。 |
| `s3` | bucket、region（或自定义 endpoint）、access key、secret key；兼容 MinIO/Ceph RGW/R2 等 S3 兼容存储。 |

创建后可用 CLI 查看：

```bash
webkvm-cli backup targets
webkvm-cli backup jobs
```

> 警告：**不要**让第二个 WebKVM 实例（Docker 或原生）以不同 `DATA_DIR` 连接同一个 libvirtd。libvirt 存储池按名称标识，第二个实例会用同名池（`webkvm-disks`、`webkvm-isos`）重新定义 target 路径，破坏第一个实例的存储视图。

---

## 10. 备份、恢复与保留策略

### 10.1 备份模型

- **目标（target）**：备份落地位置（见 9.4）。
- **计划（schedule）**：cron 表达式，定期对目标触发备份。
- **作业/运行（job/run）**：一次执行，产出：
  - 每台虚拟机一个归档 `vm-<名称>.tar.zst`（含 `domain.xml`、`disks/`、`snapshots/`、`manifest.txt`）；
  - 一份配置归档 `config.tar.zst`；
  - 可选 SHA-256 校验；
  - **机密字段不进入配置备份**（webhook、SMTP、SFTP、CIFS 凭据等）。
- 进度出现在通知中心与「备份 → 作业（Jobs）」。

### 10.2 创建与执行

UI：「备份」→ 新建目标 → 新建计划（cron）或「立即运行」。

```bash
# 立即运行某目标的备份
webkvm-cli backup run <target>

# 查看运行历史
webkvm-cli backup jobs

# 手动应用保留策略并清理旧运行
webkvm-cli backup prune <target>
```

> 保留策略的自动清理由后台 janitor 每 6 小时执行一次；CLI/界面的 `prune` 可随时手动触发。

### 10.3 保留策略

每个目标可配置（字段名即 API 的 JSON 键，0 表示不启用该规则；多条规则为「或」关系）：

| 字段 | 语义 |
|---|---|
| `keep_last` | 保留最近 N 次运行。 |
| `keep_days` | 保留最近 N 天内的运行。 |
| `keep_daily` | 每个 UTC 自然日保留最新 N 次。 |
| `keep_weekly` | 每个 UTC ISO 周保留最新 N 次。 |
| `keep_monthly` | 每个 UTC 自然月保留最新 N 次。 |

建议：小规模用 `keep_last: 7`；重要业务叠加 `keep_daily: 7` + `keep_weekly: 4` + `keep_monthly: 6`。S3 兼容存储若不上报 `LastModified`（部分 MinIO/Ceph/R2/NAS 网关），未知时间的运行会被**保留**而不是误删。

### 10.4 恢复

UI：「备份 → 归档（Archives）」选择某次运行：

- **完整恢复（Restore）**：覆盖回原虚拟机；带大小限制与受保护路径校验；
- **恢复为新虚拟机（Restore as VM）**：把归档重新导入为一台新 VM，不影响原机。

> 恢复前建议先给目标机做快照或手工备份；恢复过程涉及 libvirt XML 校验，UEFI 固件等敏感元素会被安全策略过滤。

### 10.5 快照 vs 备份

| 能力 | 快照（Snapshot） | 备份（Backup） |
|---|---|---|
| 存放位置 | 宿主存储池（qcow2 增量） | 独立目标（本地/NFS/SMB/SFTP/S3） |
| 用途 | 快速回滚（升级前、变更前） | 灾难恢复、跨机迁移、长期留存 |
| 制作 | 详情页「快照」，可仅磁盘或含内存；运行中虚拟机在 guest-agent 可用时做文件系统一致性（fsfreeze/quiesce），否则为崩溃一致性 | 计划/手动运行 |
| 恢复 | 直接 revert（含历史树） | 完整恢复或恢复为新 VM |
| 依赖 | 与宿主同在 | 独立于宿主磁盘 |

### 10.6 宿主配置快速备份脚本

安装器会部署 `/usr/local/bin/webkvm-backup.sh`（源码 `scripts/webkvm-backup.sh`），用于把 `DATA_DIR` 中**配置类**文件（users.json、jwt.key、audit.log、pools 元数据、covers 等，**不含 qcow2/iso 大文件**，只收 <100 MB 文件）打包到 SMB 挂载：

```bash
# 默认：/mnt/webkvm-backup（必须是已挂载的 SMB 共享）
sudo BACKUP_MOUNT=/mnt/webkvm-backup /usr/local/bin/webkvm-backup.sh
# 输出一行 JSON：filename / path / size / sha256 / timestamp / duration_ms / host
```

| 环境变量 | 默认 | 说明 |
|---|---|---|
| `DATA_DIR` | `/opt/webkvm` | 要备份的数据目录。 |
| `BACKUP_MOUNT` | `/mnt/webkvm-backup` | 备份目标挂载点（脚本会校验是否为挂载点）。 |
| `HOST_TAG` | 主机短名 | 子目录/文件名标签。 |

### 10.7 关于备份加密

WebKVM 的备份归档**本身不做加密**（机密字段不会进入配置备份，但虚拟磁盘数据在归档内是明文的）。若合规要求加密：

- 使用支持服务端加密的 S3 bucket / 加密的 NFS/SMB 卷；
- 或对归档在存储侧做额外加密（如 `age`/`gpg`），并妥善保管密钥；
- 严格控制备份目标的访问权限（目标凭据存于 `DATA_DIR` 下，0600）。

---

## 11. 升级、回滚、卸载

### 11.1 升级方式

**方式 A：重新运行安装器（原生部署推荐）**

```bash
# 一键脚本装法：先更新仓库再重跑安装器
cd /opt/webkvm-repo
sudo git pull
sudo ./packaging/standalone/install.sh

# 或直接重跑一键脚本（会更新 /opt/webkvm-repo 后安装）
curl -fsSL https://raw.githubusercontent.com/Slaker19/webkvm/main/scripts/install-webkvm.sh | sudo bash
```

安装器升级流程：

1. 备份当前二进制与 systemd 单元为 `*.previous`；
2. 安装新二进制/单元；
3. 重启服务并轮询 `/api/health`；
4. **任一步失败自动回滚**到旧版本。

`/opt/webkvm` 下所有数据（配置、磁盘、ISO、用户）都会保留。

**方式 B：updater（已发布版本）**

安装器会部署 `/usr/local/bin/webkvm-update`（源码 `packaging/standalone/update.sh`），它下载最新 GitHub release 的 `webkvm-<ver>-linux_amd64` 并**强制校验 SHA256SUMS**：

```bash
sudo webkvm-update            # 从最新 release 升级
sudo webkvm-update --source   # 从本地 checkout 拉取并重建（需要 Go/Node）
```

也可以在 UI「状态（Status）→ 更新（Update）」点击升级（后端要求 systemd 单元里 `WEBKVM_ALLOW_UPDATE=1`，安装器默认已写入）。

**方式 C：Docker**

```bash
docker compose pull
docker compose up -d
```

源码构建镜像的等价操作：`git pull && make docker-build && docker compose up -d`。**不要**在 Docker 模式使用界面更新按钮。

### 11.2 回滚

- **自动回滚**：安装器/updater 在健康检查失败时会自动恢复旧二进制并重启服务。
- **手动回滚（updater 安装）**：

```bash
sudo install -m 0755 /usr/local/bin/webkvm.previous /usr/local/bin/webkvm
sudo systemctl restart webkvm
sudo curl -kfsS https://127.0.0.1:8080/api/health
```

- **Makefile 本地部署的回滚**（仅适用于用 `make install-systemd` 安装的开发/自建场景）：

```bash
cd webkvm
sudo make rollback
```

- **Docker 回滚**：改用旧版本镜像重新 `docker compose up -d`（镜像 tag 为不带 `v` 的版本号，如 `slaker1908/webkvm:0.1.9`；或修改 compose 的 `image:` 后重建）。

> 回滚前建议先备份 `/opt/webkvm`：新版本写入的配置字段旧版本可能无法识别（JSON 状态无 schema 版本迁移）。可以使用 10.6 节的脚本或 `tar` 打包配置目录（排除 pools 大文件）。

### 11.3 卸载

源码仓库中的卸载器位于 `packaging/standalone/uninstall.sh`：

```bash
cd /opt/webkvm-repo            # 一键安装；克隆安装则在仓库根目录
cd packaging/standalone

# 默认卸载：删除二进制、systemd 单元、update 脚本，保留数据
sudo ./uninstall.sh

# 同时删除数据目录与 WebKVM 创建的网络/网桥/防火墙规则
sudo PURGE_DATA=1 PURGE_NETWORKS=1 ./uninstall.sh
```

行为说明：

- 卸载只移除 WebKVM **自己拥有**的东西：`/usr/local/bin/webkvm`、`webkvm-cli`、`webkvm-update`、`webkvm.service`、`/etc/systemd/system/webkvm.service*`；可选 `PURGE_DATA` 删除 `/opt/webkvm`、可选 `PURGE_NETWORKS` 删除它创建的网桥/防火墙规则（`vmbr1`、`dummy0`、dnsmasq 单元、持久化配置等；**不会**动承载宿主 IP 的主网桥 `vmbr0`）。
- **不会**卸载运行时软件包（libvirt、QEMU、swtpm、ovmf、dnsmasq 等）：它们是系统共享的虚拟化组件，可能被其他软件使用。
- `PURGE_PACKAGES=1` 已不再支持。
- 若 `DATA_DIR` 不在 `/opt/webkvm` 下，卸载器会拒绝执行（安全限制），需先手工迁移数据。

Docker 卸载：

```bash
docker compose down
# 数据仍在 /opt/webkvm（如不再需要请自行删除）
```

---

## 12. 安全加固

### 12.1 TLS

- **保持 HTTPS 开启**（默认开启）：自签名证书 10 年有效，SAN 覆盖 LAN IP/主机名；浏览器告警属正常，可下载 `/api/system/cert` 后导入信任。
- **公网域名 + Let's Encrypt**：设置 `--domain=webkvm.example.com` 且域名解析到本机、80/443 可达时，自动签发并续期；失败自动回退到自签名（服务不中断），缓存位于 `/opt/webkvm/tls`。
- **反向代理**：若已有 WAF / 统一认证 / 限流代理，用 `WEBKVM_HTTPS=no` 安装并绑定 `127.0.0.1`，由代理终止 TLS。注意：代理场景应设置 `WEBKVM_TRUST_PROXY=1` 并仅信任代理来源。
- **换证书/改域名**：设置页「服务器 → TLS certificate / TLS domain」，保存后 `sudo systemctl restart webkvm`；或有 Caddy 组合时 `sudo make regen-cert`。

### 12.2 管理员密码与账户

- 首次登录**立即修改**初始密码；确认 `/opt/webkvm/admin-password.initial` 已被删除（改密后自动删除）。
- 使用强密码（16+ 字符、随机），不要复用其他系统密码。
- 按最小权限创建账户：`admin`（全权）> `operator`（增删改虚拟机/存储/网络/备份）> `viewer`（只读）。
- 禁用长期不用的账户（`webkvm-cli users update <user> --active false`），删除离职账户。
- API 令牌默认 30 天过期，可随时吊销；令牌明文只显示一次，服务端只存 SHA-256。

### 12.3 两步验证 / 通行密钥

「账户（Account）」页面支持：

- **TOTP 两步验证（2FA）**：绑定认证器 App，登录时需输入动态码；
- **通行密钥（WebAuthn/Passkey）**：使用系统生物识别/安全密钥登录。

建议所有 admin 账户强制启用 2FA。

### 12.4 防火墙

- 安装器会尝试放行 8080（firewalld/ufw 处于活动状态时）；非必要不要对公网开放 8080。
- 只允许可信网段访问 Web UI；如需公网访问，优先经 VPN 或带 WAF 的反向代理。
- WebKVM 自带**每虚拟机 nftables 防火墙**（入站规则、端口转发）：规则原子应用，并带有**确认窗口**（默认 30 秒，可在设置中 `firewall.confirm_window_secs` 配置 10–300 秒）——若修改后失联未确认，会自动回滚，防止把自己锁在外面。
- 不要手动删除 webkvm 管理的 nftables 表；变更请通过 UI/API。

### 12.5 SSH 与宿主机加固

- 仅允许密钥登录：`PasswordAuthentication no`、`PermitRootLogin prohibit-password`；
- 不要对外暴露 libvirt/Incus unix socket（它们等价于宿主机 root 权限）；
- 「宿主机终端」通过 PAM 校验真实系统账户（`/bin/login -p`），请限制系统账户数量与权限；
- 保持宿主机系统更新（WebKVM 的「状态 → 主机更新」支持 APT/DNF/Pacman，含安全公告标记与待重启检测）；
- 可选：启用 fail2ban 保护 SSH 与 8080 登录入口（WebKVM 自身已有登录限速：15 分钟内 5 次失败 → 锁定 15 分钟，回环地址始终受信）。

### 12.6 审计与日志

- 所有敏感操作写入 `/opt/webkvm/audit.log`（JSONL，含用户、角色、动作、资源、来源 IP），UI 有「审计」页；
- 服务日志：`journalctl -u webkvm`；启用 `WEBKVM_LOG_FILE` 后还写入 `/opt/webkvm/logs/backend.log`，UI「状态 → 日志」可读；
- 建议把审计日志纳入集中日志收集，并设置保留期。

### 12.7 systemd 加固与 Docker 信任边界

- 安装器写入的 systemd 单元已启用 `ProtectSystem=full`、`PrivateTmp`、`ProtectHostname`、`ProtectClock`、`RestrictRealtime`、`LockPersonality`、`SystemCallArchitectures=native` 与受限的 `ReadWritePaths`；
- 进程以 root 运行（读取 libvirt 镜像与 PAM 登录所需），这是与原生安装同级的信任模型；
- Docker 模式使用 `privileged` + 宿主 socket + 宿主认证文件，等价于宿主机 root 权限——**不要把该容器交给不可信操作者**。

### 12.8 备份安全

- 配置备份不包含机密字段，但虚拟机磁盘数据以明文归档；
- 备份目标（SFTP/S3/CIFS）凭据存放在 `DATA_DIR` 下，请保护 `/opt/webkvm`（建议 0700 权限、独立磁盘、纳入主机级备份）；
- 对 S3 目标启用服务端加密（SSE-S3/SSE-KMS），对 NFS/SMB 使用加密传输或加密卷。

---

## 13. 故障排查

### 13.1 安装失败

**先看日志**：

```bash
sudo tail -n 100 /var/log/webkvm-install.log
# 独立安装器的完整输出（如未 tee）不会被一键脚本完整捕获，可重跑并留存：
sudo bash /tmp/webkvm-install.sh 2>&1 | sudo tee -a /var/log/webkvm-install.log
```

失败时一键脚本会保留 `/var/tmp` 下的工作目录（路径会打印），便于附到 issue。

常见原因：

| 现象 | 处理 |
|---|---|
| `KVM not available (/dev/kvm not found)` | BIOS/UEFI 开启 VT-x/AMD-V；虚拟机宿主开启嵌套虚拟化（见 13.2）。 |
| `at least 2 GiB RAM is required` | 增加内存或换机器。 |
| `at least 5 GiB free space is required on /opt/webkvm` | 清理磁盘/扩容，或 `--data-dir` 指向更大分区。 |
| `no supported package manager found` | 仅支持 apt/dnf/yum/pacman 系发行版。 |
| `this release currently requires amd64/x86_64` | 当前发布版仅支持 amd64。 |
| `no usable network route found` | 检查默认路由/网卡；无外网但已有默认路由时仍可离线安装（见 4.5）。 |
| `port 8080 is already in use` | `ss -ltnp 'sport = :8080'` 找占用进程；释放端口或 `--port=其他`。 |
| 包安装失败（镜像超时） | 换国内源（第 3 节），安装器默认重试 3 次；可调 `WEBKVM_PKG_RETRIES` / `WEBKVM_PKG_RETRY_DELAY`。 |
| 健康检查失败并回滚 | `journalctl -u webkvm -n 100` 查看后端启动错误；TLS/端口/libvirt 未就绪最常见。 |

### 13.2 `/dev/kvm` 缺失或不可用

```bash
ls -l /dev/kvm
lsmod | grep -E 'kvm(_intel|_amd)?'
egrep -c '(vmx|svm)' /proc/cpuinfo        # >0 表示 CPU 支持虚拟化
systemd-detect-virt                        # 非 none 说明本机是虚拟机
```

处理：在 BIOS/UEFI 打开虚拟化；若本机是云主机/虚拟机，需要在控制台开启**嵌套虚拟化**（例如 `kvm_intel.nested=1` / `kvm_amd.nested=1`）。内核模块缺失时先加载：`sudo modprobe kvm_intel`（或 `kvm_amd`）。

### 13.3 8080 端口被占用

```bash
sudo ss -ltnp 'sport = :8080'
sudo lsof -iTCP:8080 -sTCP:LISTEN       # 或
```

- 若是旧 WebKVM 进程：`systemctl stop webkvm` 后重装，或直接 `systemctl restart webkvm`；
- 若是其他服务：释放端口，或安装时用 `--port=9090` 并同步修改防火墙放行规则；
- 修改端口后记得更新反向代理/SSH 隧道。

### 13.4 登录失败 / 登录后跳回登录页（登录循环）

按可能性排查：

1. **初始密码不对**：`sudo cat /opt/webkvm/admin-password.initial`；不存在则用 6.7 节重置。
2. **首次登录强制改密未完成**：系统会拦截其他请求，按页面提示完成改密即可。
3. **HTTPS 关闭但 Cookie 被强制 Secure**：若显式设置了 `WEBKVM_COOKIE_SECURE=true` 而服务跑在 HTTP 上，浏览器会丢弃会话 Cookie → 登录循环。去掉该变量，或改用 HTTPS。
4. **反向代理/隧道场景**：确认访问地址与 Cookie 域一致（IP 与域名不要混用），代理需透传 `Host`/`X-Forwarded-*`，并只在受信时开启 `WEBKVM_TRUST_PROXY=1`。
5. **浏览器限制 Cookie**：不要用隐私模式/禁用 Cookie 的浏览器；自签名证书页面选择继续访问。
6. **服务时间偏差**：JWT 有有效期，宿主时间需准确（`timedatectl status`，建议开启 NTP）。
7. 仍失败看日志：

```bash
journalctl -u webkvm -n 200 --no-pager | grep -Ei 'login|auth|cookie|csrf'
```

### 13.5 libvirt 连接失败（health 显示 libvirt down）

```bash
systemctl status libvirtd --no-pager       # 较新发行版也可能用 virtqemud
ls -l /var/run/libvirt/libvirt-sock
sudo virsh -c qemu:///system list --all
```

处理：

```bash
sudo systemctl enable --now libvirtd       # Debian/Ubuntu
# 或
sudo systemctl enable --now virtqemud.socket
sudo reboot                                # 极端情况下清空残留 socket 后重启
```

若是 SELinux/AppArmor 或权限问题，检查 `journalctl -u libvirtd` 与 `/var/log/libvirt/`。

### 13.6 TLS 证书问题

| 现象 | 处理 |
|---|---|
| 浏览器“证书不受信任” | 自签名证书的正常行为，导入信任即可；或改用域名 + Let's Encrypt。 |
| 证书与访问地址不匹配 | 证书 SAN 未包含当前 IP/域名；用 `openssl x509 -in /opt/webkvm/certs/webkvm.crt -noout -text \| grep -A1 'Subject Alternative Name'` 检查，必要时重新安装/重新生成证书。 |
| 服务器 IP 变了 | 重新生成证书：重跑安装器，或用 `openssl` 按同样命令重新生成后重启；有 Caddy 组合时 `sudo make regen-cert`。 |
| 域名拿不到 Let's Encrypt 证书 | 域名未解析/80/443 不可达属正常回退；放行端口与 DNS 后重试。 |
| 证书过期 | 自签名证书 10 年有效；到期前重新生成。 |

### 13.7 国内网络导致的安装/更新超时

- `apt-get update` / `dnf makecache` / `pacman -Sy` 超时：用 `scripts/cn-mirrors.sh` 换源（见 [CHINA-NETWORK.md](CHINA-NETWORK.md)）；
- GitHub raw/release 超时：使用 `--github-proxy` 或 `WEBKVM_GH_PROXY`；也可以手动下载二进制后用 `WEBKVM_BINARY` 本地安装；
- Docker 拉取失败：配置 Docker 镜像仓库（`/etc/docker/daemon.json` 的 `registry-mirrors`），并用 `docker pull hello-world` 自检；
- pip/npm/go 安装慢：见 [CHINA-NETWORK.md](CHINA-NETWORK.md) 的镜像配置；
- 临时网络抖动：安装器自带重试，稍后重跑即可（幂等）。

### 13.8 虚拟机/容器网络不通

| 现象 | 排查 |
|---|---|
| 实例从 `vmbr0` 拿不到 IP | `ip -br addr show vmbr0`；确认网桥 UP 且物理口 `master vmbr0`；检查路由器 DHCP 池；`journalctl -u NetworkManager`/`networkctl status`。 |
| 实例从 `vmbr1` 拿不到 IP | `systemctl status webkvm-vmbr1-dnsmasq.service`；`cat /etc/webkvm/vmbr1-dnsmasq.conf`；`ss -lunp \| grep :67`；防火墙是否放行 DHCP/DNS。 |
| NAT 实例无法出网 | 检查 `MASQUERADE` 规则（`iptables -t nat -L POSTROUTING -n` / `nft list ruleset` / firewalld internal 区）；确认宿主机能出网。 |
| 宿主 SSH 断了 | 用物理控制台/IPMI 执行 `sudo bash scripts/recover-network.sh`，或把 netplan 备份文件（`*.webkvm-removed`）恢复后 `netplan apply`。若**重启后**宿主机 SSH/Web 失联但虚拟机网络正常，见 13.11（网桥从口重复 IP）。 |
| 容器无网络 | 确认 Incus 默认 profile 的网卡指向 `vmbr0`（安装器会自动设置）；`incus profile show default`。 |

### 13.9 服务启动失败（systemd）

```bash
systemctl status webkvm --no-pager
journalctl -u webkvm -n 200 --no-pager
systemctl cat webkvm | head -40
```

常见原因：端口被占用、TLS 证书路径错误、`DATA_DIR` 权限、libvirt 不可达。修复后：

```bash
sudo systemctl daemon-reload
sudo systemctl restart webkvm
```

> 极端情况下可临时 `systemctl edit webkvm` 加 drop-in（例如调整 `Environment=BIND_ADDR=0.0.0.0`），改完 `systemctl daemon-reload && systemctl restart webkvm`。

### 13.10 Incus 容器模块不可用

```bash
systemctl status incus --no-pager
ls -l /var/lib/incus/unix.socket
sudo incus list
grep -i incus_connected /opt/webkvm/logs/backend.log 2>/dev/null || journalctl -u webkvm -n 100 | grep -i incus
```

处理：安装并启动 Incus（`sudo apt install incus && sudo systemctl enable --now incus && sudo incus admin init --auto`），在 systemd 单元/drop-in 里确认 `Environment=WEBKVM_INCUS_ENABLED=1`；非 root 运行需把用户加入 `incus-admin` 组（旧 LXD 为 `lxd` 组）。


### 13.11 重启后宿主机 SSH/Web 失联，但虚拟机一切正常（网桥从口重复 IP）

**症状**：服务器重启后，`ping`/SSH/Web UI 都无法访问宿主机，但里面的 KVM 虚拟机、
容器网络和服务完全正常；同一局域网内的 ARP 显示宿主机 IP 对应的 MAC 是物理网卡
（如 `enp3s0`）的 MAC，而不是网桥 `vmbr0` 的 MAC。

**根因**：Debian/Ubuntu 的 ifupdown 仍把静态 IP 配置在物理网卡上
（`/etc/network/interfaces` 的 `auto enp3s0` / `iface enp3s0 inet static`）。
WebKVM/安装器已把物理网卡作为从口加入 `vmbr0` 并把 IP 配在网桥上；重启时
`systemd-networkd` 先建桥，随后 `networking.service` 又执行 ifupdown，把**同一个 IP
再加到网桥从口上**。于是两个接口用不同 MAC 同时应答同一 IP 的 ARP（ARP flux），
管理流量被发往错误的 MAC/接口而黑洞；Linux 网桥的二层转发不依赖宿主 IP，所以
虚拟机的网络不受影响。

**快速确认**（在能进入宿主机的任意控制台/串口/IPMI，或从同一二层网络的机器上）：

```bash
ip -br addr                 # 物理网卡和 vmbr0 是否都挂着 192.168.6.76/24？
ip route                    # 默认路由是不是 dev enp3s0（应该是 vmbr0）？
ip -d link show vmbr0       # 物理网卡是否为 bridge_slave
journalctl -b -u networking.service --no-pager | tail -20
cat /etc/network/interfaces # 是否仍有 auto <物理网卡> / iface <物理网卡> 静态配置
```

**无需物理控制台的应急恢复**：宿主机通常仍保留 IPv6 链路本地地址，可从同一
二层网络的 Linux/Mac 执行 `ip -6 neigh`/`ndp -an` 找到 `vmbr0` 的 `fe80::...`，
然后 `ssh -6 root@fe80::xxxx%<网卡名>` 登录（Mac 上的 `%en1` 是 Wi-Fi/网卡名）。

登录后执行（**不会影响正在运行的 VM**）：

```bash
# 1) 从物理网卡上移除与网桥重复的地址（只删物理口，不动 vmbr0）
ip addr del 192.168.6.76/24 dev enp3s0
ip -6 addr flush dev enp3s0 scope global

# 2) 把默认路由切回网桥
ip route del default dev enp3s0 2>/dev/null || true
ip route add default via 192.168.6.1 dev vmbr0

# 3) 验证
ping -c 2 192.168.6.1
curl -kfsS https://127.0.0.1:8080/api/health
```

**永久修复**：备份并注释 `/etc/network/interfaces`（以及 `interfaces.d/`）里
物理网卡的 `auto` / `allow-hotplug` / `iface` 段落，物理网卡交由
`systemd-networkd` 作为网桥从口管理：

```bash
sudo cp -a /etc/network/interfaces /root/interfaces.bak.$(date +%s)
sudo sed -i '/^auto enp3s0$/,/^iface enp3s0 inet6 static$/ { s/^/#/ }' /etc/network/interfaces
# 需要按实际文件内容确认；注释后应只剩 lo 的配置
```

也可以直接用仓库自带的修复脚本（默认只检查，`--apply` 才修改；会备份网络状态、
自动移除重复 IP、修正默认路由并注释冲突的 ifupdown 配置）：

```bash
sudo bash scripts/fix-bridge-port-ip.sh            # dry-run
sudo bash scripts/fix-bridge-port-ip.sh --apply    # 修复
```

> 注意：WebKVM 服务本身没有坏，恢复网络后无需重启 `webkvm`；也**不需要重启服务器**。
> 验证完成前不要再次重启；修复后建议找维护窗口重启一次，确认
> `ip -br addr` 中物理网卡不再有 IP、`vmbr0` 持有管理 IP、默认路由 `dev vmbr0`。
---

## 14. 附录

### 14.1 关键路径

| 路径 | 内容 |
|---|---|
| `/usr/local/bin/webkvm` | 主二进制（server）。 |
| `/usr/local/bin/webkvm-cli` | CLI（若随安装源提供）。 |
| `/usr/local/bin/webkvm-update` | 自更新脚本（界面“更新”按钮依赖）。 |
| `/usr/local/bin/webkvm-backup.sh` | 宿主配置快速备份脚本。 |
| `/etc/systemd/system/webkvm.service` | systemd 单元（升级时备份为 `.previous`）。 |
| `/etc/webkvm/` | 运行时辅助配置（如 `vmbr1-dnsmasq.conf`、持久化网络文件）。 |
| `/opt/webkvm/` | **数据目录（DATA_DIR）**：配置与状态。 |
| `/opt/webkvm/config.json` | 持久化设置（`server.bind_addr`、`server.port`、`server.tls_*` 等，0600）。 |
| `/opt/webkvm/users.json` | 用户（bcrypt 哈希，0600）。 |
| `/opt/webkvm/jwt.key` | JWT 签名密钥（0600，自动生成）。 |
| `/opt/webkvm/audit.log` | JSONL 审计日志。 |
| `/opt/webkvm/admin-password.initial` | 初始管理员密码（0600，首次改密后删除）。 |
| `/opt/webkvm/certs/webkvm.crt` / `.key` | 自签名证书与私钥。 |
| `/opt/webkvm/tls/` | Let's Encrypt 自动证书缓存。 |
| `/opt/webkvm/pools/webkvm-disks` | VM 磁盘池。 |
| `/opt/webkvm/pools/webkvm-isos` | ISO 库。 |
| `/opt/webkvm/pools/webkvm-incus` | 容器 rootfs 池（启用 Incus 时）。 |
| `/opt/webkvm/backup/` | 备份 targets/schedules/jobs 注册表。 |
| `/opt/webkvm/logs/backend.log` | 文件日志（安装器默认启用 `WEBKVM_LOG_FILE`）。 |
| `/var/log/webkvm-install.log` | 一键安装脚本日志（可用 `WEBKVM_INSTALL_LOG` 覆盖）。 |
| `/var/log/webkvm-docker-install.log` | Docker 一键安装脚本日志。 |
| `/opt/webkvm-repo` | 一键脚本克隆的仓库（保留用于后续升级）。 |

### 14.2 环境变量表

**后端运行环境（systemd 单元 / `.env` / shell，参考 `.env.example`）**

| 变量 | 默认 | 说明 |
|---|---|---|
| `PORT` | `8080` | 监听端口。 |
| `BIND_ADDR` | `127.0.0.1` | 监听地址；安装器写入 systemd 单元，`0.0.0.0` 表示所有网卡。 |
| `DATA_DIR` | `/opt/webkvm` | 数据目录。 |
| `REPO_DIR` | `$DATA_DIR/source` | 辅助脚本/源码位置。 |
| `LIBVIRT_URI` | `qemu:///system` | libvirt 连接 URI。 |
| `JWT_SECRET` | 自动生成 | 未设置时生成 256 位密钥写入 `{DATA_DIR}/jwt.key`（0600），弱密钥会被拒绝。 |
| `WEBKVM_LOG_FILE` | 空 | 额外写文件的日志路径（UI 日志页读它）。 |
| `WEBKVM_LOG_FORMAT` | `json` | `json` / `text`。 |
| `WEBKVM_LOG_LEVEL` | `info` | `debug`/`info`/`warn`/`error`。 |
| `TMPDIR` | `/var/tmp`（安装器写入） | 上传临时目录，避免 `/tmp` tmpfs 过小。 |
| `VNC_PROXY_HOST` | `127.0.0.1` | noVNC 代理目标地址。 |
| `PUBLIC_HOST` | 空（自动检测） | 写入 `.rdp` / `.vv` 的对外 IP/域名。 |
| `CORS_ORIGIN` | 空（仅同源） | 允许的跨域来源，逗号分隔；`*` 表示全部。 |
| `TLS_CERT` / `TLS_KEY` / `TLS_DOMAIN` | 空 | 后端直接提供 HTTPS 时使用；安装器会写入 `config.json` 的 `server.tls_*`。 |
| `WEBKVM_COOKIE_SECURE` | `true` | 会话 Cookie 的 Secure 标记；TLS 关闭时会自动不加（显式设置则强制）。 |
| `WEBKVM_TRUST_PROXY` | `0` | 是否信任 `X-Forwarded-For`（仅在反向代理后开启）。 |
| `WEBKVM_TRUSTED_RATELIMIT_CIDRS` | 空 | 跳过登录限速的可信 CIDR（回环始终受信；**不要**写 `0.0.0.0/0`）。 |
| `WEBKVM_ADMIN_PASSWORD` | 空 | 首次启动种子管理员密码（一般由 `--admin-password` 使用）。 |
| `WEBKVM_INCUS_ENABLED` | `0` | 启用容器模块（安装器默认写入 `1`）。 |
| `INCUS_SOCKET` | 自动 | Incus/LXD unix socket 覆盖。 |
| `WEBKVM_ALLOW_UPDATE` | 安装器写 `1` | 是否允许界面触发自更新；设为 `0` 可禁用。 |

**安装器变量**

| 变量 | 说明 |
|---|---|
| `WEBKVM_PREFIX` | 安装前缀，默认 `/usr/local`。 |
| `WEBKVM_DATA_DIR` | 数据目录，默认 `/opt/webkvm`。 |
| `WEBKVM_PORT` / `WEBKVM_BIND_ADDR` | 端口 / 监听地址。 |
| `WEBKVM_HTTPS` | `yes`/`no`。 |
| `WEBKVM_TLS_DOMAIN` | 证书域名（可选）。 |
| `NETWORK_MODE` | `bridge` / `nat` / `both` / `none`。 |
| `WEBKVM_NAT_BRIDGE` | 在 bridge 模式额外创建 `vmbr1` NAT 桥（`1` 启用）。 |
| `BRIDGE_DHCP` / `BRIDGE_STATIC_IP` / `BRIDGE_STATIC_GW` / `BRIDGE_STATIC_DNS` | 网桥地址配置。 |
| `BRIDGE_SLAVE` / `BRIDGE_NAME` | 指定物理网卡 / 网桥名（setup-network.sh）。 |
| `WEBKVM_NONINTERACTIVE` | `1` = 完全无人值守（不读取 `/dev/tty`）。 |
| `WEBKVM_INSTALL_INCUS` | `1`/`0`，默认 `1`。 |
| `WEBKVM_ADMIN_PASSWORD` | 初始管理员密码。 |
| `WEBKVM_BINARY` | 本地二进制路径。 |
| `WEBKVM_BINARY_URL` / `WEBKVM_BINARY_SHA256` | HTTPS 二进制地址 + 强制校验和。 |
| `WEBKVM_SERVICE` | systemd 单元名，默认 `webkvm.service`。 |
| `WEBKVM_INSTALL_REPO` / `WEBKVM_INSTALL_BRANCH` | 一键脚本的仓库地址/分支。 |
| `WEBKVM_INSTALL_TARBALL_URL` | 一键脚本的源码 tarball 地址：http(s) 直链或本地文件路径（规避 GitHub）。 |
| `WEBKVM_INSTALL_LOG` | 一键脚本日志路径。 |
| `WEBKVM_CN_MIRRORS` / `WEBKVM_CN_COMPONENTS` / `WEBKVM_GH_PROXY` | 安装器国内镜像源与 GitHub 加速（见第 3 节）。 |
| `WEBKVM_CN_MIRROR` / `WEBKVM_CN_DOCKER_MIRROR` / `WEBKVM_CN_GITHUB_PROXY` / `WEBKVM_CN_ROOT` / `WEBKVM_CN_DRY_RUN` | `scripts/cn-mirrors.sh` 的等价环境变量（单独运行换源脚本时使用）。 |
| `WEBKVM_PKG_RETRIES` / `WEBKVM_PKG_RETRY_DELAY` | 包操作重试次数/间隔（默认 3 / 4 秒）。 |
| `WEBKVM_UPDATE_REF` / `WEBKVM_DOCKER_IMAGE` | 更新脚本下载 ref / Docker 镜像名覆盖。 |

### 14.3 命令速查

```bash
# 服务
systemctl status webkvm --no-pager
journalctl -u webkvm -f
sudo systemctl restart webkvm
/usr/local/bin/webkvm version

# 健康检查
curl -kfsS https://127.0.0.1:8080/api/health
sudo webkvm-cli status

# 虚拟机
sudo webkvm-cli vms list
sudo webkvm-cli vms create --name demo --ram 2048 --vcpus 2 --disk 20 --image debian-12
sudo webkvm-cli vms start <id>
sudo webkvm-cli vms stop <id>
sudo webkvm-cli vms snapshot <id> create pre-upgrade
sudo webkvm-cli vms snapshot <id> revert <sid>

# 容器
sudo webkvm-cli vms create --name ct --ram 512 --vcpus 1 --type container --image images:alpine/3.21
sudo incus list

# 镜像 / 存储 / 备份
sudo webkvm-cli images pull-cloud ubuntu-24.04
sudo webkvm-cli storage pools
sudo webkvm-cli storage isos
sudo webkvm-cli backup targets
sudo webkvm-cli backup run <target>
sudo webkvm-cli backup prune <target>

# 用户
sudo webkvm-cli users list
sudo webkvm-cli users update admin --password '新密码'

# libvirt
sudo virsh -c qemu:///system list --all
sudo virsh -c qemu:///system pool-list --all

# 网络
ip -br addr show vmbr0
ip -br addr show vmbr1
bridge link show

# 升级 / 回滚 / 卸载
sudo ./packaging/standalone/install.sh --yes   # 重跑安装器升级
sudo webkvm-update                             # 从 release 升级
sudo make rollback                             # Makefile 安装场景回滚
sudo ./packaging/standalone/uninstall.sh       # 卸载（保留数据）
```

### 14.4 中文文档索引

| 文档 | 说明 |
|---|---|
| [README.zh.md](../../README.zh.md) | 项目中文 README（功能总览与快速开始）。 |
| [DEPLOYMENT.md](DEPLOYMENT.md) | 本文：完整中文部署说明。 |
| [CHINA-NETWORK.md](CHINA-NETWORK.md) | 中国大陆网络优化：换源、GitHub 加速、Docker 镜像。 |
| [INSTALLATION.md](INSTALLATION.md) | 安装指南（与英文版对应的分步说明 + 技术文档）。 |
| [USAGE.md](USAGE.md) | 使用指南：虚拟机、容器、存储、网络、备份。 |
| [CLI.md](CLI.md) | `webkvm-cli` 命令参考。 |
| [FAQ.md](FAQ.md) | 常见问题。 |
| [DOCKER.md](DOCKER.md) | Docker 部署细节与挂载/权限说明。 |
| [API.md](API.md) | REST 与 WebSocket API 参考。 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 架构深入。 |
| [COMPARISON.md](COMPARISON.md) | 与 Proxmox VE / Cockpit / virt-manager 对比。 |
| [SECURITY.md](SECURITY.md) | 安全策略与漏洞披露。 |
| [runbooks/RUNBOOKS.md](runbooks/RUNBOOKS.md) | 运维 Runbook 汇总（日常运维、升级回滚、灾难恢复、安全模型）。 |

### 14.5 文档与实现的核对说明

本文写作时对照了以下实现文件；若你阅读的文档与运行行为不一致，请以仓库当前实现为准，并欢迎提 issue：

- 安装器：`packaging/standalone/install.sh`（交互项、默认值、健康检查、systemd 单元、防火墙放行、国内换源调用）；
- 一键脚本：`scripts/install-webkvm.sh`（仓库克隆到 `/opt/webkvm-repo`、日志路径、非交互判定、国内加速透传）；
- 国内换源：`scripts/cn-mirrors.sh`（参数/环境变量/备份恢复行为，详见 [CHINA-NETWORK.md](CHINA-NETWORK.md)）；
- 卸载/升级：`packaging/standalone/uninstall.sh`、`packaging/standalone/update.sh`；
- 网络：`scripts/setup-network.sh`（`vmbr0`/`vmbr1`/`dummy0`/dnsmasq/`MASQUERADE`）；
- 运行时环境变量：`.env.example` 与 `backend/internal/config/config.go`；
- Docker：`docker-compose.yml`、`packaging/docker/install.sh`；
- 备份：`backend/internal/backupstore/`（目标类型、保留策略、归档结构）；
- 健康检查：`GET /api/health`（`status`/`libvirt`/`disk_free`/`version` 等字段）。

已知的文档差异（以实现为准）：

- `packaging/standalone/install.sh` 的 `--help` 头注释写 `--bind=ADDR (default: 0.0.0.0)`，但**实际**交互/无人值守的监听地址默认是 `127.0.0.1`（代码 `confirm DEFAULT_BIND ... "127.0.0.1"`，本文按实际行为编写）；
- 仓库内 `docs/INSTALLATION.md` 与 `Makefile` 注释对最低发行版版本的表述不完全一致；
- `.env.example` 中 `CORS_ORIGIN` 注释为 `*`，而代码默认是空（仅同源）；
- 从 GitHub Release tarball 安装时，tarball 可能未包含 `scripts/cn-mirrors.sh`，此时 `--cn-mirrors` 只告警并继续（不影响安装）。

若后续版本修订，本表会同步更新。
