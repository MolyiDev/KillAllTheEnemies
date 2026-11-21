-- The shape of a ground warning (Enemies.Telegraph), sent as a u8. TelegraphCore holds what each one covers.
--   Circle  a disc of the sent radius that fills in over the wind-up, then the hit.
--   Ring    a disc's outline for the wind-up, then a band expanding from the centre at the sent speed.
--   Cone    a sector of the sent radius and full angle (TelegraphCore.CONE_ANGLES), apex at the centre.
--   Line    a rectangle of the sent length and width, from the centre forward.
return table.freeze({
	Circle = 1,
	Ring = 2,
	Cone = 3,
	Line = 4,
})
