#!/usr/bin/env python3
"""Render the stock-core examples and verify audible output, routing, the seamless garage and trap loops, the
sound-effect presets, the delay-time zap, and stutter gestures."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import wave

ROOT = Path(__file__).resolve().parents[1]


def class_library(override: str | None) -> Path:
    candidates = [Path(override)] if override else [
        Path('/Applications/SuperCollider.app/Contents/Resources/SCClassLibrary'),
        Path('/usr/share/SuperCollider/SCClassLibrary'),
        Path('/usr/local/share/SuperCollider/SCClassLibrary'),
    ]
    for path in candidates:
        path = path.expanduser().resolve()
        if (path / 'DefaultLibrary' / 'Main.sc').is_file():
            return path
    raise RuntimeError('Provide --class-library with the stock SCClassLibrary directory.')


def cleanup_group(process: subprocess.Popen) -> None:
    """Reap only the process group created with start_new_session below."""
    def signal_group(sig: int) -> bool:
        try:
            os.killpg(process.pid, sig)
            return True
        except ProcessLookupError:
            return False
        except PermissionError as exc:
            process.poll()
            # macOS can deny signalling a group containing only dead/zombie
            # members. A permission error with a live member must stay visible.
            snapshot = subprocess.check_output(['ps', '-axo', 'pgid=,stat='], text=True, timeout=2)
            for row in snapshot.splitlines():
                fields = row.split()
                if len(fields) == 2 and fields[0] == str(process.pid) and not fields[1].startswith('Z'):
                    raise RuntimeError('Cannot signal a live process in the owned SuperCollider group.') from exc
            return False

    process.poll()
    if not signal_group(signal.SIGTERM):
        return
    deadline = time.monotonic() + 1
    while time.monotonic() < deadline:
        process.poll()
        if not signal_group(0):
            return
        time.sleep(0.05)
    signal_group(signal.SIGKILL)
    process.wait()


def render(sclang: str, library: Path, example: str, output: Path, seed: int = 42, extra: tuple = ()) -> str:
    # Ask the OS for a free ephemeral UDP port; never evict a listener.
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(('0.0.0.0', 0))
        port = probe.getsockname()[1]
    env = os.environ.copy()
    scsynth = env.get('SC_SYNTH') or shutil.which('scsynth')
    if scsynth:
        env['SC_SYNTH'] = scsynth
    if sys.platform.startswith('linux'):
        env.setdefault('QT_QPA_PLATFORM', 'offscreen')
    with tempfile.TemporaryDirectory(prefix='sc-drum-runtime-') as directory:
        config = Path(directory) / 'sclang_conf.yaml'
        config.write_text('includePaths:\n  - ' + json.dumps(str(library))
                          + '\nexcludePaths: []\npostInlineWarnings: false\n')
        command = [sclang, '-D', '-a', '-l', str(config), '-u', str(port),
                   str(ROOT / 'examples' / example), str(output), str(seed), *extra]
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, start_new_session=True, env=env)
        try:
            log, _ = process.communicate(timeout=60)
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError(f'{example}: timed out; stopping only its own process group.') from exc
        finally:
            # Runs for success, timeout, communicate errors, Ctrl-C, and SIGTERM.
            try:
                cleanup_group(process)
            finally:
                if process.stdout:
                    process.stdout.close()
    if process.returncode != 0 or 'RENDER_OK' not in log or 'ERROR:' in log or 'FAILURE IN SERVER' in log:
        raise RuntimeError(f'{example}: render failed ({process.returncode}).\n{log[-6000:]}')
    return log


def load_wav(path: Path, seconds: float | None) -> tuple[list[float], bytes, dict]:
    """Decode stereo 24-bit 48 kHz PCM; `seconds` None skips the exact-duration check (trimmed one-shots)."""
    with wave.open(str(path), 'rb') as wav:
        channels, width, rate, count = (wav.getnchannels(), wav.getsampwidth(),
                                        wav.getframerate(), wav.getnframes())
        raw = wav.readframes(count)
    if (channels, width, rate) != (2, 3, 48000):
        raise RuntimeError(f'{path.name}: expected stereo 24-bit 48 kHz WAV.')
    if seconds is not None and abs(count / rate - seconds) > 64 / rate + 1e-6:
        raise RuntimeError(f'{path.name}: unexpected duration {count / rate}.')
    values = [int.from_bytes(raw[i:i + 3], 'little', signed=True) / 8388608
              for i in range(0, len(raw), 3)]
    peak = max(abs(value) for value in values)
    dc = sum(values) / len(values)
    if not 0.0001 < peak < 0.999 or abs(dc) > 0.005:
        raise RuntimeError(f'{path.name}: bad peak or DC: {peak=}, {dc=}.')
    mono = [(values[i] + values[i + 1]) * 0.5 for i in range(0, len(values), 2)]
    return mono, raw, {'frames': count, 'duration_seconds': count / rate,
                       'peak_dbfs': db(peak), 'dc': dc, 'clipped_samples': sum(abs(v) >= 0.999 for v in values)}


def db(value: float) -> float:
    return round(20 * math.log10(max(value, 1e-12)), 3)


def carrier_amplitude(samples: list[float], start: float, duration: float = 0.04) -> float:
    start_frame = round(start * 48000)
    window = samples[start_frame:start_frame + round(duration * 48000)]
    sin = sum(value * math.sin(2 * math.pi * 997 * (start_frame + i) / 48000)
              for i, value in enumerate(window))
    cos = sum(value * math.cos(2 * math.pi * 997 * (start_frame + i) / 48000)
              for i, value in enumerate(window))
    return 2 * math.hypot(sin, cos) / len(window)


def raw_pcm(path: Path) -> bytes:
    with wave.open(str(path), 'rb') as wav:
        return wav.readframes(wav.getnframes())


def resonance_lag_ms(samples: list[float], start: float, duration: float = 0.03) -> float:
    """Lag of the strongest autocorrelation peak (0.2-4 ms) in a window: the period of a comb filter's resonance."""
    first, count = round(start * 48000), round(duration * 48000)
    window = samples[first:first + count]
    best, lag = -math.inf, 0
    for candidate in range(round(0.2 * 48), round(4.0 * 48)):
        value = sum(window[i] * samples[first + i + candidate] for i in range(count))
        if value > best:
            best, lag = value, candidate
    return lag / 48


def verify(args: argparse.Namespace, output: Path) -> dict:
    sclang = shutil.which(args.sclang)
    if not sclang:
        raise RuntimeError('sclang is unavailable; install SuperCollider or pass --sclang.')
    library = class_library(args.class_library)
    version = subprocess.check_output([sclang, '-v'], text=True).strip()
    output.mkdir(parents=True, exist_ok=True)
    gallery_a, gallery_b, ducking, garage_a, garage_b, fx_a, fx_b, trap_a, trap_b = [output / name for name in (
        'gallery-42a.wav', 'gallery-42b.wav', 'sidechain.wav', 'garage-42a.wav', 'garage-42b.wav',
        'garage-fx-42a.wav', 'garage-fx-42b.wav', 'trap-drop-42a.wav', 'trap-drop-42b.wav')]
    zap_shot, zap_a, zap_b, stutter_a, stutter_b = [output / name for name in (
        'zap-clap_zap-slow-verb.wav', 'trap-zap-42a.wav', 'trap-zap-42b.wav',
        'garage-stutter-42a.wav', 'garage-stutter-42b.wav')]
    # Sound-effect presets: (file, preset, bpm, shortest and longest acceptable length in seconds). Lengths follow
    # the musical length (8 bars; the 8 s impact ring-out; 2 bars plus a 1-bar tail) and must stretch with bpm.
    se_cases = [('se-down_trap-pump.wav', 'down_trap-pump', 140, 13.6, 13.9),
                ('se-impact_boom-a.wav', 'impact_boom', 140, 6.5, 8.05),
                ('se-impact_boom-b.wav', 'impact_boom', 140, 6.5, 8.05),
                ('se-rise_2bar-120.wav', 'rise_2bar', 120, 5.3, 6.05)]
    for path in (gallery_a, gallery_b, ducking, garage_a, garage_b, fx_a, fx_b, trap_a, trap_b,
                 zap_shot, zap_a, zap_b, stutter_a, stutter_b, *(output / case[0] for case in se_cases)):
        if path.exists():
            raise RuntimeError(f'{path.name} already exists; use a fresh output directory.')
    render(sclang, library, 'drums-nrt.scd', gallery_a)
    render(sclang, library, 'drums-nrt.scd', gallery_b)
    render(sclang, library, 'sidechain-nrt.scd', ducking)
    garage_log = render(sclang, library, 'garage-nrt.scd', garage_a)
    render(sclang, library, 'garage-nrt.scd', garage_b)
    render(sclang, library, 'garage-nrt.scd', fx_a, extra=('fx',))
    render(sclang, library, 'garage-nrt.scd', fx_b, extra=('fx',))
    trap_log = render(sclang, library, 'trap-se-nrt.scd', trap_a, extra=('drop',))
    render(sclang, library, 'trap-se-nrt.scd', trap_b, extra=('drop',))
    for name, preset, bpm, _, _ in se_cases:
        render(sclang, library, 'se-nrt.scd', output / name, seed=1, extra=(preset, str(bpm)))
    render(sclang, library, 'zap-nrt.scd', zap_shot, seed=1, extra=('clap_zap-slow-verb',))
    zap_log = render(sclang, library, 'trap-se-nrt.scd', zap_a, extra=('zap',))
    render(sclang, library, 'trap-se-nrt.scd', zap_b, extra=('zap',))
    # Stutter gestures on the garage loop just rendered: the last beat of bar 4 as 1/16 repeats, and an accelerating
    # repeat over the loop's last two beats, starting from the kick a 1/16 before them.
    gestures = ('fill16@15', 'accel@30:offset=-0.25')
    for path in (stutter_a, stutter_b):
        render(sclang, library, 'stutter-nrt.scd', path, extra=(str(garage_a), '132', *gestures))
    gallery, pcm_a, gallery_info = load_wav(gallery_a, 18)
    _, pcm_b, _ = load_wav(gallery_b, 18)
    if pcm_a != pcm_b:
        raise RuntimeError('The same seed produced different PCM within this runtime.')
    voice_info = {}
    for index, voice in enumerate(('kick', 'snare', 'clap', 'hat_closed', 'hat_open', 'crash')):
        start = round((0.25 + index * 1.25) * 48000)
        window = gallery[start:start + 24000]
        peak = max(abs(v) for v in window)
        if peak < 0.001:
            raise RuntimeError(f'{voice}: missing or too quiet, peak={db(peak)} dBFS.')
        voice_info[voice] = {'peak_dbfs': db(peak),
                              'rms_dbfs_500ms': db(math.sqrt(sum(v * v for v in window) / len(window)))}
    sidechain, _, sidechain_info = load_wav(ducking, 4)
    baseline = carrier_amplitude(sidechain, 0.70)
    ducked = carrier_amplitude(sidechain, 1.04)
    recovered = carrier_amplitude(sidechain, 3.50)
    reduction = db(ducked / baseline)
    recovery = db(recovered / baseline)
    if reduction > -3 or abs(recovery) > 0.25:
        raise RuntimeError(f'Ducking/recovery failed: reduction={reduction} dB, recovery={recovery} dB.')
    # Garage loop (dry and through fxStrip) and trap loop: exactly 8 bars, reproducible, no step at the loop seam.
    def check_loop(label, path_a, path_b, bpm):
        frames = round(8 * 4 * 60 / bpm * 48000)
        mono, pcm_a, info = load_wav(path_a, frames / 48000)
        _, pcm_b, _ = load_wav(path_b, frames / 48000)
        if info['frames'] != frames:
            raise RuntimeError(f"{label}: {info['frames']} frames, expected exactly {frames}.")
        if pcm_a != pcm_b:
            raise RuntimeError(f'{label}: the same seed produced different PCM within this runtime.')
        steps = sorted(abs(b - a) for a, b in zip(mono, mono[1:]))
        typical = steps[int(0.999 * (len(steps) - 1))]
        seam = abs(mono[0] - mono[-1])
        if seam > typical:
            raise RuntimeError(f'{label}: loop seam step {seam:.4f} exceeds the 99.9th percentile step {typical:.4f}.')
        return {**info, 'seam_step': round(seam, 5), 'p999_step': round(typical, 5),
                'same_seed_pcm_sha256': hashlib.sha256(pcm_a).hexdigest()}
    garage_report = check_loop('garage', garage_a, garage_b, 132)
    fx_report = check_loop('garage fx', fx_a, fx_b, 132)
    voices = {line.split()[1]: line.split()[2] for line in garage_log.splitlines() if line.startswith('VOICE ')}
    if sorted(voices) != ['clap', 'crash', 'hat', 'kick', 'ohat', 'rim']:
        raise RuntimeError(f'garage: unexpected voice report {voices}.')
    trap_report = check_loop('trap drop', trap_a, trap_b, 140)
    trap_voices = {line.split()[1]: line.split()[2] for line in trap_log.splitlines() if line.startswith('VOICE ')}
    if sorted(trap_voices) != ['bass', 'clap', 'hat', 'impact', 'kick', 'lodown', 'rise', 'snare']:
        raise RuntimeError(f'trap drop: unexpected voice report {trap_voices}.')
    se_report = {}
    for name, preset, bpm, shortest, longest in se_cases:
        _, pcm, info = load_wav(output / name, None)
        if not shortest <= info['duration_seconds'] <= longest:
            raise RuntimeError(f"{name}: {info['duration_seconds']:.3f} s, expected {shortest}-{longest} s at {bpm} BPM.")
        if abs(info['peak_dbfs'] + 1) > 0.05:
            raise RuntimeError(f"{name}: peak {info['peak_dbfs']} dBFS, expected -1.")
        se_report[name] = {**info, 'pcm_sha256': hashlib.sha256(pcm).hexdigest()}
    if se_report['se-impact_boom-a.wav']['pcm_sha256'] != se_report['se-impact_boom-b.wav']['pcm_sha256']:
        raise RuntimeError('impact_boom: the same seed produced different PCM within this runtime.')
    # The favourite zap: the comb's resonance must dive, from about 1.9 kHz 10 ms after the hit to about 490 Hz at
    # 100 ms (autocorrelation lags 0.54 and 2.0 ms), under its reverb tail.
    zap_mono, zap_pcm, zap_info = load_wav(zap_shot, None)
    if not 2.0 <= zap_info['duration_seconds'] <= 4.0 or abs(zap_info['peak_dbfs'] + 1) > 0.05:
        raise RuntimeError(f"zap: {zap_info['duration_seconds']:.3f} s at {zap_info['peak_dbfs']} dBFS, "
                           'expected 2-4 s at -1 dBFS.')
    onset = next(i for i, v in enumerate(zap_mono) if abs(v) > 0.05) / 48000
    lags = [resonance_lag_ms(zap_mono, onset + t) for t in (0.01, 0.1)]
    if not (lags[0] < 0.8 and lags[1] > 1.6):
        raise RuntimeError(f'zap: resonance period {lags[0]} ms then {lags[1]} ms; the dive is missing.')
    zap_report = check_loop('trap zap', zap_a, zap_b, 140)
    zap_voices = {line.split()[1]: line.split()[2] for line in zap_log.splitlines() if line.startswith('VOICE ')}
    if sorted(zap_voices) != ['bass', 'clap', 'hat', 'impact', 'kick', 'laser', 'lodown', 'rise', 'snare']:
        raise RuntimeError(f'trap zap: unexpected voice report {zap_voices}.')
    # Stutter: seamless and reproducible; outside the gestures (128 frames of margin for triggers that land on
    # 64-sample blocks) the samples equal the input loop's, inside they differ.
    stutter_report = check_loop('garage stutter', stutter_a, stutter_b, 132)
    garage_raw, stutter_raw = raw_pcm(garage_a), raw_pcm(stutter_a)
    at = [round(beat * 60 / 132 * 48000) for beat in (15, 16, 30, 32)]
    kept, changed = [(0, at[0] - 128), (at[1] + 128, at[2] - 128)], [(at[0], at[1]), (at[2], at[3])]
    if any(stutter_raw[6 * a:6 * b] != garage_raw[6 * a:6 * b] for a, b in kept):
        raise RuntimeError('garage stutter: samples outside the gestures differ from the input loop.')
    if any(stutter_raw[6 * a:6 * b] == garage_raw[6 * a:6 * b] for a, b in changed):
        raise RuntimeError('garage stutter: a gesture left the loop unchanged.')
    return {'status': 'passed', 'supercollider': version, 'stock_class_library_only': True,
            'gallery': gallery_info, 'voices': voice_info,
            'same_seed_pcm_sha256': hashlib.sha256(pcm_a).hexdigest(),
            'sidechain': {**sidechain_info, 'carrier_reduction_db': reduction, 'carrier_recovery_db': recovery},
            'garage': {**garage_report, 'voice_peaks': voices},
            'garage_fx': fx_report,
            'trap_drop': {**trap_report, 'voice_peaks': trap_voices},
            'sound_effects': se_report,
            'zap': {**zap_info, 'resonance_period_ms_at_10_and_100_ms': lags,
                    'pcm_sha256': hashlib.sha256(zap_pcm).hexdigest()},
            'trap_zap': {**zap_report, 'voice_peaks': zap_voices},
            'garage_stutter': {**stutter_report, 'gestures': list(gestures), 'unchanged_outside_gestures': True},
            'listening_checked': False, 'hardware_output_checked': False}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sclang', default='sclang')
    parser.add_argument('--class-library')
    parser.add_argument('--output-dir', type=Path, help='Keep WAV evidence in a fresh directory; otherwise use temporary files.')
    args = parser.parse_args()
    if os.name != 'posix':
        parser.error('This process-group verifier supports macOS and Linux.')

    def interrupted(signum, _frame):
        raise KeyboardInterrupt(f'signal {signum}')

    previous_term = signal.signal(signal.SIGTERM, interrupted)
    try:
        if args.output_dir:
            report = verify(args, args.output_dir.resolve())
        else:
            with tempfile.TemporaryDirectory(prefix='sc-drum-verify-') as directory:
                report = verify(args, Path(directory))
        print(json.dumps(report, indent=2))
    except (RuntimeError, OSError, subprocess.SubprocessError, wave.Error) as exc:
        parser.exit(1, f'ERROR: {exc}\n')
    except KeyboardInterrupt:
        parser.exit(130, 'Interrupted; owned SuperCollider process group cleaned up.\n')
    finally:
        signal.signal(signal.SIGTERM, previous_term)


if __name__ == '__main__':
    main()
