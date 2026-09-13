// Stock SuperCollider, no audio device. Usage: run_sclang.py -- this.scd OUTPUT.wav
(
var output, oscPath, synth, options, score;
try {
    if(thisProcess.argv.size != 1) { Error("Expected one output WAV path").throw };
    output = thisProcess.argv[0].standardizePath;
    oscPath = ("SC_SKILL_TMP".getenv ? Platform.defaultTempDir) +/+ "minimal-score.osc";
    [output, oscPath].do { |path|
        if(path.any { |char| [10, 13, 34, 36, 92, 96].includes(char.ascii) }) {
            Error("Use a path without newline, quote, dollar, backslash, or backtick").throw
        };
    };
    if(File.exists(output)) { Error("Refusing to overwrite output").throw };
    if(File.exists(output.dirname).not) { Error("Create the output directory first").throw };
    if("SC_SYNTH".getenv.notNil) { Score.program = "SC_SYNTH".getenv.shellQuote };
    TempoClock.default.tempo = 1;
    options = ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0).loadDefs_(false);
    synth = SynthDef(\skillTone, { |out = 0, freq = 440, amp = 0.15, pan = 0|
        var env = EnvGen.kr(Env.perc(0.01, 0.6), doneAction: Done.freeSelf);
        Out.ar(out, Pan2.ar(SinOsc.ar(freq) * env * amp, pan));
    });
    score = Score([
        [0.0, [\d_recv, synth.asBytes]],
        [0.1, [\s_new, \skillTone, 1000, 0, 1, \freq, 261.626, \pan, -0.6]],
        [0.6, [\s_new, \skillTone, 1001, 0, 1, \freq, 329.628, \pan, -0.2]],
        [1.1, [\s_new, \skillTone, 1002, 0, 1, \freq, 391.995, \pan, 0.2]],
        [1.6, [\s_new, \skillTone, 1003, 0, 1, \freq, 523.251, \pan, 0.6]],
        [3.0, [\c_set, 0, 0]]
    ]);
    score.recordNRT(oscFilePath: oscPath, outputFilePath: output,
        sampleRate: 48000, headerFormat: "WAV", sampleFormat: "int24", options: options,
        action: { |exitCode|
            if(exitCode == 0) { "NRT_COMPLETE".postln; 0.exit } { exitCode.exit };
        });
} { |error| error.reportError; 1.exit };
)
