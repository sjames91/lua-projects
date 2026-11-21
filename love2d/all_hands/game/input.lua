-- Four players on one keyboard, or on gamepads if they are plugged in.
--
-- Every crew member has exactly six controls, and they mean different things
-- depending on whether you are walking or mounted at a console:
--
--            walking                      mounted
--   dpad     move around the ship         operate the station
--   ACTION   mount the console you are    the station's primary action
--            standing at                  (fire / buy / brace / overdrive)
--   BACK     hold to repair this bay      step away from the console

local Input = {}

Input.KEYMAPS = {
    { up = { "w" },              down = { "s" },            left = { "a" },            right = { "d" },
      action = { "q" },          back = { "e" },
      hint = "WASD  Q=use  E=back" },

    { up = { "t" },              down = { "g" },            left = { "f" },            right = { "h" },
      action = { "r" },          back = { "y" },
      hint = "TFGH  R=use  Y=back" },

    { up = { "i" },              down = { "k" },            left = { "j" },            right = { "l" },
      action = { "u" },          back = { "o" },
      hint = "IJKL  U=use  O=back" },

    { up = { "up", "kp8" },      down = { "down", "kp5" },  left = { "left", "kp4" },  right = { "right", "kp6" },
      action = { "rshift", "kp0" }, back = { "rctrl", "kp7" },
      hint = "ARROWS  RSHIFT=use  RCTRL=back" },
}

local REPEAT_DELAY = 0.34
local REPEAT_RATE  = 0.11

local function anyDown(keys)
    for _, k in ipairs(keys) do
        if love.keyboard.isDown(k) then return true end
    end
    return false
end

local joysticks = {}

function Input.refreshJoysticks()
    joysticks = {}
    for _, j in ipairs(love.joystick.getJoysticks()) do
        if j:isGamepad() then table.insert(joysticks, j) end
    end
end

function Input.newController(index)
    return {
        index = index,
        up = false, down = false, left = false, right = false,
        action = false, back = false,
        upPressed = false, downPressed = false, leftPressed = false, rightPressed = false,
        upRepeat = false, downRepeat = false, leftRepeat = false, rightRepeat = false,
        actionPressed = false, backPressed = false,
        backHeldTime = 0, actionHeldTime = 0,
        timers = { up = 0, down = 0, left = 0, right = 0 },
        usingGamepad = false,
    }
end

local DIRS = { "up", "down", "left", "right" }

function Input.update(controllers, dt)
    for i, c in ipairs(controllers) do
        local map = Input.KEYMAPS[i]
        local joy = joysticks[i]

        local raw = { up = false, down = false, left = false, right = false }

        if map then
            raw.up    = anyDown(map.up)
            raw.down  = anyDown(map.down)
            raw.left  = anyDown(map.left)
            raw.right = anyDown(map.right)
        end
        local act  = map and anyDown(map.action) or false
        local back = map and anyDown(map.back) or false

        c.usingGamepad = false
        if joy then
            local ax = joy:getGamepadAxis("leftx") or 0
            local ay = joy:getGamepadAxis("lefty") or 0
            local dz = 0.35
            local gUp    = joy:isGamepadDown("dpup")    or ay < -dz
            local gDown  = joy:isGamepadDown("dpdown")  or ay >  dz
            local gLeft  = joy:isGamepadDown("dpleft")  or ax < -dz
            local gRight = joy:isGamepadDown("dpright") or ax >  dz
            local gAct   = joy:isGamepadDown("a") or joy:isGamepadDown("rightshoulder")
            local gBack  = joy:isGamepadDown("b")
            if gUp or gDown or gLeft or gRight or gAct or gBack then c.usingGamepad = true end
            raw.up, raw.down = raw.up or gUp, raw.down or gDown
            raw.left, raw.right = raw.left or gLeft, raw.right or gRight
            act, back = act or gAct, back or gBack
        end

        for _, d in ipairs(DIRS) do
            local held = raw[d]
            c[d .. "Pressed"] = held and not c[d]
            -- edge, then auto-repeat, so power bars and menus step cleanly
            if held then
                if not c[d] then
                    c.timers[d] = REPEAT_DELAY
                    c[d .. "Repeat"] = true
                else
                    c.timers[d] = c.timers[d] - dt
                    if c.timers[d] <= 0 then
                        c.timers[d] = REPEAT_RATE
                        c[d .. "Repeat"] = true
                    else
                        c[d .. "Repeat"] = false
                    end
                end
            else
                c[d .. "Repeat"] = false
            end
            c[d] = held
        end

        c.actionPressed = act and not c.action
        c.backPressed   = back and not c.back
        c.actionHeldTime = act and (c.actionHeldTime + dt) or 0
        c.backHeldTime   = back and (c.backHeldTime + dt) or 0
        c.action, c.back = act, back
    end
end

return Input
