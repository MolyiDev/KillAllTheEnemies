--!nonstrict
-- The settings screen (UIMatt.md, Settings), in both places: the audio sliders and the camera switches, each row
-- ending in its own reset, and RESET ALL behind a confirm (Confirm.luau). The world dims, the panel
-- rises into place, the rules draw themselves out and the rows are dealt in one after another, each slider running up
-- to its value as it lands. Closed by its X or by a click on the dim.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local vide = require(ReplicatedStorage.Packages.vide)
local Components = require(script.Parent.Components)
local Motion = require(script.Parent.Motion)
local Theme = require(script.Parent.Theme)
local Confirm = require(script.Confirm)
local Controls = require(script.Controls)
local Types = require(script.Types)

local create = vide.create
local derive = vide.derive
local source = vide.source
local Palette = Theme.Palette
local Font = Theme.Font
local Progress = Motion.Progress
local Lerp = Motion.Lerp

-- His drawn rects in px at 1080, from the panel's top left corner unless said otherwise.
local Layout = table.freeze({
	-- His panel without its PROFILE section: everything under CAMERA is 146 px higher than he drew it.
	SIZE = Vector2.new(1040, 774),
	-- The header: the glyph's middle and longer side, the title's corner and letter height, the rule under it.
	HEADER_ICON = Vector2.new(49, 48),
	HEADER_ICON_SIZE = 30,
	TITLE = Vector2.new(82, 26),
	TITLE_SIZE = 43,
	HEADER_RULE = Vector2.new(32, 96),
	HEADER_RULE_WIDTH = 984,
	CLOSE = Vector2.new(951, 15),
	CLOSE_SIZE = 66,
	CLOSE_BAR = Vector2.new(23, 2),
	-- A section header, from its own corner: the glyph's middle, the title, the rule.
	SECTION_X = 40,
	SECTION_WIDTH = 960,
	SECTION_ICON = Vector2.new(11, 12.5),
	SECTION_TITLE_X = 32,
	SECTION_TITLE_SIZE = 24,
	SECTION_RULE_Y = 37,
	ROW_X = 40,
	ROW_SIZE = Vector2.new(959, 71),
	-- From a row's corner. A row with a description carries its label higher.
	LABEL_X = 24,
	LABEL_Y = 22,
	LABEL_HIGH_Y = 12,
	LABEL_SIZE = 27,
	DESCRIPTION_Y = 43.5,
	DESCRIPTION_SIZE = 15,
	SLIDER_X = 654,
	SWITCH_X = 823,
	RESET_X = 912,
	FOOTER_RULE_Y = 659,
	HINT = Vector2.new(40, 701.5),
	HINT_SIZE = 16,
	RESET_ALL = Vector2.new(699, 677),
	RESET_ALL_SIZE = Vector2.new(302, 66),
	-- The room round the panel and round a row inside the group that fades it, for the glow and the brackets (a
	-- CanvasGroup clips).
	MARGIN = 48,
	ROW_MARGIN = 28,
})

-- Where each section's header and each row stands, down the panel.
local SECTIONS = table.freeze({
	table.freeze({ Text = "AUDIO", Icon = "Music", IconSize = 18, Y = 119 }),
	table.freeze({ Text = "CAMERA", Icon = "Camera", IconSize = 18, Y = 429 }),
})
local VOLUME_YS = table.freeze({ 173, 255, 337 })
local TOGGLE_YS = table.freeze({ 483, 565 })

local Timing = table.freeze({
	-- The panel decelerates up into place and accelerates down out of it, the exit the faster. Its fade runs on the
	-- clock, not on the move: a decelerate is nearly done in a quarter of its time, and a fade tied to it reads as
	-- a pop.
	OPEN = 0.34,
	FADE = 0.27,
	RISE = 26,
	CLOSE = 0.2,
	SINK = 14,
	DIM = 0.3,
	TITLE_DELAY = 0.06,
	TITLE = 0.32,
	TITLE_SLIDE = 22,
	-- Each rule draws itself out from its left end; a section's words fade in as its rule sets off.
	RULE_DELAY = 0.1,
	RULE = 0.45,
	SECTION_DELAY = 0.14,
	SECTION_STAGGER = 0.1,
	SECTION = 0.25,
	-- Each row is dealt in from the right a beat after the one above it, the light crosses it as it lands, and its
	-- slider runs up from nothing.
	ROW_DELAY = 0.16,
	ROW_STAGGER = 0.055,
	ROW = 0.4,
	ROW_FADE = 0.3,
	ROW_SLIDE = 44,
	ROW_SHEEN_DELAY = 0.2,
	ROW_SHEEN = 0.6,
	COUNT_DELAY = 0.1,
	COUNT = 0.5,
	FOOTER_DELAY = 0.5,
	FOOTER = 0.3,
	-- Every gesture of an open or a shut is over by now.
	SETTLED = 1.4,
	-- Under the hand a row's glow comes up and its brackets open.
	ROW_GLOW = 0.75,
	HOVER_GLOW = 0.5,
	HOVER_BRACKETS = 3,
	-- The hint goes white as a change is sent, and falls back.
	SAVED = 0.7,
})

-- His rows' violet edge and the face under it, and the rules' lavender, sampled off the art.
local ROW_ACCENT = Color3.fromRGB(118, 93, 180)
local ROW_FACE = Color3.fromRGB(26, 17, 48)
local RULE_COLOR = Color3.fromRGB(140, 111, 210)
local RULE_TRANSPARENCY = 0.55

local SettingsUI = {}

local function label(props: { [any]: any }): TextLabel
	return create("TextLabel")({
		BackgroundTransparency = 1,
		FontFace = Font.Display,
		TextColor3 = Palette.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
		props,
	})
end

-- A thin rule `width` px long that draws itself out from its left end as `drawn` runs 0 to 1.
local function rule(position: UDim2, width: number, drawn: () -> number): Frame
	return create("Frame")({
		Name = "Rule",
		Position = position,
		Size = function()
			return UDim2.fromOffset(math.round(width * Motion.Decelerate(drawn())), 1)
		end,
		BackgroundColor3 = RULE_COLOR,
		BackgroundTransparency = RULE_TRANSPARENCY,
		BorderSizePixel = 0,
		ZIndex = 2,
	})
end

-- His pink square with a thin white X. Under the hand it grows a little and the X turns a quarter; pressed, it dips.
local function closeButton(actions: Types.TActions): TextButton
	local events, isHovered, isPressed = Controls.Hand()
	local hover = Controls.Spring(function()
		return if isHovered() then 1 else 0
	end, 0.22, 0.85)
	local scale = Controls.Spring(function()
		return if isPressed() then 0.93 elseif isHovered() then 1.06 else 1
	end, 0.16, 0.85)

	local function bar(rotation: number): Frame
		return create("Frame")({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(Layout.CLOSE_BAR.X, Layout.CLOSE_BAR.Y),
			Rotation = function()
				return rotation + 90 * hover()
			end,
			BackgroundColor3 = Palette.White,
			BorderSizePixel = 0,
			ZIndex = 2,
		})
	end

	return Components.Button({
		Name = "Close",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(Layout.CLOSE.X + Layout.CLOSE_SIZE / 2, Layout.CLOSE.Y + Layout.CLOSE_SIZE / 2),
		Size = UDim2.fromOffset(Layout.CLOSE_SIZE, Layout.CLOSE_SIZE),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Activated = actions.Close,
		events,
		create("UIScale")({ Scale = scale }),
		Components.Slab({
			Kind = "Pink",
			GlowTransparency = function()
				return Lerp(0.6, 0.4, hover())
			end,
		}, {
			Name = "Face",
			Size = UDim2.fromScale(1, 1),
			bar(45),
			bar(-45),
		}),
	}) :: TextButton
end

function SettingsUI.Build(state: Types.TSettingsState, actions: Types.TActions): Frame
	-- Seconds since the screen was opened or shut, held once every gesture is over, so that the clock ticking for a
	-- row's own gesture works none of the open out again.
	local elapsed = derive(function(): number
		return math.min(state.Now() - state.ToggledAt(), Timing.SETTLED)
	end)
	-- How much of the screen is there, 0 to 1: its fade, on the clock both ways.
	local shown = function(): number
		if state.IsOpen() then return Motion.Out(Progress(elapsed(), 0, Timing.FADE)) end
		return 1 - Progress(elapsed(), 0, Timing.CLOSE)
	end
	-- How far under its place the panel is, in px.
	local drop = function(): number
		if state.IsOpen() then return Timing.RISE * (1 - Motion.Decelerate(Progress(elapsed(), 0, Timing.OPEN))) end
		return Timing.SINK * Motion.Accelerate(Progress(elapsed(), 0, Timing.CLOSE))
	end
	-- 0 to 1 as a piece's own gesture runs after the screen opens; all done while it shuts.
	local function since(delay: number, seconds: number): number
		if not state.IsOpen() then return 1 end
		return Progress(elapsed(), delay, seconds)
	end

	local hasChanges = derive(function(): boolean
		for _, row in state.Volumes do
			if row.Value() ~= row.Default then return true end
		end
		for _, row in state.Toggles do
			if row.IsOn() ~= row.Default then return true end
		end

		return false
	end)

	local function section(index: number): Frame
		local data = SECTIONS[index]
		local delay = Timing.SECTION_DELAY + Timing.SECTION_STAGGER * (index - 1)
		local faded = function(): number
			return 1 - Motion.Out(since(delay, Timing.SECTION))
		end

		return create("Frame")({
			Name = data.Text,
			Position = UDim2.fromOffset(Layout.SECTION_X, data.Y),
			Size = UDim2.fromOffset(Layout.SECTION_WIDTH, Layout.SECTION_RULE_Y + 1),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Components.Icon(data.Icon, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(Layout.SECTION_ICON.X, Layout.SECTION_ICON.Y),
				Size = Components.GlyphBox(data.IconSize),
				ImageColor3 = Palette.Pink,
				ImageTransparency = faded,
				ZIndex = 2,
			}),
			label({
				Position = UDim2.fromOffset(Layout.SECTION_TITLE_X, 0),
				Size = UDim2.fromOffset(300, Layout.SECTION_TITLE_SIZE),
				TextSize = Layout.SECTION_TITLE_SIZE,
				TextTransparency = faded,
				Text = data.Text,
			}),
			rule(UDim2.fromOffset(0, Layout.SECTION_RULE_Y), Layout.SECTION_WIDTH, function()
				return since(delay, Timing.RULE)
			end),
		})
	end

	-- One row: his violet card with its words on the left and its controls on the right. `spec` is Order (its place in
	-- the deal), Y, Text, Description (nil for none), ResetAt (the os.clock its reset last sent it home) and Build,
	-- which is handed the row's count-up and returns what stands on the right.
	local function row(spec: { [string]: any }): CanvasGroup
		local text: string, description: string? = spec.Text, spec.Description
		local delay = Timing.ROW_DELAY + Timing.ROW_STAGGER * (spec.Order - 1)
		local isHovered = source(false)
		local hover = Controls.Spring(function()
			return if isHovered() then 1 else 0
		end, 0.2, 0.9)
		local counted = function(): number
			return Motion.Out(since(delay + Timing.COUNT_DELAY, Timing.COUNT))
		end
		-- The light crosses as the row lands, and again as its reset sends it home. Derived, so that once both are
		-- over the clock ticking for another row redraws nothing here.
		local sheen = derive(function(): number
			return math.min(
				since(delay + Timing.ROW_SHEEN_DELAY, Timing.ROW_SHEEN),
				Progress(state.Now(), spec.ResetAt(), Timing.ROW_SHEEN)
			)
		end)

		return create("CanvasGroup")({
			Name = text,
			Position = function()
				local slide = Timing.ROW_SLIDE * (1 - Motion.Decelerate(since(delay, Timing.ROW)))
				return UDim2.fromOffset(
					Layout.ROW_X + math.round(slide) - Layout.ROW_MARGIN,
					spec.Y - Layout.ROW_MARGIN
				)
			end,
			Size = UDim2.fromOffset(
				Layout.ROW_SIZE.X + 2 * Layout.ROW_MARGIN,
				Layout.ROW_SIZE.Y + 2 * Layout.ROW_MARGIN
			),
			BackgroundTransparency = 1,
			ZIndex = 2,
			GroupTransparency = function()
				if not state.IsOpen() then return 1 - shown() end
				return 1 - Motion.Out(since(delay, Timing.ROW_FADE))
			end,
			Components.Card({
				Accent = ROW_ACCENT,
				Face = ROW_FACE,
				Tint = 0.1,
				Edge = 2,
				Wide = true,
				GlowTransparency = function()
					return Lerp(Timing.ROW_GLOW, Timing.HOVER_GLOW, hover())
				end,
			}, {
				Name = "Face",
				Position = UDim2.fromOffset(Layout.ROW_MARGIN, Layout.ROW_MARGIN),
				Size = UDim2.fromOffset(Layout.ROW_SIZE.X, Layout.ROW_SIZE.Y),
				MouseEnter = function()
					isHovered(true)
				end,
				MouseLeave = function()
					isHovered(false)
				end,
				-- His stand 8 px off the row's ends and 5 off its top and bottom.
				create("Frame")({
					Name = "BracketsHolder",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = function()
						local open = Timing.HOVER_BRACKETS * hover() * 2
						return UDim2.new(1, 6 + open, 1, open)
					end,
					BackgroundTransparency = 1,
					ZIndex = 0,
					Components.Brackets(5, 0.65, 20),
				}),
				label({
					Name = "Label",
					Position = UDim2.fromOffset(
						Layout.LABEL_X,
						if description then Layout.LABEL_HIGH_Y else Layout.LABEL_Y
					),
					Size = UDim2.fromOffset(440, Layout.LABEL_SIZE),
					TextSize = Layout.LABEL_SIZE,
					Text = text,
				}),
				if description
					then label({
						Name = "Description",
						Position = UDim2.fromOffset(Layout.LABEL_X, Layout.DESCRIPTION_Y),
						Size = UDim2.fromOffset(440, Layout.DESCRIPTION_SIZE),
						FontFace = Font.DisplayBold,
						TextSize = Layout.DESCRIPTION_SIZE,
						TextColor3 = Palette.Lavender,
						Text = description,
					})
					else nil,
				spec.Build(counted),
				create("Frame")({
					Name = "SheenWindow",
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					ClipsDescendants = true,
					ZIndex = 5,
					Components.Sheen(sheen, 5),
				}),
			}),
		})
	end

	local function middle(x: number): UDim2
		return UDim2.new(0, x, 0.5, 0)
	end

	local volumeCount, toggleCount = #state.Volumes, #state.Toggles
	local rows = table.create(volumeCount + toggleCount)
	for index, volume in state.Volumes do
		rows[index] = row({
			Order = index,
			Y = VOLUME_YS[index],
			Text = volume.Label,
			ResetAt = volume.ResetAt,
			Build = function(counted: () -> number)
				return {
					Controls.Slider(volume, actions, counted, { Position = middle(Layout.SLIDER_X) }),
					Controls.Reset(
						state,
						function()
							return volume.Value() ~= volume.Default
						end,
						volume.ResetAt,
						function()
							actions.ResetVolume(volume)
						end,
						{ Position = middle(Layout.RESET_X) }
					),
				}
			end,
		})
	end

	for index, toggle in state.Toggles do
		rows[volumeCount + index] = row({
			Order = volumeCount + index,
			Y = TOGGLE_YS[index],
			Text = toggle.Label,
			Description = toggle.Description,
			ResetAt = toggle.ResetAt,
			Build = function()
				return {
					Controls.Switch(state, toggle, actions, { Position = middle(Layout.SWITCH_X) }),
					Controls.Reset(
						state,
						function()
							return toggle.IsOn() ~= toggle.Default
						end,
						toggle.ResetAt,
						function()
							actions.ResetToggle(toggle)
						end,
						{ Position = middle(Layout.RESET_X) }
					),
				}
			end,
		})
	end

	-- 1 to 0 as the header's words arrive; 0 while the screen shuts.
	local away = function(): number
		return 1 - Motion.Decelerate(since(Timing.TITLE_DELAY, Timing.TITLE))
	end
	-- 1 falling to 0 after a change is sent. Derived: at 0 the clock's ticks redraw nothing.
	local saved = derive(function(): number
		return Motion.Fade(state.Now(), state.SavedAt(), Timing.SAVED)
	end)
	local footer = function(): number
		return 1 - Motion.Out(since(Timing.FOOTER_DELAY, Timing.FOOTER))
	end

	return create("Frame")({
		Name = "Settings",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = function()
			return shown() > 0.001
		end,
		-- Modal: in first person the engine holds the mouse at the centre unless a visible button says otherwise.
		create("TextButton")({
			Name = "Dim",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Modal = true,
			Text = "",
			BackgroundTransparency = function()
				return 1 - Timing.DIM * shown()
			end,
			Activated = actions.Close,
		}),
		create("Frame")({
			Name = "Window",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = function()
				return UDim2.new(0.5, 0, 0.5, math.round(drop()))
			end,
			Size = UDim2.fromOffset(Layout.SIZE.X, Layout.SIZE.Y),
			BackgroundTransparency = 1,
			ZIndex = 2,
			-- A press on the panel stops here. A Frame lets it through to the dim, which would shut the screen.
			create("TextButton")({
				Name = "Sink",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Text = "",
			}),
			create("CanvasGroup")({
				Name = "Chrome",
				Position = UDim2.fromOffset(-Layout.MARGIN, -Layout.MARGIN),
				Size = UDim2.new(1, 2 * Layout.MARGIN, 1, 2 * Layout.MARGIN),
				BackgroundTransparency = 1,
				GroupTransparency = function()
					return 1 - shown()
				end,
				-- Longer than the streak texture: its window starts at the corner and it is tiled across.
				Components.Panel({ Brackets = 5, TexturePhase = Vector2.zero, Wide = true, Tall = true }, {
					Name = "Panel",
					Position = UDim2.fromOffset(Layout.MARGIN, Layout.MARGIN),
					Size = UDim2.new(1, -2 * Layout.MARGIN, 1, -2 * Layout.MARGIN),
					create("Frame")({
						Name = "Header",
						Size = UDim2.new(1, 0, 0, Layout.HEADER_RULE.Y),
						BackgroundTransparency = 1,
						ClipsDescendants = true,
						ZIndex = 2,
						create("Frame")({
							Name = "Title",
							Position = function()
								return UDim2.fromOffset(-math.round(Timing.TITLE_SLIDE * away()), 0)
							end,
							Size = UDim2.fromScale(1, 1),
							BackgroundTransparency = 1,
							Components.Icon("Settings", {
								AnchorPoint = Vector2.new(0.5, 0.5),
								Position = UDim2.fromOffset(Layout.HEADER_ICON.X, Layout.HEADER_ICON.Y),
								Size = Components.GlyphBox(Layout.HEADER_ICON_SIZE),
								ImageColor3 = Palette.Pink,
								ImageTransparency = away,
								ZIndex = 2,
							}),
							label({
								Position = UDim2.fromOffset(Layout.TITLE.X, Layout.TITLE.Y),
								Size = UDim2.fromOffset(400, Layout.TITLE_SIZE),
								TextSize = Layout.TITLE_SIZE,
								TextTransparency = away,
								Text = "SETTINGS",
							}),
						}),
					}),
					rule(
						UDim2.fromOffset(Layout.HEADER_RULE.X, Layout.HEADER_RULE.Y),
						Layout.HEADER_RULE_WIDTH,
						function()
							return since(Timing.RULE_DELAY, Timing.RULE)
						end
					),
					closeButton(actions),
					section(1),
					section(2),
					rule(UDim2.fromOffset(Layout.SECTION_X, Layout.FOOTER_RULE_Y), Layout.SECTION_WIDTH, function()
						return since(Timing.FOOTER_DELAY - 0.1, Timing.RULE)
					end),
					label({
						Name = "Hint",
						Position = UDim2.fromOffset(Layout.HINT.X, Layout.HINT.Y),
						Size = UDim2.fromOffset(400, Layout.HINT_SIZE),
						FontFace = Font.DisplayBold,
						TextSize = Layout.HINT_SIZE,
						TextTransparency = footer,
						Text = "CHANGES SAVE AUTOMATICALLY",
						TextColor3 = function()
							local flash = saved()
							return Palette.Lavender:Lerp(Palette.White, flash * flash)
						end,
					}),
					Controls.ResetSlab("RESET ALL", hasChanges, actions.AskResetAll, {
						Position = UDim2.fromOffset(
							Layout.RESET_ALL.X + Layout.RESET_ALL_SIZE.X / 2,
							Layout.RESET_ALL.Y + Layout.RESET_ALL_SIZE.Y / 2
						),
						Size = UDim2.fromOffset(Layout.RESET_ALL_SIZE.X, Layout.RESET_ALL_SIZE.Y),
						ZIndex = 3,
					}),
				}),
			}),
			rows,
		}),
		Confirm.Build(state, actions),
	})
end

return SettingsUI
