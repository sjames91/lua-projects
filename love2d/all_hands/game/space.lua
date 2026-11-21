-- The world outside the hull.
--
-- Deliberately a separate simulation from the interior: the interior floor plan
-- never rotates, the hull out here does. That split is what makes the "only the
-- bridge can see" rule work -- the exterior is information, and information has
-- to be carried by somebody's voice.

local State   = require("game/state")
local Palette = require("game/palette")
local Ship    = require("game/ship")

local Space = {}

Space.SLOT_PX = 30          -- exterior px per hull slot
local DRAG     = 0.992
local THRUST   = 235         -- px/s^2 at full engine output and full power
local TURN     = 1.55        -- rad/s at full engine output and full power

local function norm(a)
    return ((a + math.pi) % (2 * math.pi)) - math.pi
end
Space.norm = norm

--------------------------------------------------------------------------------
-- hull geometry (local space: +x is forward, origin is the centroid)
--------------------------------------------------------------------------------

function Space.hullOffset()
    return State.ship.maxSlot * Space.SLOT_PX / 2
end

function Space.moduleLocal(m)
    local lx = Space.hullOffset() - m.slot * Space.SLOT_PX
    local ly = (m.side == "top") and -17 or 17
    return lx, ly
end

function Space.spineLocal(slot)
    return Space.hullOffset() - slot * Space.SLOT_PX, 0
end

function Space.hullRadius()
    return Space.hullOffset() + 30
end

function Space.toWorld(lx, ly)
    local s = State.space
    local c, si = math.cos(s.angle), math.sin(s.angle)
    return s.x + lx * c - ly * si, s.y + lx * si + ly * c
end

--------------------------------------------------------------------------------
-- spawning
--------------------------------------------------------------------------------

local ENEMY_KINDS = {
    raider = {
        sprite = "raider", hp = 34, radius = 13, speed = 112, standoff = 250,
        range = 430, cooldown = 1.5, dmg = 7, bolt = 330, scrap = 13,
    },
    gunship = {
        sprite = "gunship", hp = 95, radius = 18, speed = 68, standoff = 430,
        range = 620, cooldown = 2.3, dmg = 16, bolt = 290, scrap = 32, burst = 3,
    },
}
Space.ENEMY_KINDS = ENEMY_KINDS

function Space.spawnEnemy(kind)
    local def = ENEMY_KINDS[kind]
    local s = State.space
    local a = love.math.random() * math.pi * 2
    local d = 900 + love.math.random() * 400
    local e = {
        kind = kind, def = def,
        x = s.x + math.cos(a) * d,
        y = s.y + math.sin(a) * d,
        vx = 0, vy = 0,
        angle = a + math.pi,
        hp = def.hp, maxhp = def.hp,
        fireTimer = 1 + love.math.random() * 2,
        burstLeft = 0, burstTimer = 0,
        strafe = (love.math.random() < 0.5) and 1 or -1,
        wobble = love.math.random() * 6.28,
    }
    table.insert(s.enemies, e)
    return e
end

function Space.spawnRock()
    local s = State.space
    local a = love.math.random() * math.pi * 2
    local d = 1100 + love.math.random() * 600
    table.insert(s.rocks, {
        x = s.x + math.cos(a) * d,
        y = s.y + math.sin(a) * d,
        vx = (love.math.random() - 0.5) * 30,
        vy = (love.math.random() - 0.5) * 30,
        spin = (love.math.random() - 0.5) * 0.7,
        angle = love.math.random() * 6.28,
        sprite = "rock" .. love.math.random(4),
        radius = 14 + love.math.random() * 16,
        hp = 30,
    })
end

function Space.fx(kind, x, y, size, colour)
    table.insert(State.space.fx, {
        kind = kind, x = x, y = y, size = size or 12,
        t = 0, life = (kind == "boom") and 0.55 or 0.18,
        colour = colour or Palette.warn,
    })
end

--------------------------------------------------------------------------------
-- firing
--------------------------------------------------------------------------------

function Space.fireTurret(m)
    local s = State.space
    if Ship.isOffline(m) then return false end
    local cost = (m.mode == "burst") and 0.95 or 0.42
    if (m.charge or 0) < cost then return false end
    m.charge = m.charge - cost

    local shots = (m.mode == "burst") and 3 or 1
    local lx, ly = Space.moduleLocal(m)
    local wx, wy = Space.toWorld(lx, ly)
    local base = s.angle + m.turret

    for i = 1, shots do
        local spread = (shots > 1) and ((i - 2) * 0.055) or 0
        local a = base + spread
        local dmg = (m.mode == "burst") and 7 or 13
        table.insert(s.bolts, {
            x = wx, y = wy,
            vx = math.cos(a) * 760 + s.vx,
            vy = math.sin(a) * 760 + s.vy,
            angle = a, life = 1.5, dmg = dmg, friendly = true,
        })
    end
    Space.fx("flash", wx, wy, 10, Palette.sys_weapons)
    return true
end

local function enemyFire(e)
    local s = State.space
    local a = math.atan2(s.y - e.y, s.x - e.x)
    -- lead the target a little so standing still is not safe
    local d = math.sqrt((s.x - e.x) ^ 2 + (s.y - e.y) ^ 2)
    local t = d / e.def.bolt
    local px, py = s.x + s.vx * t * 0.8, s.y + s.vy * t * 0.8
    a = math.atan2(py - e.y, px - e.x) + (love.math.random() - 0.5) * 0.07
    table.insert(s.bolts, {
        x = e.x, y = e.y,
        vx = math.cos(a) * e.def.bolt,
        vy = math.sin(a) * e.def.bolt,
        angle = a, life = 4, dmg = e.def.dmg, friendly = false,
    })
    Space.fx("flash", e.x, e.y, 8, Palette.danger)
end

--------------------------------------------------------------------------------
-- waves
--------------------------------------------------------------------------------

function Space.startWave()
    State.wave = State.wave + 1
    State.phase = "combat"
    local n = 1 + State.wave
    for _ = 1, n do
        Space.spawnEnemy("raider")
    end
    if State.wave >= 3 then
        for _ = 1, math.floor(State.wave / 3) do
            Space.spawnEnemy("gunship")
        end
    end
    State.say("WAVE " .. State.wave .. " INBOUND - " .. #State.space.enemies .. " CONTACTS", Palette.danger)
    State.showBanner("WAVE " .. State.wave, 2.0)
end

local function endWave()
    State.phase = "lull"
    State.phaseTimer = 34
    local bonus = 22 + State.wave * 6
    State.scrap = State.scrap + bonus
    State.say("AREA CLEAR - salvaged " .. bonus .. " scrap", Palette.good)
    State.showBanner("AREA CLEAR\n+" .. bonus .. " scrap  --  refit at the FABRICATOR", 3.2)
end

function Space.reset()
    local s = State.space
    s.x, s.y, s.angle = 0, 0, 0
    s.vx, s.vy = 0, 0
    s.throttle = 0
    s.turnInput = 0
    s.enemies, s.bolts, s.rocks, s.fx = {}, {}, {}, {}
    for _ = 1, 14 do Space.spawnRock() end
    State.wave = 0
    State.phase = "lull"
    State.phaseTimer = 34
end

--------------------------------------------------------------------------------
-- update
--------------------------------------------------------------------------------

function Space.update(dt)
    local s = State.space
    local ship = State.ship

    local enginePower = ship.power.engines / 5
    local eOut = Ship.engineOutput()
    local mass = Ship.massFactor()

    -- helm steering, scaled by what engineering gave the engines
    local turnRate = TURN * (0.25 + 0.75 * enginePower) * math.min(1.6, eOut) / mass
    s.angle = s.angle + s.turnInput * turnRate * dt
    s.turnInput = 0

    local thrust = THRUST * (0.22 + 0.78 * enginePower) * eOut / mass
    s.vx = s.vx + math.cos(s.angle) * thrust * s.throttle * dt
    s.vy = s.vy + math.sin(s.angle) * thrust * s.throttle * dt

    local drag = math.pow(DRAG, dt * 60)
    s.vx, s.vy = s.vx * drag, s.vy * drag
    s.x = s.x + s.vx * dt
    s.y = s.y + s.vy * dt

    local hullR = Space.hullRadius()

    -- bolts
    for i = #s.bolts, 1, -1 do
        local b = s.bolts[i]
        b.x = b.x + b.vx * dt
        b.y = b.y + b.vy * dt
        b.life = b.life - dt
        local dead = b.life <= 0

        if not dead and b.friendly then
            for _, e in ipairs(s.enemies) do
                if e.hp > 0 then
                    local dx, dy = b.x - e.x, b.y - e.y
                    if dx * dx + dy * dy < (e.def.radius + 6) ^ 2 then
                        e.hp = e.hp - b.dmg
                        e.hitTimer = 0.12
                        Space.fx("flash", b.x, b.y, 12, Palette.warn)
                        dead = true
                        break
                    end
                end
            end
            if not dead then
                for _, r in ipairs(s.rocks) do
                    local dx, dy = b.x - r.x, b.y - r.y
                    if dx * dx + dy * dy < r.radius ^ 2 then
                        r.hp = r.hp - b.dmg
                        Space.fx("flash", b.x, b.y, 10, Palette.hull_light)
                        dead = true
                        break
                    end
                end
            end
        elseif not dead then
            local dx, dy = b.x - s.x, b.y - s.y
            if dx * dx + dy * dy < (hullR * 0.72) ^ 2 then
                local impact = norm(math.atan2(dy, dx) - s.angle)
                Ship.damageHull(b.dmg, impact)
                Space.fx("flash", b.x, b.y, 16, Palette.sys_shields)
                dead = true
            end
        end

        if dead then table.remove(s.bolts, i) end
    end

    -- enemies
    for i = #s.enemies, 1, -1 do
        local e = s.enemies[i]
        e.hitTimer = math.max(0, (e.hitTimer or 0) - dt)

        if e.hp <= 0 then
            Space.fx("boom", e.x, e.y, e.def.radius * 2.6)
            State.scrap = State.scrap + e.def.scrap
            State.kills = State.kills + 1
            State.say(e.kind:upper() .. " DESTROYED  +" .. e.def.scrap .. " scrap", Palette.good)
            table.remove(s.enemies, i)
        else
            local dx, dy = s.x - e.x, s.y - e.y
            local d = math.max(1, math.sqrt(dx * dx + dy * dy))
            local tx, ty = dx / d, dy / d
            e.wobble = e.wobble + dt * 1.3

            local ax, ay
            if d > e.def.standoff * 1.15 then
                ax, ay = tx, ty
            elseif d < e.def.standoff * 0.75 then
                ax, ay = -tx, -ty
            else
                ax, ay = -ty * e.strafe, tx * e.strafe
            end
            ax = ax + math.cos(e.wobble) * 0.25
            ay = ay + math.sin(e.wobble * 1.3) * 0.25

            local acc = e.def.speed * 1.6
            e.vx = e.vx + ax * acc * dt
            e.vy = e.vy + ay * acc * dt
            local sp = math.sqrt(e.vx * e.vx + e.vy * e.vy)
            if sp > e.def.speed then
                e.vx, e.vy = e.vx / sp * e.def.speed, e.vy / sp * e.def.speed
            end
            e.x = e.x + e.vx * dt
            e.y = e.y + e.vy * dt
            e.angle = norm(e.angle + norm(math.atan2(ty, tx) - e.angle) * math.min(1, dt * 4))

            -- firing
            if e.burstLeft > 0 then
                e.burstTimer = e.burstTimer - dt
                if e.burstTimer <= 0 then
                    enemyFire(e)
                    e.burstLeft = e.burstLeft - 1
                    e.burstTimer = 0.13
                end
            else
                e.fireTimer = e.fireTimer - dt
                if e.fireTimer <= 0 and d < e.def.range then
                    e.fireTimer = e.def.cooldown * (0.8 + love.math.random() * 0.5)
                    if e.def.burst then
                        e.burstLeft = e.def.burst
                        e.burstTimer = 0
                    else
                        enemyFire(e)
                    end
                end
            end

            -- ramming
            if d < hullR * 0.6 + e.def.radius then
                Ship.damageHull(6, norm(math.atan2(-dy, -dx) - s.angle))
                e.hp = e.hp - 14
                e.vx, e.vy = -tx * 180, -ty * 180
            end
        end
    end

    -- rocks
    for i = #s.rocks, 1, -1 do
        local r = s.rocks[i]
        r.x = r.x + r.vx * dt
        r.y = r.y + r.vy * dt
        r.angle = r.angle + r.spin * dt
        local dx, dy = r.x - s.x, r.y - s.y
        local d2 = dx * dx + dy * dy
        if r.hp <= 0 then
            Space.fx("boom", r.x, r.y, r.radius * 2)
            State.scrap = State.scrap + 4
            table.remove(s.rocks, i)
        elseif d2 < (hullR * 0.75 + r.radius) ^ 2 then
            Ship.damageHull(10, norm(math.atan2(dy, dx) - s.angle))
            Space.fx("boom", r.x, r.y, r.radius * 2)
            table.remove(s.rocks, i)
        elseif d2 > 2600 * 2600 then
            table.remove(s.rocks, i)
            Space.spawnRock()
        end
    end
    while #s.rocks < 10 do Space.spawnRock() end

    -- fx
    for i = #s.fx, 1, -1 do
        local f = s.fx[i]
        f.t = f.t + dt
        if f.t >= f.life then table.remove(s.fx, i) end
    end

    -- wave flow
    if State.phase == "combat" then
        if #s.enemies == 0 then endWave() end
    elseif State.phase == "lull" then
        State.phaseTimer = State.phaseTimer - dt
        if State.phaseTimer <= 0 then Space.startWave() end
    end

    -- drop the bridge's target designation if it dies
    if ship.designated then
        local alive = false
        for _, e in ipairs(s.enemies) do
            if e == ship.designated then alive = true; break end
        end
        if not alive then ship.designated = nil end
    end
end

--------------------------------------------------------------------------------
-- readouts the stations ask for
--------------------------------------------------------------------------------

-- Relative bearing in degrees, naval style: 0 is dead ahead, 90 is starboard.
function Space.relBearing(x, y)
    local s = State.space
    local a = norm(math.atan2(y - s.y, x - s.x) - s.angle)
    local deg = math.deg(a)
    if deg < 0 then deg = deg + 360 end
    return deg
end

function Space.rangeTo(x, y)
    local s = State.space
    return math.sqrt((x - s.x) ^ 2 + (y - s.y) ^ 2)
end

function Space.contacts()
    local out = {}
    local range = State.ship.radarRange or 900
    for _, e in ipairs(State.space.enemies) do
        local d = Space.rangeTo(e.x, e.y)
        if d <= range then
            table.insert(out, { enemy = e, range = d, bearing = Space.relBearing(e.x, e.y) })
        end
    end
    table.sort(out, function(a, b) return a.range < b.range end)
    return out
end

function Space.speed()
    local s = State.space
    return math.sqrt(s.vx * s.vx + s.vy * s.vy)
end

function Space.headingDeg()
    local d = math.deg(State.space.angle) % 360
    return d
end

return Space
