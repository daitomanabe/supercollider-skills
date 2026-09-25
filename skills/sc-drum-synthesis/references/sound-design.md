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

## Processing like produced one-shots

Commercial one-shots are processed, and the processing leaves measurable traces (`analyze_refs.py`): the drop in the 30 ms after the peak, the decay knee (time from -20 to -40 dB over time from the peak to -20 dB; a dry exponential gives about 1, reverb or compression much more), stereo width of the tail, envelope echoes, kick harmonics (150-1000 Hz over 30-150 Hz in 50-200 ms), and the share of samples within 1 dB of the peak. Medians of the 2,576-file library against the dry skill voices:

| Voice | Reference | Dry skill voice | Processing that closes the gap |
|---|---|---|---|
| Kick | peak/RMS 10.8 dB, harmonics -25 dB | 11.2 dB, -35 dB | Saturation, compression with a 10 ms attack |
| Snare | drops 8 dB in 30 ms, lasts 202 ms, tail width 0.15 | drops 20 dB, 56 ms, mono | Softer attack, sustain boost, fast compression, short room |
| Clap | knee 1.7, tail width 0.26 | 0.8, mono | Reverb, sustain boost |
| Hats | tail width 0.06 (ambient-glitch packs ~0.7) | mono, peakier | Fast compression, chorus |
| Crash | knee 1.4, tail width 0.29 | 1.06, mono | Chorus, large reverb |

`assets/fx.scd` holds the strip and the presets that passed listening. Across punch, knee, tail width, peak-to-RMS, and length for six voices, 23 of 30 medians fall inside the reference interquartile ranges, against 20 dry. The snare changes most (56 to 261 ms, 30 ms drop 20 to 7 dB). The kick's post-peak drop stays below the references (about 3 dB against 7): it follows the synth envelope more than the strip. Delays were left off: most reference echoes are short reflections of 10-60 ms, and a tempo delay clouded the loops. Rims stayed dry at the listener's request.

## Sound effects and bass

`assets/se_bass.scd` holds tempo-synced effects and two basses, matched with `scripts/analyze_se.py` to a commercial trap pack at 140 BPM (30 long sweeps down, 20 impacts, 20 short sweeps up, 30 modulated risers, 50 bass loops, 60 kick-and-sub loops) and two cinematic effect packs (12 lo-fi and 20 sci-fi downlifters), then approved in listening. Reference medians against the approved presets of `examples/se-nrt.scd` and the loops of `examples/trap-se-nrt.scd`, at 140 BPM:

| Effect | Reference median | Approved | Built from |
|---|---|---|---|
| Trap downlifter, 8 bars | -1.4 st/bar; 95 % roll-off 3.7k, 1.9k, 920, 420, 280 Hz over successive fifths of the sound; level holds about 3 bars, then falls to -40 dB at the end; quarter-note modulation 8.9 dB deep; width 0.46 | -1.5 st/bar; 3.8k, 2.1k, 1.1k, 650, 290 Hz; width 0.44-0.48 | `seDown`: detuned supersaws an octave apart, saturated, then a resonant low-pass closing exponentially from 8 kHz to 150 Hz while the pitch glides linearly in semitones |
| Lo-fi downlifter, ~3 bars | mono; 68 then 95 % below 100 Hz; -12 then -4 st/bar; level flat to 60 % of the length | mono; 82 %; -13 then -3.6 st/bar | `seLoDown`: sine and triangle diving along 1 - e^(-3t), low-passed noise following, sample-and-hold at 8 kHz, 8 bits, tanh; optional chop slowing from 16 to 2.5 Hz |
| Sci-fi downlifter, ~5 bars | -1.9 then -0.2 st/bar; roll-off ~1 kHz; width 0.69 then 0.92 | -2.1 then -0.3 st/bar; width 0.55 then 0.82 | `seSciDown`: eight inharmonic partials bending by different amounts, a sine two octaves down, large reverb |
| Impact | 70 % below 100 Hz; -8.5 dB at 0.2 s, -21 dB at 1 s, then -6 dB/s; width 0.14 then 1.0 | 70 then 55 % below 100 Hz; -7.7 dB, -17.5 dB, -6.2 dB/s; width 0.10 then 0.99 | `seImpact`: sine boom swept from 3x to 42 Hz in 30 ms and gone within a second, a noise burst, and a long reverb that carries the tail |
| Sweep up, 4 bars and a tail | peak at bar 3.6; +2.2 then +1.1 st/bar; roll-off 1.7 to 4.9 kHz; -30 to 0 dB; quarter gate 10.8 dB deep; tail ~1.5 bars | bar 3.75; +2.1 then +0.5 st/bar; 1.4 to 4.1 kHz; gate 8.5 dB | `seRise`: supersaw and a noise band with rising pitch and low-pass, quarter-note gate, ping-pong delay and reverb after the stop |
| Modulated swell | no pitch drift; peak near bar 3, then -13 dB within 50 ms; quarter gate 14 dB deep; centroid 1.4-1.8 kHz; width 0.83 then 0.91 | bar 3.0; gate 9 dB; centroid 1.2-1.6 kHz; width 0.88 then 0.75 | `seMod`: detuned four-note chord through an opening low-pass, gated; an accent stops it and quarter-note echoes decay |
| 808 (kick-and-sub loops) | centroid 54 Hz; 88 % below 100 Hz; mono | 51 Hz; 93 %; mono | `bass808`: sine with a 50 ms upward punch that slides skip, tanh |
| Synth bass (bass loops) | centroid 340-390 Hz; roll-off ~1 kHz; 29 % below 100 Hz; width 0.34 | 250 Hz; ~800 Hz; 38 %; 0.34 | `bassSynth`: saws and a square through a per-note filter envelope, a sine an octave down, the right side above 200 Hz delayed 5 ms |

Across length, pitch drift, flatness, sub share early and late, decay slope, width early and late, and modulation depth, 93 of the 144 values of the 16 presets fall inside the reference interquartile ranges, against 59 in the first render.

Beat-grid modulation: folding each reference's level on its strongest musical division (eight bins per cycle, phase 0 on the beat) gave three shapes, and 19 of 30 trap sweeps, 19 of 20 sweeps up, and 24 of 30 modulated risers move on quarter notes. Pump (7 sweeps): -8, -6, -1, +3, +3, +3, +3, +3 dB, deepest on the beat and recovered by 0.4 of the cycle; `tempoGate` style 0 uses `-depth * (1 - (p / 0.45)^2)`. Gate (6 sweeps): +3, +4, +4, +4, -5, -7, -4, +1, open for the first half, shut fast, reopening before the next beat; style 1. Tremolo on eighths (8 sweeps): +2, +1, -1, -2, -2, -1, 0, +1; style 2, a raised cosine. The measured depth includes what echoes and reverb fill in: the riser's 15 dB setting measured 8.5 dB and the swell's 18 dB measured 9, so set the modulator well beyond the target when the effect has a tail.

What the measurements caught along the way:

- Saturating after the closing low-pass refilled the highs: the downlifter's roll-off stopped at 470 Hz instead of 280. Saturate the source, then filter.
- An impact's tail has to be the reverb's, not the direct sound's. With a slow direct boom tail the level 1 s after the hit was -14.6 dB (reference -21); turning the reverb down instead narrowed the ring and echo variants' tails to width 0.55-0.6. A direct boom gone within a second (`boomTail` 0.02) with the reverb at 0.35 gave -17.5 dB and width 0.99. An unfiltered send made the tail a second boom (84 % below 100 Hz late, reference 58 %); high-passing the send at 60 Hz brought it to 55 %.
- The reference bass loops are mid basses (centroid ~340 Hz) meant to sit over separate kick-and-sub loops. At F2 the synth bass measured 165 Hz; an octave up with its sub an octave down matched, and it layers over the 808 with the sub off.
- Noise UGens without `RandSeed` made each render of an effect differ slightly; the same-seed comparison caught it.

## Delay-time zap

`assets/zap.scd`: after each trigger a short feedback delay (`CombC`, cubic interpolation, so its time can change every sample) lengthens from 1/`hiFreq` to 1/`loFreq` over `sweep` seconds, and the comb's resonance falls in pitch; while the delay line lengthens, its Doppler shift pulls the ringing down further. `curve` shapes the move (fast first when large; 1.5 is close to a straight line in octaves). `ring` is the comb's decay time: short keeps the feedback short, and a negative value feeds back inverted, sounding odd harmonics an octave lower, a hollow tone. The feedback gain g = 0.001^(delay/ring) changes with the delay; scaling the output by sqrt(1 - g²) keeps a noisy input's level steady through the dive. `fxZap` crossfades from the dry input to the zapped sound for `sweep` + |`ring`| after each trigger (1 ms in, 20 ms out) and sends only that window to a reverb (15 ms predelay, high-passed at 200 Hz, `FreeVerb2`), so hits left alone stay dry. `seZap` puts a 4 ms noise burst through the same sweep: a laser.

Listeners liked the zap as a whole on its first round (clap, snare, hat, rim, lasers), then asked for a reverb whenever it sounds, and picked a tight clap with a slow dive as the favourite; its setting is `fxZap`'s default. On a rim the dive was over too soon to hear. On a snare they asked for the dive while the snare sounds and in a short tail after it: a sweep about the dry snare's length with little feedback (`snare_dive-verb`). The approved one-shots in `examples/zap-nrt.scd`, all with the reverb at 0.4, room 0.8, damp 0.5:

| Preset | Source | hiFreq to loFreq (Hz) | sweep (s) | curve | ring (s) | mix |
|---|---|---|---|---|---|---|
| `clap_zap-slow-verb` (favourite) | tight clap | 3000 to 80 | 0.35 | 1.5 | 0.3 | 0.7 |
| `clap_zap-verb` | tight clap | 3000 to 110 | 0.15 | 3 | 0.12 | 0.7 |
| `snare_dive-verb` | snare | 4000 to 120 | 0.15 | 2 | 0.06 | 0.85 |
| `snare_slow-verb` | snare | 3000 to 80 | 0.35 | 1.5 | 0.3 | 0.7 |
| `hat_pew-verb` | closed hat | 6000 to 500 | 0.12 | 2 | 0.15 | 0.8 |
| `laser-verb` | `seZap` | 5000 to 60 | 0.25 | 3 | 0.25 | |
| `laser-short-verb` | `seZap` | 4000 to 150 | 0.08 | 3 | 0.1 | |
| `laser-hollow-verb` | `seZap` | 5000 to 80 | 0.25 | 3 | -0.3 | |

The favourite's resonance follows the programmed delay: the autocorrelation peak of 30 ms windows starting 10 ms and 100 ms after the hit lies at 0.58 and 2.0 ms, where the sweep puts the delay at 0.54 and 2.04 ms (window centres); ten dry and processed claps show no such rise. The verifier checks it. With `verb` 0 the output equals that of the SynthDef without a reverb, sample for sample.

## Stutter gestures

`assets/stutter.scd` follows iZotope Stutter Edit 2. A gesture lasts a set number of beats; during it the sound is replaced by repeats of the slice that starts at the trigger, or `offset` beats from it (Stutter Edit's buffer position). Each setting moves from a start to an end value across the gesture: the repeat length (`divA` to `divB` in beats, shaped by `curve`, or stepped through powers of two with `step`), the part of each repeat that sounds (`width`), pitch plus a random offset per repeat (`jitter`), pan alternating between repeats, high- and low-pass cutoffs, bit depth and sample rate, and gain. `reverse` plays each repeat backwards; `tape` turns the gesture into a tape stop, slowing the read head from full speed to a halt. `stutterPlay` plays the rendered loop from a buffer at whole-sample positions, so outside gestures the output is the input sample for sample, and it crossfades over 4 ms at each end of a gesture.

The ten gestures approved in listening (`examples/stutter-nrt.scd`), heard at 132 BPM on the garage loop and in garage, trap and house loops:

| Gesture | Beats | Repeat length | Other moves |
|---|---|---|---|
| `fill16` | 1 | 1/16 | width 0.9 |
| `accel` | 2 | 1/8 sliding to 1/64 | high-pass rising to 600 Hz |
| `stepped` | 2 | 1/8, 1/16, 1/32, 1/64 in turn | width 0.85 |
| `triplet` | 1 | 1/8 triplet | width 0.6, pan swing 0.6 |
| `pitchup` | 2 | 1/16 to 1/32 | up 12 semitones, low-pass opening from 3 to 18 kHz |
| `pitchdown` | 1 | 1/16 | down 12 semitones, low-pass closing from 16 to 1.5 kHz |
| `reverse` | 1 | 1/8 | each repeat reversed |
| `tapestop` | 2 | none | tape stop, low-pass closing from 18 to 2.5 kHz, -6 dB |
| `lofi` | 1 | 1/32 | width 0.35, 8 to 6 bits, 8 to 4 kHz sample rate |
| `jitter` | 1 | 1/16 to 1/32 | random ±7 semitones per repeat, pan swing 0.8 |

Two-beat gestures that started on the garage loop's third beat of bar 2, where it has no hit, repeated a near-empty slice and sounded weak; starting the slice a sixteenth earlier, on the kick (`offset` -0.25), fixed them.

## Measuring against references

`scripts/analyze_se.py OUT.jsonl BPM FILE_OR_DIR...` measures tempo-synced effects and bass in bars at `BPM`: onset, peak and -40/-60 dB ends, level at tenths of the sound, 95 % roll-off and centroid per fifth, pitch drift in semitones per bar (whitened log spectra 0.5 s apart, cross-correlated), flatness, sub share before and after the first 0.5 s, decay slopes (full band, sub, highs), level 50 ms, 0.2 s, and 1 s after the peak, width early and late, and the strongest modulation of the level (rate, cycles per beat, depth, and the cycle folded on the beat grid). It self-checks on a synthetic gated glide before running.

`scripts/analyze_refs.py OUT.jsonl DIR...` decodes every WAV with ffmpeg and writes one JSON line per file: length to -20/-40/-60 dB, time of the peak, band-energy shares (20-60, 60-150, 150-400, 400-1k, 1-3k, 3-6k, 6-12k, 12-20k Hz), centroid overall, in the first 30 ms and in 30-300 ms, spectral flatness (500 Hz-16 kHz), crest factor, kick pitch from zero crossings (0-20 ms and 50-150 ms), stereo width (1 - L/R correlation), the autocorrelation peak at 0.25-5 ms lags, and the energy share of the 20 strongest FFT bins. The last two are pitch cues: a pitched hit scores high on both. Categories come from file and folder names. The processing traces are described in the section above.

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
