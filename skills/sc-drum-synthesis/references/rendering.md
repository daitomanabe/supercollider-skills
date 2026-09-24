# Rendering, routing, and verification

## Run the maintained examples

Requirements: Python 3.10+, `sclang` and `scsynth` on PATH, and a stock SuperCollider class library. No Python audio packages, Node.js, OSC library, or sc3-plugins are required. The verifier discovers common macOS/Linux class-library locations; pass `--class-library` if installed elsewhere. The verified version is SC 3.14.1; other versions require a local run.

From the skill directory:

```sh
python3 scripts/verify_examples.py
```

This runs the NRT examples in a temporary directory: the drum gallery, the garage loop (dry and processed), and the trap loop twice each for same-seed identity, the sidechain graph, and four effect presets, one of them at 120 BPM to check that lengths follow the tempo. It selects a checked free UDP port for each sclang process and uses an explicit temporary class configuration with `-a` so the user's configured extension paths are not loaded. It cleans up only its own process group after success, timeout, errors, Ctrl-C, or SIGTERM. On Linux it supplies the offscreen Qt setting when none is configured. Class isolation is not a security sandbox; intentionally detached descendants are outside process-group cleanup. NRT scsynth consumes a score file without opening an audio device or network port.

To retain WAVs for listening:

```sh
python3 scripts/verify_examples.py --output-dir /absolute/new-evidence-directory
```

The directory must not already contain the example filenames. The output is stereo, 48 kHz, 24-bit WAV. The report includes per-voice levels, clipping/DC checks, same-seed PCM identity, and measured ducking/recovery of a 997 Hz carrier. Listening and hardware output remain separately marked unchecked.

Each `.scd` example is also a command-line entrypoint accepting an absolute output path. If invoking sclang directly, first check and choose a free UDP port for `-u`; supervise its lifetime. Relative asset paths are resolved from the script itself, so execution does not depend on the current working directory. Output paths containing shell-sensitive characters are rejected because the underlying `Score.recordNRT` implementation constructs a shell command. Ordinary spaces are supported.

## Bus and node order

Audio buses are separate from control buses. With two hardware outputs and no inputs, private audio bus indices start at 2. Use `Bus.audio(server, channels)` for dynamically allocated RT resources; in a closed NRT graph, documented non-overlapping indices also work.

The [sidechain example](../examples/sidechain-nrt.scd) has this graph:

```text
kick synth ──> private stereo kick bus ──┬──> detector ──> LagUD ──> gain
                                      └──> dry kick ──────────────┐
tone synth ──> private stereo music bus ──> multiply by gain ────────┼─> stereo output
```

The source group executes before the processor group. `In.ar` reads audio written earlier in the current processing cycle; an incorrectly ordered reader can receive silence. The kick remains dry while the music is ducked. Routing every instrument, including the kick, through the same ducked bus produces a different effect.

`Lag.ar(in, lagTime, mul, add)` has one lag time. Separate attack and release use `LagUD.ar(in, lagTimeU, lagTimeD)`. With an amplitude detector, these are smoothing times; they are not identical to a compressor's threshold/ratio transfer curve. See [Lag](https://doc.sccode.org/Classes/Lag.html), [LagUD](https://doc.sccode.org/Classes/LagUD.html), and [In](https://doc.sccode.org/Classes/In.html).

For RT setup, send the definitions, wait for server synchronization, create private buses and ordered groups, then start playback. Keep handles to those resources for cleanup. Freeing every server node or killing every process named `scsynth` can interrupt other work.

## NRT setup and completion

A realtime server's definitions, groups, and buffers are not automatically available to NRT. Put `\d_recv` for each SynthDef, group creation, node events, buffer operations where needed, and an end event into the Score. Sort the score and supply an explicit duration. `Score.new` creates its default group; custom groups still need score commands.

`Score.recordNRT` has its own `sampleRate` argument; set it explicitly rather than relying on `ServerOptions.sampleRate` alone. With a nil `oscFilePath` it writes the score to `PathName.tmp +/+ "temp_oscscore" ++ UniqueID.next`, and `UniqueID` starts at 1000 in every sclang process, so sclang processes rendering at the same time write the same score files: on SC 3.14.1, three of five concurrent renders failed. The examples pass an `oscFilePath` derived from their output path and delete it afterwards; do the same, and name temporary WAVs per output. A shared fixed path such as `/tmp/x.osc` races the same way. CLI examples inspect the callback exit status and exit the dedicated sclang process after completion. Do not put `0.exit` into a reusable interactive rendering function, because that would terminate its caller's language session.

NRT duration is quantized by processing blocks. On the verified runtime, a requested 18 seconds at 48 kHz with 64-frame blocks produced 864,064 frames, one block beyond 18 seconds; the four-second example similarly produced 192,064 frames. The verifier accepts at most one block of duration difference. For sample-exact DAW loops, verify the actual frame count and intentionally crop/wrap the tail to the requested sample count.

The stock [NRT guide](https://doc.sccode.org/Guides/Non-Realtime-Synthesis.html) describes the distinction between language and server resources, score event times, and `recordNRT` parameters.

## Seamless fixed-length loops

A loop file must be an exact number of frames, and hits near the end must not be cut. Render the loop plus a tail long enough for every voice to fall silent (3 s covers a 1.6 s crash), confirm the last 0.1 s of the render is silent, then add every sample past the loop length back onto the start and crop. `garage-nrt.scd` does this with a self-checked `wrap` function and writes `round(bars * 4 * 60 / bpm * sampleRate)` frames. Verify the step across the seam (last sample to first) against the 99.9th percentile of ordinary sample-to-sample steps; a cut tail shows up there as a click. Choke across the seam as described in [patterns](patterns.md).

## Per-voice stems and mix targets

Render voice k to output channels 2k and 2k+1 (`numOutputBusChannels = 2 * voices`). The stems give each voice's peak for an audibility check and let the mix be set by targets instead of hand-tuned `amp` values: in a first pass read the peak of each voice; in a second pass sum the stems with gain `target.dbamp / peak`, where the target is the voice's loudest hit in dB relative to the kick. The garage loop uses kick 0, clap -3, rim -5, closed hat -12, open hat -11, crash -9. Then normalize the sum (here to -1 dBFS peak). Peak targets survive timbre changes; they are not loudness matching, so long sounds such as open hats and crashes still need listening.

## Processing voices through fxStrip

`assets/fx.scd` returns `(def: fxStrip, presets: (kick: ..., snare: ..., clap: ..., hat: ..., ohat: ..., crash: ...))`. Route each processed voice to a private stereo bus (here 64 + 2k), create one strip per voice at time 0 in a group added after the source group (`[\g_new, 2000, 3, 1]`), and let the strip write the voice's stem to 2k, 2k+1; the stem-based mix targets then apply unchanged. `inGain` in each preset assumes the skill voice at its default `amp` and velocity 0.78; recalibrate it from a raw-peak render if a voice's level or parameters change. Reverb tails need a longer render tail (5 s for the presets), and one-shot slots of 6 s. `garage-nrt.scd` with `fx` shows the routing.

## Sound effects and bass in loops

The effects in `assets/se_bass.scd` take `beat` (seconds per beat) and lengths in beats, so one preset serves any tempo; send `\beat, 60 / bpm` with every event (voices without that control ignore it). Render a tail that covers the longest ring-out past the loop end, 5 s for the trap loops, where a riser ending on the loop point folds its echoes onto bar 1 and leads into the impact. Mix effects by their RMS over the bars they play, not by peak: `trap-se-nrt.scd` uses impact -2, downlifters -5 to -7, riser -5, 808 -1, and synth bass -8 dB against the kick's peak, which brings each effect's RMS over the bars it plays to within about 10 dB of the kick's (the lo-fi dive matches it); at -12 dB the riser was inaudible under the 808. Rendering per-voice stems makes that measurable: sum each stem's squares in the mixing pass. Mono voices (`bass808`, `bassSynth`) get one note at a time; see [patterns](patterns.md#mono-bass-lines).

## One-shot batches for listening

Render many one-shots in one NRT pass: start one hit per fixed slot (for example every 3.5 s, a whole number of 64-sample blocks at 48 kHz), then read each slot, trim at its last non-zero sample, and peak-normalize. Fail the batch if a slot still sounds in its last 0.1 s, since the next slot would contain the tail. Present the files one by one with good/bad ratings; a clear rating per sound is more useful than a verdict on a loop.

Long effects need longer slots (15 s covers 8 bars at 140 BPM) and a different trim: reverb tails approach zero slowly, so trim 20 ms after the level falls 70 dB below the peak and fade over those 20 ms, as `se-nrt.scd` does. A slot that starts on a whole number of 64-sample blocks renders the same samples as a lone render starting at time 0.

## Audio acceptance

Before using a render, confirm its channels, sample rate, sample format, frame count, non-silence, and process success. Inspect each voice in isolation as well as the mix. For noise-heavy voices, report window lengths alongside RMS values: a 35 ms hat naturally has a low RMS over a 500 ms window.

Measure transient peaks as well as band RMS. Relative band-energy percentages alone can conceal a missing upper-frequency layer when a long sub dominates total energy. Compare reference loops at matched loudness and with the same analysis bands; no single band peak or crest-factor target defines a good drum mix.

Multiband processing needs a deliberate crossover design. Summing independent LPF/HPF bands can change amplitude and phase around crossover frequencies, so verify the bypass sum before treating it as a transparent multiband compressor. Saturation, limiting, and normalization change the result and should follow the requested sound and delivery target. A peak normalization target such as −2 dBFS is optional, not a universal requirement.

Device sample rate is a separate RT concern. Choose a rate supported by the selected audio device and confirm the actual booted configuration. Setting every Bluetooth device to 44.1 kHz is not a general crash-prevention guarantee. Disable hardware input only when the task does not need it.
