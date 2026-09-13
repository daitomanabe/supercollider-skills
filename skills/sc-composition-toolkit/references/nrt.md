# Headless non-realtime rendering

`Score` stores timestamped server commands and launches `scsynth -N` through `recordNRT`. The bundled example sends a SynthDef with `d_recv`, schedules four notes, leaves a release tail, and checks the server's callback exit code. It writes 48 kHz stereo 24-bit PCM WAV. Existing output paths are refused.

Use seconds deliberately: `Score.write` uses a tempo clock; set `TempoClock.default.tempo = 1` for a timeline authored in seconds. Put setup before the notes, include explicit SynthDefs and sample-loading commands, sort after adding events, and place the final dummy event after the longest envelope or effect tail. Large SynthDefs can use a temporary `.scsyndef` with `d_load` instead of oversized `d_recv` messages.

The NRT server is a separate process, not a realtime audio server. The language interpreter still binds a UDP port. `run_sclang.py` checks an available high port and passes it with `-u`; there is necessarily a small gap between the preflight release and the interpreter bind. Avoid sharing fixed ports across parallel runs. The helper starts a new POSIX process group and sends TERM then KILL only to that group during cleanup; deliberately detached descendants are outside this guarantee. On a cleanup permission error it checks the actual process table with `ps`: a group with no live members is finished, while a live permission failure remains an error.

The runner supplies `SC_SYNTH` as the resolved server executable. The example assigns `Score.program = "SC_SYNTH".getenv.shellQuote`. `--class-library` and repeated `--include-path` configure class search without changing the user's installed configuration. `-a` isolates class loading; it does not turn SuperCollider into a security sandbox or disable arbitrary behavior in user startup scripts. Run trusted code and inspect startup behavior when configuring an unfamiliar installation.

`Score.recordNRT` builds a shell command. Its own path quoting may expand shell metacharacters, so the example rejects such characters in output paths and passes an explicit validated temporary OSC path. Paths with ordinary spaces are supported. For unrestricted filenames, write the OSC score first and launch `scsynth` using an argument-vector API such as Python `subprocess.run([...])`.

For a server UGen dependency, verify both the language class and server plugin are available; including a Quark does not install its binary UGens. The example uses only stock UGens and `loadDefs_(false)`; existing synthdef files are not needed.

## Validation

`check_wav.py` uses only the Python standard library and reads RIFF/WAVE PCM (8/16/24/32 bit), IEEE float (32/64 bit), and matching WAVE extensible subtypes in chunks. It reports channels, frames, duration, encoding, peak dBFS, RMS dBFS, nonfinite samples, and full-scale samples. It rejects truncated or misaligned data, nonfinite samples, digital silence, and full-scale samples by default. Full scale indicates possible clipping; it cannot establish whether a waveform was clipped earlier in the signal path. `--allow-silence` supports intentional silent assets; `--max-peak-db` enforces project headroom. Unsupported containers such as RF64 need a suitable external streaming analyzer.

The callback's success proves NRT exited normally. The WAV check proves the measured file's technical properties. Neither proves audible quality, speaker wiring, interface channel mapping, or calibration. Report source/output paths, commands actually run, measured values, and remaining task-relevant limits. NRT can finish on a block boundary, so duration checks should allow one block at the chosen sample rate unless exact trimming is part of delivery.

## Sources

- [SuperCollider NRT guide](https://doc.sccode.org/Guides/Non-Realtime-Synthesis.html)
- [Score API](https://doc.sccode.org/Classes/Score.html)
- [Server command reference](https://doc.sccode.org/Reference/Server-Command-Reference.html)
