#!/usr/bin/env bash
# Merge the upstream project into the current branch while keeping the
# Simplified-Chinese localization of this fork.
#
# Exit codes:
#   0  merged (or already up to date)
#   1  fatal error
#   2  merge conflicts that could not be auto-resolved (merge aborted)
#
# Environment:
#   UPSTREAM_URL        upstream Git URL (default: official repo)
#   UPSTREAM_FETCH_URL  optional URL used only for fetching (e.g. a GitHub
#                       proxy to use from mainland China); the upstream remote
#                       keeps UPSTREAM_URL for reference/CI parity
#   UPSTREAM_BRANCH     default: main
#   DRY_RUN=1           test the merge, then roll it back
#   REPORT_DIR          where to write the report (default: /tmp)
#
# What is auto-resolved when conflicts appear:
#   - fork-owned files in .gitattributes (docs/zh, README.zh, sync scripts...)
#   - human docs where we only add the language-nav line / README notes
#   - CHANGELOG/AGENTS/.env.example/ci.yml/release.yml re-apply bits
# Anything else (frontend source, installer, Makefile...) is reported as
# unresolved and must be resolved by a human; the workflow opens an issue.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "[sync-upstream] ERROR: not inside a git working tree" >&2
  exit 1
}
cd "${ROOT}"

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/Slaker19/webkvm.git}"
UPSTREAM_FETCH_URL="${UPSTREAM_FETCH_URL:-${UPSTREAM_URL}}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
DRY_RUN="${DRY_RUN:-0}"
REPORT_DIR="${REPORT_DIR:-/tmp}"
mkdir -p "${REPORT_DIR}"
REPORT="${REPORT_DIR}/.sync-upstream-report.md"
: >"${REPORT}"

log() { printf '[sync-upstream] %s\n' "$*"; }
report() { printf '%s\n' "$*" >>"${REPORT}"; }
fail() {
  log "ERROR: $*"
  report "ERROR: $*"
  exit 1
}

write_header() {
  {
    echo "# Upstream sync report"
    echo
    echo "- UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- Branch: $(git rev-parse --abbrev-ref HEAD)"
    echo "- Upstream: ${UPSTREAM_URL} (${UPSTREAM_BRANCH})"
    echo "- DRY_RUN: ${DRY_RUN}"
    echo
  } >"${REPORT}"
}

write_header

# A dirty tree makes a partial merge impossible to undo safely.
if ! git diff --quiet || ! git diff --cached --quiet; then
  fail "working tree is dirty; commit or stash your changes first"
fi
if [[ -d .git/rebase-merge || -d .git/rebase-apply || -f .git/MERGE_HEAD ]]; then
  fail "another merge/rebase is in progress"
fi

if ! git config user.name >/dev/null 2>&1 || [[ -z "$(git config user.name)" ]]; then
  git config user.name "webkvm-zh sync bot"
fi
if ! git config user.email >/dev/null 2>&1 || [[ -z "$(git config user.email)" ]]; then
  git config user.email "webkvm-zh@users.noreply.github.com"
fi

# Required by .gitattributes: on conflict, fork-owned files keep our version.
git config merge.ours.driver true

if git remote get-url upstream >/dev/null 2>&1; then
  git remote set-url upstream "${UPSTREAM_URL}"
else
  git remote add upstream "${UPSTREAM_URL}"
fi

log "fetching upstream from ${UPSTREAM_FETCH_URL}"
if ! git fetch --no-tags "${UPSTREAM_FETCH_URL}" \
  "+refs/heads/*:refs/remotes/upstream/*" 2>&1 | sed 's/^/[sync-upstream]   /'; then
  fail "git fetch failed (from mainland China try UPSTREAM_FETCH_URL=https://gh-proxy.com/https://github.com/Slaker19/webkvm.git)"
fi
git fetch --tags --force upstream >/dev/null 2>&1 || true

UPSTREAM_REF="refs/remotes/upstream/${UPSTREAM_BRANCH}"
git rev-parse --verify "${UPSTREAM_REF}" >/dev/null 2>&1 || fail "upstream branch ${UPSTREAM_BRANCH} not found"
target="$(git rev-parse --short "${UPSTREAM_REF}")"
subject="$(git log -1 --format=%s "${UPSTREAM_REF}")"
log "upstream tip: ${target} ${subject}"
report "- Upstream tip: \`${target}\` ${subject}"

if git merge-base --is-ancestor "${UPSTREAM_REF}" HEAD; then
  log "already up to date — nothing to merge"
  report "- Result: already up to date"
  exit 0
fi

log "merging ${UPSTREAM_REF} (${target})"
if git merge --no-edit -m "chore(sync): merge upstream Slaker19/webkvm@${target}" "${UPSTREAM_REF}"; then
  log "merge completed without conflicts"
  report "- Result: merged cleanly"
  report ""
  report "## Diffstat"
  report '```text'
  git diff --stat ORIG_HEAD..HEAD | tail -40 >>"${REPORT}"
  report '```'
  if [[ "${DRY_RUN}" == "1" ]]; then
    git reset --hard ORIG_HEAD >/dev/null
    log "DRY_RUN: merge rolled back"
    report "- DRY_RUN: rolled back"
  fi
  exit 0
fi

# Conflict (or an unrelated merge failure): distinguish by MERGE_HEAD.
if [[ ! -f .git/MERGE_HEAD ]]; then
  fail "git merge failed without creating a merge state (see output above)"
fi

git diff --name-only --diff-filter=U > "${REPORT_DIR}/sync-conflicts.txt" || true
log "conflicts in $(wc -l <"${REPORT_DIR}/sync-conflicts.txt" | tr -d ' ') file(s); trying auto-resolution"
python3 scripts/sync/resolve-conflicts.py
rc=$?
if [[ "${rc}" -ne 0 ]]; then
  if [[ "${rc}" != "2" ]]; then
    git merge --abort >/dev/null 2>&1 || true
    fail "auto-resolution script crashed"
  fi
  {
    echo "- Result: **conflicts need manual resolution**"
    echo
    echo "## Unresolved files"
    echo '```text'
    cat "${REPORT_DIR}/sync-unresolved.txt" 2>/dev/null || cat "${REPORT_DIR}/sync-conflicts.txt"
    echo '```'
    echo
    echo "## How to resolve locally"
    echo '```bash'
    echo 'git checkout main && git pull'
    echo 'UPSTREAM_FETCH_URL=https://gh-proxy.com/https://github.com/Slaker19/webkvm.git \'
    echo '  bash scripts/sync/sync-upstream.sh'
    echo '# resolve the files above in your editor, then:'
    echo 'git add -A && git commit --no-edit && git push origin main'
    echo '```'
  } >>"${REPORT}"
  git merge --abort >/dev/null 2>&1 || true
  log "unresolved conflicts — merge aborted; see ${REPORT}"
  exit 2
fi

if ! git diff --name-only --diff-filter=U | grep -q .; then
  # Format the semantically merged dictionary before committing so the merge
  # commit stays small (the sync workflow installs frontend deps first).
  PRETTIER="${ROOT}/frontend/node_modules/.bin/prettier"
  if [[ -x "${PRETTIER}" ]]; then
    ( cd frontend && ./node_modules/.bin/prettier --write src/lib/i18n.svelte.js >/dev/null 2>&1 ) || true
  fi
  git add -A
  if git commit --no-edit >/dev/null; then
    log "merge committed with auto-resolution"
  else
    fail "could not commit the auto-resolved merge"
  fi
else
  git merge --abort >/dev/null 2>&1 || true
  fail "auto-resolution left conflicted files"
fi

{
  echo "- Result: merged with auto-resolution"
  echo
  echo "## Auto-resolved files"
  echo '```text'
  cat "${REPORT_DIR}/sync-resolved.txt" 2>/dev/null || true
  echo '```'
  echo
  echo "## Diffstat"
  echo '```text'
  git diff --stat ORIG_HEAD..HEAD | tail -40
  echo '```'
} >>"${REPORT}"

if [[ "${DRY_RUN}" == "1" ]]; then
  git reset --hard ORIG_HEAD >/dev/null
  log "DRY_RUN: merge rolled back"
  report "- DRY_RUN: rolled back"
fi
exit 0
