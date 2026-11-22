-- An effect template as it is thrown: one Attachment of named ParticleEmitters, cloned under Workspace.Terrain (where
-- an attachment's CFrame is its world CFrame), moved to each burst and emitted there. An emitter has no burst count
-- of its own, so the caller says how many each layer throws. Every copy runs on one time scale (SetTimeScale), so a
-- stopped match holds what is already in the air.
local Workspace = game:GetService("Workspace")

local burstLayers = {}

export type TLayers = { Attachment: Attachment, Emitters: { [string]: ParticleEmitter } }

local random = Random.new()
local made: { TLayers } = {}
-- Each emitter's own TimeScale, as authored, which the match's is laid over.
local authoredScales: { [ParticleEmitter]: number } = {}
local timeScale = 1

-- A copy of `template` ready to throw, or nil when it is not an Attachment (the kit is not in the place).
function burstLayers.Clone(template: Instance?): TLayers?
	if not template or not template:IsA("Attachment") then return nil end
	local attachment = template:Clone()
	local emitters = {}
	for _, child in attachment:GetChildren() do
		if not child:IsA("ParticleEmitter") then continue end
		emitters[child.Name] = child
		authoredScales[child] = child.TimeScale
		child.TimeScale = child.TimeScale * timeScale
	end

	attachment.Parent = Workspace.Terrain
	local layers = { Attachment = attachment, Emitters = emitters }
	made[#made + 1] = layers
	return layers
end

-- Runs every copy's particles at `scale` (the match's, TimeCore), 0 holding them where they are. An emitter runs no
-- faster than 1.
function burstLayers.SetTimeScale(scale: number)
	local clamped = math.clamp(scale, 0, 1)
	if clamped == timeScale then return end
	timeScale = clamped
	for _, layers in made do
		for _, emitter in layers.Emitters do
			emitter.TimeScale = authoredScales[emitter] * timeScale
		end
	end
end

function burstLayers.Emit(layers: TLayers, layer: string, count: number)
	local emitter = layers.Emitters[layer]
	if emitter and count > 0 then emitter:Emit(count) end
end

-- A whole number out of `range`, so no two bursts match.
function burstLayers.Roll(range: NumberRange): number
	return random:NextInteger(range.Min, range.Max)
end

function burstLayers.Between(range: NumberRange): number
	return random:NextNumber(range.Min, range.Max)
end

return burstLayers
