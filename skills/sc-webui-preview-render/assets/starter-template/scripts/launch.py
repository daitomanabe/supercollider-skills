#!/usr/bin/env python3
"""Supervise only this launcher session; never terminate processes occupying ports."""
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
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
ENV_PORTS = {'httpPort':'SCW_HTTP_PORT', 'feedbackPort':'SCW_FEEDBACK_PORT', 'languagePort':'SCW_LANGUAGE_PORT', 'audioPort':'SCW_AUDIO_PORT'}

def configuration():
    defaults = json.loads((ROOT / 'config.json').read_text())
    ports = {key: int(os.environ.get(name, defaults[key])) for key,name in ENV_PORTS.items()}
    if any(port < 1024 or port > 65535 for port in ports.values()) or len(set(ports.values())) != 4:
        raise RuntimeError('Choose four distinct integer ports in 1024..65535')
    return ports

def preflight(ports):
    if not shutil.which('lsof'):
        raise RuntimeError('lsof is required for port ownership checks')
    for key, port in ports.items():
        # Inspect stdout: lsof can return a nonzero exit status even with relevant rows.
        found = subprocess.run(['lsof','-nP',f'-i:{port}'], text=True, capture_output=True).stdout.strip()
        if found:
            raise RuntimeError(f'{key} port {port} is occupied; choose another SCW_*_PORT.\n{found}')
        # Also test bind availability, including services not visible to lsof.
        for kind in [socket.SOCK_STREAM, socket.SOCK_DGRAM]:
            with socket.socket(socket.AF_INET, kind) as sock:
                if kind == socket.SOCK_STREAM:
                    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                try:
                    sock.bind(('127.0.0.1', port))
                except OSError as exc:
                    raise RuntimeError(f'{key} port {port} unavailable: {exc}') from exc

def find_sclang():
    requested = os.environ.get('SCLANG')
    candidates = [requested] if requested else [shutil.which('sclang'), '/Applications/SuperCollider.app/Contents/MacOS/sclang', str(Path.home() / 'Applications/SuperCollider.app/Contents/MacOS/sclang')]
    for candidate in candidates:
        if candidate and Path(candidate).is_file() and os.access(candidate, os.X_OK):
            return str(Path(candidate).resolve())
    raise RuntimeError('sclang was not found; install SuperCollider or set SCLANG to its executable')

def stock_library(sclang):
    requested = os.environ.get('SCW_CLASS_LIBRARY')
    candidates = [Path(requested)] if requested else [Path(sclang).parent.parent / 'Resources/SCClassLibrary', Path('/Applications/SuperCollider.app/Contents/Resources/SCClassLibrary'), Path('/usr/share/SuperCollider/SCClassLibrary'), Path('/usr/local/share/SuperCollider/SCClassLibrary')]
    for candidate in candidates:
        if candidate.is_dir():
            return candidate
    raise RuntimeError('Stock SCClassLibrary not found; set SCW_CLASS_LIBRARY to its directory')

def live_group_members(group):
    rows = subprocess.check_output(['ps','-axo','pid=,pgid=,stat='],text=True).splitlines()
    return [int(fields[0]) for row in rows if len(fields := row.split()) >= 3 and int(fields[1]) == group and not fields[2].startswith('Z')]

def signal_owned_group(child, sig):
    if not live_group_members(child.pid):
        return
    try:
        os.killpg(child.pid, sig)
    except ProcessLookupError:
        pass
    except PermissionError:
        # macOS may retain a dead group briefly; a live member is still a failure.
        if live_group_members(child.pid):
            raise RuntimeError(f'Cannot terminate live owned process group {child.pid}')

def terminate_group(child):
    # Each child was created with start_new_session=True. The group also owns scsynth.
    signal_owned_group(child, signal.SIGTERM)
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        child.poll()
        if not live_group_members(child.pid):
            return
        time.sleep(0.05)
    signal_owned_group(child, signal.SIGKILL)
    child.wait(timeout=5)
    if live_group_members(child.pid):
        raise RuntimeError(f'Live process remains in owned group {child.pid}')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Check dependencies and ports without starting services')
    args = parser.parse_args()
    children = []
    sc_log = None
    language_config = None
    def interrupted(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        node = shutil.which('node')
        if not node:
            raise RuntimeError('Node.js >=22 is required')
        version = subprocess.check_output([node,'--version'], text=True).strip()
        if int(version.lstrip('v').split('.')[0]) < 22:
            raise RuntimeError('Node.js >=22 is required')
        if not (ROOT / 'node_modules/ws').is_dir():
            raise RuntimeError('Dependencies are missing. Run npm ci in the template directory first.')
        sclang = find_sclang()
        library = stock_library(sclang)
        ports = configuration()
        preflight(ports)
        if args.check:
            print(json.dumps({'ports':ports, 'node':version, 'stockLibraryFound':True}), flush=True)
            return 0
        environment = os.environ.copy()
        for key,name in ENV_PORTS.items():
            environment[name] = str(ports[key])
        if sys.platform.startswith('linux'):
            environment.setdefault('QT_QPA_PLATFORM', 'offscreen')
        data_root = Path(environment.get('SCW_DATA_DIR', ROOT)).resolve()
        if any(char in str(data_root) for char in '\\`$\"\n\r'):
            raise RuntimeError('SCW_DATA_DIR cannot contain shell metacharacters (backslash, backtick, dollar, double quote, newline)')
        language_config = tempfile.TemporaryDirectory(prefix='scw-language-')
        config_path = Path(language_config.name)/'sclang_conf.yaml'
        config_path.write_text(json.dumps({'includePaths':[str(library)], 'excludePaths':[], 'excludeDefaultPaths':True, 'postInlineWarnings':False}))
        (data_root / 'logs').mkdir(parents=True, exist_ok=True)
        subprocess.run([node, 'scripts/generate-sc.js'], cwd=ROOT, check=True)
        sc_log = (data_root / 'logs/sclang.log').open('w')
        children.append(subprocess.Popen([node, 'server.js'], cwd=ROOT, env=environment, start_new_session=True))
        children.append(subprocess.Popen([sclang, '-D', '-a', '-l', str(config_path), '-u', str(ports['languagePort']), str(ROOT/'sc/main.scd')], cwd=ROOT, env=environment, stdout=sc_log, stderr=subprocess.STDOUT, start_new_session=True))
        deadline = time.monotonic() + 40
        url = f"http://127.0.0.1:{ports['httpPort']}"
        while time.monotonic() < deadline:
            if any(child.poll() is not None for child in children):
                raise RuntimeError('A service exited during startup; inspect logs/sclang.log')
            try:
                with urlopen(url + '/api/status', timeout=0.5) as response:
                    if json.load(response)['status'] == 'ready':
                        break
            except (OSError, ValueError):
                pass
            time.sleep(0.1)
        else:
            raise RuntimeError('SuperCollider readiness timed out; inspect logs/sclang.log')
        # Startup requires actual HTTP and OSC feedback, not merely live PIDs.
        print(f'Ready: {url} (NRT available; audio starts only on Play)', flush=True)
        while all(child.poll() is None for child in children):
            time.sleep(0.2)
        raise RuntimeError('A service exited; stopping this session. Inspect logs/sclang.log')
    except KeyboardInterrupt:
        return 0
    except (RuntimeError, ValueError, OSError, subprocess.SubprocessError) as exc:
        print(f'Error: {exc}', file=sys.stderr, flush=True)
        return 1
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        cleanup_errors = []
        for child in reversed(children):
            try:
                terminate_group(child)
            except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
                cleanup_errors.append(str(exc))
        if sc_log:
            sc_log.close()
        if language_config:
            language_config.cleanup()
        if cleanup_errors:
            print('Cleanup failed: ' + '; '.join(cleanup_errors), file=sys.stderr)
            raise SystemExit(1)

if __name__ == '__main__':
    sys.exit(main())
