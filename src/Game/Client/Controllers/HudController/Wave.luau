--!nonstrict
-- The top of the screen (UIMatt.md, In-Game HUD): the wave plate in the middle with the boss strip under it (BossBar),
-- and SKIP WAVE with its vote count and auto-skip on the right. Every rect is the designer's drawn one, at 1080.
--
-- One plate carries the whole round. While a wave is fought it reads WAVE n and the boss strip hangs under it; when the
-- wave is cleared the title lifts out, the plate takes his NEXT WAVE IN plate's shape and words, the strip slides back
-- up behind it and his countdown square pops out below. When the countdown runs out the square is swallowed by the
-- plate, the next WAVE n drops in with a flash and rings, and the strip comes back down.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Components)
local Theme = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Theme)
local Motion = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Motion)
local Hand = require(StarterPlayer.StarterPlayerScripts.GlobalClient.UI.Hand)
local BossBar = require(script.Parent.BossBar)
local Types = require(script.Parent.Types)

local create = vide.create
local derive = vide.derive
local spring = vide.spring
local Palette = Theme.Palette
local Font = Theme.Font
local Panel = Components.Panel
local Progress = Motion.Progress
local Lerp = Motion.Lerp

-- His drawn rects (outer, edge included) in px at 1920 x 1080; x is from the screen's centre for the middle pieces and
-- from its right edge for the skip block.
local Layout = table.freeze({
	TOP = 16,
	-- The WAVE plate, and his NEXT WAVE IN plate it turns into.
	PLATE = Vector2.new(380, 88),
	PREP_PLATE = Vector2.new(360, 56),
	TITLE_SIZE = 62,
	CAPTION_SIZE = 28,
	-- The countdown square, this far under the NEXT WAVE IN plate.
	COUNT = 98,
	COUNT_GAP = 15,
	COUNT_TEXT = 67,
	-- The skip block, x from the screen's right edge to each piece's left.
	SKIP = Vector2.new(545, 15),
	SKIP_SIZE = Vector2.new(302, 74),
	SKIP_TEXT = 29,
	SKIP_ICON = 13,
	SKIP_GAP = 19,
	VOTES = Vector2.new(236, 16),
	VOTES_SIZE = Vector2.new(92, 72),
	VOTES_TEXT = 29,
	AUTO = Vector2.new(544, 98),
	AUTO_SIZE = Vector2.new(380, 52),
	AUTO_TEXT = 19,
	AUTO_LABEL = 20,
	TRACK = Vector2.new(72, 35),
	TRACK_RIGHT = 21,
	KNOB = Vector2.new(32, 28),
	KNOB_INSET = 3,
})

-- His toggle's colours: a violet-edged track and a pale knob.
local TRACK_EDGE = Color3.fromRGB(110, 90, 180)
local TRACK_FACE = Color3.fromRGB(34, 28, 62)
local KNOB = Color3.fromRGB(152, 150, 172)
-- How far the knob leans toward the other side under the hand, as a share of its travel.
local KNOB_LEAN = 0.14

-- Seconds, each gesture timed from the phase change that starts it.
local Timing = table.freeze({
	-- The old title leaving, the new one arriving (after a beat, so the two never overlap).
	OUT = 0.22,
	IN = 0.42,
	IN_DELAY = 0.14,
	-- The plate changing shape for the countdown, and back once the square has been swallowed.
	RESHAPE = 0.32,
	COUNT_IN = 0.4,
	COUNT_IN_DELAY = 0.22,
	SLAM = 0.3,
	FLASH = 0.5,
	-- A shockwave's life.
	RING = 0.45,
	TICK = 0.34,
	SHEEN = 0.7,
	PUNCH = 0.3,
})

-- The countdown's last seconds each send a ring out.
local HOT_SECONDS = 3
-- A shockwave's line, and how far it grows past its element, in px.
local RING_LINE = 3
local RING_REACH = 20
-- The countdown's ring stops 2 px short of the NEXT WAVE IN plate above it.
local COUNT_RING_REACH = Layout.COUNT_GAP - RING_LINE - 2
-- SKIP WAVE's brackets stand off it this far, and open this much more under the hand.
local SKIP_BRACKETS = 5
local SKIP_BRACKETS_OPEN = 3

local Wave = {}

local function label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		props,
	})
end

-- One outline leaving an element. It grows by PIXELS at one weight (a UIScale fattens the line and runs a wide plate
-- off sideways), and it stays Visible: an element turned Visible is drawn at its last layout for a frame, which was the
-- ring at full reach. `at` is when it leaves; nil when it should not.
local function shockwave(state: Types.THudState, at: () -> number?, reach: number): Frame
	local life = function(): number
		local start = at()
		return if start then Progress(state.Now(), start, Timing.RING) else 1
	end

	return create("Frame")({
		Name = "Shockwave",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = function()
			local grow = math.round(reach * Motion.Out(life()))
			return UDim2.new(1, 2 * grow, 1, 2 * grow)
		end,
		BackgroundTransparency = 1,
		ZIndex = 0,
		create("UIStroke")({
			Color = Palette.Pink,
			Thickness = RING_LINE,
			LineJoinMode = Enum.LineJoinMode.Miter,
			-- Spent or not started: unseen. Otherwise it fades from 0.15 on the clock.
			Transparency = function()
				local t = life()
				return if t <= 0 or t >= 1 then 1 else Lerp(0.15, 1, t)
			end,
		}),
	})
end

-- ============================== The plate ==============================

local function plate(state: Types.THudState): { Instance }
	local phase = state.Phase
	local since = function(seconds: number, delay: number?): number
		return Progress(state.Now(), state.PhaseAt(), seconds, delay)
	end

	local isFromFight = function()
		return state.PreviousPhase() == "Fighting"
	end

	local isFromPrep = function()
		return state.PreviousPhase() == "Preparing"
	end

	-- The wave being fought, held through the plate's change so the leaving title keeps its own number.
	local fightRound = 0
	local shownRound = derive(function()
		if phase() == "Fighting" then fightRound = state.Round() end
		return fightRound
	end)

	-- 0 for the WAVE plate's shape, 1 for the NEXT WAVE IN plate's.
	local prepMix = function()
		local current = phase()
		if current == "Preparing" then return Motion.Out(since(Timing.RESHAPE, 0.04)) end
		if current == "Fighting" and isFromPrep() then
			return 1 - Motion.Out(since(Timing.RESHAPE, Timing.SLAM * 0.5))
		end
		return 0
	end

	-- WAVE n: x is its drop, y its transparency, z its scale.
	local title = function(): Vector3
		local current = phase()
		if current == "Fighting" then
			if not isFromPrep() and state.PreviousPhase() ~= "Waiting" then return Vector3.new(0, 0, 1) end
			local t = since(Timing.IN, Timing.SLAM * 0.6)
			return Vector3.new(
				Lerp(-Layout.PLATE.Y * 0.9, 0, Motion.OutBack(t)),
				1 - Motion.Out(math.min(t * 3, 1)),
				Lerp(1.35, 1, Motion.Out(t))
			)
		end
		if current == "Preparing" and isFromFight() then
			local t = since(Timing.OUT)
			return Vector3.new(Lerp(0, -Layout.PLATE.Y * 0.7, Motion.InBack(t)), t, 1)
		end
		return Vector3.new(0, 1, 1)
	end

	-- NEXT WAVE IN: x its rise, y its transparency.
	local caption = function(): Vector2
		local current = phase()
		if current == "Preparing" then
			local t = since(Timing.IN, Timing.IN_DELAY)
			return Vector2.new(Lerp(Layout.PREP_PLATE.Y * 0.8, 0, Motion.Decelerate(t)), 1 - Motion.Out(t))
		end
		if current == "Fighting" and isFromPrep() then
			local t = since(Timing.OUT)
			return Vector2.new(Lerp(0, Layout.PREP_PLATE.Y * 0.7, Motion.InBack(t)), t)
		end
		return Vector2.new(0, 1)
	end

	-- The countdown square: x its scale, y how far it has risen into the plate.
	local count = function(): Vector2
		local current = phase()
		if current == "Preparing" then
			return Vector2.new(Motion.OutBack(since(Timing.COUNT_IN, Timing.COUNT_IN_DELAY)), 0)
		end
		if current == "Fighting" and isFromPrep() then
			-- Swells, then is swallowed by the plate above it.
			local t = since(Timing.SLAM)
			if t < 0.3 then return Vector2.new(1 + 0.22 * Motion.Out(t / 0.3), 0) end
			local k = Motion.Accelerate((t - 0.3) / 0.7)
			return Vector2.new(1.22 * (1 - k), k)
		end
		return Vector2.new(0, 0)
	end

	-- Read off the count alone, not the phase: the last beat ("GO") is still playing when the wave starts, and a hot
	-- beat cut to a cool one mid-flight snaps its size.
	local isHot = function()
		return state.Countdown() <= HOT_SECONDS
	end

	local beat = function(): number
		return Motion.Fade(state.Now(), state.CountdownAt(), Timing.TICK)
	end

	-- A white flash as a wave starts, a green one as one is cleared.
	local flash = function(): number
		local current = phase()
		if current == "Fighting" and isFromPrep() then
			return 0.65 * Motion.Fade(state.Now(), state.PhaseAt() + Timing.SLAM * 0.55, Timing.FLASH)
		end
		if current == "Preparing" and isFromFight() then
			return 0.5 * Motion.Fade(state.Now(), state.PhaseAt(), Timing.FLASH)
		end
		return 0
	end

	-- The ring leaves as the square lands in the plate.
	local ringAt = function(): number?
		if phase() ~= "Fighting" or not isFromPrep() then return nil end
		return state.PhaseAt() + Timing.SLAM * 0.55
	end

	local beatRingAt = function(): number?
		return if isHot() then state.CountdownAt() else nil
	end

	local size = function(): Vector2
		return Layout.PLATE:Lerp(Layout.PREP_PLATE, prepMix())
	end

	local isBossWave = function()
		return state.IsBossRound()
	end

	local countTop = Layout.TOP + Layout.PREP_PLATE.Y + Layout.COUNT_GAP
	local plateFrame = Panel({ Brackets = 6 }, {
		Name = "Plate",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Layout.TOP),
		Size = function()
			local current = size()
			return UDim2.fromOffset(math.round(current.X), math.round(current.Y))
		end,
		ZIndex = 3,
		Visible = function()
			return phase() ~= "Ended"
		end,

		-- The words slide inside the face and are cut at its edges. They are never hidden with Visible, only faded: a
		-- frame turned Visible is drawn where it last stood for a frame, which was where the old title left to.
		create("Frame")({
			Name = "Window",
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 2,
			label({
				Name = "Waiting",
				Size = UDim2.fromScale(1, 1),
				TextSize = Layout.CAPTION_SIZE,
				TextColor3 = Palette.Lavender,
				Text = "WAITING FOR SQUAD",
				Visible = function()
					return phase() == "Waiting"
				end,
			}),
			label({
				Name = "Title",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				TextSize = Layout.TITLE_SIZE,
				Position = function()
					return UDim2.new(0.5, 0, 0.5, math.round(title().X))
				end,
				TextTransparency = function()
					return title().Y
				end,
				TextColor3 = function()
					return if isBossWave() then Palette.Pink else Palette.White
				end,
				Text = function()
					return `WAVE {shownRound()}`
				end,
				create("UIScale")({
					Scale = function()
						return title().Z
					end,
				}),
			}),
			label({
				Name = "Caption",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = function()
					return UDim2.new(0.5, 0, 0.5, math.round(caption().X))
				end,
				Size = UDim2.fromScale(1, 1),
				TextSize = Layout.CAPTION_SIZE,
				TextTransparency = function()
					return caption().Y
				end,
				TextColor3 = function()
					return if isBossWave() then Palette.Pink else Palette.White
				end,
				Text = function()
					return if isBossWave() then "BOSS WAVE IN" else "NEXT WAVE IN"
				end,
			}),
		}),

		create("Frame")({
			Name = "Flash",
			Size = UDim2.fromScale(1, 1),
			BorderSizePixel = 0,
			ZIndex = 4,
			BackgroundColor3 = function()
				return if phase() == "Preparing" then Palette.Green else Palette.White
			end,
			BackgroundTransparency = function()
				return 1 - flash()
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
		}),

		shockwave(state, ringAt, RING_REACH),
	})

	-- His countdown square, under the NEXT WAVE IN plate.
	local countdown = Components.Slab({ Kind = "Go" }, {
		Name = "Countdown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = function()
			local centre = countTop + Layout.COUNT / 2
			local plateCentre = Layout.TOP + Layout.PREP_PLATE.Y / 2
			return UDim2.new(0.5, 0, 0, math.round(Lerp(centre, plateCentre, count().Y)))
		end,
		Size = UDim2.fromOffset(Layout.COUNT, Layout.COUNT),
		ZIndex = 2,
		Visible = function()
			return count().X > 0.01
		end,
		create("UIScale")({
			Scale = function()
				return count().X
			end,
		}),
		create("Frame")({
			Name = "Beat",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			ZIndex = 3,
			BackgroundTransparency = function()
				local k = beat()
				return 1 - (if isHot() then 0.5 else 0.3) * k * k
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
		}),
		label({
			Name = "Number",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			TextSize = Layout.COUNT_TEXT,
			ZIndex = 4,
			Text = function()
				local left = state.Countdown()
				return if left > 0 then tostring(left) else "GO"
			end,
			create("UIScale")({
				Scale = function()
					local k = beat()
					return 1 + (if isHot() then 0.45 else 0.3) * k * k
				end,
			}),
		}),
		-- Each of the last seconds sends a ring out of the square.
		shockwave(state, beatRingAt, COUNT_RING_REACH),
	})

	return { plateFrame, countdown }
end

-- ============================== Skip ==============================

-- His SKIP WAVE slab. It is grey and filling while it cools down (through the countdown and the wave's opening seconds)
-- and turns green, with a punch and a sweep of light, when the vote opens.
local function skipButton(state: Types.THudState, actions: Types.TActions): TextButton
	local isLive = state.CanSkip
	local hand = Hand.React("Operate", isLive)

	local punch = function()
		local k = Motion.Fade(state.Now(), state.SkipOpenedAt(), Timing.PUNCH)
		return 0.08 * k * k
	end

	local ink = function()
		return if isLive() then Palette.White else Palette.Lavender
	end

	return create("TextButton")({
		Name = "SkipWave",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -Layout.SKIP.X + Layout.SKIP_SIZE.X / 2, 0, Layout.SKIP.Y + Layout.SKIP_SIZE.Y / 2),
		Size = UDim2.fromOffset(Layout.SKIP_SIZE.X, Layout.SKIP_SIZE.Y),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 2,
		Activated = function()
			hand.Commit()
			actions.VoteStart()
		end,
		hand.Events,
		Components.ButtonSounds,
		create("UIScale")({
			Scale = function()
				return hand.Scale() + punch()
			end,
		}),
		Components.Slab({
			Kind = function()
				return if isLive() then "Go" else "Off"
			end,
			Marks = true,
			GlowTransparency = function()
				if not isLive() then return 1 end
				return 0.6 - 0.3 * hand.Light()
			end,
			Brackets = function()
				return SKIP_BRACKETS + SKIP_BRACKETS_OPEN * hand.Rise()
			end,
		}, {
			Name = "Face",
			Size = UDim2.fromScale(1, 1),
			-- The cooldown filling the grey face. Faded rather than hidden: turned Visible it would be drawn full for a
			-- frame, where it last stood.
			create("Frame")({
				Name = "Cooldown",
				Position = UDim2.fromOffset(3, 3),
				Size = UDim2.new(1, -6, 1, -6),
				BackgroundTransparency = 1,
				ZIndex = 2,
				create("Frame")({
					Size = function()
						return UDim2.fromScale(state.SkipProgress(), 1)
					end,
					BackgroundColor3 = Palette.Green,
					BorderSizePixel = 0,
					BackgroundTransparency = function()
						return if isLive() then 1 else 0.75
					end,
				}),
			}),
			Hand.WashLayer(hand, 3, 4),
			Components.Sheen(
				Hand.Sheen(hand, function()
					return Progress(state.Now(), state.SkipOpenedAt(), Timing.SHEEN)
				end),
				4
			),
		}),
		create("Frame")({
			Name = "Content",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			ZIndex = 5,
			create("UIListLayout")({
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, Layout.SKIP_GAP),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Components.Icon("Skip", {
				LayoutOrder = 1,
				Size = Components.GlyphBox(Layout.SKIP_ICON),
				ImageColor3 = ink,
			}),
			label({
				LayoutOrder = 2,
				Size = UDim2.fromOffset(0, Layout.SKIP_SIZE.Y),
				AutomaticSize = Enum.AutomaticSize.X,
				TextSize = Layout.SKIP_TEXT,
				TextColor3 = ink,
				Text = "SKIP WAVE",
			}),
		}),
	}) :: TextButton
end

local function votes(state: Types.THudState): Frame
	local punch = function()
		local k = Motion.Fade(state.Now(), state.VotesAt(), Timing.PUNCH)
		return k * k
	end

	return Components.Plaque({
		Name = "Votes",
		Position = UDim2.new(1, -Layout.VOTES.X, 0, Layout.VOTES.Y),
		Size = UDim2.fromOffset(Layout.VOTES_SIZE.X, Layout.VOTES_SIZE.Y),
		label({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			TextSize = Layout.VOTES_TEXT,
			ZIndex = 2,
			TextColor3 = function()
				return Palette.White:Lerp(Palette.Green, punch())
			end,
			Text = function()
				return `{state.Votes()}/{state.VotesNeeded()}`
			end,
			create("UIScale")({
				Scale = function()
					return 1 + 0.3 * punch()
				end,
			}),
		}),
	})
end

local function autoSkip(state: Types.THudState, actions: Types.TActions): TextButton
	local isOn = state.IsAutoSkip
	local hand = Hand.React("Operate")
	local knob = spring(function()
		return if isOn() then 1 else 0
	end, 0.2, 0.72)
	-- Under the hand the knob leans toward the side a click would send it.
	local lean = function(): number
		return (if isOn() then -KNOB_LEAN else KNOB_LEAN) * hand.Rise()
	end

	-- Placed by its middle, so it grows from there.
	return create("TextButton")({
		Name = "AutoSkip",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -Layout.AUTO.X + Layout.AUTO_SIZE.X / 2, 0, Layout.AUTO.Y + Layout.AUTO_SIZE.Y / 2),
		Size = UDim2.fromOffset(Layout.AUTO_SIZE.X, Layout.AUTO_SIZE.Y),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Activated = function()
			hand.Commit()
			actions.ToggleAutoSkip()
		end,
		hand.Events,
		Components.ButtonSounds,
		create("UIScale")({ Scale = hand.Scale }),
		Panel({
			Stroke = function()
				return Palette.EdgePink:Lerp(Palette.Pink, hand.Light())
			end,
			-- His dark drop shadow at rest, warming to a pink glow under the hand.
			Glow = function()
				return Color3.new():Lerp(Palette.Pink, hand.Light())
			end,
			GlowTransparency = function()
				return 0.6 - 0.15 * hand.Light()
			end,
		}, {
			Size = UDim2.fromScale(1, 1),
			Hand.WashLayer(hand, 3, 3),
			Components.Sheen(hand.Glint, 3),
		}),
		label({
			Position = UDim2.fromOffset(Layout.AUTO_LABEL, 0),
			Size = UDim2.fromScale(0.6, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = Layout.AUTO_TEXT,
			ZIndex = 2,
			TextColor3 = function()
				return if isOn() then Palette.White else Palette.Lavender
			end,
			Text = "AUTO-SKIP",
		}),
		create("Frame")({
			Name = "Track",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -Layout.TRACK_RIGHT, 0.5, 0),
			Size = UDim2.fromOffset(Layout.TRACK.X, Layout.TRACK.Y),
			BorderSizePixel = 0,
			ZIndex = 2,
			BackgroundColor3 = function()
				return TRACK_FACE:Lerp(Palette.GoBottom, math.clamp(knob(), 0, 1))
			end,
			create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			create("UIStroke")({
				Color = function()
					return TRACK_EDGE:Lerp(Palette.Green, math.clamp(knob(), 0, 1))
				end,
				Thickness = 1.5,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			create("Frame")({
				Name = "Knob",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = function()
					local travel = Layout.TRACK.X - Layout.KNOB.X - 2 * Layout.KNOB_INSET
					return UDim2.new(0, math.round(Layout.KNOB_INSET + travel * (knob() + lean())), 0.5, 0)
				end,
				Size = UDim2.fromOffset(Layout.KNOB.X, Layout.KNOB.Y),
				BorderSizePixel = 0,
				BackgroundColor3 = function()
					return KNOB:Lerp(Palette.White, math.clamp(knob(), 0, 1))
				end,
				create("UICorner")({ CornerRadius = UDim.new(0, 3) }),
			}),
		}),
	}) :: TextButton
end

local function skipBlock(state: Types.THudState, actions: Types.TActions): Frame
	return create("Frame")({
		Name = "Skip",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = function()
			local phase = state.Phase()
			return phase == "Preparing" or phase == "Fighting"
		end,
		skipButton(state, actions),
		votes(state),
		autoSkip(state, actions),
	})
end

function Wave.Build(state: Types.THudState, actions: Types.TActions): Frame
	return create("Frame")({
		Name = "Wave",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		plate(state),
		BossBar.Build(state),
		skipBlock(state, actions),
	})
end

return Wave
