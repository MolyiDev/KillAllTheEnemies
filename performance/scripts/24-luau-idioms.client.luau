-- LUAU IDIOM MICROBENCHMARKS - driver.
--
-- Answers the questions where https://luau.org/performance and this repo's CLAUDE.md disagree, plus a set
-- of idioms CLAUDE.md is silent on. Pure CPU: no instances are created, nothing renders, so the 240 FPS cap
-- (METHODOLOGY trap 2) and the viewport (trap 9) are irrelevant here. What DOES matter:
--
--   * Studio deprioritises an unfocused window, so focus is still tracked and flagged (trap 1).
--   * Allocation-heavy suites (C, D, E) pay real GC assist costs. That is the point - it is what shipping
--     code pays - but it makes those rows noisier, hence median AND min are both reported.
--   * Ordering drift (trap 5) is controlled by rotating the variant order every repetition rather than by a
--     sentinel, since every variant here is cheap enough to run 11 times.
--
-- The suites live in three child ModuleScripts with byte-identical bodies and different headers:
--
--   SuitesO1      no directive             what every script in this repo gets today
--   SuitesO2      --!optimize 2            inlining, loop unrolling, aggressive constant folding
--   SuitesNative  --!native --!optimize 2  the above plus native codegen
--
-- Run: drop this in StarterPlayerScripts with the three modules as children, disable
-- StarterPlayerScripts.Client and ServerScriptService.Server, press F5, keep Studio focused.

local UserInputService = game:GetService("UserInputService")

local REPS = 11
local WARMUPS = 3
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

-- one repetition of one variant, in isolation
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

	-- warm up every variant first, so no variant pays first-call costs the others already paid
	for k = 1, count do
		for _ = 1, WARMUPS do
			local _, checksum = timeOnce(variants[k].Fn)
			checksums[k] = checksum
		end
		task.wait()
	end

	-- rotate the starting variant every repetition so ordering drift is spread evenly
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
	end

	print(string.format("\n== [%s] %s   (Ops = %d per run) ==", modeName, suite.Name, suite.Ops))
	print(string.format("   %-32s %9s %9s %9s %8s   %s", "variant", "med ms", "min ms", "ns/op", "x best", "checksum"))
	for k = 1, count do
		print(
			string.format(
				"   %-32s %9.4f %9.4f %9.2f %8.2f   %s",
				variants[k].Name,
				meds[k] * 1000,
				mins[k] * 1000,
				meds[k] / suite.Ops * 1e9,
				meds[k] / best,
				tostring(checksums[k])
			)
		)
	end
end

task.wait(SETTLE_SECONDS)

print("===== luau idiom microbenchmarks =====")
print(string.format("reps=%d warmups=%d  (median over reps, variant order rotated each rep)", REPS, WARMUPS))

for m = 1, #MODES do
	local mode = MODES[m]
	local module = script:FindFirstChild(mode.Child)
	if not module then
		warn(string.format("missing %s - skipping mode %s", mode.Child, mode.Name))
		continue
	end

	print(string.format("\n\n########## MODE %s   %s ##########", mode.Name, mode.Header))

	local ok, suites = pcall(require, module)
	if not ok then
		warn(string.format("mode %s failed to load: %s", mode.Name, tostring(suites)))
		continue
	end

	for s = 1, #suites do
		local suiteOk, err = pcall(runSuite, suites[s], mode.Name)
		if not suiteOk then warn(string.format("[%s] suite %d errored: %s", mode.Name, s, tostring(err))) end
	end
end

if focusLost then warn("*** FOCUS WAS LOST DURING THIS RUN - re-run it ***") end

print("\n===== done =====")
