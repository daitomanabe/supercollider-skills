#!/usr/bin/env python3
"""Real stock SC NRT tests. No audio device boots; all test services are supervised."""
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import random
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
from urllib.request import urlopen
import wave

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('launcher', ROOT/'scripts/launch.py')
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)

def free_ports():
    for _ in range(100):
        first = random.randint(48000, 55000)
        ports = dict(zip(launcher.ENV_PORTS, range(first,first+4)))
        try:
            launcher.preflight(ports)
            return ports
        except RuntimeError:
            pass
    raise RuntimeError('Could not allocate four free integration ports')

def descendants(pid):
    rows = [line.split(None, 3) for line in subprocess.check_output(['ps','-axo','pid=,ppid=,pgid=,command='],text=True).splitlines()]
    found = {pid}
    while True:
        expanded = found | {int(row[0]) for row in rows if int(row[1]) in found}
        if expanded == found:
            return [(int(row[0]),int(row[2]),row[3]) for row in rows if int(row[0]) in found]
        found = expanded

def inspect_wav(path):
    with wave.open(str(path),'rb') as wav:
        assert (wav.getnchannels(),wav.getsampwidth(),wav.getframerate()) == (2,3,44100)
        duration = wav.getnframes()/44100
        raw = wav.readframes(wav.getnframes())
    samples = [int.from_bytes(raw[i:i+3],'little',signed=True)/8388608 for i in range(0,len(raw),3)]
    peak = max(map(abs,samples))
    rms = math.sqrt(sum(value*value for value in samples)/len(samples))
    assert 0.01 < peak <= 0.951 and rms > 0.001, (path.name,peak,rms)
    metadata = json.loads(path.with_suffix('.json').read_text())
    assert abs(duration - metadata['parameters']['seconds'] - metadata['tailSeconds']) < 0.01
    return {'file':path.name,'duration':duration,'peak':peak,'rms':rms,'pcmSha256':hashlib.sha256(raw).hexdigest()}

def main():
    artifacts = ROOT/'logs'
    artifacts.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='scw-integration-') as temporary:
        data = Path(temporary)
        ports = free_ports()
        env = os.environ.copy()
        env.update({launcher.ENV_PORTS[key]:str(port) for key,port in ports.items()})
        env.update(SCW_NRT_ONLY='1', SCW_DATA_DIR=str(data))
        # A occupied port must produce failure without touching its owner.
        with socket.socket() as owner:
            owner.bind(('127.0.0.1',ports['httpPort']));owner.listen()
            blocked = subprocess.run([sys.executable,'scripts/launch.py','--check'],cwd=ROOT,env=env,capture_output=True,text=True)
            assert blocked.returncode == 1 and 'occupied' in blocked.stderr, blocked.stderr
            assert owner.getsockname()[1] == ports['httpPort']
        with (artifacts/'integration-supervisor.log').open('w') as log:
            child = subprocess.Popen([sys.executable,'scripts/launch.py'],cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
            tracked = []
            try:
                url = f"http://127.0.0.1:{ports['httpPort']}"
                deadline = time.monotonic()+45
                while time.monotonic() < deadline:
                    assert child.poll() is None, 'Supervisor exited; inspect logs/integration-supervisor.log'
                    try:
                        with urlopen(url+'/api/status',timeout=0.5) as response:
                            status=json.load(response)
                            if status['status']=='ready':
                                assert status['audio']=='disabled'
                                break
                    except OSError:
                        pass
                    time.sleep(0.1)
                else:
                    raise AssertionError('Startup timed out')
                env['SCW_TEST_URL']=url
                driver=subprocess.run(['node','tests/integration-client.js'],cwd=ROOT,env=env,capture_output=True,text=True,timeout=90)
                assert driver.returncode == 0, driver.stderr
                batches=json.loads(driver.stdout)
                tracked=descendants(child.pid)
                assert any('scsynth' in command for _,_,command in tracked), 'Expected active NRT child for cleanup test'
                # NRT does not open the configured audio server port.
                assert not subprocess.run(['lsof','-nP',f"-i:{ports['audioPort']}"],capture_output=True,text=True).stdout.strip()
                child.send_signal(signal.SIGTERM)
                assert child.wait(timeout=10)==0
                inspected=[]
                for key in ['first','repeat','stopped']:
                    folder=data/'output'/batches[key]['id']
                    files=sorted(folder.glob('*.wav'))
                    assert len(files)==batches[key]['completed']
                    inspected.extend(inspect_wav(file) for file in files)
                    assert json.loads((folder/'batch.json').read_text())['failures']==0
                assert inspected[0]['pcmSha256']==inspected[1]['pcmSha256']==inspected[2]['pcmSha256'], 'Fixed seed NRT PCM changed'
                for pid,_,_ in tracked:
                    if pid == child.pid:
                        continue
                    assert subprocess.run(['ps','-p',str(pid)],capture_output=True).returncode != 0, f'Orphan PID {pid}'
                launcher.preflight(ports)
                sc_log=(data/'logs/sclang.log').read_text()
                assert not any(marker in sc_log for marker in ['ERROR:', 'FAILURE IN SERVER', 'Exception']), sc_log
                shutil.copy2(data/'logs/sclang.log',artifacts/'integration-sclang.log')
                report={'passed':True,'stockNRT':True,'audioDeviceBooted':False,'sequential':True,'stopAfterCurrent':True,'occupiedPortOwnerPreserved':True,'ownedCleanup':True,'wavChecks':inspected}
                (artifacts/'integration-result.json').write_text(json.dumps(report,indent=2)+'\n')
                print(json.dumps(report,indent=2))
            finally:
                if child.poll() is None:
                    child.send_signal(signal.SIGTERM)
                    child.wait(timeout=10)
                if (data/'logs/sclang.log').exists():
                    shutil.copy2(data/'logs/sclang.log',artifacts/'integration-sclang.log')

if __name__=='__main__':
    main()
