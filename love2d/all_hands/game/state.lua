-- All mutable game state lives here so no two gameplay modules have to require
-- each other (which would make a require cycle). Modules read and write State;
-- main.lua drives the order they run in.

local State = {}

State.TILE   = 32   -- interior tile size, px
State.SLOT_W = 8    -- tiles per hull slot (one room bay wide)

-- interior floor-plan rows (tile units)
State.ROW_TOP_0  = -6   -- top room first interior row
State.ROW_TOP_1  = -2   -- top room last interior row
State.ROW_COR_0  =  0   -- corridor rows
State.ROW_COR_1  =  2
State.ROW_BOT_0  =  4   -- bottom room rows
State.ROW_BOT_1  =  8

State.FAB_SLOT   =  2   -- midships workshop section: corridor only, holds the fabricator

State.debug    = false
State.paused   = false
State.godmode  = false   -- F4: hull/shields take no damage, for solo testing

State.phase       = "lull"   -- "lull" | "combat" | "dead"
State.phaseTimer  = 30
State.wave        = 0
State.scrap       = 70
State.kills       = 0

State.banner      = nil      -- big centre-screen text
State.bannerTimer = 0
State.log         = {}       -- recent events, newest last

State.ship = {
    modules   = {},      -- ordered list of module records
    rooms     = {},      -- one per module, plus the corridor
    stations   = {},     -- every mountable console
    walls     = {},      -- engine sprites used as collision bodies
    grid      = {},      -- grid[y][x] = 1 floor, 2 wall
    mat       = {},      -- mat[y][x] = texture name for floor tiles
    bounds    = { x0 = 0, y0 = 0, x1 = 0, y1 = 0 },
    maxSlot   = 2,

    power        = { engines = 2, shields = 0, weapons = 2 },
    batteryTimer = 0,
    batteryCool  = 0,

    hull        = 120,
    maxHull     = 120,
    shield      = 0,
    maxShield   = 0,
    shieldAngle = 0,        -- radians, relative to hull forward
    shieldHitTimer = 0,
    braceTimer  = 0,

    designated  = nil,      -- enemy the bridge has marked
}

State.space = {
    x = 0, y = 0,
    angle = 0,
    vx = 0, vy = 0,
    throttle = 0,
    turnInput = 0,
    enemies = {},
    bolts   = {},
    rocks   = {},
    fx      = {},
}

State.players = {}

function State.say(text, colour)
    table.insert(State.log, { text = text, t = 5.0, colour = colour })
    if #State.log > 6 then table.remove(State.log, 1) end
    print("[LOG] " .. text)
end

function State.showBanner(text, seconds)
    State.banner = text
    State.bannerTimer = seconds or 2.5
end

return State
