#!/usr/bin/env python3
"""Measure tempo-synced sound effects (risers, downlifters, impacts, modulated SE) and bass into comparable features.

Usage: python3 analyze_se.py OUT.jsonl BPM FILE_OR_DIR [...]
Each WAV is decoded by ffmpeg to 48 kHz stereo float. Times are also given in bars at BPM so that references
and renders at the same tempo compare directly. One JSON line per file.
"""
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np

SR = 48000
HOP = 240                                                   # 5 ms envelope hop


def decode(path):
    r = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'],
                       capture_output=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.decode(errors='replace')[:200])
    return np.frombuffer(r.stdout, np.float32).reshape(-1, 2)


def envelope_db(m, win=960):
    """20 ms RMS every 5 ms, in dB relative to its maximum."""
    frames = np.lib.stride_tricks.sliding_window_view(np.pad(m, (0, win)), win)[::HOP]
    env = np.sqrt((frames ** 2).mean(axis=1)) + 1e-12
    return 20 * np.log10(env / env.max())


def stft(m, n, hop):
    frames = np.lib.stride_tricks.sliding_window_view(np.pad(m, (0, n)), n)[::hop] * np.hanning(n)
    return np.abs(np.fft.rfft(frames, axis=1)) ** 2, np.fft.rfftfreq(n, 1 / SR)


def modulation(db, beat):
    """Strongest periodic level change (0.8-25 Hz) of the envelope with its trend removed.

    Returns rate in Hz, rate in cycles per beat, prominence (peak / median of the spectrum), depth (10-90 %
    range of the detrended dB) and the average cycle folded on the beat grid (8 values, dB; phase 0 = beat)."""
    if len(db) * HOP / SR < 1.5:
        return {}
    k = int(0.75 * SR / HOP)
    trend = np.convolve(np.pad(db, (k // 2, k - k // 2 - 1), mode='edge'), np.ones(k) / k, mode='valid')
    d = db - trend
    n = 1 << int(np.ceil(np.log2(len(d) * 8)))
    spec = np.abs(np.fft.rfft(d * np.hanning(len(d)), n))
    f = np.fft.rfftfreq(n, HOP / SR)
    band = (f >= 0.8) & (f <= 25)
    i = np.argmax(np.where(band, spec, 0))
    rate = float(f[i])
    per_beat = rate * beat
    # Fold on the nearest musical division (1/2 .. 1/32, straight or triplet) so the shape is phase-aligned.
    divisions = np.array([0.5, 1, 1.5, 2, 3, 4, 6, 8])
    div = divisions[np.argmin(np.abs(np.log(divisions / per_beat)))]
    period = beat / div
    phase = (np.arange(len(d)) * HOP / SR / period) % 1
    fold = [round(float(d[(phase >= a / 8) & (phase < (a + 1) / 8)].mean()), 1) for a in range(8)]
    return {'mod_hz': round(rate, 2), 'mod_per_beat': round(per_beat, 2), 'mod_div': float(div),
            'mod_prom': round(float(spec[i] / (np.median(spec[band]) + 1e-12)), 1),
            'mod_depth_db': round(float(np.percentile(d, 90) - np.percentile(d, 10)), 1), 'mod_fold': fold}


def pitch_drift(m, active):
    """Rate (semitones per second) at which the harmonic fine structure moves over the active region, overall and
    for its first and second half.

    Log-frequency spectra (quarter-semitone bins, 50 Hz-8 kHz) are whitened by subtracting a one-octave moving
    average; frames 0.5 s apart are cross-correlated over +-6 semitones and the shifts averaged into a rate."""
    n, hop = 8192, 2400
    P, f = stft(m, n, hop)
    grid = 50 * 2 ** (np.arange(0, np.log2(8000 / 50) * 48) / 48)
    L = np.log(np.array([np.interp(grid, f, p) for p in P]) + 1e-12)
    k = 48
    L = L - np.array([np.convolve(np.pad(r, (k // 2, k - k // 2 - 1), mode='edge'), np.ones(k) / k, 'valid') for r in L])
    t = np.arange(len(P)) * hop / SR
    step = int(0.5 * SR / hop)
    idx = [i for i in range(0, len(P) - step, step) if active[0] <= t[i] and t[i + step] <= active[1]]
    shifts, lags = [], np.arange(-24, 25)
    for i in idx:
        a, b = L[i], L[i + step]
        c = np.array([np.dot(a[max(0, -g):len(a) - max(0, g)], b[max(0, g):len(b) - max(0, -g)]) for g in lags])
        j = int(np.argmax(c))
        off = 0.0
        if 0 < j < len(c) - 1:                              # parabolic interpolation to a fraction of a bin
            den = c[j - 1] - 2 * c[j] + c[j + 1]
            off = 0.5 * (c[j - 1] - c[j + 1]) / den if den != 0 else 0.0
        shifts.append((lags[j] + off) / 4)
    if len(shifts) < 2:
        return None, None
    half = len(shifts) // 2
    return float(np.mean(shifts)) / 0.5, [float(np.mean(shifts[:half])) / 0.5, float(np.mean(shifts[half:])) / 0.5]


def features(x, bpm):
    m = x.mean(axis=1)
    if np.abs(m).max() < 1e-5:
        return None
    beat, bar = 60 / bpm, 240 / bpm
    db = envelope_db(m)
    t = np.arange(len(db)) * HOP / SR
    on = t[np.argmax(db > -30)]
    end40 = t[np.nonzero(db > -40)[0][-1]]
    end60 = t[np.nonzero(db > -60)[0][-1]]
    ip = int(np.argmax(db))
    # Level at tenths of the span from onset to the -40 dB end.
    span = [round(float(db[min(int(np.searchsorted(t, on + q * (end40 - on))), len(db) - 1)]), 1) for q in np.linspace(0, 1, 11)]
    # Spectral centroid and 95 % roll-off (the low-pass edge) per 50 ms frame, over frames within 40 dB of the peak.
    P, f = stft(m, 4096, 2400)
    tf = np.arange(len(P)) * 2400 / SR
    keep = (f >= 30) & (f <= 16000)
    tot = P[:, keep].sum(axis=1) + 1e-30
    cen = (P[:, keep] * f[keep]).sum(axis=1) / tot
    roll = f[keep][np.minimum(np.argmax(np.cumsum(P[:, keep], axis=1) >= 0.95 * tot[:, None], axis=1), keep.sum() - 1)]
    lvl = 10 * np.log10(tot / tot.max())
    act = lvl > -40
    ta = tf[act]

    def at(arr, q):                                         # median over the q-th fifth of the active frames
        if len(ta) < 5:
            return None
        lo, hi = np.percentile(ta, [q * 20, q * 20 + 20])
        sel = act & (tf >= lo) & (tf <= hi)
        return round(float(np.median(arr[sel]))) if sel.any() else None

    sub = f < 100
    early = tf < tf[np.argmax(lvl)] + 0.5
    width = lambda a, b: (round(float(1 - np.corrcoef(x[a:b, 0], x[a:b, 1])[0, 1]), 3)
                          if b - a > 2048 and x[a:b, 0].std() > 0 and x[a:b, 1].std() > 0 else None)
    # Decay slope after the peak (impacts): fit dB over [peak + 0.2 s, -50 dB point] for the full band and bands.
    def slope(dbv, tv, t0):
        s = (tv >= t0 + 0.2) & (dbv > -50)
        s &= tv <= (tv[s][-1] if s.any() else 0)
        return round(float(np.polyfit(tv[s], dbv[s], 1)[0]), 1) if s.sum() > 20 else None
    band_db = lambda sel: 10 * np.log10(P[:, sel].sum(axis=1) / (P[:, sel].sum(axis=1).max() + 1e-30) + 1e-30)
    fl = (f >= 200) & (f <= 8000)
    flat = np.exp(np.mean(np.log(P[:, fl] + 1e-30), axis=1)) / (P[:, fl].mean(axis=1) + 1e-30)
    drift, drift_halves = pitch_drift(m, (on, end40))
    return {
        'dur_s': round(len(m) / SR, 2),
        'on_bars': round(on / bar, 2), 'peak_bars': round(t[ip] / bar, 2),
        'end40_bars': round(end40 / bar, 2), 'end60_bars': round(end60 / bar, 2),
        'level_tenths': span,
        'centroid_fifths': [at(cen, q) for q in range(5)],
        'rolloff_fifths': [at(roll, q) for q in range(5)],
        # pitch movement in semitones per bar, overall and per half of the sound
        'pitch_st_bar': None if drift is None else round(drift * bar, 1),
        'pitch_st_bar_halves': None if drift is None else [round(h * bar, 1) for h in drift_halves],
        'flatness': round(float(np.median(flat[act])), 3) if act.any() else None,
        'sub_share_early': round(float(P[early][:, sub].sum() / P[early].sum()), 3),
        'sub_share_late': round(float(P[~early & act][:, sub].sum() / (P[~early & act].sum() + 1e-30)), 3) if (~early & act).any() else None,
        'decay_db_s': slope(db, t, t[ip]),
        'decay_sub_db_s': slope(band_db(sub & (f >= 20)), tf, tf[np.argmax(lvl)]),
        'decay_high_db_s': slope(band_db(f >= 2000), tf, tf[np.argmax(lvl)]),
        'db_after_peak': [round(float(db[min(ip + int(s * SR / HOP), len(db) - 1)]), 1) for s in (0.05, 0.2, 1.0)],
        'width_early': width(int(t[ip] * SR), int((t[ip] + 0.3) * SR)),
        'width_late': width(int((t[ip] + 0.3) * SR), int(end40 * SR)),
        **modulation(db[int(on * SR / HOP):int(end40 * SR / HOP)], beat),
    }


def measure(args):
    path, bpm = args
    try:
        feats = features(decode(path), bpm)
    except Exception as exc:                                  # one broken file must not stop the survey
        return {'path': path, 'error': repr(exc)}
    return feats and {'path': path, **feats}


def main():
    out, bpm, srcs = sys.argv[1], float(sys.argv[2]), sys.argv[3:]
    paths = sorted(p for s in srcs for p in ([s] if os.path.isfile(s) else
                   [os.path.join(d, n) for d, _, names in os.walk(s) for n in names if n.lower().endswith('.wav')]))
    with ThreadPoolExecutor(8) as pool, open(out, 'w') as fh:
        for row in pool.map(measure, [(p, bpm) for p in paths]):
            if row:
                fh.write(json.dumps(row, ensure_ascii=False) + '\n')
    print(f'{len(paths)} files -> {out}')


def _self_check():
    """A 2 s saw at 200 Hz gliding down an octave, gated at 1/8 notes of 120 BPM (one bar): -12 st/bar, 1/8 gate."""
    t = np.arange(2 * SR) / SR
    f0 = 200 * 2 ** (-t / 2)
    saw = 2 * ((np.cumsum(f0) / SR) % 1) - 1
    gate = 0.25 + 0.75 * (((t * 4) % 1) < 0.5)
    x = np.stack([saw * gate] * 2, axis=1).astype(np.float32) * 0.5
    r = features(x, 120)
    assert abs(r['pitch_st_bar'] + 12) < 1.5, r['pitch_st_bar']
    assert r['mod_div'] == 2 and abs(r['mod_hz'] - 4) < 0.2, (r['mod_div'], r['mod_hz'])


if __name__ == '__main__':
    _self_check()
    main()
