-- Shared colour language for the whole prototype.
-- Everything visual pulls from here so the ship reads as one machine.

local Palette = {}

local function hex(s)
    local r = tonumber(s:sub(1, 2), 16) / 255
    local g = tonumber(s:sub(3, 4), 16) / 255
    local b = tonumber(s:sub(5, 6), 16) / 255
    return { r, g, b, 1 }
end

Palette.hex = hex

-- hull / interior
Palette.void        = hex("07090f")
Palette.deck        = hex("2a3038")
Palette.deck_dark   = hex("1d222a")
Palette.deck_light  = hex("3a424d")
Palette.hull        = hex("4a525e")
Palette.hull_light  = hex("636d7b")
Palette.hull_dark   = hex("2b313a")
Palette.rivet       = hex("848d9c")

-- ui
Palette.screen      = hex("081a1c")
Palette.screen_grid = hex("12383a")
Palette.ink         = hex("8ff0e0")
Palette.ink_dim     = hex("3f7d76")
Palette.warn        = hex("ffb13b")
Palette.danger      = hex("ff4d5e")
Palette.good        = hex("5ce08a")
Palette.panel       = hex("141a22")
Palette.panel_edge  = hex("2e3a48")

-- systems
Palette.sys_engines = hex("ff8a3b")
Palette.sys_shields = hex("4db8ff")
Palette.sys_weapons = hex("ff556e")
Palette.sys_sensors = hex("b48bff")

-- the four crew
Palette.crew = {
    { name = "RED",    suit = hex("e8484f"), shade = hex("9c2a30"), glove = hex("ff8a8f") },
    { name = "BLUE",   suit = hex("3d8ce8"), shade = hex("23548f"), glove = hex("8fc0ff") },
    { name = "GREEN",  suit = hex("46c466"), shade = hex("27773d"), glove = hex("95eaa9") },
    { name = "YELLOW", suit = hex("e5c23c"), shade = hex("98791c"), glove = hex("ffe992") },
}

-- station accent colours, keyed by station kind
Palette.station = {
    helm        = hex("5ce08a"),
    bridge      = hex("8ff0e0"),
    weapons     = hex("ff556e"),
    engineering = hex("ff8a3b"),
    shields     = hex("4db8ff"),
    engine      = hex("ffb13b"),
    reactor     = hex("b48bff"),
    fabricator  = hex("d8d2c0"),
}

function Palette.set(c, alpha)
    love.graphics.setColor(c[1], c[2], c[3], alpha or c[4] or 1)
end

function Palette.mix(a, b, t)
    return {
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
        1,
    }
end

return Palette
