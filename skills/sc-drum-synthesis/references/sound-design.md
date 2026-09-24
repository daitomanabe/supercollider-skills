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
| Closed/open hat | Above roughly 7 kHz; references centre near 7 kHz | TR-808 square set behind a 24 dB/oct high-pass, or noise with a 3-6 kHz share |
| Clap | 1–3 kHz | Several delayed bursts plus a quieter tail |
| Crash | Broad upper mids/highs | Broadband noise plus dense square partials, darkening as it decays |
| Rim (dry) | 1.5-3.5 kHz | Band-passed noise knock plus inharmonic modes ringing a few ms |
| Small clicks | 2–5, 5–8, or above 9 kHz | Distinct resonant/noise components to separate roles |

Check the spectrum both before and after each filter. For example, sine oscillators at `880 * [1, 1.4471, 1.617, 1.9265, 2.5028, 2.6637]` are all below 2.35 kHz. A 5 kHz high-pass attenuates them substantially. A pulse bank at these frequencies retains higher harmonics; sines placed above the cutoff also work. Choose the source for the desired sound rather than requiring one oscillator family for every hat.

## Voice structure and envelope ownership

The executable [SynthDefs](../assets/synthdefs.scd) retain these structures:

- **Kick:** sub sine, short second-harmonic punch, and transient noise; a rapid curved pitch sweep settles at `freq`.
- **Snare:** pitched body, two noise bands, and comb-filtered wires. A low-noise, higher-pitched variant can become a rim; longer/lower body and noise envelopes can become a layered snare.
- **Clap:** up to four noise bursts `spread` seconds apart (gains `g1`-`g4`) through one band-pass, then a band-passed room tail. Each burst is its own `WhiteNoise` delayed with `DelayN`, so the bursts are uncorrelated and no envelope time depends on a control.
- **Rim:** a click, a band-passed noise knock lasting `bodyDecay`, and eight inharmonic `Klank` modes over 0.7-5 kHz that ring only `decay` (about 5 ms), so it knocks like wood without a pitch. `wires` adds snare hiss.
- **Hats:** `drumHatClosed` and `drumHatOpen` share one graph: the TR-808 square set (205.3, 304.4, 369.6, 522.7, 540, 800 Hz) behind two cascaded high-passes near 7-8 kHz with a 10.5 kHz emphasis. They differ only in default `decay` (0.1 and 0.7 s). `gate` 0 closes a hat within 15 ms, which is how a new hat hit chokes the ringing one; see [patterns](patterns.md).
- **Crash:** white noise plus the 808 square set (x1.7) through a high-pass, a low-pass falling from 14 to 5 kHz over the decay, and a 7.5 kHz band.

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

## What listening tests rejected, and what replaced it

One-shots were rendered individually, rated good/bad, and measured. The rejected voices were earlier versions in this file.

| Voice | Heard as | Measured cause | Replacement that passed |
|---|---|---|---|
| Hats (six squares at 0.9-2.3 kHz, 12 dB/oct HPF) | Cowbell | 15-46% of energy below 5 kHz, strongest partials 2.6-4.1 kHz | TR-808 square set, 24 dB/oct HPF near 7-8 kHz |
| Hats at ~35 ms, open hats at 0.12-0.35 s | Percussion; open hat too short | Length | Closed 70-120 ms, open 0.5-0.9 s, choked in patterns |
| Noise-only hats | "Too much low end" | Not explained by the spectrum (<0.3% below 5 kHz); preference for the metallic hat | 808 set |
| Crash (eight `Ringz` modes) | Cowbell, "not a crash" | 99.8% of energy in 20 FFT bins; pure tones at 3.1/4.0/5.4 kHz ringing ~1 s | Noise plus 808 metal, darkening |
| Claps with fixed bursts at 0/8/14 ms | All the same | Variants differed only in band centre | Burst count, spacing, band, and tail vary |
| Rims from sine partials | Pitched, too wet | Autocorrelation 0.69-0.87; 95-100% of energy in 20 FFT bins | Noise knock plus few-ms modes: 0.14-0.16 and 28-37% |

Clap presets used in the approved loops (`drumClap` arguments; `g1`-`g3` default to 1, 0.85, 0.7 and `g4` to 0):

| Preset | freq | rq | spread | bursts | burst | tail | tailFreq |
|---|---|---|---|---|---|---|---|
| Tight (garage) | 1500 | 0.45 | 0.005 | 3 | 0.005 | 0.09 | 2000 |
| Room | 1000 | 0.7 | 0.011 | 4 (`g4` 0.6) | 0.007 | 0.35 | 1300 |
| Long | 1400 | 0.55 | 0.008 | 4 (`g4` 0.7) | 0.006 | 0.22 | 1900 |
| 808 | 1100 | 0.5 | 0.0105 | 3 (`g2` = `g3` = 1) | 0.009 | 0.18 | 1100 |
| Snap | 2600 | 0.3 | 0.004 | 2 (`g2` 0.5, `g3` 0) | 0.004 | 0.04 | 3000 |
| Group | 1200 | 0.8 | 0.019 | 4 (`g4` 0.75) | 0.008 | 0.2 | 1500 |

## Measuring against references

`scripts/analyze_refs.py OUT.jsonl DIR...` decodes every WAV with ffmpeg and writes one JSON line per file: length to -20/-40/-60 dB, time of the peak, band-energy shares (20-60, 60-150, 150-400, 400-1k, 1-3k, 3-6k, 6-12k, 12-20k Hz), centroid overall, in the first 30 ms and in 30-300 ms, spectral flatness (500 Hz-16 kHz), crest factor, kick pitch from zero crossings (0-20 ms and 50-150 ms), stereo width (1 - L/R correlation), the autocorrelation peak at 0.25-5 ms lags, and the energy share of the 20 strongest FFT bins. The last two are pitch cues: a pitched hit scores high on both. Categories come from file and folder names.

Compare medians and interquartile ranges per category, then tune toward them. A 55-pack commercial library (2,576 one-shots) measured, as medians:

- Kicks start their sweep at 150-175 Hz and settle at 50-60 Hz, carry 45-50% of their energy below 60 Hz and about as much at 60-150 Hz, and often end abruptly near 200-250 ms. The skill kick starts near 100 Hz, has less 60-150 Hz punch, and a weaker first 30 ms.
- Snares last 150-220 ms to -40 dB with substantial 1-6 kHz energy. The skill snare reaches -40 dB in about 56 ms; lengthen the noise envelopes when a fuller snare is wanted.
- Closed hats centre near 7 kHz with flatness 0.2-0.3. Crashes centre near 4.4 kHz and last about 2.3 s to -60 dB.
- Some packs are wide where the skill voices are mono: ambient-glitch hats (width ~0.5) and claps (~0.3), tech-house crashes (~0.4). Some packs tune claps, snares, and rims to the note in the file name; a clap labelled "Amin" rang at A4, C5, and E5.

These are measurements of one library, not rules. Listening decides.

## Syntax details worth retaining

- Put `var` declarations before executable statements in every block.
- For nested data, use ordinary arrays such as `[[1, 2], [3, 4]]`. Explicit nesting with `#[#[1, 2]]` is a parse error.
- Parenthesize an Association's fallback value: `\key -> (value ? fallback)`. `\key -> value ? fallback` applies `?` to the Association and can leave its value nil.
- Core-only examples use built-in UGens. `JPverb` needs an extension; `FreeVerb2` is one available stock reverb, with a different sound and parameter model.
- A thrown error stops the current evaluation block. Keep definitions/setup observable so a failed SynthDef is identified before scheduling patterns or registering dependent OSC callbacks.
