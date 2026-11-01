# WebKVM 中文文档

WebKVM 的简体中文文档索引。安装后请先阅读[安装指南](INSTALLATION.md)，日常操作参见[使用手册](USAGE.md)。

---

## 快速开始与部署

- [完整中文部署指南](DEPLOYMENT.md) —— 从零开始的完整部署流程：环境要求、国内网络准备、一键安装与克隆安装、Docker、离线安装、交互选项、TLS、首次登录、网络模式、创建虚拟机与容器、存储、备份恢复、升级回滚卸载、安全加固与故障排查。

## 安装

- [安装指南与技术文档](INSTALLATION.md) —— 安装、升级、卸载，以及架构、仓库布局、后端软件包、环境变量、磁盘布局、安全与 REST API 摘要。英文原版：[INSTALLATION.md](../INSTALLATION.md)

## 使用

- [使用手册](USAGE.md) —— 首次登录、界面、虚拟机与容器、模板与 cloud-init、存储、网络与防火墙、备份、告警、配额、用户与角色、社区应用、日志与故障排查。英文原版：[USAGE.md](../USAGE.md)
- [CLI 参考手册](CLI.md) —— `webkvm-cli` 全部子命令、全局选项与 JSON 输出用法。英文原版：[CLI.md](../CLI.md)

## Docker

- [在 Docker 中运行 WebKVM](DOCKER.md) —— 使用官方镜像与 Compose 运行 WebKVM，以及与原生部署的功能对等说明。英文原版：[DOCKER.md](../DOCKER.md)

## API

- [REST 与 WebSocket API 规范](API.md) —— 认证、端点、请求与响应字段。英文原版：[API.md](../API.md)

## 常见问题

- [常见问题（FAQ）](FAQ.md) —— 架构、虚拟机与容器、网络、存储、终端、安全与故障排查。英文原版：[FAQ.md](../FAQ.md)

## 架构

- [内部架构深度解析](ARCHITECTURE.md) —— 控制平面、数据平面与状态平面，后端并发模式与前端设计。英文原版：[ARCHITECTURE.md](../ARCHITECTURE.md)

## 对比

- [与其他虚拟化平台的对比](COMPARISON.md) —— 与 Proxmox VE、Cockpit (Machines)、virt-manager 和 Portainer 的客观技术对比。英文原版：[COMPARISON.md](../COMPARISON.md)

## 安全

- [安全策略与漏洞报告](SECURITY.md) —— 受支持的版本与漏洞披露渠道。英文原版：[SECURITY.md](../../SECURITY.md)

## 运维手册（runbooks）

运维手册位于 [runbooks/](runbooks/) 目录：

- [运维手册总览](runbooks/RUNBOOKS.md)
- [日常运维](runbooks/OPS-DAILY.md)
- [升级与回滚](runbooks/UPGRADE-ROLLBACK.md)
- [灾难恢复](runbooks/DISASTER-RECOVERY.md)
- [安全模型](runbooks/SECURITY-MODEL.md)

## 国内网络

- [国内网络优化指南](CHINA-NETWORK.md) —— 软件源镜像加速、GitHub 代理以及安装器的网络相关参数。
