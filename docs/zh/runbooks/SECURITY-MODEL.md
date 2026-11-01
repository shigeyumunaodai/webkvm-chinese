# 运维手册：安全模型与审计

[**English**](../../runbooks/SECURITY-MODEL.md) • [**Español**](../../runbooks/SECURITY-MODEL.es.md) • [**简体中文**](SECURITY-MODEL.md)

目的：记录 WebKVM 的安全架构、操作活动记录在哪里，以及管理员如何审计系统。补充 [SECURITY.md](../SECURITY.md)。

---

## 1. 认证与授权

- **会话**：签名 JWT（`JWT_SECRET`）。角色：`admin`、`operator`、`viewer`。由 `internal/api` 中的 `RequireRole`/`RequireAtLeast` 中间件保护。
- **管理员**：按设计不受资源配额和存储池 ACL 限制。
- **API 令牌**：用于自动化的长期 Bearer 令牌；可即时撤销。
- **持久令牌黑名单**（`revoked.json`，0600 权限）：撤销记录在守护进程重启后仍然保留。使用原子写入（tmp -> fsync -> rename），损坏时失败即放行（重命名为 `.corrupt-<ts>`）。
- **登录限速**：按 IP 强制执行；可信 CIDR 可通过 `WEBKVM_TRUSTED_RATELIMIT_CIDRS` 配置。

## 2. 密码策略

- 最少 12 个字符；4 类字符中至少包含 3 类；对照约 1,100 个常见密码的内置列表检查；拒绝简单的字符替换（例如 `p@ss`）。
- Bcrypt 哈希存储（`password_hash`）。
- 初始凭据文件 `admin-password.*`（0600）仅在哈希保存到磁盘后才会以事务方式删除。

## 3. 虚拟机与容器控制

- **资源配额**：vCPU/内存适用于**运行中**的虚拟机和容器；磁盘在所有存储池间**全局**检查。实例化模板会将配额计入**实例化用户**。
- **存储池 ACL**（`AllowedPools`）：用户对未分配的存储池收到 403 Forbidden；管理员不受限制。
- **存储池**：创建和删除仅限 `admin`。
- **应用部署**：
  - 在创建后台任务之前，目标网络会先针对可用网桥和网络预校验。
  - Cloud-Init 载荷在排队前会校验。
  - 初始化失败会将任务标记为 `error`，并审计 `appliance.deploy_cloudinit_failed`，且不会暴露不完整的凭据。
  - 自动清理（`removePoolImage`）会在失败时清除孤儿卷。
- **XML 清理**：名称和参数使用严格正则模式校验；OVA 描述符进行 XML 转义。

## 4. 审计轨迹

仅追加的 JSONL 日志，存储在 `/opt/webkvm/audit.log`（0600）。每条记录包含：
`time, user, role, action, resource, ip, detail, error`。

| 操作 | 示例 |
|---|---|
| 登录 / 退出登录 | `auth.login`、`auth.logout` |
| 用户管理 | `user.create`、`user.update`、`user.delete` |
| 虚拟机 / 容器生命周期 | `vm.create`、`vm.start`、`vm.stop`、`vm.delete` |
| 系统设置 | `system.update`、`settings.change` |
| 应用 | `vm.appliance_deploy`、`appliance.deploy_cleanup`、`appliance.deploy_cloudinit_failed` |
| 存储与 ISO | `iso.download`、`storage.pool.create` |

## 5. 审计日志轮转与持久性

- 达到 10 MB 时轮转，**最多保留 7 个备份文件**（`audit.log.1` … `.7`），总大小上限约 80 MB。
- 每次刷新后、关闭前执行 **fsync**，确保系统意外崩溃时零日志丢失。
- 守护进程优雅关闭时执行 `Logger.Close()`。
- API 查询会检查活动日志和轮转日志，返回最新优先的分页记录。

### 常用审计查询

```bash
AUDIT=/opt/webkvm/audit.log

# 最近 20 条审计事件
tail -20 "$AUDIT" | jq -r '.time + " " + .user + " " + .action'

# 失败的登录尝试
grep '"action":"auth.login"' "$AUDIT" | jq -r 'select(.error) | .time + " " + .ip'

# 用户管理变更
grep -E '"action":"user\.' "$AUDIT" | jq -r '.time + " " + .user + " " + .action + " " + (.resource // "")'

# 特定实例的生命周期事件
grep '"resource":"<vm-id-or-name>"' "$AUDIT" | jq -r '.time + " " + .action'

# 应用部署及其结果
grep -E '"action":"(vm.appliance_deploy|appliance.deploy_cleanup|appliance.deploy_cloudinit_failed)"' \
  "$AUDIT" | jq -r '.time + " " + .action + " " + (.detail.error // .error // "")'
```

> 未安装 `jq` 时，`grep '"action":"..."' "$AUDIT"` 仍然可读——每个事件一行 JSON。

---

## 6. 后台任务

- 长时间运行的操作（镜像下载、备份、导入）通过异步 worker 池执行。
- 已完成或失败超过 24 小时的任务每 5 分钟自动清除；`queued`/`running` 任务永不清理。
- 竞争通过 `sync.RWMutex` 处理；`UpdatedAt`（unix 秒）在每次创建和更新时刷新。

## 7. 月度审计清单

- [ ] 检查失败的登录与限速触发。
- [ ] 检查角色与用户账户变更。
- [ ] 验证轮转：`ls -la /opt/webkvm/audit.log*`。
- [ ] 确认 ISO/任务 UI 中没有累积 `error` 任务。
- [ ] 确认存在最近的 datadir 备份。
- [ ] 检查失败的应用部署及其清理。

## 8. 响应安全事件

1. **撤销访问**：修改管理员密码、撤销 API 令牌、轮换 `JWT_SECRET`（轮换会使所有活动会话令牌失效）。
2. **在删除任何内容之前导出审计日志**。
3. **隔离宿主机**（防火墙/网络），如果怀疑宿主机被入侵。
4. 参见 [DISASTER-RECOVERY.md](DISASTER-RECOVERY.md) 进行恢复。

## 9. 失败即关闭的破坏性防护与输入加固

- **宿主磁盘防护失败即关闭**：当 `lsblk` 安全检查无法运行或解析时，`WipeHostDisk` / `InitHostDiskDirectory` 会拒绝并返回 `503`（探测失败绝不能被解读为“没有任何挂载”）。`wipefs` 步骤失败会中止格式化路径，而不是继续执行 `sgdisk`/`mkfs`。
- **挂载点清理**：持久挂载被限制在 `/mnt/` 和 `/srv/`（不允许 `..`、不允许控制字符/换行符、绝不使用裸根），因为该值会被原样写入 systemd `.mount` unit。
- **终端临时凭证按端点限定**：`?ticket=` 仅在 `/api/host/terminal`、`/api/events` 和 `/api/vms/{id}/serial` 上被接受；在其他任何地方都返回 `403`。宿主机 PTY 仍要求通过 `/bin/login`——没有 root shell 回退——并会重新检查临时凭证的管理员角色。
- **域 XML 注入面**：`SetBootDevice` 仅接受 `disk`/`cdrom`/`network`（与 `UpdateDomain` 相同的集合）；`ImportDomain` 在归档的 `<name>` 进入 NVRAM 路径改写之前，会按卷名模式校验它。
- **防火墙应用串行化**：为每次应用使用独立临时文件；`flushTable` 只忽略“表不存在”，并会暴露权限/二进制错误。
- **磁盘挂载策略**：一个镜像最多只能挂载到一台虚拟机（`409`），非空镜像需要显式 `force: true`（否则 `409`）——在 `CreateDisk` 中强制执行，而不仅仅在 UI 中。
- **存储池 ACL 覆盖**：ISO 上传/下载、卷与 ISO 列表，以及全集群快照列表，都按 `AllowedPools` / 虚拟机 ACL 限定；用户存储不可用时，`requirePermission` 会拒绝而不是放行。
