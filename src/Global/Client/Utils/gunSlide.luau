-- A gun's slide running back on a shot and home again: the `Slide` Weld buildGunTool leaves on the Handle of a gun
-- whose model has a `Slide` Model. A picture only, written on this client: nothing replicates.
local gunSlide = {}

gunSlide.Tune = table.freeze({
	-- Studs back at the peak, as a share of the slide's length, so it is the same on a scaled copy.
	TRAVEL_SHARE = 0.16,
	-- Back in a blink, home slower: the way out is the hit, the way home is what the eye follows.
	BACK_SECONDS = 0.035,
	HOME_SECONDS = 0.13,
})

local Tune = gunSlide.Tune
local CYCLE_SECONDS = Tune.BACK_SECONDS + Tune.HOME_SECONDS

type TSlide = {
	Weld: Weld,
	-- Read once, when the joint is first moved: a C0 read later may be mid-travel.
	Rest: CFrame,
	Travel: number,
	At: number,
	IsMoving: boolean,
}

local slides: { [Weld]: TSlide } = {}
local moving: { TSlide } = {}

-- How far back the slide is `age` seconds after its shot, 0 to 1: out fast, coasting to rest on the way home.
function gunSlide.Offset(age: number): number
	if age <= 0 or age >= CYCLE_SECONDS then return 0 end
	if age < Tune.BACK_SECONDS then
		local left = 1 - age / Tune.BACK_SECONDS
		return 1 - left * left
	end

	local left = 1 - (age - Tune.BACK_SECONDS) / Tune.HOME_SECONDS
	return left * left
end

-- Studs the slide whose biggest part is `body` runs back.
function gunSlide.Travel(body: BasePart): number
	local size = body.Size
	return math.max(size.X, size.Y, size.Z) * Tune.TRAVEL_SHARE
end

function gunSlide.Kick(tool: Tool)
	local handle = tool:FindFirstChild("Handle")
	local weld = if handle then handle:FindFirstChild("Slide") else nil
	if not weld or not weld:IsA("Weld") then return end

	local slide = slides[weld]
	if not slide then
		local body = weld.Part1
		if not body then return end
		slide = { Weld = weld, Rest = weld.C0, Travel = gunSlide.Travel(body), At = 0, IsMoving = false }
		slides[weld] = slide
		weld.Destroying:Once(function()
			slides[weld] = nil
		end)
	end

	slide.At = os.clock()
	if slide.IsMoving then return end
	slide.IsMoving = true
	moving[#moving + 1] = slide
end

function gunSlide.Step(now: number)
	for index = #moving, 1, -1 do
		local slide = moving[index]
		local offset = gunSlide.Offset(now - slide.At)
		-- The Handle looks out of the barrel, so back is its +Z.
		slide.Weld.C0 = if offset > 0 then CFrame.new(0, 0, slide.Travel * offset) * slide.Rest else slide.Rest
		if offset > 0 or now - slide.At < CYCLE_SECONDS then continue end

		slide.IsMoving = false
		moving[index] = moving[#moving]
		moving[#moving] = nil
	end
end

return gunSlide
