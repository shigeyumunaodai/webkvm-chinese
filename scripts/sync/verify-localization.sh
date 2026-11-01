#!/usr/bin/env bash
# Sanity checks for the localized fork after an upstream sync:
#   - localized files still present
#   - zh locale still registered
#   - four-language i18n key symmetry / zh placeholders (scripts/check-i18n.mjs)
#   - no Git conflict markers left in tracked files
#
# Run from the repo root (the Sync upstream workflow does this after auto-fill).
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "${ROOT}"

fail=0
for f in \
  frontend/src/lib/i18n.svelte.js \
  README.zh.md \
  docs/zh/README.md \
  docs/zh/DEPLOYMENT.md \
  docs/zh/CHINA-NETWORK.md \
  scripts/cn-mirrors.sh \
  scripts/qa/test-cn-mirrors.sh; do
  if [[ ! -f "${f}" ]]; then
    echo "verify-localization: MISSING ${f}" >&2
    fail=1
  fi
done
if [[ "${fail}" -ne 0 ]]; then
  exit 1
fi

grep -q "code: 'zh'" frontend/src/lib/i18n.svelte.js || {
  echo "verify-localization: zh locale is not registered in LOCALES" >&2
  exit 1
}
grep -q "简体中文" README.zh.md || {
  echo "verify-localization: README.zh.md lost its Chinese content?" >&2
  exit 1
}

if git grep -q -E '^(<<<<<<<|>>>>>>>) ' -- . 2>/dev/null; then
  echo "verify-localization: conflict markers left in tracked files:" >&2
  git grep -l -E '^(<<<<<<<|>>>>>>>) ' -- . >&2 || true
  exit 1
fi

node scripts/check-i18n.mjs

echo "verify-localization: OK"
