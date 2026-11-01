# 运维手册：Day-2 日常运维与维护

[**English**](../../runbooks/OPS-DAILY.md) • [**Español**](../../runbooks/OPS-DAILY.es.md) • [**简体中文**](OPS-DAILY.md)

目的：在运行中的 WebKVM 安装上执行日常管理任务——监控、日志检查、审计验证、后台任务、备份与清理。

---

## 1. 监控与健康检查

### API 健康检查

```bash
curl -sk https://localhost:8080/api/health
# 预期响应：{"status":"ok","version":"...","build_time":"..."}
```

可通过 cron 定时执行：
```bash
*/1 * * * * root curl -fsS -m 5 http://127.0.0.1:8080/api/health || logger -t webkvm "WebKVM health check failed"
```

### 服务与资源检查

```bash
systemctl status webkvm --no-pager
journalctl -u webkvm -f
ss -ltnp | grep -E '8080|443'
```

> 在反向代理之后，或使用 `BIND_ADDR=127.0.0.1` 时，请改为查询回环地址上的端点。

### UI 仪表盘

- **状态（Status）**：版本、后端状态、可用更新。
- **设置（Settings）**：监听地址、端口、日志、备份、证书。
- **告警（Alerts）**（启用通知器时）：虚拟机停机、磁盘空间不足、备份失败。

---

## 2. 应用日志

- 结构化日志（默认 JSON 格式）：`journalctl -u webkvm -f`，或设置了 `WEBKVM_LOG_FILE` 时的 `/var/log/webkvm/`。
- 可配置详细程度与格式：`WEBKVM_LOG_LEVEL`（`info`、`debug`、`warn`）与 `WEBKVM_LOG_FORMAT`（`json`、`console`）。

---

## 3. 审计与合规

审计日志是取证与合规分析的主要事实来源：

```bash
ls -la /opt/webkvm/audit.log*
# 自动轮转：audit.log、audit.log.1 ... .7（每个 10 MB，总计最多约 80 MB）
tail -f /opt/webkvm/audit.log
```

示例查询见 [SECURITY-MODEL.md](SECURITY-MODEL.md)。

---

## 4. 后台任务与部署

- 任务在内存中运行；超过 24 小时的终态任务每 5 分钟自动清除。
- 活动（`running`）或等待中（`queued`）的任务永远不会被自动终止。
- 如果下载或部署卡住：
  1. 检查卷状态：`virsh vol-list <pool>`。
  2. 在 UI 任务中心查看任务状态。
  3. 如需要，清理孤儿卷后重试。
- 自动清理（`removePoolImage`）已覆盖普通失败；手动卡住的任务属于例外情况。

---

## 5. 备份

datadir 是唯一关键的状态目录。

```bash
# 手动快照：
sudo scripts/webkvm-backup.sh

# 在 UI 中配置：Backup -> Targets -> Schedule + Retention
```

建议保留策略：7 份每日 + 4 份每周 + 12 份每月快照。

---

## 6. 清理与日志精简

- 审计日志自动轮转（7 × 10 MB），无需手动 cron 任务。
- Systemd journal：`journalctl --vacuum-size=200M`。
- 存储池：用 `virsh vol-list <pool>` 对照活动域检查未被引用的存储卷。

---

## 7. 定期冒烟测试

`scripts/smoke.sh` 脚本验证端到端虚拟化栈（存储池 -> 卷 -> 虚拟机 -> 运行中），并且**会自行清理**，即使在 Ctrl+C 或失败时也是如此。宿主机或 libvirt 升级后值得运行：

```bash
sudo scripts/smoke.sh
```

选项：`SMOKE_TIMEOUT=180`、`WEBKVM_SMOKE_KEEP=1`（保留资源以便调试）、`WEBKVM_URL=https://localhost:8080`（增加健康检查）。

---

## 8. 机密轮换

- **管理员密码**：从 UI 修改（Users -> edit）——新密码保存后，`admin-password.*` 文件会以事务方式删除。
- **API 令牌**：重新签发并撤销不再使用的令牌（UI 或 API）。
- **`JWT_SECRET`**：仅在怀疑泄露时轮换；轮换会使所有活动会话失效。

---

## 9. 升级

参见 [UPGRADE-ROLLBACK.md](UPGRADE-ROLLBACK.md)：先备份，校验校验和，然后用 tarball 中的二进制重新安装（`sudo WEBKVM_BINARY=backend/webkvm bash packaging/standalone/install.sh --yes`，该命令会执行健康检查并自动回滚），最后验证。

---

## 10. 发布版本（仅维护者）

```bash
git tag v0.0.1 && git push origin v0.0.1
# GitHub Actions 会构建并发布 dist/webkvm-<tag>.tar.gz + SHA256SUMS
# 本地替代方案：
make release                      # 仅本地产物
make release RELEASE_PUBLISH=1    # 同时用 gh 发布
```

在宣布之前检查已发布的版本及其校验和。
