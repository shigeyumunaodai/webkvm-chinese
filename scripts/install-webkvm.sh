#!/usr/bin/env bash
# webkvm one-liner installer — clones the repo to /opt/webkvm-repo and installs
# from there (native systemd install; never compiles on the target server).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/shigeyumunaodai/webkvm-chinese/main/scripts/install-webkvm.sh -o /tmp/webkvm-install.sh && sudo bash /tmp/webkvm-install.sh
#
# After install, update anytime with:
#   cd /opt/webkvm-repo && git pull && sudo ./packaging/standalone/install.sh
#
# Environment variables (piped-friendly: no extra prompts are added):
#   WEBKVM_INSTALL_REPO=/repo.git     git repo URL (default: shigeyumunaodai/webkvm-chinese)
#   WEBKVM_INSTALL_BRANCH=main        branch to install
#   WEBKVM_INSTALL_TARBALL_URL=URL    install from a direct source tarball
#                                     (http(s):// URL or a local file path)
#                                     instead of git — useful for mirrors /
#                                     offline media
#   WEBKVM_GH_PROXY=https://ghfast.top/
#                                     GitHub download accelerator: prefixes
#                                     github.com / raw.githubusercontent.com
#                                     clone + tarball URLs (and is forwarded to
#                                     the installer for its release downloads)
#   WEBKVM_CN_MIRRORS=auto|tuna|ustc|aliyun|tencent|huawei
#                                     switch system/package mirrors to a
#                                     mainland-China mirror before installing
#                                     runtime deps
#   WEBKVM_CN_COMPONENTS=os,pip,npm,go,docker[,cargo,git]
#                                     components for the mirror switch
#   WEBKVM_NONINTERACTIVE=1           strictly unattended (automatic when
#                                     stdin is not a TTY, i.e. curl | bash)
#   WEBKVM_INSTALL_LOG=/var/log/webkvm-install.log   installer log file
#
# Mainland-China examples (mirrors + GitHub accelerator):
#   curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/shigeyumunaodai/webkvm-chinese/main/scripts/install-webkvm.sh -o /tmp/webkvm-install.sh
#   sudo WEBKVM_GH_PROXY=https://ghfast.top/ WEBKVM_CN_MIRRORS=auto bash /tmp/webkvm-install.sh
#
#   # Offline / mirror-hosted source tarball (no git access needed):
#   sudo WEBKVM_INSTALL_TARBALL_URL=https://mirror.example.com/webkvm-main.tar.gz bash /tmp/webkvm-install.sh
set -Eeuo pipefail

REPO_URL="${WEBKVM_INSTALL_REPO:-https://github.com/shigeyumunaodai/webkvm-chinese}"
BRANCH="${WEBKVM_INSTALL_BRANCH:-main}"
# Canonical persistent repo location: /opt/webkvm/source (mirrored by update.sh and webkvm.service)
# Fallback support: if /opt/webkvm-repo already exists from older installs, honor it.
if [[ -d "/opt/webkvm-repo/.git" && ! -d "/opt/webkvm/source" ]]; then
  REPO_DIR="/opt/webkvm-repo"
else
  REPO_DIR="${WEBKVM_INSTALL_DIR:-/opt/webkvm/source}"
fi
INSTALL_TARBALL_URL="${WEBKVM_INSTALL_TARBALL_URL:-}"
GH_PROXY="${WEBKVM_GH_PROXY:-}"
GH_PROXY="${GH_PROXY%/}"

# Piped invocation (curl ... | sudo bash) ⇒ stdin is not a TTY ⇒ run the
# installer strictly unattended (defaults everywhere, no /dev/tty prompts).
# Interactive installs (running the file from a terminal) keep their prompts.
if [[ ! -t 0 && "${WEBKVM_NONINTERACTIVE:-0}" != "1" ]]; then
  export WEBKVM_NONINTERACTIVE=1
fi

LOG_FILE="${WEBKVM_INSTALL_LOG:-/var/log/webkvm-install.log}"

red()   { printf "\033[31m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }

log() { printf "[webkvm] %s\n" "$*"; printf "[webkvm] %s\n" "$*" >>"${LOG_FILE}" 2>/dev/null || true; }

# GitHub download accelerator: <proxy>/https://github.com/... — non-GitHub
# URLs (and local files) pass through untouched.
gh_url() {
  local url="$1"
  if [[ -z "${GH_PROXY}" ]]; then
    printf '%s' "${url}"
    return 0
  fi
  case "${url}" in
    https://github.com/*|https://raw.githubusercontent.com/*)
      printf '%s/%s' "${GH_PROXY}" "${url}"
      ;;
    *) printf '%s' "${url}" ;;
  esac
}

download_and_extract() { # $1 = http(s) URL or local path, $2 = label
  local src="$1" label="$2" tmp
  if [[ -f "${src}" ]]; then
    tmp="${src}"
    log "Extracting ${label} from local file ${src}..."
  else
    tmp="$(mktemp "${TMPDIR:-/tmp}/webkvm-src.XXXXXX")"
    log "Downloading ${label}: ${src}"
    if ! curl -fsSL --retry 3 --proto '=https,http' -o "${tmp}" "${src}" >>"${LOG_FILE}" 2>&1; then
      rm -f -- "${tmp}"
      return 1
    fi
  fi
  mkdir -p "${REPO_DIR}"
  if ! tar xzf "${tmp}" -C "${REPO_DIR}" --strip-components=1 >>"${LOG_FILE}" 2>&1; then
    if [[ "${tmp}" != "${src}" ]]; then rm -f -- "${tmp}"; fi
    return 1
  fi
  if [[ "${tmp}" != "${src}" ]]; then rm -f -- "${tmp}"; fi
  return 0
}

if [[ -n "${GH_PROXY}" ]]; then
  case "${GH_PROXY}" in
    https://*) ;;
    *) red "ERROR: WEBKVM_GH_PROXY must be an https:// URL (e.g. https://ghfast.top/)"; exit 1 ;;
  esac
  log "GitHub proxy: ${GH_PROXY}"
fi

log "=== webkvm one-liner installer ==="
if [[ -n "${INSTALL_TARBALL_URL}" ]]; then
  command -v tar >/dev/null || { red "ERROR: tar is required but not installed."; exit 1; }
  if [[ ! -f "${INSTALL_TARBALL_URL}" ]]; then
    command -v curl >/dev/null || { red "ERROR: curl is required but not installed."; exit 1; }
  fi
else
  for cmd in curl tar; do
    command -v "${cmd}" >/dev/null || { red "ERROR: ${cmd} is required but not installed."; exit 1; }
  done
fi
HAVE_GIT=0
command -v git >/dev/null 2>&1 && HAVE_GIT=1

# Install source, in priority order:
#   1. WEBKVM_INSTALL_TARBALL_URL (direct tarball: mirrors/offline, no git)
#   2. existing git checkout at /opt/webkvm-repo → fetch + hard reset
#   3. fresh git clone (optionally through WEBKVM_GH_PROXY)
#   4. GitHub source tarball when git is unavailable (through the proxy)
if [[ -n "${INSTALL_TARBALL_URL}" ]]; then
  PROXIED_TARBALL_URL="$(gh_url "${INSTALL_TARBALL_URL}")"
  if ! download_and_extract "${PROXIED_TARBALL_URL}" "source tarball (WEBKVM_INSTALL_TARBALL_URL)"; then
    red "ERROR: could not download/extract ${INSTALL_TARBALL_URL}"
    exit 1
  fi
elif [[ -d "${REPO_DIR}/.git" ]]; then
  log "Updating existing repo at ${REPO_DIR}..."
  cd "${REPO_DIR}"
  ORIGIN_URL="$(git remote get-url origin 2>/dev/null || printf '%s' "${REPO_URL}")"
  PROXIED_ORIGIN_URL="$(gh_url "${ORIGIN_URL}")"
  if [[ -n "${GH_PROXY}" && "${PROXIED_ORIGIN_URL}" != "${ORIGIN_URL}" ]]; then
    # Fetch through the proxy, then point origin back at the canonical URL so
    # a later un-proxied `git pull` keeps working.
    git remote set-url origin "${PROXIED_ORIGIN_URL}"
    if ! git fetch origin "${BRANCH}" >>"${LOG_FILE}" 2>&1; then
      git remote set-url origin "${ORIGIN_URL}" 2>/dev/null || true
      red "ERROR: could not fetch ${ORIGIN_URL} (via ${GH_PROXY})"
      exit 1
    fi
    git remote set-url origin "${ORIGIN_URL}"
  else
    git fetch origin "${BRANCH}" >>"${LOG_FILE}" 2>&1 || { red "ERROR: could not fetch ${ORIGIN_URL}"; exit 1; }
  fi
  git reset --hard "origin/${BRANCH}" >>"${LOG_FILE}" 2>&1
elif [[ "${HAVE_GIT}" == 1 ]]; then
  PROXIED_REPO_URL="$(gh_url "${REPO_URL}")"
  log "Cloning webkvm (${BRANCH}) to ${REPO_DIR}..."
  git clone --depth 1 -b "${BRANCH}" "${PROXIED_REPO_URL}" "${REPO_DIR}" >>"${LOG_FILE}" 2>&1 || { red "ERROR: could not clone ${REPO_URL}"; exit 1; }
  # Keep the canonical origin URL in the checkout (the proxy was only used
  # for the clone itself; a later plain `git pull` must keep working).
  if [[ "${PROXIED_REPO_URL}" != "${REPO_URL}" ]]; then
    git -C "${REPO_DIR}" remote set-url origin "${REPO_URL}" 2>/dev/null || true
  fi
else
  TAR_URL="${REPO_URL%/}/archive/refs/heads/${BRANCH}.tar.gz"
  if ! download_and_extract "$(gh_url "${TAR_URL}")" "webkvm (${BRANCH}) tarball (no git)"; then
    red "ERROR: could not download ${TAR_URL}"
    exit 1
  fi
fi

INSTALLER="${REPO_DIR}/packaging/standalone/install.sh"
[[ -x "${INSTALLER}" ]] || { red "ERROR: installer not found at ${INSTALLER}"; exit 1; }

# Forward mainland-China acceleration settings to the standalone installer as
# flags (it also reads the WEBKVM_* env vars, but passing them explicitly keeps
# the two scripts' documented interfaces in sync). Default behaviour is
# untouched when none of them are set.
INSTALL_ARGS=()
INSTALL_ARG_COUNT=0
if [[ -n "${WEBKVM_CN_MIRRORS:-}" ]]; then
  INSTALL_ARGS+=("--cn-mirrors=${WEBKVM_CN_MIRRORS}")
  INSTALL_ARG_COUNT=$((INSTALL_ARG_COUNT + 1))
  log "cn-mirrors: ${WEBKVM_CN_MIRRORS} (components: ${WEBKVM_CN_COMPONENTS:-default})"
fi
if [[ -n "${WEBKVM_CN_COMPONENTS:-}" ]]; then
  INSTALL_ARGS+=("--cn-components=${WEBKVM_CN_COMPONENTS}")
  INSTALL_ARG_COUNT=$((INSTALL_ARG_COUNT + 1))
fi
if [[ -n "${WEBKVM_GH_PROXY:-}" ]]; then
  INSTALL_ARGS+=("--github-proxy=${WEBKVM_GH_PROXY}")
  INSTALL_ARG_COUNT=$((INSTALL_ARG_COUNT + 1))
fi

# Run installer — stdin = terminal when invoked as: curl ... -o file && sudo bash file
if [[ "${INSTALL_ARG_COUNT}" -eq 0 ]]; then
  bash "${INSTALLER}"
else
  bash "${INSTALLER}" "${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"}"
fi

log "Done. Repo kept at ${REPO_DIR} for future updates."
log "To update later: cd ${REPO_DIR} && git pull && sudo ./packaging/standalone/install.sh"
