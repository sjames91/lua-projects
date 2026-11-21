# ALL HANDS

A four-player split-screen prototype. One ship, four crew, and nobody can run
the ship from where they are standing.

Run it with `love .` from this folder (or drop the folder on `love.exe`).
Press **F1** for the in-game briefing.

## The idea

Every system on the ship is bolted to a **bay**, and a bay's console only
listens to a crew member physically standing in it:

| Bay | What it does | What it can't see |
| --- | --- | --- |
| **BRIDGE** | the only view of the outside world | — |
| **HELM** | turn and throttle | flies completely blind |
| **WEAPONS BAY** | traverse and fire one turret | no target picture, only a bearing dial |
| **ENGINEERING** | splits reactor output between engines / shields / weapons | nothing outside the hull |
| **SHIELD BAY** | which side the shield covers | cannot see where fire is coming from |
| **ENGINE BAY** | tended = full thrust, untended = 40% | — |
| **REACTOR BAY** | tended = +2 power, untended it cooks itself | — |
| **SENSOR BAY** | contact bearings and ranges as raw numbers | no picture, just the table |
| **FABRICATOR** | in the spine corridor — buy refits | — |

So the bridge has to read bearings out loud, the shield officer has to be told
which side to face, and engineering has to be told whether this is a chase or a
brawl. None of that is a UI convenience you can route around — the information
genuinely only exists on one screen.

### The growth trap

The ship starts with exactly four bays for exactly four players: bridge, helm,
engineering, weapons. Everybody has a job and nobody is spare.

Then you spend scrap at the fabricator. Most refits **bolt a new bay onto the
hull** — a second turret, an aux engine, a shield generator, a reactor, a sensor
array. The ship gets stronger and the hull visibly grows aft, but now there are
six bays and still four of you, so something is always unmanned. An untended
engine runs at 40%. An untended reactor overheats and burns its own room down.
A second turret that nobody is standing at never fires.

`HULL PLATING` is the one refit that costs you nothing but scrap — it is there
so there's always a safe choice to argue about.

Damage lands on a random bay. A bay below 50% degrades; at 0% it is breached,
its console goes dead and whoever was mounted gets thrown off. Any crew member
can stand in a damaged bay and hold BACK to weld it back together — which is a
fifth job that nobody has time for.

## Controls

Six controls each. What they do depends on whether you are walking or mounted.

|  | walking | mounted |
| --- | --- | --- |
| **DPAD** | move around the ship | operate the station |
| **USE** | mount the console you're standing at | the station's action (fire / buy / brace / overdrive) |
| **BACK** | *hold* to repair the bay you're in | step away from the console |

```
P1   W A S D       Q use    E back
P2   T F G H       R use    Y back
P3   I J K L       U use    O back
P4   ARROWS     RSHIFT use  RCTRL back   (numpad 8456 / kp0 / kp7 also work)
```

Gamepads are picked up automatically — player N uses joystick N. Left stick or
d-pad to walk, **A** = use, **B** = back.

Global keys are function keys only, because every letter on the keyboard is
already somebody's movement or use button:

```
F1 help/pause    F2 pause    F3 debug    F4 godmode    F5 restart    F10 export textures
```

**F4 godmode** is for solo testing: it stops all hull and bay damage (shield hits, hull
breaches, engine/reactor overheat) so you can walk the whole ship and try every station
without a four-person crew to keep you alive. A pulsing badge stays on screen the whole
time it's on so you don't forget it's there.

## The engine

`Engine/` is a **byte-for-byte copy** of the Chispita engine from
`fish_and_the_five_fountains`. It is never modified — verify with:

```
diff -r ../fish_and_the_five_fountains/Engine Engine
```

The game uses it for what it is good at: `Chispita.addRect` bodies for the crew,
the walls and the consoles; `Chispita.update` for per-frame integration and
rect-rect collision resolution; and the global `Camera` for the interior view.

Two places the game works *around* the engine rather than changing it:

- **Split screen.** The engine has one global `Camera`. Each viewport sets
  `Camera.x/y` itself and calls `Chispita.draw()` inside its own scissor and
  transform, so four cameras share one camera object.
- **Room occupancy** is a point test in `Ship.updateOccupancy`, not an engine
  trigger body. The engine's rect resolver pushes a sprite out of any overlap it
  finds without checking whether the *other* body is solid, so a non-solid
  trigger rect laid over a room would shove crew around inside their own bay.

The interior and the exterior are deliberately two separate simulations. The
floor plan never rotates; the hull outside does. That split is what makes "only
the bridge can see" possible at all.

## Assets

Nothing loads from disk. Everything in `game/assets.lua` is generated at startup,
either from blocks of ASCII pixel rows you can edit in place:

```lua
local CREW_DOWN_A = {
    "...oooooo...",
    "..ohhhhhho..",
    ".ohvvvvvvho.",
    ...
}
```

...or from a seeded float-only noise function (LuaJIT has no bitwise operators),
which is where the deck plating, hull bevels, hazard stripes, asteroids and bolt
glows come from. Crew sprites are one set of rows recoloured four ways.

Press **F10** in game to dump all 41 generated textures to PNG in the LÖVE save
directory if you'd rather hand-paint over them.

## Files

```
main.lua              frame order and global keys
conf.lua              window setup
Engine/               untouched copy of Chispita
game/state.lua        all mutable state, so no gameplay module requires another
game/palette.lua      one colour language for the whole ship
game/assets.lua       procedural pixel art
game/ship.lua         floor plan, bays, upgrades, damage, power
game/space.lua        flight, enemies, projectiles, waves
game/players.lua      crew bodies, mounting, repair
game/stations.lua     what each console does and what it shows
game/render.lua       four viewports, interior view, bridge tactical display
game/ui.lua           console widget kit
autotest.lua          dev harness (see below)
```

## Dev harness

`love . autotest` drives the whole game with scripted input and prints ~50
pass/fail checks: that bays gate their consoles, that a rebuild doesn't eject
the crew, that tending an engine bay actually raises thrust, that shields only
absorb on the facing they're set to, that breach and repair work, and that
restart leaves nothing behind. It also drops screenshots and a texture export in
the LÖVE save directory. Handy if you change the engine and want to know what
broke.
