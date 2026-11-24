-- Reset and availability timers: the two largest units that apply ("20d 20h", "8h 20m", "5m 12s", "42s").

local function pair(major: number, majorUnit: string, minor: number, minorUnit: string): string
	if minor == 0 then return `{major}{majorUnit}` end

	return `{major}{majorUnit} {minor}{minorUnit}`
end

return function(seconds: number): string
	-- Whole seconds rounded up, so the timer never reads 0s while time is left, and never prints "42.3s".
	seconds = math.max(0, math.ceil(seconds))

	if seconds < 60 then return `{seconds}s` end
	if seconds < 3600 then return pair(seconds // 60, "m", seconds % 60, "s") end
	if seconds < 86400 then return pair(seconds // 3600, "h", seconds % 3600 // 60, "m") end

	return pair(seconds // 86400, "d", seconds % 86400 // 3600, "h")
end
