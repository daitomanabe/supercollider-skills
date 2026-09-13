// Usage: sclang -D -u CHECKED_FREE_UDP_PORT sidechain-nrt.scd /absolute/output.wav
// 4 seconds: sustained 997 Hz tone, kick-driven ducking from 1 to 2.5 seconds.
(
var outPath, defs, score, options, sourceGroup=1000, fxGroup=1001;
var kickBus=2, musicBus=4, toneDef, mixDef;
try {
    if(thisProcess.argv.isEmpty) { Error("Supply an absolute WAV output path.").throw };
    outPath = thisProcess.argv[0];
    if(PathName(outPath).isAbsolutePath.not) { Error("Output path must be absolute.").throw };
    if(["$", "`", "\"", "\n", "\r", "\\"].any { |c| outPath.find(c).notNil }) {
        Error("Output path contains shell-sensitive characters unsupported by Score.recordNRT.").throw
    };
    if(File.exists(outPath)) { Error("Output exists; choose a new filename.").throw };
    if("SC_SYNTH".getenv.notNil) { Score.program = "SC_SYNTH".getenv.shellQuote };
    TempoClock.default.tempo = 1;
    // With 2 hardware outputs and 0 inputs, private buses begin at index 2.
    options = ServerOptions.new.numOutputBusChannels_(2).numInputBusChannels_(0).numAudioBusChannels_(64);
    defs = thisProcess.interpreter.executeFile(
        (thisProcess.nowExecutingPath.dirname +/+ "../assets/synthdefs.scd").standardizePath
    );
    toneDef = SynthDef(\drumDuckingTone, { |out=4|
        var env = EnvGen.ar(Env.linen(0.02, 3.8, 0.1), doneAction: 2);
        Out.ar(out, (SinOsc.ar(997) * 0.12 * env).dup);
    });
    mixDef = SynthDef(\drumDuckingMix, { |out=0, kickIn=2, musicIn=4, amount=0.9, release=0.18|
        var kick = In.ar(kickIn, 2), music = In.ar(musicIn, 2);
        var detector = Amplitude.ar(Mix(kick) * 0.5, 0.001, 0.03) * 12;
        var envelope = LagUD.ar(detector, 0.001, release.max(0.001));
        var gain = (1 - (envelope * amount.clip(0, 1))).clip(0.02, 1);
        Out.ar(out, LeakDC.ar(kick + (music * gain)));
    });
    score = Score.new;
    (defs ++ [toneDef, mixDef]).do { |def| score.add([0, [\d_recv, def.asBytes]]) };
    score.add([0, [\g_new, sourceGroup, 0, 1], [\g_new, fxGroup, 3, sourceGroup]]);
    score.add([0, [\s_new, \drumDuckingTone, 2000, 0, sourceGroup, \out, musicBus]]);
    score.add([0, [\s_new, \drumDuckingMix, 2001, 0, fxGroup, \kickIn, kickBus, \musicIn, musicBus]]);
    [1, 1.5, 2, 2.5].do { |time, i|
        score.add([time, [\s_new, \drumKick, -1, 0, sourceGroup,
            \out, kickBus, \amp, 0.5, \velocity, 1, \seed, 100 + i]])
    };
    score.add([4, [\c_set, 0, 0]]);
    score.sort;
    score.recordNRT(outputFilePath: outPath, sampleRate: 48000, headerFormat: "WAV", sampleFormat: "int24",
        options: options, duration: 4,
        action: { |status|
            if((status == 0) and: { File.exists(outPath) }) { "RENDER_OK sidechain 4s".postln; 0.exit }
            { "RENDER_FAILED".postln; 1.exit }
        });
} { |err| err.reportError; 1.exit };
)
