# Template customization

## Setup and ports

Work on a copy of `assets/starter-template`, run `npm ci`, and start through `./start.sh`. The Python supervisor checks dependencies, all ports, HTTP response, and SC status. `npm run server` starts only the Node bridge for development; it does not provide the SC process or the full launcher's lifecycle guarantees.

| Service | Default | Environment override |
| --- | --- | --- |
| HTTP and browser WebSocket | TCP 48761 | `SCW_HTTP_PORT` |
| OSC feedback to Node | UDP 48762 | `SCW_FEEDBACK_PORT` |
| sclang language port | UDP 48763 | `SCW_LANGUAGE_PORT` |
| Realtime scsynth | UDP 48764 | `SCW_AUDIO_PORT` |

Defaults live in `config.json`; choose four distinct, free ports. The launcher checks both current owners and bind availability, and refuses occupied ports. Preserve this preflight when changing the launcher. For example:

```sh
SCW_HTTP_PORT=49661 SCW_FEEDBACK_PORT=49662 SCW_LANGUAGE_PORT=49663 SCW_AUDIO_PORT=49664 ./start.sh --check
```

Use the same overrides for the subsequent launch. The check does not reserve ports between runs.

`SCLANG` selects an executable path; `SCW_CLASS_LIBRARY` selects the stock class library. The launcher uses a temporary `-l` configuration and `-a` rather than changing the user's configuration. Extra Quarks or plugins are a deliberate project extension. `SCW_NRT_ONLY=1` disables audio preview. `SCW_DATA_DIR` selects the output/log/preset root; ordinary spaces are supported, while shell-sensitive path characters are refused because `Score.recordNRT` builds a shell command.

The demo uses 44.1 kHz stereo PCM24 and a one-second NRT effect tail. This is a template choice. For another format, update SC realtime options, NRT options and `recordNRT` arguments, sidecar metadata in `server.js`, and matching tests together. Confirm the actual audio device supports the selected RT rate.

## Customize the engine

1. Edit `params.json`: types, defaults, limits, enum choices, OSC parameter order, and UI groups/panels. Keep output paths and batch IDs under Node control.
2. Replace `~voiceDef`, `~fxDef`, and `~noteForStep` in `sc/main.scd`. Both preview and NRT use the shared note rule. Add a parameter to the schema and its actual DSP/event usage together.
3. Preserve explicit source-before-FX node order and private bus allocation. Live `fxMix` updates the running FX node; tempo, seed, and engineDrive affect subsequent notes.
4. Run `npm run generate`. It creates `sc/generated/osc_handlers.scd`, including its directory, from the schema. Do not edit that generated file.
5. Extend `public/index.html` only for behavior the schema cannot express. Controls are already generated from schema groups; preview and render values stay independent.

Presets are available through `/api/presets` and `/api/presets/:name`; the starter browser does not provide a preset editor. Keep the validated JSON API when adding one. Logs, progress, output paths, and connection state are implemented. Metering is an optional extension.

## Validate

```sh
npm test                  # Contract and real HTTP/WebSocket/OSC transport; no SC required
npm run test:integration  # Supervised stock-SC NRT, actual WAV/JSON, cancellation and cleanup
```

The integration test uses temporary data and NRT-only mode. Run it after changes to the SC graph, completion protocol, or launcher. Check no owned live SC process remains and the chosen ports are released. RT device playback requires a separate check.

A launcher interruption stops its Node/sclang process groups, including NRT scsynth children. A timed-out NRT job exits its language process so the supervisor can stop the session. Do not replace this with process-name kills or use a bare background `sclang` process.
