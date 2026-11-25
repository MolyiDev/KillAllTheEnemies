-- Data ids for enemies. Sent on the wire as a u16 (blink/Types/DataId.blink), so keep them small and never reuse one.
-- Retired: 100 (the Zombie King).
return table.freeze({
	Basic = 1,
	Fast = 2,
	Heavy = 3,
	Exploding = 4,
	Slammer = 5,
	FossilGuard = 6,
	TRex = 101,
})
