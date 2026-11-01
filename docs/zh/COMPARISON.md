# WebKVM 与其他虚拟化平台的对比

关于 **WebKVM**、**Proxmox VE**、**Cockpit (Machines)**、**virt-manager** 与 **Portainer** 之间全面、客观的技术对比。

[**English**](../COMPARISON.md) • [**Español**](../COMPARISON.es.md) • [**简体中文**](COMPARISON.md)

---

## 功能对比矩阵

| 架构类别 | WebKVM | Proxmox VE | Cockpit (Machines) | virt-manager | Portainer |
|---|---|---|---|---|---|
| **架构与二进制** | 单一 Go 二进制（约 14 MB）+ 内嵌 Svelte 5 | 多守护进程 Perl/C 栈（PVE proxy、各守护进程） | Python / systemd D-Bus 模块 | 桌面 GTK 客户端 | Go 后端 + Docker 守护进程 |
| **空闲内存占用** | **约 15 MB 内存** | 1.2 GB – 2.5 GB 内存 | 约 80 MB 内存 | 不适用（桌面客户端） | 约 40 MB 内存 |
| **宿主机系统保留** | **100% 原样保留**（标准操作系统） | 需要定制 Debian ISO | 原样保留 | 原样保留 | 需安装 Docker |
| **KVM 虚拟机** | 是——完整支持 | 是——完整支持 | 是——基础支持 | 是——完整支持 | 否（仅容器） |
| **LXC / Incus 容器** | **是——原生 Incus/LXD 视图** | 部分——自研 PVE LXC 脚本 | 否 | 否 | 否（仅应用容器） |
| **Cloud-Init 与一键镜像** | **是——内置镜像中心，5 秒部署** | 部分——手动克隆模板 | 否——手动 | 否——手动 | 部分——应用模板 |
| **Web 终端质量** | **WebGL + Unicode 11 + TUI 按键** | 部分——基础 xterm.js | 部分——基础终端 | 否——仅桌面终端 | 部分——基础 exec shell |
| **实时传输速率与 ETA** | **是——实时 MB/s 与 ETA** | 部分——仅百分比 | 否 | 否 | 部分——基础层拉取 |
| **零令牌本地 CLI** | **是——自动认证 CLI** | 部分——`pvesh` / `qm` / `pct` | 否 | 部分——仅 `virsh` | 否 |
| **基于 Web 的多视图网格** | **是——交互式多控制台** | 否——一次 1 个控制台 | 否——一次 1 个控制台 | 部分——多个桌面窗口 | 否 |
| **防火墙安全应用回滚** | **是——30 秒自动回滚计时器** | 否——手动 PVE 防火墙 | 否——firewalld 模块 | 否 | 否 |
| **一次性 WebSocket 临时凭证** | **是——内存中 30 秒临时凭证** | 部分——会话临时凭证 / Cookie | 部分——Cookie 认证 | 否——本地 socket | 部分——请求头中的 JWT |

---

## 按平台深入分析

### 1. WebKVM vs. Proxmox VE

**何时选择 Proxmox VE：**
- 你正在构建企业数据中心集群，拥有 3 台以上专用 hypervisor，需要 Corosync 法定人数（quorum）、10GbE 上的虚拟机在线迁移，以及 Ceph 分布式存储池。
- 你希望把整台物理机专门用于虚拟化，不打算在宿主机操作系统上直接运行其他服务。

**何时选择 WebKVM：**
- 你想把现有 Linux 服务器（Ubuntu、Debian、Fedora、Arch、AlmaLinux）变成快速、私有的虚拟化平台，而无需擦盘或更换操作系统。
- 你在意极低的资源消耗（在迷你主机、家庭实验室或云 VPS 上为实际工作负载节省 1–2 GB 内存）。
- 你希望用一个统一、现代的界面同时管理完整 KVM 虚拟机和轻量 Incus 系统容器。
- 你偏好单一二进制的简洁性——零后台杂乱、即时更新。

---

### 2. WebKVM vs. Cockpit（Machines 模块）

**何时选择 Cockpit：**
- 你只需要基础的服务器监控（查看 systemd 日志、存储挂载和用户账户），只是偶尔运行一两台简单虚拟机。

**何时选择 WebKVM：**
- 你需要专用、专业的虚拟化工作流：
  - **Incus/LXC 集成**：Cockpit 仅通过 libvirt-dbus 支持 KVM，没有原生系统容器支持。
  - **镜像中心与 Cloud-Init**：Cockpit 需要手动下载 ISO 并逐步安装操作系统；WebKVM 可在 5 秒内部署预配置虚拟机。
  - **存储与网络**：WebKVM 管理专用存储池（带用途强制）、双网桥/NAT 路由，以及可安全回滚的高级宿主机防火墙规则。
  - **终端性能**：WebKVM 提供 GPU 加速的 WebGL 终端，支持 Unicode 11 和 TUI 功能键（`F1`–`F12`），确保 `btop`、`htop`、`mc` 等工具渲染不乱码。

---

### 3. WebKVM vs. virt-manager

**何时选择 virt-manager：**
- 你正坐在 Linux 桌面前面，有活动的 X11/Wayland 图形会话，偏好原生 GTK 桌面窗口。

**何时选择 WebKVM：**
- 你想从任何设备（笔记本、平板、手机、Chromebook 或远程工作站）100% 网页访问，无需配置 SSH X11 转发或 VNC 客户端软件。
- 你管理远程服务器、云实例或无头家庭实验室。
- 你需要带基于角色权限（Admin、Operator、Viewer）和全面审计日志的团队访问。

---

### 4. WebKVM vs. Portainer / Docker

**何时选择 Portainer：**
- 你只运行 Docker 微服务（打包为短生命周期状态的应用容器，例如 Nextcloud、Plex、Traefik）。

**何时选择 WebKVM：**
- 你需要**真正的虚拟机**（运行 Windows、FreeBSD、自定义内核或嵌套 hypervisor）或 **Incus 系统容器**（带 systemd init、独立 IP 地址、包管理器和持久磁盘卷的完整 Linux 操作系统）。

---

## 总结

WebKVM 在现代基础设施中占据**理想的最佳位置**：
1. 它避免了企业 hypervisor 发行版沉重、专有的锁定。
2. 它远远超越通用服务器仪表盘的能力与视觉响应速度。
3. 它为管理员和家庭实验室爱好者提供美观、云原生的体验，同时保留对底层 Linux 机器的完全控制。
