-- Blows on anything a gun shoots, from whoever draws those bodies: the match's enemies (EnemiesController) and the
-- range's dummies (RangeController). The crosshair's markers and the damage numbers answer them in both places.
-- Ids are a body's own (an enemy's InstanceId, a dummy's index) and an attacker's character InstanceId, 0 for nobody.
-- Required through PlayerScripts by everyone, so all of them meet on one copy of the signals.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Packages.Signal)

return table.freeze({
	-- (bodyId, attackerId, damage, chest, halfWidth?): the body's half width, which its number is thrown within.
	Damaged = Signal.new(),
	-- (bodyId, killerId, damage, isOverkill, chest, halfWidth?)
	Killed = Signal.new(),
})
