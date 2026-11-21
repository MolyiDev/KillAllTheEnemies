-- LUAU IDIOM MICROBENCHMARKS, PASS 2 - driver.
--
-- Pass 1 (24) left three rows unresolved:
--
--   * the lerp suite used `i % 13` to build its arguments, and floating point modulo is expensive enough
--     that all five call forms landed within 4% of each other on min. Pass 2 reads the arguments out of a
--     pre-filled array instead, and adds a "loop + read only" floor row so the marginal cost of the call
--     can be subtracted out rather than guessed at.
--   * the mutable-global suite read `workspace.Gravity`, and that Instance property read (~40-56ns) buries
--     the global lookup it was supposed to measure. Pass 2 tests only the lookup, via `if workspace then`.
--   * the object-construction suite is allocation-bound and its medians move with GC assists. Pass 2 runs
--     it again at 21 reps and reports x-min alongside x-med so a GC-dragged median is visible.
--
-- It also carries a non-timing probe: whether a trivial local function gets inlined into its caller with
-- NO --!optimize 2 directive. Inlining is a level 2 optimization, so if the O1 copy reports it, Roblox is
-- already compiling at level 2 and the directive does nothing.
--
-- Same run procedure as 24 - see scripts/README.md.

local UserInputService = game:GetService("UserInputService")

local REPS = 21
local WARMUPS = 4
local SETTLE_SECONDS = 2.0

local MODES = {
	{ Name = "O1", Child = "SuitesO1", Header = "(no directive)" },
	{ Name = "O2", Child = "SuitesO2", Header = "--!optimize 2" },
	{ Name = "NATIVE", Child = "SuitesNative", Header = "--!native --!optimize 2" },
}

local focusLost = false
UserInputService.WindowFocusReleased:Connect(function()
	focusLost = true
	warn("*** FOCUS LOST *** every number after this point is suspect")
end)

local function median(values)
	table.sort(values)
	local n = #values
	if n % 2 == 1 then return values[(n + 1) // 2] end
	return (values[n // 2] + values[n // 2 + 1]) / 2
end

local function timeOnce(fn)
	local t0 = os.clock()
	local checksum = fn()
	local t1 = os.clock()
	return t1 - t0, checksum
end

local function runSuite(suite, modeName)
	local variants = suite.Variants
	local count = #variants

	local samples = table.create(count)
	local checksums = table.create(count)
	for k = 1, count do
		samples[k] = table.create(REPS)
	end

	for k = 1, count do
		for _ = 1, WARMUPS do
			local _, checksum = timeOnce(variants[k].Fn)
			checksums[k] = checksum
		end
		task.wait()
	end

	for rep = 1, REPS do
		for k = 1, count do
			local idx = (rep + k - 2) % count + 1
			local elapsed, checksum = timeOnce(variants[idx].Fn)
			local bucket = samples[idx]
			bucket[#bucket + 1] = elapsed
			checksums[idx] = checksum
			task.wait()
		end
	end

	local meds = table.create(count)
	local mins = table.create(count)
	local best = math.huge
	local bestMin = math.huge
	for k = 1, count do
		local m = median(samples[k])
		meds[k] = m
		local lo = math.huge
		local bucket = samples[k]
		for j = 1, #bucket do
			if bucket[j] < lo then lo = bucket[j] end
		end
		mins[k] = lo
		if m < best then best = m end
		if lo < bestMin then bestMin = lo end
	end

	print(string.format("\n== [%s] %s   (Ops = %d per run) ==", modeName, suite.Name, suite.Ops))
	print(
		string.format(
			"   %-32s %9s %9s %9s %8s %8s   %s",
			"variant",
			"med ms",
			"min ms",
			"ns/op",
			"x med",
			"x min",
			"checksum"
		)
	)
	for k = 1, count do
		print(
			string.format(
				"   %-32s %9.4f %9.4f %9.2f %8.2f %8.2f   %s",
				variants[k].Name,
				meds[k] * 1000,
				mins[k] * 1000,
				meds[k] / suite.Ops * 1e9,
				meds[k] / best,
				mins[k] / bestMin,
				tostring(checksums[k])
			)
		)
	end
end

task.wait(SETTLE_SECONDS)

print("===== luau idiom microbenchmarks, pass 2 =====")
print(string.format("reps=%d warmups=%d", REPS, WARMUPS))

for m = 1, #MODES do
	local mode = MODES[m]
	local module = script:FindFirstChild(mode.Child)
	if not module then
		warn(string.format("missing %s", mode.Child))
		continue
	end

	print(string.format("\n\n########## MODE %s   %s ##########", mode.Name, mode.Header))

	local ok, payload = pcall(require, module)
	if not ok then
		warn(string.format("mode %s failed to load: %s", mode.Name, tostring(payload)))
		continue
	end

	local probeOk, direct, wrapped = pcall(payload.Probe)
	if probeOk then
		print(
			string.format(
				"   INLINE PROBE  direct=%d wrapped=%d  ->  %s",
				direct,
				wrapped,
				if wrapped == direct then "WRAPPER WAS INLINED" else "no inlining, wrapper kept its frame"
			)
		)
	else
		warn("   INLINE PROBE failed: " .. tostring(direct))
	end

	for s = 1, #payload.Suites do
		local suiteOk, err = pcall(runSuite, payload.Suites[s], mode.Name)
		if not suiteOk then warn(string.format("[%s] suite %d errored: %s", mode.Name, s, tostring(err))) end
	end
end

if focusLost then warn("*** FOCUS WAS LOST DURING THIS RUN - re-run it ***") end

print("\n===== done =====")
