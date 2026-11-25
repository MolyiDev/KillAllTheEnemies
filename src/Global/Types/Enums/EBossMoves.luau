-- What a boss's body is doing, sent as a u8 with Bosses.Move (instance, move, attack index, from, to, value, tempo) so the
-- client plays its clips, drives its body where the server moves it and throws its effects. Append only.
--   Attack      one of its attacks began: the index into TEnemy.Attacks, `from` where it stands, value its yaw, its
--               clip and beats `tempo` times as long as authored.
--   ChargeRun   it runs the charge's line from `from` to `to` at value studs a second.
--   Skid        it bleeds the run (value studs a second) off from `from` to `to` over TEnemyBoss.SkidStop.
--   ChargeTurn  it turns round on the spot to the yaw in value over TEnemyBoss.TurnLength, ending in the launch pose.
--   DiveSink    it sinks into the floor where it stands.
--   DiveRise    it bursts up at `to`, facing the yaw in value.
--   Spine       one spine of a volley flies off its back and lands on `to` in value seconds.
--   Crack       the dive's crack runs along the floor from `from` to `to` over value seconds.
--   Pace        it walks at value times its own speed from now (slowed by foam; 1 when let go).
return table.freeze({
	Attack = 1,
	ChargeRun = 2,
	Skid = 3,
	ChargeTurn = 4,
	DiveSink = 5,
	DiveRise = 6,
	Spine = 7,
	Crack = 8,
	Pace = 9,
})
