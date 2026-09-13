# SuperCollider WebUI starter

Local browser controls, independent preview/render parameters, and sequential offline WAV batches. The example uses a seeded tone pattern and reverb built from stock SuperCollider UGens.

## Run

Requirements: Node.js 22+, Python 3.10+, `lsof`, and SuperCollider with `sclang` and `scsynth`. macOS and Linux are supported by the launcher; Windows requires adaptation. The current runtime verification was on macOS with SC 3.14.1.

From this directory:

```sh
npm ci
npm test
./start.sh --check
npm start
```

Open the URL printed after **Ready**. Engine startup does not boot the template's audio server. Play boots it and plays the selected duration, plus a one-second tail. Start Batch writes to `output/<batch-id>/`; each successful take has a WAV and a JSON sidecar. `batch.json` records completion, failures and stop status. Ctrl-C stops only this launcher's processes.

For rendering without enabling Play:

```sh
SCW_NRT_ONLY=1 npm start
```

SC class loading uses a temporary config containing only the stock library. This excludes installed extensions, but does not disable existing user startup scripts. Inspect those before running on an unfamiliar installation.

## Configuration

The four defaults in `config.json` are checked before startup. The launcher refuses occupied ports without terminating their owners.

| Service | Default | Override |
| --- | ---: | --- |
| HTTP + WebSocket | 48761 | `SCW_HTTP_PORT` |
| Node OSC feedback | 48762 | `SCW_FEEDBACK_PORT` |
| sclang commands | 48763 | `SCW_LANGUAGE_PORT` |
| RT scsynth | 48764 | `SCW_AUDIO_PORT` |

HTTP and Node feedback listen on `127.0.0.1`; SC responders accept only loopback senders. This is a local trusted-user tool, not a hosted multi-user application. Browser requests require the exact local Host and matching Origin when supplied. Local command-line WS clients may omit Origin.

`SCLANG` can specify the executable; `SCW_CLASS_LIBRARY` can specify the stock class-library directory. `SCW_DATA_DIR` moves output/logs/presets together. NRT paths cannot contain backslash, backtick, dollar sign, double quote or newline because `Score.recordNRT` builds a shell command. Spaces are supported. Do not remove these checks without replacing that launch boundary.

## Parameter flow

Edit `params.json` and run `npm run generate`. The schema drives validation, UI controls, OSC ordering and generated handlers. `sc/main.scd` uses dictionaries, so additions do not require a second ordered positional parameter list there. Render transport suffixes (`outputDir`, `batchId`) are server-owned.

Preview changes update the live snapshot. Copy Preview → Render copies engine/FX, duration, tempo to both tempo bounds, and seed to a fixed render seed. Reset updates the running preview too. Fixed seeds share the same note decisions in preview and NRT; hardware sample equality is not claimed.

`/api/presets` lists preset names; GET/POST `/api/presets/<name>` reads/writes `{ "preview": {...}, "render": {...} }`. Names are 1–64 letters, digits, underscores or hyphens, beginning with a letter or digit. The starter has these APIs but no preset menu or meters.

## Verification

```sh
npm test
npm run test:integration
```

`npm test` needs no SC installation or audio device. It checks file-only generation, parameter validation, preset traversal rejection, HTTP Host/Origin checks, WebSocket errors, OSC ordering and reconnect state.

`npm run test:integration` launches stock SC with Play disabled. It renders two sequential takes and a repeat, checks 24-bit stereo 44.1 kHz PCM and valid sidecars, compares fixed-seed PCM hashes, stops after the current take, preserves a deliberately occupied port's owner, and terminates a session while an NRT child is active. The tests check ports again after cleanup. Evidence is written to:

- `logs/integration-result.json`
- `logs/integration-sclang.log`
- `logs/integration-supervisor.log`

A WAV's duration is the requested seconds plus a one-second tail, rounded to the server's processing block. NRT job timeout is `max(30, seconds * 4)` wall-clock seconds. Timeout terminates the session; partial files are not completed takes. Stop After Current is graceful and does not abort a WAV in progress.

Browser QA should verify startup status, Play/Stop state, live input/reset, copy behavior, batch progress, reconnect and layout at narrow widths. Audible preview, audio-device selection and listening acceptance remain separate checks.

## Files to customize

- `sc/main.scd`: SynthDefs, note/event generation and FX tail.
- `params.json`: parameter/UI contract.
- `public/index.html`: presentation and any new UI behavior.

Keep bridge validation, startup checks, sequential callback handling and process ownership when replacing the example engine. Temporary `.osc` scores are removed after the NRT process exits. An interrupted process can leave partial files in its unique batch folder; completion is established by `batch.json` and the successful WAV/JSON pairs.

Optional browser automation: install Playwright and its Chromium binary, start `SCW_NRT_ONLY=1 npm start`, then run `SCW_TEST_URL=http://127.0.0.1:48761 npm run test:browser`. `PLAYWRIGHT_MODULE` can point to an existing Playwright package instead. This checks copy/reset isolation, a real batch, reload/reconnect state and 1280 px / 390 px layouts; it writes screenshots and `logs/browser-result.json`.
