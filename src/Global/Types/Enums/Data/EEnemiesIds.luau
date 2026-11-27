-- Data ids for enemies. Sent on the wire as a u16 (blink/Types/DataId.blink), so keep them small and never reuse one.
-- Retired: 100 (the Zombie King).
return table.freeze({
	Basic = 1,
	Fast = 2,
	Heavy = 3,
	Exploding = 4,
	Slammer = 5,
	FossilGuard = 6,
	EggSac = 7,
	Spiderling = 8,
	TRex = 101,
	GiantSpider = 102,
})
