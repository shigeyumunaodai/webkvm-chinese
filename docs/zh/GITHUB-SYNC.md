# 上传到 GitHub 与自动同步上游更新

> 本文说明如何把本仓库（WebKVM 简体中文版）上传到 GitHub，并让它**每天自动合并上游
> [`Slaker19/webkvm`](https://github.com/Slaker19/webkvm) 的新更新，同时保留汉化**。
>
> 相关：[完整中文部署说明](DEPLOYMENT.md) · [国内网络优化](CHINA-NETWORK.md) · [中文文档索引](README.md)

---

## 1. 原理：Fork 历史 + 自动合并 + 冲突自动处理

本地的 Git 仓库已经带上游完整历史：当前分支 `main` 的父提交就是上游
`Slaker19/webkvm@0468d9c`（v0.1.9），汉化作为独立提交叠在其上。因此 GitHub 上的
仓库与上游有共同祖先，可以正常 merge。

上传后，仓库自带的两个 GitHub Actions 工作流负责后续维护：

| 工作流 | 文件 | 作用 |
|---|---|---|
| **Sync upstream** | `.github/workflows/sync-upstream.yml` | 每 6 小时（也可手动触发）拉取上游 `main` 并合并；能自动处理的冲突自动处理，处理不了的自动开 Issue 通知你 |
| **Build localized release** | `.github/workflows/build-zh-release.yml` | 每次 `main` 更新后自动构建内嵌汉化前端的 Linux 二进制（artifact）；推送 `v*-zh*` tag 时自动创建 GitHub Release |

自动合并时的处理规则：

| 文件/场景 | 行为 |
|---|---|
| `docs/zh/**`、`README.zh.md`、`scripts/cn-mirrors.sh`、`scripts/qa/test-cn-mirrors.sh`、`scripts/sync/**` | 标记为 `merge=ours`：**保留汉化版** |
| `README*.md`、`docs/**/*.md`、`SECURITY*.md` 的语言导航行 | 取上游版本后自动重新插入「简体中文」链接 |
| `CHANGELOG.md` / `CHANGELOG.es.md` | 取上游版本后自动重新插入汉化 `[Unreleased]` 段落与「四种语言」说明 |
| `AGENTS.md` | 取上游版本后自动追加「本地化 fork」章节 |
| `.env.example` 的国内网络变量、`ci.yml` 的 zh 校验步骤、`release.yml` 的换源脚本打包行 | 自动重新应用 |
| 上游新增的 i18n 英文键 | `scripts/sync/fill-missing-zh.py` 自动补入中文字典（**暂时填英文**保证界面不会出现裸 key），并生成「翻译待办」Issue |
| 前端源码 / 安装器 / Makefile 等**代码冲突** | 无法安全自动合并 → 工作流中止合并（不会破坏仓库），并创建「上游同步冲突」Issue，列出文件与本地处理命令 |
| 冲突/待办已解决 | 下一次同步成功时，对应 Issue 会自动关闭（冲突 Issue 需先手动 push 解决；翻译待办清空后自动关闭） |
| 上游新增文档 | 没有 `docs/zh/` 对应译文时，出现在「翻译待办」Issue 中 |

> 这样能保证：上游的**普通更新会自动同步**；汉化永不丢失；上游改到汉化改过的代码时，
> 不会盲目覆盖，而是明确提醒你处理一次。日常维护几乎不需要人工。

---

## 2. 首次上传（三步）

### 第 1 步：在 GitHub 创建空仓库

在 GitHub 网页创建 **空仓库**（不要勾选初始化 README / .gitignore / License），例如：

```text
用户名/webkvm-zh      （私有或公开均可）
```

> 如果本机无法直接打开 GitHub，可让能访问 GitHub 的设备/浏览器完成创建，或用手机。

### 第 2 步：连接并推送（三选一）

#### 方式 A：当前网络能访问 GitHub（VPN / 公司网络 / 海外机器）

```bash
cd /Users/mu/Downloads/webkvm-main

git remote add origin git@github.com:<用户名>/webkvm-zh.git
git push -u origin main
```

如果用 HTTPS：

```bash
git remote add origin https://github.com/<用户名>/webkvm-zh.git
git push -u origin main     # 用户名 + Personal Access Token（不要用登录密码）
```

#### 方式 B：直连 GitHub 不通，但 SSH 443 可用（本机现状）

本机实测 `ssh.github.com:443` **可连通**，只是还没有你的 GitHub 密钥。步骤：

```bash
# 1) 生成专用密钥（回车使用默认路径；如已有 GitHub 密钥可跳过）
ssh-keygen -t ed25519 -f ~/.ssh/github_webkvm_zh -C "webkvm-zh" -N ""

# 2) 复制公钥
cat ~/.ssh/github_webkvm_zh.pub
```

把输出的公钥添加到 GitHub：**Settings → SSH and GPG keys → New SSH key**。

```bash
# 3) 让 github.com 走 443 端口（~/.ssh/config 追加）
cat >> ~/.ssh/config <<'EOF'

Host github.com
  HostName ssh.github.com
  Port 443
  User git
  IdentityFile ~/.ssh/github_webkvm_zh
  IdentitiesOnly yes
EOF

# 4) 验证并推送
ssh -T git@github.com        # 应看到 "Hi <用户名>! You've successfully authenticated"
cd /Users/mu/Downloads/webkvm-main
git remote add origin git@github.com:<用户名>/webkvm-zh.git
git push -u origin main
```

#### 方式 C：完全离线转移（bundle）

```bash
cd /Users/mu/Downloads/webkvm-main
git bundle create /tmp/webkvm-zh.bundle --all
```

把 `/tmp/webkvm-zh.bundle` 拷到一台能访问 GitHub 的机器：

```bash
git clone /tmp/webkvm-zh.bundle webkvm-zh
cd webkvm-zh
git remote set-url origin git@github.com:<用户名>/webkvm-zh.git
git push -u origin main
```

> 只推 `main` 即可；不需要推上游的全部 tag（`git push --tags` 会把这些 tag 也带过去，
> 一般没必要）。

### 第 3 步：打开 Actions 写权限（必须）

GitHub 仓库 → **Settings → Actions → General → Workflow permissions**：

- 选择 **Read and write permissions**（Sync upstream 需要 push + 创建 Issue）
- 保存

然后在 **Actions** 标签页确认 `Sync upstream`、`Build localized release` 两个
workflow 已启用。可以手动点一次 **Sync upstream → Run workflow**，选择 `dry_run`
先试运行。

---

## 3. 日常维护

### 3.1 自动同步节奏

`Sync upstream` 默认每 6 小时运行一次（UTC `17 */6 * * *`）。可在
`.github/workflows/sync-upstream.yml` 中修改 cron，或到 Actions 页面手动触发。

同步成功后，`main` 会自动增加一个 `chore(sync): merge upstream ...` 提交，
并触发 `Build localized release` 重新构建二进制。

### 3.2 两种 Issue

| Issue 标题 | 含义 | 你要做什么 |
|---|---|---|
| **翻译待办：上游同步带来的新键与新文档** | 上游新增了 i18n 键或文档，字典中暂时用英文占位 | 按 Issue 里的 key 列表翻译 `messages.zh`；新文档补 `docs/zh/` 译文。完成后提交，下次同步会自动刷新 Issue |
| **上游同步冲突：需要手动解决** | 上游改到了汉化改过的代码（前端组件、安装器等），无法安全自动合并 | 在本地按 Issue 里的命令合并并解决冲突，然后 push；之后同步恢复自动 |

翻译新键的最小流程：

```bash
cd /Users/mu/Downloads/webkvm-main
# 本地先合并一次上游（国内用 GitHub 代理拉取）
UPSTREAM_FETCH_URL=https://gh-proxy.com/https://github.com/Slaker19/webkvm.git \
  bash scripts/sync/sync-upstream.sh

# 自动补齐缺失的 zh 键（英文占位）并生成待办清单
REPORT_DIR=/tmp python3 scripts/sync/fill-missing-zh.py
cat /tmp/translation-backlog.md

# 修改 frontend/src/lib/i18n.svelte.js 里的 messages.zh 译文，然后校验
bash scripts/check-i18n.sh
cd frontend && npx prettier --write src/lib/i18n.svelte.js && cd ..
git add -A && git commit -m "i18n(zh): translate upstream keys" && git push
```

### 3.3 手动解决同步冲突

Issue 中会给出冲突文件列表。处理方式：

```bash
cd /Users/mu/Downloads/webkvm-main
git checkout main && git pull

# 先让脚本自动合并（国内拉取用代理 URL）
UPSTREAM_FETCH_URL=https://gh-proxy.com/https://github.com/Slaker19/webkvm.git \
  bash scripts/sync/sync-upstream.sh
# 若退出码为 2，说明还有以下文件需要手动解决：
#   sync-unresolved.txt 中列出的文件

# 逐个编辑解决冲突（保留汉化语义 + 上游新逻辑），然后：
git add -A
git commit --no-edit
git push origin main
```

再次运行同步时，相同冲突的解决方式可以通过 Git rerere 复用（可选：

```bash
git config rerere.enabled true
```

）。

### 3.4 自动发布与服务器升级

`Build localized release` 在 tag 名形如 `v0.1.9-zh`、`v0.2.0-zh.1`、`zh-v1` 时会创建
Release。国内下载可用 GitHub 代理前缀（只读加速）：

```bash
# 在发布页找到实际文件链接后（示例）
curl -fL -o webkvm-zh.tar.gz \
  "https://gh-proxy.com/https://github.com/<用户名>/webkvm-zh/releases/download/v0.1.9-zh/webkvm-0.1.9-zh-linux_amd64.tar.gz"
sha256sum -c SHA256SUMS        # 先下载 SHA256SUMS
tar xzf webkvm-zh.tar.gz && cd webkvm-*

sudo WEBKVM_BINARY=backend/webkvm bash packaging/standalone/install.sh \
  --yes --https=yes --bind=0.0.0.0
```

也可以直接在服务器上用安装器的 GitHub 代理参数/变量：

```bash
sudo WEBKVM_GH_PROXY=https://ghfast.top/ \
     WEBKVM_BINARY_URL=https://github.com/<用户名>/webkvm-zh/releases/download/.../webkvm-... \
     bash packaging/standalone/install.sh --yes
```

> ⚠️ **自更新注意**：当前二进制内置的「界面自更新」指向**上游官方仓库**，点击后会安装
> 上游英文版并覆盖汉化版。已经在运行的汉化服务器请保持
> `WEBKVM_ALLOW_UPDATE=0`（可用 systemd drop-in：
> `/etc/systemd/system/webkvm.service.d/zh-localization.conf`）。升级请使用上面的
> Release 包手动安装。

---

## 4. 修改同步配置

| 想改什么 | 改哪里 |
|---|---|
| 上游仓库 / 分支 | `.github/workflows/sync-upstream.yml` 的 `UPSTREAM_URL` / `UPSTREAM_BRANCH`；本地同步可用环境变量覆盖 |
| 同步频率 | 同一文件的 `on.schedule.cron` |
| 某个文件永远保留汉化版 | `.gitattributes` 增加 `<path> merge=ours` |
| 某个文档冲突时自动重放 | `scripts/sync/resolve-conflicts.py` 增加规则 |
| 自动填充新键的中文占位策略 | `scripts/sync/fill-missing-zh.py` |

---

## 5. 常见问题

**Q：为什么本机 `git fetch upstream` 超时？**
A：中国大陆直连 GitHub 常被阻断。工作流运行在 GitHub 云端，不需要代理；本机拉取时
使用代理 URL 即可，例如：

```bash
git remote set-url upstream https://gh-proxy.com/https://github.com/Slaker19/webkvm.git
# 或临时覆盖：
UPSTREAM_FETCH_URL=https://gh-proxy.com/https://github.com/Slaker19/webkvm.git \
  bash scripts/sync/sync-upstream.sh
```

**Q：为什么默认的 GitHub 代理地址写的是 `gh-proxy.com`？**
A：这是本项目实测可用的只读加速前缀（`https://gh-proxy.com/https://github.com/...`）。
这类公共服务可用性会变化，失效时换一个即可（把前缀换成新的代理地址）。

**Q：Sync 工作流每天改动 main，会让历史很乱吗？**
A：每次同步只产生一个 merge commit（或没有变化），上游更新本身保留原有提交历史；
`git log --first-parent` 看得很清楚。

**Q：可以不用 GitHub Actions，只手动同步吗？**
A：可以。仓库里 `scripts/sync/sync-upstream.sh` 就是全部逻辑，本地执行后 push 即可；
Actions 只是把它自动化。

**Q：仓库是 AGPLv3，这样发布汉化版合规吗？**
A：AGPLv3 允许修改与再分发，但需要保留许可证与版权声明、向用户提供对应源码。本仓库
已保留 `LICENSE` 与上游署名；发布时请保留原项目名称与链接。

**Q：为什么不直接点 GitHub 的 “Sync fork”？**
A：如果仓库是 GitHub Fork，“Sync fork”会用默认 git merge，不经过本仓库的自动冲突
处理/翻译补全逻辑；遇到代码冲突会直接卡住。建议使用本仓库自带的 **Sync upstream**
工作流（或本地脚本），两者二选一，不要同时使用。
