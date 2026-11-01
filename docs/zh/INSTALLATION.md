# WebKVM — 安装指南与技术文档

本文档同时涵盖 WebKVM 管理器的**安装**，以及应用及其代码的**技术文档**。日常使用请参阅
[USAGE.md](USAGE.md)。

[**English**](../INSTALLATION.md) • [**Español**](../INSTALLATION.es.md) • [**简体中文**](INSTALLATION.md)

---

## 第 I 部分 — 安装

### 1. 环境要求

| 要求 | 详情 |
|-----------|---------|
| 操作系统 | Debian/Ubuntu（apt）、Fedora/RHEL（dnf）或 Arch（pacman） |
| 架构 | amd64 / x86_64 |
| KVM | 存在 `/dev/kvm`（在 BIOS/UEFI 中启用虚拟化，或在虚拟机监控程序上启用嵌套虚拟化） |
| 内存 | 至少 2 GB |
| 磁盘 | 至少 5 GB 可用空间 |
| 网络 | 可访问外网（用于下载软件包和工具） |
| Incus *（可选，容器）* | 宿主机上已安装并运行 **Incus** 守护进程，用于管理 **LXC 容器**。纯 KVM 场景可跳过。参见下文[容器（LXC）](#7-容器lxc-kvmlxc-混合)。 |

### 2. 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/Slaker19/webkvm/main/scripts/install-webkvm.sh | sudo bash
# 会询问：仅 IP（HTTP）还是启用 SSL —— 自签名证书对 IP 和域名均有效
# + 可选域名（例如 webkvm.example.com）+ 网络模式（nat / bridge / both）
```

脚本会把仓库（以压缩包形式下载，无需 `git`）下载到 `/var/tmp` 下的工作目录，并运行独立安装器。
完整输出保存在 **`/var/log/webkvm-install.log`**；如果安装失败，工作目录会被保留，便于你随缺陷报告一并附上。

或从克隆的仓库安装：

```bash
git clone https://github.com/Slaker19/webkvm
cd webkvm
sudo ./install.sh              # 委托给 packaging/standalone/install.sh
sudo ./packaging/standalone/install.sh --dry-run   # 不做任何改动地验证
```

安装器会做以下事情：

1. 预检（KVM、内存 ≥ 2 GB、磁盘 ≥ 5 GB、amd64），出错时给出可操作的错误信息。
2. 通过 apt/dnf/pacman 安装 libvirt、QEMU、OVMF、swtpm、xorriso、dnsmasq 以及磁盘管理
   工具（gdisk/parted、e2fsprogs、xfsprogs、btrfs-progs、f2fs-tools —— 供
   存储 > 宿主磁盘 用于格式化/挂载物理磁盘）。
   在 Arch 上还会先刷新 `archlinux-keyring`（旧 ISO 自带过期的密钥）。
3. 部署**预编译二进制**（前端已内嵌）。服务器**永不编译**：无需 Go/Node 工具链。
4. 安装 `webkvm.service`，数据位于 `/opt/webkvm`。
5. 交互式询问 HTTPS 与网络配置，或在管道输入时使用默认值
   （`curl … | sudo bash` → 非交互：启用 HTTPS，网络模式 `both`
   —— 共享 L2 网桥**和**隔离 NAT 网络 —— 并安装 Incus）。
6. 对服务做健康检查（`/api/health`），并打印摘要：URL、管理员密码、网络。

### 3. 从预编译二进制安装

二进制已内嵌前端：它是服务器唯一需要的产物（仅依赖系统级 libvirt/QEMU）。在开发机或 CI 上构建一次：

```bash
make binary   # 生成 backend/webkvm
make dist     # 生成 dist/webkvm-<version>.tar.gz（二进制 + 安装器 + 脚本 + SHA256SUMS）
```

在目标服务器上：

```bash
sudo WEBKVM_BINARY=backend/webkvm ./install.sh
# 从压缩包安装：
tar xzf webkvm-<version>.tar.gz
sudo WEBKVM_BINARY=backend/webkvm bash packaging/standalone/install.sh
# 通过 HTTPS 提供并强制校验和：
sudo WEBKVM_BINARY_URL=https://your-server/webkvm \
     WEBKVM_BINARY_SHA256=<sha256> \
     ./install.sh
```

**同一个通用 amd64 二进制适用于所有支持的发行版**：它需要 GLIBC ≥ 2.34 和 `libvirt.so.0`，
这两者在 Debian 13+、Ubuntu 24+、Fedora 43/44 和 Arch 上都是现成的。安装器会补齐各发行版的 libvirt 软件包。

> 支持原地升级：再次运行安装器会保留 `/opt/webkvm` 下的全部数据，并在任何步骤失败时自动回滚。

### 4. 安装器参数与环境变量

每个设置都有命令行参数和等价的环境变量 —— 两者可互换使用，且显式参数优先于已导出的变量。
运行 `install.sh --help` 可查看内置清单。

| 参数 | 等价变量 |
|------|---------------------|
| `--dry-run` | —（只报告将发生的更改，不做任何改动） |
| `--yes`、`-y`、`--unattended` | `WEBKVM_NONINTERACTIVE=1` |
| `--port=8080` | `WEBKVM_PORT` |
| `--bind=0.0.0.0` | `WEBKVM_BIND_ADDR` |
| `--https=yes\|no` | `WEBKVM_HTTPS` |
| `--domain=webkvm.example.com` | `WEBKVM_TLS_DOMAIN` |
| `--network=nat\|bridge\|both\|none` | `NETWORK_MODE` |
| `--incus=yes\|no` | `WEBKVM_INSTALL_INCUS` |
| `--prefix=/usr/local` | `WEBKVM_PREFIX` |
| `--data-dir=/opt/webkvm` | `WEBKVM_DATA_DIR` |
| `--admin-password=…` | `WEBKVM_ADMIN_PASSWORD` |
| `--bridge-dhcp` | `BRIDGE_DHCP=true` |
| `--bridge-static=10.0.0.5/24` | `BRIDGE_STATIC_IP`（隐含 `BRIDGE_DHCP=false`） |
| `--gateway=10.0.0.1` | `BRIDGE_STATIC_GW` |
| `--dns=1.1.1.1` | `BRIDGE_STATIC_DNS` |

| 变量 | 作用 |
|----------|--------------|
| `WEBKVM_DATA_DIR` | 数据目录（默认 `/opt/webkvm`）。 |
| `WEBKVM_PREFIX` | 安装前缀（默认 `/usr/local`）。 |
| `WEBKVM_BIND_ADDR` | 监听地址（默认 `127.0.0.1`，仅本机；设为 `0.0.0.0` 或局域网 IP 才能对外访问，并应同时启用 HTTPS）。 |
| `WEBKVM_PORT` | 端口（默认 `8080`）。 |
| `WEBKVM_BINARY` | 本地二进制路径。 |
| `WEBKVM_BINARY_URL` | 二进制的 HTTPS URL（强制校验和）。 |
| `WEBKVM_BINARY_SHA256` | 该二进制的 SHA-256 校验和。 |
| `WEBKVM_HTTPS=yes\|no` | `yes` = 使用自签名证书的原生 HTTPS（SAN 覆盖 IP + 主机名 [+ 域名]）；`no` = 纯 HTTP。交互式提示默认 `yes`。 |
| `WEBKVM_TLS_DOMAIN` | 证书域名（例如 `webkvm.example.com`）。留空 = 仅使用 IP/主机名。设置后，SAN 会包含该域名，并尝试使用 Let's Encrypt，失败时自动回退到自签名证书。 |
| `NETWORK_MODE` | `nat`、`bridge`、`both` 或 `none`。交互式默认 **`bridge`**；无人值守安装（`--yes` / `WEBKVM_NONINTERACTIVE=1`）默认 **`both`**，因为无论缺少哪一半，之后都无法在不重新运行安装器的情况下补上。 |
| `BRIDGE_DHCP`、`BRIDGE_STATIC_IP`、`BRIDGE_STATIC_GW`、`BRIDGE_STATIC_DNS` | br0 网桥设置。默认是**静态**：安装器会固定宿主机当前持有的地址。设置 `BRIDGE_DHCP=true`（或传入 `--bridge-dhcp`）可让网桥改用 DHCP。 |
| `WEBKVM_NONINTERACTIVE=1` | 不询问任何问题；套用默认值。 |
| `WEBKVM_INSTALL_INCUS=0\|1` | **默认 `1`。** 安装并启用供容器使用的 **Incus** 守护进程（apt/pacman/dnf 上的原生 `incus` 包，回退到 `lxd`；绝不使用 snap；不可用时仅给出非致命警告），并在服务单元中设置 `WEBKVM_INCUS_ENABLED=1`。设为 `0`（或传 `--incus=no`）即为纯 KVM 宿主机。 |
| `WEBKVM_ADMIN_PASSWORD` | 指定初始管理员密码（否则生成随机密码并保存）。 |

### 5. HTTPS（无需反向代理）

安装器会直接询问：

```
您希望如何访问 WebKVM？
  1) 仅 IP（纯 HTTP）
  2) 使用 SSL —— 自签名证书（对 IP 和域名均有效，推荐）
证书域名（可选 —— 例如 webkvm.example.com；留空 = 仅使用 IP/主机名；
SAN 包含局域网 IP + 主机名.local + localhost）
```

- **仅 IP（`WEBKVM_HTTPS=no`）** —— 在 8080 端口上使用纯 HTTP。
- **使用 SSL（默认）** —— 后端**原生提供 HTTPS**，使用有效期为 10 年的 RSA-2048
  自签名证书。
  SAN = `DNS:webkvm, DNS:localhost, DNS:<hostname>.local, IP:127.0.0.1, IP:<LAN>
  [+ DNS:<domain>]`。无需 nginx/apache/caddy 即可通过 IP 和域名访问。
- **公网域名 + Let's Encrypt** —— 当 `WEBKVM_TLS_DOMAIN` 解析到本服务器且 80/443
  端口可达时，autocert 会签发并续期真实证书（缓存位于 `DATA_DIR/tls`）。若验证失败，
  则回退到包含该域名的自签名证书 —— 服务永不中断。

浏览器会对自签名证书给出警告。你可以从
`https://IP:8080/api/system/cert` 下载自己的证书，并在系统中全局信任它。之后可在
**设置 → 服务器 → TLS 证书 / TLS 域名** 中修改，然后执行
`systemctl restart webkvm`。

**需要反向代理？** 仅当你已经为 WAF/限流/集中认证运行了反向代理时才需要。这种情况下请以
`WEBKVM_HTTPS=no` 安装，并让虚拟主机指向 `http://127.0.0.1:8080`。

### 6. 虚拟机网络

默认情况下 WebKVM 使用**操作系统层面真正的 Linux 网桥**（Proxmox 风格）：KVM 通过
`<interface type='bridge'><source bridge='vmbrX'/>` 接入，Incus 通过
`nictype=bridged parent=vmbrX` 接入。`bridge` 与 `both` 模式只用这一种模型，并会禁用
libvirt 的 `default`/`virbr0` NAT 网络；旧式仅 NAT 模式（`nat`）是例外：它只配置
libvirt 默认 NAT 网络，不创建物理网桥。

由 `NETWORK_MODE` 选择：

- **共享 L2 网桥（`bridge`，默认，推荐）** —— 虚拟机和容器通过物理 Linux 网桥
  （`vmbr0`/`br0`）接入真实局域网，由路由器通过 DHCP 分配 IP（也可用
  `BRIDGE_STATIC_IP/CIDR` + 网关 + DNS 配置静态地址）。若已存在宿主机网桥则复用；
  否则新建一个（macvlan 从设备），不改动宿主机自身地址。
- **仅 NAT（`nat`，需显式启用，旧式）** —— 只配置 libvirt 默认 NAT 网络
  （`192.168.122.0/24`），不改动宿主机自身网卡，**不会**创建 `vmbr1`。
  推荐使用 `bridge`（接入局域网）或 `both`（局域网 + 隔离租户网络）。
- **两者（`both`，需显式启用）** —— 物理局域网网桥（`vmbr0`）**加上**隔离租户网桥
  `vmbr1`（锚定内核 `dummy0`，静态 `100.0.0.1/24`，带 `dnsmasq` DHCP 和
  `MASQUERADE`）；按虚拟机选择。

在界面（**网络**）中，你可以创建额外的宿主机网桥（可选 IP + DHCP），以及为每台虚拟机
设置 nftables 防火墙规则。安装器通过 `scripts/setup-network.sh` 完成相关配置。

### 7. 容器（LXC）— KVM/LXC 混合

WebKVM 通过同一宿主机上的 **Incus**（LXD 的社区分支）**原生管理 LXC 容器**，并在统一
视图中呈现（每个实例带有 `KVM`/`Incus` 徽标）。Incus 的 Go 客户端保留 LXD REST API，
因此**现有的 LXD 守护进程可原样使用**。独立安装器**默认**会配置此模块；纯 KVM 宿主机可传
`--incus=no`（或 `WEBKVM_INSTALL_INCUS=0`）。在手动安装中，该模块在设置
`WEBKVM_INCUS_ENABLED=1` 之前保持禁用。

**宿主机依赖。** 必须安装并运行 Incus 守护进程（使用原生软件包，不要用 snap）：

```bash
# Debian / Ubuntu / Arch / Fedora / RedHat 系
sudo apt install incus    # 或：sudo pacman -S incus / sudo dnf install incus
sudo systemctl enable --now incus
sudo incus admin init     # 旧版 LXD：sudo lxd init
```

**安装器自动化。** 除非另行指定，独立安装器以 `WEBKVM_INSTALL_INCUS=1` 运行：它会安装并
启用 Incus 并将该模块接入服务单元。它在**所有包管理器**（apt/pacman/dnf）上使用
**原生 `incus` 包**，当 `incus` 不可用时回退到旧的原生 `lxd` 包；**绝不**使用 snap。
若没有可用软件包，它会打印警告，提示你按发行版 wiki 手动安装 Incus 或 LXD，并
**继续以纯 KVM 模式运行（绝不失败）**：

```bash
# 纯 KVM 宿主机 —— 完全跳过 Incus
sudo bash install-webkvm.sh --incus=no
```

**启用（环境变量）。** 在 systemd 单元（`Environment=WEBKVM_INCUS_ENABLED=1`）或
`.env` 中设置 `WEBKVM_INCUS_ENABLED=1`。`INCUS_SOCKET` 可覆盖自动探测的套接字
（优先 Incus：`/var/lib/incus/unix.socket` 或 `/run/incus/*`；其次是旧版 LXD snap
`/var/snap/lxd/common/lxd/unix.socket`、apt `/var/lib/lxd/unix.socket`）。

**权限。** 进程用户必须能读取守护进程套接字。原生服务以 `root` 运行（无需额外步骤）；
以非 root/Docker 方式运行时，请把用户加入 **`incus-admin`** 组（Incus）或 **`lxd`** 组
（旧版 LXD）：`sudo usermod -aG incus-admin <user> && sudo systemctl restart webkvm`。

**验证。** 启动时后端日志中会出现 `incus_connected`；容器会出现在虚拟机列表中，并可用
与虚拟机相同的表单创建（友好的镜像选择器、cloud-init 凭据、根磁盘扩容、网络接口、实时指标）。

### 8. 非交互式安装（服务器 / 流水线）

每个选项都可通过环境变量覆盖；没有 TTY 时使用默认值：

```bash
sudo WEBKVM_PORT=8080 \
     WEBKVM_HTTPS=yes \
     WEBKVM_TLS_DOMAIN=webkvm.example.com \
     NETWORK_MODE=nat \
     WEBKVM_NONINTERACTIVE=1 \
     ./packaging/standalone/install.sh
```

完整安装输出保存在 **`/var/log/webkvm-install.log`**；失败时 `/var/tmp` 下的工作目录
会被保留并打印其路径。

### 9. 升级

用新的代码/二进制再次运行安装器。它会：

1. 备份当前的二进制和单元文件（`*.previous`）。
2. 安装新的二进制和单元文件。
3. 重启服务并检查 `/api/health`。
4. **任何步骤失败都会自动回滚。**

`/opt/webkvm` 下的所有内容（配置、磁盘、ISO、用户）都会保留。

### 10. 卸载

```bash
cd packaging/standalone
sudo ./uninstall.sh                                  # 保留数据
sudo PURGE_DATA=1 PURGE_NETWORKS=1 ./uninstall.sh     # 同时删除数据 + 网络/网桥
```

卸载只会移除 WebKVM 自身拥有的内容：二进制、systemd 服务，以及（需显式启用）它自己的数据
（`PURGE_DATA`）和它创建的 libvirt 网络/网桥（`PURGE_NETWORKS`）。它**有意不**移除运行时
软件包（libvirt、qemu、swtpm、ovmf、dnsmasq 等）：这些是共享的系统/虚拟化工具，宿主机上的
其他软件也可能依赖它们，因此卸载永远不会触碰它们。

### 11. 故障排查

| 现象 | 可能原因 / 修复 |
|---------|---------------------|
| 缺少 `/dev/kvm` | 在 BIOS/UEFI 中启用虚拟化，或在虚拟机监控程序上启用嵌套虚拟化 |
| 安装器回滚 | 健康检查失败；检查 `journalctl -u webkvm -n 100` |
| 浏览器证书警告 | 自签名证书下的正常现象；从 `/api/system/cert` 信任该证书 |
| 服务未监听 | `systemctl status webkvm` 并查看日志 |
| 域名未获得真实证书 | 服务器不可从公网访问；回退到自签名证书属正常 |
| 端口已被占用 | 会在安装前快速失败；释放端口或设置 `WEBKVM_PORT` |

安装日志位于 `/var/log/webkvm-install.log`；失败的运行会保留 `/var/tmp` 下的工作目录
（会打印路径）。

---

## 第 II 部分 — 技术文档

### 12. 架构

WebKVM 是一个**由两部分组成的单体应用**：

- **Go 后端**（`backend/`）：REST API + noVNC 控制台 + 内嵌 Svelte SPA，全部打包进单个
  `webkvm` 二进制。
- **Svelte 5 前端**（`frontend/`）：编译为静态资源的 SPA，通过 `go:embed` 内嵌。

后端与 **libvirt**（`qemu:///system`）通信，管理域、网络和存储。所有应用状态（用户、
令牌、设置、备份、分组、节点）都以 **JSON 文件形式保存在 `DATA_DIR` 内** —— 无外部数据库。

```
Browser ──HTTP/SSE + Bearer JWT──► Go backend (:8080)
                                    │
                                    ├─ REST API (chi v5)
                                    ├─ JWT auth + RBAC (admin/operator/viewer)
                                    ├─ SSE event hub (VM state, metrics)
                                    ├─ noVNC proxy (WebSocket → VNC), serial WebSocket
                                    └─ Backup runner (cron) + OVA import/export
                                    │  libvirt C API (libvirt.org/go/libvirt)
                                    ▼
                        libvirtd / qemu:///system
                        VMs · Networks · Storage pools · Snapshots
                                    ▼
                            QEMU/KVM hypervisor
```

三个平面：

1. **控制平面（Go 后端）** —— 编排 libvirt 并暴露 API。
2. **数据平面（libvirt/QEMU）** —— 真正的虚拟机监控程序；虚拟机运行于此。
3. **状态平面（`DATA_DIR`）** —— 应用配置与元数据。

### 13. 仓库布局

| 路径 | 内容 |
|------|----------|
| `backend/` | Go 后端（`cmd/server`、`cmd/cli`、`cmd/migrate-disk-names`、`internal/*`）。 |
| `frontend/` | Svelte 5 SPA（Vite、Tailwind v4）。 |
| `docs/` | 本指南和使用手册。 |
| `packaging/standalone/` | 裸机安装器（自动回滚）、卸载器、静态测试。 |
| `scripts/` | 一行命令包装脚本、网络设置、systemd 单元、logrotate、备份辅助脚本。 |
| `Makefile` | build / test / dist / clean。 |
| `install.sh` | 统一入口（委托给独立安装器）。 |

### 14. 后端软件包（`backend/internal/`）

| 软件包 | 职责 |
|---------|----------------|
| `api/` | HTTP 路由（chi v5）、处理器、中间件、内嵌 noVNC 控制台。 |
| `libvirt/` | libvirt 集成：域、存储、网络、OVA、快照、指标、事件、宿主机网桥。 |
| `auth/` | JWT、中间件、RBAC、令牌黑名单、登录限流、控制台临时凭证。 |
| `user/` | `users.json` 中的用户存储（bcrypt）；初始管理员种子。 |
| `tokens/` | `api-tokens.json` 中的持久 API 令牌（`wvmb_…`，sha256 哈希）。 |
| `configstore/` | `config.json` 中的类型化热重载设置。 |
| `config/` | 启动配置（环境变量 + `.env`）、JWT 密钥解析。 |
| `backupstore/` | 备份 v2：目标、计划、作业、tar 生成器、SFTP 支持、恢复。 |
| `audit/` | JSONL 审计日志（`audit.log`，10 MB 轮转）。 |
| `events/` | SSE 分发中心（虚拟机状态、指标）。 |
| `nodes/` | libvirt 节点注册表（`nodes.json`）。 |
| `models/` | 共享类型（虚拟机、存储池、网络、用户、RBAC、配额、指标……）。 |
| `appliances/` | 社区应用目录、默认值和配置脚本。 |
| `cloudinit/` | NoCloud seed ISO 生成（经过校验、YAML 转义、xorriso）。 |
| `notify/` | Webhook/SMTP 通知。 |
| `vmsched/` | 基于 cron 的虚拟机电源调度。 |
| `firewall/` | 每虚拟机的 nftables 规则，原子化应用。 |
| `frontend/` | 内嵌的已编译 Svelte 资源（`go:embed`）。 |
| `logging/` | 结构化 `log/slog`（JSON），可选文件分流。 |

### 15. 环境变量

| 变量 | 默认值 | 说明 |
|----------|---------|-------|
| `PORT` | `8080` | 后端 HTTP/HTTPS 端口。 |
| `BIND_ADDR` | `127.0.0.1` | 后端/config 默认值。独立安装器未传 `--bind` 时也写入 `127.0.0.1`；`scripts/webkvm.service`（Makefile 安装）与 Docker 镜像使用 `0.0.0.0`。以 `server.bind_addr` 持久化到 `config.json`。 |
| `LIBVIRT_URI` | `qemu:///system` | libvirt URI。 |
| `DATA_DIR` | `/opt/webkvm` | 持久数据目录。 |
| `JWT_SECRET` | 自动生成 | 保存在 `{DATA_DIR}/jwt.key`（0600）；弱密钥会被拒绝。 |
| `WEBKVM_LOG_FILE` | `""` | 日志分流文件（由 `GET /api/system/logs` 读取）。 |
| `VNC_PROXY_HOST` | `127.0.0.1` | noVNC→VNC TCP 连接的目标主机。 |
| `PUBLIC_HOST` | `""` | 写入 `.rdp`/`.vv` 文件的 IP（为空时自动探测）。 |
| `CORS_ORIGIN` | *（空）* | 允许的 CORS 来源（逗号分隔）。空 = 仅同源。 |
| `TLS_CERT` / `TLS_KEY` / `TLS_DOMAIN` | — | TLS 设置（以 server.tls_* 持久化）。 |
| `WEBKVM_ADMIN_PASSWORD` | — | 初始管理员密码（否则随机生成）。 |
| `WEBKVM_INCUS_ENABLED` | `0` | 启用 Incus/LXD 容器模块（需要宿主机上有对应守护进程）。 |
| `INCUS_SOCKET` | 自动 | 容器守护进程 unix 套接字覆盖（优先 Incus：`/var/lib/incus/unix.socket`、`/run/incus/*`；其次 LXD snap/apt 路径）。 |

工作目录中的 `.env` 会作为回退加载（godotenv）；真实环境变量始终优先。

### 16. 磁盘布局（`DATA_DIR`）

| 路径 | 内容 |
|------|----------|
| `pools/webkvm-disks` | 虚拟机磁盘池（libvirt 存储池 `webkvm-disks`）。 |
| `pools/webkvm-isos` | ISO 库存储池（使用 `ISOS` 的旧安装会在首次启动时自动重命名）。 |
| `pool-purposes.json` | 每个存储池的用途（`disk`/`iso`）。 |
| `users.json` | 带 bcrypt 哈希的用户（0600）。 |
| `jwt.key` | JWT 密钥（0600）。 |
| `api-tokens.json` | API 令牌的 sha256 哈希。 |
| `config.json` | 持久化设置（类型化 schema）。 |
| `backup/{targets,schedules,jobs}.json` | 备份 v2 注册表。 |
| `nodes.json` | libvirt 节点。 |
| `groups.json` | 虚拟机分组/标签。 |
| `audit.log` | JSONL 审计日志。 |
| `cifs-secrets.json` | netfs 存储池的 CIFS secret UUID（0600）。 |
| `covers/` | 虚拟机封面图片。 |
| `logs/backend.log` | 结构化日志（启用 `WEBKVM_LOG_FILE` 时）。 |
| `admin-password.initial` | 初始管理员密码（仅首次启动）。 |
| `certs/` | TLS 证书（自签名）。 |
| `appliances.json` | 应用目录（首次启动时从默认值播种）。 |
| `tls/` | autocert 缓存（Let's Encrypt）。 |

### 17. 身份验证与安全

- **JWT HS256**（默认 TTL 24 小时，可热重载）。使用占位/弱密钥时服务器**拒绝启动**；
  会生成随机密钥并持久化到 `jwt.key`。
- **登录限流**：15 分钟内 5 次失败 → 锁定 15 分钟（429 + `Retry-After`）；回环地址始终
  可信；`WEBKVM_TRUSTED_RATELIMIT_CIDRS` 可增加受信任 CIDR；`WEBKVM_TRUST_PROXY`
  控制 `X-Forwarded-For`。
- **RBAC**：固定层级 `admin > operator > viewer`。
- **API 令牌**：`wvmb_` 前缀 + 32 个随机字节；仅存储 sha256 哈希；支持过期与吊销。
- **`must_change_password`**：在初始密码轮换之前，阻止访问除认证/密码/健康检查之外的所有
  端点。
- **SSRF 阻止名单**：用于 ISO 下载（回环、链路本地、私有网段、CGNAT）。
- **路径穿越**：ISO 上传/重命名时净化；备份路径经过校验
  （`backupstore/path_safety.go`，可识别符号链接的拒绝列表）。
- **防火墙**：专用 nftables 表，原子化校验（`nft -c`），规则以参数分离方式执行（不经 shell）。
- **systemd 加固**：`NoNewPrivileges`、`ProtectSystem=full`、`ProtectHome=read-only`、
  `PrivateTmp`、受限的 `CapabilityBoundingSet`、限定范围的 `ReadWritePaths`。
- **代码扫描**：CI 中强制执行 golangci-lint + eslint + prettier。

### 18. REST API（摘要）

基础 URL：`http(s)://<host>:8080/api`。认证：`Authorization: Bearer <JWT or
API token>`。

| 领域 | 主要端点 |
|------|----------------|
| 认证 | `POST /auth/login`、`POST /auth/logout`、`GET /auth/me`、`PUT /users/me/password` |
| 用户/组 | `GET/POST/PUT/DELETE /users/{username}`、`GET/POST /groups`、`GET /accounts` |
| 虚拟机 | `GET/POST /vms`、`GET/PUT/DELETE /vms/{id}`、电源操作、克隆/导入/导入-OVA/导出、`POST/DELETE /vms/{id}/usb`（USB 直通，仅管理员） |
| 控制台 | 串口 WebSocket（+ 一次性临时凭证）、noVNC（`POST /vms/{id}/vnc-ticket` + 可复用的、限定虚拟机的临时凭证）、`.rdp`/`.vv` 下载、剪贴板 |
| 存储 | 存储池/卷/ISO 的 CRUD、ISO 上传/下载、`POST /storage/upload-disk`（qcow2/img/raw/qed） |
| 网络 | 网桥/网络 CRUD、VLAN 感知开关 |
| 快照/备份 | 快照 CRUD + 回滚；备份目标/运行/作业/计划 |
| 应用 | 目录 CRUD、部署（后台任务）、配置脚本 |
| 系统 | `GET /health`、`/status`、`/metrics`、`/logs`、`GET /events`（SSE）、`/system/cert`、`/system/version` |

前端使用单一 API 客户端（`frontend/src/lib/stores/auth.svelte.js`）；
路由注册在 `backend/internal/api/router.go`。

### 19. 需要 CIFS 认证的 netfs 存储池

格式为 `cifs` 的 `netfs` 存储池通过 **libvirt secret** 支持认证：用户名和密码一起提交
（只提供其一则返回 400），密码在 `{DATA_DIR}/cifs-secrets.json`（0600）中仅以
libvirt secret UUID 保存 —— API 永不返回密码。通过
`PUT /api/storage/pools/{name}` 轮换凭据（存储池必须处于停止状态）。重装 libvirtd 后
（secret 被清空），通过发送 `cifs-needs-reauth: true` 加当前凭据来恢复该存储池。

### 20. 从源码构建

```bash
make build          # npm ci + 前端构建 → go:embed → go build -o backend/webkvm
make test           # go test ./... && go vet ./... ; 前端 eslint + prettier
make dist           # dist/webkvm-<version>.tar.gz（二进制 + 安装器 + SHA256SUMS）
```

版本通过 `git describe --tags --always` 或 `WEBKVM_VERSION`（ldflags）注入，回退为 `dev`。

### 21. 不可破坏的不变量

> 修改这些内容会破坏与现有安装和虚拟机的兼容性。

| 不变量 | 值 |
|-----------|-------|
| 域元数据 XML 命名空间 | `https://webvm.local/ns` |
| 磁盘存储池名称 | `webkvm-disks` |
| ISO 存储池名称 | `webkvm-isos` |
| Go 模块 | `webkvm` |
| systemd 服务 | `webkvm.service` |
| 备份文件名模式 | `webkvm-<host>-<ts>` |

### 22. 安全与许可证

- 漏洞报告：[SECURITY.md](SECURITY.md)。
- 许可证 **AGPLv3**：[LICENSE](../../LICENSE)。
