local ReplicatedStorage = game:GetService("ReplicatedStorage")
local jecs = require(ReplicatedStorage.Packages.jecs)

local Tags = {
	-- Character
	Alive = jecs.tag(),
	Character = jecs.tag(),
	Player = jecs.tag(),

	-- Enemy
	Enemy = jecs.tag(),
	-- A boss (TEnemy.IsBoss): never staggered, has the round's health bar.
	Boss = jecs.tag(),
}

for key, component in Tags :: { [string]: jecs.Entity<any> } do
	jecs.meta(component, jecs.Name, key)
end

return Tags
