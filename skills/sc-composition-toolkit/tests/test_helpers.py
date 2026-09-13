"""Behavioral checks for WAV validation and owned-process supervision; no SC required."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
spec = importlib.util.spec_from_file_location("wav_check", SCRIPTS / "check_wav.py")
wav_check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wav_check)
runner_spec = importlib.util.spec_from_file_location("sc_runner", SCRIPTS / "run_sclang.py")
sc_runner = importlib.util.module_from_spec(runner_spec)
runner_spec.loader.exec_module(sc_runner)


def wave_bytes(samples: bytes, *, channels=2, bits=24, encoding=1) -> bytes:
    alignment = channels * (bits // 8)
    fmt = struct.pack("<HHIIHH", encoding, channels, 48000, 48000 * alignment, alignment, bits)
    body = b"WAVEfmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(samples)) + samples
    if len(samples) % 2:
        body += b"\0"
    return b"RIFF" + struct.pack("<I", len(body)) + body


class WavTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sc-wav-test-")
        self.path = Path(self.temp.name) / "fixture.wav"

    def tearDown(self):
        self.temp.cleanup()

    def run_check(self, *args):
        proc = subprocess.run([sys.executable, str(SCRIPTS / "check_wav.py"), str(self.path), *args],
                              capture_output=True, text=True, timeout=5)
        return proc.returncode, json.loads(proc.stdout)

    def test_pcm24_stereo_values_and_metadata(self):
        samples = b"".join(value.to_bytes(3, "little", signed=True) for value in [2097152, -4194304] * 16)
        self.path.write_bytes(wave_bytes(samples))
        result = wav_check.inspect_wav(self.path)
        self.assertEqual((result["channels"], result["frames"], result["sample_rate"]), (2, 16, 48000))
        self.assertAlmostEqual(result["peak_dbfs"], -6.020599913279624)
        self.assertEqual(self.run_check("--channels", "2", "--sample-rate", "48000")[0], 0)
        self.assertEqual(self.run_check("--channels", "1")[0], 1)
        self.assertEqual(self.run_check("--max-peak-db", "-7")[0], 1)

    def test_silence_and_explicit_allowance(self):
        self.path.write_bytes(wave_bytes(bytes(24)))
        code, result = self.run_check()
        self.assertEqual(code, 1)
        self.assertIn("Digital silence", result["failures"])
        self.assertEqual(self.run_check("--allow-silence")[0], 0)

    def test_float_nonfinite_and_full_scale(self):
        self.path.write_bytes(wave_bytes(struct.pack("<4f", 0.25, float("nan"), float("inf"), -0.5), bits=32, encoding=3))
        code, result = self.run_check()
        self.assertEqual(code, 1)
        self.assertEqual(result["nonfinite_samples"], 2)
        self.path.write_bytes(wave_bytes(struct.pack("<2f", 1.0, -1.1), bits=32, encoding=3))
        code, result = self.run_check()
        self.assertEqual(code, 1)
        self.assertEqual(result["full_scale_samples"], 2)

    def test_pcm_full_scale(self):
        self.path.write_bytes(wave_bytes(b"\xff\xff\x7f\x00\x00\x80"))
        code, result = self.run_check()
        self.assertEqual(code, 1)
        self.assertEqual(result["full_scale_samples"], 2)

    def test_truncated_and_frame_misaligned(self):
        self.path.write_bytes(wave_bytes(bytes(24))[:-3])
        self.assertEqual(self.run_check()[0], 1)
        self.path.write_bytes(wave_bytes(bytes(5)))
        code, result = self.run_check()
        self.assertEqual(code, 1)
        self.assertIn("frame-misaligned", result["error"])


@unittest.skipUnless(os.name == "posix", "POSIX process-group supervision")
class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sc-runner-test-")
        self.root = Path(self.temp.name)
        self.library = self.root / "SCClassLibrary"
        (self.library / "DefaultLibrary").mkdir(parents=True)
        (self.library / "DefaultLibrary/Main.sc").touch()
        self.script = self.root / "input.scd"
        self.script.touch()
        self.fake = self.root / "fake-sclang"
        self.pidfile = self.root / "child.pid"

    def tearDown(self):
        self.temp.cleanup()

    def fake_program(self, body):
        self.fake.write_text(f"#!{sys.executable}\n" + body)
        self.fake.chmod(0o755)

    def run_runner(self, *args):
        return subprocess.run([sys.executable, str(SCRIPTS / "run_sclang.py"),
                               "--sclang", str(self.fake), "--scsynth", sys.executable,
                               "--class-library", str(self.library), *args, "--", str(self.script)],
                              capture_output=True, text=True, timeout=8)

    def assert_not_running(self, pid):
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            info = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)], capture_output=True, text=True)
            if not info.stdout.strip() or info.stdout.strip().startswith("Z"):
                return
            time.sleep(0.05)
        self.fail(f"Owned child {pid} is still running")

    def test_exit_status_and_stock_configuration(self):
        self.fake_program("import sys, pathlib\n"
                          "assert '-a' in sys.argv\n"
                          "assert 'SCClassLibrary' in pathlib.Path(sys.argv[sys.argv.index('-l')+1]).read_text()\n"
                          "assert int(sys.argv[sys.argv.index('-u')+1]) >= 32768\n"
                          "sys.exit(7)\n")
        self.assertEqual(self.run_runner().returncode, 7)

    def test_permission_error_only_ignored_for_nonrunning_group(self):
        proc = Mock(pid=987654)
        with patch.object(sc_runner.os, "killpg", side_effect=PermissionError(1, "denied")):
            with patch.object(sc_runner, "live_group_members", return_value=[]):
                self.assertFalse(sc_runner.signal_owned_group(proc, signal.SIGTERM))
            with patch.object(sc_runner, "live_group_members", return_value=[987654]):
                with self.assertRaises(PermissionError):
                    sc_runner.signal_owned_group(proc, signal.SIGTERM)

    def test_group_snapshot_excludes_zombies_but_retains_live_members(self):
        rows = "123 987 Z\n124 987 S\n125 988 S\n"
        with patch.object(sc_runner.subprocess, "check_output", return_value=rows):
            self.assertEqual(sc_runner.live_group_members(987), [124])

    def test_busy_udp_port_rejected_before_launch(self):
        self.fake_program(f"from pathlib import Path\nPath({str(self.pidfile)!r}).touch()\n")
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.bind(("0.0.0.0", 0))
            result = self.run_runner("--port", str(sock.getsockname()[1]))
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.pidfile.exists())

    def test_timeout_cleans_children_and_preserves_unrelated_process(self):
        self.fake_program("import subprocess, sys, time\nfrom pathlib import Path\n"
                          "child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])\n"
                          f"Path({str(self.pidfile)!r}).write_text(str(child.pid))\n"
                          "time.sleep(60)\n")
        unrelated = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"], start_new_session=True)
        try:
            result = self.run_runner("--timeout", "0.4")
            self.assertEqual(result.returncode, 124, result.stderr)
            self.assert_not_running(int(self.pidfile.read_text()))
            self.assertIsNone(unrelated.poll())
        finally:
            unrelated.terminate()
            unrelated.wait(timeout=3)

    def test_success_also_cleans_lingering_child(self):
        self.fake_program("import subprocess, sys\nfrom pathlib import Path\n"
                          "child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])\n"
                          f"Path({str(self.pidfile)!r}).write_text(str(child.pid))\n")
        self.assertEqual(self.run_runner().returncode, 0)
        self.assert_not_running(int(self.pidfile.read_text()))


if __name__ == "__main__":
    unittest.main()
