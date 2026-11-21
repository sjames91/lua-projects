-- TEMPORARY dev harness: drives the game with scripted input so the mechanics
-- can be verified without four humans. Run with:  lovec . autotest
local Autotest = {}

local State    = require("game/state")
local Ship     = require("game/ship")
local Space    = require("game/space")
local Players  = require("game/players")
local Render   = require("game/render")
local Input    = require("game/input")
local Stations = require("game/stations")

local held = {}
local frame = 0
local fails = 0

local function check(name, cond, extra)
    if cond then
        print(("PASS  %s %s"):format(name, extra or ""))
    else
        fails = fails + 1
        print(("FAIL  %s %s"):format(name, extra or ""))
    end
end

local function keyFor(pi, which)
    return Input.KEYMAPS[pi][which][1]
end

local function hold(pi, which, on)
    held[keyFor(pi, which)] = on or nil
end

local function stationOfKind(kind, n)
    local c = 0
    for _, st in ipairs(State.ship.stations) do
        if st.kind == kind then
            c = c + 1
            if c == (n or 1) then return st end
        end
    end
end

local function teleportTo(p, st)
    p.body.x = st.ix - Players.BODY_W / 2
    p.body.y = (st.facing == "down") and (st.py + st.h + 6) or (st.py - Players.BODY_H - 6)
    p.body.vx, p.body.vy = 0, 0
end

-- P1 bridge, P2 helm, P3 engineering, P4 weapons
local ASSIGN = { "bridge", "helm", "engineering", "weapons" }

local script = {}

script[1] = function()
    Render.showHelp = true
    love.graphics.captureScreenshot("shot_help.png")
end

script[3] = function()
    Render.showHelp = false
end

script[4] = function()
    check("ship built", #State.ship.modules == 4, "modules=" .. #State.ship.modules)
    check("stations built", #State.ship.stations == 5, "stations=" .. #State.ship.stations)
    check("walls merged", #State.ship.walls > 0 and #State.ship.walls < 90,
        "walls=" .. #State.ship.walls)
    check("crew spawned", #State.players == 4)
    check("crew start in corridor",
        State.players[1].room == State.ship.corridor,
        "room=" .. tostring(State.players[1].room and State.players[1].room.name))
    for i, p in ipairs(State.players) do
        teleportTo(p, stationOfKind(ASSIGN[i]))
    end
end

script[5] = function()
    for i = 1, 4 do hold(i, "action", true) end
end

script[7] = function()
    for i = 1, 4 do hold(i, "action", false) end
end

script[9] = function()
    for i, p in ipairs(State.players) do
        check("P" .. i .. " mounted " .. ASSIGN[i],
            p.station ~= nil and p.station.kind == ASSIGN[i],
            "got=" .. tostring(p.station and p.station.kind))
    end
    -- helm: throttle up and turn right
    hold(2, "up", true)
    hold(2, "right", true)
    -- engineering: select shields, pour power in
    hold(3, "right", true)
end

script[40] = function()
    hold(3, "right", false)
    check("throttle rose", State.space.throttle > 0.2,
        ("throttle=%.2f"):format(State.space.throttle))
    check("ship turned", math.abs(State.space.angle) > 0.1,
        ("angle=%.2f"):format(State.space.angle))
    check("ship moving", Space.speed() > 5, ("spd=%.1f"):format(Space.speed()))
    hold(3, "up", true)   -- assign power to whatever is selected
end

script[60] = function()
    hold(3, "up", false)
    local used = Ship.powerUsed()
    check("power reassigned", used > 4, "used=" .. used .. " out=" .. Ship.reactorOutput())
    check("power never exceeds output", Ship.powerUsed() <= Ship.reactorOutput())
    Space.startWave()
end

script[64] = function()
    check("wave spawned", #State.space.enemies > 0, "enemies=" .. #State.space.enemies)
    check("contacts start outside the sensor horizon", #Space.contacts() == 0,
        "radar=" .. tostring(State.ship.radarRange))
    -- drag them inside radar range so the bridge has something to mark
    for _, e in ipairs(State.space.enemies) do
        e.x, e.y = State.space.x + 320, State.space.y + 120
    end
    check("contacts appear once inside the horizon", #Space.contacts() > 0,
        "contacts=" .. #Space.contacts())
    hold(1, "right", true)
end

script[70] = function()
    hold(1, "right", false)
    check("bridge designated a contact", State.ship.designated ~= nil)
    check("designation gives the gunners a bearing",
        State.ship.designated and Space.relBearing(State.ship.designated.x, State.ship.designated.y) >= 0)
    hold(4, "action", true)
end

script[100] = function()
    check("friendly bolts in flight", #State.space.bolts > 0, "bolts=" .. #State.space.bolts)
    local friendly = 0
    for _, b in ipairs(State.space.bolts) do if b.friendly then friendly = friendly + 1 end end
    check("turret actually fired", friendly > 0, "friendly=" .. friendly)
    hold(4, "action", false)
end

script[120] = function()
    -- a crew member cannot operate a station from the wrong room
    local p = State.players[4]
    local wep = p.station
    hold(4, "back", true)
    Autotest.wep = wep
end

script[123] = function()
    hold(4, "back", false)
    check("dismount works", State.players[4].station == nil)
    local p = State.players[4]
    -- stand in the corridor and try to use the weapons console from there
    p.body.x, p.body.y = 200, 1 * State.TILE
    p.x, p.y = p.body.x + 9, p.body.y + 7
    Ship.updateOccupancy()
    check("corridor is not the weapons bay", p.room == State.ship.corridor,
        "room=" .. tostring(p.room and p.room.name))
    check("no station reachable from the corridor mid-ship",
        Ship.stationFor(p) == nil)
end

script[126] = function()
    -- go buy an upgrade at the fabricator
    local p = State.players[4]
    teleportTo(p, State.ship.fabricator)
    State.scrap = 400
end

script[130] = function() hold(4, "action", true) end
script[132] = function() hold(4, "action", false) end

script[134] = function()
    local p = State.players[4]
    check("fabricator mounted", p.station == State.ship.fabricator,
        "station=" .. tostring(p.station and p.station.kind))
    hold(4, "down", true)   -- move off HULL PLATING onto AUX ENGINE
end

script[137] = function()
    hold(4, "down", false)
    Autotest.beforeMods = #State.ship.modules
    Autotest.beforeSlot = State.ship.maxSlot
end

script[140] = function() hold(4, "action", true) end
script[142] = function() hold(4, "action", false) end

script[146] = function()
    check("upgrade added a module", #State.ship.modules == Autotest.beforeMods + 1,
        ("%d -> %d"):format(Autotest.beforeMods, #State.ship.modules))
    check("hull grew a slot", State.ship.maxSlot > Autotest.beforeSlot,
        ("slot %d -> %d"):format(Autotest.beforeSlot, State.ship.maxSlot))
    local eb = stationOfKind("engine")
    check("new bay has a console", eb ~= nil)
    check("new bay console is inside its own room", eb and eb.room and eb.room.kind == "engine",
        "room=" .. tostring(eb and eb.room and eb.room.name))
    check("crew survived the rebuild still mounted",
        State.players[4].station == State.ship.fabricator)
    check("other crew still mounted",
        State.players[1].station ~= nil and State.players[2].station ~= nil)
    -- untended engine should give less thrust than a tended one
    Autotest.untended = Ship.engineOutput()
end

script[150] = function()
    local eb = stationOfKind("engine")
    local p = State.players[4]
    Players.dismount(p)
    teleportTo(p, eb)
end

script[154] = function() hold(4, "action", true) end
script[156] = function() hold(4, "action", false) end

script[160] = function()
    local eb = stationOfKind("engine")
    check("engine bay mounted", State.players[4].station == eb,
        "station=" .. tostring(State.players[4].station and State.players[4].station.kind))
    local tended = Ship.engineOutput()
    check("tending the engine bay raises output", tended > Autotest.untended,
        ("%.2f -> %.2f"):format(Autotest.untended, tended))
end

script[165] = function()
    -- buy enough to exceed the crew, which is the whole point of the design
    for _ = 1, 4 do
        State.scrap = 500
        Ship.buy(Ship.UPGRADES[3])   -- turret battery
    end
    check("more bays than crew", #State.ship.stations > #State.players,
        ("%d stations / %d crew"):format(#State.ship.stations, #State.players))
    check("shield + sensor + reactor buys work", (function()
        State.scrap = 2000
        local okA = Ship.buy(Ship.UPGRADES[4])
        local okB = Ship.buy(Ship.UPGRADES[5])
        local okC = Ship.buy(Ship.UPGRADES[6])
        return okA and okB and okC
    end)())
    Ship.recomputeStats()
    check("shield generator gives shields", State.ship.maxShield > 0,
        "maxShield=" .. State.ship.maxShield)
    check("sensors extend radar", (State.ship.radarRange or 0) > 900,
        "range=" .. tostring(State.ship.radarRange))
end

script[175] = function()
    love.graphics.captureScreenshot("shot_combat.png")
end

script[180] = function()
    -- breach a bay and confirm its occupant is thrown off station
    local eb = stationOfKind("engine")
    local occ = eb.occupant
    eb.module.hp = 0
    Autotest.breachOcc = occ
end

script[183] = function()
    check("breached bay drops its occupant",
        Autotest.breachOcc == nil or Autotest.breachOcc.station == nil)
    check("breached module is offline", Ship.isOffline(stationOfKind("engine").module))
    -- repair it by standing in the room holding BACK
    local p = Autotest.breachOcc or State.players[4]
    local eb = stationOfKind("engine")
    p.body.x = eb.room.px + eb.room.pw / 2
    p.body.y = eb.room.py + eb.room.ph / 2
    hold(4, "back", true)
end

script[230] = function()
    hold(4, "back", false)
    check("repair brought the bay back", not Ship.isOffline(stationOfKind("engine").module),
        "hp=" .. tostring(stationOfKind("engine").module.hp))
end

script[235] = function()
    -- shields must only absorb on the facing they are set to
    local sh = State.ship
    sh.shieldAngle = 0
    sh.shield = sh.maxShield
    local before, hull0 = sh.shield, sh.hull
    Ship.damageHull(10, 0)            -- dead ahead: shield eats it
    check("shield absorbs on its facing", sh.shield < before and sh.hull == hull0,
        ("shield %.0f -> %.0f, hull %.0f -> %.0f"):format(before, sh.shield, hull0, sh.hull))
    local hullBefore = sh.hull
    Ship.damageHull(10, math.pi)      -- astern: shield does nothing
    check("shield ignores the far side", sh.hull < hullBefore,
        ("hull %.0f -> %.0f"):format(hullBefore, sh.hull))
end

script[240] = function()
    love.graphics.captureScreenshot("shot_big_ship.png")
end

-- panel tour: put crew on the consoles the earlier shots never showed
script[246] = function()
    for i = 1, 4 do
        for _, d in ipairs({ "up", "down", "left", "right", "action", "back" }) do
            hold(i, d, false)
        end
    end
    State.ship.shield = State.ship.maxShield
    local tour = { [2] = stationOfKind("shields"), [3] = stationOfKind("sensors"),
                   [4] = State.ship.fabricator }
    for i, st in pairs(tour) do
        local p = State.players[i]
        Players.dismount(p)
        teleportTo(p, st)
    end
    for _, e in ipairs(State.space.enemies) do
        e.x, e.y = State.space.x + 260, State.space.y - 180
    end
end

script[250] = function() for i = 2, 4 do hold(i, "action", true) end end
script[252] = function() for i = 2, 4 do hold(i, "action", false) end end

script[256] = function()
    for i, kind in pairs({ [2] = "shields", [3] = "sensors", [4] = "fabricator" }) do
        check("P" .. i .. " on " .. kind, State.players[i].station ~= nil
            and State.players[i].station.kind == kind,
            "got=" .. tostring(State.players[i].station and State.players[i].station.kind))
    end
    check("mounting did not trigger a purchase", State.scrap > 0, "scrap=" .. State.scrap)
end

script[258] = function()
    -- scroll the fabricator to the last entry to prove the list is reachable
    local fab = State.ship.fabricator
    fab.sel = #Stations.fabItems()
    check("fabricator list has every upgrade plus general quarters",
        #Stations.fabItems() >= #Ship.UPGRADES, "items=" .. #Stations.fabItems())
end

script[262] = function()
    love.graphics.captureScreenshot("shot_panels.png")
end

script[266] = function()
    local Assets = require("game/assets")
    local n = Assets.export()
    check("texture export writes PNGs", n > 20, "textures=" .. n)
    local files = love.filesystem.getDirectoryItems("assets_export")
    check("exported files land on disk", #files == n, "files=" .. #files)
end

script[268] = function()
    -- a fresh game must not inherit anything from the finished one
    local Sprite = require("Engine/Chispita_sprite")
    _G.NEWGAME()
    check("restart rebuilds the starting ship", #State.ship.modules == 4,
        "modules=" .. #State.ship.modules)
    check("restart clears old stations", #State.ship.stations == 5,
        "stations=" .. #State.ship.stations)
    check("restart leaves nobody mounted", (function()
        for _, st in ipairs(State.ship.stations) do
            if st.occupant then return false end
        end
        return true
    end)())
    check("restart leaves no orphan sprites", #Sprite.sprites < 40,
        "sprites=" .. #Sprite.sprites)
    check("restart resets the hull", State.ship.hull == State.ship.maxHull
        and State.ship.maxHull == 120, "hull=" .. State.ship.hull .. "/" .. State.ship.maxHull)
end

-- wave flow on the fresh ship
script[272] = function()
    check("new game starts in a lull", State.phase == "lull", "phase=" .. State.phase)
    Space.startWave()
    check("wave starts combat", State.phase == "combat" and #State.space.enemies > 0,
        "phase=" .. State.phase .. " enemies=" .. #State.space.enemies)
    Autotest.scrapBefore = State.scrap
end

script[276] = function()
    for _, e in ipairs(State.space.enemies) do e.hp = 0 end
end

script[280] = function()
    check("clearing the wave returns to a lull", State.phase == "lull", "phase=" .. State.phase)
    check("clearing the wave pays out", State.scrap > Autotest.scrapBefore,
        ("%d -> %d"):format(Autotest.scrapBefore, State.scrap))
    check("general quarters is offered during a lull",
        (function()
            for _, it in ipairs(Stations.fabItems()) do
                if it.kind == "gq" then return true end
            end
        end)())
end

script[284] = function()
    Ship.damageHull(9999, 0)
    check("losing the hull ends the run", State.phase == "dead", "phase=" .. State.phase)
end

script[288] = function()
    NEWGAME()
    State.scrap = 500
    Ship.buy(Ship.UPGRADES[2])   -- aux engine, so there's an engine bay to overheat
    State.godmode = true
    State.ship.shield = 0
    local hull0 = State.ship.hull
    Ship.damageHull(500, 0)
    check("godmode blocks hull damage", State.ship.hull == hull0,
        ("%d -> %d"):format(hull0, State.ship.hull))
    local eng = stationOfKind("engine").module
    eng.heat = 1.0
    Ship.update(0.5)
    check("godmode blocks overheat damage", eng.hp == eng.maxhp, "hp=" .. eng.hp)
    State.godmode = false
    local hull1 = State.ship.hull
    Ship.damageHull(10, 0)
    check("godmode off lets damage through again", State.ship.hull < hull1,
        ("%d -> %d"):format(hull1, State.ship.hull))
end

script[290] = function()
    print(("\n==== %d failure(s) ===="):format(fails))
    print("screenshots in " .. love.filesystem.getSaveDirectory())
    love.event.quit()
end

function Autotest.start()
    Render.showHelp = false
    love.keyboard.isDown = function(...)
        for _, k in ipairs({ ... }) do
            if held[k] then return true end
        end
        return false
    end
    print("=== AUTOTEST ===")
end

local acc = 0
local STEP = 0.06   -- real seconds per script step, so physics has time to act

function Autotest.tick(dt)
    acc = acc + (dt or 0)
    if acc < STEP then return end
    acc = acc - STEP
    frame = frame + 1
    local fn = script[frame]
    if fn then
        local ok, err = pcall(fn)
        if not ok then
            fails = fails + 1
            print(("FAIL  script frame %d errored: %s"):format(frame, err))
        end
    end
    if frame > 400 then love.event.quit() end
end

return Autotest
