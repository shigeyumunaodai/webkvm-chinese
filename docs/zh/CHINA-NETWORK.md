# WebKVM 国内网络优化指南

> 面向中国大陆网络环境的 WebKVM 安装与运行加速指南：系统软件源换镜像、GitHub 下载加速、Docker 镜像仓库配置、pip/npm/Go/Cargo 镜像，以及验证与恢复方法。  
> 相关文档：[完整中文部署说明](DEPLOYMENT.md) · [安装指南](INSTALLATION.md) · [中文文档索引](README.md) · 英文原文 [INSTALLATION.md](../INSTALLATION.md)

本文中的命令默认以 **root** 执行（或加 `sudo`）。所有“换源”操作都会改写系统配置文件，**修改前务必先备份**；仓库自带的一键脚本会自动备份并提供 `--restore`。

---

## 目录

1. [为什么需要换源](#1-为什么需要换源)
2. [一键换源脚本 scripts/cn-mirrors.sh](#2-一键换源脚本-scriptscn-mirrorssh)
3. [安装器集成（--cn-mirrors / --github-proxy）](#3-安装器集成--cn-mirrors----github-proxy)
4. [手动换源（不使用脚本）](#4-手动换源不使用脚本)
5. [GitHub 下载加速](#5-github-下载加速)
6. [Docker 镜像仓库](#6-docker-镜像仓库)
7. [pip / npm / Go / Cargo 镜像](#7-pip--npm--go--cargo-镜像)
8. [验证命令汇总](#8-验证命令汇总)
9. [恢复默认源](#9-恢复默认源)
10. [常见问题](#10-常见问题)

---

## 1. 为什么需要换源

WebKVM 的安装与升级会访问大量境外资源，国内直连常见问题：

| 阶段 | 访问目标 | 典型症状 |
|---|---|---|
| 安装运行时依赖 | 发行版官方软件源（archive.ubuntu.com、deb.debian.org、Fedora metalink 等） | `apt-get update` 卡住/超时、`Could not resolve`、下载速度几十 KB/s。 |
| 获取安装源码 | `github.com` / `codeload.github.com` 源码 tarball | 克隆或 tarball 下载超时、连接重置。 |
| 获取预编译二进制 | `api.github.com` + `github.com/.../releases/download/...` | API 403/超时、release 资产下载中断。 |
| 拉取镜像 | Docker Hub（`registry-1.docker.io`） | `docker pull` 超时、`TLS handshake timeout`。 |
| 开发/构建 | PyPI、npm registry、Go module proxy、crates.io | 安装依赖极慢或失败。 |

解决思路只有三类，可组合使用：

1. **换源**：把系统包管理器与语言包管理器的地址切换到国内镜像站（本文第 2、4、7 节）；
2. **加代理前缀**：给 GitHub 的下载 URL 加一层可用代理（第 3、5 节）；
3. **绕开境外网络**：使用预编译二进制、内网 tarball/对象存储、Docker 离线导入（见 [DEPLOYMENT.md](DEPLOYMENT.md) 4.5 节）。

> 加速地址、公共 Docker 镜像仓库的**可用性会随时间变化**。本文给出配置方法与自检命令，不承诺某个具体地址长期有效；请优先使用你所在云厂商/公司内网提供的镜像服务。

---

## 2. 一键换源脚本 `scripts/cn-mirrors.sh`

仓库提供 `scripts/cn-mirrors.sh`：一键把系统软件源与常见开发工具源切换为中国大陆镜像站，**自动备份、可回滚**。

> 前置说明：**真实写入需要 root 权限**；`--dry-run` 与 `--root=DIR` 允许普通用户执行（用于演练/测试）。脚本只支持 Linux（Debian/Ubuntu、Fedora/RHEL、Arch 家族）。所有改写都先备份到 `/var/backups/webkvm-cn-mirrors/<UTC 时间戳>/`。

### 2.1 用法

```bash
sudo bash scripts/cn-mirrors.sh [options]
```

| 参数 | 取值 | 说明 |
|---|---|---|
| `--mirror=auto\|tuna\|ustc\|aliyun\|tencent\|huawei` | 镜像站 | 默认 `auto`：按连通性探测选择（优先 tuna），全部不可达时回退 tuna。 |
| `--components=LIST` | `os,pip,npm,go,docker,cargo,git` 的逗号组合 | 默认 `os,pip,npm,go,docker`；缺失的工具会自动跳过并提示。 |
| `--docker-mirror=URL` | 可重复 | 写入 `/etc/docker/daemon.json` 的 `registry-mirrors`。 |
| `--github-proxy=URL` | 代理前缀 | 仅 `--components=git` 时有效：写 git `insteadOf` 重写，加速 GitHub 克隆。 |
| `--root=DIR` | 模拟根目录 | 测试用（配合 `--dry-run` 可安全演练）：所有文件路径改为 `DIR + 原路径`，不执行任何系统命令。 |
| `--dry-run` | — | 只打印将执行的操作，不改任何文件、不跑任何命令。 |
| `--restore` | — | 恢复本脚本最近一次备份。 |
| `--yes`, `-y` | — | 兼容参数（脚本本身不提问，安装器调用时会带上它）。 |
| `--help`, `-h` | — | 显示帮助。 |

等价环境变量：`WEBKVM_CN_MIRROR`、`WEBKVM_CN_COMPONENTS`、`WEBKVM_CN_DOCKER_MIRROR`、`WEBKVM_CN_GITHUB_PROXY`、`WEBKVM_CN_ROOT`、`WEBKVM_CN_DRY_RUN=1`。

实现细节（与脚本实际行为一致）：

- **权限**：真实写入需要 root（`sudo`）；`--dry-run` 与 `--root=DIR` 允许普通用户执行，方便演练与测试。
- **镜像站白名单**：`--mirror` 只接受 5 个枚举值，且写入的主机必须在内置允许列表内（防注入任意主机）。
- **`auto` 的选择逻辑**：真实且非演练模式下用 `curl` 按 tuna→ustc→aliyun→tencent→huawei 顺序探测连通性，选择第一个可用者；全部失败时回退 TUNA 并打印警告；`--dry-run`/`--root` 模式不探测，直接取 TUNA。
- **参数校验**：`--mirror`、`--components` 取值非法时以退出码 `2` 拒绝执行；`--docker-mirror` 与 `--github-proxy` 必须是 `https://` 地址、无空白/非法字符；`--root` 必须是已存在的绝对路径，且不允许 `/`。
- **Docker/代理地址策略**：`--docker-mirror` 可重复传入（环境变量用逗号分隔）；`--docker-mirror` 与 `--github-proxy` 由用户显式指定，脚本只做语法校验，未知域名仅**警告**不拒绝（公共镜像/代理地址变化快）。
- **备份结构**：`/var/backups/webkvm-cn-mirrors/<UTC 时间戳>/files/...`（被改写文件的原始副本，保留相对路径）+ `manifest.tsv`（文件清单，供 `--restore` 精确恢复/删除）；`--root=DIR` 时备份落在 `DIR/var/backups/...`。

### 2.2 常用示例

```bash
# 1) 自动选择镜像站，切换默认组件（os,pip,npm,go,docker）
sudo bash scripts/cn-mirrors.sh

# 2) 先演练：只打印将要执行的修改，不动系统
sudo bash scripts/cn-mirrors.sh --dry-run

# 3) 指定镜像站与组件
sudo bash scripts/cn-mirrors.sh --mirror=ustc --components=os,pip,npm

# 4) 同时配置 Docker 镜像仓库（地址以你的云厂商/内网服务为准）
sudo bash scripts/cn-mirrors.sh --components=os,docker \
  --docker-mirror=https://<你的镜像加速地址>

# 5) 脚本化/配置管理调用（--yes 是兼容参数，脚本本身不提问）
sudo bash scripts/cn-mirrors.sh --yes --mirror=aliyun

# 6) 恢复最近一次备份
sudo bash scripts/cn-mirrors.sh --restore
```

仓库还提供了 Makefile 快捷目标（在仓库根目录执行）：

```bash
make cn-mirrors                                  # 默认：auto 镜像 + 默认组件
make cn-mirrors MIRROR=ustc COMPONENTS=os        # 指定镜像站/组件
make cn-mirrors DRYRUN=1                         # 只预览
make cn-mirrors DOCKER_MIRROR=https://<镜像加速地址> GITHUB_PROXY=https://<加速前缀>/
make test-cn-mirrors                             # 离线运行换源脚本测试（无需 root）
```

### 2.3 脚本会改什么（按组件）

| 组件 | 备份并改写 | 说明 |
|---|---|---|
| `os` | `/etc/apt/sources.list`、`/etc/apt/sources.list.d/*.list`、`/etc/apt/sources.list.d/*.sources`（deb822）；`/etc/yum.repos.d/*.repo`（Fedora/EPEL/Rocky/Alma/CentOS Stream）；`/etc/pacman.d/mirrorlist` | 按 `/etc/os-release` 判定 apt/dnf/pacman 家族。**apt 只替换主机名**，保留协议（原本 `http://` 仍是 `http://`，避免 `ca-certificates` 未安装时 https 源不可用）、suite/component/`Signed-By` 等；`ports.ubuntu.com` 保留 `/ubuntu-ports` 路径（arm64）；第三方源（如 `download.docker.com`）不改写。dnf 按已知 repo id 映射 `baseurl` 并注释 `metalink`/`mirrorlist`，未知 repo 整段保持原样并中文警告。 |
| `pip` | `~/.config/pip/pip.conf`（root 运行时即 `/root/.config/pip/pip.conf`） | `index-url` + `trusted-host`；未检测到 pip 时跳过。 |
| `npm` | `~/.npmrc`（root 运行时即 `/root/.npmrc`） | `registry=https://registry.npmmirror.com`；未检测到 npm 时跳过。 |
| `go` | `go env -w GOPROXY=...` | 未安装 Go 时提示跳过；写入前备份 Go 的 env 文件。 |
| `docker` | `/etc/docker/daemon.json` 的 `registry-mirrors` | **仅当显式传入** `--docker-mirror` / `WEBKVM_CN_DOCKER_MIRROR` 时修改；用 JSON 合并保留原有镜像与其它键，合并失败会警告且**不覆盖**原文件；成功后重启 Docker（`--dry-run`/`--root` 不重启）。 |
| `cargo` | `~/.cargo/config.toml` | source replacement（rsproxy 稀疏索引）；未安装 cargo 时跳过。 |
| `git` | `~/.gitconfig`（当前用户级） | 仅 `--components=git` 且提供 `--github-proxy` 时，写入 `github.com` 与 `raw.githubusercontent.com` 两条 `insteadOf` 重写（真实模式先备份 `~/.gitconfig`）；同时打印一次性 URL 用法。 |

脚本特性：

- **幂等**：内容相同则跳过写入且不产生新备份；切换镜像时先备份当前状态再写，可逐层回滚；
- **可演练**：`--dry-run` 不产生任何修改；`--root=DIR` 在假根目录上操作（供仓库测试脚本 `scripts/qa/test-cn-mirrors.sh` 使用，普通用户可跑）；
- **用户级 vs 系统级**：`os`、`docker` 是系统级配置（影响全机/守护进程）；`pip`、`npm`、`go`、`cargo`、`git` 是**执行用户**级配置（`sudo` 下即 root 用户；`--root` 模拟模式固定为 `DIR/root`），重新登录 shell 后生效；
- **不自动刷新包索引**：脚本修改完成后只在结尾打印“下一步建议”（如 `sudo apt-get update`），**不会**自动执行；用安装器启用换源时，安装器随后会自行刷新包索引；
- **RHEL 限制**：RHEL 本体（`rhel`/`ol`）与已 EOL 的 CentOS Linux 7 没有公共镜像源，`os` 组件会警告并以退出码 `1` 结束；安装器侧只告警、继续用原源安装。其余 RedHat 系（Fedora、EPEL、Rocky、AlmaLinux、CentOS Stream）均有映射；
- 结束时打印中文步骤日志（`[cn-mirrors] ...`）与“下一步建议”（刷新软件源、验证 pip/npm/go/docker、`--restore` 回滚）；
- 退出码：`0` 成功、`1` 失败、`2` 用法错误。

### 2.4 执行示例输出（示意）

```text
[cn-mirrors] 检测到发行版：Ubuntu 24.04 LTS（家族：apt，version=24.04，codename=noble）
[cn-mirrors] 镜像站：auto → tuna（连通性探测通过）
[cn-mirrors] 使用镜像站：tuna（mirrors.tuna.tsinghua.edu.cn）
[cn-mirrors] ── 组件：os（系统软件源）──
[cn-mirrors] 已写入：/etc/apt/sources.list.d/ubuntu.sources
[cn-mirrors] ── 组件：pip ──
[cn-mirrors] 已写入：/root/.config/pip/pip.conf
[cn-mirrors] ── 组件：npm ──
[cn-mirrors] 已写入：/root/.npmrc
...
[cn-mirrors] 完成：共调整 5 个文件
[cn-mirrors] 原文件已备份到：/var/backups/webkvm-cn-mirrors/20261031T185510Z（--restore 可恢复）
[cn-mirrors] 下一步建议：
[cn-mirrors]   · 刷新软件源：sudo apt-get update
[cn-mirrors]   · 验证 pip：python3 -m pip config list
[cn-mirrors]   · 用户级配置（pip/npm/go/cargo/git）只对当前用户生效；重新登录 shell 后生效
[cn-mirrors]   · 如需回滚：sudo bash scripts/cn-mirrors.sh --restore
[cn-mirrors] 全部完成。
```

---

## 3. 安装器集成（`--cn-mirrors` / `--github-proxy`）

`packaging/standalone/install.sh` 支持在**安装运行时依赖之前**自动换源；默认**不启用**，不改变原有安装行为。

### 3.1 参数

```bash
sudo bash packaging/standalone/install.sh \
  --cn-mirrors[=auto|tuna|ustc|aliyun|tencent|huawei] \
  --cn-components=os,pip,npm,go,docker \
  --github-proxy=https://<加速前缀>/
```

| 参数 | 等价环境变量 | 说明 |
|---|---|---|
| `--cn-mirrors[=...]` | `WEBKVM_CN_MIRRORS` | 启用换源并指定镜像站（**默认不启用**；省略值 = `auto`）。 |
| `--cn-components=LIST` | `WEBKVM_CN_COMPONENTS` | 传给换源脚本的组件列表。 |
| `--github-proxy=URL` | `WEBKVM_GH_PROXY` | 为 `github.com` / `raw.githubusercontent.com` 的**下载**加代理前缀（release tarball、更新脚本等）。 |

行为说明（与安装器实际实现一致）：

- 启用后，安装器在**刷新包索引/安装运行时依赖之前**调用 `scripts/cn-mirrors.sh`；
- 安装器自身 `--dry-run` 时，会以 `--dry-run` 方式调用换源脚本，**只预览不修改**；
- 若仓库中缺少换源脚本，安装器**告警但不中断**安装；换源脚本执行失败（退出码非 0）时同样只告警，并继续使用原有软件源；
- `--cn-mirrors` 不带值时等价 `auto`；`--cn-components` 取值必须在 `os,pip,npm,go,docker,cargo,git` 范围内；`--github-proxy` 必须是 `https://` 地址；
- `--github-proxy` 会把 `https://github.com/...` 与 `https://raw.githubusercontent.com/...` 的**下载** URL 加上代理前缀（release tarball、CLI、更新脚本等），并同时透传给换源脚本的 git 组件（`--components` 含 `git` 时才写 git 配置）；
- **注意**：`https://api.github.com`（查询最新 release 的 API）**不经过**代理前缀。若该 API 在国内不可达，请改用 `WEBKVM_BINARY_URL` + `WEBKVM_BINARY_SHA256` 直接指定二进制，或把 `WEBKVM_UPDATE_REF` 设为已知 release tag 以跳过 API 查询；
- `--github-proxy` 只改变下载地址、不改变校验逻辑：二进制仍必须通过 SHA-256 校验（安装器强制）。

### 3.2 示例

```bash
# 完整安装 + 自动换源 + GitHub 加速
sudo bash packaging/standalone/install.sh \
  --cn-mirrors=auto \
  --cn-components=os,pip,npm,go,docker \
  --github-proxy=https://<加速前缀>/ \
  --yes

# 先看安装器 + 换源会做什么（不改系统）
sudo bash packaging/standalone/install.sh --dry-run --cn-mirrors=auto
```

### 3.3 一键脚本的透传

`scripts/install-webkvm.sh` 会把下列环境变量透传给独立安装器，并可加速仓库源码 tarball / git clone：

| 环境变量 | 用途 |
|---|---|
| `WEBKVM_CN_MIRRORS` | 等价 `--cn-mirrors`。 |
| `WEBKVM_CN_COMPONENTS` | 等价 `--cn-components`。 |
| `WEBKVM_GH_PROXY` | GitHub 下载/克隆加速前缀。 |
| `WEBKVM_INSTALL_TARBALL_URL` | 直接指定源码 tarball 地址（**http(s) 直链或本地文件路径**；内网镜像/离线分发，优先于 git 流程）。 |
| `WEBKVM_INSTALL_REPO` / `WEBKVM_INSTALL_BRANCH` | 仓库地址 / 分支（内网 Git 镜像）。 |

```bash
# 下载后执行（推荐，便于先审查脚本）
curl -fsSL https://raw.githubusercontent.com/Slaker19/webkvm/main/scripts/install-webkvm.sh -o /tmp/webkvm-install.sh
sudo WEBKVM_CN_MIRRORS=auto \
     WEBKVM_CN_COMPONENTS=os,pip,npm,go,docker \
     WEBKVM_GH_PROXY=https://<加速前缀>/ \
     bash /tmp/webkvm-install.sh
```

> 若一键脚本因网络无法下载，可先通过浏览器/下载工具把 `install-webkvm.sh` 与 WebKVM 源码 tarball 传到服务器，再用 `WEBKVM_INSTALL_TARBALL_URL` 指向内网地址或**本地 tarball 文件路径**安装：
>
> ```bash
> sudo WEBKVM_INSTALL_TARBALL_URL=/root/webkvm-main.tar.gz bash /tmp/webkvm-install.sh
> ```

---

## 4. 手动换源（不使用脚本）

如果希望完全掌控改动，可按下述方式手动配置。**每条命令执行前先备份原文件**（示例已包含 `cp`）。

### 4.1 Ubuntu（24.04+ deb822 格式）

```bash
# 备份
sudo cp -a /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak 2>/dev/null || true

# Ubuntu 24.04（noble）；其它版本把 noble 换成你的 VERSION_CODENAME
. /etc/os-release && echo "当前代号: ${VERSION_CODENAME}"

sudo tee /etc/apt/sources.list.d/ubuntu.sources >/dev/null <<'EOF'
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/ubuntu/
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/ubuntu/
Suites: noble-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF

sudo apt-get update
```

### 4.2 Debian（`/etc/apt/sources.list` 传统格式）

```bash
sudo cp -a /etc/apt/sources.list /etc/apt/sources.list.bak

# Debian 12/13（bookworm/trixie）；security 使用独立的 debian-security 源
sudo tee /etc/apt/sources.list >/dev/null <<'EOF'
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security bookworm-security main contrib non-free non-free-firmware
EOF

sudo apt-get update
```

> Debian 13（trixie）起默认使用 deb822 的 `/etc/apt/sources.list.d/debian.sources`：把其中 `URIs:` 行改为镜像地址即可，不要混用两种格式重复配置同一个 suite。

### 4.3 Fedora / RHEL 系（dnf/yum）

```bash
# 备份
sudo cp -a /etc/yum.repos.d /etc/yum.repos.d.bak

# 查看当前 repo 与 metalink 配置
grep -rE '^(metalink|mirrorlist|baseurl)=' /etc/yum.repos.d/*.repo | head -20

# 示例：把 Fedora 官方源改为清华镜像（注释 metalink，改 baseurl）
# 说明：不同 Fedora 版本的 repo 文件内容/命名略有差异；若模式不匹配，请手工编辑 baseurl。
sudo sed -i -E \
  -e 's|^metalink=|#metalink=|' \
  -e 's|^#?baseurl=https?://download\.example/pub/fedora/linux|baseurl=https://mirrors.tuna.tsinghua.edu.cn/fedora|' \
  /etc/yum.repos.d/*.repo

sudo dnf makecache
```

> RHEL / AlmaLinux / Rocky 请使用对应发行版的镜像路径（如 `<mirror>/almalinux/$releasever/...`、`<mirror>/rocky/$releasever/...`），并在 `baseurl` 中保留 `$releasever` / `$basearch` 变量。最省事的做法是让第 2 节的脚本按其 repo id 映射自动处理（Fedora/EPEL/Rocky/AlmaLinux/CentOS Stream 均已支持）。

### 4.4 Arch Linux（pacman）

```bash
sudo cp -a /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak

# 在文件顶部插入镜像 Server（越靠前优先级越高）
sudo sed -i '1i Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/$arch' /etc/pacman.d/mirrorlist

# 强制刷新（-yy）并更新 keyring
sudo pacman -Syy
sudo pacman -Sy --noconfirm archlinux-keyring
```

> 老 ISO 安装的 Arch 常因 keyring 过期导致签名错误，先更新 `archlinux-keyring` 再装包。

---

## 5. GitHub 下载加速

WebKVM 安装/升级涉及三类 GitHub 下载资源（另有 release API 查询）。加速方式都是“在原始 URL 前加代理前缀”，代理服务由你自行选择（云厂商、公司网关或公共加速服务）。

### 5.1 源码 tarball（一键脚本）

```text
原始：https://github.com/Slaker19/webkvm/archive/refs/heads/main.tar.gz
加速：https://<加速前缀>/https://github.com/Slaker19/webkvm/archive/refs/heads/main.tar.gz
```

一键脚本可通过 `WEBKVM_INSTALL_TARBALL_URL` 直接指定下载地址（可以是加速地址、内网对象存储地址，或**本地文件路径**）：

```bash
# 内网/加速地址
sudo WEBKVM_INSTALL_TARBALL_URL=https://<你的地址>/main.tar.gz bash /tmp/webkvm-install.sh
# 本地 tarball（离线介质）
sudo WEBKVM_INSTALL_TARBALL_URL=/root/webkvm-main.tar.gz bash /tmp/webkvm-install.sh
```

> 设置 `WEBKVM_GH_PROXY` 时，一键脚本会自动给 GitHub 的 clone / fetch / tarball 下载加代理前缀（`WEBKVM_INSTALL_TARBALL_URL` 是 github.com 地址时同样生效），并在克隆后把 git `origin` 还原为规范 URL，保证之后脱代理 `git pull` 仍可用。

### 5.2 git 克隆

```bash
# 方式一：给克隆 URL 加前缀
git clone --depth 1 https://<加速前缀>/https://github.com/Slaker19/webkvm.git

# 方式二：配置全局 URL 重写（对后续所有 github.com 克隆生效）
git config --global url."https://<加速前缀>/https://github.com/".insteadOf "https://github.com/"
git config --global url."https://<加速前缀>/https://raw.githubusercontent.com/".insteadOf "https://raw.githubusercontent.com/"

# 验证重写规则
git config --global --get-regexp 'url\.'

# 取消重写
git config --global --unset-all url."https://<加速前缀>/https://github.com/".insteadOf
git config --global --unset-all url."https://<加速前缀>/https://raw.githubusercontent.com/".insteadOf
```

> `scripts/cn-mirrors.sh --components=git --github-proxy=<前缀>` 会自动写入上述两条 `insteadOf` 规则（`--github-proxy` 必须是 `https://` 地址，且脚本会提示未知代理主机需自行确认可靠性）；安装器的 `--github-proxy` 则只作用于下载（release tarball / 更新脚本），两者用途不同。

### 5.3 release 资产（预编译二进制）

```text
原始：https://github.com/Slaker19/webkvm/releases/download/<tag>/webkvm-<version>-linux_amd64
校验：https://github.com/Slaker19/webkvm/releases/download/<tag>/SHA256SUMS
```

下载后**必须**校验：

```bash
sha256sum -c SHA256SUMS --ignore-missing
# 或手动比对
sha256sum webkvm-<version>-linux_amd64
```

然后用本地二进制安装，避免安装器再次走 GitHub：

```bash
sudo WEBKVM_BINARY=/path/to/webkvm-<version>-linux_amd64 \
     WEBKVM_NONINTERACTIVE=1 \
     bash packaging/standalone/install.sh
```

或用 `WEBKVM_BINARY_URL` + `WEBKVM_BINARY_SHA256`（**必须是 HTTPS**，校验和 64 位十六进制）：

```bash
sudo WEBKVM_BINARY_URL=https://<你的对象存储>/webkvm-<version>-linux_amd64 \
     WEBKVM_BINARY_SHA256=<sha256> \
     WEBKVM_NONINTERACTIVE=1 \
     bash packaging/standalone/install.sh
```

> 安全提醒：加速代理只能解决“下载慢”，不能证明文件可信。安装器对 release/large 资产强制 SHA-256 校验；**不要**跳过校验直接以 root 运行来路不明的二进制。

---

## 6. Docker 镜像仓库

Docker 模式（`docker compose up -d`）需要从 Docker Hub 拉取 `slaker1908/webkvm:latest`，国内常超时。配置镜像加速有三种思路：

1. **使用云厂商/公司提供的镜像加速地址**（以云厂商控制台当前文档为准）；
2. **自建 registry mirror**（Harbor / Nexus / registry:2 的 pull-through cache），内网最稳定；
3. **离线导入镜像**（见 [DEPLOYMENT.md](DEPLOYMENT.md) 4.5 节）。

### 6.1 配置 `registry-mirrors`

```bash
# 备份（若已有配置）
sudo cp -a /etc/docker/daemon.json /etc/docker/daemon.json.bak 2>/dev/null || true

# 写入镜像加速地址（替换 <你的镜像加速地址>；可写多个）
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "registry-mirrors": ["https://<你的镜像加速地址>"]
}
EOF

# 校验 JSON 合法性后再重启（JSON 写错会导致 Docker 起不来）
python3 -m json.tool /etc/docker/daemon.json

sudo systemctl daemon-reload
sudo systemctl restart docker
```

> 若本机已有 `daemon.json`（例如 WebKVM 换源脚本已写入 `registry-mirrors`），应**合并**而不是覆盖：保留原有 `data-root`、`log-driver`、`insecure-registries` 等键。不确定时用 `jq` 合并或交给 `scripts/cn-mirrors.sh --docker-mirror=...` 处理。

### 6.2 自检

```bash
# 查看生效的镜像仓库
docker info --format '{{json .RegistryConfig.Mirrors}}'

# 实际拉取一个公开镜像验证
docker pull hello-world

# 拉取 WebKVM 镜像
docker pull slaker1908/webkvm:latest
```

- `hello-world` 拉取失败说明镜像仓库配置未生效或地址不可用，换一个地址重试；
- 也可以覆盖默认镜像名（自建镜像/私有仓库）：

```bash
WEBKVM_DOCKER_IMAGE=<你的仓库>/webkvm:<tag> docker compose up -d
```

### 6.3 注意事项

- 公共加速地址**经常变更/限流**，本文不写死任何地址；请以你云厂商控制台或公司内网服务为准；
- 镜像仓库只加速 **Docker 镜像拉取**，不影响 `apt`/GitHub/语言包管理器（那些需要第 2、4、7 节）；
- 镜像加速地址属于信任链的一部分：只使用可信来源，避免被替换成恶意镜像；
- 拉取失败但 `docker info` 已显示 mirror 时，可用 `docker pull <mirror-host>/library/hello-world` 形式直接验证该 mirror 是否可达。

---

## 7. pip / npm / Go / Cargo 镜像

> `scripts/cn-mirrors.sh --components=pip,npm,go,cargo` 可自动完成以下配置；本节给出等价的“手动版”，便于排查。

### 7.1 pip（PyPI）

```bash
# 方式一：pip 自带命令
python3 -m pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
python3 -m pip config set global.trusted-host pypi.tuna.tsinghua.edu.cn

# 方式二：写配置文件（root 用户；脚本使用同一位置）
mkdir -p /root/.config/pip
cat > /root/.config/pip/pip.conf <<'EOF'
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn
EOF

# 验证
python3 -m pip config list
```

### 7.2 npm

```bash
npm config set registry https://registry.npmmirror.com --location=user
npm config get registry
# 预期：https://registry.npmmirror.com/

# 脚本等价写法：/root/.npmrc 中写入 registry=...
```

### 7.3 Go（Go module proxy）

```bash
go env -w GOPROXY=https://goproxy.cn,direct
go env GOPROXY
# 预期：https://goproxy.cn,direct

# 取消
go env -u GOPROXY
```

### 7.4 Cargo（crates.io）

```bash
mkdir -p ~/.cargo
cat > ~/.cargo/config.toml <<'EOF'
[source.crates-io]
replace-with = "rsproxy-sparse"

[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"

[net]
git-fetch-with-cli = true
EOF

cargo --version   # 确认 cargo 已安装（未安装则跳过该组件）
```

> 与 `scripts/cn-mirrors.sh --components=cargo` 写入的内容一致（rsproxy 稀疏索引）。

---

## 8. 验证命令汇总

```bash
# 发行版与代号（换源前确认版本）
cat /etc/os-release

# 系统包管理器
sudo apt-get update                      # Debian/Ubuntu
sudo dnf makecache                       # Fedora/RHEL
sudo pacman -Sy                          # Arch

# Python / Node / Go
python3 -m pip config list
npm config get registry
go env GOPROXY

# Docker 镜像仓库
docker info --format '{{json .RegistryConfig.Mirrors}}'
docker pull hello-world

# git URL 重写（若配置了 GitHub 加速）
git config --global --get-regexp 'url\.'

# 安装器/换源脚本是否真的执行过
sudo grep -h '\[cn-mirrors\]' /var/log/webkvm-install.log 2>/dev/null | tail -20

# 换源脚本自带测试（离线；仓库根目录执行，无需 root）
make test-cn-mirrors
# 或
bash scripts/qa/test-cn-mirrors.sh
```

---

## 9. 恢复默认源

### 9.1 用脚本恢复（推荐）

```bash
sudo bash scripts/cn-mirrors.sh --restore
```

备份目录位于 `/var/backups/webkvm-cn-mirrors/<UTC 时间戳>/`：被改写文件的原始副本保存在其 `files/` 子目录（保留相对路径），`manifest.tsv` 记录“逻辑路径 / 原本是否存在 / 备份内相对路径”。`--restore` 会恢复最近一次备份，并删除**本脚本新建**的文件（原本不存在的文件）：

```bash
# 查看备份
sudo ls -la /var/backups/webkvm-cn-mirrors/
sudo cat /var/backups/webkvm-cn-mirrors/<时间戳>/manifest.tsv

# 用脚本恢复最近一次
sudo bash scripts/cn-mirrors.sh --restore

# 或手工按清单恢复
sudo cp -a /var/backups/webkvm-cn-mirrors/<时间戳>/files/etc/apt/sources.list /etc/apt/sources.list
```

### 9.2 手动恢复

| 组件 | 恢复方法 |
|---|---|
| apt | 用你自己的备份覆盖 `/etc/apt/sources.list` / `/etc/apt/sources.list.d/*.sources`，然后 `sudo apt-get update`。 |
| dnf | `sudo rm -rf /etc/yum.repos.d && sudo cp -a /etc/yum.repos.d.bak /etc/yum.repos.d`，然后 `sudo dnf makecache`。 |
| pacman | `sudo cp -a /etc/pacman.d/mirrorlist.bak /etc/pacman.d/mirrorlist`。 |
| pip | 删除 `/root/.config/pip/pip.conf`，或 `python3 -m pip config unset global.index-url`。 |
| npm | `npm config delete registry`（删除 `/root/.npmrc` 中的 `registry` 行）。 |
| go | `go env -u GOPROXY`。 |
| cargo | 还原 `~/.cargo/config.toml`（删除 source replacement 段）。 |
| git | `git config --global --unset-all url."https://<前缀>/https://github.com/".insteadOf`。 |
| docker | 从 `/etc/docker/daemon.json.bak` 还原或删除 `registry-mirrors` 键，`sudo systemctl restart docker`。 |

---

## 10. 常见问题

### 10.1 `apt-get update` 报 GPG / `NO_PUBKEY` 错误

**原因**：镜像同步延迟、系统缺少对应的 keyring 包，或镜像站未同步签名密钥。

```bash
# Debian/Ubuntu：安装/更新 keyring
sudo apt-get install -y debian-archive-keyring ubuntu-keyring 2>/dev/null || true

# 查看缺失的 key
sudo apt-get update 2>&1 | grep -E 'NO_PUBKEY|EXPKEYSIG'

# Arch：老 ISO 的 keyring 过期，先更新 keyring
sudo pacman -Sy --noconfirm archlinux-keyring
```

若仍失败：换一个镜像站（`--mirror=aliyun` 等），或暂时恢复官方源验证。

### 10.2 镜像站同步延迟（找不到最新包 / 包版本落后）

国内镜像通常每几分钟到几小时同步一次。表现为 `E: Unable to locate package ...` 或版本号比官方旧。

- 换一个更新时间更快的镜像站（tuna/ustc/aliyun/tencent/huawei 各有差异）；
- 等待同步后重试；
- 关键场景直接使用官方源（可能很慢）或内网自建镜像。

### 10.3 签名错误 / “Release file is not valid yet” / 证书错误

- **系统时间不准**：`timedatectl status`，开启 NTP（`sudo timedatectl set-ntp true`）后重试；
- **换错了发行版代号**：确认 `/etc/os-release` 的 `VERSION_CODENAME` 与 sources 中的 suite 一致；
- **HTTPS 证书链问题**：安装 `ca-certificates`；公司网络做了 TLS 拦截时需导入公司根证书；
- **临时跳过有效期检查**（仅排障用，不建议长期）：`sudo apt-get -o Acquire::Check-Valid-Until=false update`。

### 10.4 公司代理 / 内网出口

换源脚本不会自动配置 HTTP 代理；公司网络需要手动设置：

```bash
# 临时（当前 shell）
export http_proxy=http://proxy.company.local:8080
export https_proxy=http://proxy.company.local:8080
export no_proxy=127.0.0.1,localhost,内网网段

# apt 持久化
sudo tee /etc/apt/apt.conf.d/99proxy >/dev/null <<'EOF'
Acquire::http::Proxy "http://proxy.company.local:8080";
Acquire::https::Proxy "http://proxy.company.local:8080";
EOF

# dnf 持久化
echo 'proxy=http://proxy.company.local:8080' | sudo tee -a /etc/dnf/dnf.conf

# Docker 守护进程代理
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf >/dev/null <<'EOF'
[Service]
Environment="HTTP_PROXY=http://proxy.company.local:8080"
Environment="HTTPS_PROXY=http://proxy.company.local:8080"
Environment="NO_PROXY=127.0.0.1,localhost"
EOF
sudo systemctl daemon-reload && sudo systemctl restart docker
```

> 代理场景下，GitHub 加速前缀可能不可用；优先走公司统一的出口/镜像服务。

### 10.5 修改 `daemon.json` 后 Docker 起不来

JSON 格式错误会导致 `dockerd` 启动失败：

```bash
python3 -m json.tool /etc/docker/daemon.json   # 先校验
sudo systemctl status docker --no-pager
sudo journalctl -u docker -n 50 --no-pager
# 恢复备份
sudo cp -a /etc/docker/daemon.json.bak /etc/docker/daemon.json 2>/dev/null || sudo rm -f /etc/docker/daemon.json
sudo systemctl restart docker
```

### 10.6 启用换源后安装仍超时

- 确认换源真的执行：查看安装输出/日志中的 `[cn-mirrors] ...` 行；
- 先手动 `sudo apt-get update`（或 `dnf makecache` / `pacman -Sy`）验证源可用；
- 安装器自带包操作重试，可调大重试：`WEBKVM_PKG_RETRIES=5 WEBKVM_PKG_RETRY_DELAY=8`；
- GitHub 下载仍慢是另一条链路：用 `--github-proxy` / `WEBKVM_GH_PROXY`，或改用 `WEBKVM_BINARY` 本地安装；
- Docker 慢是第三条链路：见第 6 节。

### 10.7 `--dry-run` 和 `--root` 有什么区别？

- `--dry-run`：**在真实系统上只打印**将执行的操作，不写文件、不跑命令（可用于生产机预演，普通用户即可执行）；
- `--root=DIR`：把文件路径映射到假根目录（测试用），不调用真实包管理器，也不会操作真实 `/etc`、`/var`；模拟的 root 用户主目录固定为 `DIR/root`。仓库测试（`scripts/qa/test-cn-mirrors.sh`，91 项断言）即使用该模式，macOS 上也能跑。
- `--root=/` 会被拒绝（退出码 2），避免把“模拟模式”误当真实系统；`--root` 必须是已存在的绝对路径。

### 10.8 换源会影响正在运行的 WebKVM 吗？

不会。换源只改写**软件包管理器/开发工具**的配置文件，不触碰 WebKVM 的数据（`/opt/webkvm`）、systemd 单元或正在运行的虚拟机。唯一需要注意的是 Docker：修改 `daemon.json` 后会重启 Docker 服务，正在运行的**容器**会重启（WebKVM 容器部署请安排在维护窗口）。

### 10.9 为什么换源后 apt 源还是 `http://`，没有变成 `https://`？

这是脚本的刻意设计：`apt` 源**保留原协议**，只替换主机名。安装器是在换完源之后才安装 `ca-certificates` 等 runtime 依赖的，若此时把 `http://` 强制改成 `https://`，在缺少证书包/根证书的早期系统上会导致 `apt-get update` 失败。apt 本身依赖 GPG 签名校验；原本使用 `https://` 的源会保持 `https://`。需要 https 时可自行安装证书后再手动改源。

### 10.10 脚本会自动刷新软件源缓存吗？

不会。脚本只改写配置文件，结束时打印“下一步建议”（如 `sudo apt-get update` / `sudo dnf makecache` / `sudo pacman -Sy`），需要你手动执行（或由安装器在换源后自行刷新）。`--dry-run` / `--root` 也不会联网。

### 10.11 RHEL 本体 / CentOS Linux 7 换源失败怎么办？

RHEL 本体（`rhel`/`ol`）与已 EOL 的 CentOS Linux 7 没有公共镜像源，`os` 组件会警告并以退出码 `1` 结束（不写坏原配置）；通过安装器启用换源时只会告警并继续使用原源。可选方案：

- 配置红帽订阅源（`subscription-manager`）或公司内部 RHEL 镜像；
- 换用 Rocky Linux / AlmaLinux（脚本完整支持其 repo 映射）；
- 只想加速 GitHub/二进制下载时，只启用 `--components=pip,npm,go,docker` 等非 `os` 组件，或用 `WEBKVM_BINARY` 本地安装。

---

## 附：与 WebKVM 安装流程的对应关系

```text
             ┌─────────────────────────────────────────────┐
             │ 第 2/4 节：换系统源（apt/dnf/pacman）        │
             └──────────────────┬──────────────────────────┘
                                ▼
 安装器 → 刷新包索引 → 安装 libvirt/QEMU 等运行时依赖
                                ▼
             ┌─────────────────────────────────────────────┐
             │ 第 5 节：获取 WebKVM 二进制（GitHub 加速）   │
             │  或 WEBKVM_BINARY / WEBKVM_BINARY_URL+SHA256 │
             └──────────────────┬──────────────────────────┘
                                ▼
 部署 systemd 服务 → 健康检查 → 首次登录
                                ▼
             ┌─────────────────────────────────────────────┐
             │ 第 6/7 节：Docker 镜像与语言包镜像（按需）   │
             └─────────────────────────────────────────────┘
```

更多安装细节（交互选项、TLS、网络模式、首次登录、升级回滚、故障排查）见 [完整中文部署说明](DEPLOYMENT.md)。
