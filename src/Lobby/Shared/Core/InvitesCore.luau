-- Invites, as both sides see them: the tag the surprise gift's toast puts on its invite (ExperienceInviteOptions'
-- LaunchData), which Roblox hands the friend who joins through it (Player:GetJoinData().LaunchData).
local InvitesCore = {}

InvitesCore.GIFT_LAUNCH_DATA = "InviteGift"

return table.freeze(InvitesCore)
