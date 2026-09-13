// Evaluate to obtain an Array of stock-core SynthDefs; no boot, .add, or playback.
(
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
    SynthDef(\drumClap, { |out=0, freq=1200, amp=0.35, pan=0, tone=0.5, velocity=0.8, seed=1|
        var a, b, c, tail, life, sig;
        var v = velocity.clip(0, 1), t = tone.clip(0, 1), f = freq.clip(500, 3000);
        RandSeed.ir(1, seed);
        a = BPF.ar(WhiteNoise.ar, f + (800 * t), 0.4)
            * EnvGen.ar(Env.perc(0.0001, 0.006, 1, -10));
        b = BPF.ar(WhiteNoise.ar, f + (600 * t), 0.5)
            * EnvGen.ar(Env([0, 0, 1, 0], [0.008, 0.0001, 0.005], [0, 0, -10]));
        c = BPF.ar(WhiteNoise.ar, f + (1000 * t), 0.35)
            * EnvGen.ar(Env([0, 0, 1, 0], [0.014, 0.0001, 0.004], [0, 0, -12]));
        tail = BPF.ar(WhiteNoise.ar, 1800 + (1200 * t), 0.3)
            * EnvGen.ar(Env.perc(0.015, 0.08, 0.4, -4));
        life = EnvGen.ar(Env.linen(0.0001, 0.12, 0.01), doneAction: 2);
        sig = ((a + (b * 0.7) + (c * 0.5) + tail) * (1.4 + v)).tanh * life;
        Out.ar(out, Pan2.ar(LeakDC.ar(sig) * amp.clip(0, 1) * v, pan.clip(-1, 1)));
    }),
    SynthDef(\drumHatClosed, { |out=0, freq=880, amp=0.35, pan=0, tone=0.5, velocity=0.8, seed=1|
        var ratios = [1.0, 1.4471, 1.6170, 1.9265, 2.5028, 2.6637];
        var v = velocity.clip(0, 1), t = tone.clip(0, 1), f = freq.clip(200, 1600);
        var metal, env;
        RandSeed.ir(1, seed);
        metal = Mix(ratios.collect { |ratio| Pulse.ar(f * ratio * (1 + (t * 0.3)), 0.5) }) / ratios.size;
        metal = HPF.ar(metal, 4000 + (v * 2000));
        env = EnvGen.ar(Env.perc(0.0003, 0.035, 1, -9), doneAction: 2);
        Out.ar(out, Pan2.ar(LeakDC.ar(metal) * env * amp.clip(0, 1) * v, pan.clip(-1, 1)));
    }),
    SynthDef(\drumHatOpen, { |out=0, freq=880, amp=0.3, pan=0, tone=0.5, velocity=0.8, decay=0.18, seed=1|
        var ratios = [1.0, 1.4471, 1.6170, 1.9265, 2.5028, 2.6637];
        var v = velocity.clip(0, 1), t = tone.clip(0, 1), f = freq.clip(200, 1600);
        var metal, env;
        RandSeed.ir(1, seed);
        metal = Mix(ratios.collect { |ratio|
            Pulse.ar(f * ratio * (1 + (t * 0.3)), 0.5) * SinOsc.ar(f * ratio * 1.5, 0, 0.25, 0.75)
        }) / ratios.size;
        metal = HPF.ar(metal, 3500 + (v * 1500));
        env = EnvGen.ar(Env.perc(0.0003, decay.clip(0.04, 1), 1, -5), doneAction: 2);
        Out.ar(out, Pan2.ar(LeakDC.ar(metal) * env * amp.clip(0, 1) * v, pan.clip(-1, 1)));
    }),
    SynthDef(\drumCrash, { |out=0, freq=3100, amp=0.3, pan=0, tone=0.5, velocity=0.8, seed=1|
        var ratios = [1.0, 1.283, 1.745, 2.171, 2.674, 3.261, 3.945, 4.745];
        var decays = [0.8, 0.65, 0.55, 0.45, 0.35, 0.3, 0.25, 0.2];
        var v = velocity.clip(0, 1), t = tone.clip(0, 1), f = freq.clip(1500, 4500);
        var excite, metal, noise, env, sig;
        RandSeed.ir(1, seed);
        excite = PinkNoise.ar * EnvGen.ar(Env.perc(0.0001, 0.005, 1, -8));
        metal = Mix.fill(ratios.size, { |i|
            Ringz.ar(excite, (f * ratios[i]).min(SampleRate.ir * 0.45), decays[i] * (0.6 + v)) * (0.12 / (i + 1))
        });
        noise = HPF.ar(PinkNoise.ar, 5000) * EnvGen.ar(Env.perc(0.002, 0.15, 0.1, -5));
        env = EnvGen.ar(Env.perc(0.001, 0.6 + (v * 0.5), 1, -4), doneAction: 2);
        sig = (HPF.ar(metal, 2200 + (t * 1000)) + noise).tanh * env;
        Out.ar(out, Pan2.ar(LeakDC.ar(sig) * amp.clip(0, 1) * v, pan.clip(-1, 1)));
    })
]
)
