#!/usr/bin/env python3
"""Measure drum one-shots into comparable features (reference packs or our own renders).

Usage: python3 analyze_refs.py OUT.jsonl DIR [DIR ...]
Every WAV under the DIRs is decoded by ffmpeg to 48 kHz stereo float; one JSON line per file.
"""
import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np

SR = 48000
BANDS = [20, 60, 150, 400, 1000, 3000, 6000, 12000, 20000]
# Checked against the file name first, then its two parent folders (pack names such as "808 Drum Pack" are skipped).
CATEGORIES = [
    ('crash', r'crash|cymbal|\bcym|splash|ride'),
    ('ohat', r'open.?h|\bohh?\b|_oh_|ophat|\bohat'),
    ('hat', r'hi.?hat|hihat|\bhh|hat'),
    ('clap', r'clap|clp|\bsnap'),
    ('rim', r'rim'),
    ('snare', r'snare|snr|\bsd\b'),
    ('kick', r'kick|\bbd\b|bassdrum'),
    ('808', r'808|\bsub\b'),
    ('tom', r'\btom'),
    ('shaker', r'shak|tamb'),
    ('click', r'click|glitch'),
    ('perc', r'perc|\bprc|hit|fx|conga|bongo|cowbell|block|wood|clave'),
]


def category(path):
    parts = path.lower().replace('-', '_').split(os.sep)
    for text in (parts[-1], ' '.join(parts[-3:-1])):
        for name, pattern in CATEGORIES:
            if re.search(pattern, text.replace('_', ' ')):
                return name
    return 'other'


def decode(path):
    r = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'],
                       capture_output=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.decode(errors='replace')[:200])
    return np.frombuffer(r.stdout, np.float32).reshape(-1, 2)


def spectrum(x, n=2048, hop=512):
    x = np.pad(x, (0, max(0, n - len(x))))
    w = np.hanning(n)
    P = np.mean([np.abs(np.fft.rfft(x[i:i + n] * w)) ** 2 for i in range(0, len(x) - n + 1, hop)], axis=0)
    return np.fft.rfftfreq(n, 1 / SR), P


def zero_cross_freq(low, a, b):
    seg = low[int(a * SR):int(b * SR)]
    if len(seg) < 16:
        return None
    return float(np.count_nonzero(np.diff(np.signbit(seg))) / 2 / (len(seg) / SR))


def features(x):
    m = x.mean(axis=1)
    peak = float(np.abs(m).max())
    if peak < 1e-5:
        return None
    hop, win = 48, 96                                          # 2 ms RMS every 1 ms
    env = np.sqrt((np.lib.stride_tricks.sliding_window_view(np.pad(m, (0, win)), win)[::hop] ** 2).mean(axis=1))
    top = env.max()

    def last_above(db):
        idx = np.nonzero(env > top * 10 ** (db / 20))[0]
        return float(idx[-1] * hop / SR) if len(idx) else 0.0

    dur60 = last_above(-60)
    active = m[:max(int(dur60 * SR), 2048)]
    f, P = spectrum(active)
    band = (f >= 20) & (f <= 20000)
    total = P[band].sum() + 1e-30
    fl = (f >= 500) & (f <= 16000)
    early = spectrum(m[:int(0.03 * SR)], n=1024, hop=256)
    late = spectrum(m[int(0.03 * SR):int(0.3 * SR)], n=1024, hop=256) if dur60 > 0.05 else None
    spec = np.fft.rfft(m)
    spec[np.fft.rfftfreq(len(m), 1 / SR) > 400] = 0             # below 400 Hz for kick pitch
    low = np.fft.irfft(spec, len(m))
    rms = float(np.sqrt((active ** 2).mean()))
    lr = x[:len(active)]
    corr = np.corrcoef(lr[:, 0], lr[:, 1])[0, 1] if lr[:, 0].std() > 0 and lr[:, 1].std() > 0 else 1.0
    cent = lambda s: float((s[0] * s[1]).sum() / (s[1].sum() + 1e-30))
    head = m[:int(0.05 * SR)] - m[:int(0.05 * SR)].mean()          # periodicity of the first 50 ms
    ac = np.correlate(head, head, 'full')[len(head) - 1:] / (head @ head + 1e-30)
    pb = (f >= 300) & (f <= 16000)
    return {
        'peak_db': round(20 * np.log10(peak), 2),
        'crest_db': round(20 * np.log10(peak / (rms + 1e-12)), 2),
        't_peak_ms': round(env.argmax() * hop / SR * 1000, 1),
        'dur20_ms': round(last_above(-20) * 1000, 1),
        'dur40_ms': round(last_above(-40) * 1000, 1),
        'dur60_ms': round(dur60 * 1000, 1),
        'centroid': round(float((f[band] * P[band]).sum() / total)),
        'cent_early': round(cent(early)),
        'cent_late': round(cent(late)) if late is not None else None,
        'bands': [round(float(P[(f >= lo) & (f < hi)].sum() / total), 4) for lo, hi in zip(BANDS, BANDS[1:])],
        'flatness': round(float(np.exp(np.mean(np.log(P[fl] + 1e-30))) / (P[fl].mean() + 1e-30)), 4),
        'f_start': zero_cross_freq(low, 0.0, 0.02),
        'f_body': zero_cross_freq(low, 0.05, 0.15),
        'width': round(float(1 - corr), 4),
        # pitch cues: autocorrelation peak at 0.25-5 ms lags (200 Hz-4 kHz) and energy share of the 20 strongest bins
        'acf': round(float(ac[int(0.00025 * SR):int(0.005 * SR)].max()), 3) if len(head) > 0.005 * SR else None,
        'top20': round(float(np.sort(P[pb])[-20:].sum() / (P[pb].sum() + 1e-30)), 3),
    }


def measure(path):
    try:
        feats = features(decode(path))
    except Exception as exc:                                   # a broken file must not stop the survey
        return {'path': path, 'error': str(exc)}
    return None if feats is None else {'path': path, 'category': category(path), **feats}


def main():
    out, dirs = sys.argv[1], sys.argv[2:]
    paths = sorted(os.path.join(d, n) for root in dirs for d, _, names in os.walk(root)
                   for n in names if n.lower().endswith('.wav'))
    with ThreadPoolExecutor(8) as pool, open(out, 'w') as fh:
        for row in pool.map(measure, paths):
            if row:
                fh.write(json.dumps(row, ensure_ascii=False) + '\n')
    print(f'{len(paths)} files -> {out}')


if __name__ == '__main__':
    assert category('/p/808 Drum Pack/kicks/Kick_01.wav') == 'kick'
    assert category('/p/x/pk_snr_the808.wav') == 'snare'
    assert category('/p/Glitch Pack/one-shots/drum_hits/hats/GP_hat_01.wav') == 'hat'
    assert category('/p/x/Open Hat 3.wav') == 'ohat'
    assert category('/o/27_ohat_house.wav') == 'ohat'
    main()
