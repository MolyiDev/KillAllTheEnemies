# Vide migration, 2026-10-30

Ballarc now uses `centau/vide@0.4.1`, installed through Wally. The migration covers shared UI, Lobby,
Survivors, controllers, world-space UI, UI Labs stories, and the held camera prototype. Active source has no
Fluid imports or calls to its private graph. Historical performance logs and UI notes retain their original wording.

## Appearance and behavior

- `Global/Shared/Utils/Vide.luau` configures the package with Roblox instance defaults and depth-first nested
  property application. Vide's defaults and nested-property order otherwise change existing UI. The comparison
  caught the latter changing an ability key hint's ZIndex; the configuration fixes it.
- All 49 springs convert angular speed to Vide's period using `2 * math.pi / speed`, preserving damping.
- The ticket flash retains its previous OKLab color path. Native Vide Color3 springs use RGB instead.
- Pixel bar, card, particle, and gesture tuning remains unchanged. Their existing `pixelMotion` solver is retained.
- An AST comparison found no differences in 22,326 capitalized table-field expressions across source. This
  checks property and component arguments alongside data fields; callbacks, nested tables, and framework
  constructor calls were excluded from this count.

## Performance and ownership

- Removed 275 redundant `derive` wrappers around property and spring bindings. Shared derived computations
  remain cached. This is a code-derived reduction in reactive nodes, not an FPS measurement.
- `UiSpring.luau` uses native Vide springs with translated coordinates. Vide 0.4.1 starts with a zero settling
  reference, so zero targets otherwise receive zero tolerance. In a live probe, an unshifted zero-target spring
  triggered 240 additional downstream effect evaluations during the sampled second after three seconds of
  settling; the translated scalar and Vector3 springs each triggered zero.
- Dynamic list items and rebuilt settings/catalog/profile subtrees explicitly destroy their instances after
  reconciliation. Quest cards retain keyed instance reuse and individually owned public Vide roots.
- Settings subscriptions disconnect on teardown. Simple UI Labs stories destroy their UI on unmount.
- Removed obsolete deferred initialization of pixel components and one redundant settings focus deferral.

## Verification

Both `rojo build game.project.json` and `rojo build lobby.project.json` succeeded. All 1,032 source scripts
compiled at optimization level 2. Selene reports the same 324 baseline diagnostics, with zero additions.
All changed source files pass StyLua. Whole-source `stylua --check src` still reports the same 22 pre-existing
format failures in generated, vendored, and unrelated loading-screen files.

Live Game-place probes compared original Fluid and migrated Vide instances in 18 states:

| UI | Compared states | Result |
| --- | --- | --- |
| Cursor | Hidden, shown | Match |
| Health | Full, damaged and shown | Match |
| Shield | Full, damaged with overshield | Match |
| Abilities | Initial entries, cooldown and stack updates | Match |
| Timer tiles | Initial entry, removed/replaced entry | Match |
| Mobile controls | Initial, split interaction and cooldown | Match |
| Settings | Open, after 20 settings reloads | Match |
| Reward card | Revealed, selected/banish state | Match |
| Upgrade card | Revealed, selected/banish state | Match |

The comparison inspected hierarchy and visual properties, rounding numeric channels to four decimals. Hidden
descendant geometry was excluded. Random reward-card motes were checked as a fixed pool rather than comparing
individual random positions. Settings focus was held neutral so both instances received the same input state.
Adding and removing 100 abilities returned the UI descendant count from 2 to 2 without UI errors.

These checks establish the tested property states, not pixel-by-pixel or frame-by-frame animation identity.
Fluid's spring solver was analytical; Vide's is numerical. The timing parameters are preserved, but exact
transient samples are not guaranteed identical. No total-frame-time or mobile performance improvement is claimed.
The full Lobby place was built and its constants audited, but was not played in Studio.

All temporary baseline modules and probe scripts were removed. The existing Rojo connection was preserved;
the playtests started for this migration were stopped. Local probe code, raw comparison output, and build
artifacts are under `/tmp/ballarc-vide-migration/` for this session.
