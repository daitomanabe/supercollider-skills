// Evaluate to obtain an Event: `def` is the fxStrip SynthDef (no boot, .add, or playback) and `presets` holds
// per-voice settings approved in listening tests for the voices in synthdefs.scd. The strip processes one voice's
// stereo bus like a produced one-shot: input gain, transient shaper, tanh saturation, Compander compressor,
// shelving EQ, stereo chorus, ping-pong delay send and FreeVerb2 send. Every stage defaults to off.
// references/sound-design.md has the measurements behind the presets; rendering.md shows the routing.
(
(
    def: SynthDef(\fxStrip, { |in=64, out=0, inGain=0, tAttack=0, tSustain=0, drive=0, thresh= -12, ratio=1,
            cAttack=0.005, cRelease=0.1, makeup=0, lowGain=0, lowFreq=120, highGain=0, highFreq=8000,
            chorus=0, chorusRate=0.7, chorusDepth=0.003, delay=0, delayTime=0.25, feedback=0.3, delayLp=5000,
            verb=0, room=0.5, damp=0.5, predelay=0.01, verbHp=300, verbLp=9000|
        var sig = In.ar(in, 2) * inGain.dbamp, mono, envF, envS, envL, fb, dl, rv;
        mono = Mix(sig) * 0.5;
        envF = LagUD.ar(mono.abs, 0.0005, 0.03);            // follows onsets and tails quickly
        envS = LagUD.ar(mono.abs, 0.02, 0.03);              // lags onsets: envF / envS > 1 marks an attack
        envL = LagUD.ar(mono.abs, 0.0005, 0.3);             // holds tails: envL / envF > 1 marks a decay
        sig = sig * (((envF + 1e-4) / (envS + 1e-4)).clip(1, 8) ** tAttack)
            * (((envL + 1e-4) / (envF + 1e-4)).clip(1, 10) ** tSustain);
        sig = Select.ar(drive > 0, [sig, (sig * drive.dbamp).tanh / drive.dbamp]);
        sig = Compander.ar(sig, Mix(sig) * 0.5, thresh.dbamp, 1, ratio.reciprocal, cAttack, cRelease) * makeup.dbamp;
        sig = BHiShelf.ar(BLowShelf.ar(sig, lowFreq, 1, lowGain), highFreq, 1, highGain);
        sig = sig + (DelayC.ar(sig, 0.05, 0.012 + (SinOsc.kr(chorusRate, [0, pi]) * chorusDepth)) * chorus);
        fb = LocalIn.ar(2);
        dl = LPF.ar(DelayC.ar((sig * delay) + (fb.reverse * feedback.clip(0, 0.95)), 2,
            (delayTime - ControlDur.ir).max(0.001)), delayLp);
        LocalOut.ar(dl);
        rv = FreeVerb2.ar(*(LPF.ar(HPF.ar(DelayN.ar(sig * verb, 0.2, predelay), verbHp), verbLp) ++ [1, room, damp]));
        // Saturating asymmetric hits adds DC; coef 0.9995 blocks it near 4 Hz (the default 0.995 cuts ~38 Hz of kick).
        Out.ar(out, LeakDC.ar(sig + dl + rv, 0.9995) * inGain.neg.dbamp);
    }),
    // inGain lifts a velocity-0.78 hit of the skill voice at its default amp to ~0 dBFS peak (measured raw peaks:
    // kick -21, snare -16, clap -23, closed hat -32, open hat -30, crash -15 dBFS), so thresholds and drive mean
    // the same for every voice. Compressor attack by role: 10 ms on the kick lets its transient through; 0.5 ms
    // elsewhere so compression lowers peaks instead of leaving a spike in front of the squeezed body.
    // hat is for drumHatClosed and ohat for drumHatOpen. Rims were kept dry at the listener's request.
    presets: (
        kick:  (inGain: 21, tAttack: 0.2, drive: 8, thresh: -12, ratio: 2.5, cAttack: 0.01, cRelease: 0.1),
        snare: (inGain: 16, tAttack: -0.6, tSustain: 1.0, thresh: -26, ratio: 5, cAttack: 0.0005, cRelease: 0.15,
            verb: 0.18, room: 0.4, predelay: 0.008),
        clap:  (inGain: 23, tAttack: -0.2, tSustain: 0.4, thresh: -24, ratio: 3, cAttack: 0.0005, cRelease: 0.15,
            verb: 0.32, room: 0.42, damp: 0.4, predelay: 0.01),
        hat:   (inGain: 32, tAttack: -0.3, tSustain: 0.5, thresh: -24, ratio: 4, cAttack: 0.0005, chorus: 0.2,
            verb: 0.03, room: 0.3),
        ohat:  (inGain: 30, tAttack: -0.6, tSustain: 0.3, thresh: -26, ratio: 4, cAttack: 0.0005, chorus: 0.2),
        crash: (inGain: 15, tAttack: -0.15, chorus: 0.7, verb: 0.6, room: 0.85)
    )
)
)
