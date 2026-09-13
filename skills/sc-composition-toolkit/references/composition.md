# Composition and routing

## SynthDefs and patterns

Declare local variables at the beginning of each function or block. In SuperCollider, binary operators share precedence and evaluate left to right: write parentheses around mixed calculations. Use distinct names for event duration (`dur`) and grain length (`grainDur`).

Build SynthDefs independently of server boot. Use `EnvGen` with an appropriate `doneAction` for finite notes, and a gate-controlled release for sustained voices. `{ oscillator } ! 2` creates independent UGen graphs; `oscillator ! 2` duplicates the same signal. Keep amplitude and filter envelopes distinct when their musical roles differ.

Define the piece's tempo, section durations, voices, and release tail before rendering. Patterns (`Pbind`, `Pseq`, `Ppar`, `Pfindur`) express musical structure; NRT score timestamps ultimately need a consistent time base. If adding nodes to a `Pattern.asScore` result, inspect allocated IDs or choose a disjoint explicit range. Do not treat a guessed node range as a universal guarantee. Seed both language-side random choices and server-side random UGens when reproducibility matters.

## Effects

Run sources before their dependent effects using explicit node/group order. Allocate non-overlapping internal buses after hardware output and input buses. Define every insert's input/output width and use `ReplaceOut` only when replacing that bus is intended. Parallel sends use `Out`; two inserts using `Out` can accidentally sum dry audio repeatedly.

Feedback loops need bounded gain, suitable filtering, and explicit initialization. A limiter can constrain delivered peaks but does not establish that an internal loop remains finite or stable over a long render. Test the parameter range and duration affected by the change. `Compander` thresholds use linear amplitude, and `Limiter` lookahead adds latency; account for that in synchronization and tails.

## Samples and granular

Resolve sample paths from user-supplied project configuration. Confirm channel count, sample rate, duration, and file access before building a score. In NRT include buffer allocation/loading commands before dependent synths and free buffers after use. Use a command's completion message when strict asynchronous ordering is necessary. A realtime `Buffer` object by itself does not populate an NRT server.

Match the buffer channel count to the playback UGen. `GrainBuf` expects a mono source buffer; downmix or select a channel explicitly when required. Record the choice instead of silently discarding channels.

## Multichannel

Record the logical channel count/order, coordinate convention, speaker directions, panner/decoder, and stereo preview method. A stereo fold-down is an audition derivative. Channel count and logical panning tests do not verify interface routing, speaker placement, ambisonic normalization/order, or acoustic calibration. Choose dependencies for the intended algorithm and verify them in the target runtime; avoid generalizing a historical machine-specific plugin failure into a universal prohibition.

## Sources

- [SynthDef](https://doc.sccode.org/Classes/SynthDef.html)
- [Pattern guide](https://doc.sccode.org/Tutorials/A-Practical-Guide/PG_01_Introduction.html)
- [Order of execution](https://doc.sccode.org/Guides/Order-of-execution.html)
- [GrainBuf](https://doc.sccode.org/Classes/GrainBuf.html)
