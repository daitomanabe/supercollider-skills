// Usage: sclang -D -u CHECKED_FREE_UDP_PORT se-nrt.scd /absolute/output.wav SEED PRESET [bpm]
// Renders one listening-approved sound effect from assets/se_bass.scd: downlifters (trap long sweeps with three
// quarter-note modulation shapes, a 2-bar version, lo-fi sub dives, a sci-fi bend), impacts, sweeps up, and
// modulated swells. Lengths are in beats, so `bpm` (default 140, the approved tempo) stretches them; the impact's
// ring-out is in seconds. The render is trimmed 20 ms after the sound falls 70 dB below its peak, faded over those
// 20 ms, and peak-normalized to -1 dBFS as 48 kHz int24 WAV. With seed 1 at 140 BPM every preset reproduces the
// approved file. Run with an unknown PRESET to list the presets.
(
var sr = 48000, fade = sr div: 50 * 2, outPath, tmpPath, seed, name, bpm, beat, presets, preset, defs, score, slot;
SystemClock.sched(120, { "[watchdog] forced exit".postln; 1.exit });
try {
    // [name, SynthDef arguments]; names are voice_label as in the approved files.
    presets = [
        ["down_trap-pump", (def: \seDown, beats: 32)],
        ["down_trap-gate", (def: \seDown, beats: 32, freq: 220, modStyle: 1)],
        ["down_trap-trem", (def: \seDown, beats: 32, freq: 294, modStyle: 2, modDiv: 2, modDepth: 7)],
        ["down_2bar-pump", (def: \seDown, beats: 8, fadeAt: 0.2)],
        ["lodown_lofi-dive", (def: \seLoDown)],
        ["lodown_lofi-slowdown", (def: \seLoDown, drop: -14, pulseHi: 16, pulseLo: 2.5, chopDb: -12)],
        ["scidown_scifi", (def: \seSciDown)],
        ["impact_boom", (def: \seImpact)],
        ["impact_ring", (def: \seImpact, ring: 0.35, noise: 0.35)],
        ["impact_echo", (def: \seImpact, echo: 0.7)],
        ["rise_saw-gate", (def: \seRise, beats: 16)],
        ["rise_noise-trem", (def: \seRise, beats: 16, noise: 1.5, detune: 0.3, cutHi: 4000,
            modStyle: 2, modDiv: 2, modDepth: 6, modDecay: 0)],
        ["rise_2bar", (def: \seRise, beats: 8, tailBeats: 4)],
        ["mod_gate", (def: \seMod)],
        ["mod_wobble", (def: \seMod, modStyle: 2, modDiv: 2, modDepth: 8, wobble: 0.6, wobbleDiv: 1.5)],
        ["mod_snh", (def: \seMod, modStyle: 0, snh: 1.2, n2: 5, n3: 10, n4: 14)]
    ];
    if(thisProcess.argv.size < 3) { Error("Usage: se-nrt.scd /absolute/output.wav SEED PRESET [bpm]").throw };
    outPath = thisProcess.argv[0];
    tmpPath = outPath ++ ".render.wav";
    if(PathName(outPath).isAbsolutePath.not) { Error("Output path must be absolute.").throw };
    if(["$", "`", "\"", "\n", "\r", "\\"].any { |c| outPath.find(c).notNil }) {
        Error("Output path contains shell-sensitive characters unsupported by Score.recordNRT.").throw
    };
    if(File.exists(outPath) or: { File.exists(tmpPath) }) { Error("Output exists; choose a new filename.").throw };
    seed = thisProcess.argv[1].asInteger;
    name = thisProcess.argv[2];
    bpm = (thisProcess.argv.at(3) ? "140").asFloat;
    if(bpm <= 0) { Error("bpm must be positive").throw };
    preset = presets.detect { |p| p[0] == name };
    if(preset.isNil) { Error("Unknown preset %; choose one of: %".format(name, presets.collect(_.first).join(", "))).throw };
    preset = preset[1];
    beat = 60 / bpm;
    slot = (15 * 140 / bpm).max(15).ceil;                  // the longest preset lasts 13.7 s at 140 BPM
    if("SC_SYNTH".getenv.notNil) { Score.program = "SC_SYNTH".getenv.shellQuote };
    TempoClock.default.tempo = 1;
    defs = thisProcess.interpreter.executeFile(
        (thisProcess.nowExecutingPath.dirname +/+ "../assets/se_bass.scd").standardizePath
    );

    score = Score.new;
    defs.do { |d| score.add([0, [\d_recv, d.asBytes]]) };
    score.add([0, [\s_new, preset[\def], -1, 0, 1, \velocity, 0.78, \beat, beat, \seed, seed]
        ++ preset.reject { |v, k| k == \def }.asKeyValuePairs]);
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
                "RENDER_OK % % frames at % BPM".format(name, x.size div: 2, bpm).postln;
                0.exit
            } { |err| err.reportError; 1.exit }
        });
} { |err| err.reportError; 1.exit };
)
