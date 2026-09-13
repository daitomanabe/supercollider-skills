---
name: sc-composition-toolkit
description: Compose, sequence, design SynthDefs and effects, and render verified WAV or stems with SuperCollider. Use for SuperCollider sound design, Pbind arrangements, granular synthesis, logical multichannel routing, and headless non-realtime rendering.
---

# SuperCollider composition

Use stock SuperCollider as the baseline. This skill includes a bounded headless runner, a short NRT example, and a streaming WAV checker; no separate composition repository, Quark, sample pack, or plugin is required.

## Choose the workflow

- For a WAV, stems, or an offline preview, use NRT. It runs `scsynth` without opening an audio device. Start from [examples/render_minimal.scd](examples/render_minimal.scd) and read [references/nrt.md](references/nrt.md).
- For synthesis, sequencing, effects, samples, or logical spatial output, read the relevant sections of [references/composition.md](references/composition.md).
- If the user already supplies the separate composition toolkit, read [references/optional-toolkit.md](references/optional-toolkit.md). Its `~pb`, `~renderExample`, and `ctx` helpers are project APIs, not stock SuperCollider.

## Run and verify

Resolve this skill's directory as `SKILL_DIR`; commands work after installing this folder alone. Python 3.9+ and SuperCollider with `sclang`/`scsynth` are required on macOS or Linux.

```sh
mkdir -p render
python3 "$SKILL_DIR/scripts/run_sclang.py" --timeout 60 -- \
  "$SKILL_DIR/examples/render_minimal.scd" "$PWD/render/minimal.wav"
python3 "$SKILL_DIR/scripts/check_wav.py" render/minimal.wav \
  --channels 2 --sample-rate 48000 --duration 3 --duration-tolerance 0.01
```

The runner chooses and checks a high UDP language port, uses a temporary class configuration with `sclang -a` to exclude user extensions, and cleans up only its own process group on completion, timeout, or interruption. It accepts `--sclang`, `--scsynth`, `--class-library`, `--include-path`, `--port`, and `--log`; see `--help`. Check every additional realtime/OSC port separately before binding. The runner is process supervision, not a sandbox for untrusted `.scd` files.

Use a bounded runner for unattended jobs: a parse error can prevent an in-script watchdog from executing. Scripts must explicitly exit on success and error; the NRT callback must check the server exit status. Never clean up by killing processes by name or by a shared port.

For each changed sound or render path, compile it and make one short render. Check the actual output's expected channels, sample rate, duration, non-silence where intended, finite samples, and peak/headroom. A process exit of zero alone is insufficient. Run broader regression only when shared behavior changed or the task requires it. The checker measures technical properties; listening and physical output routing need their own evidence.
