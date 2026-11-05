# WebKVM

<div align="center">

**面向 Linux 的轻量级单二进制原生虚拟机与容器管理器**

[![CI Status](https://github.com/shigeyumunaodai/webkvm-chinese/actions/workflows/ci.yml/badge.svg)](https://github.com/shigeyumunaodai/webkvm-chinese/actions/workflows/ci.yml)
[![Go Version](https://img.shields.io/badge/Go-1.26-00ADD8?style=flat&logo=go)](https://golang.org)
[![Svelte Version](https://img.shields.io/badge/Svelte-5_Runes-FF3E00?style=flat&logo=svelte)](https://svelte.dev)
[![TailwindCSS](https://img.shields.io/badge/TailwindCSS-v4-38B2AC?style=flat&logo=tailwind-css)](https://tailwindcss.com)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPLv3-blue.svg)](LICENSE)
[![Zero Dependencies](https://img.shields.io/badge/Runtime_Dependencies-0-success.svg)](#architecture)

[**English**](README.md) • [**Español**](README.es.md) • [**简体中文**](README.zh.md) • [**中文文档**](docs/zh/README.md)

</div>

> **简体中文汉化版仓库说明：** 本仓库 [`webkvm-chinese`](https://github.com/shigeyumunaodai/webkvm-chinese) 是 [Slaker19/webkvm](https://github.com/Slaker19/webkvm) 的汉化 fork，内置完整 `zh` 中文界面、中文文档、国内网络镜像工具，并提供编译好的 Linux Release。上游更新会自动合并并保留汉化，维护方式见 [docs/zh/GITHUB-SYNC.md](docs/zh/GITHUB-SYNC.md)。

---

## 什么是 WebKVM？

**WebKVM** 可以把任意一台现有 Linux 服务器（Ubuntu、Debian、Fedora、Arch、AlmaLinux、Rocky）在 **1 分钟内**变成快速、私有的云虚拟化平台，**无需重装系统，也不会劫持你的操作系统**。

WebKVM 使用 **Go** 编写，通过 CGO 绑定 `libvirt`，并内嵌 **Svelte 5** 单页 Web 应用，最终编译为一个 **约 14 MB 的单个静态可执行文件**。空闲时它只占用 **约 15 MB 内存**，即可统一管理完整的 **QEMU/KVM 虚拟机**与轻量级 **Incus/LXC 系统容器**。

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

---

## 为什么选择 WebKVM？（恰到好处的定位）

| 功能 / 指标 | WebKVM | Proxmox VE | Cockpit（Machines） | virt-manager |
|---|---|---|---|---|
| **安装体积** | **单二进制（约 14 MB）** | 完整 ISO / 接管整个操作系统 | 系统守护进程与模块 | 桌面 GTK 应用 |
| **空闲内存占用** | **约 15 MB** | 1.2 GB – 2.5 GB | 约 80 MB | 不适用（仅客户端） |
| **宿主系统保留度** | **100% 原样保留**（标准发行版） | 需要定制 Debian 分支 | 原样保留 | 原样保留 |
| **KVM 虚拟机** | 支持——完整支持 | 支持——完整支持 | 支持——基础支持 | 支持——完整支持 |
| **Incus / LXC 容器** | **支持——原生统一视图** | 部分支持——需自写 LXC 脚本 | 不支持原生 Incus | 不支持 |
| **cloud-init 与镜像中心** | **支持——一键 5 秒部署** | 部分支持——需手工模板 | 不支持——需手工配置 | 不支持——需手工配置 |
| **内嵌 Web 终端** | **WebGL + Unicode 11 + TUI 功能键** | 部分支持——基础 noVNC / xterm | 部分支持——基础终端 | 不支持——仅桌面终端 |
| **实时传输速度与剩余时间** | **支持——实时 MB/s 与进度** | 部分支持——基础进度 | 不支持 | 不支持 |
| **零令牌本地 CLI** | **支持——`webkvm-cli` 自动认证** | 部分支持——`pvesh` / `qm` | 不支持——`cockpit-bridge` | 部分支持——仅 `virsh` |
| **多控制台实时矩阵** | **支持——Multi-View 交互宫格** | 不支持——一次一台虚拟机 | 不支持——一次一台虚拟机 | 部分支持——多窗口 |

---

## 快速开始（1 分钟安装）

### 原生安装（推荐）

在服务器上以 root 身份运行无人值守安装器：

```bash
curl -fsSL https://raw.githubusercontent.com/shigeyumunaodai/webkvm-chinese/main/scripts/install-webkvm.sh | sudo bash
```

安装器会自动检测包管理器（`apt`、`dnf`、`pacman`），安装所需的虚拟化软件包（`qemu-kvm`、`libvirt-daemon-system`），配置双网桥 / NAT 网络，生成 TLS 证书，并注册 `webkvm.service` systemd 服务单元。

**访问 Web UI**：
- URL：`https://<你的服务器IP>:8080`（在本机访问则用 `https://localhost:8080`）
- 初始凭据会在安装结束时显示，并保存在 `/opt/webkvm/admin-password.initial`。

> 提示：安装器默认只监听 `127.0.0.1`（仅本机）。要从局域网访问，请在安装时把 Bind address 改为 `0.0.0.0` 或服务器 LAN IP（务必配合 HTTPS），或参见[《完整中文部署说明》](docs/zh/DEPLOYMENT.md)。


### 中文版 Release 下载（推荐局域网 / 离线宿主机）

推送 `zh-v*` tag 时会自动发布可直接安装的 tarball、原始二进制和 `SHA256SUMS`：

- Release 页面：<https://github.com/shigeyumunaodai/webkvm-chinese/releases/latest>
- 国内加速：在 GitHub 链接前加 `https://gh-proxy.com/`

```bash
# 从 Release 页面下载 tarball 与 SHA256SUMS 后：
sha256sum --check --ignore-missing SHA256SUMS
mkdir -p webkvm-<版本> && tar xzf webkvm-<版本>-linux_amd64.tar.gz -C webkvm-<版本>
cd webkvm-<版本>
sudo WEBKVM_BINARY=backend/webkvm bash packaging/standalone/install.sh --yes
```

如果服务器无法访问 GitHub，把 tarball 拷进去执行同样的 `WEBKVM_BINARY=`
安装命令即可；安装器默认不联网下载二进制，也不会在服务器上编译。

### Docker 安装

如果你更愿意让 WebKVM 以容器方式连接宿主机的 libvirt socket：

```bash
curl -fsSL https://raw.githubusercontent.com/shigeyumunaodai/webkvm-chinese/main/scripts/install-docker.sh -o /tmp/webkvm-docker-install.sh && sudo bash /tmp/webkvm-docker-install.sh
```
*（自定义卷挂载与安全权限说明见 [docs/zh/DOCKER.md](docs/zh/DOCKER.md)。）*

> **注意：** 当前 Docker 镜像（`slaker1908/webkvm`）仍是上游英文界面。需要中文界面请使用上面的原生 / Release 安装方式，或在本仓库执行 `docker compose build` 自行构建。

---

## 核心能力

### 1. 统一混合计算（KVM 虚拟机 + Incus 容器）
- 在同一个统一仪表盘中管理硬件虚拟化虚拟机（Windows、Linux、BSD）与亚秒级启动的 LXC 系统容器。
- 通过 Server-Sent Events（SSE）实时推送 CPU、内存、磁盘与网络指标。
- 在线热扩容磁盘，客户机无需停机。

### 2. 镜像中心与秒级 cloud-init 部署
- 预置 Ubuntu、Debian、Alpine、Fedora、Rocky 与 AlmaLinux 的官方云镜像（`.qcow2`）。
- 借助写时复制（Copy-On-Write，COW）后备文件，可在 **5 秒内**完成实例部署。
- 启动时自动注入 SSH 公钥、用户名、密码与自定义 `#cloud-config` 脚本。

### 3. 高性能 WebGL 宿主机终端
- 基于现代 `@xterm/xterm`，支持 **GPU WebGL 加速**与 **Unicode 11**，流畅渲染 `btop`、`htop`、`mc`、`nano` 与 `yazi`。
- 内置 TUI 工具栏，提供功能键（`F1`–`F12`）、`Esc`、`Tab` 与 `Ctrl+C`。
- **后台持久化**：在 WebKVM 各页面之间切换不会中断当前 shell 会话。
- 使用系统 PAM 安全认证（不存在不安全的 root 自动登录）。

### 4. 实时下载速度与指标
- 实时平滑下载速率显示（例如 `52.4 MB/s · 120 MB / 1.8 GB · ETA 25s (45%)`）。
- 在底部可停靠的 **任务抽屉**（`Ctrl+J` / `⌘J`）中全局跟踪。

### 5. 多视图矩阵
- 在可自定义的实时宫格中同时监控并操作多台运行中虚拟机的图形控制台。

### 6. 内置安全架构
- **一次性临时凭证**：WebSocket 使用存于内存、有效期 30 秒的一次性凭证完成认证。查询字符串中永远不会泄露长期 JWT。
- **Anti-SSRF 安全拨号器**：远程镜像下载会校验并拦截私有 / 回环 / 链路本地 IPv4 与 IPv6 地址段，并对每次重定向重新校验。
- **防火墙安全应用**：宿主机防火墙变更自带 30 秒自动回滚计时器，防止误操作把管理员锁在门外。

### 7. 原生内核软件 RAID 与存储池
- **即时发现**：直接解析内核 sysfs（`/sys/block/md*/md`），无子进程开销。
- **自动化生命周期**：一键格式化阵列（ext4、xfs、btrfs）、生成持久化 systemd 挂载单元，并自动创建 WebKVM 存储池。
- **无损挂载**：接入已有 RAID 阵列时不会丢失数据。
- **在线维护**：在 UI 中实时报告同步、检查与巡检（scrub）进度。

### 8. 应用商店与辅助脚本（600+ 应用）
- **高速目录**：流式 tarball 摄取可在 1 秒内索引 600 多个 Proxmox/Incus 社区应用。
- **无人值守与交互式安装**：既支持后台自动部署，也支持直接在宿主机控制台启动交互式 TUI 安装器。

### 9. 硬件与 VFIO 直通管理器
- **IOMMU 诊断**：即时预检（Intel VT-d / AMD-Vi），并按 IOMMU 分组展示设备层级。
- **安全设备隔离**：一键切换为 `vfio-pci` 驱动；若绑定失败，会自动重新探测驱动并回滚。

### 10. 宿主机操作系统更新
- **多发行版支持**：集成 APT（Debian/Ubuntu）、DNF（RHEL/Fedora）与 Pacman（Arch）的软件包更新。
- **安全可见性**：安全公告标识、分类筛选（安全更新、常规更新、保留更新）以及待重启检测。

---

## 零令牌命令行工具（`webkvm-cli`）

WebKVM 自带完整的命令行工具（`webkvm-cli`），面向自动化、脚本化与 SSH 管理场景。

在宿主机上以 root 身份运行时，**无需任何令牌或登录步骤**（借助本地密钥自动认证，并从 `/opt/webkvm/config.json` 自动探测本地监听端点）：

```bash
# 列出所有虚拟机与容器
webkvm-cli vms list

# 5 秒内部署一台新的 Debian 12 虚拟机
webkvm-cli vms create --name debian-prod --ram 2048 --vcpus 2 --disk 20 --image debian-12

# 创建一台轻量级 Alpine Incus 容器
webkvm-cli vms create --name alpine-ct --ram 512 --vcpus 1 --type container --image images:alpine/3.21

# 下载官方云镜像
webkvm-cli images pull-cloud ubuntu-24.04

# 直接在终端中管理用户账户
webkvm-cli users update admin --password "NewSecurePassword123!"

# 配合 jq 编写脚本（--json 参数）
webkvm-cli --json vms list | jq '.[] | select(.state=="running") | .name'
```
*（完整语法与示例见 [docs/zh/CLI.md](docs/zh/CLI.md)。）*

---

## 深入文档

| 指南 | 说明 |
|---|---|
| [**完整中文部署说明（DEPLOYMENT.md）**](docs/zh/DEPLOYMENT.md) | 面向首次部署者的旗舰中文指南：环境要求、国内网络准备、各安装方式、网络模式、存储与备份、升级回滚、安全加固与故障排查。 |
| [**国内网络优化（CHINA-NETWORK.md）**](docs/zh/CHINA-NETWORK.md) | 中国大陆网络环境下的镜像源切换、GitHub 加速、Docker 镜像仓库与验证方法。 |
| [**用户指南（USAGE.md）**](docs/zh/USAGE.md) | 虚拟机创建、存储池、网络、cloud-init 与备份的完整使用流程。 |
| [**安装指南（INSTALLATION.md）**](docs/zh/INSTALLATION.md) | 分步安装、自定义端口、双网桥 / NAT 网络、Let's Encrypt TLS 与 systemd 单元。 |
| [**常见问题（FAQ.md）**](docs/zh/FAQ.md) | 30 多个详细问答，涵盖架构、Wi-Fi 笔记本、存储格式与故障排查。 |
| [**对比矩阵（COMPARISON.md）**](docs/zh/COMPARISON.md) | WebKVM、Proxmox VE、Cockpit 与 virt-manager 的技术对比。 |
| [**CLI 参考（CLI.md）**](docs/zh/CLI.md) | `webkvm-cli` 的完整命令文档。 |
| [**REST 与 WebSocket API（API.md）**](docs/zh/API.md) | 完整的 OpenAPI 风格参考，含 JSON 请求 / 响应载荷。 |
| [**架构深入（ARCHITECTURE.md）**](docs/zh/ARCHITECTURE.md) | 内部架构：CGO libvirt 绑定、Incus 驱动与内嵌 Svelte 5 引擎。 |
| [**Docker 部署（DOCKER.md）**](docs/zh/DOCKER.md) | 以容器方式运行同一二进制：宿主机前提、绑定挂载与自更新例外。 |
| [**运维 Runbook**](docs/zh/runbooks/RUNBOOKS.md) | 日常运维、升级 / 回滚、灾难恢复与安全模型。 |
| [**安全策略（SECURITY.md）**](docs/zh/SECURITY.md) | 威胁模型、SSRF 防护、RBAC 角色与漏洞披露流程。 |
| [**GitHub 上传与上游自动同步（GITHUB-SYNC.md）**](docs/zh/GITHUB-SYNC.md) | Fork 上传到 GitHub、自动同步上游更新并保留汉化、自动构建中文版 Release。 |

---

## 从源码构建

前提：Go ≥ 1.26、Node.js ≥ 20、`libvirt-dev`、`gcc`。

```bash
# 克隆仓库
git clone https://github.com/shigeyumunaodai/webkvm-chinese.git
cd webkvm

# 构建完整单二进制（编译 Svelte 前端并嵌入 backend/webkvm）
make build

# 运行单元测试
go test ./...
cd frontend && npm test
```

---

## 许可证

WebKVM 是基于 [GNU Affero 通用公共许可证 v3.0（AGPLv3）](LICENSE) 的开源软件。
