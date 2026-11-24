-- The index screen (UIMatt.md, Index): every enemy type by page, each one found shown in its own rig and the rest as
-- silhouettes, and the picked one on a stage with what it does and how many this player has killed. IndexService sends
-- what is found; the lobby's INDEX card opens it. While it is up the world behind is blurred and heard under water.
--
-- A type found in a run and not shown yet is held unknown (Hidden) until its page is on show, then revealed one after
-- another (RevealAt), each with its sound, and the server is told so it is not revealed again. The POTIONS page reads
-- the recipes found off MutationController, which owns Mutation.Sync; a recipe new there wears NEW once its page is on
-- show, and the lab is told it has been seen.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local Ignis = require(ReplicatedStorage.Packages.Ignis)
local vide = require(ReplicatedStorage.Packages.vide)
local NetworkMeta = require(StarterPlayer.StarterPlayerScripts.GlobalClient.NetworkMeta)
-- Through PlayerScripts, the copy that runs: requiring the StarterPlayer one would load a second controller.
local BlurController = require(Players.LocalPlayer.PlayerScripts.GlobalClient.Controllers.BlurController)
local MutationController = require(script.Parent.MutationController)
local DataCore = require(ReplicatedStorage.GlobalShared.Core.DataCore)
local SoundsCore = require(ReplicatedStorage.GlobalShared.Core.SoundsCore)
local Parts = require(script.Parts)
local Screen = require(script.Screen)
local Types = require(script.Types)

local ServerNetworkIndex = NetworkMeta.Server.Index
local ClientNetworkIndex = NetworkMeta.Client.Index
local LocalPlayer = Players.LocalPlayer
local source = vide.source
local create = vide.create
local ENEMIES = DataCore.Enemies.ById

local Tune = table.freeze({
	-- The screen is his 1920 x 1080, fitted inside the viewport whole.
	DESIGN = Vector2.new(1920, 1080),
	-- Above the lobby's HUD, under the settings screen.
	DISPLAY_ORDER = 5,
	-- It is drawn this long after it is shut, for its way out.
	LEAVE_SECONDS = 0.45,
	-- How long the clock keeps ticking after a stamp: the longest gesture is shorter.
	MOTION_SECONDS = 2.2,
	-- A page's reveals start once its cards are dealt, this long after it comes up, one this long after another.
	REVEAL_DELAY = 0.75,
	REVEAL_STAGGER = 0.5,
	-- Each unlock of a page's run sounds this much higher than the one before (about a semitone), as the coins climb,
	-- up to the cap.
	UNLOCK_STEP = 0.06,
	UNLOCK_MAX_STEPS = 8,
})

local IndexController = {}

local firstMonster = Parts.CATEGORIES[1].Enemies[1]
local RECIPES = DataCore.Potions.All

local state: Types.TIndexState = {
	Scale = source(1),
	Now = source(os.clock()),
	IsOpen = source(false),
	ToggledAt = source(-math.huge),
	Category = source(1),
	CategoryAt = source(-math.huge),
	Selected = source(if firstMonster then firstMonster.Id else 0),
	SelectedAt = source(-math.huge),
	Kills = source({} :: { [number]: number }),
	Hidden = source({} :: { [number]: boolean }),
	RevealAt = source({} :: { [number]: number }),
	Unread = source({} :: { [number]: boolean }),
	PokedAt = source(-math.huge),
	SelectedPotion = source(if RECIPES[1] then RECIPES[1].Id else 0),
	Potions = source({} :: { [number]: Types.TFoundPotion }),
	PotionsRevealAt = source({} :: { [number]: number }),
	PotionsUnread = source({} :: { [number]: boolean }),
}

-- os.clock until which Now keeps ticking.
local motionUntil = -math.huge
-- Reveal sounds still to play: each one's moment and its sound.
local dueSounds: { { At: number, Group: string, Name: string, Speed: number? } } = {}

-- Whether the screen is up. Reads a vide source, so a view that calls it follows it.
function IndexController.IsOpen(): boolean
	return state.IsOpen()
end

-- How many types found in runs and recipes found in the lab are still to be shown found: the INDEX card wears the
-- count. Reads vide sources.
function IndexController.NewCount(): number
	local count = 0
	for _ in state.Hidden() do
		count += 1
	end
	for _, found in MutationController.Found() do
		if found.IsNew then
			count += 1
		end
	end

	return count
end

local function stir(seconds: number)
	motionUntil = math.max(motionUntil, os.clock() + seconds)
end

-- Stamps a gesture's start and keeps Now ticking for it. `at` may be a moment still to come.
local function stamp(at: Types.Source<number>, moment: number)
	at(moment)
	motionUntil = math.max(motionUntil, moment + Tune.MOTION_SECONDS)
end

local function isFound(enemyId: number): boolean
	return state.Kills()[enemyId] ~= nil and not state.Hidden()[enemyId]
end

-- The first of a page's enemies still to be shown found, or nil.
local function firstHidden(key: number)
	local hidden = state.Hidden()
	for _, enemy in Parts.CATEGORIES[key].Enemies do
		if hidden[enemy.Id] then return enemy end
	end

	return nil
end

-- Puts `enemyId` on the stage without a sound: a page coming up picks for the hand.
local function choose(enemyId: number)
	if state.Selected() == enemyId then return end
	vide.batch(function()
		state.Selected(enemyId)
		stamp(state.SelectedAt, os.clock())
	end)
end

-- When the page on show's reveals start: once its cards are dealt, or now for one found while it is already up.
local function revealStart(): number
	return math.max(math.max(state.ToggledAt(), state.CategoryAt()) + Tune.REVEAL_DELAY, os.clock())
end

-- Queues the sounds of reveal `order` (from 0) of a run starting at `start`, and returns its moment: its padlock's
-- click, higher for each reveal before it, and `sound` as it comes through.
local function queueReveal(start: number, order: number, sound: string): number
	local at = start + Tune.REVEAL_STAGGER * order
	table.insert(dueSounds, {
		At = at + Parts.Timing.REVEAL_CLICK,
		Group = "UI.Index",
		Name = "Unlock",
		Speed = 1 + Tune.UNLOCK_STEP * math.min(order, Tune.UNLOCK_MAX_STEPS),
	})
	table.insert(dueSounds, { At = at + Parts.REVEAL_LIT, Group = "UI.UpgradePick", Name = sound })

	return at
end

-- Reveals the page on show's hidden discoveries, one after another, and tells the server.
local function revealPage()
	if not state.IsOpen() then return end
	local category = Parts.CATEGORIES[state.Category()]
	local hidden = table.clone(state.Hidden())
	local revealAt = table.clone(state.RevealAt())
	local unread = table.clone(state.Unread())
	local start = revealStart()
	local ids = {}
	local count = 0
	for _, enemy in category.Enemies do
		local id = enemy.Id
		if not hidden[id] then continue end
		revealAt[id] = queueReveal(start, count, if enemy.IsBoss then "RevealLegendary" else "RevealEpic")
		hidden[id] = nil
		unread[id] = true
		count += 1
		ids[count] = id
	end
	if count == 0 then return end

	vide.batch(function()
		state.Hidden(hidden)
		state.RevealAt(revealAt)
		state.Unread(unread)
	end)
	stir(start + Tune.REVEAL_STAGGER * count + Parts.REVEAL_SECONDS + Tune.MOTION_SECONDS - os.clock())
	ClientNetworkIndex.Seen.Fire(ids)
end

-- The first recipe the lab calls new, or nil.
local function firstNewPotion()
	local found = state.Potions()
	for _, recipe in RECIPES do
		local entry = found[recipe.Id]
		if entry and entry.IsNew then return recipe end
	end

	return nil
end

-- Puts `recipeId` on the stage without a sound.
local function choosePotion(recipeId: number)
	if state.SelectedPotion() == recipeId then return end
	vide.batch(function()
		state.SelectedPotion(recipeId)
		stamp(state.SelectedAt, os.clock())
	end)
end

-- With the POTIONS page on show, the recipes the lab calls new are revealed as revealPage reveals enemies, keep NEW on
-- their cards until picked, and the lab is told they have been seen (its Found then calls them not new, and the INDEX
-- card's count drops).
local function revealPotions()
	if not state.IsOpen() or state.Category() ~= Parts.POTIONS then return end
	local found = state.Potions()
	local unread = table.clone(state.PotionsUnread())
	local revealAt = table.clone(state.PotionsRevealAt())
	local start = revealStart()
	local ids = {}
	local count = 0
	for _, recipe in RECIPES do
		local id = recipe.Id
		local entry = found[id]
		if not entry or not entry.IsNew or revealAt[id] then continue end
		revealAt[id] = queueReveal(start, count, "RevealEpic")
		unread[id] = true
		count += 1
		ids[count] = id
	end
	if count == 0 then return end

	vide.batch(function()
		state.PotionsUnread(unread)
		state.PotionsRevealAt(revealAt)
	end)
	stir(start + Tune.REVEAL_STAGGER * count + Parts.REVEAL_SECONDS + Tune.MOTION_SECONDS - os.clock())
	MutationController.MarkSeen(ids)
end

local function pickCategory(key: number)
	if state.Category() == key then return end
	vide.batch(function()
		state.Category(key)
		stamp(state.CategoryAt, os.clock())
		-- A page's words come in again even when its pick is the one already on the stage.
		stamp(state.SelectedAt, os.clock())
		if key == Parts.POTIONS then
			local recipe = firstNewPotion() or RECIPES[1]
			if recipe then choosePotion(recipe.Id) end
			return
		end
		local enemy = firstHidden(key) or Parts.CATEGORIES[key].Enemies[1]
		if enemy then choose(enemy.Id) end
	end)
	revealPage()
	revealPotions()
end

function IndexController.Open()
	if state.IsOpen() then return end
	vide.batch(function()
		state.IsOpen(true)
		stamp(state.ToggledAt, os.clock())
		-- It opens on a page with something to reveal, on the first of them; otherwise where it was left.
		local hasHidden = false
		for key in Parts.CATEGORIES do
			local enemy = firstHidden(key)
			if not enemy then continue end
			state.Category(key)
			state.CategoryAt(os.clock())
			choose(enemy.Id)
			hasHidden = true
			break
		end
		local recipe = if hasHidden then nil else firstNewPotion()
		if recipe then
			state.Category(Parts.POTIONS)
			state.CategoryAt(os.clock())
			choosePotion(recipe.Id)
		end
	end)
	revealPage()
	revealPotions()
	SoundsCore.SetMuffled("Index", true)
	BlurController.SetBlurred("Index", true)
	SoundsCore.PlayUINamed("UI", "MenuIn")
end

function IndexController.Close()
	if not state.IsOpen() then return end
	state.IsOpen(false)
	stamp(state.ToggledAt, os.clock())
	SoundsCore.SetMuffled("Index", false)
	BlurController.SetBlurred("Index", false)
	SoundsCore.PlayUINamed("UI", "MenuOut")
end

-- An enemy's own voice from its sound group, nothing when it has none.
local function voice(enemyId: number, line: "Idle" | "Attack")
	local enemy = ENEMIES[enemyId]
	local sounds = if enemy then enemy.Sounds else nil
	local name = if sounds then sounds[line] else nil
	if sounds and name then SoundsCore.PlayUINamed(sounds.Group, name) end
end

local actions: Types.TIndexActions = {
	Close = IndexController.Close,
	PickCategory = pickCategory,
	-- A found enemy greets the pick in its own voice.
	Select = function(enemyId: number)
		if state.Unread()[enemyId] then
			local unread = table.clone(state.Unread())
			unread[enemyId] = nil
			state.Unread(unread)
		end
		if state.Selected() == enemyId then return end
		choose(enemyId)
		SoundsCore.PlayClick()
		if isFound(enemyId) then voice(enemyId, "Idle") end
	end,
	SelectPotion = function(recipeId: number)
		if state.PotionsUnread()[recipeId] then
			local unread = table.clone(state.PotionsUnread())
			unread[recipeId] = nil
			state.PotionsUnread(unread)
		end
		if state.SelectedPotion() == recipeId then return end
		choosePotion(recipeId)
		SoundsCore.PlayClick()
	end,
	Poke = function()
		stamp(state.PokedAt, os.clock())
		if state.Category() == Parts.POTIONS then
			if Parts.IsPotionShown(state, state.SelectedPotion()) then
				SoundsCore.PlayClick()
			else
				SoundsCore.PlayUINamed("UI.UpgradePick", "Denied")
			end
			return
		end
		local enemyId = state.Selected()
		if isFound(enemyId) then
			voice(enemyId, "Attack")
		else
			SoundsCore.PlayUINamed("UI.UpgradePick", "Denied")
		end
	end,
	Stir = stir,
}

local function updateScale()
	local viewport = Workspace.CurrentCamera.ViewportSize
	state.Scale(math.max(math.min(viewport.Y / Tune.DESIGN.Y, viewport.X / Tune.DESIGN.X), 0.01))
end

-- Plays each reveal's sound on its moment; one whose screen shut before it is dropped.
local function playDueSounds(now: number)
	for index = #dueSounds, 1, -1 do
		local due = dueSounds[index]
		if now < due.At then continue end
		table.remove(dueSounds, index)
		if state.IsOpen() then SoundsCore.PlayUINamed(due.Group, due.Name, due.Speed) end
	end
end

IndexController.OnStart = function()
	vide.mount(function()
		-- The lab's recipes found, copied in so the screen's pieces read only this state. One new while its page is on
		-- show wears NEW at once; that is deferred, as telling the lab writes the Found this effect follows, and vide
		-- refuses a write to a source whose effect is running.
		vide.effect(function()
			local found = MutationController.Found()
			vide.untrack(function()
				state.Potions(found)
				task.defer(revealPotions)
			end)
		end)

		-- Drawn only while it is up or still leaving: shut, the screen costs nothing.
		local isDrawn = vide.derive(function(): boolean
			return state.IsOpen() or state.Now() - state.ToggledAt() < Tune.LEAVE_SECONDS
		end)

		return create("ScreenGui")({
			Name = "Index",
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			DisplayOrder = Tune.DISPLAY_ORDER,
			Enabled = isDrawn,
			-- His 1920 x 1080, scaled whole into the middle of the screen.
			create("Frame")({
				Name = "Root",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(Tune.DESIGN.X, Tune.DESIGN.Y),
				BackgroundTransparency = 1,
				create("UIScale")({ Scale = state.Scale }),
				-- Built only while drawn: shut, its rigs and their clips are gone too.
				vide.show(isDrawn, function()
					local pieces = Screen.Build(state, actions)
					-- Hiding ends the scope but leaves the instances, and an Animator in one would play on.
					vide.cleanup(function()
						for _, piece in pieces do
							piece:Destroy()
						end
					end)
					return pieces
				end),
			}),
		})
	end, LocalPlayer:WaitForChild("PlayerGui"))

	-- Now is written only while something moves, so a screen at rest, open or shut, redraws nothing.
	RunService.PreRender:Connect(function()
		local now = os.clock()
		if now < motionUntil then state.Now(now) end
		if #dueSounds > 0 then playDueSounds(now) end
	end)

	local camera = Workspace.CurrentCamera
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	updateScale()
end

-- The server's word on what is found and what is still to be shown found. A Sync comes as the profile loads and after
-- an `index` console command; a type it calls new is hidden again even if this screen revealed it, so its reveal
-- plays once more. The screen's own reveals reach the server (Seen) before any later command's Sync.
ServerNetworkIndex.Sync.On(function(enemyIds: { number }, kills: { number }, isNew: { boolean })
	local byId, hidden = {}, {}
	local revealAt, unread = table.clone(state.RevealAt()), table.clone(state.Unread())
	for index, enemyId in enemyIds do
		if not ENEMIES[enemyId] then continue end
		byId[enemyId] = kills[index]
		if not isNew[index] then continue end
		hidden[enemyId] = true
		revealAt[enemyId] = nil
		unread[enemyId] = nil
	end

	vide.batch(function()
		state.Kills(byId)
		state.Hidden(hidden)
		state.RevealAt(revealAt)
		state.Unread(unread)
	end)
	revealPage()
end)

return Ignis.Register(IndexController)
