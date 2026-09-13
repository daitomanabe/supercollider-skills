# Drum sound design

## Frequency choices

These ranges describe useful emphasis, not isolated brick-wall bands. `LPF`/`HPF` have slopes and phase responses; BPF's `rq` controls bandwidth relative to center frequency. Saturation after a filter creates additional harmonics.

| Layer | Starting emphasis | Technique |
|---|---|---|
| Kick sub | 30–80 Hz | Swept sine; optional low-pass near 80 Hz |
| Kick punch | 100–250 Hz | Second harmonic or damped resonance |
| Kick click | 2–6 kHz | Short band-pass noise burst |
| Snare body | 150–400 Hz | Pitched sine/resonator with fast pitch drop |
| Snare noise | 0.8–2.5 kHz and 4–8 kHz | Separate noise bands and envelopes |
| Snare wires | Above 3 kHz | High-pass noise, optionally short comb coloration |
| Closed/open hat | Above roughly 4–6 kHz | Pulse bank, high resonances, or filtered noise |
| Clap | 1–3 kHz | Several delayed bursts plus a quieter tail |
| Crash | Broad upper mids/highs | Inharmonic resonances with individual decay times |
| Small clicks | 2–5, 5–8, or above 9 kHz | Distinct resonant/noise components to separate roles |

Check the spectrum both before and after each filter. For example, sine oscillators at `880 * [1, 1.4471, 1.617, 1.9265, 2.5028, 2.6637]` are all below 2.35 kHz. A 5 kHz high-pass attenuates them substantially. A pulse bank at these frequencies retains higher harmonics; sines placed above the cutoff also work. Choose the source for the desired sound rather than requiring one oscillator family for every hat.

## Voice structure and envelope ownership

The executable [SynthDefs](../assets/synthdefs.scd) retain these structures:

- **Kick:** sub sine, short second-harmonic punch, and transient noise; a rapid curved pitch sweep settles at `freq`.
- **Snare:** pitched body, two noise bands, and comb-filtered wires. A low-noise, higher-pitched variant can become a rim; longer/lower body and noise envelopes can become a layered snare.
- **Clap:** bursts at 0, 8, and 14 ms plus a quieter filtered tail. Delayed bursts need explicit zero-level segments.
- **Hats:** six inharmonic pulse oscillators share ratios across closed and open versions. The open version adds amplitude modulation and longer decay. Choking an open hat requires a separate gate/group policy; these one-shot examples do not implement choke groups.
- **Crash:** eight upper-frequency resonances excited by a short noise burst, individual decay times, and a broad noise component. Resonance frequencies are capped below Nyquist.

Attach `doneAction: 2` to an envelope that owns the complete voice lifetime. If a short transient envelope frees the synth, longer body/resonator tails disappear. The crash example applies an overall envelope to reach silence before freeing; lengthen it when longer tails are desired.

Use a short positive attack for hard transients when a zero-time discontinuity causes clicks. A click can also be intentional; assess it in the requested sound. `Env.perc(attack, releaseControl)` works inside a SynthDef. EnvGen samples time parameters as segments begin, so changing a control need not rescale an already running segment. `timeScale` scales the envelope rather than fixing a general UGen-duration limitation. See [EnvGen](https://doc.sccode.org/Classes/EnvGen.html).

## Velocity, level, and saturation

Separate velocity from final level when output balance should not change the articulation:

```supercollider
// Inside a SynthDef: velocity and amp are controls, sig is the signal.
velocity = velocity.clip(0, 1);
noiseLayer = noiseLayer * (0.2 + (velocity * 0.6));
drive = 1.2 + (velocity * 1.5);
sig = (sig * drive).tanh / drive.sqrt;
sig = sig * velocity * amp;
```

The square-root compensation is a useful artistic approximation, not loudness matching. Measure or audition at matched level when comparing different drive settings. Low velocity can reduce high-frequency layers, transient strength, or decay; high velocity can increase them. Keep continuous amplitude controls independent when a mixer or automation needs transparent level adjustment.

Useful variation directions:

| Voice | Quiet articulation | Accented articulation |
|---|---|---|
| Kick | Smaller click, gentle drive | More transient and drive |
| Snare | Body-led, short noise | Stronger wires/high noise |
| Hat | Lower level, softer high band | Brighter and sharper |
| Crash | Shorter resonance envelope | Longer tail and broader spectrum |

These are design choices. A dynamically consistent hat or an inverse-velocity decay is equally valid when requested.

## Syntax details worth retaining

- Put `var` declarations before executable statements in every block.
- For nested data, use ordinary arrays such as `[[1, 2], [3, 4]]`. Explicit nesting with `#[#[1, 2]]` is a parse error.
- Parenthesize an Association's fallback value: `\key -> (value ? fallback)`. `\key -> value ? fallback` applies `?` to the Association and can leave its value nil.
- Core-only examples use built-in UGens. `JPverb` needs an extension; `FreeVerb2` is one available stock reverb, with a different sound and parameter model.
- A thrown error stops the current evaluation block. Keep definitions/setup observable so a failed SynthDef is identified before scheduling patterns or registering dependent OSC callbacks.
