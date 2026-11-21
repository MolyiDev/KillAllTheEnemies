# Spawn and despawn cost: skinned mesh vs Part rig

**Question:** the pooling decision - how much does it cost to bring an entity into the world and take it out?

**Answer:** skinned meshes are ~2.8x cheaper to churn. More importantly, **neither is remotely affordable
unpooled.**

Script: [`scripts/10-scale-lifecycle.client.luau`](scripts/10-scale-lifecycle.client.luau)

## Method note

`:Destroy()` **returns before the work is done**, so timing the call alone gets the answer backwards. Each phase
is measured twice: the wall clock of the call itself, and the frames that follow until they settle back to a
baseline captured beforehand - reported as excess milliseconds over baseline and as the worst single frame.

Builds are chunked (200 per chunk with a `task.wait()` between) because an unbroken 2400-rig build loop hits
Roblox's script timeout. Only the time spent *inside* the chunks is accumulated, so the yields are not counted.

## Results

| | spawn CPU | per entity | worst frame | spawn excess | destroy call | destroy worst | destroy excess |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Skeleton** n=1200 | 1995ms | **1662us** | 441ms | 3997ms | 117ms | 130ms | 273ms |
| **Slug** n=1200 | 5479ms | **4566us** | 1944ms | 7278ms | 66ms | 89ms | 265ms |
| **Skeleton** n=2400 | 3304ms | **1377us** | 916ms | 5585ms | 241ms | 522ms | 666ms |
| **Slug** n=2400 | 9173ms | **3822us** | 3987ms | 10428ms | 141ms | **2322ms** | **2562ms** |

Baseline frame time was 4.00-4.02ms in every case.

## Interpretation

**Spawn: skinned wins ~2.8x per entity** (1.4-1.7ms vs 3.8-4.6ms).

**Destroy: the tail is what matters.** At 2400 the slug's `Destroy()` *call* was the faster of the two (141ms vs
241ms) but its deferred cleanup cost **2562ms of excess with a 2322ms worst frame**, against 666ms/522ms for the
skeletons. Timing the call alone would have told you the opposite of the truth.

**Neither is affordable unpooled.** One skeleton costs ~1.4ms to spawn - a third of a 240 FPS frame for a single
bug; one slug rig ~3.8ms, most of a whole frame. `ObjectPooler` is not an optimisation here, it is a
requirement, and the `reserve` / `grow` numbers in `getPool` are doing real work.

## Caveat on the ratio

The builders configure each clone (`Anchored`, `CanCollide`, `CanQuery`, `CanTouch`, plus a `GetDescendants`
walk for the slug), which a pooled pre-configured template would not repeat. That inflates the slug side
specifically.

The durable part is the **instance count** - 12 instances per slug against 3 per skeleton - so pooling narrows
the gap but does not invert it.
