---
name: sc-webui-preview-render
description: Build SuperCollider applications with a browser WebUI, shared parameter schema, OSC/WebSocket control, realtime preview, and sequential offline batch rendering. Use for SC browser control and preview/render integration.
---

# SuperCollider WebUI preview and render

Use one schema for browser controls, OSC argument order, and generated SC handlers. Keep mutable preview settings separate from each render job's parameter snapshot.

## Start from the template

Copy [assets/starter-template](assets/starter-template) into the requested project. It is a stock-SuperCollider tone engine with a working transport and render path. From the copied directory:

```sh
npm ci
./start.sh --check
npm start
```

Requirements: Node.js 22+, Python 3.10+, SuperCollider (`sclang` and `scsynth`), and `lsof` on macOS or Linux. The launcher prints the checked local URL after both HTTP and SC status respond. It starts the audio server only when Play is pressed. Use `SCW_NRT_ONLY=1 npm start` for offline rendering without opening audio hardware.

Read [template customization](references/template-customization.md) for ports, environment variables, sample rate, engine changes, and test commands. Read [runtime contract](references/beat-generator-patterns.md) when changing schema, transport, batch completion, or cancellation.

## Preserve these behaviors

- Validate parameter types, finite ranges, enum values, and action names at the Node boundary; derive ordered arguments and SC handlers from `params.json`.
- Copy Preview → Render only on explicit action. Freeze a complete render parameter snapshot; live edits must not alter a queued batch.
- Load SynthDefs into each NRT score. Wait for each `recordNRT` callback, verify the WAV, write real JSON, then report that job complete. Include effect tails and propagate failures.
- The batch Stop action means **finish the current job and skip subsequent jobs**. Use launcher interruption to terminate the session and its owned child processes.
- Check all service ports before launch, bind the local browser bridge to loopback, and keep Host/Origin checks. Only clean up processes created by this launcher; occupied ports are a reason to choose new ports.
- Treat engine readiness, audio-server readiness, render completion, and measured audio quality as different states. Numerical NRT checks and browser tests do not prove physical RT output or listening quality.

After changes, run the affected unit/transport tests and a short actual NRT integration test. For RT-specific changes, verify the selected device, actual Play/Stop, parameter response, and shutdown separately. Add meters or project-specific visualization only when needed; the template does not claim to provide them.
