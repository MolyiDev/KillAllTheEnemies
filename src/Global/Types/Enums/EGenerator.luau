-- IdGenerator names. Each is its own id range, so a character id and an enemy id can never collide.
return table.freeze({
	CharacterEntities = "CharacterEntities",
	EnemyEntities = "EnemyEntities",
})
