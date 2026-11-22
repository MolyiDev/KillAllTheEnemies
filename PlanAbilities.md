# Classes and abilities (plan)

Each class has **2 abilities and 1 ultimate**. **Human is built** (2026-11-21, unplayed) and is every player's
class: `AbilityService`, `AbilityController`, `Data/Classes/Human.luau`; Q Decoy ($40 a use), E Foam Cannon ($50), G Orbital Cannon
(free, filled by kills; the console's `ult` fills it). The defenses are hidden from the HUD and their keys unbound. The other classes are design only.

## The old Game place

9 classes (Survivor, Scout, Demolitionist, Engineer, Reaper, Outbreak, Warden, Stormcaller, Phantom), each with 3
abilities (Q / E / F) and a passive, no ultimates (`research/Review-Combat.md` 1.2). The starting class is
**Survivor** (Common, price 0, `ClassesConfig.Default`): Adrenaline (move and reload speed), Quick Heal, Last Stand
(damage resistance below 30% health) and Scavenger (passive, never implemented).

Not kept: all three are self-buffs where a number goes up and nothing happens on screen. **Human** replaces it as the
starting class.

Old classes whose work can be reused: Outbreak -> Zombie, Phantom -> Ghost, Reaper -> Vampire (Soul Harvest already
heals on kills).

## The fantasy

Monsters hunting monsters: everybody starts Human, and unlocking a class reads as getting bitten or turned.

- **Players must never look like enemies.** In a crowd of 255 a teammate who reads as a zombie gets lost, and players
  keep their own avatar. The class shows as light touches (a vampire cape, a ghostly trail, a zombie tint on the
  clothes); a full body change happens only during an ultimate, which is also the moment people film.
- **Each class needs enemies of its family in the waves.** The roster today (Basic, Fast, Heavy, Exploding, Slammer,
  CorruptedChampion) is not themed yet.

## The rule for every kit

- **The ultimate arrives with a big moment, pays off right away, and doubles one of the class's abilities while it
  lasts** (the model: a medic whose Rescue van heals everyone to full, crashes through enemies and doubles Adrenaline).
- Each class leans one way: it kills crowds, or it carries the team.
- No grenade or turret abilities: turrets are already DefenseService's, and a grenade is planned as an upgrade card.
- An ultimate's meter fills from kills, not a timer.

## Human (crowd killer, plus one utility)

Humans are the only class with no powers, so their power is gadgets.

- **Q: Decoy.** Throw an inflatable doll of your own avatar that squeaks. Every monster in range swarms it until it
  pops. Pulls a crowd into one clump, or off a downed teammate. The old Scout's Flare already lured enemies through
  the flowfield, and NavService has a field for targets that are not players.
- **E: Foam Cannon.** Spray industrial expanding foam over a cone. It hardens around monsters and sets them in place
  as stiff blocks for a few seconds. Set foam is brittle: they take extra damage, and a stuck monster that dies
  cracks apart into foam bricks. Alternative: **Net Launcher**, a weighted net that drops over a crowd and ties it up.
- **Ult: Orbital Cannon.** A sky strike on a fixed spot would be Survive a Million Monkeys' Airstrike; this one
  **hunts**:
  1. **Target:** hold up a remote; a thin red pixel dot tracks the ground and a faint guide beam drops from the sky
     for about a second.
  2. **Fire:** a fat white-core beam slams down: flash, a square shockwave ring, heavy screen shake.
  3. **Hunt:** for about 6 s, it goes after the nearest boss in reach, else the thickest crowd, on its own at a capped
     speed, while the caster keeps shooting. Damage per tick
     above 4x a normal enemy's health, so they hit the overkill burst and blow apart into bricks instead of
     ragdolling.
  4. **End:** the beam thins to a line and fades, leaving glowing embers on the ground.

  The beam reaches the sky, so every player sees it from anywhere on the map. One `DamageMultiple` per tick from a
  spatial-hash query; a sweep through 255 bodies is mostly a brick-and-corpse budget question.

Combo: Decoy clumps the crowd, Foam Cannon locks it, Orbital Cannon deletes it.

## Zombie (crowd killer through chain reactions)

- **Q: Spit.** Lob a glob of green goo. Monsters it hits are infected: damage over time, and when they die they pop
  and infect the monsters around them.
- **E: Pounce.** Leap onto a spot and slam it. Each monster bitten on landing heals you.
- **Ult: Outbreak.** A scream, the ground cracks green, and every monster in a wide radius is infected and turns on
  its own kind for 8 s. When it ends, every turned monster bursts at once and each burst infects the ones nearby: one
  cast can chain through half a wave. **Spit has no cooldown** during it.

## Vampire (crowd killer who keeps the team alive)

- **Q: Bat Swarm.** Burst into bats and fly through the crowd in a line, biting everything on the way.
- **E: Blood Drain.** Red tethers latch onto up to 5 nearby monsters and drain them. The health is shared with nearby
  teammates.
- **Ult: Blood Rain.** The sky turns red and it rains over the whole map. Every monster bleeds, and every hit on a
  bleeding monster heals whoever landed it. When the rain stops, **every monster below 30% health bursts at once**.
  **Bat Swarm has no cooldown** during it.

## Ghost (utility: saves the team, then punishes)

- **Q: Phase.** Go untouchable and drift through monsters. Anything you pass through is chilled and slowed.
- **E: Haunt.** A scream: monsters in range flee from the players in terror for a few seconds. The panic button.
- **Ult: Witching Hour.** The lights drop and a bell tolls. **Every downed teammate gets up**, and the whole team
  turns into ghosts for 8 s: nobody can be hurt, everyone walks through monsters, and every monster a ghost passes
  through takes heavy damage. **Haunt reaches the whole map** during it.

## Werewolf (pure brawler)

- **Q: Lunge.** A leaping claw strike that tears through a line of monsters.
- **E: Howl.** Damage and speed for you and every teammate in earshot.
- **Ult: Full Moon.** The moon rises and you change into a huge wolf for 10 s (the full body change only ultimates
  get). Every claw swipe mows an arc out of the crowd, **each kill resets Lunge**, and **Howl's buff is doubled**.

## What it costs to build

- **Haunt** is cheap: the monsters walk up their flowfield instead of down it.
- **Outbreak** needs monsters that can fight monsters: new targeting work.
- **Full Moon** needs a wolf body swapped in for the ult.
- **The marks** (infected, bleeding, foamed) tint each enemy's own Highlight: nothing new may use a Highlight, so the
  255 cap holds.
- **Blood** is red glowing pixels and bricks, not liquid, in keeping with the toy look.
- Every area hit is one `DamageMultiple` per tick, never one call per enemy.
