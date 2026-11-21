-- Procedural pixel-art assets.
--
-- Nothing here loads from disk: every texture is authored either as a block of
-- ASCII pixel rows (readable + editable right in this file) or generated from a
-- seeded noise function. Press F10 in game to dump every generated texture to
-- PNG in the save directory if you want to hand-edit them later.

local Palette = require("game/palette")

local Assets = {}
Assets.images = {}   -- name -> Image
Assets.data = {}     -- name -> ImageData (kept so we can export to PNG)

local TILE = 32

--------------------------------------------------------------------------------
-- authoring helpers
--------------------------------------------------------------------------------

-- Build ImageData from ASCII rows. Rows may be ragged; short rows are padded
-- with transparent pixels, so a miscounted row never crashes the game.
local function fromRows(rows, pal)
    local h = #rows
    local w = 0
    for i = 1, h do w = math.max(w, #rows[i]) end

    local d = love.image.newImageData(w, h)
    for y = 1, h do
        local row = rows[y]
        for x = 1, #row do
            local key = row:sub(x, x)
            local c = pal[key]
            if c then
                d:setPixel(x - 1, y - 1, c[1], c[2], c[3], c[4] or 1)
            end
        end
    end
    return d
end

local function generate(w, h, fn)
    local d = love.image.newImageData(w, h)
    d:mapPixel(function(x, y)
        local r, g, b, a = fn(x, y)
        return r, g, b, a == nil and 1 or a
    end)
    return d
end

-- Deterministic value noise so textures look the same every run.
-- Float-only on purpose: LuaJIT (LOVE 11.x) has no bitwise operators.
local function hash2(x, y, seed)
    local n = math.sin(x * 12.9898 + y * 78.233 + (seed or 0) * 37.719) * 43758.5453
    return n - math.floor(n)
end

local function register(name, data, filter)
    local img = love.graphics.newImage(data)
    img:setFilter(filter or "nearest", filter or "nearest")
    Assets.images[name] = img
    Assets.data[name] = data
    return img
end

local function shade(c, amount)
    return { c[1] * amount, c[2] * amount, c[3] * amount, 1 }
end

--------------------------------------------------------------------------------
-- crew sprites
--------------------------------------------------------------------------------
-- Suited crew member, 12x15, drawn 3/4 top-down so facing reads at a glance.
-- o outline   h helmet  H helmet shade  v visor  V visor glint
-- s suit      S suit shade   t chest trim   g glove   b boot

local CREW_DOWN_A = {
    "...oooooo...",
    "..ohhhhhho..",
    ".ohhhhhhhho.",
    ".ohvvvvvvho.",
    ".oHvvvVvvHo.",
    ".ohhhhhhhho.",
    "..osssssso..",
    ".osstttttso.",
    "ogsstttttsgo",
    "ogssttttssgo",
    ".osssssssso.",
    "..oSssssSo..",
    "..obb..bbo..",
    "..obb..bbo..",
    "...oo..oo...",
}

local CREW_DOWN_B = {
    "...oooooo...",
    "..ohhhhhho..",
    ".ohhhhhhhho.",
    ".ohvvvvvvho.",
    ".oHvvvVvvHo.",
    ".ohhhhhhhho.",
    "..osssssso..",
    ".osstttttso.",
    "ogsstttttsgo",
    "ogssttttssgo",
    ".osssssssso.",
    "..oSssssSo..",
    ".obb....bbo.",
    ".obb....bbo.",
    "..oo....oo..",
}

local CREW_UP_A = {
    "...oooooo...",
    "..ohhhhhho..",
    ".ohhhhhhhho.",
    ".ohhHHHHhho.",
    ".oHhHHHHhHo.",
    ".ohhhhhhhho.",
    "..osssssso..",
    ".osstttttso.",
    "ogsstttttsgo",
    "ogsstttttsgo",
    ".osssssssso.",
    "..oSssssSo..",
    "..obb..bbo..",
    "..obb..bbo..",
    "...oo..oo...",
}

local CREW_UP_B = {
    "...oooooo...",
    "..ohhhhhho..",
    ".ohhhhhhhho.",
    ".ohhHHHHhho.",
    ".oHhHHHHhHo.",
    ".ohhhhhhhho.",
    "..osssssso..",
    ".osstttttso.",
    "ogsstttttsgo",
    "ogsstttttsgo",
    ".osssssssso.",
    "..oSssssSo..",
    ".obb....bbo.",
    ".obb....bbo.",
    "..oo....oo..",
}

-- facing right (+x); the left-facing sprite is this one drawn mirrored
local CREW_SIDE_A = {
    "...oooooo...",
    "..ohhhhhho..",
    ".ohhhhhvvo..",
    ".ohhhhhvvVo.",
    ".oHhhhhvvo..",
    ".ohhhhhhho..",
    "..osssssso..",
    "..otssssgo..",
    "..otsssssgo.",
    "..otssssssgo",
    "..osssssso..",
    "..oSsssSo...",
    "..obbbbo....",
    "..obb.obbo..",
    "...oo..oo...",
}

local CREW_SIDE_B = {
    "...oooooo...",
    "..ohhhhhho..",
    ".ohhhhhvvo..",
    ".ohhhhhvvVo.",
    ".oHhhhhvvo..",
    ".ohhhhhhho..",
    "..osssssso..",
    "..otssssgo..",
    "..otsssssgo.",
    "..otssssssgo",
    "..osssssso..",
    "..oSsssSo...",
    "...obbbbo...",
    "...obbbbo...",
    "...oo.oo....",
}

local function crewPalette(crew)
    return {
        o = Palette.hex("0b0d12"),
        h = Palette.hex("c9d2de"),
        H = Palette.hex("8b96a6"),
        v = Palette.hex("1d4e5c"),
        V = Palette.hex("9fe8ff"),
        s = crew.suit,
        S = crew.shade,
        t = Palette.hex("e4e9f0"),
        g = crew.glove,
        b = Palette.hex("25292f"),
    }
end

--------------------------------------------------------------------------------
-- enemy sprites (authored pointing right / +x)
--------------------------------------------------------------------------------

local RAIDER = {
    ".oo.........",
    ".oDo........",
    ".oDDoo......",
    "..oDDDoo....",
    "..oDDDDDoo..",
    "...oDDccDDo.",
    "...oDDccDDo.",
    "..oDDDDDoo..",
    "..oDDDoo....",
    ".oDDoo......",
    ".oDo........",
    ".oo.........",
}

local GUNSHIP = {
    "ooooo.......",
    "oGGGGoo.....",
    "oGGGGGGoo...",
    ".oGGGGGGGo..",
    ".oGGwwGGGGo.",
    "..oGGccGGGGo",
    "..oGGccGGGGo",
    ".oGGwwGGGGo.",
    ".oGGGGGGGo..",
    "oGGGGGGoo...",
    "oGGGGoo.....",
    "ooooo.......",
}

local ENEMY_PAL = {
    o = Palette.hex("120a10"),
    D = Palette.hex("7a3b52"),
    G = Palette.hex("5d4a72"),
    w = Palette.hex("c2b4d8"),
    c = Palette.hex("ff9d5c"),
}

--------------------------------------------------------------------------------
-- tile generators
--------------------------------------------------------------------------------

local function deckTile(base, seed)
    return generate(TILE, TILE, function(x, y)
        local c = base
        local n = hash2(x, y, seed)
        -- plate seam every 16px
        local seam = (x % 16 == 0) or (y % 16 == 0)
        local inner = (x % 16 == 1) or (y % 16 == 1)
        local m = 1.0 + (n - 0.5) * 0.10
        if seam then m = m * 0.72 end
        if inner then m = m * 1.12 end
        -- rivets at plate corners
        local rx, ry = x % 16, y % 16
        if (rx == 4 or rx == 12) and (ry == 4 or ry == 12) then
            local r = Palette.rivet
            return r[1], r[2], r[3], 1
        end
        return c[1] * m, c[2] * m, c[3] * m, 1
    end)
end

local function hullTile(seed)
    local base = Palette.hull
    return generate(TILE, TILE, function(x, y)
        local n = hash2(x, y, seed)
        local m = 1.0 + (n - 0.5) * 0.12
        -- chunky bevel: lit on top/left, dark on bottom/right
        if y <= 2 or x <= 2 then m = m * 1.30 end
        if y >= TILE - 3 or x >= TILE - 3 then m = m * 0.62 end
        -- bolt heads
        if (x == 6 or x == 25) and (y == 6 or y == 25) then
            local r = Palette.hull_light
            return r[1] * 1.25, r[2] * 1.25, r[3] * 1.25, 1
        end
        -- weld line down the middle of the plate
        if x == 16 and y > 4 and y < TILE - 4 then m = m * 0.78 end
        return base[1] * m, base[2] * m, base[3] * m, 1
    end)
end

local function hazardTile()
    local a = Palette.hex("3a3f46")
    local b = Palette.hex("c9a227")
    return generate(TILE, TILE, function(x, y)
        local n = hash2(x, y, 7)
        local stripe = ((x + y) % 16) < 8
        local c = stripe and b or a
        local m = 1.0 + (n - 0.5) * 0.14
        -- scuffed paint
        if stripe and n > 0.88 then c = a end
        return c[1] * m, c[2] * m, c[3] * m, 1
    end)
end

local function viewportTile()
    return generate(TILE, TILE, function(x, y)
        local n = hash2(x, y, 23)
        -- dark glass with a few stars showing through
        local base = Palette.hex("0a1420")
        if n > 0.991 then return 1, 1, 1, 1 end
        if n > 0.975 then return 0.6, 0.75, 0.9, 1 end
        local m = 1.0 + (n - 0.5) * 0.25
        -- frame
        if x <= 1 or y <= 1 or x >= TILE - 2 or y >= TILE - 2 then
            local f = Palette.hull_dark
            return f[1], f[2], f[3], 1
        end
        return base[1] * m, base[2] * m, base[3] * m, 1
    end)
end

local function consoleTile()
    -- generic wall console: housing + dark screen; the icon is drawn on top
    return generate(TILE, 20, function(x, y)
        local n = hash2(x, y, 31)
        if y < 3 then
            local c = Palette.hull_light
            return c[1], c[2], c[3], 1
        end
        if y >= 17 then
            local c = Palette.hull_dark
            return c[1], c[2], c[3], 1
        end
        if x < 2 or x >= TILE - 2 then
            local c = Palette.panel_edge
            return c[1], c[2], c[3], 1
        end
        if y >= 4 and y < 15 and x >= 4 and x < TILE - 4 then
            local c = Palette.screen
            local m = 1.0 + (n - 0.5) * 0.3
            return c[1] * m, c[2] * m, c[3] * m, 1
        end
        local c = Palette.panel
        return c[1] * n * 0.4 + c[1] * 0.8, c[2] * n * 0.4 + c[2] * 0.8, c[3] * n * 0.4 + c[3] * 0.8, 1
    end)
end

local function hullPlateTile()
    -- exterior armour plating, tiled over the hull silhouette in space
    local base = Palette.hex("5b646f")
    return generate(16, 16, function(x, y)
        local n = hash2(x, y, 51)
        local m = 1.0 + (n - 0.5) * 0.18
        if x == 0 or y == 0 then m = m * 0.7 end
        if x == 1 or y == 1 then m = m * 1.15 end
        return base[1] * m, base[2] * m, base[3] * m, 1
    end)
end

local function boltSprite(colour)
    local w, h = 10, 4
    return generate(w, h, function(x, y)
        local cx, cy = (w - 1) / 2, (h - 1) / 2
        local dx = (x - cx) / (w / 2)
        local dy = (y - cy) / (h / 2)
        local d = dx * dx * 0.55 + dy * dy
        if d > 1 then return 0, 0, 0, 0 end
        local core = 1 - d
        return colour[1] + core * 0.9,
               colour[2] + core * 0.9,
               colour[3] + core * 0.9,
               math.min(1, 0.35 + core * 1.4)
    end)
end

local function asteroidSprite(seed, size)
    return generate(size, size, function(x, y)
        local cx = (size - 1) / 2
        local dx, dy = x - cx, y - cx
        local dist = math.sqrt(dx * dx + dy * dy)
        local ang = math.atan2(dy, dx)
        -- lumpy radius from a couple of sine harmonics + noise
        local r = size / 2 * (0.76
            + 0.10 * math.sin(ang * 3 + seed)
            + 0.07 * math.sin(ang * 5 - seed * 2)
            + 0.05 * (hash2(math.floor(ang * 8), 0, seed) - 0.5))
        if dist > r then return 0, 0, 0, 0 end
        local n = hash2(x, y, seed)
        local lit = 1.0 - (dx + dy) / (size * 1.6)  -- light from top-left
        local base = Palette.hex("6b6258")
        local m = lit * (0.82 + n * 0.3)
        if dist > r - 1.5 then m = m * 0.6 end
        -- craters
        if n > 0.93 then m = m * 0.65 end
        return base[1] * m, base[2] * m, base[3] * m, 1
    end)
end

--------------------------------------------------------------------------------
-- load
--------------------------------------------------------------------------------

function Assets.load()
    -- decks: one tint per room mood
    register("deck", deckTile(Palette.deck, 1))
    register("deck_warm", deckTile(Palette.hex("342c28"), 2))
    register("deck_cool", deckTile(Palette.hex("242e38"), 3))
    register("deck_green", deckTile(Palette.hex("222f28"), 4))
    register("hull", hullTile(11))
    register("hazard", hazardTile())
    register("viewport", viewportTile())
    register("console", consoleTile())
    register("plate", hullPlateTile())
    Assets.images.plate:setWrap("repeat", "repeat")

    register("bolt_ally", boltSprite(Palette.hex("2a6a4a")))
    register("bolt_enemy", boltSprite(Palette.hex("6a2a3a")))

    for i = 1, 4 do
        register("rock" .. i, asteroidSprite(i * 13, 24 + i * 10))
    end

    register("raider", fromRows(RAIDER, ENEMY_PAL))
    register("gunship", fromRows(GUNSHIP, ENEMY_PAL))

    Assets.crew = {}
    for i, crew in ipairs(Palette.crew) do
        local pal = crewPalette(crew)
        local set = {
            down = { register("crew" .. i .. "_down_a", fromRows(CREW_DOWN_A, pal)),
                     register("crew" .. i .. "_down_b", fromRows(CREW_DOWN_B, pal)) },
            up   = { register("crew" .. i .. "_up_a", fromRows(CREW_UP_A, pal)),
                     register("crew" .. i .. "_up_b", fromRows(CREW_UP_B, pal)) },
            side = { register("crew" .. i .. "_side_a", fromRows(CREW_SIDE_A, pal)),
                     register("crew" .. i .. "_side_b", fromRows(CREW_SIDE_B, pal)) },
        }
        Assets.crew[i] = set
    end

    -- starfield: three parallax layers of plain points, built once
    Assets.stars = {}
    for layer = 1, 3 do
        local pts = {}
        local count = 260 - layer * 50
        for i = 1, count do
            pts[i] = {
                x = hash2(i, layer, 101) * 4000 - 2000,
                y = hash2(i, layer, 202) * 4000 - 2000,
                b = 0.25 + hash2(i, layer, 303) * 0.75,
                s = layer == 1 and 2 or 1,
            }
        end
        Assets.stars[layer] = pts
    end

    Assets.fonts = {
        tiny  = love.graphics.newFont(10),
        small = love.graphics.newFont(12),
        body  = love.graphics.newFont(14),
        label = love.graphics.newFont(18),
        big   = love.graphics.newFont(28),
        huge  = love.graphics.newFont(46),
    }
end

-- F10: write every generated texture out as a PNG you can edit by hand.
function Assets.export()
    local dir = "assets_export"
    love.filesystem.createDirectory(dir)
    local n = 0
    for name, data in pairs(Assets.data) do
        data:encode("png", dir .. "/" .. name .. ".png")
        n = n + 1
    end
    print(("Exported %d textures to %s/%s"):format(n, love.filesystem.getSaveDirectory(), dir))
    return n, love.filesystem.getSaveDirectory() .. "/" .. dir
end

Assets.shade = shade
Assets.hash2 = hash2
Assets.TILE = TILE

return Assets
