local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local GeneratorCore = require(ReplicatedStorage.Shared.Core.GeneratorCore)
local Grid = require(ReplicatedStorage.GlobalShared.Utils.Grid)
local enemiesUpdateServer = require(ServerScriptService.Server.Utils.enemiesUpdateServer)

-- Module-level query iterator state (per-worker; avoids allocating a fresh
-- closure on every "Run" message). Set before each enemiesUpdateServer call,
-- which drains the iterator synchronously before the next message runs.
local qEntities: { number } = {}
local qColumns: any = {}
local qIndex = 0
local qCount = 0
local auditPhase,auditMs,auditRows,auditCalls="",0,0,0

local function queryNext(): (number, vector, vector, number, vector, number, number, number)
	if qIndex >= qCount then return nil :: any end
	qIndex += 1
	local i = qIndex
	return qEntities[i],
		qColumns[1][i],
		qColumns[2][i],
		qColumns[3][i],
		qColumns[4][i],
		qColumns[5][i],
		qColumns[6][i],
		qColumns[7][i]
end

return function(actor: Actor)
	local grid: Grid.Grid<GeneratorCore.GridCell>

	actor:BindToMessageParallel("Grid", function(_grid: Grid.Grid<any>)
		grid = Grid.fromGrid(_grid)
	end)

	actor:BindToMessageParallel(
		"Run",
		function(
			caller: Actor,
			charPositions: { [number]: vector },
			bubbleCenters: { vector },
			bubbleRadii: { number },
			buckets: buffer,
			records: buffer,
			columns,
			entities: { number },
			dt: number
		)
			qEntities = entities
			qColumns = columns
			qIndex = 0
			qCount = #entities
			local phase=if workspace:GetAttribute("BallarcAuditCapture") then workspace:GetAttribute("BallarcAuditPhase") else ""
 if phase~=auditPhase then
  if auditCalls>0 then print("[BALLARC_WORKER] "..auditPhase.." "..auditMs.." "..auditRows.." "..auditCalls) end
  auditPhase,auditMs,auditRows,auditCalls=phase,0,0,0
 end
 local auditStarted=os.clock()
 local entitiesTable = enemiesUpdateServer(
				caller,
				charPositions,
				bubbleCenters,
				bubbleRadii,
				buckets,
				records,
				dt,
				grid,
				queryNext
			)

			if phase~="" then auditMs+=(os.clock()-auditStarted)*1000;auditRows+=#entities;auditCalls+=1 end
 caller:SendMessage("Receive", entitiesTable)
		end
	)
end

