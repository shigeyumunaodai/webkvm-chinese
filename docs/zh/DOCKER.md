# 在 Docker 中运行 WebKVM

WebKVM 首先是**原生**应用（见 [INSTALLATION.md](INSTALLATION.md)）；容器镜像只是同一二进制的*另一种*打包方式，面向偏好用 Docker/Compose 管理它的用户。它**不是**另一种更轻量的产品：目标是实现与原生安装 1:1 的功能对等，只有一处无法避免的例外（自更新，见下文）。

[**English**](../DOCKER.md) • [**Español**](../DOCKER.es.md) • [**简体中文**](DOCKER.md)

## 工作方式

容器**不**捆绑 libvirtd、QEMU 或 Incus。它像原生二进制一样，连接**宿主机上已经在运行**的 libvirtd（对于 **LXC 容器**，则连接 Incus/LXD 守护进程）——虚拟机和容器由宿主机的守护进程管理，而不是在容器内管理。这意味着：

- **前提条件：** 宿主机必须已经安装并运行 libvirt/QEMU。如果还没有，先运行一次 `install.sh`（或直接 `make install-deps`）完成准备——Docker 模式不会替你安装 libvirt/QEMU。对于容器，请挂载宿主机的 Incus socket（见下方绑定挂载表），并通过 `WEBKVM_INCUS_ENABLED=1` 启用该模块。
- 容器只需要 webkvm 二进制会调用的*客户端侧*工具（`qemu-img`、`virsh`、`ip`、`nft`、`xorriso`、`openssl`、`tar` 等），从不需要 `/dev/kvm` 或 QEMU/libvirt 服务端。
- 完整功能（虚拟机桥接到真实 LAN、按虚拟机配置 nftables 规则）需要 `--network host --privileged`——与原生安装同等信任级别，因为其 systemd 单元同样以 root 身份在宿主机上运行。不存在“精简”模式。

## 快速开始（自动）

全新服务器上一行命令——缺少 libvirt/QEMU 与 Docker 时会自动安装，然后部署已发布的镜像：

```bash
curl -fsSL https://raw.githubusercontent.com/Slaker19/webkvm/main/scripts/install-docker.sh -o /tmp/webkvm-docker-install.sh && sudo bash /tmp/webkvm-docker-install.sh
```

或者，从本仓库的检出目录运行：

```bash
sudo ./docker-install.sh              # 拉取已发布的镜像
sudo ./docker-install.sh --source     # 改为本地构建镜像
sudo ./docker-install.sh --dry-run    # 仅预览，不做任何更改
```

该脚本会校验/安装与原生安装 `install.sh` 相同的 libvirt/QEMU/KVM 栈（见下方 **宿主机软件包**——容器本身已自带其余一切），校验/安装 Docker Engine 与 compose 插件，然后使用 `docker-compose.yml` 中的完整权限/挂载执行 `docker compose up -d`。前提步骤是幂等的——可安全重复运行。

## 快速开始（手动，使用已发布的镜像）

```bash
# 1) 如果你的路径与默认值不同，先编辑 docker-compose.yml，然后：
docker compose up -d
```

`docker-compose.yml` 默认指向 `slaker1908/webkvm:latest`，因此 `docker compose up -d` 只会拉取它——无需本地构建。

想改为从源码构建（例如测试本地改动）？

```bash
make docker-build   # 本地构建二进制 + 镜像，打标签 webkvm:latest
docker compose build
docker compose up -d
```

打开 `https://<host-ip>:8080`——首次启动时会生成自签名证书和初始管理员密码，与全新的原生安装完全一样。（如果 `DATA_DIR` 已存放现有原生安装，打印出的“管理员密码”文件可能是*那次*安装首次启动时遗留的过期文件，而不是当前密码——请用你现有的凭据登录。）

## 宿主机软件包（前提——在 Docker 之前安装）

Docker 模式不会替你安装 libvirt/QEMU——容器是宿主机上已运行 libvirtd 的客户端，因此这套软件栈必须已经安装并运行在宿主机上，与 `install.sh` 为原生安装所做设置完全一致。`docker-install.sh` 会替你安装这些软件包；如果你想手动操作：

| 发行版系列 | 命令 |
|---|---|
| Debian/Ubuntu（`apt`） | `sudo apt-get install libvirt-daemon-system libvirt-clients libvirt-daemon-driver-qemu qemu-system-x86 qemu-utils ovmf swtpm swtpm-tools virtinst bridge-utils dnsmasq-base` |
| Fedora/RHEL（`dnf`） | `sudo dnf install libvirt-daemon libvirt-daemon-driver-qemu libvirt-daemon-driver-storage libvirt-daemon-driver-network libvirt-daemon-driver-interface libvirt-daemon-driver-nodedev libvirt-daemon-driver-nwfilter libvirt-daemon-driver-secret libvirt-daemon-config-network libvirt-client qemu-kvm-core qemu-img edk2-ovmf swtpm-tools virt-install bridge-utils dnsmasq` |
| Arch（`pacman`） | `sudo pacman -S libvirt qemu-full qemu-img swtpm edk2-ovmf virt-install dnsmasq` |

然后启用守护进程与 Docker 本身：

```bash
sudo systemctl enable --now libvirtd   # 或在新版 libvirt（9.7+）上使用 virtqemud
sudo systemctl enable --now docker
```

Docker Engine + compose 插件（如尚未安装）：

| 发行版系列 | 命令 |
|---|---|
| Debian/Ubuntu | `sudo apt-get install docker.io docker-compose-v2` |
| Fedora/RHEL | `sudo dnf install moby-engine docker-compose-plugin`（或添加 Docker 官方软件源：https://docs.docker.com/engine/install/fedora/） |
| Arch | `sudo pacman -S docker docker-compose` |

注意这些列表里**没有**什么：`xorriso`、`openssl`、`python3`、`nftables`、`qemu-utils` 的 CLI 工具等供*容器自身*使用的东西——它们在镜像内部（见 Dockerfile），而不在宿主机上。容器也通过 `--network host` 直接共享宿主机的网络命名空间来访问宿主机的 nftables——因此同样不需要宿主机侧单独的 nftables 软件包。

## 手动 `docker run`（不使用 compose）

等价于 `docker-compose.yml`，面向喜欢单条命令而非 Compose 的用户（如果 `DATA_DIR` 不是 `/opt/webkvm`，请填入真实路径）：

```bash
docker run -d \
  --name webkvm \
  --restart unless-stopped \
  --network host \
  --privileged \
  -e DATA_DIR=/opt/webkvm \
  -e LIBVIRT_URI=qemu:///system \
  -e BIND_ADDR=0.0.0.0 \
  -e PORT=8080 \
  -v /opt/webkvm:/opt/webkvm \
  -v /var/run/libvirt:/var/run/libvirt \
  -v /run/systemd:/run/systemd \
  -v /var/log/journal:/var/log/journal:ro \
  -v /etc/passwd:/etc/passwd:ro \
  -v /etc/shadow:/etc/shadow:ro \
  -v /etc/group:/etc/group:ro \
  -v /etc/pam.d:/etc/pam.d:ro \
  slaker1908/webkvm:latest
```

每个 `-v`/`-e` 的理由见下方 **绑定挂载——内容与原因**。之后可用 `docker logs -f webkvm`、`docker restart webkvm`、`docker rm -f webkvm` 管理。

## 绑定挂载——内容与原因

| 宿主机路径 | 容器路径 | 原因 |
|---|---|---|
| `/opt/webkvm` | `/opt/webkvm` | `DATA_DIR`：用户、设置、证书、磁盘/ISO 存储池。两侧挂载到**相同的绝对路径**——libvirt 将存储池位置保存为目录路径，如果容器看到的路径与宿主机 libvirtd 看到的路径不同，存储池就会指向一个空目录或错误目录。 |
| `/var/run/libvirt` | `/var/run/libvirt` | 宿主机的 libvirt socket，使 `LIBVIRT_URI=qemu:///system` 能连到宿主机的 libvirtd——与原生二进制的连接方式完全相同。 |
| `/run/systemd` | `/run/systemd` | 让容器内的 `systemctl` CLI 能操作宿主机真实的 systemd（用于 `journalctl`/服务重启）。 |
| `/var/log/journal`（只读） | `/var/log/journal` | 使 `journalctl` 能读取宿主机实际的服务日志。 |
| `/etc/passwd`、`/etc/shadow`、`/etc/group`、`/etc/pam.d`（只读） | 相同路径 | **宿主机终端**功能通过 PAM 认证真实宿主机用户账户。只共享*数据*文件——容器使用**自己的** `/bin/login` 二进制（同样是 Debian 基础镜像），而非宿主机的，以避免两个文件系统间 glibc/库版本不匹配。PAM 的 `pam_unix` 模块只读取这些数据文件，因此认证仍然校验真实宿主机密码。 |
| `/var/lib/incus/unix.socket` *（容器）* | `/var/lib/incus/unix.socket` | 宿主机的 **Incus socket**，使容器模块（`WEBKVM_INCUS_ENABLED=1`）能连到宿主机的 Incus 守护进程——与原生二进制的连接方式完全相同。对于旧版 LXD 守护进程，改挂载其 socket（snap 为 `/var/snap/lxd/common/lxd/unix.socket`，apt 为 `/var/lib/lxd/unix.socket`）。容器进程必须能读取该 socket（它在容器内以 root 运行，与宿主机的信任模型一致）。 |

共享宿主机的认证文件与 systemd socket，再加上 `--privileged`，使容器对宿主机拥有**等同于 root 的信任级别**——这不是新的安全回退，而是原生安装本来就有的同等信任（其 systemd 单元以 `User=root` 运行）。在不理解这一点的情况下，不要把此容器暴露给不受信任的操作员。

## 环境变量

| 变量 | 默认值 | 含义 |
|---|---|---|
| `DATA_DIR` | `/opt/webkvm` | 状态/证书/存储池的存放位置。需与上方卷挂载保持一致。 |
| `LIBVIRT_URI` | `qemu:///system` | libvirt 连接 URI（通过挂载的 socket 连接宿主机）。 |
| `BIND_ADDR` | `0.0.0.0` | 容器内的监听地址（配合 `network_mode: host` 时即宿主机自身的网卡）。 |
| `PORT` | `8080` | 监听端口。 |

## 唯一有意为之的例外：自更新

原生安装的更新按钮会替换宿主机上的二进制并重启 systemd 单元——要么来自经过校验的 GitHub 发布版，要么在检出目录中从源码重新构建。两者对容器都不适用：你不会重建正在运行的容器，而是替换它。**在 Docker 模式下不要使用应用内更新流程。** 请改为拉取新镜像并重新创建容器：

```bash
docker compose pull
docker compose up -d
```

（如果你从源码构建而不是使用已发布镜像，等价命令是 `git pull && make docker-build && docker compose up -d`。）

其余一切——宿主机终端、日志、服务重启、虚拟机网络、防火墙——都设计为与原生安装表现完全一致。

## 注意事项

- 在给定宿主机上**要么**运行原生安装**要么**运行容器，不要同时运行——它们会争抢同一端口和同一批磁盘/ISO 存储池。
- **绝不要让第二个 webkvm 实例（Docker 或原生）用不同的 `DATA_DIR` 连接同一个 libvirtd，哪怕“只是测试”。** libvirt 存储池在该连接上**按名称**标识，而不按 `DATA_DIR` 划分：如果第二个实例已有同名存储池（例如 `webkvm-disks`、`webkvm-isos`），它会静默地**将其目标路径重新定义**为自己的 `DATA_DIR/pools/...`，从而破坏第一个实例对自身存储的视图（底层文件不会被动，但指向它们的存储池对象会变）。如果需要测试 Docker 模式，请针对尚无存储池的 libvirtd 进行，或先重命名测试用存储池。
- 镜像按与二进制相同的目标架构（`amd64`）构建；请在你打算运行它的宿主机上/为其构建。
- 在 libvirt **不新于**镜像内版本的发行版上构建二进制（Ubuntu 24.04，与 CI 一致）：二进制通过 CGO 动态链接 libvirt，针对 libvirt 12 构建的二进制（例如 Debian 13、Ubuntu 26.04）在镜像内会因 `LIBVIRT_11.x not found` 失败——甚至无法打印版本号。拿不准时，在 24.04 工具链内构建。
