(
// No audio server boots until the user presses Play. NRT uses embedded SynthDefs.
var sourceDir = thisProcess.nowExecutingPath.dirname;
var nodeAddr = NetAddr("127.0.0.1", "SCW_FEEDBACK_PORT".getenv.asInteger);
var audioPort = "SCW_AUDIO_PORT".getenv.asInteger;
var nrtOnly = "SCW_NRT_ONLY".getenv == "1";
var previewRoutine, previewGroup, fxGroup, fxBus;
var previewGeneration = 0;
var previewPlaying = false;
var audioState = if(nrtOnly, {"disabled"}, {"stopped"});

TempoClock.default.tempo = 1;
s = Server(\scWebUI, NetAddr("127.0.0.1", audioPort));
Server.default = s;
s.options.numInputBusChannels = 0;
s.options.numOutputBusChannels = 2;
s.options.sampleRate = 44100;
s.options.bindAddress = "127.0.0.1";
~batchRunning = false;
~batchStop = false;
~pp = IdentityDictionary.new;
~log = { |msg| msg.postln; nodeAddr.sendMsg('/log', msg.asString) };
~sendStatus = { nodeAddr.sendMsg('/sc/status', "ready", audioState, previewPlaying.asInteger, ~batchRunning.asInteger) };

~voiceDef = SynthDef(\scwToneVoice, { |out=0, freq=220, amp=0.15, pan=0, engineDrive=1.2|
    var env = EnvGen.ar(Env.perc(0.001, 0.18), doneAction:2);
    var sig = SinOsc.ar(freq) + (VarSaw.ar(freq * 1.01, 0, 0.35) * 0.4);
    sig = (sig * engineDrive.clip(0.5, 4)).tanh * env * amp;
    Out.ar(out, Pan2.ar(sig, pan));
});
~fxDef = SynthDef(\scwFxChain, { |in=0, out=0, fxMix=0.12|
    var dry = In.ar(in, 2);
    var wet = FreeVerb2.ar(dry[0], dry[1], 1, 0.6, 0.3);
    Out.ar(out, Limiter.ar(XFade2.ar(dry, wet, fxMix.clip(0,1) * 2 - 1), 0.95));
});
// The same seed + step rule is used by preview and NRT.
~noteForStep = { |step, seed|
    var midi;
    thisThread.randSeed = seed + step;
    midi = if(step % 4 == 0, {48}, {[60,64,67,72].choose});
    (freq:midi.midicps, amp:if(step % 4 == 0, {0.22}, {0.12}), pan:if(step % 2 == 0, {-0.15}, {0.15}));
};
~buildRenderEvents = { |params|
    var stepDur = 60 / params[\tempo].clip(60,200) / 2;
    var seconds = params[\seconds].clip(1,120);
    var events = List.new;
    var step = 0;
    while({ (step * stepDur) < seconds }, {
        var ev = ~noteForStep.(step, params[\seed]);
        ev[\time] = step * stepDur;
        events.add(ev);
        step = step + 1;
    });
    events;
};
~previewStop = {
    previewGeneration = previewGeneration + 1;
    previewRoutine !? { previewRoutine.stop; previewRoutine = nil };
    previewGroup !? { previewGroup.free; previewGroup = nil };
    fxGroup !? { fxGroup.free; fxGroup = nil };
    fxBus !? { fxBus.free; fxBus = nil };
    previewPlaying = false;
    nodeAddr.sendMsg('/preview/stopped');
};
~previewPlay = { |params|
    var generation;
    ~previewStop.();
    generation = previewGeneration;
    if(nrtOnly, {
        nodeAddr.sendMsg('/preview/error', "Preview is disabled by SCW_NRT_ONLY=1");
    }, {
        ~pp = params.copy;
        audioState = "booting";
        s.waitForBoot({
            Routine({
                ~voiceDef.send(s); ~fxDef.send(s); s.sync;
                audioState = "ready";
                if(generation == previewGeneration, {
                    fxBus = Bus.audio(s, 2);
                    previewGroup = Group.new(s);
                    fxGroup = Group.after(previewGroup);
                    ~previewFX = Synth(\scwFxChain, [\in,fxBus.index,\fxMix,~pp[\fxMix]], fxGroup);
                    previewPlaying = true;
                    nodeAddr.sendMsg('/preview/started');
                    previewRoutine = Routine({
                        var step = 0, elapsed = 0.0;
                        while({ elapsed < ~pp[\seconds] }, {
                            var ev = ~noteForStep.(step, ~pp[\seed]);
                            var stepDur = 60 / ~pp[\tempo].clip(60,200) / 2;
                            Synth(\scwToneVoice, [\out,fxBus.index,\freq,ev[\freq],\amp,ev[\amp],\pan,ev[\pan],\engineDrive,~pp[\engineDrive]], previewGroup);
                            step = step + 1;
                            elapsed = elapsed + stepDur;
                            stepDur.wait;
                        });
                        // Let the final note and reverb decay before freeing the groups.
                        1.wait;
                        previewRoutine = nil;
                        ~previewStop.();
                    }).play(SystemClock);
                });
            }).play(SystemClock);
        }, limit:100, onFailure:{
            audioState = "failed";
            nodeAddr.sendMsg('/preview/error', "Audio server failed to boot; inspect logs/sclang.log");
        });
    });
};
~previewSetParams = { |dict|
    dict.keysValuesDo { |key,value| ~pp[key] = value };
    if(previewPlaying, { ~previewFX.set(\fxMix,~pp[\fxMix]) });
};
~safeNRTPath = { |text| text.any { |char| [10,13,34,36,92,96].includes(char.ascii) }.not };
~renderNRT = { |params, outputPath, complete|
    var score = Score.new;
    var options = ServerOptions.new;
    var scorePath = outputPath ++ ".osc";
    if(~safeNRTPath.(outputPath).not, { Error("Unsafe NRT output path").throw });
    options.numInputBusChannels = 0;
    options.numOutputBusChannels = 2;
    options.sampleRate = 44100;
    score.add([0.0, [\d_recv, ~voiceDef.asBytes]]);
    score.add([0.0, [\d_recv, ~fxDef.asBytes]]);
    score.add([0.0, [\g_new,1001,0,0]]);
    score.add([0.0, [\g_new,1002,3,1001]]);
    score.add([0.0, [\s_new,\scwFxChain,2000,0,1002,\in,16,\out,0,\fxMix,params[\fxMix]]]);
    ~buildRenderEvents.(params).do { |ev|
        score.add([ev[\time], [\s_new,\scwToneVoice,-1,0,1001,\out,16,\freq,ev[\freq],\amp,ev[\amp],\pan,ev[\pan],\engineDrive,params[\engineDrive]]]);
    };
    score.sort;
    score.recordNRT(scorePath, outputPath, sampleRate:44100, headerFormat:"WAV", sampleFormat:"int24", options:options, duration:params[\seconds] + 1,
        action:{ |exitCode|
            var soundFile = SoundFile.new;
            var valid = false;
            if(exitCode == 0, {
                if(soundFile.openRead(outputPath), {
                    valid = (soundFile.numChannels == 2) and: { soundFile.numFrames >= (params[\seconds] * 44100) };
                    soundFile.close;
                });
            });
            File.delete(scorePath);
            complete.(valid, exitCode);
        }
    );
};
~runBatch = { |batch, outputDir, batchId|
    if(~batchRunning, { ~log.("Batch already running") }, {
        ~batchRunning = true;
        ~batchStop = false;
        Routine({
            var failures = 0, completed = 0;
            batch[\count].clip(1,200).do { |index|
                if(~batchStop.not, {
                    var tempo, seed, params, outputPath, done = false;
                    var started = Main.elapsedTime;
                    var timeout = (batch[\seconds] * 4).max(30);
                    // Reproducible tempo choices except for explicitly random seed mode.
                    thisThread.randSeed = batch[\startingSeed] + index;
                    tempo = rrand(batch[\tempoMin], batch[\tempoMax]);
                    seed = switch(batch[\seedMode].asSymbol,
                        \fixed, {batch[\startingSeed]},
                        \random, {(Main.elapsedTime * 1000000).asInteger.abs % 100000},
                        {batch[\startingSeed] + index}
                    );
                    params = (tempo:tempo, seed:seed, take:batch[\takeStart] + index, seconds:batch[\seconds], engineDrive:batch[\engineDrive], fxMix:batch[\fxMix]);
                    outputPath = outputDir +/+ ("take" ++ params[\take] ++ "_tempo" ++ tempo ++ "_seed" ++ seed ++ ".wav");
                    nodeAddr.sendMsg('/render/progress',batchId,index + 1,batch[\count],outputPath);
                    try {
                        ~renderNRT.(params, outputPath, { |valid, exitCode|
                            if(valid, {
                                completed = completed + 1;
                                nodeAddr.sendMsg('/render/jobDone',batchId,index + 1,outputPath,tempo,seed,params[\take],params[\seconds],params[\engineDrive],params[\fxMix]);
                            }, {
                                failures = failures + 1;
                                nodeAddr.sendMsg('/render/error',batchId,index + 1,"scsynth failed or WAV invalid; exit " ++ exitCode);
                            });
                            done = true;
                        });
                    } { |error|
                        failures = failures + 1;
                        nodeAddr.sendMsg('/render/error',batchId,index + 1,error.errorString);
                        done = true;
                    };
                    while({done.not}, {
                        if((Main.elapsedTime - started) > timeout, {
                            nodeAddr.sendMsg('/render/error',batchId,index + 1,"NRT timed out; supervisor will clean up this session");
                            1.exit;
                        });
                        0.05.wait;
                    });
                });
            };
            ~batchRunning = false;
            nodeAddr.sendMsg('/render/done',batchId,completed,failures,~batchStop.asInteger);
        }).play(SystemClock);
    });
};
thisProcess.interpreter.executeFile(sourceDir +/+ "generated/osc_handlers.scd");
~log.("SC engine ready. Audio starts only on Play.");
~sendStatus.();
)
