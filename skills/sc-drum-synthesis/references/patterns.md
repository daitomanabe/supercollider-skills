# Drum patterns and reproducibility

## Time and event representation

For a 4/4 sixteenth-note grid, each bar has 16 steps and a step lasts `60 / bpm / 4` seconds. A different meter or subdivision needs an explicit grid; the 4/4 formula does not cover 12/8 or polymeter automatically.

Use one documented event shape across generation and rendering, for example `[timeSeconds, instrument, velocity, pan, seed]`. Keep parameter defaults and valid ranges together when the same generator feeds a UI, OSC bridge, and NRT score.

`durationSeconds = bars * beatsPerBar * 60 / bpm`. When converting events into a `Score`, use a one-beat-per-second clock or explicitly convert for its tempo. Do not multiply already-second-based event times by tempo twice.

## Density and complexity

- **Density (0–1):** how many optional hits occur.
- **Complexity (0–1):** syncopation, ghosts, rolls, and variation independent of basic density.
- Keep structural anchors explicit when they define the requested groove; avoid making every beat probabilistic by accident.

For example, a hat probability of `0.4 + density * 0.6` yields a 40–100% chance on candidate positions. A high complexity setting can add quiet snares at offbeats while maintaining the same total velocity budget. Rolls require substep event times, rather than stacking all hits at the parent step.

Set the language random seed before generating a sequence. For repeatable noise/resonator renders, also seed server-side random generators, e.g. `RandSeed.ir(1, seed)` in each SynthDef. A Python-seeded event list alone does not seed SuperCollider's noise UGens. Reproducibility checks should specify the SC version, plugin set, platform, sample rate, and block size; identical output across different versions is not promised.

Python generation can be useful when a project already owns its sequencing/data layer there. It is optional: sclang patterns or direct Score construction can also be reproducible. Validate instrument names against known definitions, finite parameter values, and event time ranges before serializing. Do not insert unchecked strings into executable `.scd` source.

## Groove sketches

Positions below are zero-based sixteenth-note indices for one 4/4 bar. They are illustrative seeds for variation, not authoritative transcriptions or sufficient definitions of a genre.

| Sketch | Kick | Snare/clap | Hat direction |
|---|---|---|---|
| Straight backbeat | 0, 8 | 4, 12 | Eighth notes |
| DnB | 0, 6, 10 | 4, 12, quiet ghosts | Active subdivisions |
| Hip-hop | 0, 5, 8, 13 | 4, 12 | Eighth notes and ghosts |
| Trap | 0, 3, 8, 11 | 4, 12 or chosen half-time backbeat | Rolls as substeps |
| UK garage | 0, 7, 10 | 4, 12 | Shuffle candidate positions 0, 3, 4, 7, 8, 11, 12, 15 |
| Dubstep / half-time | 0 | 8 | Sparse texture and optional rolls |
| House | 0, 4, 8, 12 | 4, 12 | Offbeats 2, 6, 10, 14 |
| Jungle | 0, 5, 10 | 4, 12, ghosts | Broken, busy subdivisions |
| Dembow-inspired | 0, 3, 8, 11 | 4, 7, 12, 15 | Eighth-note framework |
| Footwork | 0, 3, 6, 10, 13 | 4, 12 | Sixteenths with accents |
| Afrobeat-inspired | 0, 6, 10 | 4, 12, secondary rim | Interlocking voices; choose actual meter explicitly |
| Electro | 0, 6, 8, 14 | 4, 12 | Even subdivisions |
| Breakbeat | 0, 1, 8, 9 | 4, 12 | Varied subdivisions |

Swing affects timing, not just the selected steps. Apply velocity and microtiming deliberately and keep the bar duration unchanged when loop alignment matters.

## Fills

A useful restrained strategy adds snares to the last bar of a four-bar phrase while retaining the kick and hat framework. Build a crescendo and increase subdivisions toward the phrase boundary. This is one strategy; replacing or dropping kicks/hats can be appropriate for a break or a stronger fill.

Choose a single fill timbre per phrase when timbral continuity is useful. Avoid unintended simultaneous duplicates when a normal snare and fill snare share the same position. Place a crash on the next downbeat or before the boundary according to musical intent; the last sixteenth and the next downbeat are different gestures.

For fixed-length loops, render enough decay and then choose whether to crop, fade, or wrap the tail. Do not silently truncate an audible crash to force a precise file length.
