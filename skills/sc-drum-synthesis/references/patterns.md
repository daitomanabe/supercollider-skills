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

## Pattern strings

`garage-nrt.scd` writes each voice as one character per sixteenth: `X` accent (1.0), `x` normal (0.78), `o` ghost (0.42), `.` rest, and `2`-`6` for a roll of that many evenly spaced hits inside the step, rising from 0.5 to 0.85. A 16-character string is one bar and a 32-character string two bars; both repeat. A per-bar override replaces one voice for one bar, which is how fills and a bar-1 crash are placed. Velocities get a seeded ±8% jitter.

Swing moves odd sixteenths only: an odd step starts `(swing - 0.5) * 2 * stepDur` late, so 0.5 is straight and 0.62 is the garage shuffle. Rolls inside a swung step move with it.

## Hat choke

A drummer's hi-hat is one instrument: a new closed or open hit cuts the one still ringing. Give each hat node an explicit ID, and at every hat hit send `n_set <previous> gate 0` if the previous hat is still inside its decay. The skill hats close within 15 ms on `gate` 0. For a loop, also choke the last hat of the loop at the time of the first hat plus the loop length, or the folded tail rings over the first bar.

Choke makes the pattern decide how long an open hat sounds. Leave at least two steps after an open hat; a soft closed hat on the next step cuts it to one step. The garage loop drops the closed hat after its bar-2 open hat, so the open hat rings to the next bar.

## UK garage (2-step) in the example

132 BPM, swing 0.62. Kick on 0 and 10 in bar A and on 0, 7, 10, and 13 in bar B. A tight clap and a dry rim together on 4 and 12, with a ghost rim on the last sixteenth of bar B. Closed hats on the off-eighths (2, 6, 10, 14) and the swung sixteenth after each, an open hat on 14 of bar B. Crash on bar 1. Bar 4 adds a soft clap on 14; bar 8 thins the kick and rolls the rim into the next downbeat.

## Fills

A useful restrained strategy adds snares to the last bar of a four-bar phrase while retaining the kick and hat framework. Build a crescendo and increase subdivisions toward the phrase boundary. This is one strategy; replacing or dropping kicks/hats can be appropriate for a break or a stronger fill.

Choose a single fill timbre per phrase when timbral continuity is useful. Avoid unintended simultaneous duplicates when a normal snare and fill snare share the same position. Place a crash on the next downbeat or before the boundary according to musical intent; the last sixteenth and the next downbeat are different gestures.

For fixed-length loops, render enough decay and then choose whether to crop, fade, or wrap the tail. Do not silently truncate an audible crash to force a precise file length.
