# 运维手册（RUNBOOKS）— WebKVM

[**English**](../../runbooks/RUNBOOKS.md) • [**Español**](../../runbooks/RUNBOOKS.es.md) • [**简体中文**](RUNBOOKS.md)

面向系统管理员的运维手册。目标是确保每一次变更、事故或恢复场景，都能按照经过验证的流程、可直接复制粘贴的命令，以及明确的*退出标准*得到解决。

## 索引

| 手册 | 使用时机 |
|---|---|
| [INSTALLATION.md](../INSTALLATION.md) | 初始安装（二进制、systemd、Docker、Caddy） |
| [UPGRADE-ROLLBACK.md](UPGRADE-ROLLBACK.md) | 安全升级或回滚版本 |
| [DISASTER-RECOVERY.md](DISASTER-RECOVERY.md) | 宿主机丢失、datadir 损坏、libvirt 恢复 |
| [SECURITY-MODEL.md](SECURITY-MODEL.md) | 系统安全架构与审计 |
| [OPS-DAILY.md](OPS-DAILY.md) | Day-2 运维：健康检查、日志、审计轨迹、任务、备份 |

## 黄金法则（适用于所有手册）

1. **绝不要**在服务运行时修改 `/opt/webkvm/users.json` 或 datadir 中的文件，除非先创建备份。
2. 在进行任何修改 datadir 的操作之前，使用 `scripts/webkvm-backup.sh` 或 UI（Backup -> Create backup）。
3. 更新二进制时，保留上一版本二进制（`webkvm.previous`）以便快速回滚。
4. 二进制是预编译且自包含的：生产服务器上**无需** Go 或 Node.js 工具链。
5. 安装前务必用 `SHA256SUMS` 校验下载产物的校验和。
6. 本仓库中的 Shell 脚本以 `-euo pipefail` 运行；如果出错，请检查输出，而不是压制它。

## 关键文件与路径

| 项目 | 路径 |
|---|---|
| 二进制 | `/usr/local/bin/webkvm`（或 `/opt/webkvm/webkvm`） |
| 上一版本二进制（回滚） | `/usr/local/bin/webkvm.previous` |
| Datadir | `/opt/webkvm` |
| 用户存储 | `/opt/webkvm/users.json`（0600） |
| 初始管理员凭据 | `/opt/webkvm/admin-password.initial`（0600） |
| 已撤销令牌黑名单 | `/opt/webkvm/revoked.json`（0600） |
| API 令牌 | `/opt/webkvm/api-tokens.json`（0600） |
| 审计轨迹 | `/opt/webkvm/audit.log`（以及 `.1` … `.7` 轮转文件，每个 10 MB） |
| 应用日志 | `/var/log/webkvm/`（配置了 `WEBKVM_LOG_FILE` 时） |
| systemd 服务 | `/etc/systemd/system/webkvm.service` |
| Caddy 反向代理 | `/etc/caddy/Caddyfile`，服务 `caddy` |
| 健康检查端点 | `curl -sk https://localhost:8080/api/health` |

> 二进制路径取决于安装方式。请参阅
> [INSTALLATION.md](../INSTALLATION.md) 了解你部署方式的具体流程。

## 常用命令速查

```bash
# 服务状态与日志
systemctl status webkvm
journalctl -u webkvm -f
make status / make logs          # 在仓库内

# 健康检查
curl -sk https://localhost:8080/api/health
curl -s  http://127.0.0.1:8080/api/health

# 已安装版本
webkvm version

# 最近的审计轨迹条目
grep '"action"' /opt/webkvm/audit.log | tail

# 虚拟化栈冒烟测试
sudo scripts/smoke.sh
```

下一步：[UPGRADE-ROLLBACK.md](UPGRADE-ROLLBACK.md)。
