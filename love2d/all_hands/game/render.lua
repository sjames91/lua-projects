-- Four-way split screen.
--
-- Each viewport belongs to one crew member and shows only what that crew member
-- can actually see: the inside of the ship, plus their own console readout. The
-- exterior view exists in exactly one place -- the bridge console -- so if
-- nobody is on the bridge, nobody on the couch knows what is out there.

local State    = require("game/state")
local Palette  = require("game/palette")
local Assets   = require("game/assets")
local Ship     = require("game/ship")
local Space    = require("game/space")
local Stations = require("game/stations")
local Players  = require("game/players")
local Input    = require("game/input")
local UI       = require("game/ui")

local Render = {}

local lg = love.graphics
local T = State.TILE

local STRIP_H = 22
local PANEL_H = 148

Render.showHelp = true

--------------------------------------------------------------------------------
-- one-off textures
--------------------------------------------------------------------------------

local vignette

function Render.load()
    local d = love.image.newImageData(64, 64)
    d:mapPixel(function(x, y)
        local dx = (x - 31.5) / 31.5
        local dy = (y - 31.5) / 31.5
        local r = math.min(1, math.sqrt(dx * dx + dy * dy) / 1.414)
        local a = math.max(0, (r - 0.42) / 0.58) ^ 1.7
        return 0, 0, 0, a * 0.85
    end)
    vignette = lg.newImage(d)
    vignette:setFilter("linear", "linear")
end

--------------------------------------------------------------------------------
-- interior
--------------------------------------------------------------------------------

local function shakeAmount()
    local t = State.ship.shieldHitTimer
    if t <= 0 then return 0, 0 end
    local m = t * 14
    return (love.math.random() - 0.5) * m, (love.math.random() - 0.5) * m
end

local function drawTiles(view)
    local s = State.ship
    local tx0 = math.floor(Camera.x / T) - 1
    local ty0 = math.floor(Camera.y / T) - 1
    local tx1 = math.ceil((Camera.x + view.w) / T) + 1
    local ty1 = math.ceil((Camera.y + view.h) / T) + 1

    lg.setColor(1, 1, 1, 1)
    for ty = ty0, ty1 do
        local row = s.grid[ty]
        if row then
            for tx = tx0, tx1 do
                local v = row[tx]
                if v == 1 then
                    local mat = (s.mat[ty] and s.mat[ty][tx]) or "deck"
                    lg.draw(Assets.images[mat] or Assets.images.deck, tx * T, ty * T)
                elseif v == 2 then
                    lg.draw(Assets.images.hull, tx * T, ty * T)
                end
            end
        end
    end
end

local function drawDeckDecals()
    local s = State.ship
    -- bay name stencilled on the deck
    lg.setFont(Assets.fonts.label)
    for _, r in ipairs(s.rooms) do
        if r.kind ~= "corridor" then
            local accent = Palette.station[Ship.KINDS[r.kind].station] or Palette.ink
            lg.setColor(accent[1], accent[2], accent[3], 0.13)
            lg.printf(r.name, r.px, r.py + r.ph * 0.42, r.pw, "center")
        end
    end
    -- "fore" chevrons down the spine, pointing at slot 0
    local cy = (State.ROW_COR_0 + 1.5) * T
    lg.setColor(1, 1, 1, 0.07)
    for i = 0, s.maxSlot * 2 + 1 do
        local x = 24 + i * 112
        lg.setLineWidth(5)
        lg.line(x + 14, cy - 11, x, cy, x + 14, cy + 11)
    end
    lg.setFont(Assets.fonts.tiny)
    lg.setColor(1, 1, 1, 0.14)
    lg.print("FORE", 10, cy + 20)
    lg.setColor(1, 1, 1, 1)
end

local function drawRoomStatus()
    for _, r in ipairs(State.ship.rooms) do
        local m = r.module
        if m then
            local frac = m.hp / m.maxhp
            if frac < 1 then
                -- scorching gets worse as the bay degrades
                local a = (1 - frac) * 0.4
                lg.setColor(0.6, 0.1, 0.08, a)
                lg.rectangle("fill", r.px, r.py, r.pw, r.ph)
            end
            if frac <= 0 then
                lg.setColor(0, 0, 0, 0.55)
                lg.rectangle("fill", r.px, r.py, r.pw, r.ph)
                lg.setFont(Assets.fonts.label)
                local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 6)
                lg.setColor(1, 0.25, 0.3, 0.5 + 0.5 * pulse)
                lg.printf("BREACHED", r.px, r.py + r.ph / 2 - 12, r.pw, "center")
            end
            if frac < 0.8 then
                -- sparks
                lg.setColor(1, 0.8, 0.35, 0.8)
                local n = math.floor((1 - frac) * 6) + 1
                for i = 1, n do
                    local sx = r.px + 10 + love.math.random() * (r.pw - 20)
                    local sy = r.py + 10 + love.math.random() * (r.ph - 20)
                    lg.circle("fill", sx, sy, love.math.random() * 1.8 + 0.5)
                end
            end
        end
    end
    lg.setColor(1, 1, 1, 1)
end

local function drawConsoles(localPlayer)
    local near = localPlayer and not localPlayer.station and Ship.stationFor(localPlayer) or nil
    local img = Assets.images.console

    for _, st in ipairs(State.ship.stations) do
        local flip = (st.facing == "up")
        local sy = flip and -1 or 1
        local oy = flip and (st.py + st.h) or st.py
        lg.setColor(1, 1, 1, 1)
        lg.draw(img, st.px, oy, 0, st.w / img:getWidth(), sy)

        -- lit screen
        local offline = st.module and Ship.isOffline(st.module)
        local a = st.accent
        local lit = offline and 0.12 or (st.occupant and 1.0 or 0.45)
        local pulse = st.occupant and (0.85 + 0.15 * math.sin(st.blink * 6)) or 1
        lg.setColor(a[1], a[2], a[3], 0.55 * lit * pulse)
        local sx0 = st.px + 6
        local sy0 = st.py + (flip and 5 or 4)
        lg.rectangle("fill", sx0, sy0, st.w - 12, 11, 2)

        UI.glyph(st.kind, st.px + st.w / 2, st.py + st.h / 2, 7,
            offline and Palette.danger or a)

        -- occupant tag
        if st.occupant then
            local c = Palette.crew[st.occupant.index].suit
            lg.setColor(c[1], c[2], c[3], 1)
            lg.circle("fill", st.px + st.w - 6, st.py + st.h / 2, 3)
        end

        -- "press USE" prompt for the player whose viewport this is
        if st == near then
            local py = flip and (st.py - 20) or (st.py + st.h + 6)
            local pulse2 = 0.6 + 0.4 * math.sin(love.timer.getTime() * 7)
            lg.setColor(1, 1, 1, pulse2)
            lg.setFont(Assets.fonts.tiny)
            local label = st.label
            local tw = Assets.fonts.tiny:getWidth(label) + 10
            lg.setColor(0, 0, 0, 0.7)
            lg.rectangle("fill", st.cx - tw / 2, py, tw, 13, 3)
            lg.setColor(a[1], a[2], a[3], pulse2)
            lg.printf(label, st.cx - tw / 2, py + 1, tw, "center")
        end
    end
    lg.setColor(1, 1, 1, 1)
end

local function drawInterior(view, p)
    lg.setScissor(view.x, view.y, view.w, view.h)
    Palette.set(Palette.void)
    lg.rectangle("fill", view.x, view.y, view.w, view.h)

    Camera.x = p.x - view.w / 2
    Camera.y = p.y - view.h / 2

    local sx, sy = shakeAmount()

    lg.push()
    lg.translate(view.x + sx, view.y + sy)

    lg.push()
    lg.translate(-math.floor(Camera.x), -math.floor(Camera.y))
    drawTiles(view)
    drawDeckDecals()
    drawConsoles(p)
    drawRoomStatus()
    lg.pop()

    -- crew are engine sprites, so the engine draws them (and applies Camera)
    Chispita.draw()

    lg.pop()

    -- lighting: vignette plus a red-alert wash as the hull goes
    lg.setColor(1, 1, 1, 1)
    lg.draw(vignette, view.x, view.y, 0, view.w / 64, view.h / 64)
    local frac = State.ship.hull / State.ship.maxHull
    if frac < 0.6 then
        local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 3.5)
        lg.setColor(0.8, 0.08, 0.12, math.min(0.26, (0.6 - frac) * 0.4) * (0.55 + pulse * 0.45))
        lg.rectangle("fill", view.x, view.y, view.w, view.h)
    end
    -- plan view in the corner so a crew member can find a newly built bay
    local mw, mh = math.min(168, view.w * 0.3), 52
    local mx, my = view.x + view.w - mw - 6, view.y + 6
    lg.setColor(0, 0, 0, 0.55)
    lg.rectangle("fill", mx - 4, my - 4, mw + 8, mh + 8, 3)
    Render.miniPlan(mx, my, mw, mh, p, false)

    lg.setScissor()
end

--------------------------------------------------------------------------------
-- exterior / tactical (bridge only)
--------------------------------------------------------------------------------

local function drawStars(view)
    local s = State.space
    for layer, pts in ipairs(Assets.stars) do
        local pf = 0.06 * layer
        local a = 0.3 + layer * 0.22
        for _, st in ipairs(pts) do
            local x = (st.x - s.x * pf) % view.w
            local y = (st.y - s.y * pf) % view.h
            lg.setColor(0.75, 0.82, 1.0, a * st.b)
            lg.rectangle("fill", view.x + x, view.y + y, st.s, st.s)
        end
    end
    lg.setColor(1, 1, 1, 1)
end

local function drawHull()
    local s = State.space
    local sh = State.ship
    local off = Space.hullOffset()

    lg.push()
    lg.translate(s.x, s.y)
    lg.rotate(s.angle)

    -- engine exhaust (drawn under the hull)
    local eOut = Ship.engineOutput()
    local flame = s.throttle * (14 + eOut * 16)
    if flame > 1 then
        local nozzles = { { -off - 12, 0, 1.25 } }
        for _, m in ipairs(Ship.modulesOfKind("engine")) do
            local lx, ly = Space.moduleLocal(m)
            table.insert(nozzles, { lx - 14, ly, m.overdrive and 1.5 or 1.0 })
        end
        lg.setBlendMode("add")
        for _, n in ipairs(nozzles) do
            local f = flame * n[3] * (0.85 + 0.15 * math.sin(love.timer.getTime() * 30))
            lg.setColor(1, 0.55, 0.2, 0.55)
            lg.polygon("fill", n[1], n[2] - 7, n[1], n[2] + 7, n[1] - f, n[2])
            lg.setColor(1, 0.95, 0.7, 0.7)
            lg.polygon("fill", n[1], n[2] - 3.5, n[1], n[2] + 3.5, n[1] - f * 0.55, n[2])
        end
        lg.setBlendMode("alpha")
    end

    -- spine
    local len = sh.maxSlot * Space.SLOT_PX + 30
    Palette.set(Palette.hull)
    lg.rectangle("fill", -off - 12, -11, len + 12, 22, 3)
    Palette.set(Palette.hull_dark)
    lg.setLineWidth(1.5)
    lg.rectangle("line", -off - 12, -11, len + 12, 22, 3)

    -- nose
    Palette.set(Palette.hull_light)
    lg.polygon("fill", off + 6, -11, off + 32, 0, off + 6, 11)
    Palette.set(Palette.hull_dark)
    lg.polygon("line", off + 6, -11, off + 32, 0, off + 6, 11)

    -- module blisters
    for _, m in ipairs(sh.modules) do
        local lx, ly = Space.moduleLocal(m)
        local frac = m.hp / m.maxhp
        local base = Palette.mix(Palette.hull_dark, Palette.hull, 0.35 + 0.65 * frac)
        local x0 = lx - 12
        local y0 = (m.side == "top") and (ly - 11) or (ly - 11)
        Palette.set(base)
        lg.rectangle("fill", x0, y0, 24, 22, 3)
        -- station accent stripe on the outboard face
        local a = Palette.station[Ship.KINDS[m.kind].station] or Palette.ink
        lg.setColor(a[1], a[2], a[3], 0.55 * (0.3 + 0.7 * frac))
        if m.side == "top" then
            lg.rectangle("fill", x0 + 3, y0 + 1, 18, 3)
        else
            lg.rectangle("fill", x0 + 3, y0 + 18, 18, 3)
        end
        Palette.set(Palette.hull_dark)
        lg.setLineWidth(1)
        lg.rectangle("line", x0, y0, 24, 22, 3)
        if frac <= 0 then
            local pulse = 0.4 + 0.6 * math.abs(math.sin(love.timer.getTime() * 5))
            lg.setColor(1, 0.3, 0.2, 0.55 * pulse)
            lg.rectangle("fill", x0, y0, 24, 22, 3)
        end
        -- turret barrels
        if m.kind == "weapons" then
            Palette.set(Palette.hull_light)
            lg.circle("fill", lx, ly, 6)
            Palette.set(Palette.sys_weapons)
            lg.setLineWidth(3)
            lg.line(lx, ly, lx + math.cos(m.turret) * 20, ly + math.sin(m.turret) * 20)
        end
    end

    -- shield arc, defined relative to the hull, which is why the facing matters
    if sh.maxShield > 0 and sh.shield > 0.5 then
        local r = Space.hullRadius()
        local arc = (sh.shieldArc or math.rad(55)) * ((sh.braceTimer > 0) and 1.5 or 1)
        local strength = sh.shield / sh.maxShield
        local hit = sh.shieldHitTimer > 0 and 0.35 or 0
        UI.wedge(0, 0, r * 0.88, r * 1.06, sh.shieldAngle, arc,
            Palette.sys_shields, 0.2 + 0.4 * strength + hit)
        lg.setColor(0.3, 0.72, 1, 0.12 + 0.1 * strength)
        lg.setLineWidth(1.5)
        lg.circle("line", 0, 0, r * 0.97)
    end

    lg.pop()
end

local function drawTactical(view, st)
    lg.setScissor(view.x, view.y, view.w, view.h)
    Palette.set(Palette.void)
    lg.rectangle("fill", view.x, view.y, view.w, view.h)
    drawStars(view)

    local s = State.space
    local zoom = st.zoom or 0.34
    local cx, cy = view.x + view.w / 2, view.y + view.h / 2
    local shx, shy = shakeAmount()

    local function w2s(wx, wy)
        return cx + (wx - s.x) * zoom + shx, cy + (wy - s.y) * zoom + shy
    end

    lg.push()
    lg.translate(cx + shx, cy + shy)
    lg.scale(zoom)
    lg.translate(-s.x, -s.y)

    -- range rings + bearing ticks, the bridge's measuring instrument
    lg.setLineWidth(1 / zoom)
    for _, r in ipairs({ 300, 600, 1000, 1500 }) do
        Palette.set(Palette.screen_grid, 0.75)
        lg.circle("line", s.x, s.y, r)
    end
    for i = 0, 11 do
        local a = s.angle + i * math.pi / 6
        Palette.set(Palette.screen_grid, 0.6)
        lg.line(s.x + math.cos(a) * 1480, s.y + math.sin(a) * 1480,
                s.x + math.cos(a) * 1520, s.y + math.sin(a) * 1520)
    end
    -- heading line
    Palette.set(Palette.ink_dim, 0.5)
    lg.line(s.x, s.y, s.x + math.cos(s.angle) * 1500, s.y + math.sin(s.angle) * 1500)

    -- sensor horizon: the bridge only sees contacts inside it, which is the
    -- whole reason to spend scrap on a SENSOR ARRAY
    local radar = State.ship.radarRange or 900
    Palette.set(Palette.sys_sensors, 0.5)
    lg.setLineWidth(2 / zoom)
    local segs = 72
    for i = 0, segs - 1, 2 do
        local a0 = i / segs * math.pi * 2
        local a1 = (i + 1) / segs * math.pi * 2
        lg.line(s.x + math.cos(a0) * radar, s.y + math.sin(a0) * radar,
                s.x + math.cos(a1) * radar, s.y + math.sin(a1) * radar)
    end

    -- rocks
    lg.setColor(1, 1, 1, 1)
    for _, r in ipairs(s.rocks) do
        local img = Assets.images[r.sprite]
        local sc = r.radius * 2 / img:getWidth()
        lg.draw(img, r.x, r.y, r.angle, sc, sc, img:getWidth() / 2, img:getHeight() / 2)
    end

    drawHull()

    -- enemies, but only the ones inside the sensor horizon
    for _, e in ipairs(s.enemies) do
      local dist = Space.rangeTo(e.x, e.y)
      if dist <= radar then
        local img = Assets.images[e.def.sprite]
        local sc = e.def.radius * 2.4 / img:getWidth()
        if e.hitTimer and e.hitTimer > 0 then
            lg.setColor(1, 0.8, 0.8, 1)
        else
            lg.setColor(1, 1, 1, 1)
        end
        lg.draw(img, e.x, e.y, e.angle, sc, sc, img:getWidth() / 2, img:getHeight() / 2)
        -- health pip
        local frac = e.hp / e.maxhp
        lg.setColor(0, 0, 0, 0.6)
        lg.rectangle("fill", e.x - 16, e.y - e.def.radius - 12, 32, 4)
        lg.setColor(1 - frac * 0.7, frac, 0.3, 1)
        lg.rectangle("fill", e.x - 16, e.y - e.def.radius - 12, 32 * frac, 4)
      end
    end

    -- bolts
    lg.setBlendMode("add")
    for _, b in ipairs(s.bolts) do
        local img = Assets.images[b.friendly and "bolt_ally" or "bolt_enemy"]
        lg.setColor(1, 1, 1, 1)
        lg.draw(img, b.x, b.y, b.angle, 2.4, 2.0, img:getWidth() / 2, img:getHeight() / 2)
    end
    -- fx
    for _, f in ipairs(s.fx) do
        local t = f.t / f.life
        if f.kind == "flash" then
            lg.setColor(f.colour[1], f.colour[2], f.colour[3], (1 - t) * 0.9)
            lg.circle("fill", f.x, f.y, f.size * (0.5 + t))
        else
            lg.setColor(1, 0.7, 0.3, (1 - t) * 0.8)
            lg.circle("fill", f.x, f.y, f.size * (0.3 + t * 0.9))
            lg.setColor(1, 1, 0.8, (1 - t) * 0.6)
            lg.setLineWidth(3 / zoom)
            lg.circle("line", f.x, f.y, f.size * (0.4 + t * 1.5))
        end
    end
    lg.setBlendMode("alpha")

    lg.pop()

    -- Contact markers live in screen space so a ship stays findable however
    -- far the bridge zooms out -- the sprite alone is a few pixels at WIDE.
    lg.setFont(Assets.fonts.tiny)
    for _, e in ipairs(s.enemies) do
        if Space.rangeTo(e.x, e.y) <= radar then
            local px, py = w2s(e.x, e.y)
            local marked = (e == State.ship.designated)
            local c = marked and Palette.ink or Palette.danger
            lg.setColor(c[1], c[2], c[3], marked and 1 or 0.8)
            lg.setLineWidth(marked and 2 or 1.5)
            local r = marked and 20 or 14
            if marked then
                for _, sg in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
                    lg.line(px + sg[1] * r, py + sg[2] * r, px + sg[1] * r * 0.4, py + sg[2] * r)
                    lg.line(px + sg[1] * r, py + sg[2] * r, px + sg[1] * r, py + sg[2] * r * 0.4)
                end
                lg.print(("%03d / %d"):format(Space.relBearing(e.x, e.y), Space.rangeTo(e.x, e.y)),
                    px + r + 3, py - 6)
            else
                lg.circle("line", px, py, r)
            end
        end
    end
    lg.setColor(1, 1, 1, 1)

    -- bearing numerals around the outer ring, unscaled so they stay readable
    lg.setFont(Assets.fonts.tiny)
    for i = 0, 11 do
        local deg = i * 30
        local a = s.angle + math.rad(deg)
        local wx, wy = s.x + math.cos(a) * 1560, s.y + math.sin(a) * 1560
        local px, py = w2s(wx, wy)
        if px > view.x + 6 and px < view.x + view.w - 24 and py > view.y + 6 and py < view.y + view.h - 14 then
            Palette.set(Palette.ink_dim)
            lg.print(("%03d"):format(deg), px - 9, py - 5)
        end
    end
    lg.setColor(1, 1, 1, 1)

    --------------------------------------------------------------------------
    -- bridge chrome
    --------------------------------------------------------------------------
    local sh = State.ship
    lg.setColor(0, 0, 0, 0.55)
    lg.rectangle("fill", view.x, view.y, view.w, 44)
    lg.rectangle("fill", view.x, view.y + view.h - 56, view.w, 56)

    UI.bar(view.x + 8, view.y + 8, 170, 14, sh.hull / sh.maxHull,
        sh.hull / sh.maxHull > 0.35 and Palette.good or Palette.danger, "HULL",
        ("%d"):format(math.floor(sh.hull)))
    if sh.maxShield > 0 then
        UI.bar(view.x + 8, view.y + 24, 170, 14, sh.shield / sh.maxShield,
            Palette.sys_shields, "SHLD", ("%d"):format(math.floor(sh.shield)))
    else
        UI.bar(view.x + 8, view.y + 24, 170, 14, 0, Palette.ink_dim, "SHLD", "NONE")
    end

    UI.label(("HDG %03d"):format(math.floor(Space.headingDeg())), view.x + 190, view.y + 8, Palette.ink)
    UI.label(("SPD %3d"):format(math.floor(Space.speed())), view.x + 190, view.y + 24, Palette.ink_dim)
    UI.label(("CONTACTS %d"):format(#Space.contacts()), view.x + 262, view.y + 8,
        #s.enemies > 0 and Palette.danger or Palette.ink_dim)
    UI.label(("ZOOM %s"):format(zoom > 0.4 and "NEAR" or "WIDE"), view.x + 262, view.y + 24, Palette.ink_dim)

    -- the single most important readout in the game: what to shout
    local des = sh.designated
    local by = view.y + view.h - 50
    if des then
        lg.setFont(Assets.fonts.big)
        Palette.set(Palette.ink)
        lg.print(("MARK  BRG %03d   RNG %d"):format(
            math.floor(Space.relBearing(des.x, des.y)),
            math.floor(Space.rangeTo(des.x, des.y))), view.x + 10, by)
        UI.label("READ THAT BEARING OUT LOUD - the gunners cannot see it",
            view.x + 12, by + 34, Palette.warn, Assets.fonts.tiny)
    else
        lg.setFont(Assets.fonts.big)
        Palette.set(Palette.ink_dim)
        lg.print("NO MARK", view.x + 10, by)
        UI.label("LEFT/RIGHT designate a contact   USE change zoom",
            view.x + 12, by + 34, Palette.ink_dim, Assets.fonts.tiny)
    end

    lg.setScissor()
end

--------------------------------------------------------------------------------
-- ship floor plan
--------------------------------------------------------------------------------

-- Interior layout is public knowledge -- what is hidden in this game is the
-- world outside -- so a plan view costs nothing and makes a twelve-bay ship
-- navigable. Shows where every bay is and which of them are manned.
function Render.miniPlan(x, y, w, h, forPlayer, labels)
    local s = State.ship
    local b = s.bounds
    local tw, th = (b.x1 - b.x0 + 1), (b.y1 - b.y0 + 1)
    local sc = math.min(w / tw, h / th)
    local ox = x + (w - tw * sc) / 2 - b.x0 * sc
    local oy = y + (h - th * sc) / 2 - b.y0 * sc

    local function rect(room, col, alpha)
        lg.setColor(col[1], col[2], col[3], alpha)
        lg.rectangle("fill", ox + room.x0 * sc, oy + room.y0 * sc,
            (room.x1 - room.x0 + 1) * sc, (room.y1 - room.y0 + 1) * sc)
    end

    rect(s.corridor, Palette.hull, 0.35)
    for _, r in ipairs(s.rooms) do
        if r.kind ~= "corridor" then
            local st = Ship.KINDS[r.kind].station
            local accent = Palette.station[st] or Palette.ink
            local frac = r.module and (r.module.hp / r.module.maxhp) or 1
            rect(r, frac <= 0 and Palette.danger or accent, 0.2 + 0.4 * frac)
            -- manned bays get a bright outline; empty ones stay dim
            local manned = r.module and r.module.station and r.module.station.occupant
            lg.setColor(accent[1], accent[2], accent[3], manned and 1 or 0.35)
            lg.setLineWidth(manned and 2 or 1)
            lg.rectangle("line", ox + r.x0 * sc, oy + r.y0 * sc,
                (r.x1 - r.x0 + 1) * sc, (r.y1 - r.y0 + 1) * sc)
            if labels then
                lg.setFont(Assets.fonts.tiny)
                lg.setColor(accent[1], accent[2], accent[3], 0.95)
                lg.printf(r.name, ox + r.x0 * sc, oy + (r.y0 + 2) * sc,
                    (r.x1 - r.x0 + 1) * sc, "center")
            end
        end
    end

    -- fabricator marker
    if s.fabricator then
        local f = s.fabricator
        local c = Palette.station.fabricator
        lg.setColor(c[1], c[2], c[3], 0.95)
        lg.circle("fill", ox + (f.cx / T) * sc, oy + (f.cy / T) * sc, math.max(2, sc * 0.3))
        if labels then
            lg.setFont(Assets.fonts.tiny)
            lg.printf("FABRICATOR", ox + (f.cx / T) * sc - 40, oy + (f.cy / T) * sc - 20, 80, "center")
        end
    end

    for _, p in ipairs(State.players) do
        local c = Palette.crew[p.index].suit
        local me = (p == forPlayer)
        lg.setColor(c[1], c[2], c[3], me and 1 or 0.7)
        local r = math.max(2, sc * (me and 0.42 or 0.3))
        lg.circle("fill", ox + (p.x / T) * sc, oy + (p.y / T) * sc, r)
        if me then
            lg.setColor(1, 1, 1, 0.9)
            lg.setLineWidth(1)
            lg.circle("line", ox + (p.x / T) * sc, oy + (p.y / T) * sc, r + 2)
        end
    end
    lg.setColor(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- per-player strip
--------------------------------------------------------------------------------

local function drawStrip(view, p)
    local y = view.y + view.h - STRIP_H
    local c = Palette.crew[p.index].suit
    lg.setColor(0, 0, 0, 0.8)
    lg.rectangle("fill", view.x, y, view.w, STRIP_H)
    lg.setColor(c[1], c[2], c[3], 1)
    lg.rectangle("fill", view.x, y, 4, STRIP_H)

    lg.setFont(Assets.fonts.tiny)
    lg.setColor(c[1], c[2], c[3], 1)
    lg.print("P" .. p.index .. " " .. Palette.crew[p.index].name, view.x + 10, y + 6)

    local where = p.room and p.room.name or "OUTSIDE"
    Palette.set(Palette.ink_dim)
    lg.print(where, view.x + 88, y + 6)

    if p.station then
        local a = p.station.accent
        lg.setColor(a[1], a[2], a[3], 1)
        lg.print("ON STATION: " .. p.station.label .. "   (BACK to step away)", view.x + 220, y + 6)
    elseif p.repairing then
        Palette.set(Palette.warn)
        lg.print("REPAIRING...", view.x + 220, y + 6)
    elseif p.hintTimer > 0 and p.hint then
        Palette.set(Palette.danger)
        lg.print(p.hint, view.x + 220, y + 6)
    else
        Palette.set(Palette.ink_dim)
        local map = Input.KEYMAPS[p.index]
        local hint = p.ctrl.usingGamepad and "GAMEPAD  A=use  B=back" or (map and map.hint or "")
        lg.print(hint, view.x + 220, y + 6)
    end
    lg.setColor(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- global overlay
--------------------------------------------------------------------------------

local function drawGlobal(W, H)
    -- phase banner across the very top: this is the ship-wide intercom, the
    -- only information everybody is allowed to have for free
    local barH = 26
    lg.setColor(0, 0, 0, 0.78)
    lg.rectangle("fill", W / 2 - 290, 0, 580, barH)
    lg.setFont(Assets.fonts.small)

    local label, colour
    if State.phase == "combat" then
        label = ("WAVE %d  --  COMBAT  --  %d CONTACTS"):format(State.wave, #State.space.enemies)
        colour = Palette.danger
    elseif State.phase == "dead" then
        label = "SHIP LOST"
        colour = Palette.danger
    else
        label = ("LULL  --  WAVE %d IN %0.0fs  --  REFIT NOW"):format(State.wave + 1, math.max(0, State.phaseTimer))
        colour = Palette.good
    end
    Palette.set(colour)
    lg.printf(label, W / 2 - 290, 5, 440, "center")
    Palette.set(Palette.good)
    lg.printf(("SCRAP %d"):format(State.scrap), W / 2 - 290, 5, 572, "right")

    -- godmode is a dev cheat, not a game state, so it gets its own loud badge
    -- in a corner rather than competing with the phase bar or event log
    if State.godmode then
        local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 6)
        lg.setFont(Assets.fonts.small)
        local text = "GODMODE - F4 to turn off"
        local tw = Assets.fonts.small:getWidth(text) + 16
        local bx, by = W - tw - 8, barH + 6
        lg.setColor(0, 0, 0, 0.8)
        lg.rectangle("fill", bx, by, tw, 18, 3)
        Palette.set(Palette.warn, pulse)
        lg.rectangle("line", bx + 0.5, by + 0.5, tw - 1, 17, 3)
        lg.printf(text, bx, by + 4, tw, "center")
    end

    -- Event log hangs off the top bar rather than the bottom of the screen:
    -- the bottom of every viewport is a station readout and must stay legible.
    if #State.log > 0 then
        lg.setFont(Assets.fonts.tiny)
        local lines = math.min(4, #State.log)
        lg.setColor(0, 0, 0, 0.62)
        lg.rectangle("fill", W / 2 - 250, barH, 500, lines * 13 + 6, 0, 0)
        for i = 0, lines - 1 do
            local e = State.log[#State.log - i]
            local a = math.min(1, e.t)
            local c = e.colour or Palette.ink_dim
            lg.setColor(c[1], c[2], c[3], a * 0.95)
            lg.printf(e.text, W / 2 - 246, barH + 4 + i * 13, 492, "center")
        end
    end

    if State.banner and State.bannerTimer > 0 then
        local a = math.min(1, State.bannerTimer)
        lg.setFont(Assets.fonts.big)
        local _, wrapped = Assets.fonts.big:getWrap(State.banner, 700)
        local bh = #wrapped * 32 + 24
        lg.setColor(0, 0, 0, 0.78 * a)
        lg.rectangle("fill", W / 2 - 360, H / 2 - bh / 2, 720, bh, 6)
        Palette.set(Palette.panel_edge)
        lg.setLineWidth(1)
        lg.rectangle("line", W / 2 - 360, H / 2 - bh / 2, 720, bh, 6)
        lg.setColor(1, 1, 1, a)
        lg.printf(State.banner, W / 2 - 350, H / 2 - bh / 2 + 12, 700, "center")
    end

    if State.phase == "dead" then
        lg.setColor(0.3, 0, 0.02, 0.55)
        lg.rectangle("fill", 0, 0, W, H)
        lg.setFont(Assets.fonts.huge)
        lg.setColor(1, 0.4, 0.4, 1)
        lg.printf("ALL HANDS LOST", 0, H / 2 - 60, W, "center")
        lg.setFont(Assets.fonts.label)
        lg.setColor(1, 1, 1, 0.9)
        lg.printf(("survived %d waves  --  %d kills\n\npress  F5  to launch a new ship"):format(
            math.max(0, State.wave - 1), State.kills), 0, H / 2 + 4, W, "center")
    end
    lg.setColor(1, 1, 1, 1)
end

local HELP_LEFT = [[
The ship only works if somebody is standing in the right bay.
Every console is deaf to anyone who is not physically there.

   HELM          turn and throttle
                 flies blind -- no contact data at all

   WEAPONS BAY   traverse and fire
                 cannot see targets, only a bearing dial

   ENGINEERING   split reactor output three ways
                 the only station with the damage numbers

   BRIDGE        the ONLY view of the outside world
                 must call bearings out loud

   FABRICATOR    in the spine corridor -- buy refits here

Most refits bolt a NEW BAY onto the hull: more guns, more
thrust, more power, more shields. Every one of them is
another place one of you has to physically go. Four crew,
and a ship that can grow to a dozen bays.
]]

local HELP_RIGHT = [[
Six controls each:

   DPAD   walk
          ...or operate the console you are mounted at

   USE    mount the console you are standing at
          ...or the station's action: fire, buy, brace

   BACK   step away from a console
          ...or hold it to repair the bay you are in

   P1   W A S D      Q use    E back
   P2   T F G H      R use    Y back
   P3   I J K L      U use    O back
   P4   ARROWS    RSHIFT use  RCTRL back

   Gamepads are picked up automatically.
   Left stick to walk, A = use, B = back.

   F1 help   F2 pause   F3 debug   F4 godmode
   F5 restart   F10 export textures to PNG
]]

local function drawHelp(W, H)
    lg.setColor(0, 0, 0, 0.9)
    lg.rectangle("fill", 0, 0, W, H)

    lg.setFont(Assets.fonts.huge)
    Palette.set(Palette.ink)
    lg.printf("ALL HANDS", 0, 26, W, "center")
    lg.setFont(Assets.fonts.label)
    Palette.set(Palette.ink_dim)
    lg.printf("four players  --  one ship  --  one pair of eyes", 0, 78, W, "center")

    local colW = math.min(460, W / 2 - 60)
    local lx = W / 2 - colW - 20
    local rx = W / 2 + 20

    lg.setFont(Assets.fonts.body)
    Palette.set(Palette.ink)
    lg.printf(HELP_LEFT, lx, 120, colW, "left")
    Palette.set(Palette.ink_dim)
    lg.printf(HELP_RIGHT, rx, 120, colW, "left")

    -- live plan of the ship as it currently stands, sized to the hull's shape
    -- so it grows wider as bays get bolted on
    local b = State.ship.bounds
    local aspect = (b.x1 - b.x0 + 1) / math.max(1, (b.y1 - b.y0 + 1))
    local ph = 200
    local pw = math.min(W - 120, math.max(300, ph * aspect))
    local px, py = W / 2 - pw / 2, H - ph - 96
    lg.setColor(0, 0, 0, 0.5)
    lg.rectangle("fill", px - 8, py - 22, pw + 16, ph + 30, 4)
    Palette.set(Palette.panel_edge)
    lg.setLineWidth(1)
    lg.rectangle("line", px - 8, py - 22, pw + 16, ph + 30, 4)
    lg.setFont(Assets.fonts.tiny)
    Palette.set(Palette.ink_dim)
    lg.print("YOUR SHIP  --  bright outline = that bay is manned", px, py - 18)
    Render.miniPlan(px, py, pw, ph, nil, true)

    lg.setFont(Assets.fonts.label)
    Palette.set(Palette.warn)
    lg.printf("press F1 or ENTER to take your stations", 0, H - 48, W, "center")
    lg.setColor(1, 1, 1, 1)
end

--------------------------------------------------------------------------------

function Render.draw()
    local W, H = lg.getDimensions()
    lg.clear(Palette.void[1], Palette.void[2], Palette.void[3], 1)

    if Render.showHelp then
        drawHelp(W, H)
        return
    end

    local halfW, halfH = math.floor(W / 2), math.floor(H / 2)
    for i, p in ipairs(State.players) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local vp = {
            x = col * halfW, y = row * halfH,
            w = halfW - 1, h = halfH - 1,
        }

        local onBridge = p.station and p.station.kind == "bridge"
        local panelH = (p.station and not onBridge) and PANEL_H or 0
        local view = { x = vp.x, y = vp.y, w = vp.w, h = vp.h - STRIP_H - panelH }

        if onBridge then
            drawTactical({ x = vp.x, y = vp.y, w = vp.w, h = vp.h - STRIP_H }, p.station)
        else
            drawInterior(view, p)
            if panelH > 0 then
                lg.setScissor(vp.x, vp.y, vp.w, vp.h)
                Stations.drawPanel(p.station, vp.x + 4, vp.y + vp.h - STRIP_H - panelH + 2,
                    vp.w - 8, panelH - 4)
                lg.setScissor()
            end
        end

        drawStrip(vp, p)

        -- viewport frame
        Palette.set(Palette.panel_edge)
        lg.setLineWidth(1)
        lg.rectangle("line", vp.x + 0.5, vp.y + 0.5, vp.w - 1, vp.h - 1)
    end

    -- split-screen dividers
    Palette.set(Palette.void)
    lg.rectangle("fill", halfW - 1, 0, 2, H)
    lg.rectangle("fill", 0, halfH - 1, W, 2)

    drawGlobal(W, H)

    if State.debug then
        lg.setFont(Assets.fonts.tiny)
        Palette.set(Palette.warn)
        lg.print(("fps %d   sprites %d   walls %d   bays %d   stations %d"):format(
            love.timer.getFPS(), #require("Engine/Chispita_sprite").sprites,
            #State.ship.walls, #State.ship.modules, #State.ship.stations), 8, H - 14)
        lg.setColor(1, 1, 1, 1)
    end
end

return Render
