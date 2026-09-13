#!/usr/bin/env python3
"""Install reviewed skill directories with per-skill backups; dry run by default."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import os
from pathlib import Path
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SKILLS = ("sc-composition-toolkit", "sc-drum-synthesis", "sc-webui-preview-render")
IGNORED = {"node_modules", "__pycache__", ".DS_Store", ".venv", "generated", "render", "renders", "output", "logs", "presets"}


def excluded(name: str) -> bool:
    return name in IGNORED or name == ".env" or name.startswith(("._", ".env.")) or name.endswith((".pyc", ".wav", ".aiff", ".osc", ".scsyndef", ".log"))


def files(root: Path, source: bool = False) -> dict[str, tuple[str, int]]:
    result = {}
    for current, dirs, names in os.walk(root, followlinks=False):
        here = Path(current)
        for name in dirs + names:
            if (here / name).is_symlink():
                raise ValueError(f"Refusing symlink: {here / name}")
        if source:
            dirs[:] = [d for d in dirs if not excluded(d)]
            names = [n for n in names if not excluded(n)]
        for name in names:
            path = here / name
            result[path.relative_to(root).as_posix()] = (hashlib.sha256(path.read_bytes()).hexdigest(), path.stat().st_mode & 0o111)
    return result


def install_one(source: Path, target: Path, backups: Path, apply: bool = False) -> dict:
    if source.is_symlink() or target.is_symlink():
        raise ValueError("Skill source and destination must not be symlinks")
    if not (source / "SKILL.md").is_file():
        raise ValueError(f"Missing SKILL.md: {source}")
    if target.exists() and not target.is_dir():
        raise ValueError(f"Destination is not a directory: {target}")
    source_hashes = files(source, source=True)
    if target.exists() and source_hashes == files(target):
        return {"skill": source.name, "action": "unchanged"}
    action = "update" if target.exists() else "install"
    result = {"skill": source.name, "action": action, "applied": apply}
    if not apply:
        return result
    target.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=f".{source.name}-", dir=target.parent))
    backup = None
    try:
        shutil.copytree(source, stage, dirs_exist_ok=True,
                        ignore=lambda _path, names: [n for n in names if excluded(n)])
        if files(stage) != source_hashes:
            raise RuntimeError("Staged skill differs from source")
        if target.exists():
            backups.mkdir(parents=True, exist_ok=True)
            stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
            backup = backups / f"{source.name}-{stamp}"
            # Keep the original in place until a verified backup exists.
            shutil.copytree(target, backup)
            if files(backup) != files(target):
                raise RuntimeError("Backup verification failed")
            shutil.rmtree(target)
            result["backup"] = str(backup)
        try:
            os.replace(stage, target)
        except BaseException:
            if backup is not None and not target.exists():
                shutil.copytree(backup, target)
            raise
        if files(target) != source_hashes:
            raise RuntimeError("Installed skill differs from source")
        return result
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=("codex", "claude"), default="codex")
    parser.add_argument("--destination", type=Path, help="Override the skills directory")
    parser.add_argument("--backup-dir", type=Path)
    parser.add_argument("--skill", choices=SKILLS, action="append", help="Repeat to select skills; default all three")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    destination = args.destination or (Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")) / "skills" if args.target == "codex" else Path.home() / ".claude/skills")
    if destination.is_symlink():
        parser.error("Destination root must not be a symlink")
    destination = destination.expanduser().resolve()
    backups = (args.backup_dir or destination.parent / "skill-backups/supercollider-skills").expanduser().resolve()
    selected = tuple(dict.fromkeys(args.skill or SKILLS))
    source_root = (ROOT / "skills").resolve()
    if destination == source_root or destination.is_relative_to(source_root):
        parser.error("Destination must be outside the source skills directory")
    if backups == destination or backups.is_relative_to(destination):
        parser.error("Backups must be outside the destination skills directory")
    if backups == source_root or backups.is_relative_to(source_root):
        parser.error("Backups must be outside the source skills directory")
    try:
        # Preflight all selected targets before changing any of them.
        for skill in selected:
            install_one(source_root / skill, destination / skill, backups)
        for skill in selected:
            print(install_one(source_root / skill, destination / skill, backups, args.apply))
    except (OSError, ValueError, RuntimeError) as exc:
        parser.exit(1, f"Install failed: {exc}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
