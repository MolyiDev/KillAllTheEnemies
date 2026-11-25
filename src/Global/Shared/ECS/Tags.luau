local ReplicatedStorage = game:GetService("ReplicatedStorage")
local jecs = require(ReplicatedStorage.Packages.jecs)

local Tags = {
	-- Character
	Alive = jecs.tag(),
	Character = jecs.tag(),
	Player = jecs.tag(),
	-- Picking a run upgrade, or still watching the card taken (UpgradesService): no blow lands on the character.
	Picking = jecs.tag(),

	-- Enemy
	Enemy = jecs.tag(),
	-- A boss (TEnemy.IsBoss): never staggered, has the round's health bar.
	Boss = jecs.tag(),
	-- A boss under the floor (its dive, BossService): out of the movement update and the spatial hash, so nothing
	-- moves it, streams it or hits it.
	Submerged = jecs.tag(),
	-- A boss behind its guards' shield (BossService): every blow is the shield's (EnemiesService).
	Shielded = jecs.tag(),
	-- A boss going for a decoy (BossService): the only kind of boss the movement update walks to a lure.
	Baited = jecs.tag(),
}

for key, component in Tags :: { [string]: jecs.Entity<any> } do
	jecs.meta(component, jecs.Name, key)
end

return Tags
