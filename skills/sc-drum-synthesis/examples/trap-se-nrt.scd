// Usage: sclang -D -u CHECKED_FREE_UDP_PORT trap-se-nrt.scd /absolute/output.wav [seed]
//            [drop|sweep|scifi|bass808|synbass|zap|snarezap]
// Listening-approved 8-bar trap loops at 140 BPM with sound effects at the head and a mono bass line:
//   drop:  impact + lo-fi sub dive on bar 1, a 2-bar sweep up into the loop point, 808 bass;
//   sweep: impact + an 8-bar trap downlifter that pumps on the quarter notes, 808 plus a synth bass an octave up;
//   scifi: impact with quarter-note echoes + sci-fi downlifter on bar 1, a 4-bar sweep up from bar 5, 808 bass;
//   bass808 / synbass: the two bass lines alone;
//   zap:   the drop with every clap through a quick delay-time zap and its reverb, and a laser in bars 4 and 8;
//   snarezap: the drop with every snare through the favourite zap (a slow dive) and its reverb.
// Voices come from assets/synthdefs.scd, assets/se_bass.scd and assets/zap.scd. Each voice renders to its own stereo
// pair; the mixdown sets each voice's loudest hit relative to the kick, folds every tail (the riser's echoes included)
// back onto the start, and writes exactly 8 bars as 48 kHz int24 WAV, so the file loops without a seam. Seed 1
// reproduces the approved files.
(
var sr = 48000, bars = 8, bpm = 140, outPath, stemPath, seed, variant, defs, kit, mixTargets, claps, zaps, loops, g;
var beat, stepDur, loopFrames, loopDur, tail, voices, hitsFor, charAt, wrap, events, score, lastHat;
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
    variant = thisProcess.argv.at(2) ? "drop";
    if("SC_SYNTH".getenv.notNil) { Score.program = "SC_SYNTH".getenv.shellQuote };
    TempoClock.default.tempo = 1;
    defs = ["../assets/synthdefs.scd", "../assets/se_bass.scd", "../assets/zap.scd"].collect { |f|
        thisProcess.interpreter.executeFile((thisProcess.nowExecutingPath.dirname +/+ f).standardizePath)
    }.flatten;

    // `mono` voices play one note at a time: a note lasts until the voice's next note, at most `mono` beats.
    kit = (
        kick:    (def: \drumKick),
        snare:   (def: \drumSnare),
        clap:    (def: \drumClap),
        hat:     (def: \drumHatClosed, pan: 0.15, decay: 0.1),
        impact:  (def: \seImpact),
        down:    (def: \seDown),
        lodown:  (def: \seLoDown),
        scidown: (def: \seSciDown),
        rise:    (def: \seRise),
        bass:    (def: \bass808, mono: 4),
        synbass: (def: \bassSynth, mono: 2),
        laser:   (def: \seZap)
    );
    // dB, loudest hit vs the kick. Sustained effects sit lower than their peaks suggest; these put their RMS over
    // the bars they play near the kick's.
    mixTargets = (kick: 0, snare: -1, clap: -2, hat: -12,
        impact: -2, down: -7, lodown: -5, scidown: -6, rise: -5, bass: -1, synbass: -8, laser: -6);
    claps = (long: (freq: 1400, rq: 0.55, spread: 0.008, g4: 0.7, burst: 0.006, tail: 0.22, tailFreq: 1900));
    // fxZap settings (assets/zap.scd), written out so the approved loops do not move with the SynthDef defaults.
    // `slow` is the listener's favourite. `verb` is the zap reverb, also on the laser.
    zaps = (verb: (verb: 0.4, room: 0.8, damp: 0.5));
    zaps[\clap] = (hiFreq: 3000, loFreq: 110, sweep: 0.15, curve: 3, ring: 0.12, mix: 0.7).putAll(zaps[\verb]);
    zaps[\slow] = (hiFreq: 3000, loFreq: 80, sweep: 0.35, curve: 1.5, ring: 0.3, mix: 0.7).putAll(zaps[\verb]);

    // One char per sixteenth: X accent, x normal, o ghost, s a note sliding from the previous one, . rest, 2-6 a
    // roll. 32-char strings are 2-bar patterns; bN replaces a voice for bar N. `notes` gives a mono voice's
    // successive notes in semitones (cycling). `zap` puts fxZap on a voice, and every hit of that voice restarts
    // the dive. The random seed is derived from `name`, as when these were approved.
    loops = (
        drop: (name: "trap-drop", tail: 5, mix: (snare: -9),
            kit: (kick: (freq: 52, tone: 0.6), bass: (freq: 43.65), clap: claps[\long],
                snare: (freq: 230, tone: 0.8), hat: (tone: 0.8, decay: 0.07),
                lodown: (beats: 8), rise: (beats: 8, tailBeats: 4)),
            notes: (bass: [0, 0, 3, 0, 5, -2, 0]),
            pat: (kick: "x.....x...x.....x..x......x.....", bass: "x.....x...x.....x..x......x.s...",
                clap: "........x.......", snare: "........x.......",
                hat: "x.x.x.x.x.x.x2x.x.x.x.x.x.x.3333"),
            b1: (impact: "x...............", lodown: "x..............."),
            b4: (hat: "x.x.x.x.4.x.x.x."),
            b7: (rise: "x..............."),
            b8: (clap: "........x.....oX", hat: "x.x.x.x.x.x.2346")),
        sweep: (name: "trap-sweep", tail: 5, mix: (snare: -9),
            kit: (kick: (freq: 52, tone: 0.6), bass: (freq: 43.65), synbass: (freq: 174.61, sub: 0), clap: claps[\long],
                snare: (freq: 230, tone: 0.8), hat: (tone: 0.8, decay: 0.07), down: (beats: 32)),
            notes: (bass: [0, 0, 3, 0, 5, -2, 0], synbass: [0, 0, 3, 0, 5, 3, 0, -2, -2, 0]),
            pat: (kick: "x.....x...x.....x..x......x.....", bass: "x.....x...x.....x..x......x.s...",
                synbass: "x..x..x...x.x...x..x..x...x.s...",
                clap: "........x.......", snare: "........x.......",
                hat: "x.x.x.x.x.x.x2x.x.x.x.x.x.x.3333"),
            b1: (impact: "x...............", down: "x..............."),
            b4: (hat: "x.x.x.x.4.x.x.x."),
            b8: (clap: "........x.....oX", hat: "x.x.x.x.x.x.2346")),
        scifi: (name: "trap-scifi", tail: 5, mix: (snare: -9),
            kit: (kick: (freq: 52, tone: 0.6), bass: (freq: 43.65), clap: claps[\long],
                snare: (freq: 230, tone: 0.8), hat: (tone: 0.8, decay: 0.07),
                impact: (echo: 0.7), scidown: (beats: 16), rise: (beats: 16)),
            notes: (bass: [0, 0, 3, 0, 5, -2, 0]),
            pat: (kick: "x.....x...x.....x..x......x.....", bass: "x.....x...x.....x..x......x.s...",
                clap: "........x.......", snare: "........x.......",
                hat: "x.x.x.x.x.x.x2x.x.x.x.x.x.x.3333"),
            b1: (impact: "x...............", scidown: "x..............."),
            b4: (hat: "x.x.x.x.4.x.x.x."),
            b5: (rise: "x..............."),
            b8: (clap: "........x.....oX", hat: "x.x.x.x.x.x.2346")),
        bass808: (name: "bass808", kit: (bass: (freq: 43.65)),
            notes: (bass: [0, 0, 3, 0, 5, -2, 0]), pat: (bass: "x.....x...x.....x..x......x.s...")),
        synbass: (name: "synbass", kit: (synbass: (freq: 174.61)),
            notes: (synbass: [0, 0, 3, 0, 5, 3, 0, -2, -2, 0]), pat: (synbass: "x..x..x...x.x...x..x..x...x.s...")),
        zap: (name: "trap-zap-verb", tail: 5, mix: (snare: -9),
            kit: (kick: (freq: 52, tone: 0.6), bass: (freq: 43.65), clap: claps[\long],
                snare: (freq: 230, tone: 0.8), hat: (tone: 0.8, decay: 0.07),
                lodown: (beats: 8), rise: (beats: 8, tailBeats: 4), laser: zaps[\verb]),
            zap: (clap: zaps[\clap]),
            notes: (bass: [0, 0, 3, 0, 5, -2, 0]),
            pat: (kick: "x.....x...x.....x..x......x.....", bass: "x.....x...x.....x..x......x.s...",
                clap: "........x.......", snare: "........x.......",
                hat: "x.x.x.x.x.x.x2x.x.x.x.x.x.x.3333"),
            b1: (impact: "x...............", lodown: "x..............."),
            b4: (hat: "x.x.x.x.4.x.x.x.", laser: "..............x."),
            b7: (rise: "x..............."),
            b8: (clap: "........x.....oX", hat: "x.x.x.x.x.x.2346", laser: "............x...")),
        snarezap: (name: "trap-snarezap-slow", tail: 5, mix: (snare: -3),
            kit: (kick: (freq: 52, tone: 0.6), bass: (freq: 43.65), clap: claps[\long],
                snare: (freq: 230, tone: 0.8), hat: (tone: 0.8, decay: 0.07),
                lodown: (beats: 8), rise: (beats: 8, tailBeats: 4)),
            zap: (snare: zaps[\slow]),
            notes: (bass: [0, 0, 3, 0, 5, -2, 0]),
            pat: (kick: "x.....x...x.....x..x......x.....", bass: "x.....x...x.....x..x......x.s...",
                clap: "........x.......", snare: "........x.......",
                hat: "x.x.x.x.x.x.x2x.x.x.x.x.x.x.3333"),
            b1: (impact: "x...............", lodown: "x..............."),
            b4: (hat: "x.x.x.x.4.x.x.x."),
            b7: (rise: "x..............."),
            b8: (clap: "........x.....oX", snare: "........x.....oX", hat: "x.x.x.x.x.x.2346"))
    );
    g = loops[variant.asSymbol];
    if(g.isNil) {
        Error("Unknown loop %; choose drop, sweep, scifi, bass808, synbass, zap or snarezap".format(variant)).throw
    };

    hitsFor = { |c|   // -> [[fraction of the step, velocity, slide], ...]
        case
        { c == $X } { [[0, 1.0]] }
        { c == $x } { [[0, 0.78]] }
        { c == $o } { [[0, 0.42]] }
        { c == $s } { [[0, 0.78, 1]] }
        { c == $. } { [] }
        { c.isDecDigit and: { c.digit >= 2 } } {
            Array.fill(c.digit, { |k| [k / c.digit, 0.5 + (0.35 * k / (c.digit - 1))] })
        }
        { Error("Unknown pattern character: " ++ c).throw }
    };
    charAt = { |voice, bar, step|
        var over = g[("b" ++ (bar + 1)).asSymbol], s = g[\pat][voice];
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

    // Voices the loop plays anywhere, in alphabetical order: voice k renders to channels 2k, 2k+1, and this order
    // also fixes the order of random draws.
    voices = Set.new;
    ([g[\pat]] ++ Array.fill(bars, { |b| g[("b" ++ (b + 1)).asSymbol] })).do { |p|
        p !? { p.keysValuesDo { |voice, str|
            if(kit[voice].isNil) { Error("Unknown voice: " ++ voice).throw };
            if((str.size == 0) or: { str.size % 16 != 0 }) { Error("Pattern length not a multiple of 16: " ++ voice).throw };
            voices.add(voice)
        } }
    };
    voices = voices.asArray.sort { |a, b| a.asString < b.asString };

    beat = 60 / bpm;
    stepDur = beat / 4;
    loopFrames = (bars * 4 * 60 / bpm * sr).round.asInteger;
    loopDur = loopFrames / sr;
    tail = (g[\tail] ? 0).max(3);                            // render past the loop until every tail is silent
    thisThread.randSeed = seed + g[\name].hash;
    events = List.new;
    bars.do { |bar| 16.do { |step|
        var t = ((bar * 16) + step) * stepDur;                 // straight sixteenths: trap is not swung
        voices.do { |voice| hitsFor.(charAt.(voice, bar, step)).do { |h|
            // [time, voice, velocity, slide, semitones, length, slide from]; the last three for mono voices
            events.add([t + (h[0] * stepDur), voice, (h[1] * (1 + 0.08.rand2)).clip(0.05, 1), h[2] ? 0, 0, nil, 0])
        } }
    } };
    events = events.asArray.sort { |a, b| a[0] <= b[0] };
    // A mono voice's note n plays notes[n] semitones and lasts until its next note, at most `mono` beats; an `s`
    // note starts at the previous note's pitch and glides. Looped, the last note runs into the first.
    voices.do { |voice|
        var mine, notes, maxLen = kit[voice][\mono];
        if(maxLen.notNil) {
            mine = events.select { |e| e[1] == voice };
            notes = (g[\notes] ? ())[voice] ? [0];
            mine.do { |e, n|
                var next = if(n + 1 < mine.size) { mine[n + 1][0] } { loopDur + mine[0][0] };
                e.put(4, notes.wrapAt(n));
                e.put(5, (next - e[0]).min(maxLen * beat));
                if(e[3] == 1) { e.put(6, notes.wrapAt(if(n == 0) { mine.size - 1 } { n - 1 }) - notes.wrapAt(n)) };
            }
        }
    };

    score = Score.new;
    defs.do { |d| score.add([0, [\d_recv, d.asBytes]]) };
    // A zapped voice k plays into private bus 64 + 2k; its fxZap reads that bus in a group after the voices and writes
    // the voice's stem.
    if(g[\zap].notNil) { score.add([0, [\g_new, 2000, 3, 1]]) };
    (g[\zap] ? ()).keysValuesDo { |v, zp|
        var k = voices.indexOf(v);
        if(k.isNil) { Error("zap on a voice the loop does not play: " ++ v).throw };
        score.add([0, [\s_new, \fxZap, 4000 + k, 0, 2000, \in, 64 + (2 * k), \out, 2 * k] ++ zp.asKeyValuePairs]);
    };
    events.do { |e, k|
        var p = kit[e[1]].copy.putAll((g[\kit] ? ())[e[1]] ? ()), id = -1, msg;
        // Closed hats are one instrument: each hat hit chokes the hat still ringing.
        if(e[1] == \hat) {
            if(lastHat.notNil and: { e[0] < lastHat[1] }) { score.add([e[0], [\n_set, lastHat[0], \gate, 0]]) };
            id = 1000 + k;
            lastHat = [id, e[0] + p[\decay]];
        };
        if(p[\mono].notNil) { p[\freq] = (p[\freq] ? 440) * e[4].midiratio; p[\len] = e[5]; p[\from] = e[6] };
        msg = [\s_new, p[\def], id, 0, 1,
            \out, (voices.indexOf(e[1]) * 2) + (if((g[\zap] ? ())[e[1]].notNil) { 64 } { 0 }), \velocity, e[2],
            \seed, p[\seed] ? 100000.rand, \beat, beat];
        // Each hit of a zapped voice restarts its dive.
        (g[\zap] ? ())[e[1]] !? { score.add([e[0], [\n_set, 4000 + voices.indexOf(e[1]), \t_trig, 1]]) };
        p.keysValuesDo { |key, v| if([\def, \seed, \mono].includes(key).not) { msg = msg ++ [key, v] } };
        score.add([e[0], msg]);
    };
    // Looped, the first hat hit follows the last one: choke across the seam too.
    events.detect { |e| e[1] == \hat } !? { |e|
        if(lastHat.notNil and: { (loopDur + e[0]) < lastHat[1] }) {
            score.add([loopDur + e[0], [\n_set, lastHat[0], \gate, 0]])
        }
    };
    score.add([loopDur + tail, [\c_set, 0, 0]]);
    score.sort;

    // An explicit score file: the default name comes from UniqueID, which starts at 1000 in every sclang, so
    // renders running at the same time would overwrite each other's scores.
    score.recordNRT(oscFilePath: stemPath ++ ".osc", outputFilePath: stemPath, sampleRate: sr, headerFormat: "WAV",
        sampleFormat: "float",
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
                gains = voices.collect { |v, k| ((g[\mix] ? ())[v] ? mixTargets[v]).dbamp / peaks[k] };
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
                File.delete(stemPath); File.delete(stemPath ++ ".osc");
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
                "RENDER_OK % % frames".format(g[\name], loopFrames).postln;
                0.exit
            } { |err| err.reportError; 1.exit }
        });
} { |err| err.reportError; 1.exit };
)
