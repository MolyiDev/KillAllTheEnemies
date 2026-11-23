-- The daily rewards' rules, the same on both sides (DailyRewardsService decides, DailyRewardsController shows): one
-- reward a UTC day, 28 of them in four weeks of seven, each week ending on a gun. Missing one day is forgiven; missing
-- two sends the streak back to day 1, and after day 28 it starts again. The profile keeps the last day claimed and
-- the UTC day it was claimed on (TProfile.Daily).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LoadoutCore = require(ReplicatedStorage.GlobalShared.Core.LoadoutCore)
local TData = require(ReplicatedStorage.Types.TData)
local TProfile = require(ReplicatedStorage.Types.TProfile)

-- A day's reward: Gems, or a gun by its data Name, which pays its Gems instead once the gun is owned.
export type TReward = {
	Gems: number,
	Gun: string?,
}

local DailyRewardsCore = {}

DailyRewardsCore.DAYS = 28
DailyRewardsCore.WEEK = 7
DailyRewardsCore.WEEKS = 4
DailyRewardsCore.DAY_SECONDS = 86400
-- Whole UTC days that may go by between two claims before the streak breaks: two days apart is one missed and kept.
DailyRewardsCore.MAX_GAP = 2

DailyRewardsCore.REWARDS = table.freeze({
	{ Gems = 50 },
	{ Gems = 75 },
	{ Gems = 100 },
	{ Gems = 150 },
	{ Gems = 200 },
	{ Gems = 250 },
	{ Gun = "RPG Bazooka", Gems = 750 },
	{ Gems = 75 },
	{ Gems = 100 },
	{ Gems = 150 },
	{ Gems = 200 },
	{ Gems = 250 },
	{ Gems = 300 },
	{ Gun = "Snowy Rifle", Gems = 750 },
	{ Gems = 100 },
	{ Gems = 150 },
	{ Gems = 200 },
	{ Gems = 250 },
	{ Gems = 300 },
	{ Gems = 400 },
	{ Gun = "Hacker Drum", Gems = 1500 },
	{ Gems = 150 },
	{ Gems = 200 },
	{ Gems = 250 },
	{ Gems = 300 },
	{ Gems = 400 },
	{ Gems = 500 },
	{ Gun = "UFO Bullpup", Gems = 1500 },
} :: { TReward })

-- The UTC day number of a moment (os.time()).
function DailyRewardsCore.Today(time: number): number
	return time // DailyRewardsCore.DAY_SECONDS
end

-- Seconds from `time` until the next UTC day starts.
function DailyRewardsCore.SecondsLeft(time: number): number
	return (DailyRewardsCore.Today(time) + 1) * DailyRewardsCore.DAY_SECONDS - time
end

-- The day of the cycle a player with `daily` is on, on UTC day `today`, and whether it is still to be claimed: today's
-- if it was claimed, else the one after the last claim, or day 1 when there was none or the streak broke.
function DailyRewardsCore.Current(daily: TProfile.TDaily?, today: number): (number, boolean)
	if not daily then return 1, true end
	if daily.LastDay == today then return daily.Day, false end
	if today - daily.LastDay > DailyRewardsCore.MAX_GAP then return 1, true end
	return daily.Day % DailyRewardsCore.DAYS + 1, true
end

-- The gun day `day` gives, nil for a day of Gems.
function DailyRewardsCore.GunOf(day: number): TData.TGun?
	local reward = DailyRewardsCore.REWARDS[day]
	local name = if reward then reward.Gun else nil
	return if name then LoadoutCore.ByName[name] else nil
end

-- The week a day of the cycle falls in, 1 to WEEKS.
function DailyRewardsCore.WeekOf(day: number): number
	return (day - 1) // DailyRewardsCore.WEEK + 1
end

-- Every gun reward must name a gun, or its day would pay only the Gems and nobody would notice.
for day, reward in DailyRewardsCore.REWARDS do
	if reward.Gun and not LoadoutCore.ByName[reward.Gun] then
		warn(`[DailyRewardsCore] day {day} names no gun: {reward.Gun}`)
	end
end

return table.freeze(DailyRewardsCore)
