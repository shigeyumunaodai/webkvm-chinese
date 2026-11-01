# WebKVM CLI（`webkvm-cli`）— 参考手册

一份关于 `webkvm-cli` 命令行工具的完整指南，适用于脚本编写、自动化和 SSH 管理。

[**English**](../CLI.md) • [**Español**](../CLI.es.md) • [**简体中文**](CLI.md)

---

## 概述

`webkvm-cli` 是一个独立的 CLI 客户端，直接与 WebKVM REST API 通信。

### 核心亮点
- **零令牌本地执行**：在宿主机上以 root 身份本地执行时，它会读取 `/opt/webkvm/jwt.key` 并即时签发临时管理员令牌。无需手动登录或指定令牌参数。
- **远程认证**：支持 `webkvm-cli login`，将会话令牌安全缓存到 `~/.config/webkvm/token`。
- **脚本友好**：全局 `--json` 参数输出格式化 JSON，可与 `jq`、Python 或 bash 脚本无缝集成。
- **整洁的列输出**：表格化文本输出按标准终端宽度格式化。

---

## 全局选项

```text
webkvm-cli [OPTIONS] <COMMAND> [ARGS...]

Options:
  --server URL    WebKVM server URL (default: https://127.0.0.1:8080 or $WEBKVM_SERVER)
  --token TOKEN   API token or JWT (or $WEBKVM_TOKEN). Auto-detected on localhost.
  --insecure      Skip TLS verification for self-signed certificates (default: true)
  --secure        Enforce strict TLS certificate verification
  --json          Output raw JSON for scripting
  -h, --help      Display help information
```

---

## 认证

### 本地执行（在宿主机上）
如果直接在安装了 WebKVM 的宿主机服务器上运行，你可以执行任何命令而无需提供凭据：

```bash
sudo webkvm-cli vms list
sudo webkvm-cli storage pools
```

### 远程执行
要从工作站管理远程 WebKVM 实例：

```bash
# 1. 登录一次（凭据会交互式提示输入）
webkvm-cli --server https://192.168.1.10:8080 login

# 2. 后续命令使用 ~/.config/webkvm/token 中缓存的令牌
webkvm-cli --server https://192.168.1.10:8080 vms list

# 3. 退出登录并清除缓存的会话
webkvm-cli logout
```

---

## 服务器健康检查与控制

| 命令 | 作用 |
|---------|--------------|
| `webkvm-cli status` | 健康检查（`GET /api/health`）—— 打印 `status`、`data_dir` 以及 libvirt 是否可达。 |
| `webkvm-cli info` | 宿主机摘要（`GET /api/host`）：CPU、内存、虚拟机监控程序及能力。 |
| `webkvm-cli restart` | 请求后端自行重启（`POST /api/system/restart`）。仅管理员。 |

---

## 备份（`backup`）

| 命令 | 作用 |
|---------|--------------|
| `webkvm-cli backup targets` | 列出已配置的备份目标。 |
| `webkvm-cli backup run <target>` | 立即触发一次备份。 |
| `webkvm-cli backup prune <target>` | 应用保留策略，按需清理过期的备份运行。 |
| `webkvm-cli backup jobs` | 列出备份作业及其状态、开始时间和大小。 |
| `webkvm-cli backup schedules` | 列出计划备份。 |

---

## 虚拟机与容器（`vms`）

### 列出实例
```bash
# 格式化表格
webkvm-cli vms list

# JSON 输出
webkvm-cli --json vms list | jq .
```

### 创建实例
创建完整的 KVM 虚拟机或轻量级 Incus 系统容器：

```bash
# 创建一台使用 Cloud-Init 的 Debian 12 KVM 虚拟机
webkvm-cli vms create \
  --name web-server \
  --ram 2048 \
  --vcpus 2 \
  --disk 20 \
  --image debian-12 \
  --user admin \
  --password "SecretPassword123!" \
  --ssh-key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..."

# 创建一个轻量级 Alpine Linux Incus 容器
webkvm-cli vms create \
  --name alpine-ct \
  --type container \
  --ram 512 \
  --vcpus 1 \
  --disk 10 \
  --image images:alpine/3.21

# 使用 ISO 创建自定义虚拟机
webkvm-cli vms create \
  --name custom-bsd \
  --ram 4096 \
  --vcpus 4 \
  --disk 50 \
  --iso FreeBSD-14.0-RELEASE-amd64-disc1.iso \
  --pool webkvm-disks
```

### 生命周期操作
```bash
webkvm-cli vms start <id>
webkvm-cli vms stop <id>        # 优雅的 ACPI 关机
webkvm-cli vms forceoff <id>    # 立即断电（destroy）
webkvm-cli vms reboot <id>
webkvm-cli vms suspend <id>
webkvm-cli vms resume <id>
webkvm-cli vms delete <id>
webkvm-cli vms clone <id>
webkvm-cli vms autostart <id> <on|off>
```

### 快照
```bash
# 列出快照
webkvm-cli vms snapshots <id>

# 创建快照
webkvm-cli vms snapshot <id> create "pre-upgrade-v1"

# 回滚到快照
webkvm-cli vms snapshot <id> revert <snapshot-id>

# 删除快照
webkvm-cli vms snapshot <id> delete <snapshot-id>
```

---

## 镜像中心（`images`）

管理官方云基础磁盘和容器镜像：

```bash
# 列出所有已缓存和可用的镜像
webkvm-cli images list

# 下载官方云基础镜像
webkvm-cli images pull-cloud ubuntu-24.04
webkvm-cli images pull-cloud alpine-3.24
webkvm-cli images pull-cloud debian-12

# 下载 Incus 容器镜像
webkvm-cli images pull-container images:alpine/3.21
webkvm-cli images pull-container images:centos/10-stream

# 删除已缓存的镜像
webkvm-cli images delete-cloud alpine-3.24
webkvm-cli images delete-container <fingerprint>
```

---

## 存储管理（`storage`）

```bash
# 列出存储池（KVM 和 Incus）
webkvm-cli storage pools

# 创建新的 KVM VDI 或 ISO 存储池
webkvm-cli storage pool-create backup-pool --type dir --purpose disk --path /opt/webkvm/pools/backup-pool

# 创建新的 Incus（LXC）容器存储池
webkvm-cli storage pool-create lxc-nvme --purpose container --type dir --path /var/lib/incus/storage-pools/lxc-nvme
webkvm-cli storage pool-create lxc-zfs --purpose container --type zfs

# 删除存储池
webkvm-cli storage pool-delete backup-pool

# 列出磁盘卷（KVM 或 Incus）
webkvm-cli storage volumes
webkvm-cli storage volumes webkvm-disks
webkvm-cli storage volumes default

# 列出 ISO 库
webkvm-cli storage isos

# 从 URL 直接下载 ISO 到存储池
webkvm-cli storage download-iso \
  --url "https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso" \
  --name "ubuntu-24.04-server.iso" \
  --pool webkvm-isos
```

### 宿主机物理磁盘（`host disks`）

```bash
# 列出物理磁盘（大小、文件系统类型、挂载点）
webkvm-cli host disks list

# 在挂载存储池磁盘镜像之前进行检查（格式、大小、是否已有数据）
webkvm-cli host disks probe /opt/webkvm/pools/webkvm-disks/ubuntu-26.04.qcow2

# 深度检查（操作系统/分区，需要宿主机上有 libguestfs；会轮询作业）
webkvm-cli host disks probe /opt/webkvm/pools/webkvm-disks/ubuntu-26.04.qcow2 --deep

# 卸载非系统磁盘、分区或挂载点，并清理 systemd 单元
webkvm-cli host disks unmount /mnt/data
webkvm-cli host disks unmount /dev/sdb1
```

---

## Cloud-Init Studio 与配方（`snippets`）

管理声明式 YAML 配置配方和片段：

```bash
# 列出所有 Cloud-Init 配方（官方预设 + 自定义）
webkvm-cli snippets list

# 显示完整的 YAML 配方和元数据
webkvm-cli snippets show preset-k3s
webkvm-cli snippets show preset-docker

# 创建自定义 Cloud-Init 片段
webkvm-cli snippets create \
  --name "PostgreSQL Bootstrap" \
  --category devops \
  --type user-data \
  --desc "Installs PostgreSQL 16 and configures default database" \
  --file ./postgres-init.yaml

# 删除自定义片段
webkvm-cli snippets delete <snippet-id>
```

---

## 网络管理（`networks`）

```bash
# 列出网络和网桥
webkvm-cli networks list

# 显示详细的网络配置
webkvm-cli networks show vmbr0

# 查看活动的 DHCP 租约
webkvm-cli networks leases vmbr1

# 启动或停止网络网桥
webkvm-cli networks start <name>
webkvm-cli networks stop <name>
```

---

## 服务器设置（`settings`）

实时查看和修改服务器设置：

```bash
# 列出所有设置及其当前生效值
webkvm-cli settings list

# 获取指定的设置项
webkvm-cli settings get terminal.idle_timeout_min

# 更新设置（对可热重载的设置立即生效）
webkvm-cli settings set terminal.idle_timeout_min 0
webkvm-cli settings set logging.level debug
```

---

## 审计日志（`audit`）

检查系统安全和管理操作：

```bash
# 查看最近 20 条审计记录
webkvm-cli audit list

# 以 JSON 形式查看自定义条数，供 SIEM 集成使用
webkvm-cli --json audit list --limit 100 | jq .
```

---

## 用户与 API 令牌（`users`、`tokens`）

```bash
# 列出用户
webkvm-cli users list

# 创建操作员账户
webkvm-cli users create operator1 "SecurePass123!" --role operator --email user@example.com

# 更新用户密码、角色、邮箱或启用状态
webkvm-cli users update operator1 --password "NewSecurePass456!" --role admin
webkvm-cli users update operator1 --active false

# 删除账户
webkvm-cli users delete operator1

# 列出并创建 API 令牌
webkvm-cli tokens list
webkvm-cli tokens create "ci-cd-pipeline"
```
