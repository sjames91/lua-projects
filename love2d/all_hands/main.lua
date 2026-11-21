-- ALL HANDS
-- A four-player split-screen prototype built on the Chispita engine.
--
-- The engine in Engine/ is a byte-for-byte copy of the one in
-- fish_and_the_five_fountains and is never modified. Everything in game/ sits
-- on top of it: Chispita owns the interior sprites, their rect collision and
-- the camera; the game layer owns the ship, the stations and the exterior.

require("Engine/Chispita")

Mode       = "topdown"
Friction   = 0.72          -- engine global: how fast interior velocity bleeds off
Debug_mode = false

local Sprite   = require("Engine/Chispita_sprite")
local State    = require("game/state")
local Assets   = require("game/assets")
local Ship     = require("game/ship")
local Space    = require("game/space")
local Players  = require("game/players")
local Stations = require("game/stations")
local Render   = require("game/render")
local Input    = require("game/input")

local CREW = 4

local function newGame()
    -- wipe the engine sprite list, including crew bodies from the last run
    for i = #Sprite.sprites, 1, -1 do
        table.remove(Sprite.sprites, i)
    end

    State.players = {}
    State.log    = {}
    State.scrap  = 70
    State.kills  = 0
    State.banner = nil
    State.bannerTimer = 0
    State.phase  = "lull"

    Ship.reset()
    Space.reset()
    Players.spawn(CREW)

    Camera.target = nil      -- we drive the engine camera per viewport instead
    Camera.x, Camera.y = 0, 0

    State.say("ALL HANDS: take your stations")
    State.showBanner("ALL HANDS", 2.2)
end

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.math.setRandomSeed(os.time())
    Assets.load()
    Render.load()
    Input.refreshJoysticks()
    newGame()

    for _, a in ipairs(arg or {}) do
        if a == "autotest" then
            NEWGAME = newGame            -- so the harness can exercise restart
            AUTOTEST = require("autotest")
            AUTOTEST.start()
        end
    end
end

function love.joystickadded()   Input.refreshJoysticks() end
function love.joystickremoved() Input.refreshJoysticks() end

function love.update(dt)
    dt = math.min(dt, 1 / 30)   -- the engine integrates per frame; cap the spikes

    if AUTOTEST then AUTOTEST.tick(dt) end

    local controllers = {}
    for i, p in ipairs(State.players) do controllers[i] = p.ctrl end
    Input.update(controllers, dt)

    if Render.showHelp or State.paused then return end

    State.bannerTimer = math.max(0, State.bannerTimer - dt)
    for i = #State.log, 1, -1 do
        State.log[i].t = State.log[i].t - dt
        if State.log[i].t <= 0 then table.remove(State.log, i) end
    end

    if State.phase == "dead" then
        Space.update(dt * 0.25)   -- keep the wreck drifting
        return
    end

    Players.applyMovement(dt)    -- set body velocities from the dpads
    Chispita.update(dt)          -- engine: integrate + resolve interior collisions
    Players.sync()               -- bodies -> player records
    Ship.updateOccupancy()       -- who is standing in which bay
    Players.interact(dt)         -- mount / dismount / repair
    Stations.update(dt)          -- mounted crew operate their consoles
    Ship.update(dt)              -- power, shields, charge, heat
    Space.update(dt)             -- the world outside the hull
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "f1" or (Render.showHelp and (key == "return" or key == "space")) then
        Render.showHelp = not Render.showHelp
    elseif key == "f2" then
        State.paused = not State.paused
    elseif key == "f3" then
        State.debug = not State.debug
        Debug_mode  = State.debug
    elseif key == "f4" then
        State.godmode = not State.godmode
        State.say(State.godmode and "GODMODE ON - hull/bays take no damage" or "GODMODE OFF",
            State.godmode and require("game/palette").warn or nil)
    elseif key == "f5" then
        newGame()
    elseif key == "f10" then
        local n, path = Assets.export()
        State.say(("exported %d textures to %s"):format(n, path))
    end
    -- Global shortcuts are function keys only: every letter on the keyboard is
    -- already somebody's walk or use button.
end

function love.draw()
    Render.draw()
end
