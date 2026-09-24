// Usage: sclang -D -u CHECKED_FREE_UDP_PORT drums-nrt.scd /absolute/output.wav [seed]
// 18 seconds: six isolated voices at 0.25 + (index * 1.25)s, then 4 bars at 120 BPM.
(
var outPath, seed, defs, score, voices, levels, addHit, options;
try {
    if(thisProcess.argv.isEmpty) { Error("Supply an absolute WAV output path.").throw };
    outPath = thisProcess.argv[0];
    if(PathName(outPath).isAbsolutePath.not) { Error("Output path must be absolute.").throw };
    if(["$", "`", "\"", "\n", "\r", "\\"].any { |c| outPath.find(c).notNil }) {
        Error("Output path contains shell-sensitive characters unsupported by Score.recordNRT.").throw
    };
    if(File.exists(outPath)) { Error("Output exists; choose a new filename.").throw };
    seed = (thisProcess.argv.at(1) ? "42").asInteger;
    if("SC_SYNTH".getenv.notNil) { Score.program = "SC_SYNTH".getenv.shellQuote };
    TempoClock.default.tempo = 1;
    thisThread.randSeed = seed;
    defs = thisProcess.nowExecutingPath.dirname +/+ "../assets/synthdefs.scd";
    defs = thisProcess.interpreter.executeFile(defs.standardizePath);
    score = Score.new;
    defs.do { |def| score.add([0, [\d_recv, def.asBytes]]) };
    voices = [\drumKick, \drumSnare, \drumClap, \drumHatClosed, \drumHatOpen, \drumCrash];
    // Peaks relative to the kick: snare -1, clap -2, closed hat -12, open hat -11, crash -9 dB (as in garage-nrt).
    levels = [0.35, 0.22, 0.86, 0.47, 0.36, 0.073];
    addHit = { |time, index, velocity=0.8, pan=0|
        score.add([time, [\s_new, voices[index], -1, 0, 1,
            \amp, levels[index], \velocity, velocity, \pan, pan,
            \seed, seed + (time * 48000).asInteger + index]])
    };
    voices.size.do { |i| addHit.(0.25 + (i * 1.25), i, 0.8) };
    64.do { |step|
        var pos = step % 16, time = 8 + (step * 0.125);
        if(#[0, 8].includes(pos)) { addHit.(time, 0, 0.9) };
        if(#[4, 12].includes(pos)) { addHit.(time, 1, 0.8) };
        if(pos % 2 == 0) { addHit.(time, 3, rrand(0.55, 0.85), 0.15) };
        if(pos == 14) { addHit.(time, 4, 0.7, 0.15) };
        if((step >= 56) and: { pos % 2 == 1 }) { addHit.(time, 1, 0.25 + ((pos - 8) * 0.035), -0.1) };
    };
    score.add([16, [\s_new, \drumCrash, -1, 0, 1, \amp, 0.056, \velocity, 0.85, \seed, seed + 16000]]);
    score.add([18, [\c_set, 0, 0]]);
    score.sort;
    options = ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0).sampleRate_(48000);
    // An explicit score file: the default name comes from UniqueID, which starts at 1000 in every sclang, so
    // renders running at the same time would overwrite each other's scores.
    score.recordNRT(oscFilePath: outPath ++ ".osc", outputFilePath: outPath, sampleRate: 48000, headerFormat: "WAV",
        sampleFormat: "int24", options: options, duration: 18,
        action: { |status|
            File.delete(outPath ++ ".osc");
            if((status == 0) and: { File.exists(outPath) }) { "RENDER_OK drums 18s".postln; 0.exit }
            { "RENDER_FAILED".postln; 1.exit }
        });
} { |err| err.reportError; 1.exit };
)
