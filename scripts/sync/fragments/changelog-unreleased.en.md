## [Unreleased]

### Added
- **Simplified Chinese (`zh`) localization:** full UI dictionary (3,797 keys,
  symmetric across `en/es/ca/zh`), Simplified Chinese entry in the language
  selector, browser-language auto-detection, synchronized `<html lang="zh-CN">`
  and Chinese cron humanisation (`cronstrue` `zh_CN`).
- **China-mainland network optimization:** `scripts/cn-mirrors.sh` switches
  apt (legacy `sources.list` + deb822), dnf (Fedora, Rocky/Alma/CentOS Stream,
  EPEL) and pacman to mainland mirrors and configures pip/npm/Go/Docker/Cargo/Git;
  it backs up every file, supports `--restore`, `--dry-run` and a simulated
  `--root`, and never executes remote scripts. Installer integration:
  `--cn-mirrors[=auto|tuna|ustc|aliyun|tencent|huawei]`, `--cn-components=`,
  `--github-proxy=` (`WEBKVM_CN_MIRRORS`, `WEBKVM_CN_COMPONENTS`,
  `WEBKVM_GH_PROXY`); `scripts/install-webkvm.sh` also accepts
  `WEBKVM_INSTALL_TARBALL_URL`; new `make cn-mirrors` / `make test-cn-mirrors`.
- **Chinese documentation:** `README.zh.md` and a complete `docs/zh/` mirror
  (deployment, installation, usage, CLI, Docker, API, FAQ, architecture,
  comparison, security, China-network guide and 5 operations runbooks), with
  language links added to the English/Spanish docs.

### Changed
- **i18n coverage:** moved ~460 hardcoded Spanish/English UI strings to
  translated i18n keys across AppStore, ImageHub, VM list, networks, VM
  creation/detail, storage, snippets, security jail, terminal, keyboard-
  shortcuts help, Incus image catalog, task center/drawer, pagination and
  accessibility labels (Close/Dismiss/Select).
- **i18n tooling:** `check-i18n` now validates four locales and en→zh
  placeholder parity; the pluralisation test suite covers `zh`; CI step renamed
  accordingly.
- **Docs fixes found while localizing:** installer `--bind` help now states the
  real `127.0.0.1` default (READMEs explain LAN exposure), legacy NAT mode is
  documented as libvirt's default NAT network (no `vmbr1`), and
  `.env.example` documents the CORS default as same-origin (empty).
- Release tarball now ships `scripts/cn-mirrors.sh`.
