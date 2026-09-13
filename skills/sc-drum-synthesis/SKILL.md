---
name: sc-drum-synthesis
description: Design SuperCollider drum voices, velocity response, beat patterns, and percussion mixes. Use for synthesized kicks, snares, hats, claps, cymbals, and drum-focused NRT rendering.
---

# SuperCollider drum synthesis

Build or refine drum timbres and rhythms in stock SuperCollider. Preserve the requested musical character; frequency bands and genre grids below are starting points.

## Choose the relevant material

- Voice design, velocity, envelopes, spectral problems: [sound design](references/sound-design.md).
- Density, complexity, reproducible patterns, and fills: [patterns](references/patterns.md).
- Bus order, ducking, sample rate, NRT, and audio checks: [rendering and routing](references/rendering.md).
- Working kick, snare, clap, closed/open hat, and crash definitions: [synthdefs.scd](assets/synthdefs.scd). The file returns an array of SynthDefs without booting or sending to a server.
- Audible examples: [drums-nrt.scd](examples/drums-nrt.scd) renders a six-voice gallery and seeded beat; [sidechain-nrt.scd](examples/sidechain-nrt.scd) renders an ordered kick/music/ducking graph.

## Workflow

1. Set the target groove, tempo, meter, output format, and whether the result is a loop or a piece with a decay tail. Infer reasonable defaults when the task supplies no preference.
2. Start with the relevant voice(s). Check quiet and accented hits separately before mixing. Keep timbral velocity separate from output `amp` when independent level control matters.
3. Use sample rate and device settings that the actual destination supports. The examples use 48 kHz, stereo, 24-bit WAV; this is an example format, not a universal DAW or Bluetooth requirement.
4. For NRT, include every SynthDef and group in the score, use explicit event times and render duration, and inspect the process exit status and audio. For RT, finish asynchronous setup before scheduling sound and put source nodes before processors that read them.
5. Verify voice audibility, peak/RMS, clipped samples, DC, duration, and any requested band balance. Mark listening and hardware-output checks separately; numerical analysis does not establish listening acceptance.

## Avoid repeat failures

- `Lag.ar(in, attack, release)` interprets `release` as a gain multiplier. For separate rise/fall times use `LagUD.ar(in, attack, release)`.
- Audio buses 0 onward include hardware outputs and inputs. Allocate private buses for sidechain or mix signals; never send a positive detector envelope to output bus 0 by default.
- Check the oscillator's spectrum before filtering it. Sines below a high-pass cutoff become attenuated; high sine partials, resonators, noise, and pulse waves can all be valid metallic sources.
- `Env.perc` accepts a control/UGen duration inside a SynthDef. Keep segment times positive; use `timeScale` when scaling the whole envelope is intended.
- Scope cleanup to the processes, groups, nodes, buses, and OSC handlers created by this task. Check TCP/UDP ports before launch. A process name is not an ownership record.
