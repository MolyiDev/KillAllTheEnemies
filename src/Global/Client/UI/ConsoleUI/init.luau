-- The conch command console's window: a log, an input line with autocomplete, opened by the key bind_to binds.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Conch = require(ReplicatedStorage.Packages.conch)
local Vide = require(ReplicatedStorage.Packages.vide)
local Theme = require(script.Parent.Theme)

local create = Vide.create
local source = Vide.source
local derive = Vide.derive
local effect = Vide.effect
local cleanup = Vide.cleanup
local changed = Vide.changed
local root = Vide.root

local BACKGROUND = Color3.fromRGB(20, 20, 20)
local TEXT = Color3.fromHex("#eeeeee")
local TEXT_ERROR = Color3.fromHex("#f76b6e")
local TEXT_INFO = Color3.fromHex("#56a6e4")
local TEXT_WARN = Color3.fromHex("#e8b736")
local FONT = Theme.Font.Mono

local function textColor(style: string): Color3
	if style == "warn" then return TEXT_WARN end
	if style == "error" then return TEXT_ERROR end
	if style == "info" then return TEXT_INFO end
	return TEXT
end

local function levenshteinDistance(strA: string, strB: string): number
	local rows, cols = #strA, #strB
	if rows == 0 then return cols end
	if cols == 0 then return rows end
	if strA == strB then return 0 end

	local matrix = table.create(rows + 1)
	for i = 0, rows do
		matrix[i] = table.create(cols + 1, 0)
		matrix[i][0] = i
	end
	for j = 1, cols do
		matrix[0][j] = j
	end

	for i = 1, rows do
		for j = 1, cols do
			local cost = if string.byte(strA, i) == string.byte(strB, j) then 0 else 2
			matrix[i][j] = math.min(matrix[i - 1][j] + 3, matrix[i][j - 1] + 1, matrix[i - 1][j - 1] + cost)
		end
	end

	return matrix[rows][cols]
end

-- Module-level state shared across bind_to calls
local opened = source(false)
local focused = source(false)
local logs = source({})

local historyN = 0
local history = {}

local function output(values: { kind: string, text: string })
	local current = logs()
	for _, line in string.split(values.text, "\n") do
		table.insert(current, 1, { kind = values.kind, text = line })
		if #current > 99 then table.remove(current) end
	end
	logs(current)
end

Conch.console.output = output
output({ kind = "warn", text = "If you got here accidentally, run the `exit` command to close this UI." })

Conch.register("clear", {
	description = "Clears the console.",
	permissions = {},
	arguments = function() end,
	callback = function()
		logs({})
	end,
})

Conch.register("exit", {
	description = "Close the CLI",
	permissions = {},
	arguments = function() end,
	callback = function()
		opened(false)
		focused(false)
	end,
})

local function app()
	local rawText = source("")
	local working = source(false)
	local cursorPosition = source(0)
	local absolutePosition = source(Vector2.zero)
	local analysis = source(Conch.analyze("", 0))
	local selectedSuggestion = source(1)

	effect(function()
		selectedSuggestion(math.clamp(selectedSuggestion(), 1, math.max(1, #analysis().suggestions)))
	end)

	local isDeferred = false
	effect(function()
		rawText()
		cursorPosition()
		if isDeferred then return end
		isDeferred = true
		task.defer(function()
			isDeferred = false
			analysis(Conch.analyze(rawText(), cursorPosition() - 1))
		end)
	end)

	local beforeText = derive(function()
		return string.sub(rawText(), 1, cursorPosition() - 1)
	end)

	local suggestionPosition = source(vector.zero)
	local bounds = Instance.new("GetTextBoundsParams")
	bounds.Font = FONT
	bounds.RichText = false
	bounds.Size = 20
	bounds.Width = 100000

	effect(function()
		local t = beforeText()
		bounds.Text = t
		task.spawn(function()
			local s = TextService:GetTextBoundsAsync(bounds)
			if t ~= beforeText() then return end
			suggestionPosition(s)
		end)
	end)

	local function autofill(text: string, span: vector, with: string): string
		local before = string.sub(text, 1, span.x)
		local after = string.sub(text, span.y + 1, -1)
		task.defer(cursorPosition, span.x + #with + 2)
		return before .. with .. " " .. after
	end

	local inputConnection = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape then
			opened(false)
			focused(false)
			return
		end

		local result = analysis()
		if input.KeyCode == Enum.KeyCode.Down then
			if #result.suggestions == 0 then
				if historyN == 0 then history[historyN] = rawText() end
				historyN = math.clamp(historyN - 1, 0, #history)
				rawText(history[historyN] or "")
				cursorPosition(#rawText() + 1)
			else
				selectedSuggestion(math.min(selectedSuggestion() + 1, #result.suggestions))
			end
		elseif input.KeyCode == Enum.KeyCode.Up then
			if #result.suggestions == 0 then
				if historyN == 0 then history[historyN] = rawText() end
				historyN = math.clamp(historyN + 1, 0, #history)
				rawText(history[historyN] or "")
				cursorPosition(#rawText() + 1)
			else
				selectedSuggestion(math.max(1, selectedSuggestion() - 1))
			end
		end
	end)
	cleanup(function()
		inputConnection:Disconnect()
	end)

	local filteredSuggestions = derive(function()
		local result = analysis()
		if not result or not result.suggestions then return {} end

		local input = string.sub(rawText(), result.replace.x + 1, cursorPosition() - 1)
		input = string.gsub(input, `"(.*)"`, "%1", 1)
		input = string.gsub(input, `'(.*)'`, "%1", 1)

		local scored = {}
		for _, suggestion in result.suggestions do
			if not string.find(suggestion.display, string.gsub(input, "^%s", ""), 0, true) then continue end
			local score = levenshteinDistance(input, suggestion.display)
			if score == -math.huge then continue end
			scored[#scored + 1] = { suggestion = suggestion, score = score }
		end

		table.sort(scored, function(a, b)
			return a.score < b.score
		end)

		local out = table.create(#scored)
		for i = 1, #scored do
			out[i] = scored[i].suggestion
		end
		return out
	end)

	local nextCursorPosition: false | number = false

	local loadingDt = source(0)
	local loadingSteps = { "-", "/", "|", "\\" }
	local loadingThread = task.spawn(function()
		while true do
			loadingDt(loadingDt() + task.wait())
		end
	end)
	cleanup(function()
		task.cancel(loadingThread)
	end)

	local inputText = source("")
	local textbox = create("TextBox")({
		AutomaticSize = Enum.AutomaticSize.XY,
		Text = rawText,
		PlaceholderText = "Enter your command",
		TextSize = 18,
		TextColor3 = TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = FONT,
		BackgroundTransparency = 1,
		Visible = function()
			return not working()
		end,

		changed("Text", function(text)
			local position = nextCursorPosition or cursorPosition()
			local at = string.sub(text, position - 1, position - 1)
			local sel = filteredSuggestions()[selectedSuggestion()]

			if at == "\t" and sel then text = autofill(rawText(), analysis().replace, sel.text) end

			rawText(text)
			inputText(text)
		end),

		Focused = function()
			focused(true)
		end,

		FocusLost = function(enter)
			focused(false)
			if not enter then return end
			local value = inputText()
			historyN = 0
			table.insert(history, 1, value)
			rawText("")
			focused(true)
			working(true)
			Conch.execute(value)
			working(false)
		end,

		CursorPosition = cursorPosition,
		changed("CursorPosition", function(new)
			if nextCursorPosition then
				nextCursorPosition = new
				return
			end
			nextCursorPosition = new
			task.defer(function()
				cursorPosition(nextCursorPosition)
				nextCursorPosition = false
			end)
		end),
	})

	effect(function()
		local value = focused()
		if textbox:IsFocused() == value then return end
		task.defer(function()
			if value then
				textbox:CaptureFocus()
			else
				textbox:ReleaseFocus(false)
			end
		end)
	end)

	return create("ScreenGui")({
		Name = "Command Executor",
		Enabled = opened,
		DisplayOrder = 100_000,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,

		-- Suggestion popup - direct child of ScreenGui so it positions absolutely on screen
		create("Frame")({
			Name = "SuggestionPopup",
			Size = UDim2.fromOffset(300, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			AnchorPoint = Vector2.new(0, 1),
			BackgroundTransparency = 1,
			ZIndex = 10000,
			Position = function()
				local parts = string.split(beforeText(), "\n")
				local x = 10 * #parts[#parts] + 10
				local y = suggestionPosition().Y + absolutePosition().Y - 20
				return UDim2.fromOffset(x, y)
			end,
			Visible = function()
				local result = analysis()
				return #result.suggestions > 0 or result.additional_info ~= nil
			end,

			create("UIListLayout")({
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
			}),

			-- Suggestion list
			create("Frame")({
				LayoutOrder = 0,
				Size = UDim2.fromOffset(200, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = BACKGROUND,
				BackgroundTransparency = 0,
				Visible = function()
					return #filteredSuggestions() > 0
				end,

				create("UIListLayout")({
					SortOrder = Enum.SortOrder.LayoutOrder,
					VerticalAlignment = Enum.VerticalAlignment.Bottom,
				}),

				Vide.values(filteredSuggestions, function(suggestion, key)
					return create("TextLabel")({
						Size = UDim2.fromOffset(200, 20),
						LayoutOrder = key,
						Text = suggestion.display,
						TextSize = 16,
						TextColor3 = function()
							return if key() == selectedSuggestion() then TEXT_INFO else TEXT
						end,
						FontFace = FONT,
						TextXAlignment = Enum.TextXAlignment.Left,
						BackgroundTransparency = 1,

						create("UIPadding")({ PaddingLeft = UDim.new(0, 4) }),
					})
				end),
			}),

			-- Additional info panel
			create("Frame")({
				LayoutOrder = 10,
				Size = UDim2.fromOffset(300, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = BACKGROUND,
				BackgroundTransparency = 0,
				Visible = function()
					return analysis().additional_info ~= nil
				end,

				create("UIListLayout")({ SortOrder = Enum.SortOrder.LayoutOrder }),

				create("Frame")({
					LayoutOrder = 0,
					Size = UDim2.fromOffset(300, 24),
					BackgroundColor3 = BACKGROUND,
					BackgroundTransparency = 0,

					create("UIListLayout")({
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween,
						VerticalAlignment = Enum.VerticalAlignment.Center,
					}),
					create("UIPadding")({
						PaddingLeft = UDim.new(0, 4),
						PaddingRight = UDim.new(0, 4),
					}),

					create("TextLabel")({
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.fromOffset(0, 24),
						Text = function()
							local info = analysis().additional_info
							return if info then info.name or "" else ""
						end,
						TextSize = 20,
						TextColor3 = TEXT,
						FontFace = Font.new(FONT.Family, Enum.FontWeight.Bold),
						BackgroundTransparency = 1,
					}),
					create("TextLabel")({
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.fromOffset(0, 24),
						Text = function()
							local info = analysis().additional_info
							if not info then return "" end
							return `{info.type or ""}{if info.optional then "?" else ""}`
						end,
						TextSize = 18,
						TextColor3 = TEXT,
						FontFace = Font.new(FONT.Family, Enum.FontWeight.Light),
						BackgroundTransparency = 1,
					}),
				}),

				create("TextLabel")({
					LayoutOrder = 1,
					Size = UDim2.fromOffset(300, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Text = function()
						local info = analysis().additional_info
						return if info then info.description or "" else ""
					end,
					TextSize = 16,
					TextColor3 = TEXT,
					FontFace = FONT,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextWrapped = true,
					BackgroundTransparency = 1,

					create("UIPadding")({
						PaddingLeft = UDim.new(0, 4),
						PaddingRight = UDim.new(0, 4),
						PaddingTop = UDim.new(0, 4),
						PaddingBottom = UDim.new(0, 4),
					}),
				}),
			}),
		}),

		-- Main layout frame
		create("Frame")({
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,

			create("UIListLayout")({
				HorizontalFlex = Enum.UIFlexAlignment.Fill,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			create("UIPadding")({
				PaddingBottom = UDim.new(0.02, 0),
				PaddingLeft = UDim.new(0.005, 0),
				PaddingRight = UDim.new(0.005, 0),
				PaddingTop = UDim.new(0.02, 0),
			}),

			-- Logs + issues panel
			create("Frame")({
				LayoutOrder = 1,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = BACKGROUND,
				BackgroundTransparency = 0,

				create("UIListLayout")({ SortOrder = Enum.SortOrder.LayoutOrder }),
				create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
				create("UIPadding")({
					PaddingTop = UDim.new(0, 4),
					PaddingBottom = UDim.new(0, 4),
				}),

				Vide.values(function()
					return analysis().issues
				end, function(issue, key)
					return create("TextLabel")({
						Size = UDim2.fromOffset(0, 20),
						AutomaticSize = Enum.AutomaticSize.X,
						LayoutOrder = function()
							return 100 - key()
						end,
						Text = `{issue.why} at {issue.span.x}:{issue.span.y}:{issue.span.z}`,
						TextSize = 16,
						TextColor3 = TEXT_ERROR,
						FontFace = FONT,
						TextXAlignment = Enum.TextXAlignment.Left,
						BackgroundTransparency = 1,

						create("UIPadding")({
							PaddingLeft = UDim.new(0, 8),
							PaddingRight = UDim.new(0, 8),
						}),
					})
				end),

				Vide.values(logs, function(log, key)
					return create("TextLabel")({
						Size = UDim2.fromOffset(0, 20),
						AutomaticSize = Enum.AutomaticSize.X,
						LayoutOrder = function()
							return -key() - 1
						end,
						Text = log.text,
						TextSize = 16,
						TextColor3 = textColor(log.kind),
						FontFace = FONT,
						TextXAlignment = Enum.TextXAlignment.Left,
						BackgroundTransparency = 1,

						create("UIPadding")({
							PaddingLeft = UDim.new(0, 8),
							PaddingRight = UDim.new(0, 8),
						}),
					})
				end),
			}),

			-- Gap
			create("Frame")({
				LayoutOrder = 2,
				Size = UDim2.fromScale(1, 0.005),
				BackgroundTransparency = 1,
			}),

			-- Input panel
			create("Frame")({
				LayoutOrder = 3,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = BACKGROUND,
				BackgroundTransparency = 0,

				create("UICorner")({ CornerRadius = UDim.new(0, 4) }),
				create("UIListLayout")({
					HorizontalFlex = Enum.UIFlexAlignment.Fill,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					HorizontalAlignment = Enum.HorizontalAlignment.Left,
				}),
				create("UIPadding")({
					PaddingLeft = UDim.new(0, 8),
					PaddingRight = UDim.new(0, 8),
					PaddingTop = UDim.new(0, 8),
					PaddingBottom = UDim.new(0, 8),
				}),

				changed("AbsolutePosition", function(pos)
					absolutePosition(pos)
				end),

				-- Loading spinner
				create("TextLabel")({
					Size = UDim2.fromOffset(0, 18),
					AutomaticSize = Enum.AutomaticSize.X,
					Visible = working,
					Text = function()
						return `{loadingSteps[(loadingDt() * 6 // 1) % 4 + 1]} - {loadingDt() * 100 // 1 / 100}\ts`
					end,
					TextSize = 18,
					TextColor3 = TEXT,
					FontFace = FONT,
					TextXAlignment = Enum.TextXAlignment.Left,
					BackgroundTransparency = 1,
				}),

				textbox,
			}),
		}),
	})
end

local ConsoleUI = {}
local isMounted = false

local function mountApp()
	if isMounted then return end
	isMounted = true
	root(function()
		app().Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	end)
end

function ConsoleUI.bind_to(input: Enum.KeyCode | Enum.UserInputType)
	mountApp()
	UserInputService.InputBegan:Connect(function(inputObject)
		if inputObject.KeyCode ~= input and inputObject.UserInputType ~= input then return end
		opened(not opened())
		focused(opened())
	end)
end

ConsoleUI.opened = opened

return ConsoleUI
