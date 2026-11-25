local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Butler = require(ReplicatedStorage.Packages.Butler)
local jecs = require(ReplicatedStorage.Packages.jecs)
local TData = require(ReplicatedStorage.Types.TData)

local Components = {
	-- Player / character
	Player = jecs.component() :: jecs.Id<Player>,
	Model = jecs.component() :: jecs.Id<Model>,
	Animator = jecs.component() :: jecs.Id<Animator>,
	Humanoid = jecs.component() :: jecs.Id<Humanoid>,
	HumanoidRootPart = jecs.component() :: jecs.Id<BasePart>,
	-- The network id of a character or an enemy. Characters and enemies live in different worlds and draw
	-- their ids from different generators (EGenerator), so the two ranges never meet.
	InstanceId = jecs.component() :: jecs.Id<number>,
	MaxHealth = jecs.component() :: jecs.Id<number>,
	CurrentHealth = jecs.component() :: jecs.Id<number>,
	-- When a character can next be hurt (TimeCore.GameClock), so a crowd pressed against him lands one blow per
	-- window instead of one per enemy.
	HurtUntil = jecs.component() :: jecs.Id<number>,
	-- When a character was last hurt (TimeCore.GameClock), which holds his regeneration off (GDD 18).
	LastHurtAt = jecs.component() :: jecs.Id<number>,

	-- Enemy, server. Position is the FEET; everything that aims adds AimShape.x on top.
	Position = jecs.component() :: jecs.Id<vector>,
	Velocity = jecs.component() :: jecs.Id<vector>,
	-- External push (knockback, pulls), read by the movement update and owned by whoever applies it.
	Force = jecs.component() :: jecs.Id<vector>,
	Radius = jecs.component() :: jecs.Id<number>,
	HalfExtents = jecs.component() :: jecs.Id<vector>,
	-- (chest height, height, radius) over the feet (EnemiesCore.AimShape). Also on the clients' rows, enemies' and the
	-- range's dummies', which is what WeaponController aims at.
	AimShape = jecs.component() :: jecs.Id<vector>,
	-- TEnemy.AimPieces, on the rows of a body that has them (both sides): what a gun hits in place of AimShape.
	AimPieces = jecs.component() :: jecs.Id<{ TData.TEnemyAimPiece }>,
	Mass = jecs.component() :: jecs.Id<number>,
	-- > 0 winding up an attack, < 0 recovering from one or staggered, 0 free. See enemiesUpdate.
	AttackWindup = jecs.component() :: jecs.Id<number>,
	-- Which of TEnemy.Attacks the current wind-up is, and how many it has started (where the pattern resumes).
	AttackIndex = jecs.component() :: jecs.Id<number>,
	AttackCount = jecs.component() :: jecs.Id<number>,
	Damage = jecs.component() :: jecs.Id<number>,
	MovementSpeed = jecs.component() :: jecs.Id<number>,
	Yaw = jecs.component() :: jecs.Id<number>,
	DataId = jecs.component() :: jecs.Id<number>,
	Data = jecs.component() :: jecs.Id<TData.TEnemy>,
	-- Seconds of spawn immunity left. Removed when it runs out, so the immune set is its own small archetype.
	Immunity = jecs.component() :: jecs.Id<number>,
	-- What every blow on the body is multiplied by while it is set in foam (AbilityService). Removed when it ends.
	Brittle = jecs.component() :: jecs.Id<number>,

	-- Enemy, client
	CFrame = jecs.component() :: jecs.Id<CFrame>,
	Bone = jecs.component() :: jecs.Id<Bone>,

	Cleanup = jecs.component() :: jecs.Id<(entity: jecs.Entity<any>) -> ()>,
	Butler = jecs.component() :: jecs.Id<Butler.Butler>,
}

for key, component in Components :: { [string]: jecs.Entity<any> } do
	jecs.meta(component, jecs.Name, key)
end

return table.freeze(Components)
