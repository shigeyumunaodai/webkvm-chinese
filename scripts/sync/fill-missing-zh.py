#!/usr/bin/env python3
"""Fill Chinese locale keys added by upstream with English fallbacks.

After merging upstream, `frontend/src/lib/i18n.svelte.js` may contain new
en/es/ca keys that do not exist in the zh dictionary yet. This script:

  1. adds every missing zh key using the English text as a temporary fallback
     (so the UI falls back to English instead of showing the raw key and
     `scripts/check-i18n.sh` keeps passing), and
  2. removes zh keys that upstream deleted (the checker requires exact
     symmetry), and
  3. writes a translation-backlog report for the operator/LLM to translate
     later (new keys + upstream docs that have no docs/zh mirror yet).

It only rewrites the `zh` object inside i18n.svelte.js; run prettier afterwards
(the Sync upstream workflow does this automatically).
"""
from __future__ import annotations

import datetime as _dt
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(
    subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True
    ).stdout.strip()
)
I18N = ROOT / "frontend" / "src" / "lib" / "i18n.svelte.js"
REPORT_DIR = Path(os.environ.get("REPORT_DIR", "/tmp"))


def extract_object(src: str, key: str) -> tuple[str, int, int] | None:
    """Return (object_text, start, end) for `key: { ... }` (strings/comments aware)."""
    m = re.search(rf"\b{re.escape(key)}\s*:\s*\{{", src)
    if not m:
        return None
    start = src.index("{", m.start())
    i = start
    depth = 0
    quote: str | None = None
    escape = False
    line_comment = False
    block_comment = False
    while i < len(src):
        c = src[i]
        nxt = src[i + 1] if i + 1 < len(src) else ""
        if line_comment:
            if c == "\n":
                line_comment = False
            i += 1
            continue
        if block_comment:
            if c == "*" and nxt == "/":
                block_comment = False
                i += 2
                continue
            i += 1
            continue
        if quote:
            if escape:
                escape = False
            elif c == "\\":
                escape = True
            elif c == quote:
                quote = None
            i += 1
            continue
        if c == "/" and nxt == "/":
            line_comment = True
            i += 2
            continue
        if c == "/" and nxt == "*":
            block_comment = True
            i += 2
            continue
        if c in ("'", '"', "`"):
            quote = c
            i += 1
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return src[start : i + 1], start, i + 1
        i += 1
    return None


def eval_literal(text: str):
    """Evaluate the JS object literal with node (same parser as the app)."""
    node = subprocess.run(
        [
            "node",
            "-e",
            "const fs=require('fs');const t=fs.readFileSync(0,'utf8');"
            "console.log(JSON.stringify(Function('return ('+t+')')()));",
        ],
        input=text,
        capture_output=True,
        text=True,
        check=False,
    )
    if node.returncode != 0:
        raise RuntimeError(f"cannot evaluate dictionary with node: {node.stderr.strip()}")
    return json.loads(node.stdout)


def flatten(obj, prefix="", out=None):
    out = {} if out is None else out
    for k, v in obj.items():
        path = f"{prefix}.{k}" if prefix else k
        if isinstance(v, dict):
            flatten(v, path, out)
        else:
            out[path] = v
    return out


def set_path(obj, path: str, value) -> None:
    parts = path.split(".")
    node = obj
    for p in parts[:-1]:
        if p not in node or not isinstance(node[p], dict):
            node[p] = {}
        node = node[p]
    node[parts[-1]] = value


def del_path(obj, path: str) -> None:
    parts = path.split(".")
    node = obj
    for p in parts[:-1]:
        node = node.get(p)
        if not isinstance(node, dict):
            return
    node.pop(parts[-1], None)


def serialize(value, depth: int) -> str:
    pad = "  " * depth
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (int, float, bool)) or value is None:
        return json.dumps(value)
    if isinstance(value, list):
        items = [f"{pad}  {serialize(v, depth + 1)}," for v in value]
        return "[\n" + "\n".join(items) + f"\n{pad}]"
    if not value:
        return "{}"
    lines = []
    for k, v in value.items():
        key = k if re.match(r"^[A-Za-z_$][A-Za-z0-9_$]*$", k) else json.dumps(k)
        lines.append(f"{pad}  {key}: {serialize(v, depth + 1)},")
    return "{\n" + "\n".join(lines) + f"\n{pad}}}"


def main() -> int:
    src = I18N.read_text(encoding="utf-8")
    dicts = {}
    for lang in ("en", "es", "ca", "zh"):
        found = extract_object(src, lang)
        if not found:
            print(f"fill-missing-zh: ERROR: messages.{lang} block not found", file=sys.stderr)
            return 1
        dicts[lang] = eval_literal(found[0])

    en = flatten(dicts["en"])
    zh = dicts["zh"]
    zh_flat = flatten(zh)

    missing = [k for k in en if k not in zh_flat]
    extra = [k for k in zh_flat if k not in en]
    for key in missing:
        set_path(zh, key, en[key])
    for key in extra:
        del_path(zh, key)

    if missing or extra:
        found = extract_object(src, "zh")
        assert found is not None
        _, start, end = found
        src = src[:start] + serialize(zh, 1) + src[end:]
        I18N.write_text(src, encoding="utf-8")

    # ---- translation backlog -------------------------------------------------
    missing_docs: list[str] = []
    docs = ROOT / "docs"
    zh_docs = docs / "zh"
    for f in sorted(docs.rglob("*.md")):
        rel = f.relative_to(docs)
        if rel.parts and rel.parts[0] == "zh":
            continue
        if f.name.endswith(".es.md"):
            continue
        if not (zh_docs / rel).exists():
            missing_docs.append(str(rel))
    if not (ROOT / "README.zh.md").exists():
        missing_docs.append("README.md")

    if missing or extra or missing_docs:
        REPORT_DIR.mkdir(parents=True, exist_ok=True)
        report = [
            "# 上游同步翻译待办",
            "",
            f"- 时间: {_dt.datetime.now(_dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}",
            "",
        ]
        if missing:
            report += [
                f"## 新增英文键（{len(missing)} 个，已临时填入英文，需翻译为中文）",
                "",
                "位置：`frontend/src/lib/i18n.svelte.js` 的 `messages.zh`。",
                "",
                "```text",
                *missing[:400],
                "```" if len(missing) <= 400 else "```\n... (truncated)",
                "",
            ]
        if extra:
            report += [
                f"## 上游已删除的旧 zh 键（{len(extra)} 个，已自动清理）",
                "",
                "```text",
                *extra[:200],
                "```",
                "",
            ]
        if missing_docs:
            report += [
                f"## 缺少中文镜像的上游文档（{len(missing_docs)} 个）",
                "",
                "上游新增/重命名了以下文档，`docs/zh/` 尚无对应中文版：",
                "",
                "```text",
                *missing_docs,
                "```",
                "",
            ]
        (REPORT_DIR / "translation-backlog.md").write_text(
            "\n".join(report) + "\n", encoding="utf-8"
        )

    print(
        "fill-missing-zh: "
        f"missing={len(missing)} extra={len(extra)} missing_docs={len(missing_docs)}"
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"fill-missing-zh: FATAL: {exc}", file=sys.stderr)
        sys.exit(1)
