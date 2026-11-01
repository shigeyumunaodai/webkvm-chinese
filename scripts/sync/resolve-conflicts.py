#!/usr/bin/env python3
"""Auto-resolve the safe part of an upstream merge conflict.

Called by scripts/sync/sync-upstream.sh when `git merge upstream/main` stops
with conflicts. It resolves the *mechanical* conflicts (fork-owned
localization files, language-nav lines, CHANGELOG/AGENTS/.env/CI re-apply) and
leaves everything else untouched so the sync workflow can report those files
for manual resolution.

Exit codes: 0 = all conflicts resolved, 2 = some files still unresolved,
1 = unexpected error.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path


def git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", *args], cwd=ROOT, capture_output=True, text=True, check=False
    )


ROOT = Path(
    subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
)
FRAGMENTS = ROOT / "scripts" / "sync" / "fragments"
REPORT_DIR = Path(os.environ.get("REPORT_DIR", "/tmp"))
REPORT_DIR.mkdir(parents=True, exist_ok=True)

# Paths fully owned by this fork: always keep our side.
OWNED_DIRS = (
    "docs/zh/",
    "scripts/sync/",
)
OWNED_FILES = (
    "README.zh.md",
    "scripts/cn-mirrors.sh",
    "scripts/qa/test-cn-mirrors.sh",
    ".github/workflows/sync-upstream.yml",
    ".github/workflows/build-zh-release.yml",
)

# Documentation files whose only change from us is the language-nav line
# (plus a couple of README notes) — take upstream then re-apply our bits.
DOC_NAV_RE = re.compile(r"^\[?\*?\*?English\*?\*?\]?")
ES_LINK_RE = re.compile(r"\[(\*\*)?Español(\*\*)?\]\(([^)]+)\)")


def is_owned(path: str) -> bool:
    return path in OWNED_FILES or any(path.startswith(d) for d in OWNED_DIRS)


def checkout(side: str, path: str) -> None:
    """Take one side of a conflict (theirs = upstream)."""
    r = git("checkout", f"--{side}", "--", path)
    if r.returncode != 0:
        raise RuntimeError(f"cannot checkout --{side} for {path}: {r.stderr.strip()}")


def add(path: str) -> None:
    r = git("add", "--", path)
    if r.returncode != 0:
        raise RuntimeError(f"git add failed for {path}: {r.stderr.strip()}")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def nav_link_for(path: str) -> str:
    if path in ("README.md", "README.es.md"):
        return "README.zh.md"
    if path in ("SECURITY.md", "SECURITY.es.md"):
        return "docs/zh/SECURITY.md"
    if path.startswith("docs/runbooks/"):
        base = path.rsplit("/", 1)[1]
        base = re.sub(r"\.es\.md$", ".md", base)
        return f"../zh/runbooks/{base}"
    base = path.rsplit("/", 1)[1]
    base = re.sub(r"\.es\.md$", ".md", base)
    return f"zh/{base}"


README_NOTES = {
    "README.md": (
        "  - The installer binds to **127.0.0.1** by default. For LAN access pass "
        "`--bind=0.0.0.0`\n"
        "    (or a LAN IP) and keep HTTPS enabled, use an SSH tunnel, or put a TLS "
        "reverse\n"
        "    proxy in front. See [docs/zh/DEPLOYMENT.md](docs/zh/DEPLOYMENT.md) for "
        "details."
    ),
    "README.es.md": (
        "  - El instalador escucha en **127.0.0.1** por defecto. Para acceso desde la "
        "LAN pasa\n"
        "    `--bind=0.0.0.0` (o una IP de la LAN) y mantén HTTPS activo, usa un túnel "
        "SSH o\n"
        "    pon un proxy inverso TLS delante."
    ),
}


def reapply_readme_notes(path: str, text: str) -> str:
    note = README_NOTES.get(path)
    if not note:
        return text
    marker = "installer binds to **127.0.0.1**" if path == "README.md" else "instalador escucha en **127.0.0.1**"
    if marker in text:
        return text
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.lstrip().startswith("- URL:"):
            lines[i + 1 : i + 1] = ["", note]
            return "\n".join(lines) + "\n"
    return text


def reapply_doc_nav(path: str) -> str:
    p = ROOT / path
    text = p.read_text(encoding="utf-8")
    link = nav_link_for(path)
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if "[**English**]" in line and "Español" in line:
            if "简体中文" not in line:
                lines[i] = line.rstrip() + f" • [**简体中文**]({link})"
            text = "\n".join(lines) + "\n"
            text = reapply_readme_notes(path, text)
            write(path, text)
            return "nav"
    raise RuntimeError("no language-nav line found")


def reapply_agents() -> None:
    p = ROOT / "AGENTS.md"
    text = p.read_text(encoding="utf-8")
    marker = "## 9. Localización zh (fork)"
    if marker in text:
        return
    fragment = (FRAGMENTS / "agents-zh-section.md").read_text(encoding="utf-8").rstrip()
    text = text.rstrip() + "\n\n" + fragment + "\n"
    write("AGENTS.md", text)


def reapply_changelog(path: str) -> None:
    p = ROOT / path
    text = p.read_text(encoding="utf-8")
    lang = "es" if path.endswith(".es.md") else "en"
    fragment = (FRAGMENTS / f"changelog-unreleased.{lang}.md").read_text(encoding="utf-8").rstrip()
    if "## [Unreleased]" not in text:
        m = re.search(r"^## \[", text, re.MULTILINE)
        insert_at = m.start() if m else len(text)
        prefix = text[:insert_at]
        if prefix and not prefix.endswith("\n\n"):
            prefix = prefix.rstrip() + "\n\n"
        text = prefix + fragment + "\n\n" + text[insert_at:]
    if lang == "es":
        text = re.sub(
            r"^- \*\*Interfaz en .*?idiomas:\*\*.*$",
            "- **Interfaz en cuatro idiomas:** inglés, español, catalán y chino simplificado.",
            text,
            count=1,
            flags=re.MULTILINE,
        )
    else:
        text = re.sub(
            r"^- \*\*Interface in .*?languages:\*\*.*$",
            "- **Interface in four languages:** English, Spanish, Catalan and Simplified Chinese.",
            text,
            count=1,
            flags=re.MULTILINE,
        )
    write(path, text)


def reapply_env_example() -> None:
    p = ROOT / ".env.example"
    text = p.read_text(encoding="utf-8")
    marker = "# Mainland-China network acceleration (install-time only)"
    if marker in text:
        return
    block = (FRAGMENTS / "env-china-vars.txt").read_text(encoding="utf-8").rstrip()
    anchor = "\n# .env loading"
    if anchor in text:
        text = text.replace(anchor, "\n\n" + block + anchor, 1)
    else:
        text = text.rstrip() + "\n\n" + block + "\n"
    write(".env.example", text)


def reapply_ci() -> None:
    p = ROOT / ".github/workflows/ci.yml"
    text = p.read_text(encoding="utf-8")
    text = re.sub(
        r"i18n key symmetry \(en/es/ca(?:/zh)?\)",
        "i18n key symmetry (en/es/ca/zh)",
        text,
    )
    write(".github/workflows/ci.yml", text)


def reapply_release_workflow() -> None:
    p = ROOT / ".github/workflows/release.yml"
    text = p.read_text(encoding="utf-8")
    if "scripts/cn-mirrors.sh" in text:
        return
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if "scripts/install-webkvm.sh" in line:
            indent = line[: len(line) - len(line.lstrip())]
            lines.insert(i + 1, indent + "scripts/cn-mirrors.sh \\")
            write(".github/workflows/release.yml", "\n".join(lines) + "\n")
            return
    raise RuntimeError("install-webkvm.sh line not found in release.yml")


def reapply_changelog_dispatch(path: str) -> None:
    reapply_changelog(path)


def main() -> int:
    conflicted = [
        p
        for p in git("diff", "--name-only", "--diff-filter=U").stdout.splitlines()
        if p
    ]
    if not conflicted:
        print("resolve-conflicts: no conflicted files")
        return 0

    resolved: list[tuple[str, str]] = []
    unresolved: list[str] = []

    for path in conflicted:
        try:
            if is_owned(path):
                checkout("ours", path)
                add(path)
                resolved.append((path, "fork-owned (ours)"))
                continue
            if path == "AGENTS.md":
                checkout("theirs", path)
                reapply_agents()
                add(path)
                resolved.append((path, "upstream + fork section re-applied"))
                continue
            if path in ("CHANGELOG.md", "CHANGELOG.es.md"):
                checkout("theirs", path)
                reapply_changelog(path)
                add(path)
                resolved.append((path, "upstream + Unreleased section re-applied"))
                continue
            if path == ".env.example":
                checkout("theirs", path)
                reapply_env_example()
                add(path)
                resolved.append((path, "upstream + China install vars re-applied"))
                continue
            if path == "frontend/src/lib/i18n.svelte.js":
                # The 15k-line dictionary conflicts on almost every upstream
                # translation update — merge it semantically instead of asking
                # a human to resolve thousands of lines.
                r = subprocess.run(
                    ["python3", "scripts/sync/merge-i18n.py"],
                    cwd=ROOT,
                    capture_output=True,
                    text=True,
                )
                if r.returncode != 0:
                    raise RuntimeError(
                        "semantic i18n merge failed: " + (r.stderr or r.stdout).strip()
                    )
                add(path)
                resolved.append((path, "semantic i18n merge (upstream en/es/ca + fork zh)"))
                continue
            if path == ".github/workflows/ci.yml":
                checkout("theirs", path)
                reapply_ci()
                add(path)
                resolved.append((path, "upstream + zh i18n CI step re-applied"))
                continue
            if path == ".github/workflows/release.yml":
                checkout("theirs", path)
                reapply_release_workflow()
                add(path)
                resolved.append((path, "upstream + cn-mirrors tarball line re-applied"))
                continue
            if (
                path in ("README.md", "README.es.md", "SECURITY.md", "SECURITY.es.md")
                or path.startswith("docs/runbooks/")
                or (
                    path.startswith("docs/")
                    and path.endswith(".md")
                    and not path.startswith("docs/zh/")
                )
            ):
                checkout("theirs", path)
                reapply_doc_nav(path)
                add(path)
                resolved.append((path, "upstream + language-nav link re-applied"))
                continue
            unresolved.append(path)
        except Exception as exc:  # noqa: BLE001 - report, don't crash the sync
            print(f"resolve-conflicts: WARNING {path}: {exc}")
            unresolved.append(path)

    print(f"resolve-conflicts: resolved={len(resolved)} unresolved={len(unresolved)}")
    for path, why in resolved:
        print(f"  RESOLVED {path} ({why})")
    for path in unresolved:
        print(f"  UNRESOLVED {path}")
    (REPORT_DIR / "sync-resolved.txt").write_text(
        "\n".join(f"{p}\t{w}" for p, w in resolved) + ("\n" if resolved else ""),
        encoding="utf-8",
    )
    (REPORT_DIR / "sync-unresolved.txt").write_text(
        "\n".join(unresolved) + ("\n" if unresolved else ""), encoding="utf-8"
    )
    return 2 if unresolved else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"resolve-conflicts: FATAL: {exc}", file=sys.stderr)
        sys.exit(1)
