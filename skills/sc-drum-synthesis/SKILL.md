---
name: sc-drum-synthesis
description: Design SuperCollider drum voices, velocity response, beat patterns, percussion mixes, tempo-synced sound effects, bass, and effects played on hits and loops. Use for synthesized kicks, snares, hats, claps, rims, cymbals, downlifters, impacts, risers, 808 and synth bass lines, delay-time zaps, stutter edits, seamless drum loops, and drum-focused NRT rendering.
---

# SuperCollider drum synthesis

Build or refine drum timbres and rhythms in stock SuperCollider. Preserve the requested musical character; frequency bands and genre grids below are starting points.

## Choose the relevant material

- Voice design, velocity, envelopes, spectral problems, and what listening tests rejected: [sound design](references/sound-design.md).
- Density, complexity, pattern strings, swing, hat choke, and fills: [patterns](references/patterns.md).
- Bus order, ducking, stems and mix targets, seamless loops, one-shot batches, NRT, and audio checks: [rendering and routing](references/rendering.md).
- Working kick, snare, clap, rim, closed/open hat, and crash definitions: [synthdefs.scd](assets/synthdefs.scd). The file returns an array of SynthDefs without booting or sending to a server.
- Processing each voice like a produced one-shot (transient shaper, saturation, compressor, EQ, chorus, delay and reverb sends) with listening-approved per-voice presets: [fx.scd](assets/fx.scd).
- Tempo-synced sound effects and bass (trap, lo-fi, and sci-fi downlifters, impacts, sweeps up, modulated swells, 808 and synth bass), with the reference measurements behind them: [se_bass.scd](assets/se_bass.scd) and [sound design](references/sound-design.md#sound-effects-and-bass). Placing them in a loop and writing mono bass lines with slides: [patterns](references/patterns.md#effects-at-the-head-of-a-loop).
- A delay-time zap (a comb filter whose delay lengthens after each hit, so its resonance dives, with a reverb on the zapped sound only) as an insert retriggered per hit, and a standalone laser: [zap.scd](assets/zap.scd), whose defaults are the listener's favourite. Design, approved settings and measurements: [sound design](references/sound-design.md#delay-time-zap); per-hit routing: [rendering](references/rendering.md#zaps-triggered-per-hit).
- Stutter gestures after iZotope Stutter Edit 2 (repeats that shorten, step, reverse, bend, filter, crush, or tape-stop across a gesture of a set length) on a rendered loop, leaving every sample outside the gestures untouched: [stutter.scd](assets/stutter.scd), with the approved gestures in [sound design](references/sound-design.md#stutter-gestures) and their placement in [patterns](references/patterns.md#zaps-and-stutters-in-a-phrase).
- Audible examples: [drums-nrt.scd](examples/drums-nrt.scd) renders a six-voice gallery and seeded beat; [sidechain-nrt.scd](examples/sidechain-nrt.scd) renders an ordered kick/music/ducking graph; [garage-nrt.scd](examples/garage-nrt.scd) renders a listening-approved 8-bar UK garage loop with choked hats, mix targets, and a seamless loop point; its `fx` argument renders the approved processed version. [se-nrt.scd](examples/se-nrt.scd) renders any of 16 listening-approved effect presets at a chosen tempo; [trap-se-nrt.scd](examples/trap-se-nrt.scd) renders approved trap loops with an impact and a downlifter on bar 1, risers into the loop point, and 808 and synth bass lines; its `zap` and `snarezap` loops retrigger a zap on every clap or snare. [zap-nrt.scd](examples/zap-nrt.scd) renders eight approved zaps (clap, snare, hat, lasers) as one-shots; [stutter-nrt.scd](examples/stutter-nrt.scd) plays the ten approved stutter gestures at chosen beats of any rendered stereo 48 kHz loop.
- Comparing renders with a reference one-shot library: [analyze_refs.py](scripts/analyze_refs.py) measures length, band energy, centroid, noisiness, pitch cues, stereo width, and traces of processing (transient drop, decay knee, tail width, echoes, harmonics) per file. [analyze_se.py](scripts/analyze_se.py) measures effects and bass in bars at a given tempo: level contour, pitch drift in semitones per bar, roll-off and centroid over time, beat-grid modulation (rate, depth, cycle shape), sub share, decay slope, and width.

## Workflow

1. Set the target groove, tempo, meter, output format, and whether the result is a loop or a piece with a decay tail. Infer reasonable defaults when the task supplies no preference.
2. Start with the relevant voice(s). Check quiet and accented hits separately before mixing. Keep timbral velocity separate from output `amp` when independent level control matters.
3. When a reference library is available, measure it and your one-shots with the same features and tune toward its per-category medians before judging by ear. Offer one-shots individually for good/bad listening before building loops; a loop hides a bad timbre.
4. Use sample rate and device settings that the actual destination supports. The examples use 48 kHz, stereo, 24-bit WAV; this is an example format, not a universal DAW or Bluetooth requirement.
5. For NRT, include every SynthDef and group in the score, use explicit event times and render duration, and inspect the process exit status and audio. For RT, finish asynchronous setup before scheduling sound and put source nodes before processors that read them.
6. Verify voice audibility, peak/RMS, clipped samples, DC, duration, and any requested band balance. Mark listening and hardware-output checks separately; numerical analysis does not establish listening acceptance.

## Avoid repeat failures

- `Lag.ar(in, attack, release)` interprets `release` as a gain multiplier. For separate rise/fall times use `LagUD.ar(in, attack, release)`.
- Audio buses 0 onward include hardware outputs and inputs. Allocate private buses for sidechain or mix signals; never send a positive detector envelope to output bus 0 by default.
- Check the oscillator's spectrum before filtering it. Sines below a high-pass cutoff become attenuated; high sine partials, resonators, noise, and pulse waves can all be valid metallic sources.
- `Env.perc` accepts a control/UGen duration inside a SynthDef. Keep segment times positive; use `timeScale` when scaling the whole envelope is intended.
- Scope cleanup to the processes, groups, nodes, buses, and OSC handlers created by this task. Check TCP/UDP ports before launch. A process name is not an ownership record.
- Six squares at 0.9-2.3 kHz behind a 12 dB/oct high-pass leave sparse pitched partials below 5 kHz; listeners heard a cowbell. Use the TR-808 square set (205-800 Hz), whose odd harmonics are dense above 7 kHz, behind a 24 dB/oct high-pass.
- A bank of `Ringz` resonators is a bell, not a crash: one put 99.8% of its energy into 20 FFT bins. A crash needs broadband noise plus dense metal.
- Claps that share fixed burst timing differ only in band and sound alike. Vary burst count, spacing (4-19 ms), band, and tail length.
- Rims made of sine partials carry a pitch (autocorrelation 0.69-0.87). For a dry, unpitched rim, knock with band-passed noise and colour it with modes that ring only a few milliseconds.
- Hats of ~35 ms read as percussion. Closed 70-120 ms and open 0.5-0.9 s passed, with every hat hit choking the ringing hat, also across a loop seam.
- sclang binary operators have no precedence: `a + b * 2` is `(a + b) * 2`. Parenthesize.
- Formatting an Event or long collection into a string truncates it. Print explicit `key=value` pairs when a log is parsed.
- A negative argument default needs a space: `|thresh= -12|`. `thresh=-12` is a parse error (`=-` lexes as one operator). On a parse error sclang runs nothing, waits instead of exiting, and its buffered error text is lost when a timeout kills it; compile-check a script (`File.readAllString(path).compile`, then exit) when a render hangs silently.
- `LeakDC.ar(sig)` defaults to coefficient 0.995, a high-pass near 38 Hz at 48 kHz that thins kick fundamentals when stacked. Use `LeakDC.ar(sig, 0.9995)` (~4 Hz) to remove DC after saturation.
- Set compressor attack by role: a 10 ms attack lets a kick's transient through; on hats, claps, and snares a 5 ms attack left a spike in front of the squeezed body and raised the peak-to-RMS ratio, while 0.5 ms lowered it.
- `Score.recordNRT` without `oscFilePath` writes its score to `temp_oscscore` plus `UniqueID.next`, and `UniqueID` starts at 1000 in every sclang, so renders running at the same time overwrite each other's scores: three of five concurrent renders failed. Pass an `oscFilePath` derived from the output path and name temporary files per output, as the examples do.
- Peak mix targets bury sustained effects: a riser set 12 dB under the kick's peak measured about -38 dBFS RMS over its own bars, against an 808 at -19 dBFS. Check effects by their RMS over the bars they play.
- Saturation after a closing low-pass refills the highs it removed; a downlifter's roll-off stopped at 470 Hz instead of 280. Saturate the source, then filter.
- Noise UGens without `RandSeed.ir(1, seed)` make every render of an effect differ slightly; seed each SynthDef that uses noise.
- A zap's dive is heard only while the source or the comb still sounds. On a rim (gone within about 0.1 s) listeners found it too short; use a clap or snare, a `sweep` about as long as the source, or a longer `ring`.
- `n_set` changes only the controls it names: a stutter gesture that leaves out `reverse` or `pitchB` inherits the previous gesture's. Send every setting with each gesture.
- A stutter that starts where the loop has no hit repeats near-silence; two-beat gestures on the garage loop's empty third beat sounded weak. Start the repeated slice on the previous hit with `offset` (-0.25 beat there).
