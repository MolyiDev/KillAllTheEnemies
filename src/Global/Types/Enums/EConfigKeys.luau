-- Roblox Experience Config keys (Creator Hub > Configs), read via ConfigsCore.Observe. Every key needs its value in
-- MainConfig.json, which tools/configs/upload.py publishes; the upload refuses a key missing here.
return table.freeze({
	Enemies = "Enemies",
	-- Server only (ConfigsService never sends it): the redeemable codes.
	Codes = "Codes",
})
