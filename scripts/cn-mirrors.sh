#!/usr/bin/env bash
# webkvm — 国内网络环境优化：一键切换系统软件源与常用开发工具镜像（可回滚）。
#
# 用法：sudo bash scripts/cn-mirrors.sh [选项]
#
#   --mirror=auto|tuna|ustc|aliyun|tencent|huawei
#                             镜像站（默认 auto：按发行版与连通性选择，优先 TUNA）
#   --components=LIST         逗号分隔：os,pip,npm,go,docker,cargo,git
#                             默认 os,pip,npm,go,docker（缺失的工具自动跳过并提示）
#   --docker-mirror=URL       可重复；写入 /etc/docker/daemon.json 的 registry-mirrors
#                             （不提供时跳过 docker，不硬编码不稳定的公共镜像地址）
#   --github-proxy=URL        仅 --components 含 git 时写 git insteadOf 加速；
#                             同时打印一次性 URL 重写用法
#   --root=DIR                测试用模拟根目录（默认 /）：所有文件路径加 DIR 前缀，
#                             读 DIR/etc/os-release 检测发行版，跳过一切系统命令
#                             （apt-get update、systemctl、go env -w 等），只在假根
#                             目录内做文件改写。配合 --dry-run 可安全演练
#   --dry-run                 只打印将执行的操作：不改任何文件、不跑任何系统命令
#   --restore                 恢复本脚本最近一次备份（保留合并 JSON 等原有内容）
#   --yes, -y                 非交互（本脚本当前不提问，保留给脚本化调用兼容）
#   --help, -h                显示本帮助
#
# 环境变量等价：WEBKVM_CN_MIRROR、WEBKVM_CN_COMPONENTS、WEBKVM_CN_DOCKER_MIRROR、
#   WEBKVM_CN_GITHUB_PROXY、WEBKVM_CN_ROOT、WEBKVM_CN_DRY_RUN=1。
#
# 支持的系统：
#   · Ubuntu/Debian（传统 /etc/apt/sources.list 与 deb822 *.sources）
#   · Fedora / RHEL 系（/etc/yum.repos.d/*.repo，含 EPEL）
#   · Arch Linux（/etc/pacman.d/mirrorlist）
# 安全限制：镜像主机必须在允许列表内；写入前先备份；不 curl 执行远程脚本。
# 退出码：0 成功；1 失败；2 用法错误。
set -Eeuo pipefail

# ── 日志 ────────────────────────────────────────────────────────────────
LOG_TAG='[cn-mirrors]'
log()  { printf '%s %s\n' "${LOG_TAG}" "$*"; }
warn() { printf '%s 警告: %s\n' "${LOG_TAG}" "$*" >&2; }
err()  { printf '%s 错误: %s\n' "${LOG_TAG}" "$*" >&2; }
die()  { err "$*"; exit 1; }
die_usage() {
  err "$*"
  printf '%s 使用 --help 查看用法\n' "${LOG_TAG}" >&2
  exit 2
}

usage() {
  cat <<'EOF'
webkvm 国内网络优化 — 换源脚本（可回滚）

用法：
  sudo bash scripts/cn-mirrors.sh [选项]

选项：
  --mirror=auto|tuna|ustc|aliyun|tencent|huawei
                            镜像站（默认 auto：按连通性选择，优先 TUNA）
  --components=LIST         逗号分隔：os,pip,npm,go,docker,cargo,git
                            默认 os,pip,npm,go,docker（缺失的工具自动跳过并提示）
  --docker-mirror=URL       可重复；写入 /etc/docker/daemon.json 的 registry-mirrors
  --github-proxy=URL        components 含 git 时写 git insteadOf 加速（如 https://ghfast.top/）
  --root=DIR                模拟根目录（测试用；所有路径加 DIR 前缀，跳过系统命令）
  --dry-run                 只打印将执行的操作，不改文件、不跑系统命令
  --restore                 恢复本脚本最近一次备份
  --yes, -y                 非交互
  --help, -h                显示本帮助

环境变量（与选项等价）：
  WEBKVM_CN_MIRROR, WEBKVM_CN_COMPONENTS, WEBKVM_CN_DOCKER_MIRROR,
  WEBKVM_CN_GITHUB_PROXY, WEBKVM_CN_ROOT, WEBKVM_CN_DRY_RUN=1

覆盖范围：
  os      Ubuntu/Debian apt（sources.list + deb822）、Fedora/RHEL 系 dnf、Arch pacman
  pip     ~/.config/pip/pip.conf（python3 -m pip 存在时）
  npm     ~/.npmrc（npm 存在时）
  go      go env -w GOPROXY=https://goproxy.cn,direct（go 存在时）
  docker  /etc/docker/daemon.json 的 registry-mirrors（仅显式提供 --docker-mirror）
  cargo   ~/.cargo/config.toml source replacement（cargo 存在时）
  git     git insteadOf 加速（仅 --components 含 git 且提供 --github-proxy）

备份与回滚：
  每次实际写入前把原文件备份到 /var/backups/webkvm-cn-mirrors/<UTC 时间戳>/
  （保留相对路径 + manifest.tsv），--restore 恢复最近一次并删除本脚本新建的文件。

示例：
  sudo bash scripts/cn-mirrors.sh                          # 默认：os,pip,npm,go,docker
  sudo bash scripts/cn-mirrors.sh --mirror=ustc --yes      # 指定 USTC
  sudo bash scripts/cn-mirrors.sh --components=os --dry-run
  sudo bash scripts/cn-mirrors.sh --restore                # 回滚
  bash scripts/cn-mirrors.sh --root=/tmp/fake-root --mirror=tuna --dry-run  # 离线演练

退出码：0 成功；1 失败；2 用法错误。
EOF
}

# ── 默认值与参数解析 ─────────────────────────────────────────────────────
MIRROR="${WEBKVM_CN_MIRROR:-auto}"
COMPONENTS="${WEBKVM_CN_COMPONENTS:-os,pip,npm,go,docker}"
DOCKER_MIRRORS_RAW="${WEBKVM_CN_DOCKER_MIRROR:-}"
GITHUB_PROXY="${WEBKVM_CN_GITHUB_PROXY:-}"
ROOT_PREFIX="${WEBKVM_CN_ROOT:-}"
DRY_RUN=0
RESTORE=0
ASSUME_YES=0
if [[ "${WEBKVM_CN_DRY_RUN:-0}" == "1" ]]; then
  DRY_RUN=1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mirror=*)       MIRROR="${1#*=}" ;;
    --components=*)   COMPONENTS="${1#*=}" ;;
    --docker-mirror=*)
      if [[ -n "${DOCKER_MIRRORS_RAW}" ]]; then
        DOCKER_MIRRORS_RAW="${DOCKER_MIRRORS_RAW},${1#*=}"
      else
        DOCKER_MIRRORS_RAW="${1#*=}"
      fi
      ;;
    --github-proxy=*) GITHUB_PROXY="${1#*=}" ;;
    --root=*)         ROOT_PREFIX="${1#*=}" ;;
    --dry-run)        DRY_RUN=1 ;;
    --restore)        RESTORE=1 ;;
    --yes|-y)         ASSUME_YES=1 ;;
    -h|--help)        usage; exit 0 ;;
    *)                die_usage "未知参数: $1" ;;
  esac
  shift
done

# --root 规范化：只接受绝对路径，且不接受 "/"（否则容易误以为在演练真实系统）。
if [[ -n "${ROOT_PREFIX}" ]]; then
  case "${ROOT_PREFIX}" in
    /)   die_usage "请不要用 --root=/；模拟模式请指向一个假根目录，真实系统请省略 --root" ;;
    /*)  ROOT_PREFIX="${ROOT_PREFIX%/}" ;;
    *)   die_usage "--root 必须是绝对路径: ${ROOT_PREFIX}" ;;
  esac
  if [[ ! -d "${ROOT_PREFIX}" ]]; then
    die_usage "--root 目录不存在: ${ROOT_PREFIX}"
  fi
fi
MOCK=0
if [[ -n "${ROOT_PREFIX}" ]]; then
  MOCK=1
fi

SCRIPT_PATH="${BASH_SOURCE[0]}"

# ── 全局状态 ────────────────────────────────────────────────────────────
CHANGED=0
FAILED=0
BACKUP_BASE='/var/backups/webkvm-cn-mirrors'
BACKUP_DIR=''
TMP_FILE=''
FAMILY=''
DISTRO_ID=''
DISTRO_LIKE=''
DISTRO_VER=''
DISTRO_CODENAME=''
DISTRO_NAME=''
MIRROR_HOST=''
DNF_LAYOUT=''
DNF_MAP=''
DOCKER_MIRROR_LIST=''

cleanup() {
  if [[ -n "${TMP_FILE}" && -e "${TMP_FILE}" ]]; then
    rm -f -- "${TMP_FILE}" || true
  fi
}
trap cleanup EXIT

# ── 路径与模式工具 ──────────────────────────────────────────────────────
# 所有“逻辑路径”都是不带 --root 前缀的绝对路径；真正落盘前用 phys() 加前缀。
phys() { printf '%s%s' "${ROOT_PREFIX}" "$1"; }
is_real() { [[ "${MOCK}" -eq 0 && "${DRY_RUN}" -eq 0 ]]; }
display_path() { printf '%s' "${1#"${ROOT_PREFIX}"}"; }

# 用户级配置的目标用户。--root 模拟模式固定模拟 root 用户（DIR/root/...），
# 这样测试结果与运行脚本的用户无关；真实模式用 $HOME（sudo 下通常是 /root）。
user_home() {
  if [[ "${MOCK}" -eq 1 ]]; then
    printf '/root'
  else
    printf '%s' "${HOME:-/root}"
  fi
}

mark_failed() { FAILED=1; }

os_release_get() {
  local file="$1" key="$2" line
  line="$(grep -E "^[[:space:]]*${key}=" "${file}" 2>/dev/null | tail -n 1 || true)"
  if [[ -z "${line}" ]]; then
    printf ''
    return 0
  fi
  line="${line#*=}"
  line="${line#\"}"; line="${line%\"}"
  line="${line#\'}"; line="${line%\'}"
  printf '%s' "${line}"
}

# 工具是否“存在”：真实模式用 command -v；模拟模式只查假根目录里的可执行文件。
tool_available() {
  local name="$1" cand
  if [[ "${MOCK}" -eq 1 ]]; then
    for cand in "/usr/bin/${name}" "/usr/local/bin/${name}" "/bin/${name}"; do
      if [[ -x "$(phys "${cand}")" ]]; then
        return 0
      fi
    done
    return 1
  fi
  command -v "${name}" >/dev/null 2>&1
}

# ── 镜像站 ──────────────────────────────────────────────────────────────
# 允许列表：只有这些主机会被写入系统文件（防 WEBKVM_CN_* 注入任意主机）。
ALLOWED_MIRROR_HOSTS='mirrors.tuna.tsinghua.edu.cn mirrors.ustc.edu.cn mirrors.aliyun.com mirrors.cloud.tencent.com mirrors.tencent.com repo.huaweicloud.com mirrors.huaweicloud.com'
# 常见的旧官方主机与国内镜像主机：apt 改写时统一换成选中镜像的主机名（保留路径）。
APT_OFFICIAL_HOSTS='archive.ubuntu.com security.ubuntu.com ports.ubuntu.com deb.debian.org security.debian.org ftp.debian.org'

mirror_host() {
  case "$1" in
    tuna)    printf 'mirrors.tuna.tsinghua.edu.cn' ;;
    ustc)    printf 'mirrors.ustc.edu.cn' ;;
    aliyun)  printf 'mirrors.aliyun.com' ;;
    tencent) printf 'mirrors.cloud.tencent.com' ;;
    huawei)  printf 'repo.huaweicloud.com' ;;
  esac
}

allowed_mirror_host() {
  local host="$1" h
  for h in ${ALLOWED_MIRROR_HOSTS}; do
    if [[ "${host}" == "${h}" ]]; then
      return 0
    fi
  done
  return 1
}

probe_mirror() {
  local host
  host="$(mirror_host "$1")"
  [[ -n "${host}" ]] || return 1
  # 没有 curl 时不做探测（安装早期 ca-certificates/curl 可能尚未安装）。
  if ! command -v curl >/dev/null 2>&1; then
    return 0
  fi
  curl -fsS --head --max-time 4 "https://${host}/" >/dev/null 2>&1
}

validate_mirror_name() {
  case "$1" in
    auto|tuna|ustc|aliyun|tencent|huawei) ;;
    *) die_usage "无效的 --mirror 值：$1（可选 auto|tuna|ustc|aliyun|tencent|huawei）" ;;
  esac
}

resolve_mirror() {
  local m
  case "${MIRROR}" in
    auto)
      if [[ "${MOCK}" -eq 1 || "${DRY_RUN}" -eq 1 ]]; then
        MIRROR='tuna'
        log "镜像站：auto → tuna（模拟/演练模式不探测连通性）"
      else
        for m in tuna ustc aliyun tencent huawei; do
          if probe_mirror "${m}"; then
            MIRROR="${m}"
            log "镜像站：auto → ${m}（连通性探测通过）"
            break
          fi
        done
        if [[ "${MIRROR}" == "auto" ]]; then
          MIRROR='tuna'
          warn "所有镜像连通性探测均失败，回退到 tuna（可用 --mirror=... 显式指定）"
        fi
      fi
      ;;
    tuna|ustc|aliyun|tencent|huawei) ;;
    *)
      die_usage "无效的 --mirror 值：${MIRROR}（可选 auto|tuna|ustc|aliyun|tencent|huawei）"
      ;;
  esac
  MIRROR_HOST="$(mirror_host "${MIRROR}")"
  if [[ -z "${MIRROR_HOST}" ]] || ! allowed_mirror_host "${MIRROR_HOST}"; then
    die "镜像主机 ${MIRROR_HOST:-<empty>} 不在允许列表内，拒绝写入"
  fi
  log "使用镜像站：${MIRROR}（${MIRROR_HOST}）"
}

# ── 组件解析 ────────────────────────────────────────────────────────────
normalize_components() {
  local raw item rest out=''
  raw="$(printf '%s' "$1" | tr -d '[:space:]')"
  rest="${raw}"
  while [[ -n "${rest}" ]]; do
    case "${rest}" in
      *,*) item="${rest%%,*}"; rest="${rest#*,}" ;;
      *)   item="${rest}"; rest='' ;;
    esac
    if [[ -z "${item}" ]]; then
      continue
    fi
    case "${item}" in
      os|pip|npm|go|docker|cargo|git) ;;
      *) die_usage "无效的 --components 项：${item}（可选 os,pip,npm,go,docker,cargo,git）" ;;
    esac
    case " ${out} " in
      *" ${item} "*) ;;
      *) out="${out:+${out},}${item}" ;;
    esac
  done
  if [[ -z "${out}" ]]; then
    die_usage "组件列表为空（默认 os,pip,npm,go,docker）"
  fi
  COMPONENTS="${out}"
}

has_component() {
  case ",${COMPONENTS}," in
    *",$1,"*) return 0 ;;
  esac
  return 1
}

normalize_docker_mirrors() {
  local item old_ifs
  DOCKER_MIRROR_LIST=''
  if [[ -z "${DOCKER_MIRRORS_RAW}" ]]; then
    return 0
  fi
  old_ifs="${IFS}"
  IFS=', '
  set -f
  for item in ${DOCKER_MIRRORS_RAW}; do
    [[ -n "${item}" ]] || continue
    case "${item}" in
      https://*) ;;
      *) IFS="${old_ifs}"; set +f; die_usage "--docker-mirror 必须使用 https:// 地址：${item}" ;;
    esac
    case "${item}" in
      *[[:space:]]*) IFS="${old_ifs}"; set +f; die_usage "--docker-mirror 含空白字符：${item}" ;;
      *[!A-Za-z0-9._:/~%@+-]*) IFS="${old_ifs}"; set +f; die_usage "--docker-mirror 含不安全字符：${item}" ;;
    esac
    local host="${item#https://}"
    host="${host%%/*}"
    if [[ -z "${host}" ]]; then
      IFS="${old_ifs}"; set +f
      die_usage "无法解析 --docker-mirror 主机名：${item}"
    fi
    case "${host}" in
      *[!A-Za-z0-9.-]*) IFS="${old_ifs}"; set +f; die_usage "无法解析 --docker-mirror 主机名：${item}" ;;
    esac
    item="${item%/}"
    if [[ -n "${DOCKER_MIRROR_LIST}" ]]; then
      DOCKER_MIRROR_LIST="${DOCKER_MIRROR_LIST} ${item}"
    else
      DOCKER_MIRROR_LIST="${item}"
    fi
  done
  IFS="${old_ifs}"
  set +f
}

normalize_github_proxy() {
  local host
  [[ -z "${GITHUB_PROXY}" ]] && return 0
  case "${GITHUB_PROXY}" in
    https://*) ;;
    *) die_usage "--github-proxy 必须使用 https:// 地址：${GITHUB_PROXY}" ;;
  esac
  case "${GITHUB_PROXY}" in
    *[[:space:]]*) die_usage "--github-proxy 含空白字符：${GITHUB_PROXY}" ;;
    *[!A-Za-z0-9._:/~%@+-]*) die_usage "--github-proxy 含不安全字符：${GITHUB_PROXY}" ;;
  esac
  host="${GITHUB_PROXY#https://}"
  host="${host%%/*}"
  if [[ -z "${host}" ]]; then
    die_usage "--github-proxy 缺少主机名：${GITHUB_PROXY}"
  fi
  case "${host}" in
    *[!A-Za-z0-9.-]*) die_usage "--github-proxy 主机名非法：${GITHUB_PROXY}" ;;
  esac
  GITHUB_PROXY="${GITHUB_PROXY%/}"
  case " ghfast.top gh-proxy.com ghproxy.net ghproxy.com mirror.ghproxy.com gh.api.99988866.xyz gh.llkk.cc " in
    *" ${host} "*) ;;
    *) warn "github 代理主机 ${host} 不在内置已知列表，请确认地址可靠" ;;
  esac
}

pypi_index_url() {
  case "${MIRROR}" in
    tuna)    printf 'https://pypi.tuna.tsinghua.edu.cn/simple' ;;
    ustc)    printf 'https://pypi.mirrors.ustc.edu.cn/simple' ;;
    aliyun)  printf 'https://mirrors.aliyun.com/pypi/simple/' ;;
    tencent) printf 'https://mirrors.cloud.tencent.com/pypi/simple' ;;
    huawei)  printf 'https://repo.huaweicloud.com/repository/pypi/simple' ;;
  esac
}

# ── 备份 / 恢复 ─────────────────────────────────────────────────────────
ensure_backup_dir() {
  if [[ -n "${BACKUP_DIR}" ]]; then
    return 0
  fi
  local base stamp dir n
  base="$(phys "${BACKUP_BASE}")"
  mkdir -p "${base}"
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  dir="${base}/${stamp}"
  n=1
  while [[ -e "${dir}" ]]; do
    n=$((n + 1))
    dir="${base}/${stamp}-${n}"
  done
  mkdir -p "${dir}/files"
  : > "${dir}/manifest.tsv"
  BACKUP_DIR="${dir}"
}

# 备份一个逻辑路径（原文件不存在时记为新建，恢复时删除）。
backup_file() {
  local logical="$1" src dst rel
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    return 0
  fi
  ensure_backup_dir
  if awk -F'\t' -v p="${logical}" '$1==p{found=1} END{exit !found}' "${BACKUP_DIR}/manifest.tsv" 2>/dev/null; then
    return 0
  fi
  src="$(phys "${logical}")"
  if [[ -e "${src}" ]]; then
    rel="files${logical}"
    dst="${BACKUP_DIR}/${rel}"
    mkdir -p "$(dirname "${dst}")"
    cp -p "${src}" "${dst}"
    printf '%s\t1\t%s\n' "${logical}" "${rel}" >>"${BACKUP_DIR}/manifest.tsv"
  else
    printf '%s\t0\t-\n' "${logical}" >>"${BACKUP_DIR}/manifest.tsv"
  fi
}

# 写入一个逻辑路径：内容未变则跳过（幂等），写入前先备份。
write_logical_file() {
  local logical="$1" content="$2" target existing
  target="$(phys "${logical}")"
  if [[ -f "${target}" ]]; then
    existing="$(cat "${target}")"
    if [[ "${existing}" == "${content}" ]]; then
      log "已是最新，跳过：${logical}"
      return 0
    fi
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      log "[dry-run] 将备份并写入：${logical}"
      CHANGED=$((CHANGED + 1))
      return 0
    fi
    backup_file "${logical}"
  else
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      log "[dry-run] 将新建：${logical}"
      CHANGED=$((CHANGED + 1))
      return 0
    fi
    backup_file "${logical}"
  fi
  mkdir -p "$(dirname "${target}")"
  TMP_FILE="${target}.webkvm-cn.$$"
  printf '%s\n' "${content}" >"${TMP_FILE}"
  chmod 0644 "${TMP_FILE}"
  mv -f "${TMP_FILE}" "${target}"
  TMP_FILE=''
  CHANGED=$((CHANGED + 1))
  log "已写入：${logical}"
}

# 去掉别处（pacman/gitconfig）由本脚本写入的托管块。
strip_managed_block() {
  printf '%s\n' "$1" | awk '
    /^# webkvm-cn-mirrors begin/ { skip = 1; next }
    /^# webkvm-cn-mirrors end/   { skip = 0; next }
    skip != 1 { print }
  '
}

file_has_any_host() {
  local file="$1" host
  shift || true
  for host in "$@"; do
    if grep -qF "://${host}/" "${file}" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

# ── 发行版检测 ──────────────────────────────────────────────────────────
detect_distro() {
  local osr shown ids
  osr="$(phys /etc/os-release)"
  shown='/etc/os-release'
  if [[ "${MOCK}" -eq 1 ]]; then
    shown="${ROOT_PREFIX}/etc/os-release"
  fi
  if [[ ! -f "${osr}" ]]; then
    die "未找到 ${shown}，无法检测发行版（--root 指向的目录需包含 etc/os-release）"
  fi
  DISTRO_ID="$(os_release_get "${osr}" ID)"
  DISTRO_LIKE="$(os_release_get "${osr}" ID_LIKE)"
  DISTRO_VER="$(os_release_get "${osr}" VERSION_ID)"
  DISTRO_CODENAME="$(os_release_get "${osr}" VERSION_CODENAME)"
  DISTRO_NAME="$(os_release_get "${osr}" PRETTY_NAME)"

  ids=" ${DISTRO_ID} ${DISTRO_LIKE} "
  case "${ids}" in
    *ubuntu*|*debian*|*linuxmint*|*pop*) FAMILY='apt' ;;
    *fedora*|*rhel*|*centos*|*rocky*|*almalinux*|*ol*) FAMILY='dnf' ;;
    *arch*|*manjaro*) FAMILY='pacman' ;;
    *)
      # 兜底：按假根目录里存在的包管理器判断（模拟模式不做 command -v）。
      if [[ "${MOCK}" -eq 1 ]]; then
        if [[ -x "$(phys /usr/bin/apt-get)" ]]; then FAMILY='apt'
        elif [[ -x "$(phys /usr/bin/dnf)" ]]; then FAMILY='dnf'
        elif [[ -x "$(phys /usr/bin/pacman)" ]]; then FAMILY='pacman'
        fi
      fi
      ;;
  esac
  if [[ -z "${FAMILY}" ]]; then
    die "不支持的发行版：${DISTRO_NAME:-unknown}（ID=${DISTRO_ID:-unknown}）；仅支持 Ubuntu/Debian、Fedora/RHEL 系、Arch Linux"
  fi
  log "检测到发行版：${DISTRO_NAME:-${DISTRO_ID:-unknown}}（家族：${FAMILY}，version=${DISTRO_VER:-?}，codename=${DISTRO_CODENAME:-?}）"
}

# ── 组件：os / apt ──────────────────────────────────────────────────────
# 只替换主机名，保留协议、路径、suite 与 component；支持 sources.list 与 deb822。
rewrite_apt_content() {
  local content="$1" host escaped
  for host in ${APT_OFFICIAL_HOSTS} ${ALLOWED_MIRROR_HOSTS}; do
    escaped="${host//./\\.}"
    content="$(printf '%s\n' "${content}" | sed -E \
      -e "s#://${escaped}/#://${MIRROR_HOST}/#g" \
      -e "s#://${escaped}([[:space:]]|\$)#://${MIRROR_HOST}\\1#g")"
  done
  printf '%s' "${content}"
}

process_apt_file() {
  local logical="$1" target content new
  target="$(phys "${logical}")"
  if ! file_has_any_host "${target}" ${APT_OFFICIAL_HOSTS} ${ALLOWED_MIRROR_HOSTS}; then
    log "跳过（未发现官方或已知镜像源）：${logical}"
    return 0
  fi
  content="$(cat "${target}")"
  new="$(rewrite_apt_content "${content}")"
  write_logical_file "${logical}" "${new}"
}

run_apt() {
  local found=0 dir f logical
  if [[ -f "$(phys /etc/apt/sources.list)" ]]; then
    found=1
    process_apt_file /etc/apt/sources.list
  fi
  dir="$(phys /etc/apt/sources.list.d)"
  if [[ -d "${dir}" ]]; then
    for f in "${dir}"/*.list "${dir}"/*.sources; do
      if [[ -f "${f}" ]]; then
        found=1
        logical="${f#"${ROOT_PREFIX}"}"
        process_apt_file "${logical}"
      fi
    done
  fi
  if [[ "${found}" -eq 0 ]]; then
    warn "未找到 /etc/apt/sources.list 或 /etc/apt/sources.list.d/*.{list,sources}，跳过 os 换源"
    mark_failed
  fi
  return 0
}

# ── 组件：os / dnf ──────────────────────────────────────────────────────
detect_dnf_layout() {
  DNF_LAYOUT=''
  case "${DISTRO_ID}" in
    fedora) DNF_LAYOUT='fedora' ;;
    rocky)  DNF_LAYOUT='rocky' ;;
    alma*)  DNF_LAYOUT='almalinux' ;;
    centos)
      case "${DISTRO_NAME}" in
        *Stream*|*stream*) DNF_LAYOUT='centos-stream' ;;
        *) DNF_LAYOUT='unsupported' ;;
      esac
      ;;
    rhel|ol|oracle|scientific)
      DNF_LAYOUT='unsupported'
      ;;
    *)
      case " ${DISTRO_LIKE} " in
        *fedora*) DNF_LAYOUT='fedora' ;;
        *rhel*)   DNF_LAYOUT='unsupported' ;;
        *)        DNF_LAYOUT='unsupported' ;;
      esac
      ;;
  esac
}

_dnf_add() {
  if [[ -n "${DNF_MAP}" ]]; then
    DNF_MAP="${DNF_MAP};$1|$2"
  else
    DNF_MAP="$1|$2"
  fi
}

build_dnf_map() {
  DNF_MAP=''
  case "${DNF_LAYOUT}" in
    fedora)
      _dnf_add 'fedora' 'fedora/releases/$releasever/Everything/$basearch/os/'
      _dnf_add 'updates' 'fedora/updates/$releasever/Everything/$basearch/'
      _dnf_add 'updates-testing' 'fedora/updates/testing/$releasever/Everything/$basearch/'
      _dnf_add 'fedora-cisco-openh264' 'fedora/fedora-cisco-openh264/releases/$releasever/Everything/$basearch/os/'
      ;;
    rocky)
      _dnf_add 'baseos' 'rockylinux/$releasever/BaseOS/$basearch/os/'
      _dnf_add 'appstream' 'rockylinux/$releasever/AppStream/$basearch/os/'
      _dnf_add 'crb' 'rockylinux/$releasever/CRB/$basearch/os/'
      _dnf_add 'extras' 'rockylinux/$releasever/extras/$basearch/os/'
      _dnf_add 'highavailability' 'rockylinux/$releasever/HighAvailability/$basearch/os/'
      _dnf_add 'resilientstorage' 'rockylinux/$releasever/ResilientStorage/$basearch/os/'
      _dnf_add 'nfv' 'rockylinux/$releasever/NFV/$basearch/os/'
      _dnf_add 'plus' 'rockylinux/$releasever/plus/$basearch/os/'
      _dnf_add 'epel' 'epel/$releasever/Everything/$basearch/'
      ;;
    almalinux)
      _dnf_add 'baseos' 'almalinux/$releasever/BaseOS/$basearch/os/'
      _dnf_add 'appstream' 'almalinux/$releasever/AppStream/$basearch/os/'
      _dnf_add 'crb' 'almalinux/$releasever/CRB/$basearch/os/'
      _dnf_add 'extras' 'almalinux/$releasever/extras/$basearch/os/'
      _dnf_add 'highavailability' 'almalinux/$releasever/HighAvailability/$basearch/os/'
      _dnf_add 'resilientstorage' 'almalinux/$releasever/ResilientStorage/$basearch/os/'
      _dnf_add 'nfv' 'almalinux/$releasever/NFV/$basearch/os/'
      _dnf_add 'epel' 'epel/$releasever/Everything/$basearch/'
      ;;
    centos-stream)
      _dnf_add 'baseos' 'centos-stream/$stream/BaseOS/$basearch/os/'
      _dnf_add 'appstream' 'centos-stream/$stream/AppStream/$basearch/os/'
      _dnf_add 'crb' 'centos-stream/$stream/CRB/$basearch/os/'
      _dnf_add 'extras-common' 'centos-stream/$stream/extras-common/$basearch/os/'
      _dnf_add 'highavailability' 'centos-stream/$stream/HighAvailability/$basearch/os/'
      _dnf_add 'resilientstorage' 'centos-stream/$stream/ResilientStorage/$basearch/os/'
      _dnf_add 'nfv' 'centos-stream/$stream/NFV/$basearch/os/'
      _dnf_add 'epel' 'epel/$releasever/Everything/$basearch/'
      ;;
  esac
}

# 已知 repo id ⇒ 构造国内镜像布局的 baseurl（保留 $releasever/$basearch/$stream 变量，
# 由 dnf 展开，避免硬编码架构与版本）；未知 repo 保持原样并警告。
rewrite_dnf_content() {
  local content="$1" fname="$2"
  printf '%s\n' "${content}" | awk -v host="${MIRROR_HOST}" -v map="${DNF_MAP}" -v fname="${fname}" '
    function emit(s) { print s }
    function warn(msg) { printf("[cn-mirrors] 警告: %s\n", msg) > "/dev/stderr" }
    function flush(   i, rawid, id, path, hidx, bidx, inserted, l) {
      if (n == 0) return
      rawid = ""; hidx = 0; bidx = 0
      for (i = 1; i <= n; i++) {
        if (hidx == 0 && lines[i] ~ /^[ \t]*\[[^]]+\]/) {
          hidx = i
          rawid = lines[i]
          sub(/^[ \t]*\[/, "", rawid)
          sub(/\][ \t]*$/, "", rawid)
        }
        if (bidx == 0 && lines[i] ~ /^[ \t]*#?[ \t]*baseurl[ \t]*=/) bidx = i
      }
      id = tolower(rawid)
      gsub(/^[ \t]+|[ \t]+$/, "", id)
      if (id != "" && (id in MP)) {
        path = "https://" host "/" MP[id]
        inserted = 0
        for (i = 1; i <= n; i++) {
          l = lines[i]
          if (i == bidx) { emit("baseurl=" path); inserted = 1; continue }
          if (l ~ /^[ \t]*#?[ \t]*baseurl[ \t]*=/) continue
          if (l ~ /^[ \t]*#?[ \t]*metalink[ \t]*=/)   { sub(/^[ \t]*#?/, "#", l); emit(l); continue }
          if (l ~ /^[ \t]*#?[ \t]*mirrorlist[ \t]*=/) { sub(/^[ \t]*#?/, "#", l); emit(l); continue }
          emit(l)
          if (i == hidx && bidx == 0) { emit("baseurl=" path); inserted = 1 }
        }
        if (!inserted) emit("baseurl=" path)
      } else if (hidx == 0) {
        for (i = 1; i <= n; i++) emit(lines[i])
      } else {
        warn(fname "：未知 repo [" id "]，保持原样")
        for (i = 1; i <= n; i++) emit(lines[i])
      }
      n = 0
    }
    BEGIN {
      m = split(map, items, ";")
      for (i = 1; i <= m; i++) {
        if (items[i] == "") continue
        j = index(items[i], "|")
        if (j == 0) continue
        MP[tolower(substr(items[i], 1, j - 1))] = substr(items[i], j + 1)
      }
    }
    {
      if ($0 ~ /^[ \t]*\[[^]]+\]/) flush()
      lines[++n] = $0
    }
    END { flush() }
  '
}

run_dnf() {
  local dir f logical any=0 content new
  detect_dnf_layout
  if [[ "${DNF_LAYOUT}" == 'unsupported' ]]; then
    warn "发行版 ${DISTRO_NAME:-${DISTRO_ID}} 的 dnf 源布局未内建映射（RHEL/CentOS Linux 等使用订阅源或已 EOL 的官方源），跳过 os 换源；其他组件不受影响"
    mark_failed
    return 0
  fi
  build_dnf_map
  dir="$(phys /etc/yum.repos.d)"
  if [[ ! -d "${dir}" ]]; then
    warn "未找到 /etc/yum.repos.d，跳过 os 换源"
    mark_failed
    return 0
  fi
  for f in "${dir}"/*.repo; do
    if [[ -f "${f}" ]]; then
      any=1
      logical="${f#"${ROOT_PREFIX}"}"
      content="$(cat "${f}")"
      new="$(rewrite_dnf_content "${content}" "${logical}")"
      write_logical_file "${logical}" "${new}"
    fi
  done
  if [[ "${any}" -eq 0 ]]; then
    warn "未找到 /etc/yum.repos.d/*.repo，跳过 os 换源"
    mark_failed
  fi
  return 0
}

# ── 组件：os / pacman ───────────────────────────────────────────────────
run_pacman() {
  local logical='/etc/pacman.d/mirrorlist' target cur stripped block new
  target="$(phys "${logical}")"
  if [[ ! -f "${target}" ]]; then
    warn "未找到 ${logical}，跳过 os 换源"
    mark_failed
    return 0
  fi
  cur="$(cat "${target}")"
  stripped="$(strip_managed_block "${cur}")"
  block="$(printf '%s\n' \
    '# webkvm-cn-mirrors begin（由 webkvm scripts/cn-mirrors.sh 生成，--restore 可恢复）' \
    "Server = https://${MIRROR_HOST}/archlinux/\$repo/os/\$arch" \
    '# webkvm-cn-mirrors end')"
  if [[ -n "${stripped}" ]]; then
    new="$(printf '%s\n%s' "${block}" "${stripped}")"
  else
    new="${block}"
  fi
  write_logical_file "${logical}" "${new}"
  return 0
}

# ── 组件：pip / npm / go / cargo / docker / git ─────────────────────────
run_pip() {
  local conf index host content
  log "── 组件：pip ──"
  if [[ "${MOCK}" -eq 1 ]]; then
    if ! tool_available python3; then
      log "未检测到 python3（模拟根目录），跳过 pip"
      return 0
    fi
  else
    if ! command -v python3 >/dev/null 2>&1 || ! python3 -m pip --version >/dev/null 2>&1; then
      log "未检测到 pip（python3 -m pip），跳过"
      return 0
    fi
  fi
  index="$(pypi_index_url)"
  host="${index#https://}"
  host="${host%%/*}"
  conf="$(user_home)/.config/pip/pip.conf"
  content="$(printf '%s\n' \
    '# 由 webkvm scripts/cn-mirrors.sh 写入（--restore 可恢复）' \
    '[global]' \
    "index-url = ${index}" \
    "trusted-host = ${host}")"
  write_logical_file "${conf}" "${content}"
  return 0
}

run_npm() {
  local conf content
  log "── 组件：npm ──"
  if ! tool_available npm; then
    log "未检测到 npm，跳过"
    return 0
  fi
  conf="$(user_home)/.npmrc"
  content="$(printf '%s\n' \
    '# 由 webkvm scripts/cn-mirrors.sh 写入（--restore 可恢复）' \
    'registry=https://registry.npmmirror.com')"
  write_logical_file "${conf}" "${content}"
  return 0
}

run_go() {
  local value conf cur filtered new goenv
  log "── 组件：go ──"
  value='https://goproxy.cn,direct'
  if ! tool_available go; then
    log "未检测到 go，跳过（安装 Go 后可重跑本脚本）"
    return 0
  fi
  conf="$(user_home)/.config/go/env"
  if [[ "${MOCK}" -eq 1 ]]; then
    if [[ -f "$(phys "${conf}")" ]]; then
      cur="$(cat "$(phys "${conf}")")"
    else
      cur=''
    fi
    filtered="$(printf '%s\n' "${cur}" | awk '!/^[ \t]*GOPROXY[ \t]*=/' | sed '/^$/d')"
    if [[ -n "${filtered}" ]]; then
      new="$(printf '%s\n%s' "${filtered}" "GOPROXY=${value}")"
    else
      new="GOPROXY=${value}"
    fi
    write_logical_file "${conf}" "${new}"
    return 0
  fi
  cur="$(go env GOPROXY 2>/dev/null || true)"
  if [[ "${cur}" == "${value}" ]]; then
    log "go GOPROXY 已是最新，跳过"
    return 0
  fi
  goenv="$(go env GOENV 2>/dev/null || true)"
  if [[ -n "${goenv}" && "${goenv}" != 'off' ]]; then
    backup_file "${goenv}"
  fi
  if go env -w "GOPROXY=${value}"; then
    CHANGED=$((CHANGED + 1))
    log "已写入 go env：GOPROXY=${value}"
  else
    warn "go env -w 失败，跳过 go"
    mark_failed
  fi
  return 0
}

run_cargo() {
  local conf content
  log "── 组件：cargo ──"
  if ! tool_available cargo; then
    log "未检测到 cargo，跳过"
    return 0
  fi
  conf="$(user_home)/.cargo/config.toml"
  content="$(printf '%s\n' \
    '# 由 webkvm scripts/cn-mirrors.sh 写入（--restore 可恢复）' \
    '[source.crates-io]' \
    'replace-with = "rsproxy-sparse"' \
    '' \
    '[source.rsproxy-sparse]' \
    'registry = "sparse+https://rsproxy.cn/index/"' \
    '' \
    '[net]' \
    'git-fetch-with-cli = true')"
  write_logical_file "${conf}" "${content}"
  return 0
}

docker_daemon_json_from_scratch() {
  local item first=1 items
  items=''
  for item in ${DOCKER_MIRROR_LIST}; do
    if [[ "${first}" -eq 1 ]]; then
      first=0
      items="    \"${item}\""
    else
      items="${items},
    \"${item}\""
    fi
  done
  printf '%s\n' '{' '  "registry-mirrors": [' "${items}" '  ]' '}'
}

merge_docker_daemon_json() {
  # stdout = 合并后的合法 JSON；失败时返回非 0（调用方不得覆盖原文件）。
  python3 - "$1" ${DOCKER_MIRROR_LIST} <<'PY'
import json
import sys

path = sys.argv[1]
wanted = [m for m in sys.argv[2:] if m]
raw = ""
try:
    with open(path, "r", encoding="utf-8") as fh:
        raw = fh.read()
except FileNotFoundError:
    raw = ""

data = {}
if raw.strip():
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise SystemExit("daemon.json 顶层必须是 JSON 对象")

current = data.get("registry-mirrors", [])
if current is None:
    current = []
if not isinstance(current, list):
    raise SystemExit("daemon.json 中 registry-mirrors 必须是数组")

merged = []
for item in wanted + [str(x) for x in current]:
    if item not in merged:
        merged.append(item)
data["registry-mirrors"] = merged
sys.stdout.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY
}

run_docker() {
  local logical='/etc/docker/daemon.json' target content
  log "── 组件：docker ──"
  if [[ -z "${DOCKER_MIRROR_LIST}" ]]; then
    log "未提供 --docker-mirror（或 WEBKVM_CN_DOCKER_MIRROR），跳过 docker（不硬编码公共镜像地址）"
    return 0
  fi
  target="$(phys "${logical}")"
  if [[ -f "${target}" ]]; then
    if ! command -v python3 >/dev/null 2>&1; then
      warn "未找到 python3，无法安全合并已存在的 ${logical}；跳过 docker（其余组件不受影响）"
      return 0
    fi
    if ! content="$(merge_docker_daemon_json "${target}" 2>&1)"; then
      warn "合并 ${logical} 失败（原文件不是合法 JSON？）：${content}"
      mark_failed
      return 0
    fi
  else
    content="$(docker_daemon_json_from_scratch)"
  fi
  write_logical_file "${logical}" "${content}"
  if is_real; then
    if command -v systemctl >/dev/null 2>&1; then
      if systemctl restart docker >/dev/null 2>&1; then
        log "已重启 docker 服务"
      else
        warn "重启 docker 失败，请手动执行：sudo systemctl restart docker"
      fi
    fi
  fi
  return 0
}

gitconfig_block() {
  local proxy_base="${GITHUB_PROXY%/}/"
  printf '%s\n' \
    '# webkvm-cn-mirrors begin（由 webkvm scripts/cn-mirrors.sh 生成，--restore 可恢复）' \
    "[url \"${proxy_base}https://github.com/\"]" \
    $'\tinsteadOf = https://github.com/' \
    "[url \"${proxy_base}https://raw.githubusercontent.com/\"]" \
    $'\tinsteadOf = https://raw.githubusercontent.com/' \
    '# webkvm-cn-mirrors end'
}

print_git_one_shot_usage() {
  local proxy_base="${GITHUB_PROXY%/}/"
  log "git 一次性用法（不写任何配置）："
  log "  git clone ${proxy_base}https://github.com/Slaker19/webkvm"
  log "  curl -fsSL ${proxy_base}https://raw.githubusercontent.com/Slaker19/webkvm/main/scripts/install-webkvm.sh -o /tmp/webkvm-install.sh"
}

run_git() {
  local logical conf proxy_base prefix_raw cur new
  log "── 组件：git ──"
  if [[ -z "${GITHUB_PROXY}" ]]; then
    log "未提供 --github-proxy（或 WEBKVM_CN_GITHUB_PROXY），跳过 git 加速"
    return 0
  fi
  proxy_base="${GITHUB_PROXY%/}/"
  logical="$(user_home)/.gitconfig"
  conf="$(phys "${logical}")"
  if [[ "${MOCK}" -eq 1 ]] || ! tool_available git; then
    if [[ "${MOCK}" -eq 0 ]]; then
      log "未检测到 git，跳过"
      return 0
    fi
    cur=''
    if [[ -f "${conf}" ]]; then
      cur="$(cat "${conf}")"
    fi
    if [[ -n "${cur}" ]]; then
      local stripped
      stripped="$(strip_managed_block "${cur}")"
      if [[ -n "${stripped}" ]]; then
        new="$(printf '%s\n%s' "${stripped}" "$(gitconfig_block)")"
      else
        new="$(gitconfig_block)"
      fi
    else
      new="$(gitconfig_block)"
    fi
    write_logical_file "${logical}" "${new}"
    print_git_one_shot_usage
    return 0
  fi
  if git config --global --get-all "url.${proxy_base}https://github.com/.insteadOf" 2>/dev/null | grep -qxF 'https://github.com/'; then
    log "git insteadOf 已配置，跳过"
    print_git_one_shot_usage
    return 0
  fi
  if [[ -f "${conf}" ]]; then
    backup_file "${logical}"
  fi
  if git config --global "url.${proxy_base}https://github.com/.insteadOf" 'https://github.com/' \
    && git config --global "url.${proxy_base}https://raw.githubusercontent.com/.insteadOf" 'https://raw.githubusercontent.com/'; then
    CHANGED=$((CHANGED + 1))
    log "已写入 git insteadOf 加速（$(user_home)/.gitconfig）"
  else
    warn "写入 git 配置失败，跳过 git"
    mark_failed
  fi
  print_git_one_shot_usage
  return 0
}

run_os() {
  log "── 组件：os（系统软件源）──"
  case "${FAMILY}" in
    apt)    run_apt ;;
    dnf)    run_dnf ;;
    pacman) run_pacman ;;
  esac
  return 0
}

# ── 恢复 ────────────────────────────────────────────────────────────────
do_restore() {
  local base latest dir logical existed rel target src tab
  base="$(phys "${BACKUP_BASE}")"
  if [[ ! -d "${base}" ]]; then
    die "没有找到备份目录：${BACKUP_BASE}（尚未运行过本脚本？）"
  fi
  latest="$(ls -1 "${base}" 2>/dev/null | sort | tail -n 1)"
  if [[ -z "${latest}" ]]; then
    die "备份目录为空：${BACKUP_BASE}"
  fi
  dir="${base}/${latest}"
  if [[ ! -f "${dir}/manifest.tsv" ]]; then
    die "备份清单缺失：${dir}/manifest.tsv"
  fi
  log "从备份恢复：$(display_path "${dir}")"
  tab="$(printf '\t')"
  while IFS="${tab}" read -r logical existed rel; do
    if [[ -z "${logical}" ]]; then
      continue
    fi
    target="$(phys "${logical}")"
    if [[ "${existed}" == '1' ]]; then
      src="${dir}/${rel}"
      if [[ ! -f "${src}" ]]; then
        warn "备份中缺少文件，跳过：${logical}"
        mark_failed
        continue
      fi
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] 将恢复：${logical}"
        CHANGED=$((CHANGED + 1))
        continue
      fi
      mkdir -p "$(dirname "${target}")"
      cp -p "${src}" "${target}"
      CHANGED=$((CHANGED + 1))
      log "已恢复：${logical}"
    else
      if [[ ! -e "${target}" ]]; then
        continue
      fi
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[dry-run] 将删除本脚本新建的文件：${logical}"
        CHANGED=$((CHANGED + 1))
        continue
      fi
      rm -f -- "${target}"
      CHANGED=$((CHANGED + 1))
      log "已删除本脚本新建的文件：${logical}"
    fi
  done <"${dir}/manifest.tsv"
  if [[ "${CHANGED}" -eq 0 ]]; then
    log "备份中的文件与当前状态一致，无需恢复"
  fi
  log "恢复完成。建议刷新软件源缓存："
  log "  · Debian/Ubuntu：sudo apt-get update"
  log "  · Fedora/RHEL 系：sudo dnf makecache"
  log "  · Arch：sudo pacman -Sy"
  return 0
}

# ── 收尾提示 ────────────────────────────────────────────────────────────
print_next_steps() {
  log "下一步建议："
  case "${FAMILY}" in
    apt)    log "  · 刷新软件源：sudo apt-get update" ;;
    dnf)    log "  · 刷新软件缓存：sudo dnf makecache" ;;
    pacman) log "  · 刷新软件源：sudo pacman -Sy" ;;
  esac
  if has_component pip; then log "  · 验证 pip：python3 -m pip config list"; fi
  if has_component npm; then log "  · 验证 npm：npm config get registry"; fi
  if has_component go; then log "  · 验证 go：go env GOPROXY"; fi
  if has_component docker && [[ -n "${DOCKER_MIRROR_LIST}" ]]; then
    log "  · 验证 docker：docker info | grep -A4 'Registry Mirrors'"
  fi
  if has_component cargo; then log "  · 验证 cargo：cat ~/.cargo/config.toml"; fi
  if has_component git && [[ -n "${GITHUB_PROXY}" ]]; then
    log "  · 验证 git：git config --global --get-regexp '^url\.'"
  fi
  log "  · 用户级配置（pip/npm/go/cargo/git）只对当前用户生效；重新登录 shell 后生效"
  log "  · 如需回滚：sudo bash ${SCRIPT_PATH} --restore"
}

# ── 主流程 ──────────────────────────────────────────────────────────────
validate_mirror_name "${MIRROR}"
normalize_components "${COMPONENTS}"
normalize_docker_mirrors
normalize_github_proxy

# 真实模式（非模拟、非演练）必须 root；--dry-run / --root 允许普通用户。
if [[ "${MOCK}" -eq 0 && "${DRY_RUN}" -eq 0 && "${EUID}" -ne 0 ]]; then
  die "请使用 root 运行：sudo bash $0"
fi

if [[ "${RESTORE}" -eq 1 ]]; then
  do_restore
  if [[ "${FAILED}" -eq 1 ]]; then
    exit 1
  fi
  exit 0
fi

detect_distro
resolve_mirror

for comp in os pip npm go docker cargo git; do
  if has_component "${comp}"; then
    "run_${comp}"
  fi
done

echo ''
if [[ "${CHANGED}" -eq 0 ]]; then
  log "完成：没有需要修改的文件（可能已经是同一镜像，幂等跳过）"
else
  log "完成：共调整 ${CHANGED} 个文件"
fi
if [[ -n "${BACKUP_DIR}" ]]; then
  log "原文件已备份到：$(display_path "${BACKUP_DIR}")（--restore 可恢复）"
fi
print_next_steps
if [[ "${FAILED}" -eq 1 ]]; then
  err "部分组件失败，请检查上面的警告（已成功修改的文件仍可用 --restore 回滚）"
  exit 1
fi
log "全部完成。"
exit 0
