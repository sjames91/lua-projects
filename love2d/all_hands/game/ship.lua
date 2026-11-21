-- The ship: its floor plan, its bays, and the upgrades that grow it.
--
-- Interior layout is a tile grid built from a list of modules. Every module is
-- a room bolted to a slot on the spine corridor, and every room owns exactly
-- one console. Buying an upgrade appends a module, which carves a new room into
-- the grid and plants a new console in it -- so the ship getting stronger
-- always means there is one more place a crew member has to physically stand.
--
-- Slot 0 is the nose. Slots count up toward the stern, so upgrades extend the
-- ship backwards and the bridge stays at the front.

local State = require("game/state")
local Palette = require("game/palette")
local Sprite = require("Engine/Chispita_sprite")

local Ship = {}

local T = State.TILE
local SW = State.SLOT_W

--------------------------------------------------------------------------------
-- module catalogue
--------------------------------------------------------------------------------

Ship.KINDS = {
    bridge = {
        name = "BRIDGE", station = "bridge", deck = "deck_cool", maxhp = 60,
        blurb = "The only place the outside world is visible.",
    },
    helm = {
        name = "HELM", station = "helm", deck = "deck_green", maxhp = 60,
        blurb = "Steering and throttle. Flies blind.",
    },
    engineering = {
        name = "ENGINEERING", station = "engineering", deck = "deck_warm", maxhp = 70,
        blurb = "Splits reactor output between engines, shields and guns.",
    },
    weapons = {
        name = "WEAPONS BAY", station = "weapons", deck = "deck", maxhp = 55,
        blurb = "One turret. Must be manned to fire.",
    },
    shields = {
        name = "SHIELD BAY", station = "shields", deck = "deck_cool", maxhp = 55,
        blurb = "Holds the shield facing. Cannot see incoming fire.",
    },
    engine = {
        name = "ENGINE BAY", station = "engine", deck = "deck_warm", maxhp = 65,
        blurb = "Tended engines run at full output. Untended ones idle.",
    },
    reactor = {
        name = "REACTOR BAY", station = "reactor", deck = "deck_warm", maxhp = 65,
        blurb = "Extra power while someone keeps the core cool.",
    },
    sensors = {
        name = "SENSOR BAY", station = "sensors", deck = "deck_cool", maxhp = 50,
        blurb = "Contact ranges and bearings as raw numbers.",
    },
}

-- What the fabricator sells. `room` nil means it does not cost you a crew slot.
Ship.UPGRADES = {
    {
        id = "armour", label = "HULL PLATING", cost = 35, room = nil,
        desc = "+30 max hull. No new bay to man.",
    },
    {
        id = "engine", label = "AUX ENGINE", cost = 45, room = "engine",
        desc = "More thrust. Adds an ENGINE BAY someone must tend.",
    },
    {
        id = "weapons", label = "TURRET BATTERY", cost = 55, room = "weapons",
        desc = "A second gun. Adds a WEAPONS BAY to man.",
    },
    {
        id = "shields", label = "SHIELD GENERATOR", cost = 65, room = "shields",
        desc = "+45 shield. Adds a SHIELD BAY to man.",
    },
    {
        id = "sensors", label = "SENSOR ARRAY", cost = 50, room = "sensors",
        desc = "Longer radar. Adds a SENSOR BAY to man.",
    },
    {
        id = "reactor", label = "REACTOR CORE", cost = 75, room = "reactor",
        desc = "+3 power. Adds a REACTOR BAY to man.",
    },
}

--------------------------------------------------------------------------------
-- geometry helpers
--------------------------------------------------------------------------------

local function roomRect(slot, side)
    local x0 = slot * SW + 1
    local x1 = slot * SW + SW - 2
    local y0, y1
    if side == "top" then
        y0, y1 = State.ROW_TOP_0, State.ROW_TOP_1
    else
        y0, y1 = State.ROW_BOT_0, State.ROW_BOT_1
    end
    return x0, y0, x1, y1
end

local function doorTiles(slot, side)
    local dx = slot * SW + 3
    local dy = (side == "top") and (State.ROW_TOP_1 + 1) or (State.ROW_BOT_0 - 1)
    return dx, dy
end

function Ship.tileToPx(tx, ty)
    return tx * T, ty * T
end

--------------------------------------------------------------------------------
-- grid construction
--------------------------------------------------------------------------------

local function gset(grid, x, y, v)
    grid[y] = grid[y] or {}
    grid[y][x] = v
end

local function gget(grid, x, y)
    local row = grid[y]
    return row and row[x] or 0
end

local function carve(grid, mat, x0, y0, x1, y1, material)
    for y = y0, y1 do
        for x = x0, x1 do
            gset(grid, x, y, 1)
            gset(mat, x, y, material)
        end
    end
end

-- Merge a set of wall tiles into as few rectangles as possible: horizontal runs
-- first, then stack identical runs vertically. Fewer bodies keeps the engine's
-- all-pairs collision pass cheap, and long flat rects make its minimum-overlap
-- push resolve in the right direction.
local function mergeWalls(tiles)
    local byRow = {}
    for key in pairs(tiles) do
        local sx, sy = key:match("^(-?%d+),(-?%d+)$")
        local x, y = tonumber(sx), tonumber(sy)
        byRow[y] = byRow[y] or {}
        table.insert(byRow[y], x)
    end

    local runs = {}
    for y, xs in pairs(byRow) do
        table.sort(xs)
        local i = 1
        while i <= #xs do
            local x0 = xs[i]
            local x1 = x0
            while xs[i + 1] == x1 + 1 do
                i = i + 1
                x1 = xs[i]
            end
            table.insert(runs, { x0 = x0, x1 = x1, y0 = y, y1 = y })
            i = i + 1
        end
    end

    -- stack runs that share an x-span and sit on consecutive rows
    local groups = {}
    for _, r in ipairs(runs) do
        local k = r.x0 .. ":" .. r.x1
        groups[k] = groups[k] or {}
        table.insert(groups[k], r)
    end

    local out = {}
    for _, g in pairs(groups) do
        table.sort(g, function(a, b) return a.y0 < b.y0 end)
        local cur = nil
        for _, r in ipairs(g) do
            if cur and r.y0 == cur.y1 + 1 then
                cur.y1 = r.y1
            else
                if cur then table.insert(out, cur) end
                cur = { x0 = r.x0, x1 = r.x1, y0 = r.y0, y1 = r.y1 }
            end
        end
        if cur then table.insert(out, cur) end
    end
    return out
end

--------------------------------------------------------------------------------
-- engine sprite bookkeeping
--------------------------------------------------------------------------------

-- The engine has no delete call, so we reach into its sprite list and pull out
-- everything we tagged on the last rebuild. Player sprites are left alone.
local function clearTaggedSprites()
    local list = Sprite.sprites
    for i = #list, 1, -1 do
        if list[i].ah_tag then
            table.remove(list, i)
        end
    end
end

local function addWallBody(x0, y0, x1, y1)
    local b = Sprite.addRect(x0 * T, y0 * T, (x1 - x0 + 1) * T, (y1 - y0 + 1) * T)
    b.ah_tag  = "wall"
    b.fall    = false
    b.fixed   = true
    b.solid   = true
    b.visable = false      -- engine's spelling; we draw walls ourselves
    b.bounciness = 0
    return b
end

local function addSolidBox(px, py, w, h, tag)
    local b = Sprite.addRect(px, py, w, h)
    b.ah_tag  = tag
    b.fall    = false
    b.fixed   = true
    b.solid   = true
    b.visable = false
    b.bounciness = 0
    return b
end

-- Room occupancy is a plain point test rather than an engine trigger body.
-- The engine's rect resolver pushes a sprite out of any overlap it finds
-- without checking whether the *other* body is solid, so a non-solid trigger
-- rect laid over a room would shove crew members around inside their own bay.
-- A point test costs nothing and leaves the engine untouched.
function Ship.updateOccupancy()
    for _, r in ipairs(State.ship.rooms) do
        r.occupants = {}
    end
    for _, p in ipairs(State.players) do
        local r = Ship.roomAtPoint(p.x, p.y)
        -- doorway tiles belong to no room, so keep the last one you were in
        if r then p.room = r end
        if p.room then table.insert(p.room.occupants, p) end
    end
end

--------------------------------------------------------------------------------
-- stations
--------------------------------------------------------------------------------

local function makeStation(kind, room, px, py, w, facing)
    local st = {
        kind    = kind,
        room    = room,
        px      = px, py = py,
        w       = w, h = 20,
        facing  = facing,
        occupant = nil,
        accent  = Palette.station[kind] or Palette.ink,
        label   = Ship.KINDS[kind] and Ship.KINDS[kind].name or kind:upper(),
        -- per-station scratch state
        sel     = 1,
        blink   = 0,
    }
    st.cx = px + w / 2
    st.cy = py + st.h / 2
    -- the spot a crew member must be standing to reach it
    st.ix = st.cx
    st.iy = (facing == "down") and (py + st.h + 16) or (py - 16)
    if room then room.station = st end
    table.insert(State.ship.stations, st)
    return st
end

--------------------------------------------------------------------------------
-- build / rebuild
--------------------------------------------------------------------------------

function Ship.rebuild()
    local s = State.ship
    clearTaggedSprites()

    -- A rebuild throws away every station object, so remember who was mounted
    -- where (and their console's scratch state) and re-link it afterwards.
    -- Otherwise buying an upgrade would eject the whole crew from their posts.
    local carry = {}
    for _, st in ipairs(s.stations or {}) do
        local key = st.module and st.module.id or st.kind
        carry[key] = { occupant = st.occupant, sel = st.sel, zoom = st.zoom }
    end
    for _, p in ipairs(State.players) do
        p.station = nil
    end

    s.grid, s.mat = {}, {}
    s.rooms = {}
    s.stations = {}
    s.walls = {}

    local maxSlot = State.FAB_SLOT
    for _, m in ipairs(s.modules) do
        maxSlot = math.max(maxSlot, m.slot)
    end
    s.maxSlot = maxSlot

    -- spine corridor runs the full length of the ship
    local corX0, corX1 = 0, maxSlot * SW + SW - 1
    for x = corX0, corX1 do
        for y = State.ROW_COR_0, State.ROW_COR_1 do
            gset(s.grid, x, y, 1)
            gset(s.mat, x, y, "hazard")
        end
    end

    local corridor = {
        id = "corridor", kind = "corridor", name = "SPINE CORRIDOR",
        x0 = corX0, y0 = State.ROW_COR_0, x1 = corX1, y1 = State.ROW_COR_1,
        px = corX0 * T, py = State.ROW_COR_0 * T,
        pw = (corX1 - corX0 + 1) * T, ph = (State.ROW_COR_1 - State.ROW_COR_0 + 1) * T,
        hp = 1, maxhp = 1, occupants = {},
    }
    table.insert(s.rooms, corridor)
    s.corridor = corridor

    -- rooms
    for _, m in ipairs(s.modules) do
        local def = Ship.KINDS[m.kind]
        local x0, y0, x1, y1 = roomRect(m.slot, m.side)
        carve(s.grid, s.mat, x0, y0, x1, y1, def.deck)

        local dx, dy = doorTiles(m.slot, m.side)
        gset(s.grid, dx, dy, 1);     gset(s.mat, dx, dy, "hazard")
        gset(s.grid, dx + 1, dy, 1); gset(s.mat, dx + 1, dy, "hazard")

        local room = {
            id = m.id, kind = m.kind, name = def.name, module = m,
            x0 = x0, y0 = y0, x1 = x1, y1 = y1,
            px = x0 * T, py = y0 * T,
            pw = (x1 - x0 + 1) * T, ph = (y1 - y0 + 1) * T,
            occupants = {},
        }
        room.hp, room.maxhp = m.hp, m.maxhp
        m.room = room
        table.insert(s.rooms, room)

        -- console against the outer wall, so the bay is a place you commit to
        local cw = 2 * T
        local cpx = (x0 + 2) * T
        local cpy, facing
        if m.side == "top" then
            cpy, facing = y0 * T + 2, "down"
        else
            cpy, facing = (y1 + 1) * T - 22, "up"
        end
        local st = makeStation(def.station, room, cpx, cpy, cw, facing)
        st.module = m
        m.station = st
        addSolidBox(cpx, cpy, cw, st.h, "console")
    end

    -- the fabricator: a corridor terminal, always reachable, costs no bay
    do
        local cpx = (State.FAB_SLOT * SW + 3) * T
        local cpy = State.ROW_COR_0 * T + 2
        local st = makeStation("fabricator", nil, cpx, cpy, 2 * T, "down")
        st.label = "FABRICATOR"
        st.room = corridor
        addSolidBox(cpx, cpy, st.w, st.h, "console")
        s.fabricator = st
    end

    -- auto-wall: any empty tile touching a floor tile becomes hull
    local wallTiles = {}
    for y, row in pairs(s.grid) do
        for x, v in pairs(row) do
            if v == 1 then
                for oy = -1, 1 do
                    for ox = -1, 1 do
                        if gget(s.grid, x + ox, y + oy) == 0 then
                            wallTiles[(x + ox) .. "," .. (y + oy)] = true
                        end
                    end
                end
            end
        end
    end
    for key in pairs(wallTiles) do
        local sx, sy = key:match("^(-?%d+),(-?%d+)$")
        gset(s.grid, tonumber(sx), tonumber(sy), 2)
    end

    for _, r in ipairs(mergeWalls(wallTiles)) do
        table.insert(s.walls, r)
        addWallBody(r.x0, r.y0, r.x1, r.y1)
    end

    -- put the crew back on the consoles they were already standing at
    for _, st in ipairs(s.stations) do
        local key = st.module and st.module.id or st.kind
        local c = carry[key]
        if c then
            st.sel  = c.sel or st.sel
            st.zoom = c.zoom
            if c.occupant and not Ship.isOffline(st.module) then
                st.occupant = c.occupant
                c.occupant.station = st
            end
        end
    end

    -- bounds for rendering and the minimap
    local bx0, by0, bx1, by1 = math.huge, math.huge, -math.huge, -math.huge
    for y, row in pairs(s.grid) do
        for x in pairs(row) do
            bx0 = math.min(bx0, x); bx1 = math.max(bx1, x)
            by0 = math.min(by0, y); by1 = math.max(by1, y)
        end
    end
    s.bounds = { x0 = bx0, y0 = by0, x1 = bx1, y1 = by1 }

    Ship.recomputeStats()
end

local nextId = 0
local function newModule(kind, slot, side)
    nextId = nextId + 1
    local def = Ship.KINDS[kind]
    return {
        id = "m" .. nextId,
        kind = kind, slot = slot, side = side,
        hp = def.maxhp, maxhp = def.maxhp,
        -- turret / engine / reactor scratch
        turret = 0, charge = 1, mode = "bolt",
        heat = 0, overdrive = false,
    }
end

-- Upgrade bays fill in aft of the workshop, alternating top and bottom so the
-- hull stays roughly symmetrical as it grows.
local function nextFreeSlot()
    local used = {}
    for _, m in ipairs(State.ship.modules) do
        used[m.slot .. m.side] = true
    end
    local slot = State.FAB_SLOT + 1
    while slot < State.FAB_SLOT + 12 do
        if not used[slot .. "top"] then return slot, "top" end
        if not used[slot .. "bottom"] then return slot, "bottom" end
        slot = slot + 1
    end
    return nil
end

function Ship.reset()
    local s = State.ship
    s.modules = {}
    s.stations = {}      -- drop last run's stations so rebuild carries nothing over
    nextId = 0

    -- the starting ship: exactly four bays for exactly four crew
    table.insert(s.modules, newModule("bridge", 0, "top"))
    table.insert(s.modules, newModule("helm", 0, "bottom"))
    table.insert(s.modules, newModule("engineering", 1, "top"))
    table.insert(s.modules, newModule("weapons", 1, "bottom"))

    s.armourStacks = 0
    s.maxHull = 120
    s.hull = s.maxHull
    s.power = { engines = 2, shields = 0, weapons = 2 }
    s.shield = 0
    s.shieldAngle = 0
    s.designated = nil
    s.batteryTimer = 0
    s.batteryCool = 0

    Ship.rebuild()
end

function Ship.canBuy(up)
    if State.scrap < up.cost then return false, "NEED " .. (up.cost - State.scrap) .. " MORE SCRAP" end
    if up.room then
        local slot = nextFreeSlot()
        if not slot then return false, "NO HULL SPACE LEFT" end
    end
    return true
end

function Ship.buy(up)
    local ok, why = Ship.canBuy(up)
    if not ok then return false, why end

    State.scrap = State.scrap - up.cost

    if up.room then
        local slot, side = nextFreeSlot()
        local m = newModule(up.room, slot, side)
        table.insert(State.ship.modules, m)
        Ship.rebuild()
        State.say(("%s INSTALLED - new %s aft, slot %d"):format(up.label, Ship.KINDS[up.room].name, slot))
        State.showBanner(Ship.KINDS[up.room].name .. " ONLINE\nsomeone has to go stand in it", 3.5)
    else
        State.ship.armourStacks = State.ship.armourStacks + 1
        State.ship.maxHull = State.ship.maxHull + 30
        State.ship.hull = math.min(State.ship.maxHull, State.ship.hull + 30)
        Ship.recomputeStats()
        State.say("HULL PLATING WELDED ON - max hull " .. State.ship.maxHull)
    end
    return true
end

--------------------------------------------------------------------------------
-- derived stats
--------------------------------------------------------------------------------

function Ship.modulesOfKind(kind)
    local out = {}
    for _, m in ipairs(State.ship.modules) do
        if m.kind == kind then table.insert(out, m) end
    end
    return out
end

function Ship.countManned(kind)
    local n = 0
    for _, st in ipairs(State.ship.stations) do
        if st.kind == kind and st.occupant then n = n + 1 end
    end
    return n
end

function Ship.isManned(module)
    return module.station ~= nil and module.station.occupant ~= nil
end

-- 0..1 health factor; a breached room's station is offline entirely
function Ship.healthFactor(module)
    if not module then return 1 end
    return module.hp / module.maxhp
end

function Ship.isOffline(module)
    return module and module.hp <= 0
end

function Ship.reactorOutput()
    local s = State.ship
    local out = 5
    for _, m in ipairs(Ship.modulesOfKind("reactor")) do
        if not Ship.isOffline(m) then
            out = out + 3
            if Ship.isManned(m) then out = out + 2 end
        end
    end
    if s.batteryTimer > 0 then out = out + 3 end
    return out
end

function Ship.powerUsed()
    local p = State.ship.power
    return p.engines + p.shields + p.weapons
end

function Ship.powerFree()
    return Ship.reactorOutput() - Ship.powerUsed()
end

-- Total engine output. The hull has one automated main engine that always runs
-- at a fraction of full; every ENGINE BAY added runs much better when tended.
function Ship.engineOutput()
    local out = 0.65   -- integral main drive
    for _, m in ipairs(Ship.modulesOfKind("engine")) do
        if not Ship.isOffline(m) then
            local o = Ship.isManned(m) and 1.0 or 0.4
            o = o * (0.4 + 0.6 * Ship.healthFactor(m))
            if m.overdrive then o = o * 1.7 end
            out = out + o
        end
    end
    return out
end

function Ship.massFactor()
    return 1 + 0.10 * #State.ship.modules + 0.06 * (State.ship.armourStacks or 0)
end

function Ship.recomputeStats()
    local s = State.ship
    local maxShield = 0
    for _, m in ipairs(Ship.modulesOfKind("shields")) do
        if not Ship.isOffline(m) then
            maxShield = maxShield + 45 * (0.4 + 0.6 * Ship.healthFactor(m))
        end
    end
    s.maxShield = maxShield
    s.shield = math.min(s.shield, maxShield)

    -- shield arc widens with a second generator
    local gens = #Ship.modulesOfKind("shields")
    s.shieldArc = math.rad(55 + 22 * math.max(0, gens - 1))

    local sensors = Ship.modulesOfKind("sensors")
    local range = 900
    for _, m in ipairs(sensors) do
        if not Ship.isOffline(m) then
            range = range + 700
            if Ship.isManned(m) then range = range + 500 end
        end
    end
    s.radarRange = range
    s.hull = math.min(s.hull, s.maxHull)
end

--------------------------------------------------------------------------------
-- queries
--------------------------------------------------------------------------------

function Ship.roomAtPoint(px, py)
    for _, r in ipairs(State.ship.rooms) do
        if px >= r.px and px < r.px + r.pw and py >= r.py and py < r.py + r.ph then
            return r
        end
    end
    return nil
end

-- Station a player may mount: close enough to the console AND standing inside
-- the bay that console belongs to. The room test is the whole point of the game.
function Ship.stationFor(player)
    local best, bestD = nil, 60
    for _, st in ipairs(State.ship.stations) do
        if st.room == player.room then
            local dx = player.x - st.cx
            local dy = player.y - st.cy
            local d = math.sqrt(dx * dx + dy * dy)
            if d < bestD then best, bestD = st, d end
        end
    end
    return best
end

function Ship.spawnPoints(n)
    local pts = {}
    local cy = (State.ROW_COR_0 + 1.5) * T
    local baseX = (State.FAB_SLOT * SW + 1) * T
    for i = 1, n do
        pts[i] = { x = baseX + (i - 1) * 40, y = cy + ((i % 2 == 0) and 14 or -14) }
    end
    return pts
end

--------------------------------------------------------------------------------
-- damage & repair
--------------------------------------------------------------------------------

function Ship.damageHull(amount, impactAngleLocal)
    if State.godmode then return "god" end
    local s = State.ship

    -- shields cover an arc around the facing the shield officer picked
    if s.shield > 1 and s.maxShield > 0 then
        local diff = math.abs(((impactAngleLocal - s.shieldAngle + math.pi) % (2 * math.pi)) - math.pi)
        local arc = s.shieldArc or math.rad(55)
        if s.braceTimer > 0 then arc = arc * 1.5 end
        if diff <= arc then
            local absorbed = amount * ((s.braceTimer > 0) and 1.0 or 1.0)
            local taken = math.min(s.shield, absorbed)
            s.shield = s.shield - taken
            s.shieldHitTimer = 0.35
            local leak = amount - taken
            if leak <= 0 then return "shield" end
            amount = leak
        end
    end

    s.hull = s.hull - amount
    s.shieldHitTimer = 0.15

    -- splash the hit into a random bay, which degrades whatever it does
    local mods = s.modules
    if #mods > 0 then
        local m = mods[love.math.random(#mods)]
        local before = m.hp
        m.hp = math.max(0, m.hp - amount * 1.6)
        if m.room then m.room.hp = m.hp end
        if before > 0 and m.hp <= 0 then
            State.say(Ship.KINDS[m.kind].name .. " BREACHED - station offline", Palette.danger)
            if m.station and m.station.occupant then
                m.station.occupant.station = nil
                m.station.occupant = nil
            end
        end
        Ship.recomputeStats()
    end

    if s.hull <= 0 then
        s.hull = 0
        State.phase = "dead"
        State.showBanner("HULL BREACH\nALL HANDS LOST", 99)
    end
    return "hull"
end

function Ship.repairTick(room, dt)
    local m = room.module
    if not m then return false end
    if m.hp >= m.maxhp then return false end
    local wasOffline = m.hp <= 0
    m.hp = math.min(m.maxhp, m.hp + 14 * dt)
    room.hp = m.hp
    if wasOffline and m.hp > 0 then
        State.say(Ship.KINDS[m.kind].name .. " BACK ONLINE", Palette.good)
    end
    Ship.recomputeStats()
    return true
end

--------------------------------------------------------------------------------
-- per-frame
--------------------------------------------------------------------------------

function Ship.update(dt)
    local s = State.ship

    s.shieldHitTimer = math.max(0, s.shieldHitTimer - dt)
    s.braceTimer     = math.max(0, s.braceTimer - dt)
    s.batteryTimer   = math.max(0, s.batteryTimer - dt)
    s.batteryCool    = math.max(0, s.batteryCool - dt)

    -- power can exceed output if the reactor goes down or a battery dump ends;
    -- shed from the least critical system first so it self-corrects.
    local over = Ship.powerUsed() - Ship.reactorOutput()
    while over > 0 do
        if s.power.weapons > 0 then s.power.weapons = s.power.weapons - 1
        elseif s.power.shields > 0 then s.power.shields = s.power.shields - 1
        elseif s.power.engines > 0 then s.power.engines = s.power.engines - 1
        else break end
        over = over - 1
    end

    -- shields recharge; tended bays recharge much faster
    if s.maxShield > 0 and s.shieldHitTimer <= 0 then
        local frac = s.power.shields / 5
        local tend = 0
        for _, m in ipairs(Ship.modulesOfKind("shields")) do
            if not Ship.isOffline(m) then
                tend = tend + (Ship.isManned(m) and 1.0 or 0.35)
            end
        end
        local rate = 7 * (0.15 + 0.85 * frac) * tend
        s.shield = math.min(s.maxShield, s.shield + rate * dt)
    end

    -- turret charge
    local wFrac = s.power.weapons / 5
    for _, m in ipairs(Ship.modulesOfKind("weapons")) do
        if not Ship.isOffline(m) then
            local rate = (0.18 + 0.72 * wFrac) * (0.4 + 0.6 * Ship.healthFactor(m))
            m.charge = math.min(1, (m.charge or 0) + rate * dt)
        else
            m.charge = 0
        end
    end

    -- engine + reactor heat
    for _, m in ipairs(Ship.modulesOfKind("engine")) do
        local target = m.overdrive and 1.0 or (State.space.throttle * 0.45)
        local cool = Ship.isManned(m) and 0.30 or 0.10
        m.heat = m.heat + (target - m.heat * cool * 3) * dt * 0.35
        m.heat = math.max(0, math.min(1.3, m.heat))
        if m.heat >= 1.0 then
            if not State.godmode then
                m.hp = math.max(0, m.hp - 9 * dt)
                if m.room then m.room.hp = m.hp end
            end
            if m.overdrive and m.heat > 1.2 then
                m.overdrive = false
                State.say("ENGINE OVERHEAT - overdrive cut out", Palette.warn)
            end
        end
    end
    for _, m in ipairs(Ship.modulesOfKind("reactor")) do
        local cool = Ship.isManned(m) and 0.9 or 0.25
        m.heat = math.max(0, math.min(1.2, m.heat + (0.35 - cool) * dt * 0.5))
        if m.heat >= 1.0 and not State.godmode then
            m.hp = math.max(0, m.hp - 7 * dt)
            if m.room then m.room.hp = m.hp end
        end
    end

    -- drop a mounted crew member if their bay gets breached under them
    for _, st in ipairs(s.stations) do
        if st.module and Ship.isOffline(st.module) and st.occupant then
            st.occupant.station = nil
            st.occupant = nil
        end
    end
end

return Ship
