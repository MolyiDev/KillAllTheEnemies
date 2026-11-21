# UI Matt: UI design catalogue

Source: `UI Matt.rbxl` (designer place file, 2026-11). It was extracted with lune 0.10.4 `@lune/roblox`. That runtime cannot read the file as saved: its rbx-dom expects `Tags` to be SharedString, so it chokes on the newer `Tags` type. The file was therefore rewritten first with every `Tags` PROP chunk dropped (all of them were empty; no GUI instance carries tags or attributes). The extraction scripts are in `tools/uimatt/` (`strip.py` writes `clean.rbxl`, then `dump.luau`, `format.py`, `models.luau`), run from a scratch working directory.

**How it is built here (decided 2026-11-20): every screen is ported to vide, in code.** The file is the visual spec,
not a source of instances or images: panels, corners, strokes, gradients, shadows and button states are drawn with
`UICorner` / `UIStroke` / `UIGradient` and layouts, labels are live text (none baked into art), and hover / press
are designed in code. An image is used only for what code cannot draw (an icon, an illustration); it is made, saved
under `Assets/ui/` and uploaded to group 34796361 with the rest. Never reference the designer's image ids: they are
private to another account and will not load in this game.

## 1. Where the UI lives

- **All UI is in `StarterGui`**: 19 ScreenGuis and 2,307 instances. `Workspace` holds only the default Baseplate and SpawnLocation. `ReplicatedStorage`, `ReplicatedFirst`, `ServerStorage`, `StarterPlayer`, `StarterPack` and `ServerScriptService` are empty. There are no SurfaceGuis or BillboardGuis.
- **Every ScreenGui uses the same settings:** `ResetOnSpawn=false`, `ScreenInsets=DeviceSafeInsets`, `ZIndexBehavior=Sibling` and `DisplayOrder=0`. All are `Enabled=false` except `Lobby HUD`.
- **Each ScreenGui is one mock-up state of a screen, not a component library.** Some are variants of another: `In-Game HUD - Squad Open` is the HUD plus the squad overlay, `Settings - Reset Confirm` is Settings plus a modal, and `Quests - Daily` / `Quests - Weekly` are the two tabs of one screen.
- **Design resolution: 1920x1080.** Every container's `UIAspectRatioConstraint` matches its scale size at 1080p. The `px[...]` rects below were measured at 1920x1080 with rur.

| ScreenGui | Place | Purpose (inferred from the text it shows) |
| --- | --- | --- |
| Lobby HUD | Lobby | Lobby overlay. Top left: level/XP bar ("LV 9", "6,200 / 10,000"). Top right: currency bar (coins 48,250, energy "85 / 100", + button). Left rail: Daily Rewards, Shop, Daily Spins, Invite Friends. Bottom: Weapons / Menu / Classes buttons. |
| Weapons Shop | Lobby | Weapon armory ("WEAPONS · UPGRADE YOUR ARSENAL"). Tier 1-4 tabs, a weapon list split into owned and not owned with prices, a 3D stage preview, a skin selector, and an info panel with rarity, type, name, 3 stats with bonuses, upgrade cost, and Upgrade / Try / Show / Equipped buttons. |
| Robux Shop | Lobby | Premium shop ("SHOP · DEALS REFRESH DAILY"). Category tabs (Featured, Bundles, Gamepasses, Credits, Gems), 2 featured cards (limited weapon, bundle) with countdowns, and 4 gem packs. |
| Index | Lobby | Bestiary ("INDEX · DISCOVER EVERY ENEMY"). Categories (Monsters, Bosses) with found counts, completion and a reward title, an enemy grid with locked "???" entries, and an enemy info panel (description, defeated count, location, health, threat). |
| Classes | Lobby | Class picker ("CLASSES · PICK YOUR PLAYSTYLE"). Classes/Equipment top tabs, a class list of 7 (rarity, price, equipped state), a stage preview, and class info with 3 ability cards and an ability stat-upgrade preview. |
| Equipment | Lobby | Cosmetic gear ("EQUIPMENT · GEAR UP FOR THE HORDE"). Slot filter (All, Head, Torso, Legs), a 9-item grid, a stage preview, worn slots, and item info (stat +10 MAX HP, description, "Show on character" toggle). |
| Settings | Both | Settings modal. Audio sliders (Music, SFX, Menu sounds), camera toggles (reduce shake, drag fire to aim), and display name. Every row has its own reset button, plus a Reset All. |
| Settings - Reset Confirm | Both | Settings plus a second dim and the "RESET ALL SETTINGS?" confirm modal (Cancel / Confirm). |
| Quests - Daily | Lobby | Quest board, Daily tab: 5 quest rows (name, description, progress, gem reward, claim) and Claim All. |
| Quests - Weekly | Lobby | The same board on the Weekly tab. |
| Daily Rewards | Lobby | 28-day login calendar paged by week (Week 1-4). Day cards in claimed, claim-now and locked states; the day 7 card is a big weapon reward ("RPG · LEGENDARY WEAPON"). |
| Daily Spins | Lobby | Daily/Spin tabbed modal, on the Spin tab: a horizontal prize reel of 7 reward cards (coins, tokens, x2 coins for 15 min). It is a reel, not a wheel. Also "2 free spins left today", a spin button, the next-free-spin timer and the token balance. |
| Player Head Tag | Game (and lobby?) | 3 sample overhead nameplates (name, class tag, LV, two stat chips). Laid out as ScreenGui frames; in code these become BillboardGuis. |
| Upgrade Selection | Game | Pick-one-of-3 upgrade cards after a wave ("WAVE 5 CLEARED · CHOOSE ONE"): number, NEW tag, name, description, rarity; Reroll; "AUTO-PICK IN 8". |
| In-Game HUD | Game | Run HUD. Wave counter and next boss, next-wave countdown, skip-wave vote and auto-skip, Squad and Settings buttons, Heal All / Nuke All items, buyable upgrades (left), Robux money products, abilities with keybinds and ult charge (right), round money, 5-slot hotbar. |
| In-Game HUD - Squad Open | Game | The HUD plus a dim and the squad scoreboard (player, class, kills, deaths, cash, contraband). |
| Monster Mutation | Lobby | "MUTATION LAB · COMBINE MONSTER ENERGY INTO POTIONS". Mutate/Potions tabs, energy inventory, potion result card, pick-2 energy selection grid, brew cost. |
| Lobby Entering | Lobby | Post-match summary shown on return to the lobby: level-up bar, XP breakdown (waves, kills, new best, bosses, bounties), 2 player cards (MVP), match stats. |
| Round Results | Game | End-of-run modal ("SQUAD WIPED", returning in 20). Wave reached, squad kills, time, gems earned, double-gems offer (Robux or ad), Return to Lobby / Play Again / vote count / Revive, "UPGRADES AVAILABLE" tag. |

## 2. Construction conventions (apply to every screen)

The file is a Figma-style export, and that fixes how it has to be rebuilt:

- **All styling is baked into PNGs.** There is not a single `UICorner`, `UIStroke`, `UIGradient`, `UIPadding`, `UIListLayout`, `UIGridLayout`, `UISizeConstraint`, `ScrollingFrame`, `TextBox` or `TextButton` in any screen. The only `UICorner`, `UIGradient` and `UIPadding` in the file are Roblox's default chat-bubble children under `TextChatService.BubbleChatConfiguration`. Corner radii, strokes, gradients, panel fills and shadows therefore exist only inside the image assets (see §4).
- **Element pattern.** A Frame or ImageButton is the logical hit box. Its child `Art [ImageLabel]` draws the visuals, usually bigger than the box, because each PNG carries a drop shadow or glow. The bleed is asymmetric: more below than above, so the shadow sits lower. TextLabels sit as siblings of `Art` at a higher ZIndex.
- **Common `Art` bleeds**, written as Art P / S relative to the box:
  - `P(-0.0694,-0.1667) S(1.1389,1.4762)`: ×21, the currency pills and lobby menu buttons.
  - `P(-0.6,-0.45) S(2.2,2.2)`: ×12, small round buttons.
  - `P(-0.1578,-0.1182) S(1.315,1.3371)`: ×10, HUD upgrade and ability cards.
  - Example: on the 230x67 px coin pill the art bleeds 16 px left and right, 11 px above and 21 px below. That is a shadow of roughly 16 px blur with a +5 px y-offset.
- **ImageButtons have no image of their own.** Every one is `AutoButtonColor=false` and transparent; the visuals are in the `Art` child. There are no HoverImage or PressedImage states, so hover and press feedback has to be designed in code.
- **94 of 197 ImageButtons contain no TextLabel: their label text is baked into the PNG.** Examples: Upgrade, Equip, Claim, Spin, Brew, Play Again, Revive, Watch Ad, Exit, Reset, and the Robux Shop `Price Button` (the R$ price itself is baked in). These cannot be localised or made dynamic as they stand. A code version needs text-free button art plus a live label.
- **All 572 text elements are TextLabels**, every one with `TextScaled=true`, `TextWrapped=true`, `TextYAlignment=Top`. All are `TextXAlignment=Left` except 5 marked `align=Center`. Every TextLabel has a `UITextSizeConstraint`, written `max=N`; it has no MinTextSize. Text boxes are cut tight to each string, so a scaled label is sized by its box and `max` is only a cap. To rebuild with fixed sizes, size from box height × 1080, not from `max`.
- **Font:** Montserrat (`rbxasset://fonts/families/Montserrat.json`) in two weights only: Heavy (503 labels) and Bold (69). No other font and no italic.
- **No layout objects.** Every position is absolute scale. Repeated rows and cards are hand-placed copies with hand-set ZIndex. Text-fit boxes make label sizes differ by a few thousandths between copies. Lists will need `UIListLayout` / `UIGridLayout` in code.
- **Other uniform properties:** the only non-transparent backgrounds are the `Dim Overlay UI` frames: `#000000` at 0.4-0.7 transparency (0.7 on lobby modals, 0.6 on upgrade selection, 0.5 on squad and results). `BorderSizePixel=0` everywhere. Every ImageLabel is `Interactable=false`. Every `UIAspectRatioConstraint` is `DominantAxis=Height` with the default `AspectType`. `ScaleType` is Stretch everywhere (no 9-slice), with no `ImageColor3` tint and no `ImageTransparency`. No `Visible=false`, no `LayoutOrder`, no `ClipsDescendants`.
- **Only 4 TextLabels set unusual properties:**
  - `Rotation=-8` on the "✓ CLAIMED" stamp and `Rotation=4` on the "PERMANENT" tag (Daily Rewards).
  - `TextTransparency=0.7` on the claimed day's reward value, and `0.1` on the squad "HOVER YOURS TO DROP" hint.
- **Placeholders:** `Stage Container › Image`, `Player Container › Image` and `Skin Container › Image` are flat screenshots standing in for 3D or ViewportFrame content: weapon, class and character previews.

### Legend for the trees

`Name [Class]` then only the non-default properties:

| Notation | Meaning |
| --- | --- |
| `P(x, y)` / `S(w, h)` | Position / Size as UDim2 scale, offsets 0. A `{xs,xo},{ys,yo}` form appears where offsets are set; none are. |
| `A(x, y)` | AnchorPoint. |
| `zN` | ZIndex (Sibling behaviour, so relative to siblings; omitted = 1). |
| `"text"` | Text, followed by the weight (`Heavy` / `Bold`, Montserrat), TextColor3 hex, `max=` MaxTextSize and `align=Center` where not Left. |
| `img:ID` | `ImageContent` rbxassetid. |
| `AR=` | A child `UIAspectRatioConstraint` (DominantAxis Height). |
| `bg=` / `bgT=` | BackgroundColor3 / BackgroundTransparency, only where the background is visible. |
| `px[x,y wxh]` | Absolute rect at 1920x1080, on top-level containers only. |

Collapsing works in three ways:

- `⤷ ×N siblings like "X"`: the siblings share X's tree (same classes, names apart from digits, fonts and constraints). Each copy is listed with what differs: P / S / z / Text / TextColor3 / img, with paths relative to the copy.
- `= identical to Screen › Node`: the subtree matches one printed earlier exactly.
- `≈ Screen › Node, differs: …`: the same structure, with the listed differences.

## 3. Screens

### Lobby HUD (49 instances)

```
Lobby HUD [ScreenGui] ResetOnSpawn=False ScreenInsets=DeviceSafeInsets ZIndexBehavior=Sibling
  Level Container [Frame] P(0.0193, 0.0398) S(0.2512, 0.0835) AR=5.347  px[37,43 482x90]
    Art [ImageLabel] P(-0.051, -0.1951) S(1.1022, 1.5477) img:95385927520034
    Objective Label [TextLabel] P(0.4856, 0.2217) S(0.0649, 0.2661) z2 "XP" Bold #FFC13B max=40
    Round State Container [Frame] P(0.0464, 0.2106) S(0.9077, 0.5854) z3
      Art [ImageLabel] S(1, 1) img:103060127131943
      Round Info Container [Frame] P(0.1042, 0) S(0.8958, 1) z2
        Round Timer [TextLabel] P(0, 0.0758) S(0.2423, 0.8333) z2 "LV 9" Bold #FFC13B max=72
        Objective Progress Container [Frame] P(0.3391, 0) S(0.6609, 1) z3
          Art [ImageLabel] S(1, 1) img:132354210830277
          Objective Count [TextLabel] P(0.4222, 0.0189) S(0.6, 0.4545) z2 "6,200 / 10,000" Bold #FFFFFF align=Center max=40
  Currency Container [Frame] P(0.986, 0.0528) S(0.288, 0.0622) A(1, 0) z2 AR=8.2292  px[1340,57 553x67]
    Coins Container [Frame] S(0.4166, 1) z2
      Art [ImageLabel] P(-0.0694, -0.1667) S(1.1389, 1.4762) img:133212127550433
      Price Container 01 [Frame] P(0.1745, 0.2842) S(0.651, 0.4315) z2
        Art [ImageLabel] S(1, 1) img:124051185775739
        Button Label [TextLabel] P(0.36, 0) S(0.6912, 1) z2 "48,250" Heavy #FFFFFF max=48
    Add Currency Button [ImageButton] P(0.8767, 0) S(0.1233, 1) z3
      Art [ImageLabel] S(1, 1) img:117488698850227
    Energy Container [Frame] P(0.4383, 0) S(0.4166, 1) z4
      Art [ImageLabel] P(-0.0694, -0.1667) S(1.1389, 1.4762) img:127612138989771
      Price Container 01 [Frame] P(0.151, 0.2634) S(0.707, 0.4836) z2
        Art [ImageLabel] S(1, 1) img:86413066371189
        Button Label [TextLabel] P(0.3186, 0.0431) S(0.7359, 0.8923) z2 "85 / 100" Heavy #FFFFFF max=48
  Left Menu Container [Frame] P(0.0127, 0.497) S(0.0865, 0.631) A(0, 0.5) z3 AR=0.2436  px[24,196 166x681]
    Daily Rewards Button [ImageButton] P(0, 0.2568) S(1, 0.2296) z2
      Art [ImageLabel] P(-0.0554, -0.1214) S(1.1102, 1.1776) img:127246397724885
    Shop Button [ImageButton] P(0.1, 0) S(0.7994, 0.2296) z3
      Art [ImageLabel] P(-0.1944, -0.1214) S(1.3888, 1.1776) img:73853576426051
    Daily Spins Button [ImageButton] P(0.1, 0.5136) S(0.7994, 0.2296) z4
      Art [ImageLabel] P(-0.1944, -0.1214) S(1.3888, 1.1776) img:128090333006940
    Invite Friends Button [ImageButton] P(0.0301, 0.7704) S(0.9398, 0.2296) z5
      Art [ImageLabel] P(-0.091, -0.1214) S(1.1814, 1.1776) img:122739019370404
  Bottom Menu Container [Frame] P(0.4959, 0.9391) S(0.6137, 0.1011) A(0.5, 1) z4 AR=10.7912  px[363,905 1178x109]
    Menu Button [ImageButton] P(0.3381, 0) S(0.3177, 1) z2
      Art [ImageLabel] P(-0.0694, -0.1667) S(1.1389, 1.4762) img:135852007616651
    Weapons Button [ImageButton] S(0.3177, 1) z3
      Art [ImageLabel] P(-0.0694, -0.1667) S(1.1389, 1.4762) img:130257945394564
    Classes Button [ImageButton] P(0.6823, 0) S(0.3177, 1) z4
      Art [ImageLabel] P(-0.0694, -0.1667) S(1.1389, 1.4762) img:98610907786270
```

### Weapons Shop (173 instances)

```
Weapons Shop [ScreenGui] Enabled=False ResetOnSpawn=False ScreenInsets=DeviceSafeInsets ZIndexBehavior=Sibling
  Title Container [Frame] P(0.0232, 0.037) S(0.1643, 0.0731) AR=3.9937  px[44,40 315x79]
    Art [ImageLabel] S(1, 1) img:82244686436632
    Title Label [TextLabel] P(0.1632, 0) S(0.9037, 0.7089) z2 "WEAPONS" Heavy #FFFFFF max=92
    Subtitle Label [TextLabel] P(0.2393, 0.7722) S(0.7702, 0.2278) z3 "UPGRADE YOUR ARSENAL" Bold #FFC13B max=30
  Currency Container [Frame] ≈ Lobby HUD › Currency Container  px[1327,52 553x67], differs: P(0.9792, 0.0481)
  Tier Container [Frame] P(0.5, 0.0315) S(0.3518, 0.1148) A(0.5, 0) z3 AR=5.4476  px[622,34 676x124]
    Art [ImageLabel] S(1, 1) img:135859983790952
    Tier Card 01 [ImageButton] S(0.2272, 1) z2
      Art [ImageLabel] P(-0.1681, -0.1484) S(1.3355, 1.4274) img:117154288608064
      Item Label [TextLabel] P(0.3466, 0.746) S(0.3307, 0.1371) z2 "TIER 1" Heavy #FFFFFF max=28
      ⤷ ×4 siblings like "Tier Card 01" (same tree); per-copy differences:
        · Tier Card 02: P(0.2576, 0.0048); z3; S(0.2272, 0.9903); Art img:94958630353516; Art P(-0.1681, -0.1547); Art S(1.3355, 1.4414); Item Label P(0.3401, 0.7484); Item Label "TIER 2"; Item Label S(0.3448, 0.1384)
        · Tier Card 03: P(0.5152, 0.0048); z4; S(0.2272, 0.9903); Art img:75316907530001; Art P(-0.1681, -0.1547); Art S(1.3355, 1.4414); Item Label #B9A9D9; Item Label P(0.3401, 0.7484); Item Label "TIER 3"; Item Label S(0.3448, 0.1384)
        · Tier Card 04: P(0.7728, 0.0048); z5; S(0.2272, 0.9903); Art img:125548802721747; Art P(-0.1681, -0.1547); Art S(1.3355, 1.4414); Item Label #B9A9D9; Item Label P(0.3336, 0.7484); Item Label "TIER 4"; Item Label S(0.3588, 0.1384)
  Weapon List Container [Frame] P(0.0186, 0.5695) S(0.2335, 0.7946) A(0, 0.5) z4 AR=0.5224  px[36,186 448x858]
    Art [ImageLabel] P(-0.0549, -0.0205) S(1.11, 1.0576) img:82511536364357
    Tier 1 Header [Frame] P(0.0629, 0.0332) S(0.8744, 0.0474) z2
      Art [ImageLabel] S(1, 1) img:74747094875955
      Tier 1 Label [TextLabel] P(0.0816, 0) S(0.2094, 0.7125) z2 "TIER 1" Heavy #FFFFFF max=48
      4  8 Owned Label [TextLabel] P(0.7372, 0.1351) S(0.2838, 0.4423) z3 "4 / 8 OWNED" Bold #FFC13B max=30
    Owned Label [TextLabel] P(0.0629, 0.1025) S(0.1686, 0.021) z3 "OWNED" Heavy #B9A9D9 max=30
    Owned Count UI [Frame] P(0.2458, 0.0979) S(0.058, 0.0303) z4
      Art [ImageLabel] S(1, 1) img:75012799070771
      4 Label [TextLabel] P(0.3077, 0.1923) S(0.4154, 0.6154) z2 "4" Heavy #0D0A1C max=27
    Weapon Card 01 [ImageButton] P(0.0477, 0.1335) S(0.2978, 0.1874) z5
      Art [ImageLabel] P(-0.1933, -0.1182) S(1.3858, 1.3371) img:123404956544074
      Item Label [TextLabel] P(0.2562, 0.8141) S(0.5258, 0.0933) z2 "BAYONET" Heavy #FFFFFF max=24
      ⤷ ×4 siblings like "Weapon Card 01" (same tree); per-copy differences:
        · Weapon Card 02: P(0.3511, 0.1335); z6; Art img:73436236494805; Item Label P(0.3198, 0.8141); Item Label "PISTOL"; Item Label S(0.3883, 0.0933)
        · Weapon Card 03: P(0.6545, 0.1335); z7; Art img:117416028118163; Item Label P(0.2262, 0.8141); Item Label "POW POW"; Item Label S(0.5906, 0.0933)
        · Weapon Card 04: P(0.0477, 0.3263); z8; Art img:90195836579340; Art P(-0.1933, -0.1136); Art S(1.3858, 1.3272); Item Label P(0.23, 0.8117); Item Label "REVOLVER"; Item Label S(0.5825, 0.0926)
    Not Owned Label [TextLabel] P(0.0629, 0.543) S(0.2746, 0.021) z9 "NOT OWNED" Heavy #B9A9D9 max=30
    Not Owned Count UI [Frame] P(0.344, 0.5383) S(0.058, 0.0303) z10
      Art [ImageLabel] S(1, 1) img:132079874668558
      4 Label [TextLabel] P(0.3077, 0.1923) S(0.4154, 0.6154) z2 "4" Heavy #FFFFFF max=27
    Weapon Card 05 [ImageButton] P(0.0477, 0.574) S(0.2978, 0.1874) z11
      Art [ImageLabel] P(-0.1933, -0.1182) S(1.3858, 1.3371) img:101908562587014
      Item Label [TextLabel] P(0.2936, 0.8141) S(0.4449, 0.0933) z2 "SHORTY" Heavy #B9A9D9 max=24
      Price Label [TextLabel] P(0.3049, 0.1175) S(0.2912, 0.0933) z3 "5,000" Heavy #FFC13B max=24
      ⤷ ×4 siblings like "Weapon Card 05" (same tree); per-copy differences:
        · Weapon Card 06: P(0.3511, 0.574); z12; Art img:70432781426856; Item Label "DEAGLE"; Price Label "45,000"; Price Label S(0.364, 0.0933)
        · Weapon Card 07: P(0.6545, 0.574); z13; Art img:91149835129162; Item Label P(0.2674, 0.8141); Item Label "PHOENIX"; Item Label S(0.5016, 0.0933); Price Label "120,000"; Price Label S(0.3964, 0.0933)
        · Weapon Card 08: P(0.0477, 0.7674); z14; Art img:122676223998162; Item Label P(0.2712, 0.8141); Item Label "OUTLAW"; Item Label S(0.4935, 0.0933); Price Label "250,000"; Price Label S(0.4207, 0.0933)
  Weapon Info Container [Frame] P(0.9813, 0.5695) S(0.2335, 0.7946) A(1, 0.5) z5 AR=0.5224  px[1436,186 448x858]
    Art [ImageLabel] P(-0.0549, -0.0205) S(1.11, 1.0576) img:94894442574611
    Rarity Label [TextLabel] P(0.1109, 0.0414) S(0.1084, 0.0198) z2 "RARE" Heavy #FFFFFF max=28
    Type Label [TextLabel] P(0.2949, 0.0408) S(0.1542, 0.021) z3 "PISTOL" Heavy #8B5CFF max=30
    Weapon Name [TextLabel] P(0.0629, 0.0816) S(0.6408, 0.0653) z4 "REVOLVER" Heavy #FFFFFF max=92
    Stat Container 01 [Frame] P(0.0629, 0.2097) S(0.2737, 0.1025) z5
      Art [ImageLabel] S(1, 1) img:76249517702705
      Stat Label [TextLabel] P(0.1141, 0.1591) S(0.6425, 0.1705) z2 "DMG / SEC" Bold #B9A9D9 max=24
      Stat Value [TextLabel] P(0.1141, 0.4091) S(0.3345, 0.4205) z3 "75" Heavy #FFFFFF max=60
      Stat Bonus [TextLabel] P(0.4727, 0.5455) S(0.3433, 0.2045) z4 "+19.5" Heavy #33D980 max=30
      ⤷ ×2 siblings like "Stat Container 01" (same tree); per-copy differences:
        · Stat Container 02: P(0.3632, 0.2097); z6; Stat Label "DAMAGE"; Stat Label S(0.5369, 0.1705); Stat Value "50"; Stat Value S(0.3521, 0.4205); Stat Bonus P(0.489, 0.5455); Stat Bonus "+13"; Stat Bonus S(0.22, 0.2045)
    Stat Container 03 [Frame] P(0.6636, 0.2097) S(0.2737, 0.1025) z7
      Art [ImageLabel] S(1, 1) img:76249517702705
      Stat Label [TextLabel] P(0.1141, 0.1591) S(0.6249, 0.1705) z2 "FIRE RATE" Bold #B9A9D9 max=24
      Stat Value [TextLabel] P(0.1141, 0.4091) S(0.3609, 0.4205) z3 "90" Heavy #FFFFFF max=60
    Upgrade Header [Frame] P(0.0629, 0.3408) S(0.8744, 0.0474) z8
      Art [ImageLabel] S(1, 1) img:87233388169296
      Upgrade Label [TextLabel] P(0.0816, 0) S(0.3554, 0.7125) z2 "UPGRADE" Heavy #FFC13B max=48
      Lv 1    2 Label [TextLabel] P(0.8342, 0.1351) S(0.1791, 0.4423) z3 "LV 1  →  2" Bold #FFFFFF max=30
    Cost Value [TextLabel] P(0.286, 0.4195) S(0.1614, 0.0478) z9 "750" Heavy #FFC13B max=68
    Cost Currency [TextLabel] P(0.4533, 0.4381) S(0.1229, 0.0198) z10 "COINS" Heavy #FFC13B max=28
    Balance Label [TextLabel] P(0.286, 0.4777) S(0.2939, 0.0175) z11 "YOU HAVE 48,250" Bold #B9A9D9 max=24
    Upgrade Button [ImageButton] P(0.0513, 0.5393) S(0.8976, 0.1007) z12
      Art [ImageLabel] P(-0.0646, -0.2106) S(1.1292, 1.6019) img:138863731477205
    Try Button [ImageButton] P(0.0535, 0.776) S(0.4379, 0.0841) z13
      Art [ImageLabel] P(-0.1253, -0.2438) S(1.2511, 1.6842) img:113860369732059
    Show Button [ImageButton] P(0.5086, 0.776) S(0.4379, 0.0841) z14
      Art [ImageLabel] P(-0.1253, -0.2438) S(1.2511, 1.6842) img:109356623109379
    Equipped Button [ImageButton] P(0.0513, 0.8725) S(0.8976, 0.1007) z15
      Art [ImageLabel] P(-0.0646, -0.2106) S(1.1292, 1.6019) img:86162458886427
  Stage Container [Frame] P(0.5, 0.463) S(0.3125, 0.5556) A(0.5, 0.5) z6 AR=1  px[660,200 600x600]
    Image [ImageLabel] S(1, 1) img:117074096317449
  Skin Plate Container [Frame] P(0.5, 0.8039) S(0.2335, 0.0669) A(0.5, 1) z7 AR=6.2091  px[736,796 448x72]
    Art [ImageLabel] P(-0.0549, -0.2438) S(1.11, 1.6842) img:90010497710665
    Skin Title [TextLabel] P(0.0629, 0.3878) S(0.0891, 0.2216) z2 "SKIN" Heavy #B9A9D9 max=26
    Skin Name [TextLabel] P(0.1878, 0.2978) S(0.2843, 0.4017) z3 "DEFAULT" Heavy #FFFFFF max=48
    Skin Count [TextLabel] P(0.8481, 0.3463) S(0.0964, 0.3047) z4 "1 / 4" Heavy #FFFFFF max=36
  Skin Container [Frame] P(0.5, 0.8833) S(0.1706, 0.0741) A(0.5, 1) z8 AR=4.0938  px[796,874 327x80]
    Image [ImageLabel] P(-0.0788, -0.23) S(1.1576, 1.6625) img:115956195301386
  Exit Button [ImageButton] P(0.5, 0.9678) S(0.1617, 0.0744) A(0.5, 1) z9 AR=3.8607  px[805,965 310x80]
    Art [ImageLabel] P(-0.0838, -0.2264) S(1.1675, 1.6468) img:135962089193493
```

### Robux Shop (132 instances)

```
Robux Shop [ScreenGui] Enabled=False ResetOnSpawn=False ScreenInsets=DeviceSafeInsets ZIndexBehavior=Sibling
  Title Container [Frame] P(0.0217, 0.037) S(0.144, 0.0731) AR=3.4987  px[42,40 276x79]
    Art [ImageLabel] S(1, 1) img:122910304446957
    Title Label [TextLabel] P(0.1968, 0) S(0.5509, 0.7089) z2 "SHOP" Heavy #FFFFFF max=92
    Subtitle Label [TextLabel] P(0.2836, 0.7722) S(0.7737, 0.2278) z3 "DEALS REFRESH DAILY" Bold #FFC13B max=30
  Currency Container [Frame] ≈ Lobby HUD › Currency Container  px[1327,52 553x67], differs: P(0.9792, 0.0481)
  Shop Container [Frame] P(0.5, 0.5094) S(0.9627, 0.7298) A(0.5, 0.5) z3 AR=2.345  px[36,156 1848x788]
    Art [ImageLabel] P(-0.0133, -0.0223) S(1.0267, 1.0627) img:117101296521126
    Category Tab Container [Frame] P(0.1607, 0.0315) S(0.6781, 0.0893) z2
      Category Tab 01 [Frame] S(0.1966, 1) z2
        Art [ImageLabel] P(-0.1055, -0.2585) S(1.211, 1.7386) img:137281746135871
        Button Label [TextLabel] P(0.3174, 0.3295) S(0.5435, 0.3409) z2 "FEATURED" Heavy #FFFFFF max=40
        ⤷ ×5 siblings like "Category Tab 01" (same tree); per-copy differences:
          · Category Tab 02: P(0.2019, 0.017); z3; S(0.1949, 0.9688); Art img:119325174776269; Art P(-0.1007, -0.2581); Art S(1.2018, 1.7243); Button Label #B9A9D9; Button Label P(0.3447, 0.3226); Button Label "BUNDLES"; Button Label S(0.4863, 0.3519)
          · Category Tab 03: P(0.4029, 0.017); z4; S(0.1949, 0.9688); Art img:113666052844282; Art P(-0.1007, -0.2581); Art S(1.2018, 1.7243); Button Label #B9A9D9; Button Label P(0.2464, 0.3226); Button Label "GAMEPASSES"; Button Label S(0.6985, 0.3519)
          · Category Tab 04: P(0.604, 0.017); z5; S(0.1949, 0.9688); Art img:104210793573965; Art P(-0.1007, -0.2581); Art S(1.2018, 1.7243); Button Label #B9A9D9; Button Label P(0.3631, 0.3226); Button Label "CREDITS"; Button Label S(0.4465, 0.3519)
          · Category Tab 05: P(0.805, 0.017); z6; S(0.1949, 0.9688); Art img:131995510832205; Art P(-0.1007, -0.2581); Art S(1.2018, 1.7243); Button Label #B9A9D9; Button Label P(0.4368, 0.3226); Button Label "GEMS"; Button Label S(0.2874, 0.3519)
    Featured Header [Frame] P(0.0153, 0.1478) S(0.9695, 0.0516) z3
      Art [ImageLabel] S(1, 1) img:126133567391830
      Section Title [TextLabel] P(0.0179, 0) S(0.0838, 0.7125) z2 "FEATURED" Heavy #FFFFFF max=48
      Section Info [TextLabel] P(0.9308, 0.1351) S(0.0747, 0.4423) z3 "ENDS IN 2D 14H" Bold #FFC13B max=30
    Featured Card 01 [ImageButton] P(0.0116, 0.219) S(0.4856, 0.4704) z4
      Art [ImageLabel] P(-0.0287, -0.0512) S(1.0574, 1.1462) img:83259412357554
      Tag Label [TextLabel] P(0.0543, 0.1022) S(0.1456, 0.0458) z2 "NEW WEAPON" Heavy #FFFFFF max=28
        ⤷ ×5 siblings like "Tag Label" (same tree); per-copy differences:
          · Tag Label: #0D0A1C; P(0.0543, 0.5715); z5; "LEGENDARY"; S(0.1203, 0.0458)
          · Tag Label: #FFC13B; P(0.2058, 0.5715); z6; "MELEE WEAPON"; S(0.1625, 0.0458)
          · Tag Label: #FF2E8B; P(0.0543, 0.6901); z7; "+ SINGULARITY TITLE"; S(0.2106, 0.0458)
          · Tag Label: #FF2E8B; P(0.0543, 0.798); z8; "+ 250,000 GEMS"; S(0.1576, 0.0458)
      Featured Title 01 [TextLabel] P(0.0387, 0.198) S(0.2972, 0.1699) z3 "GRAVITY" Heavy #FFFFFF max=100
        ⤷ ×2 siblings like "Featured Title 01" (same tree); per-copy differences:
          · Featured Title 02: #FF2E8B; P(0.0387, 0.349); z4; "HAMMER"; S(0.3093, 0.1699)
      Price Button [ImageButton] P(0.6657, 0.7287) S(0.2968, 0.2006) z9
        Art [ImageLabel] P(-0.0976, -0.2446) S(1.1952, 1.6989) img:79711321775618
      ⤷ ×2 siblings like "Featured Card 01" (same tree); per-copy differences:
        · Featured Card 02: P(0.5028, 0.219); z5; Art img:108556591273891; Tag Label #0D0A1C; Tag Label "LIMITED BUNDLE"; Tag Label S(0.1685, 0.0458); Featured Title 01 "GUNSLINGER"; Featured Title 01 S(0.4368, 0.1699); Featured Title 02 #FFC13B; Featured Title 02 "BUNDLE"; Featured Title 02 S(0.2804, 0.1699); Tag Label#2 #FFFFFF; Tag Label#2 "EPIC"; Tag Label#2 S(0.0457, 0.0458); Tag Label#3 P(0.1367, 0.5715); Tag Label#3 "3 ITEMS"; Tag Label#3 S(0.077, 0.0458); Tag Label#4 #FFC13B; Tag Label#4 "+ OUTLAW CLASS"; Tag Label#4 S(0.1745, 0.0458); Tag Label#5 #FFC13B; Tag Label#5 "+ 100,000 GEMS"; Tag Label#5 S(0.1552, 0.0458); Price Button.Art img:76982159966074
    Gems Header [Frame] P(0.0153, 0.7137) S(0.9695, 0.0516) z6
      Art [ImageLabel] S(1, 1) img:137631189209311
      Section Title [TextLabel] P(0.0179, 0) S(0.0446, 0.7125) z2 "GEMS" Heavy #FFFFFF max=48
      Section Info [TextLabel] P(0.918, 0.1351) S(0.0886, 0.4423) z3 "BEST VALUE  +20%" Bold #FFC13B max=30
    Gem Pack Container [Frame] P(0.0116, 0.7798) S(0.9768, 0.1913) z7
      Gem Pack Card 01 [ImageButton] S(0.2456, 1) z2
        Art [ImageLabel] P(-0.0582, -0.126) S(1.1161, 1.3594) img:128812146012773
        Gem Amount [TextLabel] P(0.2902, 0.2845) S(0.2046, 0.2454) z2 "1,000" Heavy #FFFFFF max=60
        Gem Label [TextLabel] P(0.2902, 0.563) S(0.1145, 0.1127) z3 "GEMS" Heavy #9EBAD9 max=28
        Price Button [ImageButton] P(0.6302, 0.2798) S(0.3211, 0.4403) z4
          Art [ImageLabel] P(-0.1826, -0.2741) S(1.3652, 1.7831) img:137567530957986
        ⤷ ×4 siblings like "Gem Pack Card 01" (same tree); per-copy differences:
          · Gem Pack Card 02: P(0.2515, 0); z3; Art img:129484553498841; Gem Amount "5,500"; Gem Amount S(0.2143, 0.2454); Gem Label #33D980; Price Button.Art img:138508283109286
          · Gem Pack Card 03: P(0.5029, 0); z4; Art img:109435065174700; Gem Amount "12,000"; Gem Amount S(0.2508, 0.2454); Gem Label #8B5CFF; Price Button.Art img:138202877248174
          · Gem Pack Card 04: P(0.7544, 0); z5; Art img:101044918543698; Gem Amount "30,000"; Gem Amount S(0.2679, 0.2454); Gem Label #FFC13B; Price Button.Art img:123408593698389
  Exit Button [ImageButton] ≈ Weapons Shop › Exit Button  px[805,965 310x80], differs: z4
```

### Index (158 instances)

```
Index [ScreenGui] Enabled=False ResetOnSpawn=False ScreenInsets=DeviceSafeInsets ZIndexBehavior=Sibling
  Title Container [Frame] P(0.0273, 0.037) S(0.1477, 0.0731) AR=3.5899  px[52,40 284x79]
    Art [ImageLabel] S(1, 1) img:96313689585852
    Title Label [TextLabel] P(0.1537, 0) S(0.5979, 0.7089) z2 "INDEX" Heavy #FFFFFF max=92
    Subtitle Label [TextLabel] P(0.2384, 0.7722) S(0.8226, 0.2278) z3 "DISCOVER EVERY ENEMY" Bold #FFC13B max=30
  Currency Container [Frame] ≈ Lobby HUD › Currency Container  px[1327,52 553x67], differs: P(0.9792, 0.0481)
  Category List Container [Frame] P(0.0186, 0.5695) S(0.2335, 0.7946) A(0, 0.5) z3 AR=0.5224  px[36,186 448x858]
    Art [ImageLabel] P(-0.0549, -0.0205) S(1.11, 1.0576) img:90116331032962
    Categories Header [Frame] P(0.0629, 0.0332) S(0.8744, 0.0474) z2
      Art [ImageLabel] S(1, 1) img:102879682101068
      Section Title [TextLabel] P(0.0816, 0) S(0.4546, 0.7125) z2 "CATEGORIES" Heavy #FFFFFF max=48
      Section Info [TextLabel] P(0.8393, 0.1351) S(0.1736, 0.4423) z3 "2 TYPES" Bold #FFC13B max=30
    Category Card 01 [ImageButton] P(0.0477, 0.1025) S(0.9045, 0.1352) z3
      Art [ImageLabel] P(-0.0636, -0.1586) S(1.127, 1.4569) img:122107874079539
      Category Name [TextLabel] P(0.2779, 0.2586) S(0.4155, 0.2759) z2 "MONSTERS" Heavy #FFFFFF max=52
      Category Count [TextLabel] P(0.2779, 0.5991) S(0.293, 0.1466) z3 "4 / 13  FOUND" Bold #33D980 max=28
      ⤷ ×2 siblings like "Category Card 01" (same tree); per-copy differences:
        · Category Card 02: P(0.0477, 0.2477); z4; Art img:133728852931713; Art P(-0.0636, -0.1655); Art S(1.127, 1.4721); Category Name P(0.2779, 0.2561); Category Name "BOSSES"; Category Name S(0.2956, 0.2787); Category Count #FF2E8B; Category Count "1 / 4  FOUND"; Category Count S(0.269, 0.1481)
    Completion Header [Frame] P(0.0629, 0.4247) S(0.8744, 0.0474) z5
      Art [ImageLabel] S(1, 1) img:71162335431119
      Section Title [TextLabel] P(0.0816, 0) S(0.4766, 0.7125) z2 "COMPLETION" Heavy #FFC13B max=48
      Section Info [TextLabel] P(0.8903, 0.1351) S(0.1185, 0.4423) z3 "5 / 67" Bold #FFFFFF max=30
    Reward Card [ImageButton] P(0.0477, 0.5344) S(0.9045, 0.199) z6
      Art [ImageLabel] P(-0.0636, -0.1112) S(1.127, 1.3173) img:110044685260426
      Reward Label [TextLabel] P(0.0757, 0.1604) S(0.1864, 0.0937) z2 "REWARD" Heavy #FFC13B max=26
      Reward Name [TextLabel] P(0.0757, 0.2892) S(0.7537, 0.1991) z3 "MONSTER HUNTER" Heavy #FFFFFF max=56
      Reward Desc [TextLabel] P(0.0757, 0.5468) S(0.9162, 0.0995) z4 "Discover all 67 monsters to unlock this title." Bold #B9A9D9 max=28
      Reward Value [TextLabel] P(0.1546, 0.7635) S(0.2184, 0.1288) z5 "+ 25,000" Heavy #FFC13B max=36
  Enemy Grid Container [Frame] P(0.5, 0.5232) S(0.4793, 0.702) A(0.5, 0.5) z4 AR=1.2138  px[500,186 920x758]
    Art [ImageLabel] P(-0.0267, -0.0232) S(1.0536, 1.0652) img:112637994550561
    Monsters Header [Frame] P(0.0306, 0.0376) S(0.9388, 0.0537) z2
      Art [ImageLabel] S(1, 1) img:111429902403933
      Section Title [TextLabel] P(0.037, 0) S(0.18, 0.7125) z2 "MONSTERS" Heavy #FFFFFF max=48
      Section Info [TextLabel] P(0.8229, 0.1351) S(0.1912, 0.4423) z3 "DISCOVERED  4 / 13" Bold #FFC13B max=30
    Enemy Card 01 [ImageButton] P(0.0233, 0.1142) S(0.2363, 0.2728) z3
      Art [ImageLabel] P(-0.1186, -0.0919) S(1.2368, 1.2621) img:122125101544239
      Enemy Label [TextLabel] P(0.3641, 0.853) S(0.293, 0.0774) z2 "ZOMBIE" Heavy #FFFFFF max=26
      ⤷ ×12 siblings like "Enemy Card 01" (same tree); per-copy differences:
        · Enemy Card 02: P(0.2623, 0.1142); z4; Art img:111095047400906; Enemy Label P(0.3411, 0.853); Enemy Label "VAMPIRE"; Enemy Label S(0.3426, 0.0774)
        · Enemy Card 03: P(0.5014, 0.1142); z5; Art img:118626977993579; Enemy Label P(0.3205, 0.853); Enemy Label "SKELETON"; Enemy Label S(0.3873, 0.0774)
        · Enemy Card 04: P(0.7404, 0.1134); z6; S(0.2363, 0.2743); Art img:128997286701294; Art P(-0.1186, -0.0885); Art S(1.2368, 1.2548); Enemy Label P(0.3067, 0.851); Enemy Label "SKULLKING"; Enemy Label S(0.4171, 0.0769)
        · Enemy Card 05: P(0.0233, 0.3938); z7; Art img:97190183161617; Enemy Label #B9A9D9; Enemy Label P(0.4423, 0.853); Enemy Label "???"; Enemy Label S(0.1241, 0.0774)
        · Enemy Card 06: P(0.2623, 0.3938); z8; Art img:87946383224941; Enemy Label #B9A9D9; Enemy Label P(0.4423, 0.853); Enemy Label "???"; Enemy Label S(0.1241, 0.0774)
        · Enemy Card 07: P(0.5014, 0.3938); z9; Art img:85216215301706; Enemy Label #B9A9D9; Enemy Label P(0.4423, 0.853); Enemy Label "???"; Enemy Label S(0.1241, 0.0774)
        · Enemy Card 08: P(0.7404, 0.3938); z10; Art img:92532302598430; Enemy Label #B9A9D9; Enemy Label P(0.4423, 0.853); Enemy Label "???"; Enemy Label S(0.1241, 0.0774)
        · Enemy Card 09: P(0.0233, 0.6734); z11; Art img:130039893781785; Enemy Label #B9A9D9; Enemy Label P(0.4423, 0.853); Enemy Label "???"; Enemy Label S(0.1241, 0.0774)
        · Enemy Card 10: P(0.2623, 0.6734); z12; Art img:70589428557952; Enemy Label #B9A9D9; Enemy Label P(0.4423, 0.853); Enemy Label "???"; Enemy Label S(0.1241, 0.0774)
        · Enemy Card 11: P(0.5014, 0.6734); z13; Art img:83374273093874; Enemy Label #B9A9D9; Enemy Label P(0.4423, 0.853); Enemy Label "???"; Enemy Label S(0.1241, 0.0774)
        · Enemy Card 12: P(0.7404, 0.6734); z14; Art img:117700711518768; Enemy Label #B9A9D9; Enemy Label P(0.4423, 0.853); Enemy Label "???"; Enemy Label S(0.1241, 0.0774)
  Enemy Info Container [Frame] P(0.9813, 0.5695) S(0.2335, 0.7946) A(1, 0.5) z5 AR=0.5224  px[1436,186 448x858]
    Art [ImageLabel] P(-0.0549, -0.0205) S(1.11, 1.0576) img:123558359943642
    Tag Label [TextLabel] P(0.0941, 0.4177) S(0.1084, 0.0198) z2 "ELITE" Heavy #FFFFFF max=28
      ⤷ ×2 siblings like "Tag Label" (same tree); per-copy differences:
        · Tag Label: #33D980; P(0.2904, 0.4177); z3; "MONSTER"; S(0.1927, 0.0198)
    Enemy Name [TextLabel] P(0.0629, 0.4591) S(0.6794, 0.0653) z4 "SKULLKING" Heavy #FFFFFF max=92
    Enemy Description [TextLabel] P(0.0629, 0.5337) S(0.9444, 0.0734) z5 "Rules the monster hordes from the old cemetery and summons skeletons and vampires when its health drops low." Bold #B9A9D9 max=30
    Stat Container 01 [Frame] P(0.0629, 0.6455) S(0.4238, 0.0979) z6
      Art [ImageLabel] S(1, 1) img:79340410811348
      Stat Label [TextLabel] P(0.0842, 0.1667) S(0.4149, 0.1786) z2 "DEFEATED" Bold #B9A9D9 max=24
      Stat Value [TextLabel] P(0.0842, 0.4286) S(0.1648, 0.4048) z3 "12" Heavy #FFFFFF max=56
      ⤷ ×3 siblings like "Stat Container 01" (same tree); per-copy differences:
        · Stat Container 03: P(0.0629, 0.7574); z8; Stat Label "HEALTH"; Stat Label S(0.3069, 0.1786); Stat Value #FF2E8B; Stat Value "4,500"; Stat Value S(0.4888, 0.4048)
        · Stat Container 04: P(0.5135, 0.7574); z9; Stat Label "THREAT"; Stat Label S(0.3069, 0.1786); Stat Value #FFC13B; Stat Value "HIGH"; Stat Value S(0.4377, 0.4048)
    Stat Container 02 [Frame] P(0.5135, 0.6455) S(0.4238, 0.0979) z7
      Art [ImageLabel] S(1, 1) img:79340410811348
      Stat Label [TextLabel] P(0.0842, 0.1667) S(0.3922, 0.1786) z2 "FOUND IN" Bold #B9A9D9 max=24
      Stat Value [TextLabel] P(0.0842, 0.4286) S(0.7958, 0.3452) z3 "CEMETERY" Heavy #FFFFFF max=48
    Track Button [ImageButton] P(0.0513, 0.8725) S(0.8976, 0.1007) z10
      Art [ImageLabel] P(-0.0646, -0.2106) S(1.1292, 1.6019) img:82774949048419
  Exit Button [ImageButton] ≈ Weapons Shop › Exit Button  px[805,965 310x80], differs: z6
```

### Classes (168 instances)

```
Classes [ScreenGui] Enabled=False ResetOnSpawn=False ScreenInsets=DeviceSafeInsets ZIndexBehavior=Sibling
  Title Container [Frame] P(0.0251, 0.037) S(0.1406, 0.0731) AR=3.4165  px[48,40 270x79]
    Art [ImageLabel] S(1, 1) img:92395649426353
    Title Label [TextLabel] P(0.1775, 0) S(0.8883, 0.7089) z2 "CLASSES" Heavy #FFFFFF max=92
    Subtitle Label [TextLabel] P(0.2664, 0.7722) S(0.7843, 0.2278) z3 "PICK YOUR PLAYSTYLE" Bold #FFC13B max=30
  Currency Container [Frame] ≈ Lobby HUD › Currency Container  px[1327,52 553x67], differs: P(0.9792, 0.0481)
  Top Menu Container [Frame] P(0.4997, 0.0433) S(0.2632, 0.0689) A(0.5, 0) z3 AR=6.793  px[707,47 505x74]
    Top Menu Tab 01 [Frame] S(0.4954, 1) z2
      Art [ImageLabel] P(-0.1038, -0.2446) S(1.2077, 1.6989) img:117540626912917
      Button Label [TextLabel] P(0.3442, 0.3185) S(0.4917, 0.3629) z2 "CLASSES" Heavy #FFFFFF max=44
      ⤷ ×2 siblings like "Top Menu Tab 01" (same tree); per-copy differences:
        · Top Menu Tab 02: P(0.5085, 0.0161); z3; S(0.4913, 0.9704); Art img:83791817744243; Art P(-0.0991, -0.2438); Art S(1.1985, 1.6842); Button Label #B9A9D9; Button Label P(0.1921, 0.3116); Button Label "EQUIPMENT"; Button Label S(0.6655, 0.374)
  Class List Container [Frame] P(0.0186, 0.5695) S(0.2335, 0.7946) A(0, 0.5) z4 AR=0.5224  px[36,186 448x858]
    Art [ImageLabel] P(-0.0549, -0.0205) S(1.11, 1.0576) img:132352515506787
    All Classes Header [Frame] P(0.0629, 0.0332) S(0.8744, 0.0474) z2
      Art [ImageLabel] S(1, 1) img:126385323239527
      Section Title [TextLabel] P(0.0816, 0) S(0.4739, 0.7125) z2 "ALL CLASSES" Heavy #FFFFFF max=48
      Section Info [TextLabel] P(0.75, 0.1351) S(0.27, 0.4423) z3 "1 / 7 OWNED" Bold #FFC13B max=30
    Class Card 01 [ImageButton] P(0.0477, 0.0955) S(0.9045, 0.1165) z3
      Art [ImageLabel] P(-0.0636, -0.184) S(1.127, 1.53) img:87369403762982
      Rarity Label [TextLabel] P(0.2434, 0.265) S(0.1838, 0.15) z2 "COMMON" Heavy #9999AD max=24
      Class Name [TextLabel] P(0.2434, 0.51) S(0.3169, 0.26) z3 "SURVIVOR" Heavy #FFFFFF max=42
      Tag Label [TextLabel] P(0.7539, 0.215) S(0.1784, 0.13) z4 "EQUIPPED" Heavy #0D0A1C max=22
    Class Card 02 [ImageButton] P(0.0477, 0.2104) S(0.9045, 0.1151) z4
      Art [ImageLabel] P(-0.0636, -0.1923) S(1.127, 1.5486) img:114917201772506
      Rarity Label [TextLabel] P(0.2434, 0.2621) S(0.2424, 0.1518) z2 "UNCOMMON" Heavy #33D980 max=24
      Class Name [TextLabel] P(0.2434, 0.5101) S(0.1998, 0.2632) z3 "MEDIC" Heavy #B9A9D9 max=42
      Price Label [TextLabel] P(0.7588, 0.5304) S(0.1944, 0.2227) z4 "$15,000" Heavy #FFFFFF max=36
      ⤷ ×6 siblings like "Class Card 02" (same tree); per-copy differences:
        · Class Card 03: P(0.0477, 0.3246); z5; Art img:88145592925399; Rarity Label #9EBAD9; Rarity Label "RARE"; Rarity Label S(0.1065, 0.1518); Class Name "ENGINEER"; Class Name S(0.309, 0.2632); Price Label P(0.7465, 0.5304); Price Label "$30,000"; Price Label S(0.2077, 0.2227)
        · Class Card 04: P(0.0477, 0.4388); z6; Art img:110868345812178; Rarity Label #9EBAD9; Rarity Label "RARE"; Rarity Label S(0.1065, 0.1518); Class Name "JUGGERNAUT"; Class Name S(0.4102, 0.2632); Price Label P(0.749, 0.5304); Price Label "$75,000"; Price Label S(0.2051, 0.2227)
        · Class Card 05: P(0.0477, 0.553); z7; Art img:89873322598983; Rarity Label #FF2E8B; Rarity Label "EPIC"; Rarity Label S(0.0932, 0.1518); Class Name "BOMBER"; Class Name S(0.269, 0.2632); Price Label P(0.7292, 0.5304); Price Label "$120,000"; Price Label S(0.2264, 0.2227)
        · Class Card 06: P(0.0477, 0.6672); z8; Art img:110152762528398; Rarity Label #FF2E8B; Rarity Label "EPIC"; Rarity Label S(0.0932, 0.1518); Class Name "PYROMANIAC"; Class Name S(0.4208, 0.2632); Price Label P(0.7144, 0.5304); Price Label "$300,000"; Price Label S(0.2424, 0.2227)
        · Class Card 07: P(0.0477, 0.7814); z9; Art img:136317508440804; Rarity Label #FFC13B; Rarity Label "LEGENDARY"; Class Name "OUTLAW"; Class Name S(0.2743, 0.2632); Price Label P(0.7144, 0.5304); Price Label "$500,000"; Price Label S(0.2424, 0.2227)
  Stage Container [Frame] P(0.5, 0.5035) S(0.2708, 0.6079) A(0.5, 0.5) z5 AR=0.7921  px[700,216 520x656]
    Art [ImageLabel] S(1, 1) img:72748462167739
    Class Name [TextLabel] P(0.0865, 0) S(0.8931, 0.1417) z2 "SURVIVOR" Heavy #FFFFFF max=100
    Tag Label [TextLabel] P(0.4115, 0.1592) S(0.1911, 0.0274) z3 "COMMON" Heavy #0D0A1C max=30
  Exit Button [ImageButton] ≈ Weapons Shop › Exit Button  px[805,965 310x80], differs: z6
  Class Info Container [Frame] P(0.9813, 0.5695) S(0.2335, 0.7946) A(1, 0.5) z7 AR=0.5224  px[1436,186 448x858]
    Art [ImageLabel] P(-0.0549, -0.0205) S(1.11, 1.0576) img:88002291333331
    Abilities Header [Frame] P(0.0629, 0.0332) S(0.8744, 0.0474) z2
      Art [ImageLabel] S(1, 1) img:103336442378007
      Section Title [TextLabel] P(0.0816, 0) S(0.3471, 0.7125) z2 "ABILITIES" Heavy #FFFFFF max=48
      Section Info [TextLabel] P(0.8291, 0.1351) S(0.1846, 0.4423) z3 "3 SKILLS" Bold #FFC13B max=30
    Ability Card 01 [ImageButton] P(0.0477, 0.1002) S(0.3036, 0.1631) z3
      Art [ImageLabel] P(-0.1896, -0.1314) S(1.3791, 1.3786) img:105895148284092
      Ability Label [TextLabel] P(0.2542, 0.775) S(0.5317, 0.1071) z2 "GRENADE" Heavy #FFFFFF max=24
      Tag Label [TextLabel] P(0.2109, 0.1321) S(0.1825, 0.0929) z3 "$50" Heavy #33D980 max=22
      ⤷ ×3 siblings like "Ability Card 01" (same tree); per-copy differences:
        · Ability Card 02: P(0.3482, 0.1009); z4; Art img:79367531594226; Art P(-0.1896, -0.1369); Art S(1.3791, 1.3905); Ability Label P(0.302, 0.7774); Ability Label "MEDKIT"; Ability Label S(0.4285, 0.1081); Tag Label P(0.2109, 0.129); Tag Label "$40"; Tag Label S(0.1904, 0.0937)
        · Ability Card 03: P(0.6487, 0.1009); z5; Art img:87260294542231; Art P(-0.1896, -0.1369); Art S(1.3791, 1.3905); Ability Label P(0.2322, 0.7774); Ability Label "AIRSTRIKE"; Ability Label S(0.5793, 0.1081); Tag Label #0D0A1C; Tag Label P(0.2109, 0.129); Tag Label "ULT"
    Ability Name [TextLabel] P(0.0629, 0.2843) S(0.5107, 0.0571) z6 "GRENADE" Heavy #FFFFFF max=80
    Help Button [ImageButton] P(0.8481, 0.289) S(0.0892, 0.0466) z7
      Art [ImageLabel] S(1, 1) img:93902344826618
    Help Label [TextLabel] P(0.8771, 0.2966) S(0.0337, 0.0315) z8 "?" Heavy #33D980 max=44
    Stat Container 01 [Frame] P(0.0629, 0.4032) S(0.8744, 0.0746) z9
      Art [ImageLabel] S(1, 1) img:137969553595518
      Stat Label [TextLabel] P(0.0459, 0.3594) S(0.2094, 0.2813) z2 "DAMAGE" Bold #B9A9D9 max=30
      Stat Next [TextLabel] P(0.8393, 0.25) S(0.124, 0.5) z3 "120" Heavy #33D980 max=52
      Stat Arrow [TextLabel] P(0.7883, 0.3125) S(0.0331, 0.375) z4 "→" Heavy #33D980 max=40
      Stat Value [TextLabel] P(0.6658, 0.25) S(0.1102, 0.5) z5 "110" Heavy #FFFFFF max=52
      ⤷ ×2 siblings like "Stat Container 01" (same tree); per-copy differences:
        · Stat Container 02: P(0.0629, 0.4917); z10; Stat Label "RADIUS"; Stat Label S(0.1818, 0.2813); Stat Next P(0.8801, 0.25); Stat Next "10"; Stat Next S(0.0799, 0.5); Stat Arrow P(0.8291, 0.3125); Stat Value P(0.7628, 0.25); Stat Value "8"; Stat Value S(0.0496, 0.5)
    Cost Value [TextLabel] P(0.4878, 0.6024) S(0.118, 0.0396) z11 "150" Heavy #FFC13B max=56
    Upgrade Button [ImageButton] P(0.0513, 0.6581) S(0.8976, 0.1007) z12
      Art [ImageLabel] P(-0.0646, -0.2106) S(1.1292, 1.6019) img:116477987709622
    Equip Button [ImageButton] P(0.0513, 0.8725) S(0.8976, 0.1007) z13
      Art [ImageLabel] P(-0.0646, -0.2106) S(1.1292, 1.6019) img:125334353114191
```

### Equipment (157 instances)

```
Equipment [ScreenGui] Enabled=False ResetOnSpawn=False ScreenInsets=DeviceSafeInsets ZIndexBehavior=Sibling
  Title Container [Frame] P(0.0223, 0.037) S(0.1829, 0.0731) AR=4.4443  px[43,40 351x79]
    Art [ImageLabel] S(1, 1) img:75976353207490
    Title Label [TextLabel] P(0.1512, 0) S(0.9167, 0.7089) z2 "EQUIPMENT" Heavy #FFFFFF max=92
    Subtitle Label [TextLabel] P(0.2196, 0.7722) S(0.6921, 0.2278) z3 "GEAR UP FOR THE HORDE" Bold #FFC13B max=30
  Currency Container [Frame] ≈ Lobby HUD › Currency Container  px[1327,52 553x67], differs: P(0.9792, 0.0481)
  Top Menu Container [Frame] ≈ Classes › Top Menu Container  px[708,47 505x74], differs: Top Menu Tab 01 P(0, 0.0161); Top Menu Tab 01 S(0.4913, 0.9704); Top Menu Tab 01.Art img:115579819543890; Top Menu Tab 01.Art P(-0.0991, -0.2438); Top Menu Tab 01.Art S(1.1985, 1.6842); Top Menu Tab 01.Button Label #B9A9D9; Top Menu Tab 01.Button Label P(0.2706, 0.3116); Top Menu Tab 01.Button Label S(0.4959, 0.374); Top Menu Tab 02 P(0.5046, 0); Top Menu Tab 02 S(0.4954, 1); Top Menu Tab 02.Art img:108133736565973; Top Menu Tab 02.Art P(-0.1038, -0.2446); Top Menu Tab 02.Art S(1.2077, 1.6989); Top Menu Tab 02.Button Label #FFFFFF; Top Menu Tab 02.Button Label P(0.2664, 0.3185); Top Menu Tab 02.Button Label S(0.6599, 0.3629)
  Item Grid Container [Frame] P(0.0186, 0.5695) S(0.2335, 0.7946) A(0, 0.5) z4 AR=0.5224  px[36,186 448x858]
    Art [ImageLabel] P(-0.0549, -0.0205) S(1.11, 1.0576) img:134491076023635
    Sub Tab Container [Frame] P(0.0513, 0.0266) S(0.8954, 0.068) z2
      Sub Tab 01 [Frame] S(0.2551, 1) z2
        Art [ImageLabel] P(-0.2539, -0.3116) S(1.5078, 1.8904) img:110504270790823
        Button Label [TextLabel] P(0.3389, 0.3459) S(0.348, 0.3082) z2 "ALL" Heavy #FFFFFF max=30
        ⤷ ×4 siblings like "Sub Tab 01" (same tree); per-copy differences:
          · Sub Tab 02: P(0.2516, 0.0205); z3; S(0.2499, 0.9623); Art img:101317556846010; Art P(-0.2453, -0.3132); Art S(1.4915, 1.879); Button Label #B9A9D9; Button Label P(0.2512, 0.3381); Button Label "HEAD"; Button Label S(0.5384, 0.3203)
          · Sub Tab 03: P(0.5007, 0.0205); z4; S(0.2499, 0.9623); Art img:81430650282413; Art P(-0.2453, -0.3132); Art S(1.4915, 1.879); Button Label #B9A9D9; Button Label P(0.2014, 0.3381); Button Label "TORSO"; Button Label S(0.6461, 0.3203)
          · Sub Tab 04: P(0.7499, 0.0205); z5; S(0.2499, 0.9623); Art img:101917548826449; Art P(-0.2453, -0.3132); Art S(1.4915, 1.879); Button Label #B9A9D9; Button Label P(0.2812, 0.3381); Button Label "LEGS"; Button Label S(0.4738, 0.3203)
    Items Header [Frame] P(0.0629, 0.1171) S(0.8744, 0.0474) z3
      Art [ImageLabel] S(1, 1) img:86558707764577
      Section Title [TextLabel] P(0.0816, 0) S(0.2177, 0.7125) z2 "ITEMS" Heavy #FFFFFF max=48
      Section Info [TextLabel] P(0.7474, 0.1351) S(0.2728, 0.4423) z3 "1 / 9 OWNED" Bold #FFC13B max=30
    Item Card 01 [ImageButton] P(0.0477, 0.1841) S(0.2978, 0.2191) z4
      Art [ImageLabel] P(-0.1933, -0.0979) S(1.3858, 1.2819) img:108263692862249
      Item Label [TextLabel] P(0.0914, 0.8431) S(0.8818, 0.0691) z2 "STANDARD ISSUE" Heavy #FFFFFF max=22
      ⤷ ×9 siblings like "Item Card 01" (same tree); per-copy differences:
        · Item Card 02: P(0.3511, 0.1848); z5; Art img:117711285212679; Art P(-0.1933, -0.1017); Art S(1.3858, 1.2902); Item Label #B9A9D9; Item Label P(0.2674, 0.8453); Item Label "HOTHEAD"; Item Label S(0.5016, 0.0696)
        · Item Card 03: P(0.6545, 0.1848); z6; Art img:111837058343495; Art P(-0.1933, -0.1017); Art S(1.3858, 1.2902); Item Label #B9A9D9; Item Label P(0.2562, 0.8453); Item Label "TIKI SKIRT"; Item Label S(0.5258, 0.0696)
        · Item Card 04: P(0.0477, 0.4085); z7; Art img:124535311721304; Art P(-0.1933, -0.1017); Art S(1.3858, 1.2902); Item Label #B9A9D9; Item Label P(0.215, 0.8453); Item Label "COVE BLING"; Item Label S(0.6148, 0.0696)
        · Item Card 05: P(0.3511, 0.4085); z8; Art img:74000720857918; Art P(-0.1933, -0.1017); Art S(1.3858, 1.2902); Item Label #B9A9D9; Item Label P(0.1363, 0.8453); Item Label "MUTAGEN VEST"; Item Label S(0.7847, 0.0696)
        · Item Card 06: P(0.6545, 0.4085); z9; Art img:133188359998045; Art P(-0.1933, -0.1017); Art S(1.3858, 1.2902); Item Label #B9A9D9; Item Label P(0.1476, 0.8453); Item Label "BARON'S CAPE"; Item Label S(0.7604, 0.0696)
        · Item Card 07: P(0.0477, 0.6323); z10; Art img:124696515327339; Art P(-0.1933, -0.1017); Art S(1.3858, 1.2902); Item Label #B9A9D9; Item Label P(0.1438, 0.8453); Item Label "NIGHT GUARDS"; Item Label S(0.7685, 0.0696)
        · Item Card 08: P(0.3511, 0.6323); z11; Art img:108972816716784; Art P(-0.1933, -0.1017); Art S(1.3858, 1.2902); Item Label #B9A9D9; Item Label P(0.1064, 0.8453); Item Label "GOOD OLD DAYS"; Item Label S(0.8494, 0.0696)
        · Item Card 09: P(0.6545, 0.6323); z12; Art img:83466385017943; Art P(-0.1933, -0.1017); Art S(1.3858, 1.2902); Item Label #B9A9D9; Item Label P(0.1476, 0.8453); Item Label "GRAVE WRAPS"; Item Label S(0.7604, 0.0696)
  Stage Container [Frame] P(0.5, 0.4259) S(0.2604, 0.4815) A(0.5, 0.5) z5 AR=0.9615  px[710,200 500x520]
    Image [ImageLabel] S(1, 1) img:76071037245364
  Wearing Container [Frame] P(0.5, 0.8846) S(0.2664, 0.2018) A(0.5, 1) z6 AR=2.3474  px[704,738 511x218]
    Wearing Title [TextLabel] P(0.3631, 0) S(0.2956, 0.1331) z2 "WEARING" Heavy #FFFFFF max=48
    Wearing Slot 01 [Frame] P(0, 0.1703) S(0.3196, 0.8297) z3
      Art [ImageLabel] P(-0.1578, -0.1051) S(1.315, 1.2998) img:130923731014927
      Slot Label [TextLabel] P(0.3346, 0.1073) S(0.3567, 0.1106) z2 "HEAD" Heavy #FFFFFF max=32
      Slot Item Label [TextLabel] P(0.1664, 0.8236) S(0.72, 0.0719) z3 "STANDARD ISSUE" Heavy #FFFFFF max=22
      ⤷ ×3 siblings like "Wearing Slot 01" (same tree); per-copy differences:
        · Wearing Slot 02: P(0.3402, 0.1703); z4; Art img:119433769737790; Slot Label #B9A9D9; Slot Label P(0.3009, 0.1073); Slot Label "TORSO"; Slot Label S(0.4294, 0.1106); Slot Item Label #B9A9D9; Slot Item Label P(0.3713, 0.8236); Slot Item Label "EMPTY"; Slot Item Label S(0.2774, 0.0719)
        · Wearing Slot 03: P(0.6804, 0.1703); z5; Art img:120724388375483; Slot Label #B9A9D9; Slot Label P(0.3529, 0.1073); Slot Label "LEGS"; Slot Label S(0.3171, 0.1106); Slot Item Label #B9A9D9; Slot Item Label P(0.3713, 0.8236); Slot Item Label "EMPTY"; Slot Item Label S(0.2774, 0.0719)
  Item Info Container [Frame] P(0.9813, 0.5695) S(0.2335, 0.7946) A(1, 0.5) z7 AR=0.5224  px[1436,186 448x858]
    Art [ImageLabel] P(-0.0549, -0.0205) S(1.11, 1.0576) img:93487134628245
    Head Header [Frame] P(0.0629, 0.0332) S(0.8744, 0.0474) z2
      Art [ImageLabel] S(1, 1) img:113128659041052
      Section Title [TextLabel] P(0.0816, 0) S(0.2066, 0.7125) z2 "HEAD" Heavy #FFFFFF max=48
      Section Info [TextLabel] P(0.8112, 0.1351) S(0.2039, 0.4423) z3 "SLOT 1 / 3" Bold #FFC13B max=30
    Preview Card [ImageButton] P(0.0477, 0.1009) S(0.9045, 0.2922) z3
      Art [ImageLabel] P(-0.0636, -0.0758) S(1.127, 1.2161) img:112292749540103
      Tag Label [TextLabel] P(0.0806, 0.8389) S(0.2051, 0.0638) z2 "COMMON" Heavy #0D0A1C max=26
    Item Name [TextLabel] P(0.0629, 0.4125) S(0.7781, 0.0478) z4 "STANDARD ISSUE" Heavy #FFFFFF max=68
    Help Button [ImageButton] P(0.8481, 0.4148) S(0.0892, 0.0466) z5
      Art [ImageLabel] S(1, 1) img:93902344826618
    Help Label [TextLabel] P(0.8771, 0.4224) S(0.0337, 0.0315) z6 "?" Heavy #33D980 max=44
    Stat Container 01 [Frame] P(0.0629, 0.4824) S(0.8744, 0.0746) z7
      Art [ImageLabel] S(1, 1) img:137969553595518
      Stat Value [TextLabel] P(0.0459, 0.25) S(0.124, 0.5) z2 "+10" Heavy #33D980 max=52
      Stat Label [TextLabel] P(0.2092, 0.3281) S(0.2204, 0.3438) z3 "MAX HP" Bold #FFFFFF max=36
    Item Description [TextLabel] P(0.0629, 0.5803) S(0.9444, 0.0489) z8 "Standard-issue army helmet. Not pretty, but it keeps your head on your shoulders." Bold #B9A9D9 max=30
    Show Toggle [Frame] P(0.0629, 0.7691) S(0.8744, 0.0839) z9
      Art [ImageLabel] S(1, 1) img:128035418919606
      Toggle Label [TextLabel] P(0.0459, 0.3611) S(0.5923, 0.2778) z2 "SHOW ON CHARACTER" Heavy #FFFFFF max=32
    Equip Button [ImageButton] P(0.0513, 0.8725) S(0.8976, 0.1007) z10
      Art [ImageLabel] P(-0.0646, -0.2106) S(1.1292, 1.6019) img:125334353114191
  Exit Button [ImageButton] ≈ Weapons Shop › Exit Button  px[805,965 310x80], differs: z8
```

### Settings (85 instances)

```
Settings [ScreenGui] Enabled=False ResetOnSpawn=False ScreenInsets=DeviceSafeInsets ZIndexBehavior=Sibling
  Dim Overlay UI [Frame] S(1, 1) bg=#000000 bgT=0.7  px[0,0 1920x1080]
  Settings Container [Frame] P(0.5, 0.5001) S(0.546, 0.8594) A(0.5, 0.5) z2 AR=1.1294  px[436,76 1048x928]
    Art [ImageLabel] P(-0.0235, -0.019) S(1.047, 1.0532) img:89099049083500
    Header Container [Frame] P(0.0345, 0.0215) S(0.9387, 0.0875) z2
      Art [ImageLabel] S(1, 1) img:87986228259949
      Title Label [TextLabel] P(0.0508, 0.1232) S(0.2074, 0.5419) z2 "SETTINGS" Heavy #FFFFFF max=72
      Close Button [ImageButton] P(0.935, 0) S(0.065, 0.7882) z3
        Art [ImageLabel] P(-0.4875, -0.3656) S(1.975, 1.975) img:87934738225568
    Audio Header [Frame] P(0.0422, 0.1325) S(0.9158, 0.0412) z3
      Art [ImageLabel] S(1, 1) img:85445603148106
      Section Title [TextLabel] P(0.0333, 0) S(0.081, 0.6283) z2 "AUDIO" Heavy #FFFFFF max=40
    Music Setting [Frame] P(0.0357, 0.1838) S(0.9286, 0.0892) z4
      Art [ImageLabel] P(-0.0265, -0.2295) S(1.0529, 1.6546) img:104154756775730
      Setting Label [TextLabel] P(0.0315, 0.337) S(0.0854, 0.3261) z2 "MUSIC" Heavy #FFFFFF max=44
      Music Slider [Frame] P(0.5246, 0.2585) S(0.3657, 0.4831) z3
        Art [ImageLabel] S(1, 1) img:135123923403961
        Slider Value [TextLabel] P(0.8961, 0.2) S(0.1122, 0.6) z2 "100" Heavy #FFFFFF max=40
      Music Reset Button [ImageButton] P(0.9191, 0.2101) S(0.0493, 0.5797) z4
        Art [ImageLabel] P(-0.6, -0.45) S(2.2, 2.2) img:125107580511892
    Sound Effects Setting [Frame] P(0.0357, 0.2721) S(0.9286, 0.0892) z5
      Art [ImageLabel] P(-0.0265, -0.2295) S(1.0529, 1.6546) img:117465090351192
      Setting Label [TextLabel] P(0.0315, 0.337) S(0.2174, 0.3261) z2 "SOUND EFFECTS" Heavy #FFFFFF max=44
      Sound Effects Slider [Frame] P(0.5246, 0.2585) S(0.3657, 0.4831) z3
        Art [ImageLabel] S(1, 1) img:79154612532477
        Slider Value [TextLabel] P(0.9298, 0.2) S(0.0758, 0.6) z2 "75" Heavy #FFFFFF max=40
      Sound Effects Reset Button [ImageButton] P(0.9191, 0.2101) S(0.0493, 0.5797) z4
        Art [ImageLabel] P(-0.6, -0.45) S(2.2, 2.2) img:118009714755116
    Menu Sounds Setting [Frame] P(0.0357, 0.3605) S(0.9286, 0.0892) z6
      Art [ImageLabel] P(-0.0265, -0.2295) S(1.0529, 1.6546) img:112562392406666
      Setting Label [TextLabel] P(0.0315, 0.337) S(0.1975, 0.3261) z2 "MENU SOUNDS" Heavy #FFFFFF max=44
      Menu Sounds Slider [Frame] P(0.5112, 0.2585) S(0.379, 0.4831) z3
        Art [ImageLabel] S(1, 1) img:83160627763321
        Slider Value [TextLabel] P(0.9621, 0.2) S(0.041, 0.6) z2 "0" Heavy #FFFFFF max=40
      Menu Sounds Reset Button [ImageButton] P(0.9191, 0.2101) S(0.0493, 0.5797) z4
        Art [ImageLabel] P(-0.6, -0.45) S(2.2, 2.2) img:133056598251309
    Camera Header [Frame] P(0.0422, 0.4665) S(0.9158, 0.0412) z7
      Art [ImageLabel] S(1, 1) img:114795113817787
      Section Title [TextLabel] P(0.0333, 0) S(0.1069, 0.6283) z2 "CAMERA" Heavy #FFFFFF max=40
    Reduce Camera Shake Setting [Frame] P(0.0357, 0.5178) S(0.9286, 0.0892) z8
      Art [ImageLabel] P(-0.0265, -0.2295) S(1.0529, 1.6546) img:138525765842214
      Setting Label [TextLabel] P(0.0315, 0.2162) S(0.3284, 0.3261) z2 "REDUCE CAMERA SHAKE" Heavy #FFFFFF max=44
      Setting Description [TextLabel] P(0.0315, 0.5966) S(0.2774, 0.1932) z3 "No camera shake; weapon kick stays" Bold #B9A9D9 max=26
      Reduce Camera Shake Reset Button [ImageButton] P(0.9191, 0.2101) S(0.0493, 0.5797) z4
        Art [ImageLabel] P(-0.6, -0.45) S(2.2, 2.2) img:82346710001747
    Drag Fire To Aim Setting [Frame] P(0.0357, 0.6061) S(0.9286, 0.0892) z9
      Art [ImageLabel] P(-0.0265, -0.2295) S(1.0529, 1.6546) img:86504477922950
      Setting Label [TextLabel] P(0.0315, 0.2162) S(0.2463, 0.3261) z2 "DRAG FIRE TO AIM" Heavy #FFFFFF max=44
      Setting Description [TextLabel] P(0.0315, 0.5966) S(0.2663, 0.1932) z3 "Drag the fire button to look around" Bold #B9A9D9 max=26
      Drag Fire To Aim Reset Button [ImageButton] P(0.9191, 0.2101) S(0.0493, 0.5797) z4
        Art [ImageLabel] P(-0.6, -0.45) S(2.2, 2.2) img:89654794002981
    Profile Header [Frame] P(0.0422, 0.7121) S(0.9158, 0.0412) z10
      Art [ImageLabel] S(1, 1) img:104283121581154
      Section Title [TextLabel] P(0.0333, 0) S(0.1046, 0.6283) z2 "PROFILE" Heavy #FFFFFF max=40
    Display Name Setting [Frame] P(0.0357, 0.7634) S(0.9286, 0.0892) z11
      Art [ImageLabel] P(-0.0265, -0.2295) S(1.0529, 1.6546) img:128344107999105
      Setting Label [TextLabel] P(0.0315, 0.2162) S(0.2008, 0.3261) z2 "DISPLAY NAME" Heavy #FFFFFF max=44
      Setting Description [TextLabel] P(0.0315, 0.5966) S(0.1853, 0.1932) z3 "Shown on your head tag" Bold #B9A9D9 max=26
      Display Name Input [Frame] P(0.541, 0.2101) S(0.3493, 0.5797) z4
        Art [ImageLabel] S(1, 1) img:139649818264337
        Input Value [TextLabel] P(0.0471, 0.2708) S(0.3653, 0.4583) z2 "RenKaMens" Heavy #FFFFFF max=36
      Display Name Reset Button [ImageButton] P(0.9191, 0.2101) S(0.0493, 0.5797) z5
        Art [ImageLabel] P(-0.6, -0.45) S(2.2, 2.2) img:124396401044302
    Footer Hint [TextLabel] P(0.0422, 0.9174) S(0.273, 0.0183) z12 "CHANGES SAVE AUTOMATICALLY" Bold #B9A9D9 max=28
    Reset All Button [ImageButton] P(0.6668, 0.8864) S(0.2961, 0.0802) z13
      Art [ImageLabel] P(-0.0838, -0.2446) S(1.1675, 1.6989) img:91425743204667
```

### Settings - Reset Confirm (97 instances)

```
Settings - Reset Confirm [ScreenGui] Enabled=False ResetOnSpawn=False ScreenInsets=DeviceSafeInsets ZIndexBehavior=Sibling
  Dim Overlay UI [Frame] = identical to Settings › Dim Overlay UI (1 instances)  px[0,0 1920x1080]
  Settings Container [Frame] = identical to Settings › Settings Container (83 instances)  px[436,76 1048x928]
  Dim Overlay UI [Frame] S(1, 1) z3 bg=#000000 bgT=0.4  px[0,0 1920x1080]
  Confirm Modal Container [Frame] P(0.5, 0.5001) S(0.3377, 0.3965) A(0.5, 0.5) z4 AR=1.514  px[636,326 648x428]
    Art [ImageLabel] P(-0.0379, -0.0411) S(1.076, 1.1154) img:95928634624098
    Confirm Title [TextLabel] P(0.1885, 0.3585) S(0.673, 0.0957) z2 "RESET ALL SETTINGS?" Heavy #FFFFFF max=68
    Confirm Description [TextLabel] P(0.0836, 0.4811) S(0.8329, 0.1028) z3 "Audio, camera and profile settings will go back to their default values. This can't be undone." Bold #B9A9D9 align=Center max=32
    Cancel Button [ImageButton] P(0.0617, 0.7473) S(0.4262, 0.1873) z4
      Art [ImageLabel] P(-0.089, -0.2195) S(1.1784, 1.616) img:82449601802613
    Confirm Reset Button [ImageButton] P(0.5106, 0.7445) S(0.4294, 0.1924) z5
      Art [ImageLabel] P(-0.0934, -0.2209) S(1.1868, 1.6311) img:84114244116415
```

### Quests - Daily (113 instances)

```
Quests - Daily [ScreenGui] Enabled=False ResetOnSpawn=False ScreenInsets=DeviceSafeInsets ZIndexBehavior=Sibling
  Title Container [Frame] P(0.0223, 0.037) S(0.1902, 0.0731) AR=4.6215  px[43,40 365x79]
    Art [ImageLabel] S(1, 1) img:83344093114314
    Title Label [TextLabel] P(0.1454, 0) S(0.5827, 0.7089) z2 "QUESTS" Heavy #FFFFFF max=92
    Subtitle Label [TextLabel] P(0.2112, 0.7722) S(0.8519, 0.2278) z3 "COMPLETE TASKS FOR REWARDS" Bold #FFC13B max=30
  Currency Container [Frame] ≈ Lobby HUD › Currency Container  px[1327,52 553x67], differs: P(0.9792, 0.0481)
  Exit Button [ImageButton] ≈ Weapons Shop › Exit Button  px[805,965 310x80], differs: z3
  Quest Container [Frame] P(0.5, 0.514) S(0.6918, 0.7206) A(0.5, 0.5) z4 AR=1.7069  px[296,166 1328x778]
    Art [ImageLabel] P(-0.0185, -0.0226) S(1.0371, 1.0635) img:99390408111037
    Category Tab Container [Frame] P(0.0203, 0.0293) S(0.379, 0.0905) z2
      Category Tab 01 [Frame] S(0.4974, 1) z2
        Art [ImageLabel] P(-0.1038, -0.2585) S(1.2077, 1.7386) img:91256781390773
        Button Label [TextLabel] P(0.4181, 0.3082) S(0.3321, 0.3835) z2 "DAILY" Heavy #FFFFFF max=44
        ⤷ ×2 siblings like "Category Tab 01" (same tree); per-copy differences:
          · Category Tab 02: P(0.5066, 0.017); z3; S(0.4932, 0.9688); Art img:139632073147694; Art P(-0.0991, -0.2581); Art S(1.1985, 1.7243); Button Label #B9A9D9; Button Label P(0.3572, 0.3006); Button Label "WEEKLY"; Button Label S(0.4654, 0.3959)
    Reset Timer [TextLabel] P(0.8252, 0.0604) S(0.1626, 0.0283) z3 "RESETS IN 13:24:58" Heavy #FFC13B max=36
    Quest Card 01 [ImageButton] P(0.0191, 0.1653) S(0.9617, 0.1372) z4
      Art [ImageLabel] P(-0.0202, -0.1779) S(1.0404, 1.5075) img:83188519409588
      Quest Name [TextLabel] P(0.0882, 0.2051) S(0.1632, 0.2528) z2 "ZOMBIE SLAYER" Heavy #FFFFFF max=44
      Quest Description [TextLabel] P(0.0882, 0.4953) S(0.0938, 0.1592) z3 "Kill 50 zombies" Bold #B9A9D9 max=28
      Progress Count [TextLabel] P(0.5317, 0.6404) S(0.0465, 0.1685) z4 "50 / 50" Heavy #FFFFFF max=30
      Reward Container [Frame] P(0.7255, 0.3876) S(0.0712, 0.2247) z5
        Art [ImageLabel] S(1, 1) img:137562486482836
        Reward Value [TextLabel] P(0.3736, 0) S(0.6765, 1) z2 "+ 250" Heavy #FFC13B max=40
      Claim Button [ImageButton] P(0.8419, 0.1891) S(0.1428, 0.6217) z6
        Art [ImageLabel] P(-0.1425, -0.2741) S(1.2851, 1.7831) img:111969642107112
      ⤷ ×5 siblings like "Quest Card 01" (same tree); per-copy differences:
        · Quest Card 02: P(0.0191, 0.304); z5; Art img:75111604174807; Quest Name "SHARPSHOOTER"; Quest Name S(0.1674, 0.2528); Quest Description "Land 25 headshots"; Quest Description S(0.1167, 0.1592); Progress Count "25 / 25"; Progress Count S(0.0448, 0.1685); Reward Container S(0.0728, 0.2247); Reward Container.Art img:135816275011537; Reward Container.Reward Value P(0.3656, 0); Reward Container.Reward Value "+ 300"; Reward Container.Reward Value S(0.6852, 1)
        · Quest Card 03: P(0.0191, 0.4428); z6; Art img:109854365213229; Quest Name "SURVIVOR"; Quest Name S(0.1057, 0.2528); Quest Description "Clear wave 10"; Quest Description S(0.0837, 0.1592); Progress Count P(0.5364, 0.6404); Progress Count "6 / 10"; Progress Count S(0.0364, 0.1685); Reward Container S(0.0728, 0.2247); Reward Container.Art img:135816275011537; Reward Container.Reward Value P(0.3656, 0); Reward Container.Reward Value "+ 500"; Reward Container.Reward Value S(0.6852, 1); Claim Button P(0.8427, 0.2004); Claim Button S(0.1411, 0.6011); Claim Button.Art img:123458864414198; Claim Button.Art P(-0.1364, -0.2741); Claim Button.Art S(1.2734, 1.7695)
        · Quest Card 04: P(0.0191, 0.5816); z7; Art img:106966139080159; Quest Name "MONSTER MASHER"; Quest Name S(0.1911, 0.2528); Quest Description "Defeat 15 vampires or skeletons"; Quest Description S(0.1961, 0.1592); Progress Count P(0.5368, 0.6404); Progress Count "9 / 15"; Progress Count S(0.0355, 0.1685); Reward Container S(0.0744, 0.2247); Reward Container.Art img:107695290692412; Reward Container.Reward Value P(0.3579, 0); Reward Container.Reward Value "+ 400"; Reward Container.Reward Value S(0.6935, 1); Claim Button P(0.8427, 0.2004); Claim Button S(0.1411, 0.6011); Claim Button.Art img:123458864414198; Claim Button.Art P(-0.1364, -0.2741); Claim Button.Art S(1.2734, 1.7695)
        · Quest Card 05: P(0.0191, 0.7204); z8; Art img:132691131507089; Quest Name "TEAM PLAYER"; Quest Name S(0.142, 0.2528); Quest Description "Revive 3 squad mates"; Quest Description S(0.1353, 0.1592); Progress Count P(0.5395, 0.6404); Progress Count "3 / 3"; Progress Count S(0.0296, 0.1685); Reward Container S(0.0681, 0.2247); Reward Container.Art img:115699803177577; Reward Container.Reward Value P(0.3908, 0); Reward Container.Reward Value "+ 150"; Reward Container.Reward Value S(0.6579, 1); Claim Button P(0.8427, 0.2004); Claim Button S(0.1411, 0.6011); Claim Button.Art img:105128221383475; Claim Button.Art P(-0.1364, -0.2741); Claim Button.Art S(1.2734, 1.7695)
    Claim All Button [ImageButton] P(0.0203, 0.8671) S(0.9594, 0.1033) z9
      Art [ImageLabel] P(-0.0204, -0.2264) S(1.0408, 1.6468) img:91157372072686
```

### Quests - Weekly (113 instances)

```
Quests - Weekly [ScreenGui] Enabled=False ResetOnSpawn=False ScreenInsets=DeviceSafeInsets ZIndexBehavior=Sibling
  Title Container [Frame] = identical to Quests - Daily › Title Container (7 instances)  px[43,40 365x79]
  Currency Container [Frame] ≈ Lobby HUD › Currency Container  px[1327,52 553x67], differs: P(0.9792, 0.0481)
  Exit Button [ImageButton] ≈ Weapons Shop › Exit Button  px[805,965 310x80], differs: z3
  Quest Container [Frame] ≈ Quests - Daily › Quest Container  px[296,166 1328x778], differs: Art img:87480345104506; Category Tab Container.Category Tab 01 P(0, 0.017); Category Tab Container.Category Tab 01 S(0.4932, 0.9688); Category Tab Container.Category Tab 01.Art img:122016713198194; Category Tab Container.Category Tab 01.Art P(-0.0991, -0.2581); Category Tab Container.Category Tab 01.Art S(1.1985, 1.7243); Category Tab Container.Category Tab 01.Button Label #B9A9D9; Category Tab Container.Category Tab 01.Button Label P(0.4176, 0.3006); Category Tab Container.Category Tab 01.Button Label S(0.3349, 0.3959); Category Tab Container.Category Tab 02 P(0.5026, 0); Category Tab Container.Category Tab 02 S(0.4974, 1); Category Tab Container.Category Tab 02.Art img:92240609674531; Category Tab Container.Category Tab 02.Art P(-0.1038, -0.2585); Category Tab Container.Category Tab 02.Art S(1.2077, 1.7386); Category Tab Container.Category Tab 02.Button Label #FFFFFF; Category Tab Container.Category Tab 02.Button Label P(0.3582, 0.3082); Category Tab Container.Category Tab 02.Button Label S(0.4615, 0.3835); Reset Timer P(0.835, 0.0604); Reset Timer "RESETS IN 4D 13H"; Reset Timer S(0.152, 0.0283); Quest Card 01.Art img:113265118194194; Quest Card 01.Quest Name "BOSS HUNTER"; Quest Card 01.Quest Name S(0.1437, 0.2528); Quest Card 01.Quest Description "Defeat the Cove King 3 times"; Quest Card 01.Quest Description S(0.1809, 0.1592); Quest Card 01.Progress Count P(0.5407, 0.6404); Quest Card 01.Progress Count "1 / 3"; Quest Card 01.Progress Count S(0.0271, 0.1685); Quest Card 01.Reward Container S(0.0846, 0.2247); Quest Card 01.Reward Container.Art img:80708699376512; Quest Card 01.Reward Container.Reward Value #59BFFF; Quest Card 01.Reward Container.Reward Value P(0.3062, 0); Quest Card 01.Reward Container.Reward Value "+ 1,000"; Quest Card 01.Reward Container.Reward Value S(0.7493, 1); Quest Card 01.Claim Button P(0.8427, 0.2004); Quest Card 01.Claim Button S(0.1411, 0.6011); Quest Card 01.Claim Button.Art img:123458864414198; Quest Card 01.Claim Button.Art P(-0.1364, -0.2741); Quest Card 01.Claim Button.Art S(1.2734, 1.7695); Quest Card 02.Art img:111208087525613; Quest Card 02.Quest Name "GRENADIER"; Quest Card 02.Quest Name S(0.1192, 0.2528); Quest Card 02.Quest Description "Get 100 grenade kills"; Quest Card 02.Quest Description S(0.1294, 0.1592); Quest Card 02.Progress Count P(0.5258, 0.6404); Quest Card 02.Progress Count "100 / 100"; Quest Card 02.Progress Count S(0.0592, 0.1685); Quest Card 02.Reward Container S(0.0713, 0.2247); Quest Card 02.Reward Container.Art img:116788292057451; Quest Card 02.Reward Container.Reward Value #59BFFF; Quest Card 02.Reward Container.Reward Value P(0.3633, 0); Quest Card 02.Reward Container.Reward Value "+ 750"; Quest Card 02.Reward Container.Reward Value S(0.6876, 1); Quest Card 03.Art img:112451977484500; Quest Card 03.Quest Name "MARATHON"; Quest Card 03.Quest Name S(0.1192, 0.2528); Quest Card 03.Quest Description "Play 20 matches"; Quest Card 03.Quest Description S(0.1023, 0.1592); Quest Card 03.Progress Count P(0.5324, 0.6404); Quest Card 03.Progress Count "14 / 20"; Quest Card 03.Progress Count S(0.0448, 0.1685); Quest Card 03.Reward Container.Art img:92078868039296; Quest Card 03.Reward Container.Reward Value #59BFFF; Quest Card 03.Reward Container.Reward Value P(0.3555, 0); Quest Card 03.Reward Container.Reward Value "+ 600"; Quest Card 03.Reward Container.Reward Value S(0.696, 1); Quest Card 04.Art img:99518029390157; Quest Card 04.Quest Name "COLLECTOR"; Quest Card 04.Quest Name S(0.12, 0.2528); Quest Card 04.Quest Description "Discover 10 new monsters"; Quest Card 04.Quest Description S(0.1615, 0.1592); Quest Card 04.Progress Count "4 / 10"; Quest Card 04.Reward Container.Art img:92078868039296; Quest Card 04.Reward Container.Reward Value #59BFFF; Quest Card 04.Reward Container.Reward Value P(0.3555, 0); Quest Card 04.Reward Container.Reward Value "+ 800"; Quest Card 04.Reward Container.Reward Value S(0.696, 1); Quest Card 05.Art img:118842130068194; Quest Card 05.Quest Name "BIG SPENDER"; Quest Card 05.Quest Name S(0.1361, 0.2528); Quest Card 05.Quest Description "Spend 50,000 coins"; Quest Card 05.Quest Description S(0.1217, 0.1592); Quest Card 05.Progress Count P(0.5039, 0.6404); Quest Card 05.Progress Count "50,000 / 50,000"; Quest Card 05.Progress Count S(0.1065, 0.1685); Quest Card 05.Reward Container S(0.0721, 0.2247); Quest Card 05.Reward Container.Art img:93438823902575; Quest Card 05.Reward Container.Reward Value #59BFFF; Quest Card 05.Reward Container.Reward Value P(0.3594, 0); Quest Card 05.Reward Container.Reward Value "+ 500"; Quest Card 05.Reward Container.Reward Value S(0.6919, 1); Claim All Button.Art img:78613759875855
```

### Daily Rewards (116 instances)

```
Daily Rewards [ScreenGui] Enabled=False ResetOnSpawn=False ScreenInsets=DeviceSafeInsets ZIndexBehavior=Sibling
  Dim Overlay UI [Frame] = identical to Settings › Dim Overlay UI (1 instances)  px[0,0 1920x1080]
  Daily Rewards Container [Frame] P(0.5, 0.5001) S(0.6918, 0.8224) A(0.5, 0.5) z2 AR=1.4955  px[296,96 1328x888]
    Art [ImageLabel] P(-0.0185, -0.0198) S(1.0371, 1.0556) img:86503260149717
    Header Container [Frame] P(0.0273, 0.0225) S(0.9516, 0.0914) z2
      Art [ImageLabel] S(1, 1) img:112100775231900
      Title Label [TextLabel] P(0.0396, 0.1232) S(0.2811, 0.5419) z2 "DAILY REWARDS" Heavy #FFFFFF max=72
      Header Info [TextLabel] P(0.8362, 0.2833) S(0.1051, 0.2217) z3 "DAY 2 STREAK" Bold #FFC13B max=30
      Close Button [ImageButton] P(0.9494, 0) S(0.0506, 0.7882) z4
        Art [ImageLabel] P(-0.4875, -0.3656) S(1.975, 1.975) img:87934738225568
    Week Navigation Container [Frame] P(0.1613, 0.1293) S(0.6776, 0.0748) z3
      Previous Week Button [ImageButton] P(0, 0.0783) S(0.0622, 0.8434) z2
        Art [ImageLabel] P(-0.5143, -0.3857) S(2.0286, 2.0286) img:140142838441677
      Week Tab 01 [Frame] P(0.0742, 0) S(0.2116, 1) z3
        Art [ImageLabel] P(-0.1366, -0.2741) S(1.2731, 1.7831) img:109559608738506
        Button Label [TextLabel] P(0.2952, 0.3343) S(0.4424, 0.3313) z2 "WEEK 1" Heavy #FFFFFF max=36
        ⤷ ×4 siblings like "Week Tab 01" (same tree); per-copy differences:
          · Week Tab 02: P(0.2887, 0.0181); z4; S(0.2092, 0.9669); Art img:114954008972764; Art P(-0.1306, -0.2741); Art S(1.2618, 1.7695); Button Label #B9A9D9; Button Label P(0.2825, 0.3271); Button Label "WEEK 2"; Button Label S(0.4703, 0.3427)
          · Week Tab 03: P(0.502, 0.0181); z5; S(0.2092, 0.9669); Art img:103892751930229; Art P(-0.1306, -0.2741); Art S(1.2618, 1.7695); Button Label #B9A9D9; Button Label P(0.3569, 0.3271); Button Label "WEEK 3"; Button Label S(0.4703, 0.3427)
          · Week Tab 04: P(0.7153, 0.0181); z6; S(0.2092, 0.9669); Art img:120948452005613; Art P(-0.1306, -0.2741); Art S(1.2618, 1.7695); Button Label #B9A9D9; Button Label P(0.3516, 0.3271); Button Label "WEEK 4"; Button Label S(0.4818, 0.3427)
      Next Week Button [ImageButton] P(0.9378, 0.0783) S(0.0622, 0.8434) z7
        Art [ImageLabel] P(-0.5143, -0.3857) S(2.0286, 2.0286) img:71252287070686
    Day Card 01 [ImageButton] P(0.0349, 0.2236) S(0.2029, 0.2936) z4
      Art [ImageLabel] P(-0.0957, -0.0729) S(1.1911, 1.2078) img:128308738930274
      Day Label [TextLabel] P(0.3792, 0.0744) S(0.2605, 0.092) z2 "DAY 1" Heavy #FFFFFF max=40
      Reward Value [TextLabel] P(0.3792, 0.6208) S(0.2605, 0.1495) z3 "500" Heavy #FFFFFF max=64 TextTransparency=0.7
      Currency Tag UI [Frame] P(0.3755, 0.8029) S(0.2486, 0.0997) z4
        Art [ImageLabel] S(1, 1) img:126472791793872
        Tag Label [TextLabel] P(0.209, 0.2115) S(0.6287, 0.5769) z2 "GEMS" Heavy #59BFFF max=24
      Claimed Tag UI [Frame] P(0.2122, 0.3597) S(0.5922, 0.2496) z5
        Art [ImageLabel] S(1, 1) img:115410369770027
        Tag Label [TextLabel] P(0.0959, 0.172) S(0.9074, 0.6467) z2 "✓ CLAIMED" Heavy #0D0A1C max=40 Rotation=-8
    Day Card 02 [ImageButton] P(0.2412, 0.2229) S(0.2029, 0.295) z5
      Art [ImageLabel] P(-0.0957, -0.0702) S(1.1911, 1.2023) img:89324846464181
      Day Label [TextLabel] P(0.3718, 0.0763) S(0.2765, 0.0916) z2 "DAY 2" Heavy #FFFFFF max=40
      Reward Value [TextLabel] P(0.3328, 0.6202) S(0.3607, 0.1489) z3 "1,000" Heavy #FFFFFF max=64
      Claim Tag UI [Frame] P(0.2753, 0.7939) S(0.449, 0.1145) z4
        Art [ImageLabel] S(1, 1) img:131423325026452
        Tag Label [TextLabel] P(0.1157, 0.2333) S(0.8301, 0.5333) z2 "CLAIM NOW" Heavy #0D0A1C max=26
    Day Card 03 [ImageButton] P(0.4475, 0.2236) S(0.2029, 0.2936) z6
      Art [ImageLabel] P(-0.0957, -0.0729) S(1.1911, 1.2078) img:138973527655694
      Day Label [TextLabel] P(0.3718, 0.0744) S(0.2765, 0.092) z2 "DAY 3" Heavy #FFFFFF max=40
      Reward Value [TextLabel] P(0.3254, 0.6208) S(0.3767, 0.1495) z3 "2,500" Heavy #FFFFFF max=64
      Currency Tag UI [Frame] P(0.3755, 0.8029) S(0.2486, 0.0997) z4
        Art [ImageLabel] S(1, 1) img:126472791793872
        Tag Label [TextLabel] P(0.209, 0.2115) S(0.6287, 0.5769) z2 "GEMS" Heavy #59BFFF max=24
      ⤷ ×4 siblings like "Day Card 03" (same tree); per-copy differences:
        · Day Card 04: P(0.0349, 0.5253); z7; Art img:74018695406816; Day Label P(0.3681, 0.0744); Day Label "DAY 4"; Day Label S(0.2845, 0.092); Reward Value P(0.3217, 0.6208); Reward Value "5,000"; Reward Value S(0.3847, 0.1495)
        · Day Card 05: P(0.2412, 0.5253); z8; Art img:90003112198137; Day Label "DAY 5"; Reward Value P(0.2939, 0.6208); Reward Value "10,000"; Reward Value S(0.4448, 0.1495)
        · Day Card 06: P(0.4475, 0.5253); z9; Art img:113168626488746; Day Label P(0.3699, 0.0744); Day Label "DAY 6"; Day Label S(0.2805, 0.092); Reward Value P(0.2976, 0.6208); Reward Value "15,000"; Reward Value S(0.4368, 0.1495)
    Day Card 07 [ImageButton] P(0.6538, 0.2236) S(0.3113, 0.5954) z10
      Art [ImageLabel] P(-0.0624, -0.0359) S(1.1245, 1.1025) img:109913372182532
      Day Label [TextLabel] P(0.3898, 0.0367) S(0.2377, 0.0605) z2 "DAY 7" Heavy #FFFFFF max=52
      Permanent Tag UI [Frame] P(0.281, 0.1615) S(0.4295, 0.1061) z3
        Art [ImageLabel] S(1, 1) img:133196750938875
        Tag Label [TextLabel] P(0.0828, 0.1961) S(0.9018, 0.6096) z2 "PERMANENT" Heavy #FFFFFF max=40 Rotation=4
      Reward Name [TextLabel] P(0.3028, 0.7288) S(0.4257, 0.1664) z4 "RPG" Heavy #FFFFFF max=100
      Rarity Tag UI [Frame] P(0.2472, 0.8952) S(0.5054, 0.0605) z5
        Art [ImageLabel] S(1, 1) img:91335999477117
        Tag Label [TextLabel] P(0.067, 0.2344) S(0.9353, 0.5313) z2 "LEGENDARY WEAPON" Heavy #0D0A1C max=28
    Next Reward Timer [Frame] P(0.3011, 0.8467) S(0.3977, 0.0813) z11
      Art [ImageLabel] P(-0.0466, -0.2438) S(1.0933, 1.6842) img:83619619294874
      Button Label [TextLabel] P(0.2323, 0.3324) S(0.648, 0.3324) z2 "NEXT REWARD IN  13:24:58" Heavy #B9A9D9 max=40
```

### Daily Spins (69 instances)

```
Daily Spins [ScreenGui] Enabled=False ResetOnSpawn=False ScreenInsets=DeviceSafeInsets ZIndexBehavior=Sibling
  Dim Overlay UI [Frame] = identical to Settings › Dim Overlay UI (1 instances)  px[0,0 1920x1080]
  Daily Spins Container [Frame] P(0.5, 0.4908) S(0.6814, 0.5261) A(0.5, 0.5) z2 AR=2.3025  px[306,246 1308x568]
    Art [ImageLabel] P(-0.0188, -0.031) S(1.0377, 1.0869) img:124085912966106
    Top Menu Container [Frame] P(0.0306, 0.0542) S(0.2915, 0.1169) z2
      Top Menu Tab 01 [Frame] P(0, 0.0181) S(0.4937, 0.9669) z2
        Art [ImageLabel] P(-0.1306, -0.2741) S(1.2618, 1.7695) img:130963585909584
        Button Label [TextLabel] P(0.3144, 0.3115) S(0.4015, 0.3738) z2 "DAILY" Heavy #B9A9D9 max=40
        ⤷ ×2 siblings like "Top Menu Tab 01" (same tree); per-copy differences:
          · Top Menu Tab 02: P(0.5008, 0); z3; S(0.4992, 1); Art img:110273546838339; Art P(-0.1366, -0.2741); Art S(1.2731, 1.7831); Button Label #FFFFFF; Button Label P(0.4449, 0.3193); Button Label "SPIN"; Button Label S(0.312, 0.3614)
    Header Info [TextLabel] P(0.7301, 0.095) S(0.1923, 0.0352) z3 "2 FREE SPINS EVERY DAY" Bold #FFC13B max=32
    Close Button [ImageButton] P(0.9234, 0.0563) S(0.0489, 0.1126) z4
      Art [ImageLabel] P(-0.4875, -0.3656) S(1.975, 1.975) img:87934738225568
    Reel Container [Frame] P(0.0569, 0.3097) S(0.8863, 0.3097) z5
      Reward Card 01 [ImageButton] P(0, 0.0034) S(0.141, 0.9932) z2
        Art [ImageLabel] P(-0.1578, -0.1087) S(1.315, 1.3101) img:110165926703254
        Reward Value [TextLabel] P(0.3651, 0.4457) S(0.2906, 0.2231) z2 "X2" Heavy #8B5CFF max=64
        Reward Label [TextLabel] P(0.2214, 0.6859) S(0.6011, 0.0858) z3 "COINS 15 MIN" Heavy #FFFFFF max=24
        ⤷ ×7 siblings like "Reward Card 01" (same tree); per-copy differences:
          · Reward Card 02: P(0.1432, 0.0034); z3; Art img:95853150922122; Reward Value #FFC13B; Reward Value P(0.2979, 0.4457); Reward Value "600"; Reward Value S(0.436, 0.2231); Reward Label P(0.3682, 0.6859); Reward Label "COINS"; Reward Label S(0.284, 0.0858)
          · Reward Card 03: P(0.2863, 0.0034); z4; Art img:119003530866236; Reward Value #FFC13B; Reward Value P(0.2245, 0.4457); Reward Value "1,000"; Reward Value S(0.5945, 0.2231); Reward Label P(0.3682, 0.6859); Reward Label "COINS"; Reward Label S(0.284, 0.0858)
          · Reward Card 04: P(0.4295, 0); z5; S(0.141, 1); Art img:97385221413200; Art P(-0.1578, -0.1045); Art S(1.315, 1.3011); Reward Value #59BFFF; Reward Value P(0.3896, 0.446); Reward Value "10"; Reward Value S(0.2378, 0.2216); Reward Label P(0.3284, 0.6847); Reward Label "TOKENS"; Reward Label S(0.3699, 0.0852)
          · Reward Card 05: P(0.5727, 0.0034); z6; Art img:87631407058169; Reward Value #FFC13B; Reward Value P(0.2306, 0.4457); Reward Value "1,500"; Reward Value S(0.5813, 0.2231); Reward Label P(0.3682, 0.6859); Reward Label "COINS"; Reward Label S(0.284, 0.0858)
          · Reward Card 06: P(0.7158, 0.0034); z7; Art img:115674659070949; Reward Value #FFC13B; Reward Value P(0.3101, 0.4457); Reward Value "250"; Reward Value S(0.4095, 0.2231); Reward Label P(0.3682, 0.6859); Reward Label "COINS"; Reward Label S(0.284, 0.0858)
          · Reward Card 07: P(0.859, 0.0034); z8; Art img:112790914515878; Reward Value #59BFFF; Reward Value P(0.4385, 0.4457); Reward Value "5"; Reward Value S(0.1321, 0.2231); Reward Label P(0.3284, 0.6859); Reward Label "TOKENS"; Reward Label S(0.3699, 0.0858)
    Spins Left Label [TextLabel] P(0.3938, 0.6917) S(0.2295, 0.0387) z6 "2 FREE SPINS LEFT TODAY" Heavy #B9A9D9 max=36
    Spin Button [ImageButton] P(0.3508, 0.7582) S(0.2984, 0.1591) z7
      Art [ImageLabel] P(-0.0666, -0.2013) S(1.1332, 1.5752) img:73494365881083
    Next Spin Label [TextLabel] P(0.0598, 0.8201) S(0.1923, 0.0352) z8 "NEXT FREE SPIN  13:24:58" Heavy #B9A9D9 max=32
    Token Balance [TextLabel] P(0.8646, 0.814) S(0.1098, 0.0475) z9 "70 TOKENS" Heavy #59BFFF max=44
```

### Player Head Tag (64 instances)

```
Player Head Tag [ScreenGui] Enabled=False ResetOnSpawn=False ScreenInsets=DeviceSafeInsets ZIndexBehavior=Sibling
  Player Head Tag [Frame] P(0.0811, 0.2741) S(0.2335, 0.165) AR=2.5157  px[156,296 448x178]
    Art [ImageLabel] P(-0.0549, -0.0988) S(1.11, 1.2772) img:104010296897182
    Username Label [TextLabel] P(0.3038, 0.1655) S(0.4963, 0.2076) z2 "RENKAMENS" Heavy #FFFFFF max=60
    Class Tag UI [Frame] P(0.3038, 0.4265) S(0.2476, 0.1571) z3
      Art [ImageLabel] S(1, 1) img:107717472954621
      Tag Label [TextLabel] P(0.1261, 0.2143) S(0.8076, 0.5714) z2 "SURVIVOR" Heavy #0D0A1C max=26
    Rank Container [Frame] P(0.0495, 0.7183) S(0.2855, 0.1908) z4
      Art [ImageLabel] S(1, 1) img:87277754446534
      Rank Value [TextLabel] P(0.3281, 0.1765) S(0.3544, 0.6471) z2 "LV 9" Heavy #FFC13B max=36
    Victories Container [Frame] P(0.3529, 0.7183) S(0.2855, 0.1908) z5
      Art [ImageLabel] S(1, 1) img:77266565363541
      Victories Value [TextLabel] P(0.3281, 0.1765) S(0.1603, 0.6471) z2 "21" Heavy #FFC13B max=36
    Deaths Container [Frame] P(0.6563, 0.7183) S(0.2855, 0.1908) z6
      Art [ImageLabel] S(1, 1) img:138728373135121
      Deaths Value [TextLabel] P(0.3281, 0.1765) S(0.1013, 0.6471) z2 "7" Heavy #FFFFFF max=36
  Player Head Tag [Frame] P(0.5, 0.2741) S(0.2335, 0.165) A(0.5, 0) z2 AR=2.5157  px[736,296 448x178]
    Art [ImageLabel] P(-0.0549, -0.0988) S(1.11, 1.2772) img:111095235166627
    Username Label [TextLabel] P(0.3038, 0.1655) S(0.489, 0.2076) z2 "TURBOTACO" Heavy #FFFFFF max=60
    Class Tag UI [Frame] P(0.3038, 0.4265) S(0.1785, 0.1571) z3
      Art [ImageLabel] S(1, 1) img:78236504222233
      Tag Label [TextLabel] P(0.175, 0.2143) S(0.702, 0.5714) z2 "MEDIC" Heavy #0D0A1C max=26
    Rank Container [Frame] P(0.0495, 0.7183) S(0.2855, 0.1908) z4
      Art [ImageLabel] S(1, 1) img:71651373868348
      Rank Value [TextLabel] P(0.3281, 0.1765) S(0.4556, 0.6471) z2 "LV 24" Heavy #FFC13B max=36
    Victories Container [Frame] P(0.3529, 0.7183) S(0.2855, 0.1908) z5
      Art [ImageLabel] S(1, 1) img:116126683088072
      Victories Value [TextLabel] P(0.3281, 0.1765) S(0.2109, 0.6471) z2 "88" Heavy #FFC13B max=36
    Deaths Container [Frame] P(0.6563, 0.7183) S(0.2855, 0.1908) z6
      Art [ImageLabel] S(1, 1) img:125495116909529
      Deaths Value [TextLabel] P(0.3281, 0.1765) S(0.1603, 0.6471) z2 "31" Heavy #FFFFFF max=36
  Player Head Tag [Frame] P(0.9188, 0.2741) S(0.2335, 0.165) A(1, 0) z3 AR=2.5157  px[1316,296 448x178]
    Art [ImageLabel] P(-0.0549, -0.0988) S(1.11, 1.2772) img:97778966097999
    Username Label [TextLabel] P(0.3038, 0.1655) S(0.4794, 0.2076) z2 "NITRONANA" Heavy #FFFFFF max=60
    Class Tag UI [Frame] P(0.3038, 0.4265) S(0.2186, 0.1571) z3
      Art [ImageLabel] S(1, 1) img:115300907008322
      Tag Label [TextLabel] P(0.1429, 0.2143) S(0.7714, 0.5714) z2 "OUTLAW" Heavy #0D0A1C max=26
    Rank Container [Frame] P(0.0495, 0.7183) S(0.2855, 0.1908) z4
      Art [ImageLabel] S(1, 1) img:91522727864801
      Rank Value [TextLabel] P(0.3281, 0.1765) S(0.4472, 0.6471) z2 "LV 57" Heavy #FFC13B max=36
    Victories Container [Frame] P(0.3529, 0.7183) S(0.2855, 0.1908) z5
      Art [ImageLabel] S(1, 1) img:93931657434466
      Victories Value [TextLabel] P(0.3281, 0.1765) S(0.3122, 0.6471) z2 "240" Heavy #FFC13B max=36
    Deaths Container [Frame] P(0.6563, 0.7183) S(0.2855, 0.1908) z6
      Art [ImageLabel] S(1, 1) img:90696578889761
      Deaths Value [TextLabel] P(0.3281, 0.1765) S(0.2109, 0.6471) z2 "64" Heavy #FFFFFF max=36
```

### Upgrade Selection (68 instances)

```
Upgrade Selection [ScreenGui] Enabled=False ResetOnSpawn=False ScreenInsets=DeviceSafeInsets ZIndexBehavior=Sibling
  Dim Overlay UI [Frame] S(1, 1) bg=#000000 bgT=0.6  px[0,0 1920x1080]
  Title Label [TextLabel] P(0.5, 0.1884) S(0.3172, 0.0676) A(0.5, 0) z2 "PICK AN UPGRADE" Heavy #FFFFFF max=100  px[655,204 609x73]
  Subtitle Label [TextLabel] P(0.5, 0.2639) S(0.1953, 0.0204) A(0.5, 0) z3 "WAVE 5 CLEARED  ·  CHOOSE ONE" Bold #FFC13B max=36  px[773,285 375x22]
  Upgrade Card 01 [ImageButton] P(0.1965, 0.5278) S(0.1945, 0.4185) A(0, 0.5) z4 AR=0.8263  px[377,344 373x452]
    Art [ImageLabel] P(-0.0691, -0.0407) S(1.1379, 1.1173) img:131612903443518
    Keybind Slot UI [Frame] P(0.0661, 0.0531) S(0.1178, 0.0973) z2
      Art [ImageLabel] S(1, 1) img:91841909929463
      Badge Label [TextLabel] P(0.3864, 0.1932) S(0.2455, 0.6136) z2 "1" Heavy #FFFFFF max=44
    New Tag UI [Frame] P(0.7596, 0.0664) S(0.174, 0.0664) z3
      Art [ImageLabel] S(1, 1) img:134534118821825
      Tag Label [TextLabel] P(0.2154, 0.2333) S(0.6148, 0.5333) z2 "NEW" Heavy #FFFFFF max=26
    Upgrade Name [TextLabel] P(0.2415, 0.6007) S(0.5581, 0.0642) z4 "NEW WEAPON" Heavy #FFFFFF max=48
    Upgrade Description [TextLabel] P(0.0806, 0.6903) S(0.8386, 0.0487) z5 "The next gun of your loadout" Bold #B9A9D9 align=Center max=32
    Rarity Tag UI [Frame] P(0.4035, 0.8628) S(0.1928, 0.0664) z6
      Art [ImageLabel] S(1, 1) img:74713151156883
      Tag Label [TextLabel] P(0.1944, 0.2333) S(0.66, 0.5333) z2 "RARE" Heavy #FFFFFF max=26
  Upgrade Card 02 [ImageButton] P(0.5, 0.5278) S(0.1945, 0.4174) A(0.5, 0.5) z5 AR=0.8285  px[773,345 373x451]
    Art [ImageLabel] P(-0.0691, -0.0421) S(1.1379, 1.1202) img:133154211546866
    Keybind Slot UI [Frame] P(0.0661, 0.0519) S(0.1178, 0.0976) z2
      Art [ImageLabel] S(1, 1) img:91841909929463
      Badge Label [TextLabel] P(0.3409, 0.1932) S(0.3436, 0.6136) z2 "2" Heavy #FFFFFF max=44
    New Tag UI [Frame] P(0.7596, 0.0652) S(0.174, 0.0665) z3
      Art [ImageLabel] S(1, 1) img:136098500115062
      Tag Label [TextLabel] P(0.2154, 0.2333) S(0.6148, 0.5333) z2 "NEW" Heavy #FFFFFF max=26
    Upgrade Name [TextLabel] P(0.0795, 0.6009) S(0.908, 0.0643) z4 "EXPLOSIVE HEADSHOTS" Heavy #FFFFFF max=48
    Upgrade Description [TextLabel] P(0.0806, 0.6908) S(0.8386, 0.0976) z5 "A headshot blows up the zombies around it" Bold #B9A9D9 align=Center max=32
    Rarity Tag UI [Frame] P(0.4115, 0.8638) S(0.1767, 0.0665) z6
      Art [ImageLabel] S(1, 1) img:130765577471127
      Tag Label [TextLabel] P(0.2121, 0.2333) S(0.6218, 0.5333) z2 "EPIC" Heavy #FFFFFF max=26
  Upgrade Card 03 [ImageButton] P(0.8035, 0.5278) S(0.1945, 0.4174) A(1, 0.5) z6 AR=0.8285  px[1169,345 373x451]
    Art [ImageLabel] P(-0.0691, -0.0421) S(1.1379, 1.1202) img:136465613551012
    Keybind Slot UI [Frame] P(0.0661, 0.0519) S(0.1178, 0.0976) z2
      Art [ImageLabel] S(1, 1) img:91841909929463
      Badge Label [TextLabel] P(0.3409, 0.1932) S(0.3436, 0.6136) z2 "3" Heavy #FFFFFF max=44
    New Tag UI [Frame] P(0.7596, 0.0652) S(0.174, 0.0665) z3
      Art [ImageLabel] S(1, 1) img:96358922087817
      Tag Label [TextLabel] P(0.2154, 0.2333) S(0.6148, 0.5333) z2 "NEW" Heavy #0D0A1C max=26
    Upgrade Name [TextLabel] P(0.3473, 0.6009) S(0.3296, 0.0643) z4 "BIG MAG" Heavy #FFFFFF max=48
    Upgrade Description [TextLabel] P(0.0806, 0.6908) S(0.8386, 0.0488) z5 "+50% rounds in every magazine" Bold #B9A9D9 align=Center max=32
    Rarity Tag UI [Frame] P(0.362, 0.8638) S(0.2758, 0.0665) z6
      Art [ImageLabel] S(1, 1) img:113130620411556
      Tag Label [TextLabel] P(0.1359, 0.2333) S(0.7864, 0.5333) z2 "COMMON" Heavy #0D0A1C max=26
  Reroll Button [ImageButton] P(0.5, 0.8372) S(0.1606, 0.0669) A(0.5, 1) z7 AR=4.2701  px[806,832 308x72]
    Art [ImageLabel] P(-0.0798, -0.2438) S(1.1599, 1.6842) img:92766423851791
  Auto Pick Label [TextLabel] P(0.5, 0.8759) S(0.0792, 0.0185) A(0.5, 1) z8 "AUTO-PICK IN 8" Heavy #B9A9D9 max=32  px[884,926 152x20]
```

### In-Game HUD (174 instances)

```
In-Game HUD [ScreenGui] Enabled=False ResetOnSpawn=False ScreenInsets=DeviceSafeInsets ZIndexBehavior=Sibling
  Squad Button [ImageButton] P(0.1186, 0.0111) S(0.1033, 0.0594) AR=3.0888  px[228,12 198x64]
    Art [ImageLabel] P(-0.1241, -0.2741) S(1.2486, 1.7695) img:102488643301775
  Wave Info Container [Frame] P(0.5, 0.0111) S(0.2439, 0.1706) A(0.5, 0) z2 AR=2.5423  px[726,12 468x184]
    Wave Container [Frame] P(0.0854, 0) S(0.8292, 0.5223) z2
      Art [ImageLabel] P(-0.0634, -0.183) S(1.127, 1.5135) img:119386316212396
      Wave Label [TextLabel] P(0.213, 0.1715) S(0.6202, 0.6549) z2 "WAVE 2" Heavy #FFFFFF max=100
    Boss Container [Frame] P(0, 0.5429) S(1, 0.4571) z3
      Art [ImageLabel] P(-0.0525, -0.209) S(1.1053, 1.5867) img:105424574669114
      Boss Tag UI [Frame] P(0.1841, 0.19) S(0.2157, 0.285) z2
        Art [ImageLabel] S(1, 1) img:105276233832108
        Tag Label [TextLabel] P(0.1386, 0.2292) S(0.7806, 0.5417) z2 "NEXT BOSS" Heavy #FFFFFF max=22
      Boss Name [TextLabel] P(0.4147, 0.1722) S(0.4266, 0.3207) z3 "THE COVE KING" Heavy #FFFFFF max=44
  Next Wave Announcement [Frame] P(0.5, 0.2111) S(0.1918, 0.1593) A(0.5, 0) z3 AR=2.1413  px[776,228 368x172]
    Announcement Plate [Frame] S(1, 0.3733) z2
      Art [ImageLabel] P(-0.0668, -0.2741) S(1.1339, 1.7695) img:96359751034255
      Announcement Label [TextLabel] P(0.2028, 0.2726) S(0.6422, 0.4517) z2 "NEXT WAVE IN" Heavy #FFFFFF max=48
    Countdown UI [Frame] P(0.3698, 0.4419) S(0.2607, 0.5581) z3
      Art [ImageLabel] P(-0.325, -0.2438) S(1.65, 1.65) img:94093865067334
      Button Label [TextLabel] P(0.3177, 0.1458) S(0.3938, 0.7083) z2 "3" Heavy #FFFFFF max=100
  Skip Wave Container [Frame] P(0.925, 0.01) S(0.211, 0.1289) A(1, 0) z4 AR=2.9109  px[1371,11 405x139]
    Skip Wave Button [ImageButton] S(0.766, 0.592) z2
      Art [ImageLabel] P(-0.0838, -0.2209) S(1.1675, 1.6311) img:136264706820933
    Skip Vote UI [Frame] P(0.773, 0.0374) S(0.227, 0.5172) z3
      Art [ImageLabel] S(1, 1) img:87979913592103
      Badge Label [TextLabel] P(0.2935, 0.2986) S(0.4461, 0.4028) z2 "0/1" Heavy #FFFFFF max=48
    Auto Skip Container [Frame] P(0.0128, 0.6264) S(0.9378, 0.3736) z4
      Art [ImageLabel] P(-0.0758, -0.4154) S(1.1516, 2.1077) img:122769094588401
      Auto Skip Label [TextLabel] P(0.0526, 0.3077) S(0.3013, 0.3846) z2 "AUTO-SKIP" Heavy #B9A9D9 max=32
  Settings Button [ImageButton] P(0.9792, 0.0148) S(0.0292, 0.0519) A(1, 0) z5 AR=1  px[1824,16 56x56]
    Art [ImageLabel] P(-0.5143, -0.3857) S(2.0286, 2.0286) img:117907024936005
  Usable Items Container [Frame] P(0.9827, 0.1556) S(0.1133, 0.1013) A(1, 0) z6 AR=1.9881  px[1669,168 217x109]
    Heal All Button [ImageButton] S(0.5034, 1) z2
      Art [ImageLabel] P(-0.2356, -0.1499) S(1.4703, 1.4717) img:96605410628882
    Nuke All Button [ImageButton] P(0.4966, 0) S(0.5034, 1) z3
      Art [ImageLabel] P(-0.2356, -0.1499) S(1.4703, 1.4717) img:81873692731083
  Upgrades Container [Frame] P(0.0173, 0.4442) S(0.0852, 0.3291) A(0, 0.5) z7 AR=0.46  px[33,302 163x355]
    Upgrades Title [TextLabel] P(0.041, 0) S(0.7134, 0.0563) z2 "UPGRADES" Heavy #B9A9D9 max=32
    Upgrade Card 01 [ImageButton] P(0, 0.0805) S(1, 0.4524) z3
      Art [ImageLabel] P(-0.1578, -0.1182) S(1.315, 1.3371) img:139807635165862
      Keybind Slot UI [Frame] P(0.726, 0.0833) S(0.1835, 0.1866) z2
        Art [ImageLabel] S(1, 1) img:106777040389792
        Badge Label [TextLabel] P(0.3, 0.1667) S(0.432, 0.6667) z2 "C" Heavy #FFFFFF max=32
      Price Label [TextLabel] P(0.1144, 0.5404) S(0.284, 0.1803) z3 "$10" Heavy #FFC13B max=48
      Card Label [TextLabel] P(0.1144, 0.7799) S(0.4558, 0.1244) z4 "HEALTH" Heavy #FFFFFF max=32
      ⤷ ×2 siblings like "Upgrade Card 01" (same tree); per-copy differences:
        · Upgrade Card 02: P(0, 0.5476); z4; Art img:111485632705697; Keybind Slot UI.Badge Label P(0.2833, 0.1667); Keybind Slot UI.Badge Label "V"; Keybind Slot UI.Badge Label S(0.468, 0.6667); Price Label "$150"; Price Label S(0.3831, 0.1803); Card Label "SHOTGUN"; Card Label S(0.5615, 0.1244)
  Money Products Container [Frame] P(0.0181, 0.7993) S(0.1304, 0.1696) A(0, 1) z8 AR=1.3668  px[35,680 250x183]
    Money Product Button 01 [Frame] S(1, 0.4978) z2
      Art [ImageLabel] P(-0.1038, -0.1469) S(1.2077, 1.5175) img:133849700511605
      Product Value [TextLabel] P(0.2604, 0.3509) S(0.5478, 0.3509) z2 "+$99,999" Heavy #FFFFFF max=52
      Price Tag UI [Frame] P(0.7396, 0) S(0.2556, 0.2632) z3
        Art [ImageLabel] S(1, 1) img:90510248158128
        Tag Label [TextLabel] P(0.2188, 0.2292) S(0.6075, 0.5417) z2 "R$ 99" Heavy #FFFFFF max=22
      ⤷ ×2 siblings like "Money Product Button 01" (same tree); per-copy differences:
        · Money Product Button 02: P(0, 0.5022); z3; Art img:96646665217373; Product Value "+$1,000"; Product Value S(0.4572, 0.3509); Price Tag UI S(0.2236, 0.2632); Price Tag UI.Art img:90862369608039; Price Tag UI.Tag Label P(0.25, 0.2292); Price Tag UI.Tag Label "R$ 9"; Price Tag UI.Tag Label S(0.54, 0.5417)
  Ult Charge Container [Frame] P(0.8979, 0.7574) S(0.0198, 0.1389) A(1, 1) z9 AR=0.2533  px[1686,668 38x150]
    Art [ImageLabel] S(1, 1) img:138507042702294
    Ult Charge UI [Frame] S(1, 0.1733) z2
      Art [ImageLabel] S(1, 1) img:80967780391968
      Badge Label [TextLabel] P(0.2632, 0.1731) S(0.5116, 0.6538) z2 "29" Heavy #0D0A1C max=28
  Abilities Container [Frame] P(0.9827, 0.521) S(0.0852, 0.4828) A(1, 0.5) z10 AR=0.3136  px[1723,302 163x521]
    Abilities Title [TextLabel] P(0.3651, 0) S(0.6407, 0.0384) z2 "ABILITIES" Heavy #B9A9D9 max=32
    Ability Card 01 [ImageButton] P(0, 0.0549) S(1, 0.3084) z3
      Art [ImageLabel] P(-0.1578, -0.1182) S(1.315, 1.3371) img:127534093757665
      Keybind Slot UI [Frame] P(0.726, 0.0833) S(0.1835, 0.1866) z2
        Art [ImageLabel] S(1, 1) img:106777040389792
        Badge Label [TextLabel] P(0.2833, 0.1667) S(0.468, 0.6667) z2 "G" Heavy #FFFFFF max=32
      Price Label [TextLabel] P(0.1144, 0.5404) S(0.3171, 0.1803) z3 "$50" Heavy #FFC13B max=48
      Card Label [TextLabel] P(0.1144, 0.7799) S(0.5615, 0.1244) z4 "GRENADE" Heavy #FFFFFF max=32
      ⤷ ×3 siblings like "Ability Card 01" (same tree); per-copy differences:
        · Ability Card 02: P(0, 0.3732); z4; Art img:81637994815500; Keybind Slot UI.Badge Label "X"; Price Label "$40"; Price Label S(0.3303, 0.1803); Card Label "BARRICADE"; Card Label S(0.687, 0.1244)
        · Ability Card 03: P(0, 0.6916); z5; Art img:97897316009467; Keybind Slot UI.Badge Label P(0.2667, 0.1667); Keybind Slot UI.Badge Label "Q"; Keybind Slot UI.Badge Label S(0.504, 0.6667); Price Label "ULT"; Card Label "AIRSTRIKE"; Card Label S(0.6077, 0.1244)
  Player Container [Frame] P(0.7089, 0.5759) S(0.125, 0.237) A(1, 0.5) z11 AR=0.9375  px[1121,494 240x256]
    Image [ImageLabel] S(1, 1) img:125256443016297
  Round Money Container [Frame] P(0.5, 0.8741) S(0.1427, 0.0778) A(0.5, 1) z12 AR=3.2619  px[823,860 274x84]
    Art [ImageLabel] S(1, 1) img:74780406950195
    Money Plate [Frame] P(0.3066, 0) S(0.6934, 1) z2
      Art [ImageLabel] P(-0.1516, -0.2571) S(1.3032, 1.6857) img:135702173692848
      Round Money Value [TextLabel] P(0.2658, 0.1786) S(0.5059, 0.6429) z2 "$60" Heavy #FFC13B max=88
  Hotbar Container [Frame] P(0.5, 0.9833) S(0.282, 0.1) A(0.5, 1) z13 AR=5.0139  px[689,954 541x108]
    Hotbar Slot 01 [Frame] S(0.2022, 1) z2
      Art [ImageLabel] P(-0.2356, -0.1704) S(1.4703, 1.4907) img:75462913076534
      Keybind Slot UI [Frame] P(0.0977, 0.0926) S(0.2192, 0.2222) z2
        Art [ImageLabel] S(1, 1) img:94781803337083
        Badge Label [TextLabel] P(0.375, 0.1667) S(0.27, 0.6667) z2 "1" Heavy #FFFFFF max=26
      ⤷ ×5 siblings like "Hotbar Slot 01" (same tree); per-copy differences:
        · Hotbar Slot 02: P(0.1994, 0.0056); z3; S(0.2022, 0.9889); Art img:116185397246459; Art P(-0.2356, -0.1779); Art S(1.4703, 1.5075); Keybind Slot UI P(0.0977, 0.088); Keybind Slot UI S(0.2192, 0.2247); Keybind Slot UI.Badge Label P(0.3333, 0.1667); Keybind Slot UI.Badge Label "2"; Keybind Slot UI.Badge Label S(0.36, 0.6667)
        · Hotbar Slot 03: P(0.3989, 0.0056); z4; S(0.2022, 0.9889); Art img:114051206819480; Art P(-0.2356, -0.1779); Art S(1.4703, 1.5075); Keybind Slot UI P(0.0977, 0.088); Keybind Slot UI S(0.2192, 0.2247); Keybind Slot UI.Badge Label P(0.3333, 0.1667); Keybind Slot UI.Badge Label "3"; Keybind Slot UI.Badge Label S(0.36, 0.6667)
        · Hotbar Slot 04: P(0.5983, 0.0056); z5; S(0.2022, 0.9889); Art img:130193220903955; Art P(-0.2356, -0.1779); Art S(1.4703, 1.5075); Keybind Slot UI P(0.0977, 0.088); Keybind Slot UI S(0.2192, 0.2247); Keybind Slot UI.Badge Label P(0.2917, 0.1667); Keybind Slot UI.Badge Label "4"; Keybind Slot UI.Badge Label S(0.45, 0.6667)
        · Hotbar Slot 05: P(0.7978, 0.0056); z6; S(0.2022, 0.9889); Art img:108072718401150; Art P(-0.2356, -0.1779); Art S(1.4703, 1.5075); Keybind Slot UI P(0.0977, 0.088); Keybind Slot UI S(0.2192, 0.2247); Keybind Slot UI.Badge Label P(0.3125, 0.1667); Keybind Slot UI.Badge Label "5"; Keybind Slot UI.Badge Label S(0.405, 0.6667)
```

### In-Game HUD - Squad Open (260 instances)

```
In-Game HUD - Squad Open [ScreenGui] Enabled=False ResetOnSpawn=False ScreenInsets=DeviceSafeInsets ZIndexBehavior=Sibling
  Squad Button [ImageButton] = identical to In-Game HUD › Squad Button (3 instances)  px[228,12 198x64]
  Wave Info Container [Frame] = identical to In-Game HUD › Wave Info Container (14 instances)  px[726,12 468x184]
  Next Wave Announcement [Frame] = identical to In-Game HUD › Next Wave Announcement (10 instances)  px[776,228 368x172]
  Skip Wave Container [Frame] = identical to In-Game HUD › Skip Wave Container (12 instances)  px[1371,11 405x139]
  Settings Button [ImageButton] = identical to In-Game HUD › Settings Button (3 instances)  px[1824,16 56x56]
  Usable Items Container [Frame] = identical to In-Game HUD › Usable Items Container (6 instances)  px[1669,168 217x109]
  Upgrades Container [Frame] = identical to In-Game HUD › Upgrades Container (24 instances)  px[33,302 163x355]
  Money Products Container [Frame] = identical to In-Game HUD › Money Products Container (18 instances)  px[35,680 250x183]
  Ult Charge Container [Frame] = identical to In-Game HUD › Ult Charge Container (7 instances)  px[1686,668 38x150]
  Abilities Container [Frame] = identical to In-Game HUD › Abilities Container (34 instances)  px[1723,302 163x521]
  Player Container [Frame] P(0.5, 0.5167) S(0.125, 0.237) A(0.5, 0.5) z11 AR=0.9375  px[840,430 240x256]
    Image [ImageLabel] S(1, 1) img:136313906547974
  Round Money Container [Frame] = identical to In-Game HUD › Round Money Container (7 instances)  px[823,860 274x84]
  Hotbar Container [Frame] = identical to In-Game HUD › Hotbar Container (32 instances)  px[689,954 541x108]
  Dim Overlay UI [Frame] S(1, 1) z14 bg=#000000 bgT=0.5  px[0,0 1920x1080]
  Squad Container [Frame] P(0.5, 0.4168) S(0.6502, 0.5261) A(0.5, 0.5) z15 AR=2.1969  px[336,166 1248x568]
    Art [ImageLabel] P(-0.0197, -0.031) S(1.0395, 1.0869) img:124947646330516
    Squad Title [TextLabel] P(0.0803, 0.0766) S(0.1151, 0.0722) z2 "SQUAD" Heavy #FFFFFF max=68
    Squad Info [TextLabel] P(0.1988, 0.0986) S(0.1255, 0.0352) z3 "WAVE 2  ·  0:19" Heavy #FFFFFF max=32
    Close Button [ImageButton] P(0.9229, 0.0563) S(0.0513, 0.1126) z4
      Art [ImageLabel] P(-0.4875, -0.3656) S(1.975, 1.975) img:87934738225568
    Column Label [TextLabel] P(0.0354, 0.2147) S(0.0536, 0.0282) z5 "PLAYER" Heavy #B9A9D9 max=26
      ⤷ ×5 siblings like "Column Label" (same tree); per-copy differences:
        · Column Label: P(0.5321, 0.2147); z6; "KILLS"; S(0.0389, 0.0282)
        · Column Label: P(0.6202, 0.2147); z7; "DEATHS"; S(0.0554, 0.0282)
        · Column Label: P(0.7243, 0.2147); z8; "CASH"; S(0.0372, 0.0282)
        · Column Label: P(0.8284, 0.2147); z9; "CONTRABAND"; S(0.0978, 0.0282)
    Drop Hint [TextLabel] P(0.7492, 0.1021) S(0.1601, 0.0282) z10 "HOVER YOURS TO DROP" Heavy #FFFFFF max=26 TextTransparency=0.1
    Player Row 01 [Frame] P(0.0171, 0.2615) S(0.9656, 0.1668) z11
      Art [ImageLabel] P(-0.0214, -0.2004) S(1.0428, 1.5717) img:94016127323039
      Player Name [TextLabel] P(0.0819, 0.231) S(0.121, 0.2848) z2 "USERNAME" Heavy #FFFFFF max=44
      Class Tag UI [Frame] P(0.0819, 0.5633) S(0.0805, 0.2321) z3
        Art [ImageLabel] S(1, 1) img:122834962580930
        Tag Label [TextLabel] P(0.1443, 0.2045) S(0.7682, 0.5909) z2 "SURVIVOR" Heavy #0D0A1C max=22
      Kills Value [TextLabel] P(0.5332, 0.3207) S(0.0332, 0.3586) z4 "42" Heavy #FFFFFF max=56
      Deaths Value [TextLabel] P(0.6244, 0.3207) S(0.0161, 0.3586) z5 "3" Heavy #FF2E8B max=56
      Cash Value [TextLabel] P(0.7323, 0.3312) S(0.0771, 0.3376) z6 "$1,250" Heavy #FFC13B max=52
      Contraband Value [TextLabel] P(0.8401, 0.4051) S(0.0779, 0.1899) z7 "NONE YET" Heavy #B9A9D9 max=30
      ⤷ ×4 siblings like "Player Row 01" (same tree); per-copy differences:
        · Player Row 02: P(0.0171, 0.4305); z12; Art img:138002208158330; Class Tag UI S(0.0589, 0.2321); Class Tag UI.Art img:73164670004294; Class Tag UI.Tag Label P(0.1972, 0.2045); Class Tag UI.Tag Label "MEDIC"; Class Tag UI.Tag Label S(0.6541, 0.5909); Kills Value "35"; Kills Value S(0.0314, 0.3586); Deaths Value "5"; Cash Value "$980"; Cash Value S(0.0627, 0.3376); Contraband Value #33D980; Contraband Value "1x MED KIT"; Contraband Value S(0.0842, 0.1899)
        · Player Row 03: P(0.0171, 0.5994); z13; Art img:109062171713033; Class Tag UI S(0.0713, 0.2321); Class Tag UI.Art img:72355242284072; Class Tag UI.Tag Label P(0.1628, 0.2045); Class Tag UI.Tag Label "OUTLAW"; Class Tag UI.Tag Label S(0.7284, 0.5909); Kills Value "61"; Kills Value S(0.0278, 0.3586); Deaths Value "2"; Cash Value "$2,400"; Cash Value S(0.086, 0.3376); Contraband Value #33D980; Contraband Value "1x NUKE"; Contraband Value S(0.0627, 0.1899)
        · Player Row 04: P(0.0171, 0.7684); z14; Art img:94838661970299; Class Tag UI S(0.0788, 0.2321); Class Tag UI.Art img:96454778900249; Class Tag UI.Tag Label P(0.1474, 0.2045); Class Tag UI.Tag Label "ENGINEER"; Class Tag UI.Tag Label S(0.7617, 0.5909); Kills Value "18"; Kills Value S(0.0278, 0.3586); Deaths Value "7"; Cash Value "$420"; Cash Value S(0.0627, 0.3376)
```

### Monster Mutation (120 instances)

```
Monster Mutation [ScreenGui] Enabled=False ResetOnSpawn=False ScreenInsets=DeviceSafeInsets ZIndexBehavior=Sibling
  Title Container [Frame] P(0.0253, 0.037) S(0.2346, 0.0731) AR=5.7013  px[49,40 450x79]
    Art [ImageLabel] S(1, 1) img:71210644569949
    Title Label [TextLabel] P(0.1052, 0) S(0.9136, 0.7089) z2 "MUTATION LAB" Heavy #FFFFFF max=92
    Subtitle Label [TextLabel] P(0.1585, 0.7722) S(0.9088, 0.2278) z3 "COMBINE MONSTER ENERGY INTO POTIONS" Bold #FFC13B max=30
  Currency Container [Frame] ≈ Lobby HUD › Currency Container  px[1327,52 553x67], differs: P(0.9792, 0.0481)
  Mutation Container [Frame] P(0.5, 0.514) S(0.6918, 0.7206) A(0.5, 0.5) z3 AR=1.7069  px[296,166 1328x778]
    Art [ImageLabel] P(-0.0185, -0.0226) S(1.0371, 1.0635) img:99341368297270
    Category Tab Container [Frame] P(0.0203, 0.0293) S(0.379, 0.0905) z2
      Category Tab 01 [Frame] S(0.4974, 1) z2
        Art [ImageLabel] P(-0.1038, -0.2585) S(1.2077, 1.7386) img:120434916248112
        Button Label [TextLabel] P(0.3622, 0.3082) S(0.4529, 0.3835) z2 "MUTATE" Heavy #FFFFFF max=44
        ⤷ ×2 siblings like "Category Tab 01" (same tree); per-copy differences:
          · Category Tab 02: P(0.5066, 0.017); z3; S(0.4932, 0.9688); Art img:122868778446129; Art P(-0.0991, -0.2581); Art S(1.1985, 1.7243); Button Label #B9A9D9; Button Label P(0.3391, 0.3006); Button Label "POTIONS"; Button Label S(0.5046, 0.3959)
    Brew Limit Label [TextLabel] P(0.8004, 0.0604) S(0.1894, 0.0283) z3 "2 BREWS LEFT TODAY" Heavy #FFC13B max=36
    Ingredient Slot 01 [Frame] P(0.0191, 0.173) S(0.1833, 0.3094) z4
      Art [ImageLabel] P(-0.106, -0.0789) S(1.2115, 1.2251) img:108744582150253
      Energy Name [TextLabel] P(0.1897, 0.8322) S(0.6697, 0.0831) z2 "ZOMBIE ENERGY" Heavy #FFFFFF max=32
      Energy Cost Tag UI [Frame] P(0.0768, 0.0723) S(0.2177, 0.1163) z3
        Art [ImageLabel] S(1, 1) img:101733397651777
        Tag Label [TextLabel] P(0.2642, 0.2143) S(0.5094, 0.5714) z2 "x10" Heavy #0D0A1C max=26
      ⤷ ×2 siblings like "Ingredient Slot 01" (same tree); per-copy differences:
        · Ingredient Slot 02: P(0.2525, 0.173); z5; Art img:140277414445597; Energy Name P(0.163, 0.8322); Energy Name "VAMPIRE ENERGY"; Energy Name S(0.7274, 0.0831); Energy Cost Tag UI S(0.1889, 0.1163); Energy Cost Tag UI.Art img:72382745067772; Energy Cost Tag UI.Tag Label P(0.3043, 0.2143); Energy Cost Tag UI.Tag Label "x5"; Energy Cost Tag UI.Tag Label S(0.4226, 0.5714)
    Result Card [ImageButton] P(0.4889, 0.173) S(0.492, 0.3094) z6
      Art [ImageLabel] P(-0.0395, -0.0789) S(1.0788, 1.2251) img:93791040338551
      New Tag UI [Frame] P(0.4112, 0.1636) S(0.1852, 0.108) z2
        Art [ImageLabel] S(1, 1) img:111950161471563
        Tag Label [TextLabel] P(0.1157, 0.2115) S(0.8301, 0.5769) z2 "NEW POTION" Heavy #0D0A1C max=24
      Potion Name [TextLabel] P(0.4112, 0.3131) S(0.466, 0.1537) z3 "IRON HIDE TONIC" Heavy #FFFFFF max=60
      Potion Effect 01 [TextLabel] P(0.4112, 0.5125) S(0.276, 0.0914) z4 "+50% max health" Heavy #FFFFFF max=36
      Potion Effect 02 [TextLabel] P(0.4112, 0.6287) S(0.3157, 0.0831) z5 "Lasts the whole match" Bold #B9A9D9 max=32
      Rarity Tag UI [Frame] P(0.4112, 0.7782) S(0.0964, 0.108) z6
        Art [ImageLabel] S(1, 1) img:88798692469871
        Tag Label [TextLabel] P(0.2222, 0.2115) S(0.6, 0.5769) z2 "EPIC" Heavy #FFFFFF max=24
    Select Energy Header [Frame] P(0.0242, 0.5095) S(0.9516, 0.0523) z7
      Art [ImageLabel] S(1, 1) img:138662403188583
      Section Title [TextLabel] P(0.0253, 0) S(0.1786, 0.7125) z2 "SELECT ENERGY" Heavy #FFFFFF max=48
      Section Info [TextLabel] P(0.9597, 0.1351) S(0.0436, 0.4423) z3 "PICK 2" Bold #FFC13B max=30
    Energy Container [Frame] P(0.0824, 0.5842) S(0.8353, 0.2323) z8
      Energy Card 01 [ImageButton] S(0.1924, 1) z2
        Art [ImageLabel] P(-0.1208, -0.1051) S(1.2412, 1.2998) img:124567000873483
        Energy Name [TextLabel] P(0.3405, 0.6217) S(0.344, 0.0996) z2 "ZOMBIE" Heavy #FFFFFF max=30
        Energy Count [TextLabel] P(0.3991, 0.7765) S(0.2175, 0.1217) z3 "x120" Heavy #33D980 max=36
        ⤷ ×5 siblings like "Energy Card 01" (same tree); per-copy differences:
          · Energy Card 02: P(0.2019, 0); z3; Art img:75427362859330; Energy Name P(0.3148, 0.6217); Energy Name "VAMPIRE"; Energy Name S(0.3996, 0.0996); Energy Count #FF2E8B; Energy Count P(0.4178, 0.7765); Energy Count "x45"; Energy Count S(0.177, 0.1217)
          · Energy Card 03: P(0.4038, 0); z4; Art img:109141668561799; Energy Name P(0.289, 0.6217); Energy Name "SKELETON"; Energy Name S(0.4553, 0.0996); Energy Count #9EBAD9; Energy Count P(0.4131, 0.7765); Energy Count "x80"; Energy Count S(0.1872, 0.1217)
          · Energy Card 04: P(0.6057, 0); z5; Art img:77519406423475; Energy Name P(0.392, 0.6217); Energy Name "BOSS"; Energy Name S(0.2327, 0.0996); Energy Count #FFC13B; Energy Count P(0.4459, 0.7765); Energy Count "x3"; Energy Count S(0.1163, 0.1217)
          · Energy Card 05: P(0.8076, 0); z6; Art img:109971706741373; Energy Name #B9A9D9; Energy Name P(0.4318, 0.6217); Energy Name "???"; Energy Name S(0.1467, 0.0996); Energy Count #B9A9D9; Energy Count P(0.3101, 0.7765); Energy Count "LOCKED"; Energy Count S(0.4097, 0.1217)
    Brew Cost Container [Frame] P(0.0211, 0.8687) S(0.2321, 0.1005) z9
      Art [ImageLabel] P(-0.0798, -0.2251) S(1.1599, 1.6317) img:84127142806707
      Brew Cost Value [TextLabel] P(0.325, 0.2494) S(0.2978, 0.4987) z2 "1,250" Heavy #FFC13B max=64
    Brew Button [ImageButton] P(0.2612, 0.8671) S(0.7185, 0.1033) z10
      Art [ImageLabel] P(-0.0272, -0.2264) S(1.0545, 1.6468) img:140593374519435
    Potion Count Badge UI [Frame] P(0.3811, 0.0206) S(0.0226, 0.0386) z11
      Art [ImageLabel] S(1, 1) img:133675710064003
      Badge Label [TextLabel] P(0.3333, 0.1667) S(0.36, 0.6667) z2 "3" Heavy #FFFFFF max=32
  Exit Button [ImageButton] ≈ Weapons Shop › Exit Button  px[805,965 310x80], differs: z4
```

### Lobby Entering (112 instances)

```
Lobby Entering [ScreenGui] Enabled=False ResetOnSpawn=False ScreenInsets=DeviceSafeInsets ZIndexBehavior=Sibling
  Dim Overlay UI [Frame] = identical to Settings › Dim Overlay UI (1 instances)  px[0,0 1920x1080]
  Level Up Container [Frame] P(0.4993, 0.0293) S(0.4223, 0.1304) A(0.5, 0) z2 AR=5.7592  px[553,32 811x141]
    Art [ImageLabel] P(-0.0318, -0.1349) S(1.0318, 1.3849) img:93979643706444
    XP Panel [Frame] P(0.1833, 0.0099) S(0.8167, 0.9815) z2
      Art [ImageLabel] P(-0.0371, -0.1274) S(1.0744, 1.3575) img:82274130567465
      Level Value [TextLabel] P(0.0426, 0.152) S(0.168, 0.3907) z2 "LV 8" Heavy #FFFFFF max=88
      Rank Name [TextLabel] P(0.2238, 0.2822) S(0.1549, 0.1592) z3 "PRIVATE" Heavy #FFC13B max=36
      XP Gained Value [TextLabel] P(0.6707, 0.1809) S(0.3098, 0.3329) z4 "+5,351 XP" Heavy #33D980 max=76
      XP Bar Label [TextLabel] P(0.4155, 0.6476) S(0.1826, 0.123) z5 "1,120 / 1,300 XP" Heavy #FFFFFF max=28
  XP Breakdown Container [Frame] P(0.5, 0.1731) S(0.45, 0.0333) A(0.5, 0) z3 AR=24  px[528,187 864x36]
    Waves XP Tag UI [Frame] S(0.1875, 1) z2
      Art [ImageLabel] S(1, 1) img:136038874136528
      Tag Label [TextLabel] P(0.0864, 0.25) S(0.8933, 0.5) z2 "WAVES   +1,725" Heavy #33D980 max=30
    Kills XP Tag UI [Frame] P(0.1991, 0) S(0.1516, 1) z3
      Art [ImageLabel] S(1, 1) img:96864286967835
      Tag Label [TextLabel] P(0.1069, 0.25) S(0.8492, 0.5) z2 "KILLS   +551" Heavy #33D980 max=30
    New best XP Tag UI [Frame] P(0.3623, 0) S(0.2153, 1) z4
      Art [ImageLabel] S(1, 1) img:105584121209173
      Tag Label [TextLabel] P(0.0753, 0.25) S(0.9174, 0.5) z2 "NEW BEST   +1,155" Heavy #33D980 max=30
    Bosses XP Tag UI [Frame] P(0.5891, 0) S(0.1933, 1) z5
      Art [ImageLabel] S(1, 1) img:120952172712379
      Tag Label [TextLabel] P(0.0838, 0.25) S(0.8989, 0.5) z2 "BOSSES   +1,320" Heavy #33D980 max=30
    Bounties XP Tag UI [Frame] P(0.794, 0) S(0.206, 1) z6
      Art [ImageLabel] S(1, 1) img:104811889463477
      Tag Label [TextLabel] P(0.0787, 0.25) S(0.9101, 0.5) z2 "BOUNTIES   +600" Heavy #33D980 max=30
  Player Container 02 [Frame] P(0.1599, 0.5035) S(0.1172, 0.1505) A(0, 0.5) z4 AR=1.3846  px[307,462 225x163]
    Art [ImageLabel] S(1, 1) img:129479538507070
    Player Head Tag [Frame] P(0.1067, 0) S(0.7067, 0.5538) z2
      Art [ImageLabel] S(1, 1) img:101645915113070
      Username Label [TextLabel] S(1.08, 0.3556) z2 "USERNAME" Heavy #FFFFFF max=52
      Class Label [TextLabel] P(0.2987, 0.4333) S(0.5638, 0.1778) z3 "SURVIVOR" Heavy #9999AD max=26
      Kills Value [TextLabel] P(0.5, 0.7333) S(0.3328, 0.2667) z4 "1,012" Heavy #FF2E8B max=40
  Player Container 01 [Frame] P(0.4083, 0.4306) S(0.1563, 0.1574) A(0.5, 0.5) z5 AR=1.7647  px[634,380 300x170]
    Art [ImageLabel] S(1, 1) img:121104360495010
    Player Head Tag [Frame] P(0.05, 0) S(0.8267, 0.5294) z2
      Art [ImageLabel] S(1, 1) img:116370959810856
      MVP Tag UI [Frame] P(0, 0.0111) S(0.3185, 0.3333) z2
        Art [ImageLabel] S(1, 1) img:98908921723341
        Tag Label [TextLabel] P(0.1772, 0.2167) S(0.7656, 0.5667) z2 "★ MVP" Heavy #0D0A1C max=28
      Username Label [TextLabel] P(0.3589, 0) S(0.6924, 0.3556) z3 "USERNAME" Heavy #FFFFFF max=52
      Class Label [TextLabel] P(0.3871, 0.4333) S(0.3048, 0.1778) z4 "OUTLAW" Heavy #FFC13B max=26
      Kills Value [TextLabel] P(0.4879, 0.7333) S(0.2177, 0.2667) z5 "1,001" Heavy #FF2E8B max=40
  Match Stats Container [Frame] P(0.9827, 0.5009) S(0.2154, 0.6027) A(1, 0.5) z6 AR=0.6353  px[1473,216 413x651]
    Match Stats Header [Frame] P(0.0162, 0) S(0.9674, 0.0625) z2
      Art [ImageLabel] S(1, 1) img:139172497883106
      Section Title [TextLabel] P(0.08, 0) S(0.4914, 0.7125) z2 "MATCH STATS" Heavy #FFFFFF max=48
    Gems Earned Card [ImageButton] P(0, 0.0862) S(1, 0.2225) z3
      Art [ImageLabel] P(-0.0624, -0.1312) S(1.1245, 1.3743) img:120414123386933
      Stat Label [TextLabel] P(0.0694, 0.1616) S(0.3552, 0.1381) z2 "GEMS EARNED" Heavy #FF2E8B max=32
      Stat Value [TextLabel] P(0.0694, 0.3273) S(0.397, 0.3729) z3 "+7,505" Heavy #FFFFFF max=88
      Stat Sub Label [TextLabel] P(0.0694, 0.7279) S(0.2664, 0.1105) z4 "TOTAL: 16,365" Bold #B9A9D9 max=26
    Squad Kills Card [ImageButton] P(0, 0.3166) S(1, 0.2225) z4
      Art [ImageLabel] P(-0.0624, -0.1312) S(1.1245, 1.3743) img:136294362056284
      Stat Label [TextLabel] P(0.0694, 0.1616) S(0.3265, 0.1381) z2 "SQUAD KILLS" Heavy #FF8026 max=32
      Stat Value [TextLabel] P(0.0694, 0.3273) S(0.303, 0.3729) z3 "2,013" Heavy #FFFFFF max=88
      Stat Sub Label [TextLabel] P(0.0694, 0.7279) S(0.1959, 0.1105) z4 "YOU: 1,001" Bold #B9A9D9 max=26
    Wave Reached Card [ImageButton] P(0, 0.5369) S(1, 0.2326) z5
      Art [ImageLabel] P(-0.0624, -0.0819) S(1.1245, 1.3144) img:122414854136283
      Stat Label [TextLabel] P(0.0694, 0.1982) S(0.4022, 0.1321) z2 "WAVE REACHED" Heavy #59BFFF max=32
      Stat Value [TextLabel] P(0.0694, 0.3567) S(0.1201, 0.3567) z3 "21" Heavy #FFFFFF max=88
      Stat Sub Label [TextLabel] P(0.0694, 0.7398) S(0.1593, 0.1057) z4 "BEST: 21" Bold #B9A9D9 max=26
      New Best Tag UI [Frame] P(0.6933, 0) S(0.2467, 0.1717) z5
        Art [ImageLabel] S(1, 1) img:120344275906024
        Tag Label [TextLabel] P(0.1373, 0.2115) S(0.7835, 0.5769) z2 "NEW BEST" Heavy #0D0A1C max=24
    Time Survived Card [ImageButton] P(0, 0.7674) S(1, 0.2326) z6
      Art [ImageLabel] P(-0.0624, -0.0819) S(1.1245, 1.3144) img:120240315024527
      Stat Label [TextLabel] P(0.0694, 0.1982) S(0.3866, 0.1321) z2 "TIME SURVIVED" Heavy #FFC13B max=32
      Stat Value [TextLabel] P(0.0694, 0.3567) S(0.316, 0.3567) z3 "13:40" Heavy #FFFFFF max=88
      Stat Sub Label [TextLabel] P(0.0694, 0.7398) S(0.2194, 0.1057) z4 "BEST: 13:40" Bold #B9A9D9 max=26
      New Best Tag UI [Frame] P(0.6933, 0) S(0.2467, 0.1717) z5
        Art [ImageLabel] S(1, 1) img:107196240633733
        Tag Label [TextLabel] P(0.1373, 0.2115) S(0.7835, 0.5769) z2 "NEW BEST" Heavy #0D0A1C max=24
  Lobby Button [ImageButton] P(0.9819, 0.9502) S(0.2138, 0.1207) A(1, 1) z7 AR=3.1472  px[1475,896 410x130]
    Art [ImageLabel] P(-0.0634, -0.1396) S(1.1267, 1.3988) img:70748244379011
```

### Round Results (79 instances)

```
Round Results [ScreenGui] Enabled=False ResetOnSpawn=False ScreenInsets=DeviceSafeInsets ZIndexBehavior=Sibling
  Dim Overlay UI [Frame] ≈ In-Game HUD - Squad Open › Dim Overlay UI  px[0,0 1920x1080], differs: ZIndex=<default>
  Results Container [Frame] P(0.5, 0.4908) S(0.6502, 0.6743) A(0.5, 0.5) z2 AR=1.7142  px[336,166 1248x728]
    Art [ImageLabel] P(-0.0197, -0.0242) S(1.0395, 1.0678) img:86512949763738
    Header Container [Frame] P(0.0306, 0.0275) S(0.9405, 0.0879) z2
      Art [ImageLabel] S(1, 1) img:104386502506343
      Header Title [TextLabel] P(0.0562, 0.0625) S(0.3385, 0.875) z2 "SQUAD WIPED" Heavy #FFFFFF max=92
      Return Label [TextLabel] P(0.8356, 0.1563) S(0.1279, 0.3125) z3 "RETURNING IN" Heavy #B9A9D9 max=32
      Return Timer UI [Frame] P(0.9659, 0) S(0.0341, 0.625) z4
        Art [ImageLabel] S(1, 1) img:105523190664687
        Badge Label [TextLabel] P(0.1625, 0.2) S(0.729, 0.6) z2 "20" Heavy #0D0A1C max=40
    Wave Card [ImageButton] P(0.0236, 0.1711) S(0.4274, 0.5916) z3
      Art [ImageLabel] P(-0.0484, -0.0441) S(1.0965, 1.1258) img:73562681815674
      Wave Label [TextLabel] P(0.3078, 0.0775) S(0.415, 0.0557) z2 "WAVE REACHED" Heavy #FF2E8B max=40
      Wave Value [TextLabel] P(0.3162, 0.1263) S(0.3968, 0.5385) z3 "21" Heavy #FFFFFF max=100
      New Best Tag UI [Frame] P(0.3931, 0.6207) S(0.2137, 0.0743) z4
        Art [ImageLabel] S(1, 1) img:133745464281288
        Tag Label [TextLabel] P(0.1228, 0.2344) S(0.8147, 0.5313) z2 "NEW BEST" Heavy #0D0A1C max=28
      Squad Kills Container [Frame] P(0.0575, 0.7461) S(0.4274, 0.1857) z5
        Art [ImageLabel] S(1, 1) img:132710483231091
        Stat Label [TextLabel] P(0.2719, 0.2) S(0.4216, 0.1625) z2 "SQUAD KILLS" Heavy #B9A9D9 max=22
        Stat Value [TextLabel] P(0.2719, 0.425) S(0.3505, 0.425) z3 "2,013" Heavy #FFFFFF max=56
      Time Survived Container [Frame] P(0.5149, 0.7461) S(0.4274, 0.1857) z6
        Art [ImageLabel] S(1, 1) img:94909205766457
        Stat Label [TextLabel] P(0.2719, 0.2) S(0.4926, 0.1625) z2 "TIME SURVIVED" Heavy #B9A9D9 max=22
        Stat Value [TextLabel] P(0.2719, 0.425) S(0.3647, 0.425) z3 "13:40" Heavy #FFFFFF max=56
    Gems Card [ImageButton] P(0.4593, 0.1711) S(0.5171, 0.2757) z4
      Art [ImageLabel] P(-0.04, -0.0946) S(1.0798, 1.2699) img:110701547367116
      Gems Label [TextLabel] P(0.0538, 0.1464) S(0.2677, 0.1096) z2 "GEMS EARNED" Heavy #59BFFF max=36
      Gems Value [TextLabel] P(0.1994, 0.3282) S(0.3028, 0.4731) z3 "7.6K" Heavy #FFFFFF max=100
      Total Label [TextLabel] P(0.8655, 0.3655) S(0.087, 0.0797) z4 "TOTAL" Heavy #B9A9D9 max=26
      Total Value [TextLabel] P(0.7927, 0.4726) S(0.1656, 0.1843) z5 "16,365" Heavy #FFFFFF max=60
    Double Gems Card [ImageButton] P(0.4593, 0.4595) S(0.5171, 0.3032) z5
      Art [ImageLabel] P(-0.04, -0.0861) S(1.0798, 1.2455) img:133028327833325
      Bonus Tag UI [Frame] P(0.0538, 0.115) S(0.1208, 0.1178) z2
        Art [ImageLabel] S(1, 1) img:107140397242037
        Tag Label [TextLabel] P(0.1795, 0.2115) S(0.6923, 0.5769) z2 "BONUS" Heavy #FFFFFF max=24
      Double Label [TextLabel] P(0.0538, 0.2781) S(0.5638, 0.1676) z3 "DOUBLE YOUR GEMS" Heavy #FFFFFF max=60
      Double Value [TextLabel] P(0.7896, 0.2577) S(0.169, 0.2219) z4 "15.1K" Heavy #FFFFFF max=80
      Robux Double Button [ImageButton] P(0.0457, 0.5353) S(0.4499, 0.3641) z5
        Art [ImageLabel] P(-0.0895, -0.2264) S(1.1791, 1.6468) img:120333389261265
      Watch Ad Button [ImageButton] P(0.5043, 0.5353) S(0.4499, 0.3641) z6
        Art [ImageLabel] P(-0.0895, -0.2264) S(1.1791, 1.6468) img:100421269701855
    Action Container [Frame] P(0.0256, 0.7893) S(0.9496, 0.1681) z6
      Return To Lobby Button [ImageButton] P(0, 0.0098) S(0.2516, 0.982) z2
        Art [ImageLabel] P(-0.0825, -0.1464) S(1.1653, 1.411) img:134036027972997
      Play Again Button [ImageButton] P(0.2573, 0) S(0.3293, 1) z3
        Art [ImageLabel] P(-0.0666, -0.1487) S(1.1332, 1.4248) img:114440233802906
      Vote Count Container [Frame] P(0.5855, 0.0098) S(0.0998, 0.982) z4
        Art [ImageLabel] P(-0.2079, -0.1464) S(1.4167, 1.411) img:109064559204027
        Vote Value [TextLabel] P(0.2806, 0.2621) S(0.4747, 0.3078) z2 "0/2" Heavy #FFFFFF max=60
        Vote Label [TextLabel] P(0.306, 0.6281) S(0.4199, 0.1082) z3 "VOTED" Heavy #B9A9D9 max=22
      Revive Button [ImageButton] P(0.6909, 0) S(0.3091, 1) z5
        Art [ImageLabel] P(-0.071, -0.1487) S(1.1419, 1.4248) img:129357551429107
  Upgrades Available Tag UI [Frame] P(0.2057, 0.887) S(0.1271, 0.0389) A(0, 1) z3 AR=5.8095  px[395,916 244x42]
    Art [ImageLabel] S(1, 1) img:72554556037753
    Tag Label [TextLabel] P(0.0574, 0.2619) S(0.9561, 0.4762) z2 "UPGRADES AVAILABLE" Heavy #0D0A1C max=32
```

## 4. Design tokens

Only text colours and the dim overlays are live properties. Every surface colour, corner radius, stroke and gradient is inside the PNGs listed in §5. Those images are private: rur, the public asset-delivery route and Tripwire's `download_asset` all answered 401/403. Panel and button colours, radii and stroke widths therefore cannot be read from the file. They have to be measured from the PNGs: get them from the designer or the Figma file, or set `ROBLOX_ASSET_DELIVERY_API_KEY` (Open Cloud, `legacy-asset:manage`) on an account that can read them, then rerun rur.

### Palette (TextColor3: every distinct value)

| Hex | Uses | Role (what it is used for) |
| --- | --- | --- |
| `#FFFFFF` | 281 | Primary text: titles, values, button and badge labels, names, stat values. |
| `#B9A9D9` | 115 | Secondary / muted lavender: section labels ("OWNED", "UPGRADES", "ABILITIES"), stat captions, descriptions, column headers, unselected tabs ("TIER 3"), not-owned item names. |
| `#FFC13B` | 81 | Gold, i.e. currency and highlight: prices, coin amounts, "$60" round money, subtitles under titles ("UPGRADE YOUR ARSENAL"), "XP" / "LV 9", "UPGRADE", owned counts. |
| `#0D0A1C` | 30 | Near-black ink on bright tag pills: rarity tags (LEGENDARY, COMMON…), "EQUIPPED", "NEW BEST", "UPGRADES AVAILABLE", the ult-charge "29", class tags in rows, the "✓ CLAIMED" stamp. |
| `#33D980` | 24 | Green, positive: stat bonuses ("+19.5"), "UNCOMMON", "MONSTER", found counts, "GEMS", contraband held. |
| `#FF2E8B` | 16 | Pink/magenta, danger or epic: deaths, "EPIC" rarity, boss counts, "WAVE REACHED", health stat, featured title line 2. |
| `#59BFFF` | 15 | Blue, gems: gem reward values ("+ 1,000"), "GEMS EARNED", token balance. |
| `#9EBAD9` | 4 | Steel blue: "RARE" rarity label, small gem labels. |
| `#8B5CFF` | 3 | Violet: weapon type ("PISTOL"), "X2", gem label. |
| `#9999AD` | 2 | Grey: "COMMON" rarity and the default "SURVIVOR" class label. |
| `#FF8026` | 1 | Orange: "SQUAD KILLS" (Lobby Entering match stats). |
| `#000000` | 9 frames | Dim overlay backgrounds: transparency 0.7 on lobby modals, 0.6 on Upgrade Selection, 0.5 on Squad / Round Results, 0.4 for the stacked confirm dim. |

The rarity text colours are COMMON `#9999AD`, UNCOMMON `#33D980`, RARE `#9EBAD9`, EPIC `#FF2E8B`, LEGENDARY on a tag (`#0D0A1C` ink). They are not consistent everywhere: "RARE" is `#FFFFFF` on the weapon info panel. Check the art before fixing a rarity palette.

### Typography

- **Family:** Montserrat only (`Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy | Bold)`).
- **Heavy (503):** everything by default: titles, labels, values, tags, buttons.
- **Bold (69):** subtitles under screen titles, descriptions (quest, setting, upgrade), stat captions on the weapon panel, section info lines, footer hints, and the Lobby HUD level block.
- **Text is ALL CAPS** except descriptions and the display name.
- **MaxTextSize caps in use**, which approximate the design sizes at 1080p:

| max | Role |
| --- | --- |
| 100 | Hero numbers and featured titles. |
| 92 | Screen titles ("WEAPONS") and big item names. |
| 88 | Results stat values and round money. |
| 76 / 80 | XP gained, ability name. |
| 72 | Modal titles. |
| 68 | Confirm / squad titles, cost. |
| 64 | Reward values. |
| 60 | Stat values. |
| 56 / 52 | Medium values. |
| 48 | Currency pill values, section headers. |
| 44 / 42 / 40 | Tab and card labels. |
| 36 / 32 | Sub-headers, keybind letters, descriptions. |
| 30 / 28 | Subtitles, captions, tier tabs. |
| 26 / 24 / 22 | Small captions, item names in grids, tag pills. |

The most common caps are 30 (59), 26 (56), 48 (51), 32 (48), 24 (47), 40 (46), 44 (44) and 28 (43).

### Geometry and spacing (1920x1080, from the px rects)

- **Screen margin:** about 40 px. Title block at x 43-52, y 40. Currency bar right edge at 1880 (40 px), top 52. Settings button 40 px from the right. HUD side columns at x 33 and right edge 1886 (34 px).
- **Side panels** (Weapons, Classes, Equipment): 448 px wide, inset 36 px, y 186 → 1044 (858 px tall).
- **Centre modals:** 1248 px wide (`S.X=0.6502`) at x 336, y 166. Results is 1248x728, Squad 1248x568, Quests 1328x778, Settings 1048x928.
- **Exit button** for full-screen pages: 310x80 bottom centre at y 965 (shared by 8 screens). Close buttons on modals are small round icons top-right.
- **Currency bar:** 553x67, two pills of 230x67 plus a 68 px "+" button.
- **Title block:** 79 px tall. The title label is 70.9% of the block height (Heavy, cap 92) and the subtitle 22.8% (Bold gold, cap 30).
- **HUD cards:** upgrade and ability columns 163 px wide with about 160 px tall cards. Hotbar is 541x108 with 5 slots of about 109 px. Keybind badge is about 0.18 of the card width, in the top-right corner.
- **Corner radii, stroke widths, gradients:** not present as instances (see the note at the top of §4).

## 5. Asset ids

351 distinct `rbxassetid` images, 497 references, all `ImageLabel.ImageContent`. No ImageButton images, no sounds, no meshes or decals in the UI. Workspace has only the default baseplate texture and spawn decal. Every id was private to anonymous asset delivery (401). Ids are listed by the screen that uses them first. The path is the ImageLabel's parent: the label is the `Art` child unless a name is given in the path. Ids used more than once give their total count.

**Lobby HUD**

- `95385927520034` Level Container
- `103060127131943` Level Container › Round State Container
- `132354210830277` Level Container › Round State Container › Round Info Container › Objective Progress Container
- `133212127550433` Currency Container › Coins Container — ×9 uses (Lobby HUD, Weapons Shop, Robux Shop, Index, Classes, Equipment, Quests - Daily, Quests - Weekly, Monster Mutation)
- `124051185775739` Currency Container › Coins Container › Price Container 01 — ×9 uses (Lobby HUD, Weapons Shop, Robux Shop, Index, Classes, Equipment, Quests - Daily, Quests - Weekly, Monster Mutation)
- `117488698850227` Currency Container › Add Currency Button — ×9 uses (Lobby HUD, Weapons Shop, Robux Shop, Index, Classes, Equipment, Quests - Daily, Quests - Weekly, Monster Mutation)
- `127612138989771` Currency Container › Energy Container — ×9 uses (Lobby HUD, Weapons Shop, Robux Shop, Index, Classes, Equipment, Quests - Daily, Quests - Weekly, Monster Mutation)
- `86413066371189` Currency Container › Energy Container › Price Container 01 — ×9 uses (Lobby HUD, Weapons Shop, Robux Shop, Index, Classes, Equipment, Quests - Daily, Quests - Weekly, Monster Mutation)
- `127246397724885` Left Menu Container › Daily Rewards Button
- `73853576426051` Left Menu Container › Shop Button
- `128090333006940` Left Menu Container › Daily Spins Button
- `122739019370404` Left Menu Container › Invite Friends Button
- `135852007616651` Bottom Menu Container › Menu Button
- `130257945394564` Bottom Menu Container › Weapons Button
- `98610907786270` Bottom Menu Container › Classes Button

**Weapons Shop**

- `82244686436632` Title Container
- `135859983790952` Tier Container
- `117154288608064` Tier Container › Tier Card 01
- `94958630353516` Tier Container › Tier Card 02
- `75316907530001` Tier Container › Tier Card 03
- `125548802721747` Tier Container › Tier Card 04
- `82511536364357` Weapon List Container
- `74747094875955` Weapon List Container › Tier 1 Header
- `75012799070771` Weapon List Container › Owned Count UI
- `123404956544074` Weapon List Container › Weapon Card 01
- `73436236494805` Weapon List Container › Weapon Card 02
- `117416028118163` Weapon List Container › Weapon Card 03
- `90195836579340` Weapon List Container › Weapon Card 04
- `132079874668558` Weapon List Container › Not Owned Count UI
- `101908562587014` Weapon List Container › Weapon Card 05
- `70432781426856` Weapon List Container › Weapon Card 06
- `91149835129162` Weapon List Container › Weapon Card 07
- `122676223998162` Weapon List Container › Weapon Card 08
- `94894442574611` Weapon Info Container
- `76249517702705` Weapon Info Container › Stat Container 01 — ×3 uses (Weapons Shop ×3)
- `87233388169296` Weapon Info Container › Upgrade Header
- `138863731477205` Weapon Info Container › Upgrade Button
- `113860369732059` Weapon Info Container › Try Button
- `109356623109379` Weapon Info Container › Show Button
- `86162458886427` Weapon Info Container › Equipped Button
- `117074096317449` Stage Container › Image
- `90010497710665` Skin Plate Container
- `115956195301386` Skin Container › Image
- `135962089193493` Exit Button — ×8 uses (Weapons Shop, Robux Shop, Index, Classes, Equipment, Quests - Daily, Quests - Weekly, Monster Mutation)

**Robux Shop**

- `122910304446957` Title Container
- `117101296521126` Shop Container
- `137281746135871` Shop Container › Category Tab Container › Category Tab 01
- `119325174776269` Shop Container › Category Tab Container › Category Tab 02
- `113666052844282` Shop Container › Category Tab Container › Category Tab 03
- `104210793573965` Shop Container › Category Tab Container › Category Tab 04
- `131995510832205` Shop Container › Category Tab Container › Category Tab 05
- `126133567391830` Shop Container › Featured Header
- `83259412357554` Shop Container › Featured Card 01
- `79711321775618` Shop Container › Featured Card 01 › Price Button
- `108556591273891` Shop Container › Featured Card 02
- `76982159966074` Shop Container › Featured Card 02 › Price Button
- `137631189209311` Shop Container › Gems Header
- `128812146012773` Shop Container › Gem Pack Container › Gem Pack Card 01
- `137567530957986` Shop Container › Gem Pack Container › Gem Pack Card 01 › Price Button
- `129484553498841` Shop Container › Gem Pack Container › Gem Pack Card 02
- `138508283109286` Shop Container › Gem Pack Container › Gem Pack Card 02 › Price Button
- `109435065174700` Shop Container › Gem Pack Container › Gem Pack Card 03
- `138202877248174` Shop Container › Gem Pack Container › Gem Pack Card 03 › Price Button
- `101044918543698` Shop Container › Gem Pack Container › Gem Pack Card 04
- `123408593698389` Shop Container › Gem Pack Container › Gem Pack Card 04 › Price Button

**Index**

- `96313689585852` Title Container
- `90116331032962` Category List Container
- `102879682101068` Category List Container › Categories Header
- `122107874079539` Category List Container › Category Card 01
- `133728852931713` Category List Container › Category Card 02
- `71162335431119` Category List Container › Completion Header
- `110044685260426` Category List Container › Reward Card
- `112637994550561` Enemy Grid Container
- `111429902403933` Enemy Grid Container › Monsters Header
- `122125101544239` Enemy Grid Container › Enemy Card 01
- `111095047400906` Enemy Grid Container › Enemy Card 02
- `118626977993579` Enemy Grid Container › Enemy Card 03
- `128997286701294` Enemy Grid Container › Enemy Card 04
- `97190183161617` Enemy Grid Container › Enemy Card 05
- `87946383224941` Enemy Grid Container › Enemy Card 06
- `85216215301706` Enemy Grid Container › Enemy Card 07
- `92532302598430` Enemy Grid Container › Enemy Card 08
- `130039893781785` Enemy Grid Container › Enemy Card 09
- `70589428557952` Enemy Grid Container › Enemy Card 10
- `83374273093874` Enemy Grid Container › Enemy Card 11
- `117700711518768` Enemy Grid Container › Enemy Card 12
- `123558359943642` Enemy Info Container
- `79340410811348` Enemy Info Container › Stat Container 01 — ×4 uses (Index ×4)
- `82774949048419` Enemy Info Container › Track Button

**Classes**

- `92395649426353` Title Container
- `117540626912917` Top Menu Container › Top Menu Tab 01
- `83791817744243` Top Menu Container › Top Menu Tab 02
- `132352515506787` Class List Container
- `126385323239527` Class List Container › All Classes Header
- `87369403762982` Class List Container › Class Card 01
- `114917201772506` Class List Container › Class Card 02
- `88145592925399` Class List Container › Class Card 03
- `110868345812178` Class List Container › Class Card 04
- `89873322598983` Class List Container › Class Card 05
- `110152762528398` Class List Container › Class Card 06
- `136317508440804` Class List Container › Class Card 07
- `72748462167739` Stage Container
- `88002291333331` Class Info Container
- `103336442378007` Class Info Container › Abilities Header
- `105895148284092` Class Info Container › Ability Card 01
- `79367531594226` Class Info Container › Ability Card 02
- `87260294542231` Class Info Container › Ability Card 03
- `93902344826618` Class Info Container › Help Button — ×2 uses (Classes, Equipment)
- `137969553595518` Class Info Container › Stat Container 01 — ×3 uses (Classes ×2, Equipment)
- `116477987709622` Class Info Container › Upgrade Button
- `125334353114191` Class Info Container › Equip Button — ×2 uses (Classes, Equipment)

**Equipment**

- `75976353207490` Title Container
- `115579819543890` Top Menu Container › Top Menu Tab 01
- `108133736565973` Top Menu Container › Top Menu Tab 02
- `134491076023635` Item Grid Container
- `110504270790823` Item Grid Container › Sub Tab Container › Sub Tab 01
- `101317556846010` Item Grid Container › Sub Tab Container › Sub Tab 02
- `81430650282413` Item Grid Container › Sub Tab Container › Sub Tab 03
- `101917548826449` Item Grid Container › Sub Tab Container › Sub Tab 04
- `86558707764577` Item Grid Container › Items Header
- `108263692862249` Item Grid Container › Item Card 01
- `117711285212679` Item Grid Container › Item Card 02
- `111837058343495` Item Grid Container › Item Card 03
- `124535311721304` Item Grid Container › Item Card 04
- `74000720857918` Item Grid Container › Item Card 05
- `133188359998045` Item Grid Container › Item Card 06
- `124696515327339` Item Grid Container › Item Card 07
- `108972816716784` Item Grid Container › Item Card 08
- `83466385017943` Item Grid Container › Item Card 09
- `76071037245364` Stage Container › Image
- `130923731014927` Wearing Container › Wearing Slot 01
- `119433769737790` Wearing Container › Wearing Slot 02
- `120724388375483` Wearing Container › Wearing Slot 03
- `93487134628245` Item Info Container
- `113128659041052` Item Info Container › Head Header
- `112292749540103` Item Info Container › Preview Card
- `128035418919606` Item Info Container › Show Toggle

**Settings**

- `89099049083500` Settings Container — ×2 uses (Settings, Settings - Reset Confirm)
- `87986228259949` Settings Container › Header Container — ×2 uses (Settings, Settings - Reset Confirm)
- `87934738225568` Settings Container › Header Container › Close Button — ×5 uses (Settings, Settings - Reset Confirm, Daily Rewards, Daily Spins, In-Game HUD - Squad Open)
- `85445603148106` Settings Container › Audio Header — ×2 uses (Settings, Settings - Reset Confirm)
- `104154756775730` Settings Container › Music Setting — ×2 uses (Settings, Settings - Reset Confirm)
- `135123923403961` Settings Container › Music Setting › Music Slider — ×2 uses (Settings, Settings - Reset Confirm)
- `125107580511892` Settings Container › Music Setting › Music Reset Button — ×2 uses (Settings, Settings - Reset Confirm)
- `117465090351192` Settings Container › Sound Effects Setting — ×2 uses (Settings, Settings - Reset Confirm)
- `79154612532477` Settings Container › Sound Effects Setting › Sound Effects Slider — ×2 uses (Settings, Settings - Reset Confirm)
- `118009714755116` Settings Container › Sound Effects Setting › Sound Effects Reset Button — ×2 uses (Settings, Settings - Reset Confirm)
- `112562392406666` Settings Container › Menu Sounds Setting — ×2 uses (Settings, Settings - Reset Confirm)
- `83160627763321` Settings Container › Menu Sounds Setting › Menu Sounds Slider — ×2 uses (Settings, Settings - Reset Confirm)
- `133056598251309` Settings Container › Menu Sounds Setting › Menu Sounds Reset Button — ×2 uses (Settings, Settings - Reset Confirm)
- `114795113817787` Settings Container › Camera Header — ×2 uses (Settings, Settings - Reset Confirm)
- `138525765842214` Settings Container › Reduce Camera Shake Setting — ×2 uses (Settings, Settings - Reset Confirm)
- `82346710001747` Settings Container › Reduce Camera Shake Setting › Reduce Camera Shake Reset Button — ×2 uses (Settings, Settings - Reset Confirm)
- `86504477922950` Settings Container › Drag Fire To Aim Setting — ×2 uses (Settings, Settings - Reset Confirm)
- `89654794002981` Settings Container › Drag Fire To Aim Setting › Drag Fire To Aim Reset Button — ×2 uses (Settings, Settings - Reset Confirm)
- `104283121581154` Settings Container › Profile Header — ×2 uses (Settings, Settings - Reset Confirm)
- `128344107999105` Settings Container › Display Name Setting — ×2 uses (Settings, Settings - Reset Confirm)
- `139649818264337` Settings Container › Display Name Setting › Display Name Input — ×2 uses (Settings, Settings - Reset Confirm)
- `124396401044302` Settings Container › Display Name Setting › Display Name Reset Button — ×2 uses (Settings, Settings - Reset Confirm)
- `91425743204667` Settings Container › Reset All Button — ×2 uses (Settings, Settings - Reset Confirm)

**Settings - Reset Confirm**

- `95928634624098` Confirm Modal Container
- `82449601802613` Confirm Modal Container › Cancel Button
- `84114244116415` Confirm Modal Container › Confirm Reset Button

**Quests - Daily**

- `83344093114314` Title Container — ×2 uses (Quests - Daily, Quests - Weekly)
- `99390408111037` Quest Container
- `91256781390773` Quest Container › Category Tab Container › Category Tab 01
- `139632073147694` Quest Container › Category Tab Container › Category Tab 02
- `83188519409588` Quest Container › Quest Card 01
- `137562486482836` Quest Container › Quest Card 01 › Reward Container
- `111969642107112` Quest Container › Quest Card 01 › Claim Button — ×3 uses (Quests - Daily ×2, Quests - Weekly)
- `75111604174807` Quest Container › Quest Card 02
- `135816275011537` Quest Container › Quest Card 02 › Reward Container — ×2 uses (Quests - Daily ×2)
- `109854365213229` Quest Container › Quest Card 03
- `123458864414198` Quest Container › Quest Card 03 › Claim Button — ×5 uses (Quests - Daily ×2, Quests - Weekly ×3)
- `106966139080159` Quest Container › Quest Card 04
- `107695290692412` Quest Container › Quest Card 04 › Reward Container
- `132691131507089` Quest Container › Quest Card 05
- `115699803177577` Quest Container › Quest Card 05 › Reward Container
- `105128221383475` Quest Container › Quest Card 05 › Claim Button — ×2 uses (Quests - Daily, Quests - Weekly)
- `91157372072686` Quest Container › Claim All Button

**Quests - Weekly**

- `87480345104506` Quest Container
- `122016713198194` Quest Container › Category Tab Container › Category Tab 01
- `92240609674531` Quest Container › Category Tab Container › Category Tab 02
- `113265118194194` Quest Container › Quest Card 01
- `80708699376512` Quest Container › Quest Card 01 › Reward Container
- `111208087525613` Quest Container › Quest Card 02
- `116788292057451` Quest Container › Quest Card 02 › Reward Container
- `112451977484500` Quest Container › Quest Card 03
- `92078868039296` Quest Container › Quest Card 03 › Reward Container — ×2 uses (Quests - Weekly ×2)
- `99518029390157` Quest Container › Quest Card 04
- `118842130068194` Quest Container › Quest Card 05
- `93438823902575` Quest Container › Quest Card 05 › Reward Container
- `78613759875855` Quest Container › Claim All Button

**Daily Rewards**

- `86503260149717` Daily Rewards Container
- `112100775231900` Daily Rewards Container › Header Container
- `140142838441677` Daily Rewards Container › Week Navigation Container › Previous Week Button
- `109559608738506` Daily Rewards Container › Week Navigation Container › Week Tab 01
- `114954008972764` Daily Rewards Container › Week Navigation Container › Week Tab 02
- `103892751930229` Daily Rewards Container › Week Navigation Container › Week Tab 03
- `120948452005613` Daily Rewards Container › Week Navigation Container › Week Tab 04
- `71252287070686` Daily Rewards Container › Week Navigation Container › Next Week Button
- `128308738930274` Daily Rewards Container › Day Card 01
- `126472791793872` Daily Rewards Container › Day Card 01 › Currency Tag UI — ×5 uses (Daily Rewards ×5)
- `115410369770027` Daily Rewards Container › Day Card 01 › Claimed Tag UI
- `89324846464181` Daily Rewards Container › Day Card 02
- `131423325026452` Daily Rewards Container › Day Card 02 › Claim Tag UI
- `138973527655694` Daily Rewards Container › Day Card 03
- `74018695406816` Daily Rewards Container › Day Card 04
- `90003112198137` Daily Rewards Container › Day Card 05
- `113168626488746` Daily Rewards Container › Day Card 06
- `109913372182532` Daily Rewards Container › Day Card 07
- `133196750938875` Daily Rewards Container › Day Card 07 › Permanent Tag UI
- `91335999477117` Daily Rewards Container › Day Card 07 › Rarity Tag UI
- `83619619294874` Daily Rewards Container › Next Reward Timer

**Daily Spins**

- `124085912966106` Daily Spins Container
- `130963585909584` Daily Spins Container › Top Menu Container › Top Menu Tab 01
- `110273546838339` Daily Spins Container › Top Menu Container › Top Menu Tab 02
- `110165926703254` Daily Spins Container › Reel Container › Reward Card 01
- `95853150922122` Daily Spins Container › Reel Container › Reward Card 02
- `119003530866236` Daily Spins Container › Reel Container › Reward Card 03
- `97385221413200` Daily Spins Container › Reel Container › Reward Card 04
- `87631407058169` Daily Spins Container › Reel Container › Reward Card 05
- `115674659070949` Daily Spins Container › Reel Container › Reward Card 06
- `112790914515878` Daily Spins Container › Reel Container › Reward Card 07
- `73494365881083` Daily Spins Container › Spin Button

**Player Head Tag**

- `104010296897182` Player Head Tag
- `107717472954621` Player Head Tag › Class Tag UI
- `87277754446534` Player Head Tag › Rank Container
- `77266565363541` Player Head Tag › Victories Container
- `138728373135121` Player Head Tag › Deaths Container
- `111095235166627` Player Head Tag
- `78236504222233` Player Head Tag › Class Tag UI
- `71651373868348` Player Head Tag › Rank Container
- `116126683088072` Player Head Tag › Victories Container
- `125495116909529` Player Head Tag › Deaths Container
- `97778966097999` Player Head Tag
- `115300907008322` Player Head Tag › Class Tag UI
- `91522727864801` Player Head Tag › Rank Container
- `93931657434466` Player Head Tag › Victories Container
- `90696578889761` Player Head Tag › Deaths Container

**Upgrade Selection**

- `131612903443518` Upgrade Card 01
- `91841909929463` Upgrade Card 01 › Keybind Slot UI — ×3 uses (Upgrade Selection ×3)
- `134534118821825` Upgrade Card 01 › New Tag UI
- `74713151156883` Upgrade Card 01 › Rarity Tag UI
- `133154211546866` Upgrade Card 02
- `136098500115062` Upgrade Card 02 › New Tag UI
- `130765577471127` Upgrade Card 02 › Rarity Tag UI
- `136465613551012` Upgrade Card 03
- `96358922087817` Upgrade Card 03 › New Tag UI
- `113130620411556` Upgrade Card 03 › Rarity Tag UI
- `92766423851791` Reroll Button

**In-Game HUD**

- `102488643301775` Squad Button — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `119386316212396` Wave Info Container › Wave Container — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `105424574669114` Wave Info Container › Boss Container — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `105276233832108` Wave Info Container › Boss Container › Boss Tag UI — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `96359751034255` Next Wave Announcement › Announcement Plate — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `94093865067334` Next Wave Announcement › Countdown UI — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `136264706820933` Skip Wave Container › Skip Wave Button — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `87979913592103` Skip Wave Container › Skip Vote UI — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `122769094588401` Skip Wave Container › Auto Skip Container — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `117907024936005` Settings Button — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `96605410628882` Usable Items Container › Heal All Button — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `81873692731083` Usable Items Container › Nuke All Button — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `139807635165862` Upgrades Container › Upgrade Card 01 — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `106777040389792` Upgrades Container › Upgrade Card 01 › Keybind Slot UI — ×10 uses (In-Game HUD ×5, In-Game HUD - Squad Open ×5)
- `111485632705697` Upgrades Container › Upgrade Card 02 — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `133849700511605` Money Products Container › Money Product Button 01 — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `90510248158128` Money Products Container › Money Product Button 01 › Price Tag UI — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `96646665217373` Money Products Container › Money Product Button 02 — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `90862369608039` Money Products Container › Money Product Button 02 › Price Tag UI — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `138507042702294` Ult Charge Container — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `80967780391968` Ult Charge Container › Ult Charge UI — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `127534093757665` Abilities Container › Ability Card 01 — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `81637994815500` Abilities Container › Ability Card 02 — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `97897316009467` Abilities Container › Ability Card 03 — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `125256443016297` Player Container › Image
- `74780406950195` Round Money Container — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `135702173692848` Round Money Container › Money Plate — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `75462913076534` Hotbar Container › Hotbar Slot 01 — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `94781803337083` Hotbar Container › Hotbar Slot 01 › Keybind Slot UI — ×10 uses (In-Game HUD ×5, In-Game HUD - Squad Open ×5)
- `116185397246459` Hotbar Container › Hotbar Slot 02 — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `114051206819480` Hotbar Container › Hotbar Slot 03 — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `130193220903955` Hotbar Container › Hotbar Slot 04 — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)
- `108072718401150` Hotbar Container › Hotbar Slot 05 — ×2 uses (In-Game HUD, In-Game HUD - Squad Open)

**In-Game HUD - Squad Open**

- `136313906547974` Player Container › Image
- `124947646330516` Squad Container
- `94016127323039` Squad Container › Player Row 01
- `122834962580930` Squad Container › Player Row 01 › Class Tag UI
- `138002208158330` Squad Container › Player Row 02
- `73164670004294` Squad Container › Player Row 02 › Class Tag UI
- `109062171713033` Squad Container › Player Row 03
- `72355242284072` Squad Container › Player Row 03 › Class Tag UI
- `94838661970299` Squad Container › Player Row 04
- `96454778900249` Squad Container › Player Row 04 › Class Tag UI

**Monster Mutation**

- `71210644569949` Title Container
- `99341368297270` Mutation Container
- `120434916248112` Mutation Container › Category Tab Container › Category Tab 01
- `122868778446129` Mutation Container › Category Tab Container › Category Tab 02
- `108744582150253` Mutation Container › Ingredient Slot 01
- `101733397651777` Mutation Container › Ingredient Slot 01 › Energy Cost Tag UI
- `140277414445597` Mutation Container › Ingredient Slot 02
- `72382745067772` Mutation Container › Ingredient Slot 02 › Energy Cost Tag UI
- `93791040338551` Mutation Container › Result Card
- `111950161471563` Mutation Container › Result Card › New Tag UI
- `88798692469871` Mutation Container › Result Card › Rarity Tag UI
- `138662403188583` Mutation Container › Select Energy Header
- `124567000873483` Mutation Container › Energy Container › Energy Card 01
- `75427362859330` Mutation Container › Energy Container › Energy Card 02
- `109141668561799` Mutation Container › Energy Container › Energy Card 03
- `77519406423475` Mutation Container › Energy Container › Energy Card 04
- `109971706741373` Mutation Container › Energy Container › Energy Card 05
- `84127142806707` Mutation Container › Brew Cost Container
- `140593374519435` Mutation Container › Brew Button
- `133675710064003` Mutation Container › Potion Count Badge UI

**Lobby Entering**

- `93979643706444` Level Up Container
- `82274130567465` Level Up Container › XP Panel
- `136038874136528` XP Breakdown Container › Waves XP Tag UI
- `96864286967835` XP Breakdown Container › Kills XP Tag UI
- `105584121209173` XP Breakdown Container › New best XP Tag UI
- `120952172712379` XP Breakdown Container › Bosses XP Tag UI
- `104811889463477` XP Breakdown Container › Bounties XP Tag UI
- `129479538507070` Player Container 02
- `101645915113070` Player Container 02 › Player Head Tag
- `121104360495010` Player Container 01
- `116370959810856` Player Container 01 › Player Head Tag
- `98908921723341` Player Container 01 › Player Head Tag › MVP Tag UI
- `139172497883106` Match Stats Container › Match Stats Header
- `120414123386933` Match Stats Container › Gems Earned Card
- `136294362056284` Match Stats Container › Squad Kills Card
- `122414854136283` Match Stats Container › Wave Reached Card
- `120344275906024` Match Stats Container › Wave Reached Card › New Best Tag UI
- `120240315024527` Match Stats Container › Time Survived Card
- `107196240633733` Match Stats Container › Time Survived Card › New Best Tag UI
- `70748244379011` Lobby Button

**Round Results**

- `86512949763738` Results Container
- `104386502506343` Results Container › Header Container
- `105523190664687` Results Container › Header Container › Return Timer UI
- `73562681815674` Results Container › Wave Card
- `133745464281288` Results Container › Wave Card › New Best Tag UI
- `132710483231091` Results Container › Wave Card › Squad Kills Container
- `94909205766457` Results Container › Wave Card › Time Survived Container
- `110701547367116` Results Container › Gems Card
- `133028327833325` Results Container › Double Gems Card
- `107140397242037` Results Container › Double Gems Card › Bonus Tag UI
- `120333389261265` Results Container › Double Gems Card › Robux Double Button
- `100421269701855` Results Container › Double Gems Card › Watch Ad Button
- `134036027972997` Results Container › Action Container › Return To Lobby Button
- `114440233802906` Results Container › Action Container › Play Again Button
- `109064559204027` Results Container › Action Container › Vote Count Container
- `129357551429107` Results Container › Action Container › Revive Button
- `72554556037753` Upgrades Available Tag UI

## 6. Scripts

None. The file has no `Script`, `LocalScript` or `ModuleScript` anywhere (a full class census of every service found none), so there is no logic, animation or tween code. Every state is a separate static ScreenGui (§1).

## 7. Renders

Rendered with `rur-native 0.8.0 render --model … --viewport 1920x1080 --scale 1 --margin 0`, with `RUR_ROBLOX_CONTENT` set to the Vinegar Studio `content` folder (so Montserrat renders) and `ROBLOX_ASSET_DELIVERY_API_KEY` set to `.env`'s `ROBLOX_CONFIGS_API_KEY_PROD`. The art belongs to user 2354147156's account and is private: asset delivery answers 401 without that key. Every image renders except `87986228259949` (Settings Container › Header Container, in Settings and Settings - Reset Confirm), which the key is refused (403). The background `#28283C` was added behind each screen; it is not the design. The renders are in `Assets/ui/UIMatt/renders/` (gitignored, like all of `Assets/`):

- `Assets/ui/UIMatt/renders/01_Lobby_HUD.png`
- `Assets/ui/UIMatt/renders/02_Weapons_Shop.png`
- `Assets/ui/UIMatt/renders/03_Robux_Shop.png`
- `Assets/ui/UIMatt/renders/04_Index.png`
- `Assets/ui/UIMatt/renders/05_Classes.png`
- `Assets/ui/UIMatt/renders/06_Equipment.png`
- `Assets/ui/UIMatt/renders/07_Settings.png`
- `Assets/ui/UIMatt/renders/08_Settings_Reset_Confirm.png`
- `Assets/ui/UIMatt/renders/09_Quests_Daily.png`
- `Assets/ui/UIMatt/renders/10_Quests_Weekly.png`
- `Assets/ui/UIMatt/renders/11_Daily_Rewards.png`
- `Assets/ui/UIMatt/renders/12_Daily_Spins.png`
- `Assets/ui/UIMatt/renders/13_Player_Head_Tag.png`
- `Assets/ui/UIMatt/renders/14_Upgrade_Selection.png`
- `Assets/ui/UIMatt/renders/15_In_Game_HUD.png`
- `Assets/ui/UIMatt/renders/16_In_Game_HUD_Squad_Open.png`
- `Assets/ui/UIMatt/renders/17_Monster_Mutation.png`
- `Assets/ui/UIMatt/renders/18_Lobby_Entering.png`
- `Assets/ui/UIMatt/renders/19_Round_Results.png`

Each render folder `Assets/ui/UIMatt/renders/<NN_Name>/` also holds `scene.json`, the absolute rect of every node at 1080p.
