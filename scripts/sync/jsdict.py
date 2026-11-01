"""Shared helpers for the sync scripts that touch i18n.svelte.js.

The message dictionaries are plain JS object literals (no functions), so they
can be extracted with a string/comment-aware brace scanner and evaluated with
node exactly like the app does (see scripts/check-i18n.mjs for the same trick).
"""
from __future__ import annotations

import json
import re
import subprocess


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


def extract_messages(src: str) -> tuple[str, int, int] | None:
    """Locate the `export const messages = { ... }` object."""
    m = re.search(r"export const messages\s*=\s*\{", src)
    if not m:
        return None
    start = src.index("{", m.start())
    i = start
    depth = 0
    quote: str | None = None
    escape = False
    while i < len(src):
        c = src[i]
        nxt = src[i + 1] if i + 1 < len(src) else ""
        if quote:
            if escape:
                escape = False
            elif c == "\\":
                escape = True
            elif c == quote:
                quote = None
            i += 1
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
    """Evaluate a JS object literal with node (same parser as the app)."""
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


def deep_merge(ours, upstream):
    """Merge dicts: upstream values win on existing keys; ours-only keys survive."""
    if not isinstance(ours, dict) or not isinstance(upstream, dict):
        return upstream
    out = {}
    for k in upstream:
        if k in ours and isinstance(ours[k], dict) and isinstance(upstream[k], dict):
            out[k] = deep_merge(ours[k], upstream[k])
        else:
            out[k] = upstream[k]
    for k in ours:
        if k not in out:
            out[k] = ours[k]
    return out
