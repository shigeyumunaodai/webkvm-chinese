# WebKVM — 常见问题（FAQ）

全面解答关于 WebKVM 的常见架构、技术、运维和故障排查问题。

[**English**](../FAQ.md) • [**Español**](../FAQ.es.md) • [**简体中文**](FAQ.md)

---

## 目录

1. [常规与架构](#1-常规与架构)
2. [虚拟机与 QEMU/KVM](#2-虚拟机与-qemukvm)
3. [Incus 与 LXC 容器](#3-incus-与-lxc-容器)
4. [网络与动态 IP](#4-网络与动态-ip)
5. [存储池与镜像中心](#5-存储池与镜像中心)
6. [WebGL 终端与控制台](#6-webgl-终端与控制台)
7. [安全与访问控制](#7-安全与访问控制)
8. [故障排查与诊断](#8-故障排查与诊断)

---

## 1. 常规与架构

### WebKVM 与 Proxmox VE 或 Cockpit 有何不同？
- **Proxmox VE** 需要占用整台机器，或使用其定制的 Debian 发行版重新格式化，并运行多个重量级后台守护进程，空闲时消耗 1–2 GB 内存。
- **Cockpit** 是一个基础的服务器管理面板，缺少原生 Incus/LXD 容器管理、镜像中心下载、自动化 cloud-init 注入、安全的防火墙回滚以及高性能 WebGL 终端集成。
- **WebKVM** 提供现代化的云体验（即时 COW 克隆、cloud-init 模板、Incus 容器和 WebGL 终端），打包为**单个约 14 MB 的静态 Go 二进制**，使用**不到 20 MB 内存**，可直接安装在现有 Linux 发行版之上，无需修改操作系统。

### 最低系统要求是什么？
- **CPU**：1 核（x86_64，在 BIOS/UEFI 中启用了 VT-x/AMD-V 虚拟化扩展）。也支持 ARM64。
- **内存**：最低 2 GB（WebKVM 自身约使用 15 MB；其余内存可供虚拟机和容器使用）。
- **磁盘**：5 GB 可用磁盘空间，用于宿主机二进制和基础镜像。
- **操作系统**：任何标准 Linux 发行版（Debian 11+、Ubuntu 20.04+、Fedora 38+、Arch Linux、AlmaLinux 9+、Rocky Linux 9+）。

### WebKVM 能在 Raspberry Pi 或 ARM64 开发板上运行吗？
可以！针对 `linux/arm64` 编译后，WebKVM 可管理 ARM64 KVM 虚拟机（通过 UEFI AAVMF）和原生 ARM64 Incus/LXC 容器，并具备完整的硬件加速。

### WebKVM 能在另一台虚拟机内运行吗（嵌套虚拟化）？
可以。如果你的云服务商或虚拟机监控程序支持嵌套虚拟化（例如 `kvm_intel.nested=1` 或 `kvm_amd.nested=1`），WebKVM 会检测到 `/dev/kvm`，并无缝运行硬件加速的客户机。

---

## 2. 虚拟机与 QEMU/KVM

### 应该选择 QCOW2 还是 RAW 磁盘格式？
- **QCOW2（推荐）**：精简置备（仅当客户机写入数据时才占用磁盘空间），支持快速快照、从基础镜像进行瞬时写时复制（COW）克隆，以及在线卷扩容。
- **RAW**：直接块布局，裸 I/O 性能略快，但会预先占用整个磁盘分配，且不支持后备文件或瞬时快照。

### Cloud-Init 配置是如何工作的？
WebKVM 使用标准的 `NoCloud` ISO/seed 机制。当你创建虚拟机或从云模板实例化虚拟机时，WebKVM 会生成一个临时 ISO，其中包含 `#cloud-config` 指令（用户账户、授权的 SSH 密钥、网络接口、主机名以及安装后执行的 bash 脚本）。客户机操作系统在首次启动时读取该磁盘，并在数秒内完成自我配置。

### 快照具有文件系统一致性吗？
是的。当客户机安装了 `qemu-guest-agent`（WebKVM 云模板会自动预配置）时，WebKVM 会在创建在线磁盘快照之前发出文件系统冻结（`fsfreeze`），确保零数据库或文件系统损坏。

### 虚拟机运行中可以扩容磁盘吗？
可以！对于通过 VirtIO 挂载的 QCOW2 磁盘，WebKVM 支持**在线磁盘扩容**，无需客户机停机。只需在界面或 CLI 中增大磁盘大小；虚拟机监控程序会在线扩展块分配，现代 Linux 内核会自动识别新的磁盘边界。

---

## 3. Incus 与 LXC 容器

### Incus 容器与 Docker 容器有什么区别？
- **Docker / Podman**：应用容器，设计为运行单个微服务进程（例如 `nginx` 或 `redis`），根文件系统是临时的。
- **Incus / LXC**：完整的**系统容器**，运行完整的 Linux 发行版，拥有自己的 `systemd` init 进程、SSH 服务器、包管理器（`apt`/`apk`/`dnf`）、syslog 和 cron 作业。它们的体验和行为与虚拟机完全一致，但可在 200 毫秒内启动，且仅消耗 30–50 MB 内存。

### KVM 虚拟机和 Incus 容器可以共享同一个网络吗？
可以。KVM 虚拟机和 Incus 系统容器都接入相同的 Linux 网桥（`vmbr0` 用于局域网访问，`vmbr1` 用于私有 NAT）。虚拟机和容器可以以完整的硬件线速直接相互通信。

---

## 4. 网络与动态 IP

### 如果宿主机通过 DHCP 更改了 IP 地址会怎样？
WebKVM 可无缝处理宿主机动态 IP：
1. **服务器套接字**：Go 后端绑定到 `0.0.0.0:8080`，无论 IP 如何变化，都会持续在任何接口上接受流量。
2. **动态 UI 端点**：Svelte Web 前端会从 `window.location.host` 动态解析所有 API 和 WebSocket 端点。
3. **客户机网络隔离**：网桥网络（`vmbr0`）上的虚拟机与你的路由器保持各自独立的 DHCP 租约，而 `vmbr1` 上的虚拟机使用 WebKVM 的内部 NAT 路由器（`100.0.0.1`）。

### 如何在通过 Wi-Fi 连接的笔记本电脑上使用 WebKVM？
标准 Wi-Fi 接口（`wlan0`）在硬件层面阻止多 MAC 二层桥接。使用 Wi-Fi 笔记本电脑时：
- 创建虚拟机时选择 **NAT 网络（`vmbr1`）**。
- WebKVM 会透明地通过宿主机当前活动的 Wi-Fi 连接路由虚拟机流量。

### 如何使用本地主机名而不是 IP 访问 WebKVM？
你可以使用 mDNS 主机名访问 WebKVM：`https://<hostname>.local:8080`（例如 `https://webkvm.local:8080`）。macOS、iOS、Android、Linux 和 Windows 均原生支持 mDNS。

---

## 5. 存储池与镜像中心

### 什么是"存储池用途"分离？
为防止意外损坏和安全配置错误，WebKVM 严格将存储池分类为：
- **`disk` 存储池**：用于虚拟机根卷、数据磁盘和容器存储。
- **`iso` 存储池**：用于只读安装介质。
后端以失败即拒绝（fail-closed）的方式校验存储池用途，防止磁盘被上传到 ISO 存储池，反之亦然。

### 镜像中心如何加速部署？
镜像中心让你无需下载 ISO 并逐步点击操作系统安装程序，而是缓存官方预构建的云镜像（`ubuntu-24.04.qcow2`、`debian-12.qcow2`、`alpine-3.24.qcow2`）。创建虚拟机时会在数毫秒内生成一个精简 COW 覆盖层，而无需复制原始基础磁盘。

---

## 6. WebGL 终端与控制台

### 为什么宿主机终端要求系统登录？
出于严格的安全性和多用户管理考虑，WebKVM 通过安全的 PTY 执行 `/bin/login -p`，而不是打开未经认证的 root shell。你必须使用有效的 Linux 系统用户凭据进行认证，从而防止未经授权的浏览器访问。

### 为什么 `btop`、`htop`、`mc` 和 `nano` 等 TUI 工具可以流畅运行？
1. **TrueColor 与 UTF-8**：PTY 环境强制使用 `TERM=xterm-256color`、`COLORTERM=truecolor` 和 `LANG=C.UTF-8`。
2. **Unicode 11 引擎**：xterm.js 使用官方的 Unicode 11 插件，为 emoji、盲文图案和制表符号计算精确的单元格宽度。
3. **二进制 WebSocket 管道**：数据帧以原始二进制缓冲区流动，不会出现分块 UTF-8 校验错误。
4. **GPU WebGL 加速**：60 FPS 渲染可防止高频遥测更新时出现撕裂和重绘延迟。

### 在 WebKVM 标签页之间切换会终止我的终端会话吗？
不会！`HostConsole` 会保持挂载并在后台持续活动。你可以切换到*虚拟机*、*存储*或*设置*，再回到终端时，正在运行的命令、`btop` 或 `nano` 会话都会保持原样。

---

## 7. 安全与访问控制

### WebKVM 如何保护 WebSocket 连接？
WebKVM 使用存储在内存中、生存时间（TTL）为 30 秒的**一次性临时凭证**。打开终端或控制台时，前端会通过已认证的 REST 请求获取一个临时凭证，并在 WebSocket 升级请求中传递它。连接建立后该临时凭证会立即作废，确保 URL 或代理日志中不存在长期令牌。

### SSRF 安全拨号器是如何工作的？
从外部 URL 下载镜像或 ISO 时，WebKVM 会预先解析 DNS 查询，并拒绝任何落在回环（`127.0.0.0/8`）、RFC 1918 私有网段（`10.0.0.0/8`、`172.16.0.0/12`、`192.168.0.0/16`）、链路本地、运营商级 NAT 或 IPv6 对应地址范围内的目标，并对每个 HTTP 重定向跳转重新校验。

### 防火墙的"安全应用"功能是什么？
修改宿主机防火墙规则时，WebKVM 会先将规则暂存，并给出 30 秒的确认窗口（可通过 `firewall.confirm_window_secs` 配置为 10 到 300 秒）。如果管理员因错误规则失去连接且始终未确认，防火墙会自动回滚到之前稳定状态，防止意外锁定。

---

## 8. 故障排查与诊断

### 我忘记了初始管理员密码，如何重置？
如果你对宿主机有 root 访问权限：
```bash
# 生成新的管理员密码
webkvm-cli users update admin --password "NewSecurePassword123!"
```
或者删除 `/opt/webkvm/users.json` 并重启服务，以重新生成初始凭据。

### 虚拟机启动失败时应该检查什么？
1. 检查 KVM 硬件加速：`ls -l /dev/kvm`（权限应为 `crw-rw---- root kvm`）。
2. 确认可用内存：`free -h`。
3. 查看后端日志：`journalctl -u webkvm -n 50 --no-pager`。
