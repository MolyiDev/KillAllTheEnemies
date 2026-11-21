# Methodology, and every trap hit along the way

Read this before trusting or extending any number in this folder. Several of the traps below produced
*confidently wrong* results that only reversed after a control was added.

## Environment

- Roblox Studio, `Game` place, F5 playtest, driven over the Tripwire MCP plugin.
- Frame rate cap **240 FPS** (4.167ms/frame). Confirmed by an empty-scene baseline reading 239.0.
- Viewport 1918x1080. **Print `Camera.ViewportSize` in every run rather than assuming this.** It was assumed for
  runs 01-19 and never checked; when run 20 finally printed it, it read 1002x238 for the first four rows and
  1340x546 for the rest, because the Studio window was resized mid-run. CPU-side costs are unaffected, but any
  claim about fill rate or screen coverage is only as good as the viewport it was measured in.
- **Re-assert the camera before every sample, not once at startup.** A respawn resets `CameraType` to `Custom`
  and hands the camera back to the default camera script, which then follows the character to wherever it was
  parked and points at empty sky. The harness happily keeps measuring: run 20's first attempt produced a clean
  looking row with a *better* frame time, and the only tell was `vis=0/2400`.
- `Workspace` is essentially empty in this place (no map), so the scene under test is the only render load.
- `StarterPlayer.StarterPlayerScripts.Client` and `ServerScriptService.Server` are **disabled** for the
  duration of every run, so the game's own controllers do not spawn or render anything. **Both are re-enabled
  afterwards.** Note that disabling `Client` does not remove its ModuleScript children, so
  `require(PlayerScripts.Client.Utils.BugGait)` still works while it is disabled.
- **`ReplicatedFirst.FirstShared.LoadingScreen` must be disabled as well.** It holds a full-screen opaque black
  `ScreenGui` until `LoadingState.WaitForTerrain()` and `WaitForGameStart()` both return, and with `Server`
  disabled neither ever does - so the screen stays black for the whole run. The 3D scene still renders behind it
  and the numbers are unaffected, but nothing is visible, which makes every visual check impossible and hides a
  scene that is silently wrong. Re-enable it afterwards along with the other two.

## The harness

Every benchmark is a LocalScript in `StarterPlayerScripts` that:

1. Anchors the character and parks it at `(0, 500, 0)`, sets the camera to `Scriptable`, FOV 70, positioned at
   `(0, 0, 155)` looking at the origin.
2. Lays entities out on a deterministic grid (260 x 140 x 40 studs) with a per-entity phase offset, so every
   variant gets a byte-identical layout. **No RNG anywhere** - positions come from `(i * 7919) % 1000` style
   hashes so runs are comparable.
3. Moves each entity on a small orbit every frame from `RunService.PreRender`, so the movement cost is real and
   identical across variants.
4. Records per-frame `dt`, and the wall-clock cost of its own update callback.
5. Builds detached and parents to Workspace in one write, then waits out a settle window before sampling.

### Isolating engine time from script time

    engine time for frame N = (duration of the frame that CONTAINED update N) - (Luau cost of update N)
                            = frameTimes[N + 1] - updateTimes[N]

**`PreRender`'s `dt` is the time since the last render**, so work done during frame N is billed to the `dt`
reported at frame **N+1**. Reading it off the same index credits the cost to the frame *before* the one that
caused it. Every change-vs-quiet comparison in this folder is shifted by one frame for this reason.

### Change frames vs quiet frames

For anything that might trigger a rebuild, the update writes the property on **one frame in N** (a "burst") and
the analysis splits frames into those that followed a change and those that did not. A rebuild shows up as a
spike on exactly the changed frames and nowhere else. This is far more sensitive than comparing averages, and it
is self-controlled: same scene, same count, same machine state, only the write differs.

---

## Traps

### 1. Studio throttles to 60 FPS when unfocused

The very first run produced a baseline of **59.6 FPS** and a wall of identical 16.67ms medians. That was not the
scene - it was Studio rendering at 60 because its window did not have focus. Mid-run the numbers jumped to 240
when focus returned, silently invalidating everything measured before it.

**Mitigation:** every later script connects `UserInputService.WindowFocusReleased` and flags any sample where
focus was lost, printing `*** FOCUS LOST ***`. Keep Studio focused and untouched for the whole run.

**The marker is not enough, and doc [16](16-shell-ripple-mechanism.md) got caught by this twice.**
`WindowFocusReleased` only fires if focus was *held and then lost*, so a run that never had focus in the
first place prints no marker at all and looks clean. **The tell is `fps=60.0` and a wall of 16.6ms
medians** - check that on every row before reading anything else. The second instance was worse: the run
was clean until the operator was asked a question mid-pass and clicked away to answer it. Do not talk to
anyone, in any window, while a pass is running.

### 2. The frame cap flattens everything

At 240 FPS a frame with spare time reads 4.167ms **no matter what happened in it**. Any variant that is not
already over budget reads identically, and engine-time isolation degenerates into measuring the script cost
inverted. Counts of 600 and 1200 were entirely useless for this reason - all variants pinned at the cap.

**Mitigation:** report `atCap%` on every row and only trust rows where it is low. Push the entity count until
the scene is genuinely over budget. A failed attempt at this is trap 3.

### 3. Static ballast does not clear the cap

An attempt to clear the cap by adding 1200 static (anchored, never-written) slug rigs alongside the scene under
test failed: `atCap` stayed at 63-71%. Static parts batch too well to add meaningful load.

**What worked instead:** raising the count of the thing under test, within its stable range (trap 4).

### 4. Raising the count too far falls off a different cliff

7200 skeletons produced 193ms **engine** medians - a regime where nothing can be measured, since the scene is
thrashing for unrelated reasons. The usable window for skinned meshes is roughly 2400-4800.

### 4b. A fixed settle window is not long enough, and this one bit hard

Every count in the ceiling sweep needed **4.3-6.2 seconds** for frame times to converge, *including n=2400*. The
runs in this folder allowed 1.5-2s. At 7200 skeletons - roughly ten seconds of build CPU - that produced a
**164ms median that was really the tail of the build**, and a wrong conclusion about where skinned meshes stop
working. See [09-skinned-ceiling.md](09-skinned-ceiling.md).

**Mitigation:** sample the frame time in 1s windows and only begin measuring once two consecutive windows agree
within 10%, then **report how long that took** so a suspiciously long settle is visible. `scripts/11-ceiling`
implements this; prefer it for any run where absolute numbers matter.

What the short settle does and does not invalidate elsewhere in this folder:

- **Medians and p95 still hold** for comparisons where variants were measured against their own control in the
  same run - both sides had the same too-short settle, so the *relative* result stands.
- **`worst`-frame columns are suspect throughout**, because a short settle leaves build tail in the sample. That
  is why [04](04-specialmesh-vs-meshpart.md) reports a 14ms worst frame in one pass and 900ms in another for the
  same variant.

### 5. Ordering and session drift

Three mesh variants once measured 46.8 / 4.0 / 3.2 FPS - a perfect monotonic decline that tracked **run order**,
not the variable under test. Building and destroying thousands of instances per run can degrade the session.

**Mitigation:** a **sentinel** (an unchanging reference variant) runs between every variant, and a second pass
runs every variant in **reverse order**. If the sentinel drifts, nothing in the run means anything. In the final
isolation run the sentinel held 6.00-6.57ms across 14 interleaved samples, including immediately after every
catastrophic variant - which is what makes those results trustworthy.

### 6. Mean is the wrong statistic when rebuilds are involved

Mesh variants routinely showed `mean=5.22ms` next to `med=4.09ms` - the mean dragged by rebuild hitches leaking
past the settle window. Elsewhere a quiet-frame mean of 5.02ms was inflated by a single 171ms outlier.

**Use the median** for central tendency, and report p95 / max separately for the tail. Both matter and they say
different things: `Part+SpecialMesh` had median 10.4ms and p95 12.0ms (healthy), while `MeshPart on Motor6D` had
median 8.87ms and p95 **445ms** (broken). The median alone would have called them similar.

### 7. `:Destroy()` returns before the work is done

Timing the `Destroy()` call alone gets the answer backwards. At 2400 entities the slug rig's call was *faster*
than the skeleton's (141ms vs 241ms) while its deferred cleanup cost **2562ms of excess with a 2322ms worst
frame**, against 666ms/522ms for skeletons.

**Mitigation:** measure the call *and* the frames that follow it until they settle back to a baseline captured
beforehand, reported as excess-over-baseline and worst-single-frame.

### 8. Small sample counts when each sample is expensive

The transparency stall rows caught only n=3-5 change events, precisely *because* each event ate ~1s of a 6s
window. The effect reproduced across four independent runs so its existence is not in doubt, but the exact
magnitudes there are soft. Always print the sample count.

### 9. Verify the geometry is actually on screen

A benchmark where half the entities were behind the camera would be measuring the update loop and calling it a
frame time. Every run counts entities inside the frustum via `Camera:WorldToViewportPoint` and prints `vis=n/n`.
There is also a **camera-away control**: turning the camera off the cluster must recover frame time, otherwise
the geometry is not being drawn where the layout says it is.

Caveat: for the bone variant there is no readable moved position (the MeshPart stays at the origin), so
visibility is counted from the intended layout slots. For Motor6D variants `Part1.Position` does track the
joint's Transform, which is how that was verified directly.

### 10. Things a LocalScript cannot do

- **`CollisionFidelity` is not writable** - "lacking capability Plugin". This killed one run outright and left
  the leading hypothesis for two separate findings untested.
- **`Model.Scale` does not exist** in this engine version. The API is `Model:ScaleTo(n)` / `Model:GetScale()`.
  Reading `.Scale` throws and kills the thread.

An unhandled error inside the `task.spawn` driver **terminates the whole run silently** - later variants simply
never print. Wrap anything uncertain in `pcall`, and probe capability up front.

### 11. Script timeout on large unbroken build loops

Building 2400 slug rigs in one loop hit *"Script timeout: exhausted allowed execution time"*.

**Mitigation:** build in chunks of ~200 with a `task.wait()` between them. Where build cost is itself the
measurement, accumulate only the `os.clock` time spent *inside* the chunks so the yields are not counted.

---

## Running these

1. Copy a script from `scripts/` into `StarterPlayer.StarterPlayerScripts` as a `LocalScript`.
2. Disable `StarterPlayerScripts.Client` and `ServerScriptService.Server`.
3. Press F5. **Keep Studio focused and do not touch it.** Watch Output for `[FOCUS LOST]` markers.
4. When `===== done =====` prints, stop, delete the script, and re-enable `Client` and `Server`.

Each script prints a self-describing table to Output. Counts and sample windows are constants at the top.
