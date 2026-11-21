# Excluded candidates

These Luau files are archived experiments, outside every Rojo source mapping. They are not the production implementation.

- `EnemiesController.luau`, `EnemyRigQueue.luau`, `EnemyRetirementQueue.luau`: queued lifecycle / bounded-particle prototype from the earlier pass. Slower full burst attachment and reduced particle density were not approved.
- `EnemiesControllerDetachedPools.luau`: tested idle-model reparenting prototype. Rejected because spawn and removal work increased substantially.
- `CameraController.luau`: archived candidate; its 20 Hz reporting was subsequently approved and is retained in the current production controller.

See `../RESULTS.md` for retained changes, measurements, and exclusions. Do not replace the current controller with a held file; the final cleanup fixes also postdate some of these prototypes.
