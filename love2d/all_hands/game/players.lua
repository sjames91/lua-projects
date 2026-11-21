-- Crew members. Each one is an engine rect body that walks the interior grid,
-- plus the bookkeeping for which console they are currently mounted at.

local State   = require("game/state")
local Palette = require("game/palette")
local Assets  = require("game/assets")
local Ship    = require("game/ship")
local Input   = require("game/input")
local Chispita = require("Engine/Chispita_sprite")

local Players = {}

local BODY_W, BODY_H = 18, 14
local SPEED = 2.5          -- px per frame; the engine integrates velocity per frame
local SCALE = 2

local function drawCrew(self)
    local p = self.ah_player
    local art = Assets.crew[p.index]
    local frame = (p.animFrame % 2) + 1
    local img, sx = nil, SCALE

    if p.facing == "up" then
        img = art.up[frame]
    elseif p.facing == "down" then
        img = art.down[frame]
    else
        img = art.side[frame]
        if p.facing == "left" then sx = -SCALE end
    end

    local w, h = img:getWidth(), img:getHeight()
    local footY = self.y + BODY_H + 2
    local cx = self.x + BODY_W / 2

    -- contact shadow so crew read as standing on the deck
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.ellipse("fill", cx, footY - 2, 9, 3.5)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, cx, footY, 0, sx, SCALE, w / 2, h)

    -- mounted crew get a glow ring in their suit colour
    if p.station then
        local c = Palette.crew[p.index].suit
        local pulse = 0.55 + 0.45 * math.sin(love.timer.getTime() * 5)
        love.graphics.setColor(c[1], c[2], c[3], 0.5 * pulse)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", cx, footY - 4, 16)
    end

    -- repair sparks
    if p.repairing then
        love.graphics.setColor(1, 0.85, 0.3, 0.9)
        for i = 1, 4 do
            local a = love.math.random() * math.pi * 2
            local r = love.math.random() * 14
            love.graphics.circle("fill", cx + math.cos(a) * r, footY - 10 + math.sin(a) * r, 1.4)
        end
    end

    -- name tag
    love.graphics.setFont(Assets.fonts.tiny)
    local c = Palette.crew[p.index].suit
    local tag = "P" .. p.index
    local tw = Assets.fonts.tiny:getWidth(tag)
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", cx - tw / 2 - 2, footY - 46, tw + 4, 11, 2)
    love.graphics.setColor(c[1], c[2], c[3], 1)
    love.graphics.print(tag, cx - tw / 2, footY - 46)
    love.graphics.setColor(1, 1, 1, 1)
end

function Players.spawn(count)
    State.players = {}
    -- players persist across rebuilds, so only make bodies once per reset
    local pts = Ship.spawnPoints(count)
    for i = 1, count do
        local body = Chispita.addRect(pts[i].x, pts[i].y, BODY_W, BODY_H)
        body.fall    = false
        body.fixed   = false
        body.solid   = true
        body.bounciness = 0
        body.friction = 0.6
        body.visable = true
        body.draw    = drawCrew

        local p = {
            index = i,
            body = body,
            x = body.x + BODY_W / 2,
            y = body.y + BODY_H / 2,
            facing = "down",
            animFrame = 0,
            animTime = 0,
            room = nil,
            station = nil,
            repairing = false,
            ctrl = Input.newController(i),
            hintTimer = 0,
        }
        body.ah_player = p
        State.players[i] = p
    end
end

function Players.applyMovement(dt)
    for _, p in ipairs(State.players) do
        local c = p.ctrl
        local body = p.body

        if p.station then
            -- mounted: the console eats the dpad, and the crew member stands put
            body.vx, body.vy = 0, 0
            local st = p.station
            local tx = st.ix - BODY_W / 2
            local ty = (st.facing == "down") and (st.py + st.h + 4) or (st.py - BODY_H - 4)
            body.x = body.x + (tx - body.x) * math.min(1, dt * 12)
            body.y = body.y + (ty - body.y) * math.min(1, dt * 12)
            p.facing = (st.facing == "down") and "up" or "down"
            p.animFrame = 0
        else
            local dx = (c.right and 1 or 0) - (c.left and 1 or 0)
            local dy = (c.down and 1 or 0) - (c.up and 1 or 0)
            if dx ~= 0 and dy ~= 0 then
                dx, dy = dx * 0.7071, dy * 0.7071
            end

            local speed = SPEED
            if p.repairing then speed = speed * 0.35 end
            body.vx = dx * speed
            body.vy = dy * speed

            if dx ~= 0 or dy ~= 0 then
                if math.abs(dx) > math.abs(dy) then
                    p.facing = dx > 0 and "right" or "left"
                else
                    p.facing = dy > 0 and "down" or "up"
                end
                p.animTime = p.animTime + dt
                if p.animTime > 0.14 then
                    p.animTime = 0
                    p.animFrame = p.animFrame + 1
                end
            else
                p.animFrame = 0
                p.animTime = 0
            end
        end
    end
end

-- Pull the engine body positions back onto the player records. Must run after
-- Chispita.update and before Ship.updateOccupancy.
function Players.sync()
    for _, p in ipairs(State.players) do
        p.x = p.body.x + BODY_W / 2
        p.y = p.body.y + BODY_H / 2
    end
end

-- Runs once room occupancy is known for this frame.
function Players.interact(dt)
    for _, p in ipairs(State.players) do
        local c = p.ctrl
        p.repairing = false

        if p.station then
            -- stepping away
            if c.backPressed then
                Players.dismount(p)
            elseif p.room ~= p.station.room then
                -- shoved out of the bay somehow
                Players.dismount(p)
            end
        else
            -- mount whatever console we are standing at
            if c.actionPressed then
                local st = Ship.stationFor(p)
                if st then
                    if st.occupant and st.occupant ~= p then
                        p.hint = "P" .. st.occupant.index .. " IS ON THIS STATION"
                        p.hintTimer = 1.6
                    elseif st.module and Ship.isOffline(st.module) then
                        p.hint = "STATION DEAD - REPAIR THIS BAY (hold BACK)"
                        p.hintTimer = 2.2
                    else
                        Players.mount(p, st)
                    end
                else
                    p.hint = "NOTHING TO USE HERE"
                    p.hintTimer = 1.2
                end
            end

            -- hold BACK inside a damaged bay to patch it up
            if c.back and p.room and p.room.module then
                if Ship.repairTick(p.room, dt) then
                    p.repairing = true
                end
            end
        end

        p.hintTimer = math.max(0, p.hintTimer - dt)
    end
end

function Players.mount(p, st)
    st.occupant = p
    p.station = st
    st.blink = 0
    -- USE both mounts a console and is the station's primary action, so eat the
    -- press that got us here. Without this, walking up to the fabricator would
    -- buy whatever happened to be selected.
    st.suppressAction = true
end

function Players.dismount(p)
    if p.station then
        p.station.occupant = nil
        p.station = nil
    end
end

Players.BODY_W = BODY_W
Players.BODY_H = BODY_H

return Players
