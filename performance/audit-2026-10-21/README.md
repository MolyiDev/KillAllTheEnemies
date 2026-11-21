# Enemy audit artifacts

Read [REPORT.md](REPORT.md) first. Production scripts are unchanged. These are archival experiments, not drop-in replacements.

## Results

- `game-run-1.json` / `.parsed.json`: actual Survivors F5, current parallel movement versus direct serial movement, normal animation distance, elevated camera. Exclude 500-enemy rows from a matched comparison because normal startup added enemies.
- `game-run-2.json` / `.parsed.json`: actual Survivors F5, current parallel movement versus lifecycle-safe reusable decoder, forced all-enemy animation and exact populations. Includes 16 worker timing summaries for each stage. These are short, sequential A/B comparisons; small differences require replication.
- `engine-run-2.json`: authoritative isolated shared-hash tests in lobby F8. The stable decoder prototype omits lifecycle pruning. `engine-run-1.json` is retained for provenance; its crowded-query layout was wrong and superseded.
- `movement-run.json`: isolated extracted movement in a flat synthetic world; chunks run sequentially. It does not measure actual parallel latency.
- `target-run.json`: isolated nearest-enemy comparison and fixed-step cadence simulation.

The raw `.json` files preserve MCP results; parse the text content block as JSON to get log entries. Some isolated benchmark messages contain a second escaped JSON string. Parsed game files remove that wrapper.

## Probe layout for reproduction in a disposable test copy

Use the correct Survivors place and confirm its place ID. Preserve the original source of every touched module, stop play before editing, and restore/remove all instrumentation afterward. The archived code intentionally suppresses progression/weapons and changes test-only camera/settings behavior; do not install it in a published game.

1. Server probe: a Script in ServerScriptService with a child ModuleScript named `GroundDirect`, using `gameplay-GroundDirect.luau`. Use `gameplay-run1.server.luau` or `gameplay-run2.server.luau` as appropriate.
2. Client probe: a LocalScript in StarterPlayerScripts using the corresponding `gameplay-run*.client.luau`.
3. The actual enemy client controller needs the small timing field/instrumentation archived in `gameplay-instrumented-client.luau`; the ground updater needs the audit serial-mode gate in `gameplay-instrumented-updater.luau`.
4. Run 1 uses the original ground movement and original Work module. Run 2 uses `gameplay-reuse-worker.luau` for `Server.Utils.enemiesUpdateServer` and `gameplay-timed-work.luau` for the ground Actor's Work module.
5. Start F5, allow normal player/map startup, then collect `[BALLARC_GAME_SERVER]`, `[BALLARC_GAME_CLIENT]` and, for run 2, `[BALLARC_WORKER]` output through the final `done` message. The probe runs both variants at 500, 1,500 and 3,000.

The benchmark's `parallel` label means the current algorithm with timing instrumentation. `reuse` keeps the Actors and changes decoder storage. `direct` skips the ground Actor dispatcher and invokes movement synchronously with live hash tables; it is an experiment that performed badly on the actual dense scene.

For isolated movement tests, `GroundCurrent.luau` and `GroundDirect.luau` belong under the movement benchmark Script along with `NearestCharacter`, `EntityPacker` and `ResolveCircleAABB`. These variants intentionally supply synthetic flat terrain, unlike `gameplay-GroundDirect.luau`.

Improve future runs with alternating variant order, repeated controls, adaptive settling, true screen projection/occlusion checks, normal gameplay cameras, mobile devices, multiple clients, mixed archetypes and full combat. See the detailed limitations and acceptance matrix in the report and BeACastleLord's performance/METHODOLOGY.md.
