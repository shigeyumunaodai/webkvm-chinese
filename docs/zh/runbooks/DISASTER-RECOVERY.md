# 运维手册：灾难恢复

[**English**](../../runbooks/DISASTER-RECOVERY.md) • [**Español**](../../runbooks/DISASTER-RECOVERY.es.md) • [**简体中文**](DISASTER-RECOVERY.md)

目的：在灾难性故障后恢复 WebKVM——宿主机硬件故障、datadir 损坏、libvirt 损坏或配置文件丢失。系统设计为**datadir 是唯一的状态来源**；其他所有组件（二进制、systemd 服务、存储池）都可重建。

---

## 0. 架构与依赖关系图

```
可运行的 WebKVM =
  二进制 (/usr/local/bin/webkvm)
  + Datadir (/opt/webkvm)      <-- 关键状态（需要备份）
  + libvirt（存储池、卷、QEMU/KVM 域）
  + （可选）Caddy / SSL 证书 / .env
```

- **虚拟机和磁盘位于存储池中**，而不在 WebKVM datadir 内。
- datadir 包含：`users.json`、`api-tokens.json`、`revoked.json`、`audit.log*`、`backup/`、`nodes.json`、`certs/` 以及配置存储。

---

## 1. 宿主机启动但服务无法启动

```bash
systemctl status webkvm
journalctl -u webkvm -n 100 --no-pager

# 常见原因：
# - libvirtd 已停止       -> sudo systemctl start libvirtd
# - 端口 8080 冲突        -> ss -ltnp | grep 8080
# - datadir 缺失/损坏     -> 检查 /opt/webkvm
# - 二进制缺失            -> 重新安装二进制（见第 2 节）
```

WebKVM 包含到 libvirt 的自动后台重连，采用指数退避（10 秒到 60 秒）；libvirtd 恢复后无需重启 WebKVM。

---

## 2. 二进制丢失或损坏

1. 从 GitHub 下载所需的发布版。
2. 用 `SHA256SUMS` 校验校验和（见 UPGRADE-ROLLBACK）。
3. 安装：
   ```bash
   sudo install -m 0755 webkvm /usr/local/bin/webkvm
   sudo systemctl restart webkvm
   ```
4. 通过 `/api/health` 验证。

> datadir 格式在次要版本之间不会变化；仅替换二进制永远不会丢失用户或审计历史。

---

## 3. datadir 损坏或丢失

### 3a. 从自动化 UI 备份恢复

如果在 `/opt/webkvm/backup/` 中配置了本地备份：

```bash
sudo systemctl stop webkvm
# 将有问题的 datadir 移到一旁：
sudo mv /opt/webkvm /opt/webkvm.broken
sudo mkdir -p /opt/webkvm
# 将备份归档解压到 /opt/webkvm
sudo tar -xzf /path/to/backup.tar.gz -C /opt/webkvm
sudo chown -R root:root /opt/webkvm
sudo chmod 600 /opt/webkvm/*.json /opt/webkvm/revoked.json 2>/dev/null || true
sudo systemctl start webkvm
curl -sk https://localhost:8080/api/health
```

### 3b. 从手动备份恢复（`webkvm-backup.sh` 或普通复制）

```bash
sudo systemctl stop webkvm
sudo rm -rf /opt/webkvm
sudo cp -a /opt/webkvm.bak.<date> /opt/webkvm
# 恢复正确的属主与权限：
sudo chown -R root:root /opt/webkvm
sudo chmod 600 /opt/webkvm/*.json /opt/webkvm/revoked.json 2>/dev/null || true
sudo chmod 700 /opt/webkvm/certs 2>/dev/null || true
sudo systemctl start webkvm
```

### 3c. 没有 datadir 备份时的恢复

如果不存在 datadir 备份，可恢复的状态为：

- **虚拟机在 libvirt 中完好无损**——仍可由 `virsh list --all` 列出，WebKVM 在重新安装后会重新发现并管理它们。
- **用户账户、API 令牌和审计历史将丢失。** 重新安装、重新创建管理员账户并重新签发令牌。

---

## 4. 单个状态文件的部分损坏

| 文件 | 症状 | 恢复方法 |
|---|---|---|
| `users.json` | 所有登录失败 | 从备份恢复。没有备份时：重新安装并重新创建管理员。 |
| `revoked.json` | `Error loading revoked file` | **失败即放行（fail-open）**：服务器将损坏文件重命名为 `revoked.json.corrupt-<ts>` 并继续运行。此前已撤销的令牌不再处于撤销状态——请重新撤销它们，或轮换 `JWT_SECRET` 一次性使所有已签发令牌失效。 |
| `audit.log` | 列表为空或解析错误 | 日志记录器会跳过格式错误的行；仅在需要历史记录时从备份恢复。 |
| `api-tokens.json` | 有效令牌返回 401 | 从备份恢复，或重新创建令牌。 |
| `certs/` | TLS 握手失败 | 用 `make regen-cert` 生成新的自签名证书对，或重新指向你自己的证书。 |

---

## 5. libvirt 域丢失但磁盘完好

即使域定义已丢失，磁盘通常仍保留在存储池中。请使用 `virt-install` / `virsh define` 重新创建域，并指向现有卷：

```bash
virsh vol-list <pool>                    # 定位卷
# 复用该磁盘重新创建虚拟机；客户机数据就在卷中。
```

如果域存在但每次启动都 panic，且它是通过 cloud-init 置备的，请注意 NoCloud seed 仅在首次启动时被消费——不会自动重新置备。

---

## 6. 完整宿主机重建（引导）

1. 安装依赖：`make install-deps`（libvirt、QEMU 等）。
2. `make install-all`（后端 + Caddy + HTTPS）。
3. 恢复 datadir（第 3 节）。
4. 检查存储池：`virsh pool-list --all`；用 `pool-start` 重新激活。
5. 运行 `sudo scripts/smoke.sh` 端到端验证栈。
6. 以管理员身份登录并验证虚拟机、用户、审计日志和任务。

---

## 事故快速检查清单

```bash
# 1. 服务是否在响应？
systemctl is-active webkvm
curl -sk https://localhost:8080/api/health

# 2. libvirt 是否健康？
virsh -c qemu:///system list --all

# 3. datadir 是否完好？
ls -la /opt/webkvm | head

# 4. 审计日志是否完好？
wc -l /opt/webkvm/audit.log

# 5. 最近的备份是什么？
ls -lt /opt/webkvm/backup/ | head
```
