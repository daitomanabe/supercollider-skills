// Delay-time zap: on each trigger a short feedback delay (a comb filter) lengthens from 1/hiFreq to 1/loFreq, so its
// resonance dives in pitch, and the Doppler shift of the moving delay line pulls the ringing down further. Evaluating
// this file returns an Array of SynthDefs (no boot, .add or playback):
//   fxZap: an insert on a stereo bus, retriggered by `t_trig` (sent at each hit) or, with `auto` 1, by the input's
//          own onsets; the wet sound speaks only for `sweep` + |ring| after each trigger, and `verb` sends the zapped
//          sound of that window to a reverb, so only zapped hits leave a tail;
//   seZap: a noise burst through the same sweep, a standalone laser, with the same reverb.
// Reverb: `predelay` s, a high-pass at `verbLo` on the send, FreeVerb2 with `room` and `damp`. verb 0 leaves it out
// (the output then equals the reverbless one sample for sample).
// fxZap's defaults are the setting a listener picked as the favourite zap: a tight clap diving from 3 kHz to 80 Hz over
// 0.35 s with a gentle curve (1.5), ringing 0.3 s, mix 0.7, and the reverb at 0.4 (room 0.8, damp 0.5). Listeners
// asked for the reverb whenever the zap sounds, so it defaults on in both SynthDefs. Other approved settings are in
// examples/zap-nrt.scd (one-shots) and examples/trap-se-nrt.scd (`zap`, `snarezap`: per-hit triggers in a loop).
(
var zapCore;

// p runs 0 -> 1 over `sweep` s after each trigger, shaped fast-first by `curve` (> 0), and moves the comb frequency
// from hiFreq to loFreq exponentially (a straight line in octaves when curve is small). CombC interpolates the delay
// (cubic), so its time can change every sample. `ring` is the comb's decay time in seconds: short keeps the feedback
// short; negative feeds back inverted, sounding odd harmonics an octave lower. The feedback gain is
// g = 0.001 ** (delay / ring); scaling by sqrt(1 - g^2) keeps the level of a noisy input steady while g changes.
zapCore = { |sig, trig, hiFreq, loFreq, sweep, curve, ring|
    var p = Sweep.ar(trig, sweep.reciprocal).min(1);
    var freq = hiFreq * ((loFreq / hiFreq) ** ((1 - exp(curve.neg * p)) / (1 - exp(curve.neg))));
    var delay = freq.reciprocal;
    var g = 0.001 ** (delay / ring.abs.max(0.001));
    CombC.ar(sig, 0.05, delay, ring) * (1 - g.squared).max(1e-4).sqrt
};

[
    SynthDef(\fxZap, { |in=64, out=0, t_trig=0, hiFreq=3000, loFreq=80, sweep=0.35, curve=1.5, ring=0.3,
            mix=0.7, drive=2, lp=9000, auto=0, thresh= -24, verb=0.4, room=0.8, damp=0.5, predelay=0.015, verbLo=200|
        var dry = In.ar(in, 2), trig, wet, win, open, main, rv;
        // A trigger per hit; `auto` also triggers on the input's onsets (level rising through `thresh` dBFS).
        trig = T2A.ar(t_trig) + (auto * Trig1.ar(Amplitude.ar(Mix(dry) * 0.5, 0.0005, 0.03) > thresh.dbamp, 0.05));
        wet = zapCore.(dry, trig, hiFreq, loFreq, sweep, curve, ring);
        wet = LPF.ar((wet * drive).tanh, lp);
        // Crossfade to the wet sound only in the window after a trigger, so untouched hits pass dry.
        win = LagUD.ar(Sweep.ar(trig, 1) < (sweep + ring.abs), 0.001, 0.02);
        open = win * mix;
        main = (dry * (1 - open)) + (wet * open);
        // The zapped sound of the window, and only that, feeds the reverb.
        rv = FreeVerb2.ar(*(HPF.ar(DelayN.ar(main * win, 0.1, predelay), verbLo) ++ [1, room, damp])) * verb;
        Out.ar(out, main + rv);
    }),

    SynthDef(\seZap, { |out=0, amp=0.5, velocity=0.78, pan=0, hiFreq=5000, loFreq=60, sweep=0.25, curve=3, ring=0.25,
            burst=0.004, noiseLo=400, width=0.3, drive=2, lp=10000, verb=0.4, room=0.8, damp=0.5, predelay=0.015,
            verbLo=200, verbTail=3, seed=1|
        // With a reverb the synth lives `verbTail` s longer, and the reverb fades over the last 5 % of that time.
        var exc, sig, rv, life = sweep + ring.abs + 0.1, total = life + (verbTail * (verb > 0)),
            done = Line.ar(1, 1, total, doneAction: 2);
        RandSeed.ir(1, seed);
        exc = HPF.ar(WhiteNoise.ar(1 ! 2), noiseLo) * EnvGen.ar(Env.perc(0.0002, 1, 1, -4), timeScale: burst);
        exc = [exc[0], (exc[0] * (1 - width)) + (exc[1] * width)];
        sig = zapCore.(exc, Impulse.ar(0), hiFreq, loFreq, sweep, curve, ring) * 4;
        sig = LPF.ar((sig * drive).tanh, lp) * EnvGen.ar(Env([1, 1, 0], [0.9, 0.1]), timeScale: life) * done;
        rv = FreeVerb2.ar(*(HPF.ar(DelayN.ar(sig, 0.1, predelay), verbLo) ++ [1, room, damp])) * verb
            * EnvGen.ar(Env([1, 1, 0], [0.95, 0.05]), timeScale: total);
        sig = sig + rv;
        Out.ar(out, Balance2.ar(sig[0], sig[1], pan) * amp * (0.4 + (0.6 * velocity.clip(0, 1))));
    })
]
)
