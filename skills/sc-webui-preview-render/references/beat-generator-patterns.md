# Runtime contract

This describes the bundled starter, including its limits. Keep these relationships when adapting it to a beat generator or another musical engine.

## Schema and transport

`params.json` owns parameter types/defaults/ranges, enum options, UI grouping, and ordered OSC arguments. `scripts/contract.js` validates that contract and incoming actions; `scripts/generate-sc.js` produces the SC responders. Node derives paths and batch identifiers, rather than accepting them from a browser control.

Browser actions are `preview/play`, `preview/stop`, `preview/setParams`, `render/start`, and `render/stop`. Node prepends `/` for OSC. Replies use `state`, `log`, `error`, `renderProgress`, `renderJobDone`, `renderError`, and `renderDone` WebSocket events. The `state` snapshot is authoritative for readiness, preview activity, render activity, and reconnecting browsers.

HTTP/WebSocket and OSC feedback bind to loopback. HTTP and WebSocket upgrade requests check Host and Origin, message sizes are bounded, and preset names cannot contain path components. This is a local operator tool: do not expose it remotely without designing authentication and access rules for that deployment. Arbitrary programs on the same machine can still speak local OSC.

## Preview

The audio server is created for this session and boots only on Play. Setup sends the definitions, synchronizes, allocates a private stereo bus, then orders source and FX groups. `~pp` holds the live preview parameters. Starting or stopping changes a generation counter so an earlier asynchronous boot callback cannot start an obsolete preview.

Parameter changes affect the live preview; a render batch uses its own snapshot. The Copy Preview → Render button also translates the preview tempo and seed to the appropriate batch fields. It does not silently start rendering. A normal preview finishes after its duration and tail; explicit Stop frees its owned groups immediately.

## NRT batch

Each job builds a new `Score` with embedded SynthDefs, groups, FX, and note events. Realtime server state is not available to this NRT process. `~noteForStep` shares the seed/step rule with preview; exact RT/NRT PCM parity is not promised.

Jobs run sequentially. Each `recordNRT` callback checks the process result and readable WAV metadata before `/render/jobDone`. Node verifies the output belongs to the current batch, writes a JSON sidecar, and only then counts the pair. `/render/done` must agree with the number of verified pairs. Failures are visible in the final batch result; they are not silently turned into success.

A unique batch directory prevents a repeat render from overwriting an earlier batch. Sidecars include format, tail, effective per-job parameters, and the original batch snapshot. `batch.json` records completed count, failures, stop status, and errors. These checks establish file/job completion; use a PCM analyzer for non-silence, nonfinite values, peaks and clipping before delivering audio.

Stop After Current sets a stop flag. The active job completes and its pair is recorded, then pending jobs are skipped. To interrupt an active NRT process immediately, interrupt the launcher session; a partial output from a terminated job is not a completed pair. Output files from failed or interrupted jobs are diagnostic leftovers, not validated deliverables.

The supervisor requires both Node and SC to stay alive and checks startup through actual HTTP/OSC feedback. It sends termination signals only to process groups it created. A live cleanup failure remains an error; a transient zombie-only group on macOS is distinguished from a running owned process.
