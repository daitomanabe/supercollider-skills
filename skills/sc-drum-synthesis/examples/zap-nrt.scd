// Usage: sclang -D -u CHECKED_FREE_UDP_PORT zap-nrt.scd /absolute/output.wav SEED PRESET
// Renders one listening-approved delay-time zap from assets/zap.scd as a one-shot: a voice from assets/synthdefs.scd
// through fxZap, or the standalone seZap laser, each with the zap reverb. clap_zap-slow-verb is the listener's
// favourite (fxZap's defaults). The render is trimmed 20 ms after the sound falls 70 dB below its peak, faded over
// those 20 ms, and peak-normalized to -1 dBFS as 48 kHz int24 WAV. With seed 1 every preset reproduces the approved
// file. Run with an unknown PRESET to list the presets.
(
var sr = 48000, slot = 8, fade = sr div: 50 * 2, outPath, tmpPath, seed, name, presets, preset, clap, snare, slow, verb;
var defs, score, msg;
SystemClock.sched(120, { "[watchdog] forced exit".postln; 1.exit });
try {
    clap = (def: \drumClap, freq: 1500, rq: 0.45, spread: 0.005, burst: 0.005, tail: 0.09, tailFreq: 2000);  // tight
    snare = (def: \drumSnare, freq: 210, tone: 0.6);
    // The favourite, written out so the approved sounds do not move with the SynthDef defaults.
    slow = (hiFreq: 3000, loFreq: 80, sweep: 0.35, curve: 1.5, ring: 0.3, mix: 0.7);
    verb = (verb: 0.4, room: 0.8, damp: 0.5);
    // [name, voice and its arguments, fxZap settings (nil: the voice is seZap itself)].
    presets = [
        ["clap_zap-slow-verb", clap, slow.copy.putAll(verb)],
        ["clap_zap-verb", clap, (hiFreq: 3000, loFreq: 110, sweep: 0.15, curve: 3, ring: 0.12, mix: 0.7).putAll(verb)],
        // The dive spans the snare and a short tail: sweep about the snare's length, short ring, mostly wet.
        ["snare_dive-verb", snare, (hiFreq: 4000, loFreq: 120, sweep: 0.15, curve: 2, ring: 0.06, mix: 0.85).putAll(verb)],
        ["snare_slow-verb", snare, slow.copy.putAll(verb)],
        ["hat_pew-verb", (def: \drumHatClosed, decay: 0.09, tone: 0.6),
            (hiFreq: 6000, loFreq: 500, sweep: 0.12, curve: 2, ring: 0.15, mix: 0.8).putAll(verb)],
        ["laser-verb", (def: \seZap).putAll(verb), nil],
        ["laser-short-verb", (def: \seZap, hiFreq: 4000, loFreq: 150, sweep: 0.08, ring: 0.1).putAll(verb), nil],
        // Negative ring feeds back inverted: odd harmonics an octave lower, a hollow tone.
        ["laser-hollow-verb", (def: \seZap, loFreq: 80, ring: -0.3).putAll(verb), nil]
    ];
    if(thisProcess.argv.size < 3) { Error("Usage: zap-nrt.scd /absolute/output.wav SEED PRESET").throw };
    outPath = thisProcess.argv[0];
    tmpPath = outPath ++ ".render.wav";
    if(PathName(outPath).isAbsolutePath.not) { Error("Output path must be absolute.").throw };
    if(["$", "`", "\"", "\n", "\r", "\\"].any { |c| outPath.find(c).notNil }) {
        Error("Output path contains shell-sensitive characters unsupported by Score.recordNRT.").throw
    };
    if(File.exists(outPath) or: { File.exists(tmpPath) }) { Error("Output exists; choose a new filename.").throw };
    seed = thisProcess.argv[1].asInteger;
    name = thisProcess.argv[2];
    preset = presets.detect { |p| p[0] == name };
    if(preset.isNil) { Error("Unknown preset %; choose one of: %".format(name, presets.collect(_.first).join(", "))).throw };
    if("SC_SYNTH".getenv.notNil) { Score.program = "SC_SYNTH".getenv.shellQuote };
    TempoClock.default.tempo = 1;
    defs = ["../assets/synthdefs.scd", "../assets/zap.scd"].collect { |f|
        thisProcess.interpreter.executeFile((thisProcess.nowExecutingPath.dirname +/+ f).standardizePath)
    }.flatten;

    score = Score.new;
    defs.do { |d| score.add([0, [\d_recv, d.asBytes]]) };
    msg = [\s_new, preset[1][\def], -1, 0, 1, \velocity, 0.78, \beat, 60 / 140, \seed, seed]
        ++ preset[1].reject { |v, k| k == \def }.asKeyValuePairs;
    preset[2] !? { |zap|
        // The voice plays into a private bus at amp 0.5 (the zap's drive makes its level matter); fxZap reads that
        // bus in a group after the voices and writes the output.
        score.add([0, [\g_new, 2000, 3, 1]]);
        score.add([0, [\s_new, \fxZap, 2001, 0, 2000, \in, 64, \out, 0] ++ zap.asKeyValuePairs]);
        msg = msg ++ [\out, 64, \amp, 0.5];
    };
    score.add([0, msg]);
    score.add([slot, [\c_set, 0, 0]]);
    score.sort;
    // An explicit score file: the default name comes from UniqueID, which starts at 1000 in every sclang, so
    // renders running at the same time would overwrite each other's scores.
    score.recordNRT(oscFilePath: tmpPath ++ ".osc", outputFilePath: tmpPath, sampleRate: sr, headerFormat: "WAV",
        sampleFormat: "float", options: ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0).sampleRate_(sr),
        duration: slot,
        action: { |status|
            try {
                var sf = SoundFile.new, x, n, peak = 0, floor, gain, out;
                if(status != 0) { Error("scsynth NRT exited with " ++ status).throw };
                if(sf.openRead(tmpPath).not) { Error("Cannot read NRT output " ++ tmpPath).throw };
                x = FloatArray.newClear(sf.numFrames * sf.numChannels);
                sf.readData(x);
                sf.close;
                File.delete(tmpPath); File.delete(tmpPath ++ ".osc");
                x.do { |v| peak = peak.max(v.abs) };
                if(peak < 1e-4) { Error("% is silent".format(name)).throw };
                // Reverb tails approach zero only slowly, so trim at -70 dB rather than at the last non-zero sample.
                floor = peak * -70.dbamp;
                n = x.size;
                while { (n > 0) and: { x[n - 1].abs < floor } } { n = n - 1 };
                if(n > (x.size - (sr div: 10 * 2))) { Error("% still sounding at the end of the render".format(name)).throw };
                n = (n + fade).min(x.size);
                x = x.copyRange(0, n - (n % 2) - 1);
                gain = -1.dbamp / peak;
                x.size.do { |i| x[i] = x[i] * gain * ((x.size - i) / fade).min(1) };
                out = SoundFile.new.headerFormat_("WAV").sampleFormat_("int24").numChannels_(2).sampleRate_(sr);
                if(out.openWrite(outPath).not) { Error("Cannot write " ++ outPath).throw };
                if(out.writeData(x) == false) { Error("writeData failed for " ++ outPath).throw };
                out.close;
                "RENDER_OK % % frames".format(name, x.size div: 2).postln;
                0.exit
            } { |err| err.reportError; 1.exit }
        });
} { |err| err.reportError; 1.exit };
)
