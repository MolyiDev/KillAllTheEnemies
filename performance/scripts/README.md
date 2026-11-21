# Benchmark scripts

Archival copies, **as run**, of every LocalScript that produced the numbers in this folder. They are kept
verbatim rather than refactored into a shared harness, so the code that produced each documented result is
exactly what is here.

## How to run one

1. Copy the file into `StarterPlayer.StarterPlayerScripts` as a `LocalScript`.
2. Disable `StarterPlayer.StarterPlayerScripts.Client` and `ServerScriptService.Server`.
3. Press F5. **Keep Studio focused and untouched** - it throttles to 60 FPS when unfocused, which silently
   floors every number. Watch Output for `*** FOCUS LOST ***`.
4. Wait for `===== done =====`, then stop, delete the script, and re-enable `Client` and `Server`.

Counts and sample windows are constants at the top of each file.

## Index

| Script | Produces | Doc |
| --- | --- | --- |
| `01-render-bench.client.luau` | Billboards vs Motor6D + Part, raw write costs | [01](../01-billboards-vs-motor6d.md) |
| `02-bone-bench.client.luau` | `Bone.Transform` vs `Motor6D.Transform`, camera-away control | [02](../02-bone-vs-motor6d.md) |
| `03-mesh-isolation.client.luau` | The MeshPart cliff isolated (bone / shadow / joint), sentinels + reversed pass | [03](../03-meshpart-on-motor6d-cliff.md) |
| `04-meshkind.client.luau` | Part+SpecialMesh vs MeshPart, one part vs one part | [04](../04-specialmesh-vs-meshpart.md) |
| `05-anim.client.luau` | Real `BugGait` vs per-entity `AnimationTrack` | [05](../05-animation.md) |
| `06-tint.client.luau` | `SurfaceAppearance.Color` per-frame and burst | [06](../06-color-transparency-fastcluster.md) |
| `07-cluster.client.luau` | `Part.Transparency` stall reproduction on Part rigs. **This is the Roblox repro case.** | [06](../06-color-transparency-fastcluster.md) |
| `08-skinned-props.client.luau` | Colour / transparency on the skinned path | [06](../06-color-transparency-fastcluster.md) |
| `09-stretch.client.luau` | `MeshPart.Size` vs `SpecialMesh.Scale`+`Offset` (the vacuum stretch) | [07](../07-scale-size-and-the-vacuum-stretch.md) |
| `10-scale-lifecycle.client.luau` | `Model:ScaleTo`, and spawn/despawn cost | [07](../07-scale-size-and-the-vacuum-stretch.md), [08](../08-spawn-despawn.md) |
| `11-ceiling.client.luau` | Skinned-mesh ceiling sweep. **Has the adaptive settle - copy this pattern for any run where absolute numbers matter.** | [09](../09-skinned-ceiling.md) |
| `14-flash-calibrate.client.luau` | Slime count sweep to clear the 240fps cap, capability probes, raw write cost of every flash mechanism | [13](../13-damage-flash-tint-vs-highlight.md) |
| `15-flash-bench.client.luau` | Tint vs pooled-reparent vs pooled-Adornee vs pre-parented `.Enabled`, burst analysis | [13](../13-damage-flash-tint-vs-highlight.md) |
| `16-flash-visual-and-cap.client.luau` | Does each method look like a flash, and how many highlights actually render past the cap. Stage-driven by `workspace:SetAttribute("FlashProbeStage", n)` | [13](../13-damage-flash-tint-vs-highlight.md) |
| `17-flash-mechanism.client.luau` | Is the cost per (highlight, adornee) pair? Cold vs warm bursts, fixed vs rotating pairing, camera away | [13](../13-damage-flash-tint-vs-highlight.md) |
| `18-flash-textured.client.luau` | Flashing an enemy whose texture already needs a white tint: detaching the `SurfaceAppearance` vs a Neon material swap | [13](../13-damage-flash-tint-vs-highlight.md) |
| `19-flash-colormap.client.luau` | Blanking `SurfaceAppearance.ColorMap` (not scriptable), the K=1 rebind cost, and a close-up visual hold | [13](../13-damage-flash-tint-vs-highlight.md) |
| `20-flash-filltransparency.client.luau` | `FillTransparency` CROSS vs WITHIN on a bound Highlight. **Re-asserts the camera per sample and prints the viewport - copy this.** | [13](../13-damage-flash-tint-vs-highlight.md) |
| `21-spawn-with-highlight.client.luau` | Spawn / despawn cost by construction order, with the per-spawn Luau split and an M sweep | [14](../14-enemy-spawn-with-highlight.md) |
| `22-highlight-cap-parentless.client.luau` | Does a Highlight whose Parent is never set take one of the 255 slots? **Visual, needs a human watching.** | [13](../13-damage-flash-tint-vs-highlight.md) |
| `23-highlight-cap-detached-models.client.luau` | Same question for a Highlight inside a never-parented Model, which is how enemy templates would hold it | [13](../13-damage-flash-tint-vs-highlight.md) |
| `24-luau-idioms.client.luau` + `.suites.luau` | Pass 1: iteration, appending, object construction, closures, builtins, method dispatch, field reads, vector math | [15](../15-luau-idioms.md) |
| `25-luau-idioms-pass2.client.luau` + `.suites.luau` | Pass 2: the rows pass 1 could not resolve, plus the **inline probe** that shows `--!optimize 2` is a no-op | [15](../15-luau-idioms.md) |
| `26-luau-idioms-pass3.client.luau` + `.suites.luau` + `.helpers.luau` | Pass 3: cross-module vs in-module calls, and table reuse. **The largest effect in the whole set is here** | [15](../15-luau-idioms.md) |
| `27-shell-ripple.client.luau` | Panel lattice vs EditableMesh ripple, four resolutions, one shell and eight | [16](../16-shell-ripple-mechanism.md) |
| `28-shell-ripple-look.client.luau` | The same eight combinations staged as the game stages them (night, crystal, ground) for a human to judge. **Visual, needs a human watching.** | [16](../16-shell-ripple-mechanism.md) |

## Running 24 to 26

These three are pure CPU, so they do not need a scene, a settle window, or the camera. They do need their
suite modules parented as children, one per compilation mode, with the headers prepended:

| Child | Header to prepend |
| --- | --- |
| `SuitesO1` | none |
| `SuitesO2` | `--!optimize 2` |
| `SuitesNative` | `--!native` and `--!optimize 2` |

Keep the bodies byte-identical or the mode comparison means nothing. Script 26 also needs a `Helpers`
ModuleScript sibling, from `26-luau-idioms-pass3.helpers.luau`, so the cross-module call crosses a real
module boundary.

## Shared conventions

- Deterministic layout from integer hashes - **no RNG**, so every variant gets a byte-identical grid.
- `RunService.PreRender` drives updates and records `dt` plus the update's own Luau cost.
- Engine time is `frameTimes[N+1] - updateTimes[N]` (PreRender's `dt` bills frame N's work to N+1).
- `atCap%` counts frames under 4.35ms - a high value means the 240 cap is flattening the result.
- Sentinels and reversed passes appear in the scripts that need drift protection.

See [../METHODOLOGY.md](../METHODOLOGY.md) for the traps these conventions exist to avoid.
