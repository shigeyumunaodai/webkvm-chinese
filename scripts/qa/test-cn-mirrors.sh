#!/usr/bin/env bash
# scripts/qa/test-cn-mirrors.sh — scripts/cn-mirrors.sh 的离线单元测试。
#
# 特点：
#   · 不需要 root、不需要真实包管理器（apt/dnf/pacman 都不会被调用）；
#   · 不访问网络（所有镜像连通性探测在 --root/--dry-run 下都会被跳过）；
#   · 不修改本机：所有文件改写都发生在 mktemp -d 出来的假根目录内；
#   · macOS（/bin/bash 3.2）与 Linux 均可直接运行；失败退出非 0。
#
# 用法：bash scripts/qa/test-cn-mirrors.sh
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CN="${ROOT_DIR}/scripts/cn-mirrors.sh"

TMP=''
cleanup() {
  if [[ -n "${TMP}" && -d "${TMP}" ]]; then
    rm -rf -- "${TMP}"
  fi
}
trap cleanup EXIT
TMP="$(mktemp -d "${TMPDIR:-/tmp}/webkvm-cn-mirrors-test.XXXXXX")"

PASS=0
FAIL=0
RC=0
OUT=''

ok()  { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$*"; }
bad() {
  FAIL=$((FAIL + 1))
  printf 'FAIL: %s\n' "$*" >&2
  if [[ -n "${OUT}" ]]; then
    printf '%s\n' "${OUT}" | sed 's/^/    | /' >&2
  fi
}
section() { printf '\n── %s ──\n' "$*"; }

write_file() {
  mkdir -p "$(dirname "$1")"
  cat >"$1"
}

# 在假根目录内运行 cn-mirrors.sh；结果放在 OUT/RC。
run_cn() {
  set +e
  OUT="$(bash "${CN}" "$@" 2>&1)"
  RC=$?
  set -e
}

assert_rc() {
  local want="$1" name="$2"
  if [[ "${RC}" == "${want}" ]]; then
    ok "${name}（rc=${RC}）"
  else
    bad "${name}：期望 rc=${want}，实际 rc=${RC}"
  fi
}

assert_contains() {
  local name="$1" needle="$2"
  case "${OUT}" in
    *"${needle}"*) ok "${name}" ;;
    *) bad "${name}：输出中缺少「${needle}」" ;;
  esac
}

assert_file_contains() {
  local name="$1" file="$2" needle="$3"
  if grep -qF -- "${needle}" "${file}" 2>/dev/null; then
    ok "${name}"
  else
    bad "${name}：${file#${TMP}} 中缺少「${needle}」"
  fi
}

assert_file_not_contains() {
  local name="$1" file="$2" needle="$3"
  if grep -qF -- "${needle}" "${file}" 2>/dev/null; then
    bad "${name}：${file#${TMP}} 中不应出现「${needle}」"
  else
    ok "${name}"
  fi
}

assert_files_equal() {
  local name="$1" a="$2" b="$3"
  if cmp -s "${a}" "${b}"; then
    ok "${name}"
  else
    bad "${name}：文件内容不一致（$(basename "${b}") vs 期望）"
  fi
}

assert_path_absent() {
  local name="$1" path="$2"
  if [[ -e "${path}" ]]; then
    bad "${name}：不应存在 ${path#${TMP}}"
  else
    ok "${name}"
  fi
}

backup_count() {
  ls -1 "$1/var/backups/webkvm-cn-mirrors" 2>/dev/null | wc -l | tr -d ' '
}

section '静态检查'
if bash -n "${CN}" 2>/dev/null; then
  ok "bash -n scripts/cn-mirrors.sh"
else
  bad "bash -n scripts/cn-mirrors.sh"
fi

section '--help 与用法错误（退出码 2）'
run_cn --help
assert_rc 0 '--help 退出码为 0'
assert_contains '--help 提到 --restore' '--restore'
assert_contains '--help 提到 --root' '--root=DIR'
assert_contains '--help 提到 --dry-run' '--dry-run'
assert_contains '--help 列出环境变量' 'WEBKVM_CN_MIRROR'

run_cn --mirror=evil
assert_rc 2 '非法 --mirror 退出码为 2'
run_cn --components=os,bogus
assert_rc 2 '非法 --components 退出码为 2'
run_cn --nonsense
assert_rc 2 '未知参数退出码为 2'
run_cn --root=relative/path
assert_rc 2 '相对 --root 退出码为 2'
run_cn --root=/tmp/webkvm-cn-test-does-not-exist-$$
assert_rc 2 '不存在的 --root 退出码为 2'
run_cn --root=/
assert_rc 2 '拒绝 --root=/（避免误操作真实系统）'
run_cn --docker-mirror=http://insecure.example
assert_rc 2 '非 https 的 --docker-mirror 退出码为 2'

# ── Ubuntu：传统 sources.list + deb822 *.sources ────────────────────────
section 'Ubuntu（legacy + deb822）换源 / 备份 / 幂等'
R="${TMP}/ubuntu"
write_file "${R}/etc/os-release" <<'EOF'
PRETTY_NAME="Ubuntu 24.04 LTS"
ID=ubuntu
ID_LIKE=debian
VERSION_ID="24.04"
VERSION_CODENAME=noble
EOF
write_file "${R}/etc/apt/sources.list" <<'EOF'
deb http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-updates main restricted
deb http://security.ubuntu.com/ubuntu noble-security main restricted
deb http://ports.ubuntu.com/ubuntu-ports noble main
# 第三方源应保持不变
deb [arch=amd64 signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable
EOF
write_file "${R}/etc/apt/sources.list.d/ubuntu.sources" <<'EOF'
Types: deb
URIs: http://archive.ubuntu.com/ubuntu/
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://security.ubuntu.com/ubuntu/
Suites: noble-security
Components: main restricted
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
mkdir -p "${TMP}/expect"
cp "${R}/etc/apt/sources.list" "${TMP}/expect/ubuntu-sources.list"
cp "${R}/etc/apt/sources.list.d/ubuntu.sources" "${TMP}/expect/ubuntu.sources"

run_cn --root="${R}" --mirror=tuna --components=os --yes
assert_rc 0 'Ubuntu 换源成功'
SL="${R}/etc/apt/sources.list"
DS="${R}/etc/apt/sources.list.d/ubuntu.sources"
assert_file_contains 'archive.ubuntu.com 已替换为 tuna' "${SL}" 'http://mirrors.tuna.tsinghua.edu.cn/ubuntu'
assert_file_contains 'security.ubuntu.com 已替换为 tuna' "${SL}" 'mirrors.tuna.tsinghua.edu.cn/ubuntu noble-security'
assert_file_contains 'ports.ubuntu.com 路径（ubuntu-ports）保留' "${SL}" 'mirrors.tuna.tsinghua.edu.cn/ubuntu-ports noble main'
assert_file_contains 'suite/component 保留' "${SL}" 'noble-updates main restricted'
assert_file_not_contains 'archive.ubuntu.com 不再出现' "${SL}" 'archive.ubuntu.com'
assert_file_not_contains 'security.ubuntu.com 不再出现' "${SL}" 'security.ubuntu.com'
assert_file_not_contains 'ports.ubuntu.com 不再出现' "${SL}" 'ports.ubuntu.com'
assert_file_contains '第三方 docker 源保持原样' "${SL}" 'download.docker.com/linux/ubuntu'
assert_file_contains 'deb822 URIs 已替换为 tuna' "${DS}" 'URIs: http://mirrors.tuna.tsinghua.edu.cn/ubuntu/'
assert_file_contains 'deb822 security 套件保留' "${DS}" 'Suites: noble-security'
assert_file_not_contains 'deb822 无 archive.ubuntu.com 残留' "${DS}" 'archive.ubuntu.com'

BK_COUNT="$(backup_count "${R}")"
if [[ "${BK_COUNT}" == '1' ]]; then ok '产生 1 个备份目录'; else bad "备份目录数量应为 1，实际 ${BK_COUNT}"; fi
MANIFEST="$(ls -1 "${R}/var/backups/webkvm-cn-mirrors"/*/manifest.tsv 2>/dev/null | head -1)"
assert_file_contains 'manifest 记录 sources.list' "${MANIFEST}" '/etc/apt/sources.list'
assert_files_equal '备份内容与原始 sources.list 一致' \
  "$(dirname "${MANIFEST}")/files/etc/apt/sources.list" "${TMP}/expect/ubuntu-sources.list"
assert_files_equal '备份内容与原始 ubuntu.sources 一致' \
  "$(dirname "${MANIFEST}")/files/etc/apt/sources.list.d/ubuntu.sources" "${TMP}/expect/ubuntu.sources"

cp "${SL}" "${TMP}/expect/ubuntu-after-1.list"
run_cn --root="${R}" --mirror=tuna --components=os --yes
assert_rc 0 '重复执行（同镜像）成功'
assert_contains '重复执行提示已是最新' '已是最新'
assert_files_equal '重复执行文件内容不变' "${SL}" "${TMP}/expect/ubuntu-after-1.list"
BK_COUNT2="$(backup_count "${R}")"
if [[ "${BK_COUNT2}" == '1' ]]; then ok '重复执行不产生新备份（幂等）'; else bad "重复执行产生了额外备份：${BK_COUNT2}"; fi

# ── Debian：legacy sources.list + --restore 回原 ────────────────────────
section 'Debian（legacy）换源 / --restore 恢复'
R="${TMP}/debian"
write_file "${R}/etc/os-release" <<'EOF'
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
ID=debian
VERSION_ID="12"
VERSION_CODENAME=bookworm
EOF
write_file "${R}/etc/apt/sources.list" <<'EOF'
deb http://deb.debian.org/debian bookworm main contrib non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main
deb http://security.debian.org/debian-security bookworm-security main
EOF
cp "${R}/etc/apt/sources.list" "${TMP}/expect/debian-sources.list"
run_cn --root="${R}" --mirror=aliyun --components=os --yes
assert_rc 0 'Debian 换源成功'
assert_file_contains 'deb.debian.org → aliyun' "${R}/etc/apt/sources.list" 'http://mirrors.aliyun.com/debian bookworm main'
assert_file_contains 'security.debian.org → aliyun（debian-security 路径保留）' \
  "${R}/etc/apt/sources.list" 'mirrors.aliyun.com/debian-security bookworm-security'
assert_file_not_contains 'deb.debian.org 不再出现' "${R}/etc/apt/sources.list" 'deb.debian.org'

run_cn --root="${R}" --restore
assert_rc 0 '--restore 成功'
assert_files_equal '--restore 恢复为原始 sources.list' "${R}/etc/apt/sources.list" "${TMP}/expect/debian-sources.list"
assert_contains '--restore 打印恢复日志' '已恢复'

# ── Fedora：dnf repo 改写（已知 repo 映射、未知 repo 保持原样）─────────
section 'Fedora（dnf）换源 / 未知 repo 保持原样 / 幂等'
R="${TMP}/fedora"
write_file "${R}/etc/os-release" <<'EOF'
PRETTY_NAME="Fedora Linux 41 (Server Edition)"
ID=fedora
VERSION_ID=41
EOF
write_file "${R}/etc/yum.repos.d/fedora.repo" <<'EOF'
[fedora]
name=Fedora $releasever - $basearch
#baseurl=http://download.example/pub/fedora/linux/releases/$releasever/Everything/$basearch/os/
metalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-$releasever&arch=$basearch
enabled=1
gpgcheck=1

[updates]
name=Fedora $releasever - $basearch - Updates
metalink=https://mirrors.fedoraproject.org/metalink?repo=updates-released-f$releasever&arch=$basearch
enabled=1

[fedora-cisco-openh264]
name=Fedora $releasever openh264 (from Cisco) - $basearch
metalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-cisco-openh264-$releasever&arch=$basearch
enabled=1
EOF
write_file "${R}/etc/yum.repos.d/vendor.repo" <<'EOF'
[vendor-tool]
name=Vendor Tool
baseurl=https://packages.vendor.example/tool/x86_64/
enabled=1
EOF
cp "${R}/etc/yum.repos.d/vendor.repo" "${TMP}/expect/vendor.repo"
run_cn --root="${R}" --mirror=ustc --components=os --yes
assert_rc 0 'Fedora 换源成功'
FR="${R}/etc/yum.repos.d/fedora.repo"
assert_file_contains 'fedora 主仓库 baseurl 指向 ustc' "${FR}" \
  'baseurl=https://mirrors.ustc.edu.cn/fedora/releases/$releasever/Everything/$basearch/os/'
assert_file_contains 'updates 仓库 baseurl 指向 ustc' "${FR}" \
  'baseurl=https://mirrors.ustc.edu.cn/fedora/updates/$releasever/Everything/$basearch/'
assert_file_contains 'fedora-cisco-openh264 单独映射' "${FR}" \
  'baseurl=https://mirrors.ustc.edu.cn/fedora/fedora-cisco-openh264/releases/$releasever/Everything/$basearch/os/'
assert_file_contains 'metalink 被注释掉' "${FR}" '#metalink='
if grep -qE '^metalink=' "${FR}" 2>/dev/null; then
  bad '仍存在未注释的 metalink= 行（会继续走官方源）'
else
  ok '没有未注释的 metalink= 行（会走镜像 baseurl）'
fi
assert_files_equal '未知 repo（vendor.repo）保持原样' "${R}/etc/yum.repos.d/vendor.repo" "${TMP}/expect/vendor.repo"
assert_contains '未知 repo 有中文警告' '未知 repo'
assert_file_contains '备份清单记录 fedora.repo' \
  "$(ls -1 "${R}/var/backups/webkvm-cn-mirrors"/*/manifest.tsv | head -1)" '/etc/yum.repos.d/fedora.repo'
BK_F1="$(backup_count "${R}")"
run_cn --root="${R}" --mirror=ustc --components=os --yes
assert_rc 0 'Fedora 重复执行成功'
BK_F2="$(backup_count "${R}")"
if [[ "${BK_F1}" == "${BK_F2}" ]]; then ok 'Fedora 重复执行不产生新备份（幂等）'; else bad "Fedora 幂等失败：${BK_F1} → ${BK_F2}"; fi

# ── Arch：pacman mirrorlist 托管块 ──────────────────────────────────────
section 'Arch（pacman）换源 / 切换镜像 / 幂等'
R="${TMP}/arch"
write_file "${R}/etc/os-release" <<'EOF'
NAME="Arch Linux"
PRETTY_NAME="Arch Linux"
ID=arch
EOF
write_file "${R}/etc/pacman.d/mirrorlist" <<'EOF'
##
## Arch Linux repository mirrorlist
##

#Server = https://mirror.example.org/archlinux/$repo/os/$arch
Server = https://mirror.example.org/archlinux/$repo/os/$arch
EOF
ML="${R}/etc/pacman.d/mirrorlist"
run_cn --root="${R}" --mirror=huawei --components=os --yes
assert_rc 0 'Arch 换源成功'
assert_file_contains 'mirrorlist 写入 huawei Server' "${ML}" \
  'Server = https://repo.huaweicloud.com/archlinux/$repo/os/$arch'
assert_file_contains '托管块开始标记' "${ML}" '# webkvm-cn-mirrors begin'
assert_file_contains '托管块结束标记' "${ML}" '# webkvm-cn-mirrors end'
assert_file_contains '原 mirrorlist 注释行保留' "${ML}" '## Arch Linux repository mirrorlist'
assert_file_contains '原 Server 行保留在托管块之后' "${ML}" 'Server = https://mirror.example.org/archlinux/$repo/os/$arch'
BK_A1="$(backup_count "${R}")"
run_cn --root="${R}" --mirror=huawei --components=os --yes
BK_A2="$(backup_count "${R}")"
assert_rc 0 'Arch 重复执行成功'
if [[ "${BK_A1}" == "${BK_A2}" ]]; then ok 'Arch 重复执行不产生新备份（幂等）'; else bad "Arch 幂等失败：${BK_A1} → ${BK_A2}"; fi
run_cn --root="${R}" --mirror=aliyun --components=os --yes
assert_rc 0 'Arch 切换镜像成功'
assert_file_contains '切换后使用 aliyun' "${ML}" 'Server = https://mirrors.aliyun.com/archlinux/$repo/os/$arch'
assert_file_not_contains '旧 huawei 托管块被移除' "${ML}" 'repo.huaweicloud.com'
BEGIN_COUNT="$(grep -c '^# webkvm-cn-mirrors begin' "${ML}" 2>/dev/null || true)"
if [[ "${BEGIN_COUNT}" == '1' ]]; then ok '切换镜像后只保留 1 个托管块'; else bad "托管块数量应为 1，实际 ${BEGIN_COUNT}"; fi
BK_A3="$(backup_count "${R}")"
if [[ "${BK_A3}" == '2' ]]; then ok '切换镜像产生新备份（可回滚）'; else bad "切换镜像后备份数应为 2，实际 ${BK_A3}"; fi

# ── 工具配置组件（假根目录中的假可执行文件）────────────────────────────
section 'pip / npm / go / cargo / git / docker 组件（模拟根目录）'
R="${TMP}/tools"
write_file "${R}/etc/os-release" <<'EOF'
PRETTY_NAME="Ubuntu 24.04 LTS"
ID=ubuntu
VERSION_ID="24.04"
EOF
mkdir -p "${R}/usr/bin"
for tool in python3 npm go cargo git; do
  printf '#!/bin/sh\nexit 0\n' >"${R}/usr/bin/${tool}"
  chmod 0755 "${R}/usr/bin/${tool}"
done
run_cn --root="${R}" --mirror=tencent \
  --components=pip,npm,go,cargo,git,docker \
  --docker-mirror=https://docker.m.daocloud.io \
  --github-proxy=https://ghfast.top/ --yes
assert_rc 0 '工具组件换源成功'
assert_file_contains 'pip.conf 指向 tencent pypi' "${R}/root/.config/pip/pip.conf" \
  'index-url = https://mirrors.cloud.tencent.com/pypi/simple'
assert_file_contains 'pip.conf trusted-host 正确' "${R}/root/.config/pip/pip.conf" \
  'trusted-host = mirrors.cloud.tencent.com'
assert_file_contains '.npmrc 指向 npmmirror' "${R}/root/.npmrc" 'registry=https://registry.npmmirror.com'
assert_file_contains 'go env 写入 GOPROXY' "${R}/root/.config/go/env" 'GOPROXY=https://goproxy.cn,direct'
assert_file_contains 'cargo 使用 rsproxy sparse' "${R}/root/.cargo/config.toml" 'sparse+https://rsproxy.cn/index/'
assert_file_contains '.gitconfig 写入 github insteadOf' "${R}/root/.gitconfig" \
  '[url "https://ghfast.top/https://github.com/"]'
assert_file_contains 'daemon.json 写入 registry-mirrors' "${R}/etc/docker/daemon.json" 'https://docker.m.daocloud.io'
assert_contains 'git 打印一次性 URL 重写用法' 'git clone https://ghfast.top/https://github.com/'
BK_T1="$(backup_count "${R}")"
run_cn --root="${R}" --mirror=tencent \
  --components=pip,npm,go,cargo,git,docker \
  --docker-mirror=https://docker.m.daocloud.io \
  --github-proxy=https://ghfast.top/ --yes
BK_T2="$(backup_count "${R}")"
assert_rc 0 '工具组件重复执行成功'
if [[ "${BK_T1}" == "${BK_T2}" ]]; then ok '工具组件重复执行不产生新备份（幂等）'; else bad "工具组件幂等失败：${BK_T1} → ${BK_T2}"; fi

if command -v python3 >/dev/null 2>&1; then
  R="${TMP}/docker-merge"
  write_file "${R}/etc/os-release" <<'EOF'
ID=ubuntu
PRETTY_NAME="Ubuntu 24.04"
EOF
  write_file "${R}/etc/docker/daemon.json" <<'EOF'
{
  "log-driver": "json-file",
  "registry-mirrors": ["https://old-mirror.example"]
}
EOF
  run_cn --root="${R}" --mirror=tuna --components=docker \
    --docker-mirror=https://dockerproxy.com --yes
  assert_rc 0 'docker daemon.json 合并成功'
  assert_file_contains '合并保留原有 registry-mirrors' "${R}/etc/docker/daemon.json" 'https://old-mirror.example'
  assert_file_contains '合并写入新 registry-mirrors' "${R}/etc/docker/daemon.json" 'https://dockerproxy.com'
  assert_file_contains '合并保留其它 JSON 键' "${R}/etc/docker/daemon.json" '"log-driver": "json-file"'
else
  printf 'SKIP: 未找到 python3，跳过 daemon.json 合并用例\n'
fi

# ── --dry-run：不得写任何文件 ───────────────────────────────────────────
section '--dry-run 不产生任何写入'
R="${TMP}/dryrun"
write_file "${R}/etc/os-release" <<'EOF'
PRETTY_NAME="Ubuntu 24.04 LTS"
ID=ubuntu
VERSION_ID="24.04"
EOF
write_file "${R}/etc/apt/sources.list" <<'EOF'
deb http://archive.ubuntu.com/ubuntu noble main
EOF
cp "${R}/etc/apt/sources.list" "${TMP}/expect/dryrun-sources.list"
run_cn --root="${R}" --mirror=tuna --components=os,docker \
  --docker-mirror=https://docker.m.daocloud.io --dry-run --yes
assert_rc 0 '--dry-run 退出码为 0'
assert_contains '--dry-run 打印将执行的操作' '[dry-run] 将'
assert_files_equal '--dry-run 未修改 sources.list' "${R}/etc/apt/sources.list" "${TMP}/expect/dryrun-sources.list"
assert_path_absent '--dry-run 未创建备份目录' "${R}/var"
assert_path_absent '--dry-run 未创建 docker 目录' "${R}/etc/docker"
assert_path_absent '--dry-run 未创建用户配置目录' "${R}/root"

run_cn --root="${R}" --dry-run
assert_rc 0 '--dry-run（默认组件，auto 镜像）退出码为 0'
assert_path_absent '--dry-run 默认组件也不写文件' "${R}/root"

# ── 边界：无备份可恢复 / 缺 os-release ─────────────────────────────────
section '边界情况'
R="${TMP}/nobackup"
mkdir -p "${R}"
run_cn --root="${R}" --restore
assert_rc 1 '没有备份时 --restore 退出码为 1'
assert_contains '没有备份时有中文提示' '没有找到备份目录'

R="${TMP}/nosos"
mkdir -p "${R}"
run_cn --root="${R}" --components=os --mirror=tuna
assert_rc 1 '缺少 os-release 时退出码为 1'
assert_contains '缺少 os-release 提示清晰' 'etc/os-release'

# ── 汇总 ────────────────────────────────────────────────────────────────
echo ''
echo "──────────────────────────────────────────────"
printf '%d passed, %d failed\n' "${PASS}" "${FAIL}"
if [[ "${FAIL}" -eq 0 ]]; then
  echo '全部 PASS'
  exit 0
fi
echo '存在失败项' >&2
exit 1
