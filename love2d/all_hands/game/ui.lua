-- Small widget kit so every console in the ship looks like it came out of the
-- same parts bin: dark housing, cyan phosphor, one accent colour per station.

local Palette = require("game/palette")
local Assets  = require("game/assets")

local UI = {}

local lg = love.graphics

function UI.panel(x, y, w, h, title, accent)
    accent = accent or Palette.ink
    Palette.set(Palette.panel, 0.93)
    lg.rectangle("fill", x, y, w, h, 4)
    lg.setLineWidth(1)
    Palette.set(Palette.panel_edge)
    lg.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 4)
    -- accent rail along the top
    lg.setColor(accent[1], accent[2], accent[3], 0.85)
    lg.rectangle("fill", x + 3, y + 3, w - 6, 2)
    if title then
        lg.setFont(Assets.fonts.tiny)
        lg.setColor(accent[1], accent[2], accent[3], 0.95)
        lg.print(title, x + 7, y + 8)
    end
    lg.setColor(1, 1, 1, 1)
end

function UI.screen(x, y, w, h)
    Palette.set(Palette.screen)
    lg.rectangle("fill", x, y, w, h, 3)
    Palette.set(Palette.screen_grid, 0.5)
    lg.setLineWidth(1)
    for gy = y + 6, y + h - 2, 7 do
        lg.line(x + 2, gy, x + w - 2, gy)
    end
    Palette.set(Palette.panel_edge)
    lg.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 3)
    lg.setColor(1, 1, 1, 1)
end

function UI.bar(x, y, w, h, frac, colour, label, labelRight)
    frac = math.max(0, math.min(1, frac or 0))
    Palette.set(Palette.screen)
    lg.rectangle("fill", x, y, w, h, 2)
    lg.setColor(colour[1], colour[2], colour[3], 0.9)
    lg.rectangle("fill", x, y, w * frac, h, 2)
    Palette.set(Palette.panel_edge)
    lg.setLineWidth(1)
    lg.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 2)
    if label then
        lg.setFont(Assets.fonts.tiny)
        lg.setColor(1, 1, 1, 0.9)
        lg.print(label, x + 4, y + h / 2 - 6)
    end
    if labelRight then
        lg.setFont(Assets.fonts.tiny)
        lg.setColor(1, 1, 1, 0.75)
        lg.printf(labelRight, x, y + h / 2 - 6, w - 4, "right")
    end
    lg.setColor(1, 1, 1, 1)
end

-- Power allocation pips: filled = assigned, hollow = free capacity.
function UI.pips(x, y, filled, capacity, maxSlots, colour, highlight)
    local pw, ph, gap = 13, 16, 3
    for i = 1, maxSlots do
        local px = x + (i - 1) * (pw + gap)
        if i <= filled then
            lg.setColor(colour[1], colour[2], colour[3], 1)
            lg.rectangle("fill", px, y, pw, ph, 2)
        elseif i <= capacity then
            lg.setColor(colour[1], colour[2], colour[3], 0.22)
            lg.rectangle("fill", px, y, pw, ph, 2)
        else
            Palette.set(Palette.screen)
            lg.rectangle("fill", px, y, pw, ph, 2)
        end
        Palette.set(Palette.panel_edge)
        lg.setLineWidth(1)
        lg.rectangle("line", px + 0.5, y + 0.5, pw - 1, ph - 1, 2)
    end
    if highlight then
        lg.setColor(1, 1, 1, 0.8)
        lg.setLineWidth(1)
        lg.rectangle("line", x - 2.5, y - 2.5, maxSlots * (pw + gap) - gap + 5, ph + 5, 3)
    end
    lg.setColor(1, 1, 1, 1)
end

-- Compass rose. `angle` is radians with 0 = up on the dial.
function UI.compass(cx, cy, r, angle, accent, label)
    accent = accent or Palette.ink
    Palette.set(Palette.screen)
    lg.circle("fill", cx, cy, r)
    Palette.set(Palette.screen_grid)
    lg.setLineWidth(1)
    lg.circle("line", cx, cy, r)
    lg.circle("line", cx, cy, r * 0.62)

    lg.setFont(Assets.fonts.tiny)
    for i = 0, 11 do
        local a = i * math.pi / 6
        local inner = (i % 3 == 0) and r * 0.74 or r * 0.86
        Palette.set(Palette.ink_dim)
        lg.line(cx + math.sin(a) * inner, cy - math.cos(a) * inner,
                cx + math.sin(a) * r * 0.96, cy - math.cos(a) * r * 0.96)
    end
    Palette.set(Palette.ink_dim)
    lg.print("0", cx - 3, cy - r + 2)

    -- needle
    lg.setColor(accent[1], accent[2], accent[3], 1)
    lg.setLineWidth(2)
    local nx, ny = cx + math.sin(angle) * r * 0.78, cy - math.cos(angle) * r * 0.78
    lg.line(cx, cy, nx, ny)
    lg.circle("fill", nx, ny, 3)
    lg.circle("fill", cx, cy, 2.5)

    if label then
        lg.setFont(Assets.fonts.tiny)
        lg.setColor(1, 1, 1, 0.8)
        lg.printf(label, cx - r, cy + r + 3, r * 2, "center")
    end
    lg.setColor(1, 1, 1, 1)
end

-- Annular wedge, used for shield coverage and turret traverse limits.
--
-- Drawn as a strip of quads rather than one polygon: love.graphics.polygon
-- fills with a triangle fan, so a concave ring band would collapse into a
-- solid pie slice.
function UI.wedge(cx, cy, r0, r1, centre, half, colour, alpha)
    local steps = math.max(8, math.floor(half * 24))
    lg.setColor(colour[1], colour[2], colour[3], alpha or 0.35)
    local a0 = centre - half
    local step = (half * 2) / steps
    for i = 0, steps - 1 do
        local aA = a0 + step * i
        local aB = a0 + step * (i + 1)
        local cA, sA = math.cos(aA), math.sin(aA)
        local cB, sB = math.cos(aB), math.sin(aB)
        lg.polygon("fill",
            cx + cA * r0, cy + sA * r0,
            cx + cA * r1, cy + sA * r1,
            cx + cB * r1, cy + sB * r1,
            cx + cB * r0, cy + sB * r0)
    end
    lg.setColor(1, 1, 1, 1)
end

function UI.gauge(x, y, w, h, frac, label, warnAt)
    frac = math.max(0, math.min(1.2, frac or 0))
    local colour = Palette.good
    if frac > (warnAt or 0.75) then colour = Palette.warn end
    if frac >= 1.0 then colour = Palette.danger end
    UI.bar(x, y, w, h, math.min(1, frac), colour, label,
        ("%d%%"):format(math.floor(frac * 100)))
    -- redline tick
    lg.setColor(1, 0.3, 0.35, 0.8)
    local tx = x + w * (warnAt or 0.75)
    lg.rectangle("fill", tx, y, 1, h)
    lg.setColor(1, 1, 1, 1)
end

function UI.label(text, x, y, colour, font)
    lg.setFont(font or Assets.fonts.small)
    local c = colour or Palette.ink
    lg.setColor(c[1], c[2], c[3], c[4] or 1)
    lg.print(text, x, y)
    lg.setColor(1, 1, 1, 1)
end

function UI.centred(text, x, y, w, colour, font)
    lg.setFont(font or Assets.fonts.small)
    local c = colour or Palette.ink
    lg.setColor(c[1], c[2], c[3], c[4] or 1)
    lg.printf(text, x, y, w, "center")
    lg.setColor(1, 1, 1, 1)
end

-- A chunky "no signal" fill for consoles that are dead or that deliberately
-- refuse to show you something.
function UI.static(x, y, w, h, text, colour)
    UI.screen(x, y, w, h)
    local t = love.timer.getTime()
    lg.setColor(1, 1, 1, 0.045)
    for i = 1, 26 do
        local sy = y + ((i * 37 + t * 90) % h)
        lg.rectangle("fill", x + 2, sy, w - 4, 1)
    end
    if text then
        local c = colour or Palette.ink_dim
        lg.setFont(Assets.fonts.small)
        lg.setColor(c[1], c[2], c[3], 0.8)
        lg.printf(text, x + 4, y + h / 2 - 9, w - 8, "center")
    end
    lg.setColor(1, 1, 1, 1)
end

-- Station glyphs, drawn as primitives so they scale with the console.
function UI.glyph(kind, cx, cy, s, colour)
    local c = colour or Palette.ink
    lg.setColor(c[1], c[2], c[3], 1)
    lg.setLineWidth(math.max(1, s * 0.12))

    if kind == "helm" then
        lg.circle("line", cx, cy, s * 0.8)
        for i = 0, 3 do
            local a = i * math.pi / 2 + math.pi / 4
            lg.line(cx + math.cos(a) * s * 0.3, cy + math.sin(a) * s * 0.3,
                    cx + math.cos(a) * s, cy + math.sin(a) * s)
        end
        lg.circle("fill", cx, cy, s * 0.22)
    elseif kind == "bridge" then
        lg.arc("line", "open", cx, cy + s * 0.3, s, -math.pi * 0.85, -math.pi * 0.15)
        lg.line(cx - s, cy + s * 0.3, cx + s, cy + s * 0.3)
        lg.circle("fill", cx, cy - s * 0.2, s * 0.2)
    elseif kind == "weapons" then
        lg.circle("line", cx, cy, s * 0.75)
        lg.line(cx - s, cy, cx - s * 0.35, cy)
        lg.line(cx + s * 0.35, cy, cx + s, cy)
        lg.line(cx, cy - s, cx, cy - s * 0.35)
        lg.line(cx, cy + s * 0.35, cx, cy + s)
        lg.circle("fill", cx, cy, s * 0.15)
    elseif kind == "engineering" then
        lg.polygon("fill", cx - s * 0.1, cy - s,
                           cx + s * 0.55, cy - s * 0.15,
                           cx + s * 0.1, cy - s * 0.15,
                           cx + s * 0.1, cy + s,
                           cx - s * 0.55, cy + s * 0.1,
                           cx - s * 0.1, cy + s * 0.1)
    elseif kind == "shields" then
        lg.polygon("line", cx, cy - s, cx + s * 0.8, cy - s * 0.45,
                           cx + s * 0.6, cy + s * 0.7, cx, cy + s,
                           cx - s * 0.6, cy + s * 0.7, cx - s * 0.8, cy - s * 0.45)
    elseif kind == "engine" then
        lg.polygon("fill", cx - s * 0.5, cy - s * 0.7, cx + s * 0.2, cy - s * 0.7,
                           cx + s * 0.2, cy + s * 0.7, cx - s * 0.5, cy + s * 0.7)
        lg.polygon("line", cx + s * 0.3, cy - s * 0.5, cx + s, cy, cx + s * 0.3, cy + s * 0.5)
    elseif kind == "reactor" then
        lg.circle("line", cx, cy, s * 0.3)
        for i = 0, 2 do
            local a = i * math.pi * 2 / 3
            lg.ellipse("line", cx, cy, s, s * 0.34, a)
        end
    elseif kind == "sensors" then
        for i = 1, 3 do
            lg.arc("line", "open", cx - s * 0.6, cy + s * 0.6, s * 0.45 * i,
                   -math.pi * 0.5, 0)
        end
        lg.circle("fill", cx - s * 0.6, cy + s * 0.6, s * 0.16)
    elseif kind == "fabricator" then
        lg.rectangle("line", cx - s * 0.85, cy - s * 0.6, s * 1.7, s * 1.2, 2)
        lg.line(cx - s * 0.5, cy + s * 0.6, cx - s * 0.5, cy + s)
        lg.line(cx + s * 0.5, cy + s * 0.6, cx + s * 0.5, cy + s)
        lg.circle("fill", cx, cy, s * 0.22)
    else
        lg.circle("line", cx, cy, s * 0.6)
    end
    lg.setColor(1, 1, 1, 1)
end

return UI
