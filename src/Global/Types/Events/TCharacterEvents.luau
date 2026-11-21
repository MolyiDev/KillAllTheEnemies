local ReplicatedStorage = game:GetService("ReplicatedStorage")
local jecs = require(ReplicatedStorage.Packages.jecs)
local TCharacter = require(ReplicatedStorage.Types.TCharacter)

export type OnCharacterAdded = (character: TCharacter.TCharacter, characterEntity: jecs.Entity<any>) -> ()
export type OnCharacterRemoving = (character: TCharacter.TCharacter, characterEntity: jecs.Entity<any>) -> ()

return {}
