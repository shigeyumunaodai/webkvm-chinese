#!/usr/bin/env python3
"""Semantic merge for `frontend/src/lib/i18n.svelte.js` during an upstream merge.

`i18n.svelte.js` is by far the most conflict-prone file when upstream adds
translation keys (it is a 15k-line dictionary). Instead of dumping a huge
conflict on the operator, this script reconstructs it:

  * start from the upstream version (theirs) — code, helpers and all en/es/ca
    dictionaries as upstream intends them;
  * deep-merge this fork's dictionaries into it: upstream values win for keys
    upstream provides, fork-only keys (the localization string migrations) are
    kept, and the whole `zh` dictionary is kept from this fork;
  * re-apply the four small code changes the fork owns in this file
    (LOCALES zh entry, <html lang> helpers, setLocale hook, initial lang call).

New upstream keys missing from zh are filled afterwards by
`scripts/sync/fill-missing-zh.py` (English fallback) and prettier formats the
result. Called by scripts/sync/resolve-conflicts.py.
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

from jsdict import (  # noqa: E402
    deep_merge,
    eval_literal,
    extract_messages,
    extract_object,
    serialize,
)

PATH = "frontend/src/lib/i18n.svelte.js"
ROOT = Path(
    subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True
    ).stdout.strip()
)
FILE = ROOT / PATH

DOC_LANG_HELPERS = """
// Keep <html lang> in sync with the selected UI language. Besides being
// the accessible/correct thing to do, browsers use it to pick the CJK
// font stack, line-breaking rules and spell-check language — without it
// Chinese text renders with the Latin font's fallback metrics.
function documentLangFor(code) {
  return code === 'zh' ? 'zh-CN' : code;
}

function applyDocumentLang(code) {
  if (typeof document === 'undefined' || !document.documentElement) return;
  document.documentElement.lang = documentLangFor(code);
}
"""


def git_show(stage_and_path: str) -> str:
    r = subprocess.run(["git", "show", stage_and_path], cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"git show {stage_and_path} failed: {r.stderr.strip()}")
    return r.stdout


def parse_messages(src: str) -> dict:
    found = extract_messages(src)
    if not found:
        raise RuntimeError("messages object not found")
    return eval_literal(found[0])


def replace_messages(src: str, messages: dict) -> str:
    found = extract_messages(src)
    if not found:
        raise RuntimeError("messages object not found")
    _, start, end = found
    body = serialize(messages, 0)
    return src[:start] + body + src[end:]


def ensure_locales(src: str) -> str:
    if "{ code: 'zh'," in src:
        return src
    # insert after the ca entry, else before the array closer
    m = re.search(r"(\n  \{ code: 'ca', label: '[^']*' \},)", src)
    if m:
        return src[: m.end(1)] + "\n  { code: 'zh', label: '简体中文' }," + src[m.end(1) :]
    m = re.search(r"\n\];", src)
    if not m:
        raise RuntimeError("LOCALES array not found")
    return src[: m.start()] + "\n  { code: 'zh', label: '简体中文' }," + src[m.start() :]


def ensure_helpers(src: str) -> str:
    if "function applyDocumentLang(" in src:
        return src
    anchor = "export function getLocale()"
    idx = src.find(anchor)
    if idx == -1:
        raise RuntimeError("getLocale anchor not found")
    return src[:idx] + DOC_LANG_HELPERS.lstrip("\n") + "\n" + src[idx:]


def ensure_set_locale_hook(src: str) -> str:
    if "applyDocumentLang(code);" in src:
        return src
    m = re.search(r"(\n  safeStorage\.setItem\('webkvm\.locale', code\);)", src)
    if not m:
        raise RuntimeError("setLocale hook anchor not found")
    return src[: m.end(1)] + "\n  applyDocumentLang(code);" + src[m.end(1) :]


def ensure_initial_call(src: str) -> str:
    if "applyDocumentLang(current);" in src:
        return src
    m = re.search(r"(let current = \$state\(load\(\)\);)", src)
    if not m:
        raise RuntimeError("current state anchor not found")
    return src[: m.end(1)] + "\napplyDocumentLang(current);" + src[m.end(1) :]


def main() -> int:
    ours = git_show(f":2:{PATH}")
    theirs = git_show(f":3:{PATH}")
    ours_messages = parse_messages(ours)
    theirs_messages = parse_messages(theirs)

    merged = {}
    for lang in theirs_messages:
        if lang == "zh":
            merged[lang] = ours_messages.get("zh", theirs_messages[lang])
        else:
            merged[lang] = deep_merge(
                ours_messages.get(lang, {}), theirs_messages[lang]
            )
    # zh may only exist in ours (upstream has en/es/ca) — keep it last.
    if "zh" not in merged and "zh" in ours_messages:
        merged["zh"] = ours_messages["zh"]

    out = replace_messages(theirs, merged)
    out = ensure_locales(out)
    out = ensure_helpers(out)
    out = ensure_set_locale_hook(out)
    out = ensure_initial_call(out)
    FILE.write_text(out, encoding="utf-8")
    print(
        "merge-i18n: merged en/es/ca from upstream with fork-only keys; "
        f"kept zh ({len(merged.get('zh', {}))} sections)"
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"merge-i18n: FATAL: {exc}", file=sys.stderr)
        sys.exit(1)
