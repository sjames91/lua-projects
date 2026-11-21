-- Station behaviour and station readouts.
--
-- This file is where the whole design lives: each console only accepts input
-- from the crew member physically standing at it, and each console only shows
-- the slice of ship state its job needs. Nobody can see everything, so the
-- crew has to talk.

local State   = require("game/state")
local Palette = require("game/palette")
local Assets  = require("game/assets")
local Ship    = require("game/ship")
local Space   = require("game/space")
local UI      = require("game/ui")

local Stations = {}

local lg = love.graphics
local TURRET_ARC = math.rad(115)

--------------------------------------------------------------------------------
-- fabricator menu
--------------------------------------------------------------------------------

local function fabItems()
    local items = {}
    for _, up in ipairs(Ship.UPGRADES) do
        table.insert(items, { kind = "buy", up = up, label = up.label, cost = up.cost, desc = up.desc })
    end
    if State.phase == "lull" then
        table.insert(items, {
            kind = "gq", label = "SOUND GENERAL QUARTERS", cost = 0,
            desc = "Skip the lull, start the wave now. +18 scrap bounty.",
        })
    end
    return items
end

--------------------------------------------------------------------------------
-- per-station logic
--------------------------------------------------------------------------------

local logic = {}

function logic.helm(st, p, c, dt)
    local s = State.space
    if c.left  then s.turnInput = s.turnInput - 1 end
    if c.right then s.turnInput = s.turnInput + 1 end
    if c.up   then s.throttle = math.min(1, s.throttle + dt * 0.9) end
    if c.down then s.throttle = math.max(0, s.throttle - dt * 1.4) end
    if c.actionPressed then
        s.throttle = 0
        State.say("HELM: all stop")
    end
end

function logic.bridge(st, p, c, dt)
    local contacts = Space.contacts()
    if #contacts == 0 then
        State.ship.designated = nil
        return
    end
    local function cycle(dir)
        local idx = 1
        for i, ct in ipairs(contacts) do
            if ct.enemy == State.ship.designated then idx = i end
        end
        idx = ((idx - 1 + dir) % #contacts) + 1
        State.ship.designated = contacts[idx].enemy
    end
    if c.leftRepeat  then cycle(-1) end
    if c.rightRepeat then cycle(1) end
    if c.actionPressed then
        st.zoom = (st.zoom == 0.34) and 0.62 or 0.34
    end
end

function logic.weapons(st, p, c, dt)
    local m = st.module
    if not m then return end
    local rate = 1.5 * dt
    if c.left  then m.turret = math.max(-TURRET_ARC, m.turret - rate) end
    if c.right then m.turret = math.min(TURRET_ARC, m.turret + rate) end
    if c.upPressed or c.downPressed then
        m.mode = (m.mode == "bolt") and "burst" or "bolt"
    end
    if c.action then
        st.fireHold = (st.fireHold or 0) - dt
        if st.fireHold <= 0 then
            if Space.fireTurret(m) then
                st.fireHold = (m.mode == "burst") and 0.5 or 0.16
            else
                st.fireHold = 0.1
            end
        end
    else
        st.fireHold = 0
    end
end

local SYSTEMS = { "engines", "shields", "weapons" }

function logic.engineering(st, p, c, dt)
    local s = State.ship
    if c.leftRepeat  then st.sel = ((st.sel - 2) % 3) + 1 end
    if c.rightRepeat then st.sel = (st.sel % 3) + 1 end
    local key = SYSTEMS[st.sel]
    if c.upRepeat then
        if Ship.powerFree() > 0 and s.power[key] < 5 then
            s.power[key] = s.power[key] + 1
        end
    end
    if c.downRepeat then
        if s.power[key] > 0 then s.power[key] = s.power[key] - 1 end
    end
    if c.actionPressed then
        if s.batteryCool <= 0 then
            s.batteryTimer = 8
            s.batteryCool = 26
            State.say("ENGINEERING: battery dump - +3 power for 8s", Palette.warn)
        end
    end
end

local FACINGS = { 0, math.pi / 2, math.pi, -math.pi / 2 }

function logic.shields(st, p, c, dt)
    local s = State.ship
    local function idx()
        for i, a in ipairs(FACINGS) do
            if math.abs(Space.norm(a - s.shieldAngle)) < 0.01 then return i end
        end
        return 1
    end
    if c.leftRepeat  then s.shieldAngle = FACINGS[((idx() - 2) % 4) + 1] end
    if c.rightRepeat then s.shieldAngle = FACINGS[(idx() % 4) + 1] end
    if c.actionPressed and s.shield > s.maxShield * 0.25 and s.braceTimer <= 0 then
        s.braceTimer = 2.2
        s.shield = s.shield - s.maxShield * 0.15
        State.say("SHIELDS: bracing", Palette.sys_shields)
    end
end

function logic.engine(st, p, c, dt)
    local m = st.module
    if not m then return end
    if c.actionPressed then
        m.overdrive = not m.overdrive
        State.say("ENGINE BAY: overdrive " .. (m.overdrive and "ENGAGED" or "off"),
            m.overdrive and Palette.warn or nil)
    end
end

function logic.reactor(st, p, c, dt)
    local m = st.module
    if not m then return end
    if c.action then
        m.heat = math.max(0, m.heat - dt * 1.1)
        st.purging = 0.2
    end
end

function logic.sensors(st, p, c, dt)
    local contacts = Space.contacts()
    if #contacts == 0 then st.sel = 1 return end
    if c.upRepeat   then st.sel = ((st.sel - 2) % #contacts) + 1 end
    if c.downRepeat then st.sel = (st.sel % #contacts) + 1 end
    st.sel = math.max(1, math.min(#contacts, st.sel))
    if c.actionPressed then
        State.ship.designated = contacts[st.sel].enemy
        State.say("SENSORS: contact designated", Palette.sys_sensors)
    end
end

function logic.fabricator(st, p, c, dt)
    local items = fabItems()
    if c.upRepeat   then st.sel = ((st.sel - 2) % #items) + 1 end
    if c.downRepeat then st.sel = (st.sel % #items) + 1 end
    st.sel = math.max(1, math.min(#items, st.sel))
    local it = items[st.sel]

    if c.actionPressed then
        if it.kind == "gq" then
            State.scrap = State.scrap + 18
            Space.startWave()
        else
            local ok, why = Ship.buy(it.up)
            if not ok then
                st.error = why
                st.errorTimer = 2.0
            end
        end
    end
    st.errorTimer = math.max(0, (st.errorTimer or 0) - dt)
end

--------------------------------------------------------------------------------
-- update
--------------------------------------------------------------------------------

function Stations.update(dt)
    for _, st in ipairs(State.ship.stations) do
        st.blink = (st.blink or 0) + dt
        st.purging = math.max(0, (st.purging or 0) - dt)
        local p = st.occupant
        if st.suppressAction then
            st.suppressAction = false
        elseif p and not (st.module and Ship.isOffline(st.module)) then
            local fn = logic[st.kind]
            if fn then fn(st, p, p.ctrl, dt) end
        end
    end
end

--------------------------------------------------------------------------------
-- readouts
--------------------------------------------------------------------------------

local panels = {}

local function kv(label, value, x, y, colour)
    UI.label(label, x, y, Palette.ink_dim, Assets.fonts.tiny)
    UI.label(value, x + 62, y, colour or Palette.ink, Assets.fonts.small)
end

function panels.helm(st, x, y, w, h)
    local s = State.space
    UI.compass(x + 50, y + 58, 34, s.angle + math.pi / 2, Palette.station.helm,
        ("HDG %03d"):format(math.floor(Space.headingDeg())))

    local bx = x + 106
    UI.label("THROTTLE", bx, y + 22, Palette.ink_dim, Assets.fonts.tiny)
    UI.bar(bx, y + 33, w - 118, 15, s.throttle, Palette.station.helm, nil,
        ("%d%%"):format(math.floor(s.throttle * 100)))

    UI.label("VELOCITY", bx, y + 53, Palette.ink_dim, Assets.fonts.tiny)
    UI.bar(bx, y + 64, w - 118, 15, Space.speed() / 420, Palette.ink, nil,
        ("%d m/s"):format(math.floor(Space.speed())))

    UI.label("ENGINE POWER FROM ENGINEERING", bx, y + 84, Palette.ink_dim, Assets.fonts.tiny)
    UI.pips(bx, y + 95, State.ship.power.engines, 5, 5, Palette.sys_engines)

    UI.label("LEFT/RIGHT turn   UP/DOWN throttle   USE all-stop",
        x + 8, y + h - 30, Palette.ink_dim, Assets.fonts.tiny)
    UI.label("NO TACTICAL FEED AT THE HELM - ASK THE BRIDGE",
        x + 8, y + h - 17, Palette.warn, Assets.fonts.tiny)
end

function panels.weapons(st, x, y, w, h)
    local m = st.module
    if not m then return end
    local cx, cy, r = x + 58, y + 62, 40

    -- traverse arc, drawn as a fan pointing up (ship forward)
    UI.wedge(cx, cy, 8, r, -math.pi / 2, TURRET_ARC, Palette.sys_weapons, 0.16)
    Palette.set(Palette.screen_grid)
    lg.setLineWidth(1)
    lg.arc("line", "open", cx, cy, r, -math.pi / 2 - TURRET_ARC, -math.pi / 2 + TURRET_ARC)
    lg.line(cx, cy, cx, cy - r)

    -- designated bearing from the bridge / sensors
    local des = State.ship.designated
    if des then
        local b = math.rad(Space.relBearing(des.x, des.y)) - math.pi / 2
        Palette.set(Palette.ink, 0.9)
        lg.setLineWidth(2)
        lg.line(cx, cy, cx + math.cos(b) * r, cy + math.sin(b) * r)
        UI.label("MARK", cx + math.cos(b) * (r + 4) - 12, cy + math.sin(b) * (r + 4) - 6,
            Palette.ink, Assets.fonts.tiny)
    end

    -- turret needle
    local a = m.turret - math.pi / 2
    Palette.set(Palette.sys_weapons)
    lg.setLineWidth(3)
    lg.line(cx, cy, cx + math.cos(a) * r * 0.92, cy + math.sin(a) * r * 0.92)
    lg.circle("fill", cx, cy, 4)

    local bx = x + 112
    kv("TRAVERSE", ("%+d deg"):format(math.floor(math.deg(m.turret))), bx, y + 22)
    kv("MODE", m.mode == "burst" and "BURST x3" or "SINGLE BOLT", bx, y + 40,
        m.mode == "burst" and Palette.warn or Palette.ink)
    UI.label("CHARGE", bx, y + 58, Palette.ink_dim, Assets.fonts.tiny)
    UI.bar(bx, y + 69, w - 124, 15, m.charge or 0,
        (m.charge or 0) > 0.42 and Palette.sys_weapons or Palette.ink_dim)
    UI.label("GUN POWER", bx, y + 89, Palette.ink_dim, Assets.fonts.tiny)
    UI.pips(bx, y + 100, State.ship.power.weapons, 5, 5, Palette.sys_weapons)

    UI.label("LEFT/RIGHT traverse   UP/DOWN mode   USE fire",
        x + 8, y + h - 30, Palette.ink_dim, Assets.fonts.tiny)
    if des then
        UI.label(("MARK AT %03d deg - RANGE %d"):format(
            math.floor(Space.relBearing(des.x, des.y)), math.floor(Space.rangeTo(des.x, des.y))),
            x + 8, y + h - 17, Palette.ink, Assets.fonts.tiny)
    else
        UI.label("NO MARK - BRIDGE OR SENSORS MUST DESIGNATE",
            x + 8, y + h - 17, Palette.warn, Assets.fonts.tiny)
    end
end

function panels.engineering(st, x, y, w, h)
    local s = State.ship
    local out = Ship.reactorOutput()
    local free = Ship.powerFree()

    UI.label(("REACTOR OUTPUT  %d"):format(out), x + 8, y + 22, Palette.sys_engines, Assets.fonts.small)
    UI.label(("UNASSIGNED  %d"):format(free), x + 150, y + 22,
        free > 0 and Palette.good or Palette.ink_dim, Assets.fonts.small)
    if s.batteryTimer > 0 then
        UI.label(("BATTERY DUMP %.1fs"):format(s.batteryTimer), x + 258, y + 22, Palette.warn, Assets.fonts.small)
    elseif s.batteryCool > 0 then
        UI.label(("DUMP COOLDOWN %.0fs"):format(s.batteryCool), x + 258, y + 22, Palette.ink_dim, Assets.fonts.small)
    else
        UI.label("USE = BATTERY DUMP", x + 258, y + 22, Palette.ink_dim, Assets.fonts.small)
    end

    local rows = {
        { key = "engines", label = "ENGINES", colour = Palette.sys_engines },
        { key = "shields", label = "SHIELDS", colour = Palette.sys_shields },
        { key = "weapons", label = "WEAPONS", colour = Palette.sys_weapons },
    }
    for i, row in ipairs(rows) do
        local ry = y + 40 + (i - 1) * 22
        UI.label(row.label, x + 8, ry + 2, (st.sel == i) and row.colour or Palette.ink_dim, Assets.fonts.tiny)
        UI.pips(x + 66, ry, s.power[row.key], s.power[row.key] + free, 5, row.colour, st.sel == i)
    end

    -- damage control: engineering is the only station with the raw numbers
    local px = x + 176
    UI.label("HULL", px, y + 42, Palette.ink_dim, Assets.fonts.tiny)
    UI.bar(px + 34, y + 40, w - px + x - 44, 14, s.hull / s.maxHull,
        s.hull / s.maxHull > 0.35 and Palette.good or Palette.danger, nil,
        ("%d/%d"):format(math.floor(s.hull), s.maxHull))
    UI.label("SHLD", px, y + 62, Palette.ink_dim, Assets.fonts.tiny)
    if s.maxShield > 0 then
        UI.bar(px + 34, y + 60, w - px + x - 44, 14, s.shield / s.maxShield, Palette.sys_shields, nil,
            ("%d/%d"):format(math.floor(s.shield), math.floor(s.maxShield)))
    else
        UI.bar(px + 34, y + 60, w - px + x - 44, 14, 0, Palette.ink_dim, nil, "NONE FITTED")
    end

    local dmg = {}
    for _, m in ipairs(s.modules) do
        if m.hp < m.maxhp then
            table.insert(dmg, ("%s %d%%"):format(Ship.KINDS[m.kind].name, math.floor(m.hp / m.maxhp * 100)))
        end
    end
    UI.label("DAMAGE", px, y + 82, Palette.ink_dim, Assets.fonts.tiny)
    if #dmg == 0 then
        UI.label("ALL BAYS NOMINAL", px + 54, y + 81, Palette.good, Assets.fonts.tiny)
    else
        lg.setFont(Assets.fonts.tiny)
        Palette.set(Palette.danger)
        lg.printf(table.concat(dmg, "   "), px + 54, y + 81, w - px + x - 60, "left")
        lg.setColor(1, 1, 1, 1)
    end

    UI.label("LEFT/RIGHT pick system   UP/DOWN assign power   USE battery dump",
        x + 8, y + h - 17, Palette.ink_dim, Assets.fonts.tiny)
end

function panels.shields(st, x, y, w, h)
    local s = State.ship
    local cx, cy = x + 64, y + 70
    local r = 30

    Palette.set(Palette.screen)
    lg.circle("fill", cx, cy, r + 8)
    Palette.set(Palette.screen_grid)
    lg.setLineWidth(1)
    lg.circle("line", cx, cy, r + 8)

    if s.maxShield > 0 then
        local arc = (s.shieldArc or math.rad(55)) * ((s.braceTimer > 0) and 1.5 or 1)
        local a = s.shieldAngle - math.pi / 2     -- fore is up on this diagram
        local strength = s.shield / s.maxShield
        UI.wedge(cx, cy, r - 4, r + 6, a, arc, Palette.sys_shields, 0.25 + 0.55 * strength)
    end

    -- hull icon, nose up
    Palette.set(Palette.hull_light)
    lg.polygon("fill", cx, cy - 17, cx + 7, cy - 3, cx + 6, cy + 15, cx - 6, cy + 15, cx - 7, cy - 3)
    Palette.set(Palette.hull_dark)
    lg.setLineWidth(1)
    lg.polygon("line", cx, cy - 17, cx + 7, cy - 3, cx + 6, cy + 15, cx - 6, cy + 15, cx - 7, cy - 3)

    lg.setFont(Assets.fonts.tiny)
    Palette.set(Palette.ink_dim)
    lg.print("FORE", cx - 12, cy - r - 14)
    lg.print("AFT", cx - 9, cy + r + 3)
    lg.print("P", cx - r - 16, cy - 5)
    lg.print("S", cx + r + 10, cy - 5)
    lg.setColor(1, 1, 1, 1)

    local bx = x + 124
    local names = { [0] = "FORE", "STARBOARD", "AFT", "PORT" }
    local idx = 0
    local F = { 0, math.pi / 2, math.pi, -math.pi / 2 }
    for i, a in ipairs(F) do
        if math.abs(Space.norm(a - s.shieldAngle)) < 0.01 then idx = i - 1 end
    end
    kv("FACING", names[idx] or "FORE", bx, y + 22, Palette.sys_shields)
    UI.label("STRENGTH", bx, y + 44, Palette.ink_dim, Assets.fonts.tiny)
    if s.maxShield > 0 then
        UI.bar(bx, y + 55, w - 136, 15, s.shield / s.maxShield, Palette.sys_shields, nil,
            ("%d"):format(math.floor(s.shield)))
    else
        UI.bar(bx, y + 55, w - 136, 15, 0, Palette.ink_dim, nil, "NO GENERATOR")
    end
    UI.label("SHIELD POWER", bx, y + 75, Palette.ink_dim, Assets.fonts.tiny)
    UI.pips(bx, y + 86, s.power.shields, 5, 5, Palette.sys_shields)
    if s.braceTimer > 0 then
        UI.label(("BRACED %.1fs"):format(s.braceTimer), bx + 110, y + 22, Palette.warn, Assets.fonts.small)
    end

    UI.label("LEFT/RIGHT rotate facing   USE brace",
        x + 8, y + h - 30, Palette.ink_dim, Assets.fonts.tiny)
    UI.label("YOU CANNOT SEE INCOMING FIRE - SOMEONE MUST CALL THE SIDE",
        x + 8, y + h - 17, Palette.warn, Assets.fonts.tiny)
end

function panels.engine(st, x, y, w, h)
    local m = st.module
    if not m then return end
    local manned = st.occupant ~= nil
    kv("OUTPUT", ("%d%%"):format(math.floor((manned and 100 or 40) * (m.overdrive and 1.7 or 1))),
        x + 8, y + 24, Palette.sys_engines)
    kv("TENDED", manned and "YES" or "NO", x + 8, y + 44, manned and Palette.good or Palette.danger)
    kv("OVERDRIVE", m.overdrive and "ENGAGED" or "OFF", x + 8, y + 64,
        m.overdrive and Palette.warn or Palette.ink_dim)

    UI.label("CORE TEMPERATURE", x + 178, y + 24, Palette.ink_dim, Assets.fonts.tiny)
    UI.gauge(x + 178, y + 36, w - 190, 18, m.heat, nil, 0.78)
    UI.label("INTEGRITY", x + 178, y + 60, Palette.ink_dim, Assets.fonts.tiny)
    UI.bar(x + 178, y + 72, w - 190, 16, m.hp / m.maxhp,
        m.hp / m.maxhp > 0.4 and Palette.good or Palette.danger, nil,
        ("%d%%"):format(math.floor(m.hp / m.maxhp * 100)))
    UI.label("THROTTLE SET BY HELM", x + 178, y + 94, Palette.ink_dim, Assets.fonts.tiny)
    UI.bar(x + 178, y + 104, w - 190, 10, State.space.throttle, Palette.station.helm)

    UI.label("Standing here doubles this engine. USE toggles overdrive.",
        x + 8, y + h - 30, Palette.ink_dim, Assets.fonts.tiny)
    if m.heat > 0.9 then
        UI.label("OVERHEATING - CUT OVERDRIVE OR THE BAY BURNS",
            x + 8, y + h - 17, Palette.danger, Assets.fonts.tiny)
    else
        UI.label("Leave the bay and output drops to 40%.",
            x + 8, y + h - 17, Palette.warn, Assets.fonts.tiny)
    end
end

function panels.reactor(st, x, y, w, h)
    local m = st.module
    if not m then return end
    local manned = st.occupant ~= nil
    kv("CORE", "ONLINE", x + 8, y + 24, Palette.sys_sensors)
    kv("TENDED", manned and "YES (+2 PWR)" or "NO", x + 8, y + 44,
        manned and Palette.good or Palette.danger)
    kv("INTEGRITY", ("%d%%"):format(math.floor(m.hp / m.maxhp * 100)), x + 8, y + 64)

    UI.label("CORE HEAT", x + 178, y + 24, Palette.ink_dim, Assets.fonts.tiny)
    UI.gauge(x + 178, y + 36, w - 190, 18, m.heat, nil, 0.72)
    UI.label("SHIP POWER OUTPUT", x + 178, y + 60, Palette.ink_dim, Assets.fonts.tiny)
    UI.pips(x + 178, y + 72, Ship.powerUsed(), Ship.reactorOutput(), 10, Palette.sys_sensors)

    UI.label("HOLD USE to purge coolant and drop core heat.",
        x + 8, y + h - 30, Palette.ink_dim, Assets.fonts.tiny)
    UI.label(st.purging > 0 and "PURGING" or "Unattended cores cook themselves.",
        x + 8, y + h - 17, st.purging > 0 and Palette.good or Palette.warn, Assets.fonts.tiny)
end

function panels.sensors(st, x, y, w, h)
    local contacts = Space.contacts()
    UI.label(("CONTACT LOG   RANGE %d"):format(State.ship.radarRange or 900),
        x + 8, y + 22, Palette.sys_sensors, Assets.fonts.small)

    if #contacts == 0 then
        UI.static(x + 8, y + 40, w - 16, h - 72, "NO CONTACTS IN RANGE")
    else
        UI.screen(x + 8, y + 38, w - 16, h - 70)
        lg.setFont(Assets.fonts.tiny)
        Palette.set(Palette.ink_dim)
        lg.print("  BRG   RNG    TYPE        HULL", x + 16, y + 44)
        for i = 1, math.min(5, #contacts) do
            local ct = contacts[i]
            local ry = y + 56 + (i - 1) * 14
            local sel = (i == st.sel)
            if sel then
                Palette.set(Palette.sys_sensors, 0.22)
                lg.rectangle("fill", x + 12, ry - 2, w - 24, 13)
            end
            local marked = (ct.enemy == State.ship.designated)
            Palette.set(marked and Palette.ink or Palette.sys_sensors)
            lg.print(("%s %03d  %5d   %-10s %3d%%"):format(
                marked and ">" or " ",
                math.floor(ct.bearing), math.floor(ct.range),
                ct.enemy.kind:upper(), math.floor(ct.enemy.hp / ct.enemy.maxhp * 100)),
                x + 16, ry)
        end
        lg.setColor(1, 1, 1, 1)
    end

    UI.label("UP/DOWN pick contact   USE designate it for the gunners",
        x + 8, y + h - 17, Palette.ink_dim, Assets.fonts.tiny)
end

function panels.fabricator(st, x, y, w, h)
    local items = fabItems()
    UI.label(("SCRAP  %d"):format(State.scrap), x + 8, y + 22, Palette.good, Assets.fonts.body)
    UI.label(("BAYS  %d"):format(#State.ship.modules), x + 110, y + 23, Palette.ink_dim, Assets.fonts.small)
    UI.label(("CREW  %d"):format(#State.players), x + 180, y + 23, Palette.ink_dim, Assets.fonts.small)

    local lx, ly, lw = x + 8, y + 40, w * 0.52
    local lh = h - 70
    local rowH = 13
    local visible = math.floor((lh - 6) / rowH)
    UI.screen(lx, ly, lw, lh)

    -- scroll the window so the selected row is always on screen
    local top = math.max(1, math.min(st.sel - math.floor(visible / 2), #items - visible + 1))
    if #items <= visible then top = 1 end

    lg.setFont(Assets.fonts.tiny)
    for row = 0, math.min(visible, #items) - 1 do
        local i = top + row
        local it = items[i]
        if not it then break end
        local ry = ly + 4 + row * rowH
        local sel = (i == st.sel)
        local affordable = (it.kind == "gq") or (State.scrap >= it.cost)
        if sel then
            Palette.set(Palette.station.fabricator, 0.22)
            lg.rectangle("fill", lx + 2, ry - 1, lw - 4, rowH)
        end
        Palette.set(affordable and (sel and Palette.ink or Palette.ink_dim) or Palette.danger)
        local cost = (it.kind == "gq") and "  --" or ("%4d"):format(it.cost)
        lg.print((sel and "> " or "  ") .. it.label, lx + 4, ry)
        lg.printf(cost, lx, ry, lw - 18, "right")   -- leave room for scroll arrows
    end
    -- more-items arrows
    Palette.set(Palette.ink_dim)
    if top > 1 then lg.print("^", lx + lw - 12, ly + 1) end
    if top + visible - 1 < #items then lg.print("v", lx + lw - 12, ly + lh - 12) end
    lg.setColor(1, 1, 1, 1)

    local dx = lx + lw + 10
    local dw = w - (dx - x) - 8
    local it = items[math.max(1, math.min(#items, st.sel))]
    UI.screen(dx, ly, dw, lh)
    lg.setFont(Assets.fonts.tiny)
    Palette.set(Palette.ink)
    lg.printf(it.label, dx + 6, ly + 6, dw - 12, "left")
    Palette.set(Palette.ink_dim)
    lg.printf(it.desc, dx + 6, ly + 22, dw - 12, "left")
    if it.kind == "buy" and it.up.room then
        Palette.set(Palette.warn)
        lg.printf("This adds a bay. Someone has to walk there and stand in it.",
            dx + 6, ly + 56, dw - 12, "left")
    end
    lg.setColor(1, 1, 1, 1)

    if (st.errorTimer or 0) > 0 then
        UI.label(st.error or "", x + 8, y + h - 30, Palette.danger, Assets.fonts.small)
    end
    UI.label("UP/DOWN pick   USE buy", x + 8, y + h - 17, Palette.ink_dim, Assets.fonts.tiny)
end

-- Draws the readout for a mounted station into the given rect.
function Stations.drawPanel(st, x, y, w, h)
    local where = st.room and st.room.name or nil
    local title = (where and where ~= st.label) and (st.label .. "  --  " .. where) or st.label
    UI.panel(x, y, w, h, title, st.accent)
    if st.module and Ship.isOffline(st.module) then
        UI.static(x + 8, y + 20, w - 16, h - 28, "STATION OFFLINE\nTHIS BAY IS BREACHED", Palette.danger)
        return
    end
    local fn = panels[st.kind]
    if fn then fn(st, x, y, w, h) end
end

Stations.TURRET_ARC = TURRET_ARC
Stations.fabItems = fabItems

return Stations
