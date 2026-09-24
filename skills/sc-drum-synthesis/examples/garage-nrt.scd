// Usage: sclang -D -u CHECKED_FREE_UDP_PORT garage-nrt.scd /absolute/output.wav [seed] [fx]
// An 8-bar UK garage (2-step) loop approved in listening tests: 132 BPM, 62% swing on odd sixteenths, a dry
// rim under a tight clap on the backbeat, 808 hats that choke each other (also across the loop seam), a crash
// on bar 1 and fills in bars 4 and 8. Each voice renders to its own stereo pair; the mixdown sets each voice's
// loudest hit to a level relative to the kick, folds the decay tail back onto the start, and writes exactly
// 8 bars as 48 kHz int24 WAV, so the file loops without a seam. Seed 1 reproduces the approved file.
// With `fx`, every voice but the rim runs through its fxStrip preset (assets/fx.scd) before the stems; seed 1
// then reproduces the approved processed version.
(
var sr = 48000, bars = 8, bpm = 132, swing = 0.62, tail = 3, outPath, stemPath, seed, defs, kit, mixTargets, fx;
var pat, barOver, voices, stepDur, swingOff, loopFrames, loopDur, hitsFor, charAt, wrap, events, score, lastHat;
SystemClock.sched(120, { "[watchdog] forced exit".postln; 1.exit });
try {
    if(thisProcess.argv.isEmpty) { Error("Supply an absolute WAV output path.").throw };
    outPath = thisProcess.argv[0];
    stemPath = outPath ++ ".stems.wav";
    if(PathName(outPath).isAbsolutePath.not) { Error("Output path must be absolute.").throw };
    if(["$", "`", "\"", "\n", "\r", "\\"].any { |c| outPath.find(c).notNil }) {
        Error("Output path contains shell-sensitive characters unsupported by Score.recordNRT.").throw
    };
    if(File.exists(outPath) or: { File.exists(stemPath) }) { Error("Output exists; choose a new filename.").throw };
    seed = (thisProcess.argv.at(1) ? "1").asInteger;
    if(thisProcess.argv.at(2) == "fx") {
        fx = thisProcess.interpreter.executeFile(
            (thisProcess.nowExecutingPath.dirname +/+ "../assets/fx.scd").standardizePath
        )[\presets];
        tail = 5;                                            // room for the reverb tails
    };
    if("SC_SYNTH".getenv.notNil) { Score.program = "SC_SYNTH".getenv.shellQuote };
    TempoClock.default.tempo = 1;
    defs = thisProcess.interpreter.executeFile(
        (thisProcess.nowExecutingPath.dirname +/+ "../assets/synthdefs.scd").standardizePath
    );
    if(fx.notNil) {
        defs = defs.add(thisProcess.interpreter.executeFile(
            (thisProcess.nowExecutingPath.dirname +/+ "../assets/fx.scd").standardizePath
        )[\def]);
    };

    // Voice k renders to channels 2k, 2k+1; this order also fixes the order of random draws.
    voices = [\clap, \crash, \hat, \kick, \ohat, \rim];
    kit = (
        clap:  (def: \drumClap, freq: 1500, rq: 0.45, spread: 0.005, burst: 0.005, tail: 0.09, tailFreq: 2000),
        crash: (def: \drumCrash, pan: -0.2),
        hat:   (def: \drumHatClosed, pan: 0.15, decay: 0.09, tone: 0.6),
        kick:  (def: \drumKick, freq: 48, tone: 0.55),
        ohat:  (def: \drumHatOpen, pan: 0.15, decay: 0.7, tone: 0.6),
        rim:   (def: \drumRim, tone: 1.1, bodyDecay: 0.1, click: 0.7)
    );
    mixTargets = (kick: 0, clap: -3, rim: -5, hat: -12, ohat: -11, crash: -9);   // dB, loudest hit vs the kick

    // One char per sixteenth: X accent, x normal, o ghost, . rest, 2-6 = a roll of that many hits in the step.
    // 32-char strings are 2-bar patterns. barOver[n] replaces a voice for bar n + 1 only.
    pat = (
        kick: "x.........x.....x......x..x..x..",
        clap: "....x.......x...",
        rim:  "....x.......x.......x.......x..o",
        hat:  "..xo..xo..xo..xo..xo..xo..xo....",   // no hat right after the open hat: it rings to the next bar
        ohat: "..............................x."
    );
    barOver = [(crash: "x..............."), nil, nil, (clap: "....x.......x.o."), nil, nil, nil,
        (kick: "x......x........", rim: "....x...o..ox.xX")];

    hitsFor = { |c|   // -> [[fraction of the step, velocity], ...]
        case
        { c == $X } { [[0, 1.0]] }
        { c == $x } { [[0, 0.78]] }
        { c == $o } { [[0, 0.42]] }
        { c == $. } { [] }
        { c.isDecDigit and: { c.digit >= 2 } } {
            Array.fill(c.digit, { |k| [k / c.digit, 0.5 + (0.35 * k / (c.digit - 1))] })
        }
        { Error("Unknown pattern character: " ++ c).throw }
    };
    charAt = { |voice, bar, step|
        var over = barOver[bar], s = pat[voice];
        if(over.notNil and: { over[voice].notNil }) { s = over[voice] };
        if(s.isNil) { $. } { s[((bar * 16) + step) % s.size] }
    };
    // Fold every sample past n back onto the start (interleaved data; n is a whole number of frames).
    wrap = { |x, n|
        var y = x.copyRange(0, n - 1);
        (x.size - n).do { |k| y[k % n] = y[k % n] + x[n + k] };
        y
    };
    if(wrap.(FloatArray[1, 2, 3, 4, 5, 6, 7], 3) != FloatArray[12, 7, 9]) { Error("wrap self-check failed").throw };

    stepDur = 60 / bpm / 4;
    swingOff = (swing - 0.5) * 2 * stepDur;                  // odd sixteenths land 62% of the way through the eighth
    loopFrames = (bars * 4 * 60 / bpm * sr).round.asInteger;
    loopDur = loopFrames / sr;
    thisThread.randSeed = seed + "ukgarage".hash;           // seeding of the project that approved this loop
    events = List.new;
    bars.do { |bar| 16.do { |step|
        var t = (((bar * 16) + step) * stepDur) + (if(step.odd) { swingOff } { 0 });
        voices.do { |voice| hitsFor.(charAt.(voice, bar, step)).do { |h|
            events.add([t + (h[0] * stepDur), voice, (h[1] * (1 + 0.08.rand2)).clip(0.05, 1)])
        } }
    } };
    events = events.asArray.sort { |a, b| a[0] <= b[0] };

    score = Score.new;
    defs.do { |d| score.add([0, [\d_recv, d.asBytes]]) };
    // With fx, voice k writes to private bus 64 + 2k and a strip after the voices writes the stem to 2k, 2k+1.
    if(fx.notNil) {
        score.add([0, [\g_new, 2000, 3, 1]]);
        voices.do { |v, k| fx[v] !? { |preset|
            score.add([0, [\s_new, \fxStrip, 3000 + k, 0, 2000, \in, 64 + (2 * k), \out, 2 * k] ++ preset.asKeyValuePairs])
        } };
    };
    events.do { |e, k|
        var p = kit[e[1]], id = -1, msg;
        // Closed and open hat are one instrument: each hat hit chokes the hat still ringing.
        if([\hat, \ohat].includes(e[1])) {
            if(lastHat.notNil and: { e[0] < lastHat[1] }) { score.add([e[0], [\n_set, lastHat[0], \gate, 0]]) };
            id = 1000 + k;
            lastHat = [id, e[0] + p[\decay]];
        };
        msg = [\s_new, p[\def], id, 0, 1, \out, (voices.indexOf(e[1]) * 2) + (if(fx.notNil and: { fx[e[1]].notNil }) { 64 } { 0 }),
            \velocity, e[2], \seed, 100000.rand];
        p.keysValuesDo { |key, v| if(key != \def) { msg = msg ++ [key, v] } };
        score.add([e[0], msg]);
    };
    // Looped, the first hat hit follows the last one: choke across the seam too.
    events.detect { |e| [\hat, \ohat].includes(e[1]) } !? { |e|
        if(lastHat.notNil and: { (loopDur + e[0]) < lastHat[1] }) {
            score.add([loopDur + e[0], [\n_set, lastHat[0], \gate, 0]])
        }
    };
    score.add([loopDur + tail, [\c_set, 0, 0]]);
    score.sort;

    score.recordNRT(outputFilePath: stemPath, sampleRate: sr, headerFormat: "WAV", sampleFormat: "float",
        options: ServerOptions.new.numOutputBusChannels_(voices.size * 2).numInputBusChannels_(0).sampleRate_(sr),
        duration: loopDur + tail,
        action: { |status|
            try {
                var sf = SoundFile.new, nV = voices.size, nCh = voices.size * 2, frame = 0, peaks = 0 ! voices.size;
                var mix, chunk, gains, y, out, peak = 0, tailPeak = 0, gain;
                if(status != 0) { Error("scsynth NRT exited with " ++ status).throw };
                if(sf.openRead(stemPath).not) { Error("Cannot read NRT output " ++ stemPath).throw };
                if(sf.numChannels != nCh) { Error("Expected % channels, got %".format(nCh, sf.numChannels)).throw };
                // Pass 1: each voice's peak. Pass 2: sum the voices with gains that put those peaks on target.
                while { chunk = FloatArray.newClear(65536 * nCh); sf.readData(chunk); chunk.size > 0 } {
                    chunk.do { |x, i| var v = (i % nCh) div: 2; peaks[v] = peaks[v].max(x.abs) };
                };
                voices.do { |v, k| if(peaks[k] < 1e-3) { Error("Voice % is silent".format(v)).throw } };
                gains = voices.collect { |v, k| mixTargets[v].dbamp / peaks[k] };
                sf.seek(0);
                mix = FloatArray.newClear(sf.numFrames * 2);
                while { chunk = FloatArray.newClear(65536 * nCh); sf.readData(chunk); chunk.size > 0 } {
                    (chunk.size div: nCh).do { |f|
                        var o = f * nCh, l = 0, r = 0;
                        nV.do { |v| l = l + (chunk[o + (2 * v)] * gains[v]); r = r + (chunk[o + (2 * v) + 1] * gains[v]) };
                        mix[2 * (frame + f)] = l; mix[(2 * (frame + f)) + 1] = r;
                    };
                    frame = frame + (chunk.size div: nCh);
                };
                sf.close;
                File.delete(stemPath);
                (sr div: 10 * 2).do { |k| tailPeak = tailPeak.max(mix[mix.size - 1 - k].abs) };
                if(tailPeak > 1e-4) { Error("Tail still sounding at render end; raise `tail`").throw };
                y = wrap.(mix, loopFrames * 2);
                y.do { |s| peak = peak.max(s.abs) };
                gain = -1.dbamp / peak;
                y.size.do { |k| y[k] = y[k] * gain };
                out = SoundFile.new.headerFormat_("WAV").sampleFormat_("int24").numChannels_(2).sampleRate_(sr);
                if(out.openWrite(outPath).not) { Error("Cannot write " ++ outPath).throw };
                if(out.writeData(y) == false) { Error("writeData failed for " ++ outPath).throw };
                out.close;
                voices.do { |v, k| "VOICE % %dBFS".format(v, (peaks[k] * gains[k] * gain).ampdb.round(0.1)).postln };
                "RENDER_OK garage % frames".format(loopFrames).postln;
                0.exit
            } { |err| err.reportError; 1.exit }
        });
} { |err| err.reportError; 1.exit };
)
