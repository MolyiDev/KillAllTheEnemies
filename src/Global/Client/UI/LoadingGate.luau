-- Between the loading screen (ReplicatedFirst's LoadingScreen.client) and the place's controllers: the screen says
-- when its assets are in, the place says when its first screen has what it needs (the lobby: the profile; a run: the
-- match started) and what it is waiting for meanwhile, and the screen says when it starts lifting off the world, so
-- what comes in next (the lobby's HUD) is seen arriving rather than played under the cover. Both sides require it by
-- the StarterPlayer path, so they share one copy.
local LoadingGate = {}

local DEADLINE_SECONDS = 120

LoadingGate.IsLoaded = false
LoadingGate.IsReady = false
LoadingGate.IsLifted = false
-- The words under the bar once the assets are in, while the place gets ready.
LoadingGate.Waiting = "GETTING READY"

local loadedCallbacks: { () -> () } = {}
local liftedCallbacks: { () -> () } = {}
local waitingCallbacks: { (text: string) -> () } = {}

-- Calls `callback` once the screen's assets are in (or it gave up on them, was skipped or never ran), at once if they
-- are: what a run's start waits on from every player, so nothing starts under the cover.
function LoadingGate.OnLoaded(callback: () -> ())
	if LoadingGate.IsLoaded then
		callback()
		return
	end
	table.insert(loadedCallbacks, callback)
end

-- Calls `callback` once the screen starts lifting off the world, at once if it has (or never covered it).
function LoadingGate.OnLifted(callback: () -> ())
	if LoadingGate.IsLifted then
		callback()
		return
	end
	table.insert(liftedCallbacks, callback)
end

-- Calls `callback` with the waiting words now and each time they change.
function LoadingGate.OnWaiting(callback: (text: string) -> ())
	table.insert(waitingCallbacks, callback)
	callback(LoadingGate.Waiting)
end

function LoadingGate.SetWaiting(text: string)
	if text == LoadingGate.Waiting then return end
	LoadingGate.Waiting = text
	for _, callback in waitingCallbacks do
		task.spawn(callback, text)
	end
end

-- Only the first call counts.
function LoadingGate.MarkLoaded()
	if LoadingGate.IsLoaded then return end
	LoadingGate.IsLoaded = true
	for _, callback in loadedCallbacks do
		task.spawn(callback)
	end
	table.clear(loadedCallbacks)
end

function LoadingGate.MarkReady()
	LoadingGate.IsReady = true
end

-- Only the first call counts.
function LoadingGate.MarkLifted()
	if LoadingGate.IsLifted then return end
	LoadingGate.IsLifted = true
	-- Lifted before its load was done (skipped, broken, past the deadline): the world is in view, so it counts.
	LoadingGate.MarkLoaded()
	for _, callback in liftedCallbacks do
		task.spawn(callback)
	end
	table.clear(liftedCallbacks)
	table.clear(waitingCallbacks)
end

-- A screen that broke or never ran must not keep the HUD out for good: past this (counted from the client's start)
-- the gate lifts itself.
task.delay(math.max(0, DEADLINE_SECONDS - time()), LoadingGate.MarkLifted)

return LoadingGate
