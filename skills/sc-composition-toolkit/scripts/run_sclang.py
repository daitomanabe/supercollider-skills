#!/usr/bin/env python3
"""Bounded, stock-class-library SuperCollider execution on macOS/Linux."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time


def executable(value: str) -> Path:
    found = shutil.which(value)
    if not found:
        raise ValueError(f"Executable not found: {value}")
    return Path(found).resolve()


def class_library(binary: Path, explicit: str | None) -> Path:
    candidates = [Path(explicit).expanduser()] if explicit else [
        binary.parent.parent / "Resources/SCClassLibrary",
        binary.parent.parent / "share/SuperCollider/SCClassLibrary",
        Path("/Applications/SuperCollider.app/Contents/Resources/SCClassLibrary"),
        Path("/usr/share/SuperCollider/SCClassLibrary"),
        Path("/usr/local/share/SuperCollider/SCClassLibrary"),
    ]
    for path in candidates:
        if (path / "DefaultLibrary/Main.sc").is_file():
            return path.resolve()
    raise ValueError("Stock SCClassLibrary not found; supply --class-library PATH")


def preflight_port(requested: int | None) -> int:
    if requested is not None and not 1024 <= requested <= 65535:
        raise ValueError("--port must be between 1024 and 65535")
    # No SO_REUSEADDR: reject listeners bound to this address or all interfaces.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("0.0.0.0", requested or 0))
        port = sock.getsockname()[1]
    if port < 32768 and requested is None:
        # Some systems configure a low ephemeral range; choose a high port instead.
        for candidate in range(49152, 65536):
            try:
                return preflight_port(candidate)
            except OSError:
                continue
        raise ValueError("No free high UDP port found")
    return port


def live_group_members(group: int) -> list[int]:
    """Inspect the group after a permission error; zombies cannot execute or hold ports."""
    rows = subprocess.check_output(["ps", "-axo", "pid=,pgid=,stat="], text=True)
    members = []
    for row in rows.splitlines():
        pid, pgid, status = row.split()
        if int(pgid) == group and not status.startswith("Z"):
            members.append(int(pid))
    return members


def signal_owned_group(proc: subprocess.Popen, signum: int) -> bool:
    try:
        os.killpg(proc.pid, signum)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        # Darwin can return EPERM while the last signallable process is exiting.
        # Never suppress a permission error for a group that still has live members.
        proc.poll()
        if live_group_members(proc.pid):
            raise
        print(f"Owned process group {proc.pid} has no live members; cleanup complete", file=sys.stderr)
        return False


def cleanup_group(proc: subprocess.Popen, grace: float = 1.0) -> None:
    """Only target the group created by start_new_session for this subprocess."""
    if not signal_owned_group(proc, signal.SIGTERM):
        return
    deadline = time.monotonic() + grace
    while time.monotonic() < deadline:
        proc.poll()  # reap the group leader if it has exited
        if not signal_owned_group(proc, 0):
            return
        time.sleep(0.05)
    signal_owned_group(proc, signal.SIGKILL)
    proc.wait()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, default=60, help="Wall-clock seconds (default: 60)")
    parser.add_argument("--port", type=int, help="Checked UDP language port (default: free high port)")
    parser.add_argument("--sclang", default=os.environ.get("SCLANG", "sclang"))
    parser.add_argument("--scsynth", default=os.environ.get("SC_SYNTH", "scsynth"))
    parser.add_argument("--class-library", default=os.environ.get("SC_CLASS_LIBRARY"))
    parser.add_argument("--include-path", action="append", default=[], help="Explicit extra class path; repeatable")
    parser.add_argument("--log", type=Path, help="Write stdout/stderr to a new log file")
    parser.add_argument("script", type=Path)
    parser.add_argument("script_args", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if os.name != "posix":
        parser.error("This process-group runner supports macOS and Linux")
    if not 0 < args.timeout < float("inf"):
        parser.error("--timeout must be finite and positive")
    try:
        lang = executable(args.sclang)
        synth = executable(args.scsynth)
        library = class_library(lang, args.class_library)
        script = args.script.expanduser().resolve(strict=True)
        if not script.is_file():
            raise ValueError("Script must be a regular file")
        includes = [library] + [Path(p).expanduser().resolve(strict=True) for p in args.include_path]
        if not all(p.is_dir() for p in includes):
            raise ValueError("Class include paths must be directories")
        port = preflight_port(args.port)
    except (OSError, ValueError) as error:
        parser.error(str(error))

    def interrupted(signum, _frame):
        raise KeyboardInterrupt(f"signal {signum}")

    previous_term = signal.signal(signal.SIGTERM, interrupted)
    proc = None
    logfile = None
    try:
        with tempfile.TemporaryDirectory(prefix="sc-skill-") as tmp:
            config = Path(tmp) / "sclang_conf.yaml"
            # JSON strings are valid YAML double-quoted scalars.
            config.write_text("includePaths:\n" + "".join(f"  - {json.dumps(str(p))}\n" for p in includes)
                              + "excludePaths: []\npostInlineWarnings: false\n")
            env = os.environ.copy()
            env["SC_SYNTH"] = str(synth)
            env["SC_SKILL_TMP"] = tmp
            if sys.platform.startswith("linux"):
                env.setdefault("QT_QPA_PLATFORM", "offscreen")
            command = [str(lang), "-D", "-a", "-l", str(config), "-u", str(port), str(script), *args.script_args]
            if args.log:
                logfile = args.log.expanduser().open("x", encoding="utf-8")
            print(json.dumps({"sclang": str(lang), "scsynth": str(synth), "class_library": str(library),
                              "udp_port": port, "timeout_seconds": args.timeout}), flush=True)
            proc = subprocess.Popen(command, env=env, stdin=subprocess.DEVNULL, stdout=logfile,
                                    stderr=subprocess.STDOUT, start_new_session=True)
            try:
                returncode = proc.wait(timeout=args.timeout)
                return returncode if returncode >= 0 else 128 - returncode
            except subprocess.TimeoutExpired:
                print(f"sclang exceeded {args.timeout:g} seconds; cleaning owned process group", file=sys.stderr)
                return 124
            finally:
                cleanup_group(proc)
    except KeyboardInterrupt:
        print("Interrupted; owned process group cleaned up", file=sys.stderr)
        return 130
    except OSError as error:
        print(f"Runner error: {error}", file=sys.stderr)
        return 2
    finally:
        if logfile:
            logfile.close()
        signal.signal(signal.SIGTERM, previous_term)


if __name__ == "__main__":
    raise SystemExit(main())
