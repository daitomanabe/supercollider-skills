// Stutter gestures after iZotope Stutter Edit 2: for a set length after each trigger, the sound is replaced by
// repeats of the slice that starts at the trigger, and every setting can move across the gesture (start -> end).
// Evaluating this file returns an Array with one SynthDef (no boot, .add or playback):
//   stutterPlay: plays a stereo buffer (a rendered loop) from its start to `out`; `n_set` a gesture's settings with
//   `t_trig` 1 at the time it starts. Outside gestures the buffer passes through sample for sample.
// Gesture settings (lengths in beats; `beat` = seconds per beat; A -> B moves across the gesture):
//   dur          gesture length;
//   offset       where the repeated slice starts, in beats from the trigger (Buffer Position; -0.25 = the 1/16
//                before it, useful when the gesture starts between hits);
//   divA, divB   repeat length, e.g. 0.5 (1/8 note) -> 0.0625 (1/64); a third of a beat is a 1/8 triplet;
//   curve        shape of that move (0 = straight in log time; > 0 faster at first, < 0 later, as in lincurve);
//   step         1 snaps the repeat length to divA times powers of two (1/8, 1/16, 1/32 ... in turn);
//   width        part of each repeat that sounds (1 = all); each repeat opens in 2 ms and closes in 4 ms;
//   reverse      1 plays each repeat backwards;
//   pitchA/B     semitones; jitter adds a random +-jitter semitones per repeat; pan swings alternate repeats;
//   hpA/B, lpA/B filter sweeps in Hz; bitsA/B and crushA/B (sample rate in Hz) for lo-fi; gainA/B in dB;
//   tape         1 turns the gesture into a tape stop: the read head slows from full speed to a halt.
// `n_set` changes only the settings it names, so send every setting with each gesture (defaults plus the gesture's
// own), or a reverse or pitch from the previous gesture carries over. examples/stutter-nrt.scd holds the ten gestures
// approved in listening and renders them on a loop.
(
[
    SynthDef(\stutterPlay, { |out=0, buf=0, t_trig=0, beat=0.5, dur=1, offset=0, divA=0.25, divB=0.25, curve=0, step=0,
            width=1, reverse=0, pitchA=0, pitchB=0, jitter=0, pan=0, hpA=20, hpB=20, lpA=20000, lpB=20000,
            bitsA=24, bitsB=24, crushA=48000, crushB=48000, gainA=0, gainB=0, tape=0, seed=1|
        var sr = SampleRate.ir, trig, pos, dry, armed, el, gdur, g, act, g0, div, len, tp, rep, rate, off, tapeOff;
        var wet, env, cnt, side, bits, crush;
        RandSeed.ir(1, seed);
        trig = T2A.ar(t_trig);
        // Playback position counts whole samples (exact in float up to 2^24 frames), so the dry path is the buffer.
        pos = Phasor.ar(0, 1, 0, BufFrames.ir(buf));
        dry = BufRd.ar(2, buf, pos, 0, 1);
        armed = PulseCount.ar(trig) > 0;                    // nothing happens before the first gesture
        el = Sweep.ar(trig, 1);                             // seconds since the gesture started
        gdur = dur * beat;
        g = (el / gdur).clip(0, 1);                         // progress 0 -> 1
        // 4 ms linear crossfades in and out, ending exactly at the gesture's end (a loop seam stays dry).
        act = armed * (el / 0.004).clip(0, 1).min(((gdur - el) / 0.004).clip(0, 1));
        g0 = Latch.ar(pos, trig) + (offset * beat * sr);    // where the gesture's slice starts
        div = divA * ((divB / divA) ** g.lincurve(0, 1, 0, 1, curve));
        div = Select.ar(step, [div, divA * (2 ** (div / divA).log2.round)]);
        len = div * beat * sr;                              // repeat length in samples
        tp = Phasor.ar(trig, 1, 0, len);                    // position inside the current repeat
        rep = (HPZ1.ar(tp) < 0) + trig;                     // a new repeat starts
        rate = (pitchA + ((pitchB - pitchA) * g) + TRand.ar(jitter.neg, jitter, rep)).midiratio;
        off = Select.ar(reverse, [tp * rate, (len - tp) * rate]);
        // Tape stop: speed falls from 1 to 0 as (1 - g)^2; the offset is its running integral.
        tapeOff = Sweep.ar(trig, sr * (1 - g).squared);
        off = Select.ar(tape, [off, tapeOff]);
        wet = BufRd.ar(2, buf, g0 + off, 0, 4);
        env = (tp / (0.002 * sr)).clip(0, 1) * (((width * len) - tp) / (0.004 * sr)).clip(0, 1);
        wet = wet * Select.ar(tape, [env, DC.ar(1)]);
        cnt = PulseCount.ar(rep, trig);
        side = ((cnt % 2) * 2) - 1;
        wet = Balance2.ar(wet[0], wet[1], (side * pan).clip(-1, 1));
        wet = LPF.ar(HPF.ar(wet, hpA * ((hpB / hpA) ** g)), lpA * ((lpB / lpA) ** g));
        // Lo-fi: hold samples at `crush` Hz and quantize to `bits`; at 48000 and 24 it leaves the sound alone.
        crush = crushA * ((crushB / crushA) ** g);
        bits = bitsA + ((bitsB - bitsA) * g);
        wet = Select.ar(crush < (sr * 0.99), [wet, Latch.ar(wet, Impulse.ar(crush))]);
        wet = Select.ar(bits < 23.9, [wet, (wet * (2 ** (bits - 1))).round(1) / (2 ** (bits - 1))]);
        wet = wet * (gainA + ((gainB - gainA) * g)).dbamp;
        Out.ar(out, (dry * (1 - act)) + (wet * act));
    })
]
)
