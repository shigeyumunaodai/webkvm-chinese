# WebKVM — 内部架构深度解析

关于 WebKVM 背后工程原则、后端并发模式与前端设计的技术指南。

[**English**](../ARCHITECTURE.md) • [**Español**](../ARCHITECTURE.es.md) • [**简体中文**](ARCHITECTURE.md)

---

## 系统架构总览

```text
┌────────────────────────────────────────────────────────────────────────┐
│                   Web Browser / Client Applications                    │
│        Svelte 5 SPA • @xterm/xterm WebGL • noVNC RFB • SSE Client      │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ HTTP/2 / TLS / WebSockets / SSE
┌───────────────────────────────────▼────────────────────────────────────┐
│                  WebKVM Backend (Single Go Binary)                     │
│                                                                        │
│   ┌─────────────────────┐ ┌───────────────────┐ ┌──────────────────┐   │
│   │   Chi HTTP Router   │ │  JWT & Token Auth │ │ Global Rate Lim. │   │
│   └──────────┬──────────┘ └─────────┬─────────┘ └────────┬─────────┘   │
│              │                      │                    │             │
│   ┌──────────▼──────────────────────▼────────────────────▼─────────┐   │
│   │               API Handlers & Service Layer                     │   │
│   │   VMs • Storage • Networks • Image Hub • Firewall • Settings   │   │
│   └───────────────────────┬──────────────────────┬─────────────────┘   │
│                           │                      │                     │
│   ┌───────────────────────▼────────┐  ┌──────────▼─────────────────┐   │
│   │       KVM / libvirt Driver     │  │    Incus / LXD Driver      │   │
│   │     (CGO + Unix RPC Socket)    │  │    (Native Go REST Client) │   │
│   └────────────────────────────────┘  └────────────────────────────┘   │
│                                                                        │
│   ┌────────────────────────────────────────────────────────────────┐   │
│   │              Embedded Svelte 5 Static Assets                   │   │
│   │                  //go:embed all:dist (SPA)                     │   │
│   └────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 核心子系统

### 1. 单一二进制范式（`go:embed`）
WebKVM 消除了多层 Web 应用的运维复杂性：
- 编译期间（`make build`），Vite 将 Svelte 5 单页应用构建到 `frontend/dist/`。
- Go 编译器使用 Go 1.16+ 的 `embed.FS` 将所有编译后的资源、样式、字体和脚本直接嵌入可执行文件。
- 运行时，`internal/frontend/embed.go` 直接从内存提供单页应用，并附带最优缓存头（`Cache-Control: public, max-age=31536000`）。

### 2. 混合计算层（`internal/compute`）
WebKVM 在 `internal/compute/backend.go` 中定义了一个干净、抽象的 `Instance` 接口：
- **`KVMBackend`（`internal/compute/kvm.go`）**：通过 `libvirt.org/go/libvirt` 与基于 Linux 内核的虚拟机（KVM）交互。处理硬件虚拟化、QEMU 域 XML 生成、PCI 设备挂载与 VirtIO 驱动。
- **`IncusBackend`（`internal/compute/incus/incus.go`）**：使用官方 Incus Go 客户端 SDK，直接与 Incus/LXD 守护进程 socket（`/var/lib/incus/unix.socket` 或 `/var/snap/lxd/common/lxd/unix.socket`）通信。
- **`CombinedBackend`（`internal/compute/combined.go`）**：根据实例标识将传入的 API 调用无缝路由到 KVM 或 Incus，向用户呈现单一、统一的计算接口。

### 3. 并发与 Goroutine 安全（`internal/safego`）
为保证高可用与崩溃恢复能力：
- 所有后台 goroutine（任务清扫器、下载流、WebSocket 代理、libvirt 事件循环）都使用 `safego.Recover(name)` 包裹。
- 如果隔离的 worker 中发生意外的运行时 panic，panic 会被安全捕获，结构化错误遥测会记录到 journald，主服务器进程保持不中断。

### 4. 内存与性能表现
- **空闲零分配**：当没有活动浏览器连接或后台任务时，WebKVM 的内存占用稳定在 **约 12 MB 至 18 MB RSS 内存**。
- **垃圾回收优化**：WebSocket 代理使用固定大小复用的字节缓冲区（64 KB）流式传输数据，以在大量 I/O 传输时最小化 Go 运行时 GC 压力。

### 5. 磁盘内容检查（`internal/diskprobe` + `hostcaps` GuestFS）
将已有磁盘镜像挂载到虚拟机过去是盲操作：没有任何检查确认镜像是否为空、是否为已安装的客户机操作系统，或是否为其他虚拟机的数据。`internal/diskprobe` 在挂载/格式化之前回答一个问题——*这块磁盘是否已包含数据？*——分为两个层级：
- **基础（始终可用）**：`qemu-img info` 报告真实镜像格式及已分配字节数。新建的 qcow2 分配量约为 0；超过 1 MiB 余量（或存在任何后备文件）即设置 `HasData`。快速、无依赖、只读，超时 15 秒。
- **深度（仅当安装了 libguestfs 时）**：`virt-inspector --no-applications` 启动一个最小化 appliance 来读取分区/文件系统并识别已安装的操作系统（超时 120 秒，因较慢而通过 `submitJob` 作为后台任务提供）。
`hostcaps` 探测 `virt-inspector` + `guestfish`（`LookPath`），并通过 `/api/host/capabilities` 暴露 `GuestFS`/`GuestFSBin`；缺失属正常情况，只会禁用深度路径。`POST /api/vms/{id}/disks` 会拒绝非空镜像并返回 `409`，除非 `force: true`，同样以该方式拒绝重复挂载（一个镜像只能挂载到一台虚拟机）——两者均在服务端强制执行，同时 Add-Disk 对话框会先在客户端呈现警告。

---

## 前端架构（采用 Runes 的 Svelte 5）

WebKVM 专为 **Svelte 5** 设计：
- **Runes 响应式**：状态管理使用 Svelte 5 原语（`$state`、`$derived`、`$effect`），实现确定性、细粒度更新，无虚拟 DOM 开销。
- **动态模块拆分**：每个主要路由（`VmDetail`、`Storage`、`ImageHub`、`HostConsole`、`Settings`）都通过动态 `import()` 拆分为独立的懒加载 chunk。
- **GPU 终端加速**：终端组件集成 `@xterm/xterm` 与 `@xterm/addon-webgl`、`@xterm/addon-unicode11`，直接通过 GPU 以 60 FPS 流式输出终端内容。
- **设计系统**：`app.css` 中的语义化颜色/动效令牌（3 套主题、6 种强调色），基于 shadcn 的原语组件，加上 WebKVM 自有组件（`StatusBadge`、`Tip`、`EmptyState` 变体、`TableSkeleton`/`CardGridSkeleton`/`VmDetailSkeleton`、`Sheet` 抽屉）。模态框位于 `Dialog`/`Sheet` 中；不使用 `window.confirm`。
- **组件拆分**：自包含的对话框/表单从大型路由中抽取，使用显式 props 和父级持有的数据（`DeleteVmDialog`、`ManageGroupsDialog`、`CloudInitPreviewDialog`、`AddScheduleDialog`、`CreateVolumeInlineForm`）。经验法则：仅当一个区块的状态真正自包含时才抽取——那些十几个 `bind:` 字段需要与页面其余部分交叉校验的表单仍留在路由中。
- **i18n**：每个用户可见字符串都经过 `t()`（`i18n.svelte.js` 中的 `en`/`es`/`ca`）；缺失条目时 `t()` 返回原始 key，因此 `t(k) || 'fallback'` 永远不会触发——不要使用该模式。

### Proxmox LXC 兼容性（vzdump）
`internal/vzdump` 包处理 Proxmox vzdump LXC 与 Incus 备份格式之间的双向转换：

- **导入**（`POST /api/vms/import`）：通过查找 `./etc/vzdump/pct.conf` 或根级文件系统条目来检测 `vzdump-lxc-*.tar.zst` / `.tar.gz`。转换为 `backup/container/` 下的 Incus 原生格式（`backup.yaml` 含容器配置 + 卷结构，`index.yaml` 含名称/后端/存储池/类型，`rootfs/`）。同时处理 Proxmox 布局（文件位于根）与 Incus 布局（`rootfs/` 前缀）、硬链接（为 `tar --strip-components=2` 提供正确的 `backup/container/rootfs/` 前缀）以及符号链接。
- **导出**（`GET /api/vms/{id}/export?format=proxmox`）：读取 Incus 备份（剥离 `backup/container/` 前缀），若存在 `rootfs.squashfs` 则通过 `unsquashfs` 展开，从 `backup.yaml` 元数据生成 `pct.conf`，并产出包含 `./etc/vzdump/pct.conf` + `./rootfs/` 的 `vzdump-lxc-*.tar.zst`。
- 需要宿主机安装 `squashfs-tools`（`unsquashfs`、`mksquashfs`）（`.49`）。
- `vzdump_test.go` 中的 **7 个单元测试**覆盖 gzip/zstd 检测、导入、导出和文件名生成。
