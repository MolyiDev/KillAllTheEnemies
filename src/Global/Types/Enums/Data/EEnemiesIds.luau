-- Data ids for enemies. Sent on the wire as a u16 (blink/Types/DataId.blink), so keep them small and never reuse one.
return table.freeze({
	Basic = 1,
	Fast = 2,
	Heavy = 3,
	Exploding = 4,
	Slammer = 5,
	ZombieKing = 100,
})
