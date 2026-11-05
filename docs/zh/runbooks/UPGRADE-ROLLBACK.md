# 运维手册：升级与回滚

[**English**](../../runbooks/UPGRADE-ROLLBACK.md) • [**Español**](../../runbooks/UPGRADE-ROLLBACK.es.md) • [**简体中文**](UPGRADE-ROLLBACK.md)

目的：安全、可靠地升级 WebKVM，并在必要时回滚到上一版本，**不丢失数据，也不损坏审计日志**。

> 适用于原生 systemd 安装。对于容器化部署，参见 [docs/DOCKER.md](../DOCKER.md)。

---

## 1. 准备工作

1. **检查当前版本：**
   ```bash
   webkvm version
   ```

2. **查看更新日志**（发布版中的 `CHANGELOG.md`），了解破坏性变更或额外的迁移步骤。

3. **在做任何更改前完整备份 datadir：**
   ```bash
   sudo scripts/webkvm-backup.sh
   # 或手动：
   sudo systemctl stop webkvm
   sudo cp -a /opt/webkvm /opt/webkvm.bak.$(date +%F-%H%M)
   sudo systemctl start webkvm
   ```

4. **下载发布版并校验校验和：**
   ```bash
   VERSION=v0.0.1
   curl -fsSL -o /tmp/webkvm-$VERSION.tar.gz \
     https://github.com/shigeyumunaodai/webkvm-chinese/releases/download/$VERSION/webkvm-$VERSION.tar.gz
   curl -fsSL -o /tmp/SHA256SUMS \
     https://github.com/shigeyumunaodai/webkvm-chinese/releases/download/$VERSION/SHA256SUMS
   cd /tmp
   sha256sum -c SHA256SUMS --ignore-missing webkvm-$VERSION.tar.gz
   ```
   必须打印 `OK`。如果失败，立即**中止**。

5. **运行栈冒烟测试**（可选但推荐）：
   ```bash
   sudo scripts/smoke.sh
   ```

---

## 2. 执行升级

### 自动部署（内置回滚）

tarball 附带**预编译二进制**和安装器，因此生产服务器无需 Go 或 Node.js 工具链。安装器会设置回滚陷阱：任何失败时都会恢复上一版本的二进制和 unit。

```bash
cd /tmp && tar -xzf webkvm-$VERSION.tar.gz
sudo WEBKVM_BINARY=backend/webkvm bash packaging/standalone/install.sh --yes
```

### 手动升级

```bash
sudo systemctl stop webkvm
sudo cp -a /usr/local/bin/webkvm /usr/local/bin/webkvm.previous
sudo install -m 0755 /tmp/webkvm /usr/local/bin/webkvm
sudo systemctl daemon-reload
sudo systemctl start webkvm
```

---

## 3. 升级后验证

1. **服务状态：**
   ```bash
   systemctl is-active webkvm        # -> active
   systemctl status webkvm --no-pager
   ```

2. **健康检查：**
   ```bash
   # 8080/http 是默认值；如果此安装使用其他端口
   # 或 HTTPS（config.json 中的 server.port / server.tls_cert），
   # 可用以下命令查找：
   #   sudo bash scripts/detect-webkvm-endpoint.sh /opt/webkvm
   curl -sk https://localhost:8080/api/health
   ```

3. **版本检查：**
   ```bash
   webkvm version
   ```

4. **UI 验证：** 在浏览器中访问 `https://<host>:8080`，验证登录和虚拟机列表。

5. **审计完整性：**
   ```bash
   wc -l /opt/webkvm/audit.log
   tail -3 /opt/webkvm/audit.log
   ```

---

## 4. 回滚流程

如果升级遇到问题或未通过健康检查，上一版本的二进制始终由 `make install-systemd`（以及上面的手动步骤）保留在 `webkvm.previous`。

```bash
# 使用 makefile：
sudo make rollback
# 将 webkvm.previous -> webkvm，重启，并进行 20 秒健康检查。

# 手动：
sudo systemctl stop webkvm
sudo test -f /usr/local/bin/webkvm.previous || { echo "no previous binary"; exit 1; }
sudo mv /usr/local/bin/webkvm.previous /usr/local/bin/webkvm
sudo systemctl start webkvm
curl -sk https://localhost:8080/api/health   # 如果不是默认端口/协议请调整；见上方说明
```

> **重要**：回滚**不会**恢复 datadir。如果问题涉及数据，请恢复完整备份：
> ```bash
> sudo systemctl stop webkvm
> sudo rm -rf /opt/webkvm
> sudo cp -a /opt/webkvm.bak.<timestamp> /opt/webkvm
> sudo systemctl start webkvm
> ```

---

## 5. 卸载

```bash
make uninstall
# 停止并移除服务与二进制。datadir 会被有意保留
# （如果你想删除它，请手动删除）。
```

## 退出标准

- [ ] `webkvm version` 报告目标版本。
- [ ] `systemctl is-active webkvm` = `active`。
- [ ] `/api/health` 返回 `ok`。
- [ ] `audit.log` 完整且仍在增长。
- [ ] 失败时，回滚已完成且服务可正常使用。
