-- The settings screen's rows, as they go over the wire (Settings.SetVolume / SetToggle). Never reused.
return table.freeze({
	MusicVolume = 1,
	SoundEffectsVolume = 2,
	MenuSoundsVolume = 3,
	IsCameraShakeReduced = 4,
	IsDragFireToAim = 5,
	ShouldShowDamageNumbers = 6,
	ShouldShowDebugInfo = 7,
})
