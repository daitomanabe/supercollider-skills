// Tempo-synced sound effects and bass, matched to measured trap reference packs (scripts/analyze_se.py) and approved
// in listening tests at 140 BPM: downlifters (seDown, seLoDown, seSciDown), an impact, a sweep up, a modulated swell,
// an 808 and a synth bass. Evaluating this file returns an Array of SynthDefs (no boot, .add or playback). The effects
// take `beat` (seconds per beat), so lengths, gates and echoes follow the tempo; their lengths are given in beats.
// examples/se-nrt.scd holds the approved presets; examples/trap-se-nrt.scd places them in loops.
(
var tempoGate, supersaw, endFade;

// Level change over one modulation cycle, as an amplitude factor. Phase 0 is the beat the sound starts on, so the
// cycle stays on the grid. Shapes measured on trap sweeps (median fold of 8 bins per cycle):
// 0 pump: sidechain duck, deepest on the beat and back by 0.45 of the cycle, dB = -depth * (1 - (p / 0.45)^2);
// 1 gate: open for `duty` of the cycle, shut in 5 % of it, reopening from duty + 0.2 to the next beat;
// 2 trem: raised cosine, loudest on the beat. `decay` dB falls across the open part (retriggered-note feel).
tempoGate = { |rate, style, depth, duty, decay|
    var p = Sweep.ar(0, rate) % 1;
    var pump = (1 - (p / 0.45).squared).max(0);
    var gate = ((p - duty) / 0.05).clip(0, 1).min((1 - ((p - duty - 0.2) / (0.8 - duty))).clip(0, 1));
    var trem = 0.5 * (1 - cos(2pi * p));
    ((depth.neg * Select.ar(style, [pump, gate, trem])) - (decay * (p / duty).min(1))).dbamp
};

// Five band-limited saws detuned over +-detune semitones, spread across the stereo field.
supersaw = { |freq, detune, spread|
    Splay.ar(Array.fill(5, { |k| Saw.ar(freq * (detune * ((k / 2) - 1)).midiratio) }), spread)
};

// 1 until the last `frac` of a 0..1 ramp, then down to 0: effects with reverb or delay stop without a click.
endFade = { |ramp, frac = 0.05| ((1 - ramp) / frac).clip(0, 1) };

[
    // Downlifter (trap long sweep down): detuned saws (plus the same an octave up, `octave`, and a sine an octave
    // down, `sub`) whose pitch falls `drop` semitones linearly over `beats`, saturated, then a resonant low-pass
    // closing exponentially from cutHi to cutLo; level holds, then falls 30 dB from `fadeAt` (fraction of the length).
    // Reference median: -1.4 st/bar, roll-off 3.7 kHz -> 280 Hz, level flat for 3 bars then -2.5 dB/s.
    SynthDef(\seDown, { |out=0, amp=0.5, velocity=0.78, pan=0, beat=0.428571, beats=32, freq=262, drop= -12,
            cutHi=8000, cutLo=150, rq=0.6, detune=0.3, spread=1, octave=0.5, sub=0.15, noise=0.03, drive=3,
            modStyle=0, modDiv=1, modDepth=10, modDuty=0.5, modDecay=0, fadeAt=0.3, seed=1|
        var dur = beats * beat, t, pitch, cut, sig, level;
        RandSeed.ir(1, seed);                              // same seed, same noise (every noisy def below)
        t = Line.ar(0, 1, dur, doneAction: 2);
        pitch = freq * (drop * t).midiratio;
        cut = (cutHi * ((cutLo / cutHi) ** t)).clip(30, 18000);
        sig = supersaw.(pitch, detune, spread) + (supersaw.(pitch * 2, detune, spread) * octave);
        sig = ((sig + (SinOsc.ar(pitch * 0.5) * sub) + PinkNoise.ar(noise ! 2)) * drive).tanh;
        sig = LPF.ar(RLPF.ar(sig, cut, rq), (cut * 2.5).min(20000));
        level = (-30 * ((t - fadeAt) / (0.97 - fadeAt)).clip(0, 1)).dbamp * endFade.(t, 0.03);
        sig = sig * level * tempoGate.(modDiv / beat, modStyle, modDepth, modDuty, modDecay);
        Out.ar(out, Balance2.ar(sig[0], sig[1], pan) * amp * (0.4 + (0.6 * velocity.clip(0, 1))));
    }),

    // Lo-fi downlifter: mono sine + triangle diving `drop` semitones, fast first and slowing (`curve`), with
    // low-passed noise that follows the dive, sample-and-hold at `crush` Hz, `bits` quantisation and tanh.
    // pulseHi > 0 adds a decelerating chop (pulseHi -> pulseLo Hz, dipping to chopDb), the slow-down stutter heard
    // in the pack. Reference median: mono, 70-95 % below 100 Hz, -12 then -4 st/bar, level flat until 60 %, 3 bars.
    SynthDef(\seLoDown, { |out=0, amp=0.5, velocity=0.78, pan=0, beat=0.428571, beats=12, freq=98, drop= -22, curve=3,
            tri=1.5, noise=0.5, noiseCut=1500, crush=8000, bits=8, drive=4,
            pulseHi=0, pulseLo=3, pulseDuty=0.55, chopDb= -24, fadeAt=0.6, seed=1|
        var dur = beats * beat, t, st, pitch, sig, chop, level;
        RandSeed.ir(1, seed);
        t = Line.ar(0, 1, dur, doneAction: 2);
        st = drop * ((1 - exp(curve.neg * t)) / (1 - exp(curve.neg)));
        pitch = freq * st.midiratio;
        sig = SinOsc.ar(pitch) + (LFTri.ar(pitch) * tri) + LPF.ar(WhiteNoise.ar(noise), (noiseCut * st.midiratio).max(40));
        sig = Latch.ar(sig, Impulse.ar(crush));
        sig = (sig * (2 ** (bits - 1))).round(1) / (2 ** (bits - 1));
        sig = (sig * drive).tanh;
        chop = Select.ar(pulseHi > 0, [DC.ar(1), chopDb.dbamp + ((1 - chopDb.dbamp)
            * LagUD.ar(LFPulse.ar(XLine.kr(pulseHi.max(0.1), pulseLo, dur), 0, pulseDuty), 0.001, 0.004))]);
        level = (-38 * ((t - fadeAt) / (0.95 - fadeAt)).clip(0, 1)).dbamp * endFade.(t);
        Out.ar(out, Pan2.ar(LeakDC.ar(sig * chop * level), pan) * amp * (0.4 + (0.6 * velocity.clip(0, 1))));
    }),

    // Sci-fi downlifter: eight partials (inharmonic ratios) gliding down by different amounts so the chord bends
    // as it falls, fast first then settling; a sine two octaves down (`sub`) and a noise band follow; wide reverb.
    // Level rises 6 dB over the first 20 %, falls 30 dB from `fadeAt`. Reference median: -1.9 then -0.2 st/bar,
    // roll-off ~1 kHz, 15-30 % below 100 Hz, width 0.7-0.9.
    SynthDef(\seSciDown, { |out=0, amp=0.5, velocity=0.78, pan=0, beat=0.428571, beats=20, freq=220, drop= -6, curve=4,
            cut=1400, rq=0.7, sub=0.5, noise=0.15, verb=1, room=0.9, damp=0.35, fadeAt=0.5, tail=3, seed=1|
        var dur = beats * beat, t, life, glide, sig, level;
        RandSeed.ir(1, seed);
        t = Line.ar(0, 1, dur);
        life = Line.ar(0, 1, dur + tail, doneAction: 2);
        glide = drop * ((1 - exp(curve.neg * t)) / (1 - exp(curve.neg)));
        sig = [1, 1.5, 2.02, 2.99, 4.03, 5.1, 6.02, 7.9].collect { |r, k|
            var bend = [1.0, 0.8, 1.2, 0.9, 1.35, 0.7, 1.1, 1.5][k];
            Pan2.ar(VarSaw.ar(freq * r * (glide * bend).midiratio, k * 0.13, 0.3) * (k + 1).reciprocal.sqrt,
                [-0.8, 0.7, -0.4, 0.5, -0.9, 0.2, 0.9, -0.2][k])
        }.sum;
        sig = RLPF.ar(sig, cut * (glide * 0.5).midiratio, rq) + (SinOsc.ar(freq * 0.25 * glide.midiratio) * sub)
            + BPF.ar(PinkNoise.ar(noise ! 2), (freq * 4 * glide.midiratio).clip(60, 12000), 0.6);
        level = (-6 * (1 - (t / 0.2).clip(0, 1))).dbamp * (-30 * ((t - fadeAt) / (0.97 - fadeAt)).clip(0, 1)).dbamp
            * endFade.(t, 0.03);
        sig = sig * level;
        sig = sig + FreeVerb2.ar(sig[0], sig[1], 1, room, damp, verb);
        Out.ar(out, Balance2.ar(sig[0], sig[1], pan) * endFade.(life) * amp * (0.4 + (0.6 * velocity.clip(0, 1))));
    }),

    // Impact: sine boom swept from freq * sweep down to freq (30 ms), decaying in two stages (boomDecay s, then
    // boomTail of the level at 1.45 s), a noise burst whose low-pass falls, an optional inharmonic ring, optional
    // tempo echoes of the noise and ring, and a long dark reverb. Reference median: 70 % below 100 Hz, -8.5 dB at
    // 0.2 s, -21 dB at 1 s, then -6 dB/s; mono attack (width 0.14), fully decorrelated tail (1.0).
    SynthDef(\seImpact, { |out=0, amp=0.5, velocity=0.78, pan=0, beat=0.428571, freq=42, sweep=3, boom=0.9,
            boomDecay=0.15, boomTail=0.02, drive=2, noise=1.6, noiseDecay=0.45, noiseLo=120, noiseHi=5000, width=0.35,
            ring=0, ringFreq=820, ringDecay=1.5, verb=0.35, verbLo=60, room=1, damp=0.65, echo=0, echoBeats=1, feedback=0.45,
            life=8, seed=1|
        var tt, bm, nz, rg, dry, sig;
        RandSeed.ir(1, seed);
        tt = Line.ar(0, life, life, doneAction: 2);
        bm = SinOsc.ar(freq * (1 + ((sweep - 1) * exp(tt.neg / 0.03))))
            * (((1 - boomTail) * exp(tt.neg / boomDecay)) + (boomTail * exp(tt.neg / 1.45))) * (tt / 0.002).clip(0, 1);
        bm = (bm * drive).tanh * boom;
        nz = LPF.ar(HPF.ar(WhiteNoise.ar(1 ! 2), noiseLo), (noiseHi * exp(tt.neg / 0.6)) + 800) * exp(tt.neg / noiseDecay) * noise;
        nz = [nz[0], (nz[0] * (1 - width)) + (nz[1] * width)];
        // Left and right partials 0.3 % apart, so the ring beats slowly across the stereo field.
        rg = [1, 1.003].collect { |d| Mix(SinOsc.ar(ringFreq * d * [1, 1.51, 2.27, 3.03], 0, [1, 0.6, 0.4, 0.25])) }
            * exp(tt.neg / ringDecay) * (tt / 0.003).clip(0, 1) * ring;
        nz = nz + rg;
        nz = nz + (CombL.ar(nz, 2, (echoBeats * beat).min(2), (echoBeats * beat) * 3 / feedback.log10.neg) * echo);
        dry = bm + nz;
        // The reverb send is high-passed at verbLo: a dark tail with some sub, not a second boom (reference tail:
        // centroid ~300 Hz, 58 % below 100 Hz).
        sig = dry + (FreeVerb2.ar(HPF.ar(dry[0], verbLo), HPF.ar(dry[1], verbLo), 1, room, damp) * verb);
        Out.ar(out, Balance2.ar(sig[0], sig[1], pan) * endFade.(tt / life, 0.1) * amp * (0.4 + (0.6 * velocity.clip(0, 1))));
    }),

    // Sweep up: detuned saws plus a noise band, pitch rising `rise` semitones (fast first, `curve`), low-pass
    // opening cutLo -> cutHi, level from startDb to 0 dB (`levelCurve`: fast first), gated on the beat grid; the
    // source stops at `beats` and a ping-pong delay and reverb ring for `tailBeats`. Reference median: 4 bars,
    // +2.2 then +1.0 st/bar, roll-off 1.7 -> 4.9 kHz, quarter-note gate 11 dB deep, level -30 -> 0 dB, tail ~1.5 bars.
    SynthDef(\seRise, { |out=0, amp=0.5, velocity=0.78, pan=0, beat=0.428571, beats=16, tailBeats=8, freq=220, rise=7,
            curve=1.6, levelCurve=3, cutLo=1000, cutHi=8000, rq=0.5, detune=0.25, spread=0.8, noise=0.15, drive=1.5,
            startDb= -30, modStyle=1, modDiv=1, modDepth=15, modDuty=0.55, modDecay=5,
            delay=0.45, delayBeats=0.75, feedback=0.6, verb=0.6, room=0.9, seed=1|
        var dur = beats * beat, t, life, pitch, cut, src, fb, dl, rv;
        RandSeed.ir(1, seed);
        t = Line.ar(0, 1, dur);
        life = Line.ar(0, 1, dur + (tailBeats * beat), doneAction: 2);
        pitch = freq * (rise * (1 - ((1 - t) ** curve))).midiratio;
        cut = cutLo * ((cutHi / cutLo) ** t);
        src = supersaw.(pitch, detune, spread) + BPF.ar(WhiteNoise.ar(noise ! 2), cut.min(16000), 1);
        src = (LPF.ar(RLPF.ar(src, cut, rq), (cut * 2).min(20000)) * drive).tanh;
        src = src * (startDb * ((1 - t) ** levelCurve)).dbamp * ((1 - t) * dur / 0.01).clip(0, 1)
            * tempoGate.(modDiv / beat, modStyle, modDepth, modDuty, modDecay);
        fb = LocalIn.ar(2);
        dl = LPF.ar(DelayC.ar((src * delay) + (fb.reverse * feedback.clip(0, 0.95)), 2,
            ((delayBeats * beat) - ControlDur.ir).max(0.001)), 5000);
        LocalOut.ar(dl);
        rv = FreeVerb2.ar(src[0], src[1], 1, room, 0.5) * verb;
        src = (src + dl + rv) * endFade.(life);
        Out.ar(out, Balance2.ar(src[0], src[1], pan) * amp * (0.4 + (0.6 * velocity.clip(0, 1))));
    }),

    // Modulated SE: a detuned four-note chord (0, n2, n3, n4 semitones) swelling from startDb to `beats`, gated on
    // the grid, then stopped by an accent (`accent`: noise burst plus the open chord, 0.15 s); tempo echoes and
    // reverb carry it for `tailBeats`. Extra modulation: `wobble` semitones of vibrato at wobbleDiv per beat, `snh`
    // octaves of stepped random cutoff at snhDiv per beat. Reference median: no pitch drift, peak ~3 bars then
    // -13 dB within 50 ms, quarter gate 14 dB deep, centroid ~1.5 kHz, width 0.8-0.9.
    SynthDef(\seMod, { |out=0, amp=0.5, velocity=0.78, pan=0, beat=0.428571, beats=12, tailBeats=8, freq=330,
            n2=7, n3=12, n4=15, cutLo=1800, cutHi=7000, rq=0.5, detune=0.3, spread=1, noise=0.08, drive=1.5, startDb= -30,
            modStyle=1, modDiv=1, modDepth=18, modDuty=0.5, modDecay=1, wobble=0, wobbleDiv=3, snh=0, snhDiv=4,
            accent=1, delay=0.6, delayBeats=1, feedback=0.55, verb=1, room=0.9, seed=1|
        var dur = beats * beat, t, life, pitch, cut, chord, src, acc, fb, dl, rv;
        RandSeed.ir(1, seed);
        t = Line.ar(0, 1, dur);
        life = Line.ar(0, 1, dur + (tailBeats * beat), doneAction: 2);
        pitch = freq * (wobble * SinOsc.ar(wobbleDiv / beat)).midiratio;
        cut = cutLo * ((cutHi / cutLo) ** t) * (2 ** (snh * Latch.ar(WhiteNoise.ar, Impulse.ar(snhDiv / beat))));
        chord = [0, n2, n3, n4].collect { |n| supersaw.(pitch * n.midiratio, detune, spread) }.sum * 0.5
            + BPF.ar(WhiteNoise.ar(noise ! 2), cut.clip(60, 16000), 1);
        chord = HPF.ar((LPF.ar(RLPF.ar(chord, cut.clip(40, 18000), rq), (cut * 2).clip(40, 20000)) * drive).tanh, 120);
        src = chord * (startDb * ((1 - t) ** 1.5)).dbamp * ((1 - t) * dur / 0.01).clip(0, 1)
            * tempoGate.(modDiv / beat, modStyle, modDepth, modDuty, modDecay);
        // t holds at 1 from `beats` on, which opens the gate of the accent's percussive envelope.
        acc = ((HPF.ar(WhiteNoise.ar(1 ! 2), 600) * 0.7) + chord) * EnvGen.ar(Env.perc(0.001, 0.15, 1, -4), t >= 0.9999) * accent * 2;
        src = src + acc;
        fb = LocalIn.ar(2);
        dl = LPF.ar(DelayC.ar((src * delay) + (fb.reverse * feedback.clip(0, 0.95)), 2,
            ((delayBeats * beat) - ControlDur.ir).max(0.001)), 6000);
        LocalOut.ar(dl);
        rv = FreeVerb2.ar(src[0], src[1], 1, room, 0.5) * verb;
        src = (src + dl + rv) * endFade.(life);
        Out.ar(out, Balance2.ar(src[0], src[1], pan) * amp * (0.4 + (0.6 * velocity.clip(0, 1))));
    }),

    // 808 bass: sine (plus `tone` of the octave) with a short upward pitch punch on attack, sliding from `from`
    // semitones to the note over `glide` s (a slide note skips the punch), tanh drive, decay `decay` s, cut after
    // `len` s so the next note of a mono line takes over. Reference (kick & sub loops): centroid 54 Hz, mono.
    SynthDef(\bass808, { |out=0, amp=0.5, velocity=0.78, pan=0, freq=43.65, from=0, glide=0.09, punch=1.2,
            decay=1.6, drive=2.5, tone=0.2, len=4|
        var tt, pitch, sig;
        tt = Line.ar(0, len + 0.02, len + 0.02, doneAction: 2);
        pitch = freq * (from * EnvGen.ar(Env([1, 0], [1], -3), timeScale: glide)).midiratio
            * (1 + (punch * (from.abs < 0.01) * EnvGen.ar(Env([1, 0], [1], -6), timeScale: 0.05)));
        sig = SinOsc.ar(pitch) + (SinOsc.ar(pitch * 2) * tone);
        sig = (sig * drive).tanh * EnvGen.ar(Env.perc(0.002, 1, 1, -3), timeScale: decay) * ((len - tt) / 0.012).clip(0, 1);
        Out.ar(out, Pan2.ar(LeakDC.ar(sig), pan) * amp * (0.4 + (0.6 * velocity.clip(0, 1))));
    }),

    // Synth bass: two saws detuned +-detune semitones (left/right; `width` 0 = both in the middle) plus a square,
    // through a resonant low-pass that falls from cutHi to cutLo over `decay` s each note, with a mono sine an octave
    // down (`sub`; 0 when an 808 plays the low end). Above 200 Hz the right side is delayed `spreadMs` for width; the
    // lows stay mono. Slides like bass808; held for `len` s. Reference (bass loops): centroid ~340 Hz, roll-off
    // ~1 kHz, width 0.34 (0.77 in the tails). Pitched an octave above the 808 so the two can be layered.
    SynthDef(\bassSynth, { |out=0, amp=0.5, velocity=0.78, pan=0, freq=174.61, from=0, glide=0.06, decay=0.45,
            cutHi=3500, cutLo=600, rq=0.3, sub=0.3, detune=0.2, width=0.8, drive=4, spreadMs=5, len=0.5|
        var tt, pitch, cut, osc, sig, hi;
        tt = Line.ar(0, len + 0.02, len + 0.02, doneAction: 2);
        pitch = freq * (from * EnvGen.ar(Env([1, 0], [1], -3), timeScale: glide)).midiratio;
        cut = cutLo * ((cutHi / cutLo) ** EnvGen.ar(Env([1, 0], [1], -4), timeScale: decay));
        osc = [Saw.ar(pitch * detune.midiratio), Saw.ar(pitch * detune.neg.midiratio)] + (Pulse.ar(pitch, 0.4) * 0.5);
        osc = [osc[0] + (osc[1] * (1 - width)), osc[1] + (osc[0] * (1 - width))] * 0.5;
        sig = RLPF.ar(osc, cut, rq) + (SinOsc.ar(pitch * 0.5) * sub);
        sig = LeakDC.ar((sig * drive).tanh) * (tt / 0.003).clip(0, 1) * ((len - tt) / 0.012).clip(0, 1);
        hi = HPF.ar(sig, 200);
        sig = [sig[0], sig[1] - hi[1] + DelayC.ar(hi[1], 0.03, spreadMs / 1000)];
        Out.ar(out, Balance2.ar(sig[0], sig[1], pan) * amp * (0.4 + (0.6 * velocity.clip(0, 1))));
    })
]
)
