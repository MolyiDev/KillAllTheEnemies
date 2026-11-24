-- Where the lobby screens' panels start, in his 1920 x 1080 (each screen's page is scaled whole into the middle of the
-- screen): GAP under whichever reaches lower, Roblox's top bar or the lobby's top row (the Gems counter, in its own gui
-- from the screen's top at the HUD's scale). A panel never starts higher than this, and never lower than his layout
-- put it: on a phone the bar already reaches past his tops, so nothing moves there.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local vide = require(ReplicatedStorage.Packages.vide)
local Hud = require(script.Parent.Parent.Controllers.LobbyController.Hud)

local camera = Workspace.CurrentCamera

local DESIGN = Vector2.new(1920, 1080)
local GAP = 32

local panelTop = {}

-- The panels' top in design px.
panelTop.Top = vide.source(0)

-- How far a panel his layout puts at `designTop` is raised (and grown, its bottom staying put).
function panelTop.Lift(designTop: number): () -> number
	return function(): number
		return math.max(0, designTop - panelTop.Top())
	end
end

local function update()
	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then return end

	local scale = math.min(viewport.Y / DESIGN.Y, viewport.X / DESIGN.X)
	local pageTop = (viewport.Y - DESIGN.Y * scale) / 2
	local rowBottom = Hud.TOP_ROW_BOTTOM * Hud.ScaleFor(viewport.Y, GuiService:GetGuiInset().Y)
	local reach = math.max(GuiService.TopbarInset.Max.Y, rowBottom)
	panelTop.Top(math.round((reach - pageTop) / scale + GAP))
end

camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(update)
update()

return panelTop
