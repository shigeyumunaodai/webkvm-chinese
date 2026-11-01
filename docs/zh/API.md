# WebKVM — REST 与 WebSocket API 规范

WebKVM REST API 与 WebSocket 接口的完整技术参考。

[**English**](../API.md) • [**Español**](../API.es.md) • [**简体中文**](API.md)

---

## 认证与安全模型

WebKVM 支持三种不同的认证方式：

1. **会话 Cookie（浏览器 Web UI）**：
   - 通过 `POST /api/auth/login` 认证。
   - 返回 HttpOnly `session` 与 CSRF 双提交 Cookie。
2. **API Bearer 令牌（自动化与 CLI）**：
   - 请求头：`Authorization: Bearer wvmb_<token>`
   - 通过 UI 或 `webkvm-cli tokens create <name>` 生成。
3. **一次性 WebSocket 临时凭证（控制台与终端）**：
   - WebSocket 端点（`/api/vms/{id}/vnc`、`/api/vms/{id}/serial`、`/api/host/terminal`）接受短期有效的一次性临时凭证（`?ticket=<token>`）。
   - 临时凭证在内存中保存 30 秒 TTL，并在首次升级时作废，防止凭据通过 URL 泄漏。
   - `?ticket=` 仅限终端/SSE 端点（`/api/host/terminal`、`/api/events`、`/api/vms/{id}/serial`）：在任何其他 `/api/*` 路由上出示有效的控制台临时凭证会返回 `403`，因此控制台临时凭证永远不能代替完整会话。

---

## 端点参考

### 1. 认证与会话

#### `POST /api/auth/login`
对用户进行认证并建立会话。
- **请求体**：
  ```json
  {
    "username": "admin",
    "password": "your-password"
  }
  ```
- **响应 `200 OK`**：
  ```json
  {
    "token": "eyJhbGciOiJIUzI1NiIs...",
    "csrf": "6f2e...",
    "user": "admin",
    "role": "admin",
    "must_change_password": false
  }
  ```

#### `GET /api/auth/me`
返回当前已认证用户的身份与角色。

---

### 2. 虚拟机与容器

#### `GET /api/vms`
列出所有 KVM 虚拟机与 Incus 容器。
- **响应 `200 OK`**：
  ```json
  [
    {
      "id": "3036beb7-4116-4d73-8db8-a71e94033526",
      "name": "ubuntu-srv",
      "type": "vm",
      "state": "running",
      "vcpus": 2,
      "ram_mb": 2048,
      "disk_gb": 20,
      "ip": "192.168.1.150",
      "autostart": true
    }
  ]
  ```

#### `POST /api/vms`
创建新的 KVM 虚拟机或 Incus 容器。
- **请求体**：
  ```json
  {
    "name": "debian-prod",
    "type": "vm",
    "vcpus": 2,
    "ram_mb": 2048,
    "disk_gb": 20,
    "image": "debian-12",
    "storage_pool": "webkvm-disks",
    "network": "vmbr0",
    "cloud_init": {
      "user": "admin",
      "password": "SecurePassword123!",
      "ssh_key": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...",
      "hostname": "debian-prod"
    }
  }
  ```

#### 生命周期操作
- `POST /api/vms/{id}/start` — 启动实例
- `POST /api/vms/{id}/shutdown` — 发送 ACPI 关机信号
- `POST /api/vms/{id}/forceoff` — 立即断电（destroy）
- `POST /api/vms/{id}/reboot` — 发送重启命令
- `POST /api/vms/{id}/suspend` — 暂停虚拟机或冻结容器
- `POST /api/vms/{id}/resume` — 恢复执行
- `DELETE /api/vms/{id}` — 取消定义实例并删除磁盘

#### 虚拟机磁盘
- `POST /api/vms/{id}/disks` — 挂载已有镜像（`source`）或创建新卷（`pool`、`size_gb`、`format`）。挂载已包含数据的镜像会被拒绝并返回 `409`，除非请求设置 `"force": true`；挂载已连接到另一台虚拟机的卷会被拒绝并返回 `409`。
- `GET /api/vms/{id}/disks/{dev}/probe` — 对已挂载的磁盘镜像进行只读检查（格式、虚拟/已分配大小、`has_data`）。已认证的 viewer 可调用。

#### 存储迁移
- `POST /api/vms/{id}/move-storage` — 将实例的存储迁移到另一个存储池。返回 `202 Accepted` + `job_id`；轮询 `GET /api/storage/jobs/{id}` 获取字节级进度。
  - **请求体**：`{"pool": "webkvm-incus-2"}`
  - 目标存储池的用途必须与实例匹配：Incus 容器为 `container`，KVM 虚拟机为 `disk`（或 `template`）。不匹配会被拒绝并返回 `400`（`pool "X" cannot hold a container`）。
  - **KVM 虚拟机**：每个 qcow2/raw 磁盘被复制到目标存储池，并重新指向域 XML。
  - **Incus 容器**：rootfs *及其快照*通过 Incus 原生实例迁移搬迁。容器必须处于**已停止**状态（否则返回 `409`），且目标存储池必须与当前不同。
  - 跨 hypervisor 迁移（libvirt 存储池 ⇄ Incus 存储池）按设计拒绝——请改用导出和重新导入。

#### 实例元数据
- `PUT /api/vms/{id}/meta` — 更新别名、备注、封面、分组、所有者，以及 `template` / `shared` 标志。
  - 模板上的 `"shared": true` 使其对**每个**用户可见且可实例化，绕过所有者/分组/标签范围限制。**仅限管理员。** 每次实例化都会复制模板的完整磁盘。克隆永远不会继承该标志。

#### 硬件与设备
- `GET /api/vms/{id}` — 完整实例详情；`PATCH /api/vms/{id}` 更新 vCPU、内存、CPU 型号/拓扑、固件和磁盘调优。
- `GET`/`POST /api/vms/{id}/boot` — 读取或设置启动设备（仅 `disk`、`cdrom`、`network`——其他任何值都会被拒绝）。
- `GET`/`POST`/`DELETE /api/vms/{id}/networks[/{mac}]` — 列出、连接、编辑（`PATCH`）或断开网络接口。`GET /api/vms/{id}/vlan-support` 报告后端网桥是否接受 VLAN 标签。
- `POST /api/vms/{id}/usb` 与 `DELETE /api/vms/{id}/usb/{vendorId}/{productId}` — 连接/断开宿主机 USB 设备。**仅限管理员。**
- `POST /api/vms/{id}/pci` — 将一个或多个宿主机 PCI 地址直通给**已停止**的虚拟机：`{"addresses": ["0000:01:00.0", "0000:01:00.1"]}`。**仅限管理员。** 通常会一次直通同一 IOMMU 组内的所有地址；启动/控制台 GPU 一律拒绝。审计为 `vm.pci_attach`。
- `DELETE /api/vms/{id}/pci/{address}` — 断开已直通的设备。地址在路径中需进行百分号编码（它包含 `:` 和 `.`）。审计为 `vm.pci_detach`。
- `POST`/`DELETE /api/vms/{id}/shared-folders[/{tag}]` — 管理 virtiofs 共享文件夹。
- `GET /api/vms/{id}/graphics`、`/spice`、`/rdp` — 图形配置以及可下载的 `.vv` / `.rdp` 连接文件。

#### 快照
- `GET`/`POST /api/vms/{id}/snapshots` — 列出或创建快照（`{"name": "...", "memory": false}`）。对运行中的虚拟机做仅磁盘快照时，若客户机代理响应则为文件系统一致，否则回退为崩溃一致。
- `DELETE /api/vms/{id}/snapshots/{sid}` 与 `POST /api/vms/{id}/snapshots/{sid}/revert`。
- `GET /api/vms/snapshots` — 全集群快照列表，按调用者的虚拟机 ACL 限定范围。

#### 客户机集成与监控
- `GET /api/vms/{id}/guest-info` — `qemu-guest-agent` 上报的数据（IP、主机名、操作系统）。
- `POST /api/vms/{id}/reset-password` — 通过客户机代理重置客户机账户密码。
- `POST /api/vms/{id}/clipboard` — 将文本推送至客户机剪贴板。
- `GET /api/vms/{id}/metrics` 与 `/metrics/history` — 实时与历史 CPU/内存/IO 计数器。
- `GET /api/vms/{id}/logs` — 该实例最近的 libvirt/QEMU 日志行。
- `GET`/`PUT /api/vms/{id}/alerts` — 按实例的告警阈值。
- `GET`/`PUT /api/vms/{id}/schedule` — 基于 Cron 的自动开关机。

#### 克隆、模板与 Cloud-Init
- `POST /api/vms/{id}/clone` — 复制实例（包括其磁盘）。
- `POST /api/vms/{id}/make-template` 与 `POST /api/vms/{id}/unset-template`。
- `GET`/`POST /api/vms/{id}/cloudinit` — 读取或替换该实例的 NoCloud user-data。
- `POST`/`DELETE /api/vms/{id}/cover` — 设置或清除卡片图片。

#### Incus 目录
- `GET /api/vms/incus-images` — 容器向导提供的发行版镜像。
- `GET /api/vms/incus-profiles` — 可用的 Incus 配置文件。

---

### 2.1. 模板

- `GET /api/templates` — 列出调用者可见的模板：其拥有或被授予的模板，以及所有标记为 `shared` 的模板。
- `POST /api/templates/{id}/instantiate` — 从模板创建新实例，复制其磁盘。接受 cloud-init 字段（用户、密码、SSH 密钥、主机名）用于 NoCloud 置备。

---

### 3. 镜像中心与后台任务

#### `GET /api/images/cloud-base`
列出可用及本地已缓存的官方云基础镜像。

#### `POST /api/images/cloud-base/pull`
启动官方云镜像的异步后台下载。
- **请求体**：`{"id": "ubuntu-24.04"}`
- **响应 `202 Accepted`**：
  ```json
  {
    "id": "ubuntu-24.04",
    "job_id": "base_img_1789672293311288289",
    "status": "queued"
  }
  ```

#### `GET /api/storage/jobs/{id}`
轮询活动下载或后台任务的进度、速度与状态。
- **响应 `200 OK`**：
  ```json
  {
    "id": "base_img_1789672293311288289",
    "name": "Download Ubuntu 24.04",
    "progress": 48.47,
    "status": "downloading",
    "bytes_done": 89050176,
    "bytes_total": 183697408,
    "speed_bps": 50447203,
    "eta_seconds": 1,
    "updated_at": 1789672295
  }
  ```

---

### 4. 存储与存储池

- `GET /api/storage/pools` — 列出存储池及其容量与用途。用途为 `disk`（libvirt 虚拟机镜像）、`container`（Incus rootfs）、`iso`、`backup`、`template` 中的一个或多个，当代一个存储池服务多种用途时以逗号分隔。
- `POST /api/storage/pools` — 创建目录型或 NFS/CIFS 存储池。
- `GET /api/storage/volumes` — 列出全部或指定存储池中的卷（按调用者的 `AllowedPools` 限定；受限用户在其他存储池看到空列表）。
- `GET /api/storage/isos` — 列出所有可用 ISO 镜像（同样的存储池范围限制；ISO 上传/下载同样强制 `AllowedPools`）。
- `POST /api/storage/isos/download` — 将 ISO 直接下载到 ISO 存储池。
- `POST /api/storage/probe-disk` — 在挂载前检查存储池中的磁盘镜像：`{"path": "...", "deep": false}` 通过 `qemu-img` 返回 `{format, virtual_size, allocated, has_data, backing_file}`。若 `"deep": true`（需要宿主机安装 `libguestfs`，见宿主机能力中的 `guestfs`），则返回 `202` + 任务；轮询 `GET /api/storage/jobs/{id}` 获取操作系统/分区/文件系统报告。

---

### 5. 控制台与 WebSocket

- `POST /api/vms/{id}/console-ticket` — 生成虚拟机串口控制台的 30 秒临时凭证。
- `GET /api/vms/{id}/serial?ticket={tk}` — 到客户机串口的 WebSocket 流。
- `POST /api/vms/{id}/vnc-ticket` — 生成虚拟机 VNC 图形临时凭证。
- `GET /api/vms/{id}/vnc?vt={ticket}` — 到 RFB/noVNC 帧缓冲的 WebSocket 代理。
- `POST /api/host/terminal-ticket` — 生成宿主机 shell 的管理员临时凭证。
- `GET /api/host/terminal?ticket={tk}&cols={N}&rows={N}` — WebGL 加速的宿主机 PTY 流。

---

### 6. 实时事件（服务器发送事件）

#### `GET /api/events`
打开一个持久的 SSE 流，广播实时系统事件：
- `vm.state_changed`：实例电源状态转换（`running`、`shutoff`、`paused`）。
- `vm.created` / `vm.deleted`：实例生命周期通知。
- `task.progress`：后台任务的实时更新。

---

### 7. 宿主机能力与物理磁盘

- `GET /api/host/capabilities` — 报告本地 QEMU/libvirt 接受的能力（视频/图形型号、磁盘总线、CPU 型号/特性、`spice_supported`、`parsed`）。包含 `guestfs` / `guestfs_bin`：是否安装了 `virt-inspector` + `guestfish`，这将解锁深度磁盘检查。
- `GET /api/host/disks` — 列出物理磁盘及其 `fstype`、挂载点和分区子项（来自 `lsblk`）。
- `POST /api/host/capabilities/refresh` — 重新探测 QEMU/libvirt，而不是返回缓存的报告。
- `GET /api/host/disks` / `GET /api/host/disks/filesystems` / `GET /api/host/disks/orphan-mounts` — 物理磁盘、其文件系统，以及后端设备已消失的挂载点。
- `POST /api/host/disks/wipe` 与 `POST /api/host/disks/initialize-directory`（仅限管理员）— 破坏性防护是**失败即关闭（fail-closed）**的：如果 `lsblk` 安全检查无法运行或无法解析，请求会被拒绝并返回 `503`，而不是继续执行。`mount_point` 必须位于 `/mnt/` 或 `/srv/` 下；wipe 步骤失败时会中止整个操作。
- `GET /api/host/pci-devices` — 可用于直通的宿主机 PCI 设备，按 IOMMU 分组。**仅限管理员。**
- `GET /api/host/pci-preflight` — IOMMU/VFIO 就绪状态：IOMMU 是否开启、有多少分组、以及它们是否可干净分配。当报告称设备所在分组会连带无关设备时，UI 会阻止直通挂载。
- `GET /api/host/usb-devices` — 当前插入宿主机的 USB 设备。**仅限管理员。**
- `GET /api/host/stats` 与 `GET /api/host/metrics` — 宿主机 CPU、内存、负载和存储计数器。

### 8. 网络

- `GET`/`POST /api/networks` — 列出或创建宿主机网桥（可选 IP、DHCP 范围、网关、DNS、自启动）。
- `PUT`/`DELETE /api/networks/{id}` — 更新或移除网桥。
- `POST /api/networks/{id}/start` 与 `/stop` — 启用或停用受管网桥。
- `GET /api/networks/{id}/leases` 与 `DELETE /api/networks/{id}/leases/{mac}` — 查看并释放 DHCP 租约。
- `GET /api/host/interfaces` — 宿主机上的物理网卡与现有网桥。

---

### 9. 防火墙

按虚拟机的规则位于实例下；宿主机级规则使用**安全应用（Safe-Apply）**协议，不会把你锁在外面。

- `GET`/`PUT /api/vms/{id}/firewall` — 按虚拟机的入站规则与宿主机→虚拟机端口转发。
- `GET /api/firewall/host` — 当前已确认的宿主机规则集。
- `POST /api/firewall/host/preview` — 渲染载荷将产生的 nftables 规则集，但不应用。
- `POST /api/firewall/host/apply` — 暂存新规则集并启动确认计时器（默认 30 秒，可通过 `firewall.confirm_window_secs` 在 10 到 300 之间配置）。返回上一规则集与确认 `deadline`。同一时间只允许一个待确认应用（否则返回 `400`）。
- `POST /api/firewall/host/confirm` — 保留已暂存的规则集。**如果在截止时间前始终未收到确认，上一已确认规则集将自动恢复**——该机制保护刚刚把自己 SSH 锁掉的远程管理员。
- `POST /api/firewall/host/rollback` — 立即回滚已暂存的规则集；没有暂存内容时返回 `{"status": "no_pending"}`。
- `GET /api/firewall/host/export` 与 `POST /api/firewall/host/import` — 可移植的 JSON 规则集（请求体上限 1 MB）。

---

### 10. 备份

- `GET`/`POST /api/backup/targets` — 列出或创建备份目标（本地目录、NFS/SMB 挂载、SFTP）。
- `PUT`/`DELETE /api/backup/targets/{id}` — 更新或移除目标；`DELETE /api/backup/targets/{id}/config` 只删除其存储的配置归档。
- `POST /api/backup/targets/test` — 保存前验证连通性与可写性。
- `POST /api/backup/targets/{id}/run` — 启动一次备份运行；返回任务 id。
- `GET /api/backup/targets/{id}/files` 与 `DELETE …/files/{filename}` — 浏览并清理目标上的归档。
- `GET /api/backup/targets/{id}/verify` — 重新校验已存储归档的 SHA-256。
- `POST /api/backup/targets/{id}/restore` — 完整恢复（强制执行大小限制与受保护路径检查）。
- `POST /api/backup/targets/{id}/restore-as-vm` — 将归档重新导入为全新虚拟机。
- `DELETE /api/backup/targets/{id}/runs/{suffix}` — 删除一次完整的运行。
- `GET`/`POST /api/backup/schedules`、`PUT`/`DELETE /api/backup/schedules/{id}` — 带 keep-last / keep-days 保留策略的 Cron 计划。
- `GET /api/backup/jobs` 与 `GET /api/vms/{id}/backup/jobs` — 运行历史，全局或按实例。
- `POST /api/vms/{id}/backup` — 将单个实例备份到指定目标；`GET /api/vms/{id}/backup/targets` 列出符合条件的目标。

机密（webhook、SMTP、SFTP、CIFS 凭据）绝不会写入配置备份。

---

### 11. 用户、用户组、配额与令牌

- `GET`/`POST /api/users` — 列出或创建用户（`role`：`admin`、`operator`、`viewer`）。**仅限管理员。**
- `PUT`/`DELETE /api/users/{username}` — 更新角色、用户组、`allowed_pools` 与配额，或删除账户。
- `POST /api/users/{username}/revoke-sessions` — 使该用户的所有活动会话失效。
- `GET /api/users/{username}/usage` 与 `GET /api/users/me/usage` — 当前配额消耗（虚拟机数量、vCPU、内存、磁盘）。
- `PUT /api/users/me/password` — 修改自己的密码；强制执行密码策略并清除 `must_change_password` 标志。
- `GET`/`POST`/`PUT`/`DELETE /api/groups[/{name}]` — 管理用于 ACL 范围限定的用户组。
- `GET`/`POST /api/tokens` — 列出或签发 API 令牌（`wvmb_…`，仅返回一次，以 SHA-256 哈希存储，默认 30 天过期）。
- `POST /api/tokens/{id}/revoke` 与 `DELETE /api/tokens/{id}` — 立即撤销（持久化到 `revoked.json`）或删除记录。

配额覆盖**运行中**实例的 vCPU/内存，以及跨存储池的**全局**磁盘。实例化模板会将配额计入实例化用户。管理员按设计不受配额和存储池 ACL 限制。

---

### 12. Cloud-Init 片段

- `GET`/`POST /api/cloudinit/snippets` — 列出或创建可复用的 user-data 片段。
- `GET`/`PUT`/`DELETE /api/cloudinit/snippets/{id}` — 管理单个片段。
- `POST /api/cloudinit/preview` — 为一组输入渲染最终的 NoCloud user-data，而不创建任何内容。

---

### 13. 应用、辅助脚本与媒体

- `GET`/`POST /api/appliances` — 社区应用目录；`PUT`/`DELETE /api/appliances/{id}` 用于自定义条目。
- `POST /api/appliances/{id}/deploy` — 部署应用。目标网络会先针对可用网桥校验（在创建任何任务之前返回 `400`），cloud-init 载荷在排队前也会校验。初始化失败会将任务标记为 `error`，不写入 `AppInfo`，并审计 `appliance.deploy_cloudinit_failed`。
- `GET /api/appliances/{id}/provision` — 应用首次启动时运行的置备脚本。
- `GET /api/helper-scripts`、`POST /api/helper-scripts/refresh`、`GET /api/helper-scripts/{slug}/provision` — 社区辅助脚本目录。
- `GET`/`POST /api/media`、`POST /api/media/upload`、`DELETE /api/media/{id}`、`GET /api/media/{id}/raw`、`POST /api/media/apply-usage` — 卡片封面与品牌素材。

---

### 14. 系统、设置、通知与审计

- `GET /api/system/status` — 后端、libvirt 与宿主机状态，以及可用更新。
- `GET /api/system/logs` — 最近的服务日志。
- `POST /api/system/update` — 触发应用内更新（仅原生安装；见 DOCKER.md）。要求后端以 root 运行且服务环境中设置了 `WEBKVM_ALLOW_UPDATE=1`，否则返回 `403`。返回 `202` 及 `{status, mode, updater, log}`；`mode` 为 `release`（安装经校验的 GitHub 发布产物）或 `source`（从检出目录重建），取决于 `REPO_DIR` 是否为 git 检出而自动选择。如果更新脚本或 `systemd-run` 缺失则返回 `503`。进度会追加到返回的 `log` 路径。
- `POST /api/system/restart` 与 `POST /api/system/apply-restart` — 重启服务，可选择先应用已暂存的设置。
- `POST /api/system/backup` 与 `GET /api/system/backups` — Datadir 快照。
- `GET /api/system/cert` — 下载服务器证书，以便在本地信任它（按设计无需认证）。
- `GET`/`PUT /api/settings` — 读取或写入服务器配置；`GET /api/settings/schema` 描述每个字段，`POST /api/settings/apply-live` 应用无需重启即可生效的更改，`POST /api/settings/reset` 恢复默认值。
- `GET`/`PUT /api/notify/config`、`GET /api/notify/events`、`POST /api/notify/test` — Webhook/SMTP 通知渠道、可订阅事件列表，以及测试投递。
- `GET`/`POST`/`PUT`/`DELETE /api/nodes[/{id}]` — 用于多宿主机视图的远程节点注册表。
- `GET /api/audit` — 跨活动日志与轮转日志的分页、最新优先的审计记录；`GET /api/audit/export` 流式导出以供归档。**仅限管理员。**
- `GET /api/alerts/active`、`GET /api/tags`、`GET /api/jobs/{id}` — 活动告警、全局标签列表，以及通用任务轮询。

---

### 虚拟机导出（`GET /api/vms/{id}/export`）
- `?format=proxmox` — 生成与 Proxmox `pct restore` 兼容的 `vzdump-lxc-*.tar.zst` 归档。仅对 `hypervisor=="incus"` 容器有效。生成 `etc/vzdump/pct.conf` + `rootfs/` 目录树（zstd 压缩）。

### 虚拟机导入（`POST /api/vms/import`）
- 自动检测 Proxmox `vzdump-lxc-*.tar.zst` / `.tar.gz` 文件（含 `./etc/vzdump/pct.conf` 或根级 rootfs），并通过 `internal/vzdump` 自动转换为 Incus 原生备份。同时处理 Proxmox 布局（文件位于根）与 Incus 布局（`rootfs/` 前缀）、硬链接和符号链接。输出遵循 Incus `backup/container/` 约定（`backup.yaml`、`index.yaml`、`rootfs/`）。
- 导入时**容器名**字段为必填。
