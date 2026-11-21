-- Starts the forked PlayerModule (camera and controls). StarterPlayer.CreateDefaultPlayerModule is off in every place,
-- so the engine neither builds its own module nor inserts a loader: without this script no camera or control code runs.
require(script.Parent:WaitForChild("PlayerModule"))
