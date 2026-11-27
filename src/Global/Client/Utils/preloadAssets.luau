-- Fetches `assets` (Instances or content ids) in parallel batches within a budget, for a loading screen. An image goes
-- in on an ImageLabel, never as a bare id: PreloadAsync fails every Image asset given as a string (9 of 9,
-- 2026-11-27). A request that fails still counts as returned, and requests already in the engine when the budget runs
-- out may finish in the background. Returns whether every request returned in time and how many failed. Completion is
-- counted, never waited on as a signal: a request may return before anything would have waited for it.
local ContentProvider = game:GetService("ContentProvider")

local BATCH_SIZE = 40
local MAX_PARALLEL = 6

-- `onProgress` hears the share of requests returned after each batch; `shouldStop` ends it early (a skip).
return function(
	assets: { any },
	timeoutSeconds: number,
	shouldStop: () -> boolean,
	onProgress: (share: number) -> ()
): (boolean, number)
	local total = #assets
	if total == 0 then return true, 0 end
	local deadline = os.clock() + timeoutSeconds
	local nextIndex = 1
	local completed = 0
	local failed = 0
	local isFinished = false

	for _ = 1, math.min(MAX_PARALLEL, math.ceil(total / BATCH_SIZE)) do
		task.spawn(function()
			while not isFinished and os.clock() < deadline and not shouldStop() do
				local first = nextIndex
				if first > total then break end
				local last = math.min(first + BATCH_SIZE - 1, total)
				nextIndex = last + 1
				local batch = table.create(last - first + 1)
				for index = first, last do
					batch[index - first + 1] = assets[index]
				end

				local ok = pcall(ContentProvider.PreloadAsync, ContentProvider, batch, function(_, status)
					if status ~= Enum.AssetFetchStatus.Success then
						failed += 1
					end
				end)
				if not ok then
					failed += 1
				end
				completed += #batch
				onProgress(completed / total)
			end
		end)
	end

	while completed < total and os.clock() < deadline and not shouldStop() do
		task.wait(0.05)
	end
	isFinished = true

	return completed >= total, failed
end
