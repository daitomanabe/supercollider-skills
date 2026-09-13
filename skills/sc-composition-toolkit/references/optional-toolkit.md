# Optional integration with an existing composition toolkit

Some projects supply an independent toolkit containing `init.scd`, `lib/06_render.scd`, `docs/CATALOG.md`, and `~renderExample`. This skill does not install or redistribute that repository, its sample library, plugins, or collected third-party code. Use this integration only when that checkout is already available and authorized; resolve its root from the project or `SC_TOOLKIT_ROOT` and read its current README and renderer before using the API.

## Current API shape

Load `init.scd`; use `~prepare.()` for definition loading without realtime boot. `~find.("pad")` and `~info.(instrument)` discover the available catalog instead of assuming a fixed count or version. `~pb` wires patterns to toolkit buses/groups, while `~pbs` and `~pbg` handle loaded sample and granular instruments. Load only the samples actually used, from configured paths.

A shared piece uses an event containing `name`, `bpm`, `bars`, `tail`, `numOut`, a `pattern` function, and an optional `fx` function. `~renderExample.(~example, outputDirectory)` produces NRT output; `~playExample` is the realtime path after toolkit server setup.

The render context exposes `send`, `insert`, `master`, `spatBus`, `scheduleMessage`, `lfo`, and `map`. For example:

```supercollider
fx: { |ctx|
    ctx.insert(\tiltEQ, [\tilt, 0], 5004);
    ctx.scheduleMessage(2, [\n_set, 5004, \tilt, 0.5]);
    ctx.master;
}
```

Use `ctx.scheduleMessage(seconds, message)`. Calling `ctx.at(...)` dispatches the built-in `Event.at` lookup and does not invoke the stored scheduling function. Some versions retain `ctx[\at].value(ctx, seconds, message)` as a compatibility alias; new code should use the named method. Recheck this against the supplied checkout because it is a project API.

Toolkit routing commonly uses a mix bus with serial inserts and a master, plus parallel reverb/delay sends. Multichannel contexts may replace the stereo master with an N-channel limiter. Read that checkout's routing and actual SynthDef arguments before editing them. Follow its RT logical-to-real node-ID behavior when scheduling automation.

The current renderer returns `[path, peakDb]`. An optional `analyzePeak: false` can return `nil` for peak after structural checks; this means peak and silence remain unmeasured. Run a streaming content check before reporting verified audio. Do not infer clipping or non-silence from a nil value.

## Change scope

Compile and short-render the affected SynthDef or example. Regenerate its catalog when public arguments change. Run broad checks when loading, shared buses/groups, or global rendering behavior changes. Keep generated harvests separate from authored code and preserve each dependency's license; copying third-party code into an authored library does not change its license. Paid source generation, dependency registration, and publication remain separate actions governed by the user's request.
