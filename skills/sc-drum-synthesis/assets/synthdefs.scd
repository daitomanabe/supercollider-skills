// Evaluate to obtain an Array of stock-core SynthDefs; no boot, .add, or playback.
// drumClap, the hats, drumCrash and drumRim were rebuilt after one-shot listening tests; the measurements
// behind each change are in references/sound-design.md. Kick and snare are unchanged.
(
var hat = { |name, decay|
    // TR-808 square set (205-800 Hz): its odd harmonics are dense above 7 kHz, and a 24 dB/oct high-pass
    // keeps only that band. Six squares at 0.9-2.3 kHz behind 12 dB/oct left pitched partials below 5 kHz
    // that read as a cowbell. gate 0 (n_set) chokes a ringing hat within 15 ms, as the next hat hit does.
    SynthDef(name, { |out=0, amp=0.35, pan=0, tone=0.5, velocity=0.8, gate=1|
        var dec = \decay.kr(decay);
        var v = velocity.clip(0, 1), t = tone.clip(0, 1), cut = 6500 + (t * 1500) + (v * 1000);
        var metal = Mix(Pulse.ar([205.3, 304.4, 369.6, 522.7, 540, 800] * (0.85 + (t * 0.3)))) / 6;
        var sig = HPF.ar(HPF.ar(metal, cut), cut);
        var env = EnvGen.ar(Env.perc(0.0005, 1, 1, -4), timeScale: dec.clip(0.02, 2), doneAction: 2);
        var choke = EnvGen.ar(Env.cutoff(0.015), gate, doneAction: 2);
        sig = sig + (BPF.ar(sig, 10500, 0.5) * 0.8);
        Out.ar(out, Pan2.ar(LeakDC.ar(sig) * env * choke * amp.clip(0, 1) * v, pan.clip(-1, 1)));
    })
};
[
    SynthDef(\drumKick, { |out=0, freq=48, amp=0.25, pan=0, tone=0.5, velocity=0.8, seed=1|
        var pitch, env, sub, mid, click, drive, sig;
        var v = velocity.clip(0, 1), t = tone.clip(0, 1), f = freq.clip(25, 120);
        RandSeed.ir(1, seed);
        pitch = EnvGen.ar(Env([f * (4 + (t * 4)), f * 1.05, f], [0.012, 0.04], [-6, -3]));
        env = EnvGen.ar(Env.perc(0.001, 0.35, 1, -6), doneAction: 2);
        sub = LPF.ar(SinOsc.ar(pitch) * env, 80);
        mid = BPF.ar(SinOsc.ar(pitch * 2), 160 + (t * 60), 0.7)
            * EnvGen.ar(Env.perc(0.001, 0.06, 1, -8)) * (0.5 + (t * 0.4));
        click = BPF.ar(WhiteNoise.ar, 3000 + (t * 3000), 0.6)
            * EnvGen.ar(Env.perc(0.0001, 0.004, 1, -12)) * (0.15 + (t * 0.35));
        drive = 1.2 + (t * 1.5) + (v * 1.5);
        sig = ((sub + mid + click) * drive).tanh / drive.sqrt;
        Out.ar(out, Pan2.ar(LeakDC.ar(sig) * amp.clip(0, 1) * v, pan.clip(-1, 1)));
    }),
    SynthDef(\drumSnare, { |out=0, freq=200, amp=0.3, pan=0, tone=0.5, velocity=0.8, seed=1|
        var pitch, body, hi, mid, wires, env, sig;
        var v = velocity.clip(0, 1), t = tone.clip(0, 1), f = freq.clip(80, 600);
        RandSeed.ir(1, seed);
        pitch = EnvGen.ar(Env([f * 2.5, f * 1.1, f], [0.005, 0.02], [-8, -4]));
        env = EnvGen.ar(Env.perc(0.0003, 0.16, 1, -6), doneAction: 2);
        body = BPF.ar(SinOsc.ar(pitch), 250 + (t * 100), 0.5)
            * EnvGen.ar(Env.perc(0.0003, 0.12, 1, -6));
        hi = BPF.ar(WhiteNoise.ar, 5000 + (t * 3000), 0.5)
            * EnvGen.ar(Env.perc(0.0003, 0.035, 1, -8)) * (0.2 + (v * 0.6));
        mid = BPF.ar(WhiteNoise.ar, 1200 + (t * 800), 0.5)
            * EnvGen.ar(Env.perc(0.001, 0.06, 0.7, -6)) * (0.3 + (v * 0.5));
        wires = CombL.ar(HPF.ar(WhiteNoise.ar, 3000), 0.01, 0.003, 0.04)
            * EnvGen.ar(Env.perc(0.005, 0.08, 0.35, -4));
        sig = ((body + hi + mid + wires) * (1.2 + (v * 1.5))).tanh * env;
        Out.ar(out, Pan2.ar(LeakDC.ar(sig) * amp.clip(0, 1) * v, pan.clip(-1, 1)));
    }),
    // Clap: up to four noise bursts `spread` s apart (gains g1-g4) through one band, then a room tail.
    // Fixed burst timing made every clap variant sound alike; see the presets in references/sound-design.md.
    SynthDef(\drumClap, { |out=0, amp=0.6, pan=0, velocity=0.8, freq=1200, rq=0.5, spread=0.009,
            g1=1, g2=0.85, g3=0.7, g4=0, burst=0.006, tail=0.12, tailFreq=1600, seed=1|
        var v = velocity.clip(0, 1), sp = spread.clip(0.002, 0.03), drive = 1.4 + v;
        var bursts, room, sig;
        RandSeed.ir(1, seed);
        bursts = Mix([g1, g2, g3, g4].collect { |g, i|
            DelayN.ar(WhiteNoise.ar * EnvGen.ar(Env.perc(0.0002, 1, 1, -8), timeScale: burst.clip(0.002, 0.03)), 0.1, sp * i) * g
        });
        room = DelayN.ar(BPF.ar(WhiteNoise.ar, tailFreq.clip(500, 6000), 0.6)
            * EnvGen.ar(Env.perc(0.004, 1, 0.45, -4), timeScale: tail.clip(0.02, 1)), 0.1, sp * 2);
        sig = BPF.ar(bursts, freq.clip(400, 5000), rq.clip(0.1, 2)) + room;
        sig = (sig * drive).tanh / drive.sqrt * Line.kr(1, 1, tail.clip(0.02, 1) + (sp * 4) + 0.05, doneAction: 2);
        Out.ar(out, Pan2.ar(LeakDC.ar(sig) * amp.clip(0, 1) * v, pan.clip(-1, 1)));
    }),
    hat.(\drumHatClosed, 0.1),
    hat.(\drumHatOpen, 0.7),
    // Crash: broadband noise plus the 808 metal, darkening as it decays. A Ringz resonator bank put 99.8% of
    // its energy into 20 FFT bins (pure tones at 3.1/4.0/5.4 kHz) and was heard as a bell, not a cymbal.
    SynthDef(\drumCrash, { |out=0, amp=0.3, pan=0, tone=0.5, velocity=0.8, decay=1.6, seed=1|
        var v = velocity.clip(0, 1), t = tone.clip(0, 1);
        var noise, metal, sig, env, bright;
        RandSeed.ir(1, seed);
        noise = WhiteNoise.ar;
        metal = Mix(Pulse.ar([205.3, 304.4, 369.6, 522.7, 540, 800] * 1.7)) / 6;
        env = EnvGen.ar(Env.perc(0.002, 1, 1, -4), timeScale: decay.clip(0.3, 4), doneAction: 2);
        bright = EnvGen.kr(Env([14000, 5000], [1], [-3]), timeScale: decay.clip(0.3, 4));
        sig = LPF.ar(HPF.ar((noise * 0.7) + (metal * 0.5), 3000 + (t * 2000)), bright);
        sig = sig + (BPF.ar(noise, 7500, 0.8) * 0.4);
        Out.ar(out, Pan2.ar(LeakDC.ar(sig) * env * amp.clip(0, 1) * v, pan.clip(-1, 1)));
    }),
    // Rim, dry and unpitched: band-passed noise knocks for `bodyDecay` s; eight inharmonic modes over
    // 0.7-5 kHz ring only `decay` s (a few cycles) to colour it like wood; click and optional wire hiss.
    // Sine-partial rims measured autocorrelation 0.69-0.87 and were heard as pitched.
    SynthDef(\drumRim, { |out=0, amp=0.5, pan=0, velocity=0.8, tone=1.1, decay=0.005, body=1, bodyDecay=0.1,
            click=0.7, wires=0, width=0, seed=1|
        var v = velocity.clip(0, 1), w = width.clip(0, 1), t = tone.clip(0.3, 3);
        var exc, modes, knock, clk, wire, sig;
        RandSeed.ir(1, seed);
        exc = WhiteNoise.ar * EnvGen.ar(Env.perc(0.0002, 0.002, 1, -6));
        modes = Klank.ar(`[[733, 1117, 1583, 2087, 2671, 3319, 4129, 5003], [0.6, 0.8, 1, 1, 0.9, 0.8, 0.7, 0.6], 1 ! 8],
            exc, t, 0, decay.clip(0.001, 0.03));
        knock = BPF.ar(WhiteNoise.ar, 1800 * t, 1) * body
            * EnvGen.ar(Env.perc(0.0005, 1, 1, -6), timeScale: bodyDecay.clip(0.01, 0.3));
        clk = HPF.ar(WhiteNoise.ar, 2500) * EnvGen.ar(Env.perc(0.0001, 0.0015, 1, -8)) * click;
        wire = HPF.ar(WhiteNoise.ar(1 ! 2), 2500) * EnvGen.ar(Env.perc(0.001, 0.05, 1, -5)) * wires;
        wire = [wire[0], (wire[0] * (1 - w)) + (wire[1] * w)];
        sig = (((modes * 6) + knock + clk + wire) * 2).tanh * Line.kr(1, 1, 0.35, doneAction: 2);
        Out.ar(out, Balance2.ar(sig[0], sig[1], pan.clip(-1, 1)) * amp.clip(0, 1) * v);
    })
]
)
