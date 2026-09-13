# Rendering, routing, and verification

## Run the maintained examples

Requirements: Python 3.10+, `sclang` and `scsynth` on PATH, and a stock SuperCollider class library. No Python audio packages, Node.js, OSC library, or sc3-plugins are required. The verifier discovers common macOS/Linux class-library locations; pass `--class-library` if installed elsewhere. The verified version is SC 3.14.1; other versions require a local run.

From the skill directory:

```sh
python3 scripts/verify_examples.py
```

This runs both NRT examples and repeats the seeded drum render in a temporary directory. It selects a checked free UDP port for each sclang process and uses an explicit temporary class configuration with `-a` so the user's configured extension paths are not loaded. It cleans up only its own process group after success, timeout, errors, Ctrl-C, or SIGTERM. On Linux it supplies the offscreen Qt setting when none is configured. Class isolation is not a security sandbox; intentionally detached descendants are outside process-group cleanup. NRT scsynth consumes a score file without opening an audio device or network port.

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

`Score.recordNRT` has its own `sampleRate` argument; set it explicitly rather than relying on `ServerOptions.sampleRate` alone. A nil OSC-file path lets Score choose a unique temporary filename; a shared fixed path such as `/tmp/x.osc` races across renders. CLI examples inspect the callback exit status and exit the dedicated sclang process after completion. Do not put `0.exit` into a reusable interactive rendering function, because that would terminate its caller's language session.

NRT duration is quantized by processing blocks. On the verified runtime, a requested 18 seconds at 48 kHz with 64-frame blocks produced 864,064 frames, one block beyond 18 seconds; the four-second example similarly produced 192,064 frames. The verifier accepts at most one block of duration difference. For sample-exact DAW loops, verify the actual frame count and intentionally crop/wrap the tail to the requested sample count.

The stock [NRT guide](https://doc.sccode.org/Guides/Non-Realtime-Synthesis.html) describes the distinction between language and server resources, score event times, and `recordNRT` parameters.

## Audio acceptance

Before using a render, confirm its channels, sample rate, sample format, frame count, non-silence, and process success. Inspect each voice in isolation as well as the mix. For noise-heavy voices, report window lengths alongside RMS values: a 35 ms hat naturally has a low RMS over a 500 ms window.

Measure transient peaks as well as band RMS. Relative band-energy percentages alone can conceal a missing upper-frequency layer when a long sub dominates total energy. Compare reference loops at matched loudness and with the same analysis bands; no single band peak or crest-factor target defines a good drum mix.

Multiband processing needs a deliberate crossover design. Summing independent LPF/HPF bands can change amplitude and phase around crossover frequencies, so verify the bypass sum before treating it as a transparent multiband compressor. Saturation, limiting, and normalization change the result and should follow the requested sound and delivery target. A peak normalization target such as −2 dBFS is optional, not a universal requirement.

Device sample rate is a separate RT concern. Choose a rate supported by the selected audio device and confirm the actual booted configuration. Setting every Bluetooth device to 44.1 kHz is not a general crash-prevention guarantee. Disable hardware input only when the task does not need it.
