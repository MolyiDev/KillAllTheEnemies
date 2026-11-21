local ReplicatedStorage = game:GetService("ReplicatedStorage")
local jecs = require(ReplicatedStorage.Packages.jecs)

export type OnPlayerConnected = (player: Player, playerEntity: jecs.Entity<any>) -> ()
export type OnPlayerDisconnected = (player: Player, playerEntity: jecs.Entity<any>) -> ()
export type OnDataLoaded = (player: Player) -> ()

return {}
