// Usage: sclang -D -u CHECKED_FREE_UDP_PORT stutter-nrt.scd /absolute/output.wav SEED /absolute/input.wav BPM
//            GESTURE@BEAT[:key=value,...] ...
// Stutter gestures after iZotope Stutter Edit 2 (assets/stutter.scd) on a stereo 48 kHz WAV, typically a loop from
// garage-nrt.scd or trap-se-nrt.scd. A gesture starts BEAT quarter notes (at BPM) into the file and lasts its `dur`;
// `:key=value` pairs override its settings, e.g. accel@30:offset=-0.25 repeats from the 1/16 before beat 30 when the
// gesture starts between hits. Gestures may not overlap or run past the end. SEED fixes `jitter`.
// The output keeps the input's length and level (48 kHz int24 WAV): outside gestures its samples equal the input's, so
// a loop stays seamless when its last gesture ends on the loop point. Run with an unknown gesture to list the ten
// gestures approved in listening.
(
var sr = 48000, outPath, tmpPath, seed, inPath, bpm, beat, input, frames, defaults, presets, gestures, defs, score;
SystemClock.sched(120, { "[watchdog] forced exit".postln; 1.exit });
try {
    // Every gesture sends all settings, so nothing carries over from the previous gesture.
    defaults = (dur: 1, offset: 0, divA: 0.25, divB: 0.25, curve: 0, step: 0, width: 1, reverse: 0, pitchA: 0, pitchB: 0,
        jitter: 0, pan: 0, hpA: 20, hpB: 20, lpA: 20000, lpB: 20000, bitsA: 24, bitsB: 24, crushA: 48000,
        crushB: 48000, gainA: 0, gainB: 0, tape: 0);
    // Lengths in beats: 0.25 = 1/16 note, 1/3 = 1/8 triplet, 0.0625 = 1/64.
    presets = (
        fill16: (dur: 1, width: 0.9),                                           // the last beat as 1/16 repeats
        accel: (dur: 2, divA: 0.5, divB: 0.0625, hpB: 600),                     // 1/8 -> 1/64 sliding, thinning
        stepped: (dur: 2, divA: 0.5, divB: 0.0625, step: 1, width: 0.85),       // 1/8, 1/16, 1/32, 1/64 in turn
        triplet: (dur: 1, divA: 1/3, divB: 1/3, width: 0.6, pan: 0.6),          // 1/8 triplets, gated, L/R
        pitchup: (dur: 2, divA: 0.25, divB: 0.125, pitchB: 12, lpA: 3000, lpB: 18000),
        pitchdown: (dur: 1, pitchB: -12, lpA: 16000, lpB: 1500),
        reverse: (dur: 1, divA: 0.5, divB: 0.5, reverse: 1),
        tapestop: (dur: 2, tape: 1, lpA: 18000, lpB: 2500, gainB: -6),
        lofi: (dur: 1, divA: 0.125, divB: 0.125, width: 0.35, bitsA: 8, bitsB: 6, crushA: 8000, crushB: 4000),
        jitter: (dur: 1, divA: 0.25, divB: 0.125, jitter: 7, pan: 0.8)
    );
    if(thisProcess.argv.size < 5) {
        Error("Usage: stutter-nrt.scd /absolute/output.wav SEED /absolute/input.wav BPM GESTURE@BEAT[:key=value,...] ...")
            .throw
    };
    outPath = thisProcess.argv[0];
    tmpPath = outPath ++ ".render.wav";
    if(PathName(outPath).isAbsolutePath.not) { Error("Output path must be absolute.").throw };
    if(["$", "`", "\"", "\n", "\r", "\\"].any { |c| outPath.find(c).notNil }) {
        Error("Output path contains shell-sensitive characters unsupported by Score.recordNRT.").throw
    };
    if(File.exists(outPath) or: { File.exists(tmpPath) }) { Error("Output exists; choose a new filename.").throw };
    seed = thisProcess.argv[1].asInteger;
    inPath = thisProcess.argv[2];
    bpm = thisProcess.argv[3].asFloat;
    if(bpm <= 0) { Error("bpm must be positive").throw };
    beat = 60 / bpm;
    // The player reads two channels at the file's own rate: a mono file would be read across frame boundaries, and
    // another rate would play at the wrong speed, both without an error.
    if(PathName(inPath).isAbsolutePath.not) { Error("Input path must be absolute.").throw };
    input = SoundFile.openRead(inPath);
    if(input.isNil) { Error("Cannot read input " ++ inPath).throw };
    frames = input.numFrames;
    input.close;
    if((input.numChannels != 2) or: { input.sampleRate != sr }) {
        Error("Input must be stereo at % Hz, not % channels at % Hz".format(sr, input.numChannels, input.sampleRate)).throw
    };
    // "name@beat[:key=value,...]" -> [start in beats, settings, text], in time order
    gestures = thisProcess.argv.copyToEnd(4).collect { |spec|
        var parts = spec.split($:), head = parts[0].split($@), settings;
        if((head.size != 2) or: { presets[head[0].asSymbol].isNil }) {
            Error("Unknown gesture %; choose one of: %".format(spec,
                presets.keys.asArray.collect(_.asString).sort { |a, b| a < b }.join(", "))).throw
        };
        settings = defaults.copy.putAll(presets[head[0].asSymbol]);
        parts.drop(1).do { |list| list.split($,).do { |pair|
            var kv = pair.split($=);
            if((kv.size != 2) or: { defaults[kv[0].asSymbol].isNil }) { Error("Unknown setting % in %".format(pair, spec)).throw };
            settings[kv[0].asSymbol] = kv[1].asFloat;
        } };
        [head[1].asFloat, settings, spec]
    }.sort { |a, b| a[0] <= b[0] };
    gestures.do { |gst, i|
        if(gst[0] < 0) { Error("% starts before the file".format(gst[2])).throw };
        if(((gst[0] + gst[1][\dur]) * beat * sr) > frames) { Error("% runs past the end of the input".format(gst[2])).throw };
        if((i > 0) and: { gst[0] < (gestures[i - 1][0] + gestures[i - 1][1][\dur]) }) {
            Error("% starts before % ends".format(gst[2], gestures[i - 1][2])).throw
        };
    };
    if("SC_SYNTH".getenv.notNil) { Score.program = "SC_SYNTH".getenv.shellQuote };
    TempoClock.default.tempo = 1;
    defs = thisProcess.interpreter.executeFile(
        (thisProcess.nowExecutingPath.dirname +/+ "../assets/stutter.scd").standardizePath
    );

    score = Score.new;
    defs.do { |d| score.add([0, [\d_recv, d.asBytes]]) };
    // One bundle, so the buffer exists before the player starts.
    score.add([0, [\b_allocRead, 0, inPath], [\s_new, \stutterPlay, 1000, 0, 1, \buf, 0, \beat, beat, \seed, seed]]);
    gestures.do { |gst| score.add([gst[0] * beat, [\n_set, 1000] ++ gst[1].asKeyValuePairs ++ [\t_trig, 1]]) };
    score.add([frames / sr, [\c_set, 0, 0]]);
    score.sort;
    // An explicit score file: the default name comes from UniqueID, which starts at 1000 in every sclang, so
    // renders running at the same time would overwrite each other's scores.
    score.recordNRT(oscFilePath: tmpPath ++ ".osc", outputFilePath: tmpPath, sampleRate: sr, headerFormat: "WAV",
        sampleFormat: "float", options: ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0).sampleRate_(sr),
        duration: frames / sr,
        action: { |status|
            try {
                var sf = SoundFile.new, x, peak = 0, out;
                if(status != 0) { Error("scsynth NRT exited with " ++ status).throw };
                if(sf.openRead(tmpPath).not) { Error("Cannot read NRT output " ++ tmpPath).throw };
                if(sf.numFrames < frames) { Error("Render too short: % frames".format(sf.numFrames)).throw };
                x = FloatArray.newClear(frames * 2);
                sf.readData(x);
                sf.close;
                File.delete(tmpPath); File.delete(tmpPath ++ ".osc");
                x.do { |v| peak = peak.max(v.abs) };
                if(peak < 1e-4) { Error("Silent render").throw };
                if(peak > 0.999) { Error("Clipping (peak %); lower gainA/gainB or the input".format(peak)).throw };
                out = SoundFile.new.headerFormat_("WAV").sampleFormat_("int24").numChannels_(2).sampleRate_(sr);
                if(out.openWrite(outPath).not) { Error("Cannot write " ++ outPath).throw };
                if(out.writeData(x) == false) { Error("writeData failed for " ++ outPath).throw };
                out.close;
                "RENDER_OK % frames, gestures %".format(frames, gestures.collect(_.last).join(" ")).postln;
                0.exit
            } { |err| err.reportError; 1.exit }
        });
} { |err| err.reportError; 1.exit };
)
