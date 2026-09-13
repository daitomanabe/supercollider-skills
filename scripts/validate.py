#!/usr/bin/env python3
"""Check distributable skill structure, local links, syntax, and private-path leaks."""
import ast
from pathlib import Path
import re
import shutil
import subprocess
import sys

from install import SKILLS, excluded

ROOT = Path(__file__).resolve().parents[1]


def main():
    errors = []
    checked = 0
    for name in SKILLS:
        folder = ROOT / "skills" / name
        entry = folder / "SKILL.md"
        if not entry.is_file():
            errors.append(f"Missing {entry.relative_to(ROOT)}")
            continue
        text = entry.read_text()
        front = re.match(r"\A---\n(.*?)\n---\n", text, re.S)
        if not front or not re.search(rf"^name: {re.escape(name)}$", front[1], re.M) or not re.search(r"^description: .+", front[1], re.M):
            errors.append(f"Invalid frontmatter: {entry.relative_to(ROOT)}")
    for path in sorted(ROOT.rglob("*")):
        rel = path.relative_to(ROOT)
        if any(part.startswith(".") or excluded(part) or part in {"backups", "state", "build"} for part in rel.parts):
            continue
        if path.is_symlink():
            errors.append(f"Symlink in distribution: {rel}")
            continue
        if not path.is_file():
            continue
        checked += 1
        if path.stat().st_size > 1_000_000:
            errors.append(f"Unexpected large source file: {rel}")
        try:
            text = path.read_text()
        except UnicodeDecodeError:
            errors.append(f"Unexpected binary file: {rel}")
            continue
        if re.search(r"/(?:Users|home)/[A-Za-z0-9_.-]+/", text):
            errors.append(f"Concrete home path: {rel}")
        if re.search(r"-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}", text):
            errors.append(f"Possible credential: {rel}")
        if path.suffix == ".md":
            for target in re.findall(r"\[[^\]]*\]\(([^)]+)\)", text):
                if "://" in target or target.startswith(("#", "mailto:")):
                    continue
                local = target.split("#")[0]
                if local and not (path.parent / local).exists():
                    errors.append(f"Broken local link in {rel}: {local}")
        try:
            if path.suffix == ".py":
                ast.parse(text, filename=str(rel))
            elif path.suffix in {".js", ".mjs", ".cjs"}:
                if shutil.which("node"):
                    subprocess.run(["node", "--check", str(path)], check=True, capture_output=True)
                else:
                    errors.append("Node.js is required for JavaScript syntax checks")
            elif path.suffix == ".sh":
                subprocess.run(["bash", "-n", str(path)], check=True, capture_output=True)
        except (SyntaxError, subprocess.CalledProcessError) as exc:
            errors.append(f"Syntax check failed: {rel}: {exc}")
    for error in errors:
        print(error, file=sys.stderr)
    print(f"{'FAIL' if errors else 'PASS'}: {len(SKILLS)} skills, {checked} source files, {len(errors)} errors")
    return bool(errors)


if __name__ == "__main__":
    raise SystemExit(main())
