# The Core shell's impact ripple: panel lattice vs EditableMesh

Measured **2026-09-05** in the `Game` place, driven over the Tripwire MCP plugin, against the real Core
shell (`AwakeningCore.SHIELD_SIZE`, 10 studs, tumbling on its three authored rates).

**Verdict: EditableMesh vertex displacement, at 10x10.** It is 1.6x cheaper than a panel lattice at that
resolution while moving *more* elements, and it costs 726 fewer Instances. Shipped in
`Client/Utils/ShellMesh.luau`.

Script: [`scripts/27-shell-ripple.client.luau`](scripts/27-shell-ripple.client.luau) for the numbers,
[`scripts/28-shell-ripple-look.client.luau`](scripts/28-shell-ripple-look.client.luau) for the visual
reel.

---

## The question

Roblox has no GPU shaders, so "the whole forcefield reacts outward from the point it was hit" has to be
faked with geometry. Two ways to fake it:

- **Lattice** — the shell stops being one solid Part and becomes N x N flat panels a face, each joined to
  an anchored hub by a `Motor6D`. The tumble is one write to the hub and every panel rides it, so only the
  ripple is per-panel work. Chosen over CFrame writes because docs [01](01-billboards-vs-motor6d.md) and
  [02](02-bone-vs-motor6d.md) put `Motor6D.Transform` at 86ns.
- **Editable** — the shell is one `MeshPart` whose geometry is a subdivided cube in an `EditableMesh`, and
  the ripple is real vertex displacement.

Both ran the identical ripple, from identical hashed hit points, with the outward direction hoisted out of
the frame loop on both sides.

## The numbers

One shell, which is the only case that ships. 240 FPS cap, Studio focused.

| Resolution | Lattice | | EditableMesh | | Lattice cost |
| --- | --- | --- | --- | --- | --- |
| | elements | script | elements | script | |
| 6x6 | 216 panels | **92us** | 294 verts | **65us** | 1.4x |
| 8x8 | 384 panels | **151us** | 486 verts | **101us** | 1.5x |
| 10x10 | 600 panels | **225us** | 726 verts | **142us** | 1.6x |
| 12x12 | 864 panels | **343us** | 1014 verts | **192us** | 1.8x |

Per element: lattice **375-425ns**, editable **189-220ns**. The mesh is about **twice as cheap per thing
moved**, and wins on the total even though a subdivided cube carries (n+1)^2 vertices a face against n^2
panels.

**Frame time did not separate them at one shell.** Every row read median 4.14-4.24ms against the 4.167ms
cap with 60-75% of frames pinned at it, so the engine-side cost of one shell is below what the harness can
resolve either way (METHODOLOGY trap 2). The whole decision is the script column.

### How resolution scales

Both are linear in element count, and element count is n^2, so cost is n^2 and nothing else.

| Step | Lattice | Editable |
| --- | --- | --- |
| 6x6 -> 8x8 | +64% | +57% |
| 8x8 -> 10x10 | +50% | +40% |
| 10x10 -> 12x12 | +52% | +35% |
| 6x6 -> 12x12 | 3.7x | 3.0x |

10x10 was taken because 12x12 is 40% more vertices for crests already finer than the eye reads at ten
studs, and 8x8 starts showing the facets as facets on a slow ripple.

### Eight shells

Only the lattice survived this, and it is worth recording what it showed: 1728 panels at 6x6 still read
`atCap=76%`, and 4800 panels at 10x10 only reached a 17.26ms median. Panels are cheap on the engine side;
their cost is Luau and Instance count, not draw.

## What EditableMesh actually costs you

These are the reasons the faster option is also the more fragile one, and they are all load-bearing for
any future use:

- **There is a memory budget, and it is not generous.** At 8 shells even 6x6 (294 vertices each) failed
  with `Failed to create empty EditableMesh that was requested due to reaching memory budget limits`. It
  failed *after* earlier meshes had been created and destroyed, so the budget is not reclaimed promptly.
  Reproduced on two independent runs.
- **It fails by returning `nil`, not by throwing.** A `pcall` reports success and the next `AddVertex`
  indexes nil and takes the whole thread with it (METHODOLOGY trap 10 — this killed a run). Check the
  value, never just the pcall.
- **`BatchSetValues` is gated off** in this engine version: the method exists on the class but throws
  `EditableMesh API function not available`. Every vertex goes through `SetPosition`, measured at ~100ns
  raw. The 2x lead exists *despite* having no bulk write.
- **It does not replicate**, so the mesh must be built client-side. Fine here — `CoreController` already
  owns the shell's picture.
- **`MeshPart.MeshContent` holds the EditableMesh by reference** (`Content{SourceType=Object}`, and the
  object compares equal to the one passed in), so edits land live without rebuilding the part. But
  `Size`, `ExtentsSize` and the collision geometry are all baked at `CreateMeshPartAsync` and do **not**
  follow the vertices.

The last point is why `ShellMesh` bakes the shell's opening into the vertex positions instead of writing
`Part.Size`: on a mesh part a `Size` write is a rebuild, where a vertex write is a value the loop is
already making.

## What it costs in the game

Nothing at rest. `ShellMesh.Step` writes vertices only while a ripple is alive or the shell is still
opening, and writes one settling frame after the last ripple dies. So 142us is the price of the half
second after a hit, not a standing cost — which the benchmark, deliberately keeping a ripple in every
sampled frame, does not show.

## Traps hit in this run

Both are already in [METHODOLOGY.md](METHODOLOGY.md); these are fresh instances of them.

1. **Trap 1, twice.** The first pass read `fps=60.0` and a wall of 16.6ms medians because the Studio
   window was not focused. `WindowFocusReleased` does not fire if focus was never held, so the
   `*** FOCUS LOST ***` marker stayed silent — **the tell is `fps=60.0`, not the marker.** The second pass
   was contaminated the same way partway through, by the operator being asked a question mid-run. Do not
   interact with anyone while a pass is running.
2. **A fairness bug in the harness itself.** Pass 1 computed `at.Unit` inside the per-frame loop, a square
   root per element per frame charged to both variants. It was hoisted for pass 2. The ranking is
   unaffected — both sides paid it — but it is why the pass 1 per-element numbers are a ceiling rather
   than the mechanism's own cost.
3. **`get_playtest_output` with a `since` cursor dribbles one row per call.** Call it without the cursor
   to pull the whole buffer.
