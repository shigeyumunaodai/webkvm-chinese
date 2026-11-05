## 9. Localización zh (fork) y red doméstica

> Sección mantenida por el fork `webkvm-zh`. `scripts/sync/sync-upstream.sh` la
> reinserta automáticamente cuando un merge de upstream reescribe este fichero.
> Guía de sincronización: [`docs/zh/GITHUB-SYNC.md`](docs/zh/GITHUB-SYNC.md).

- **i18n**: locales `en/es/ca/zh` (3.797 claves por idioma), selector de idioma,
  autodetección del idioma del navegador, `<html lang="zh-CN">` sincronizado y
  `cronstrue` con locale `zh_CN`. `scripts/check-i18n.sh` valida las cuatro
  lenguas y la paridad de placeholders `zh`.
- **Textos hardcodeados**: ~460 cadenas ES/EN migradas a claves i18n
  (AppStore, ImageHub, VmList, VmCreate/VmDetail, Storage, Snippets,
  SecurityJail, Terminal, KeyboardShortcuts, TaskCenter/TaskDrawer,
  Pagination, etiquetas a11y `Close`/`Dismiss`/`Select`...).
- **Documentación china**: `README.zh.md` + `docs/zh/**` (incluye
  `docs/zh/DEPLOYMENT.md`, `docs/zh/CHINA-NETWORK.md`, `docs/zh/runbooks/`).
- **Recuperación de red del host**: `scripts/fix-bridge-port-ip.sh` (dry-run por defecto, `--apply` repara IP duplicada en puerto de bridge; ver `docs/zh/DEPLOYMENT.md` §13.11) y aviso en `scripts/setup-network.sh` cuando ifupdown también configura la interfaz física.
- **Red doméstica (China)**: `scripts/cn-mirrors.sh`, su test offline
  `scripts/qa/test-cn-mirrors.sh`, flags del instalador
  `--cn-mirrors/--cn-components/--github-proxy` y variables `WEBKVM_CN_*`,
  `WEBKVM_GH_PROXY`, `WEBKVM_INSTALL_TARBALL_URL`.
- **Sincronización con upstream**: workflow `.github/workflows/sync-upstream.yml`;
  los ficheros de localización propios están marcados `merge=ours` en
  `.gitattributes`. Tras cada sync, el workflow rellena con inglés las claves
  nuevas (`scripts/sync/fill-missing-zh.py`) y abre una incidencia de
  "traducción pendiente"; los conflictos de código se abren como incidencia
  aparte.
