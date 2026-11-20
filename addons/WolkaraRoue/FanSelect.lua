-- Which corner fan the iPhone Duo layout uses: the classic fan (FanClassic.lua), two pages of
-- ten with a flip button, or the spinning wheel (Fan.lua), up to four fans of up to fifteen
-- spells that also turn in combat. Fan style on the Combat page chooses; the classic fan is the
-- default. Both files load, but only the chosen one builds its frames, so a change takes effect
-- when the interface reloads (closing the settings saves and reloads).
--
-- ns.Fan is the chosen fan for everything outside these files (settings, window placement, the
-- Duo menu): a stand-in that hands each call to whichever fan is on.
local _, ns = ...

function ns.FanMode()
    local db = ns.db
    local fan = type(db) == "table" and db.fan
    return (type(fan) == "table" and fan.mode == "spin") and "spin" or "classic"
end

local function Active()
    return ns.FanMode() == "spin" and ns.FanSpin or ns.FanClassic
end

ns.Fan = setmetatable({}, {
    __index = function(proxy, key)
        local fan = Active()
        local value = fan and fan[key]
        if type(value) ~= "function" then return value end
        return function(first, ...)
            if first == proxy then first = fan end
            return value(first, ...)
        end
    end,
})

-- The ring the app leaves to the spinning wheel. The app cannot see the game's frames, so the
-- wheel's ring - inner and outer edge as shares of the screen height from the bottom-right
-- corner, following Reach and the spell size - is saved for it here, in an account-wide saved
-- variable the game writes when the interface reloads (closing the settings) or the player logs
-- out. Floating sticks leave that ring to the game and a drag in it turns the wheel; with the
-- classic fan, the fan off or another layout, wheel is false and the corner is the sticks'.
local function Share(value) return math.floor(value * 1000 + 0.5) / 1000 end
local Ring = ns.Register("Spell wheel ring", {})
function Ring:Layout()
    local ring = ns.FanMode() == "spin" and ns.FanSpin and ns.FanSpin.ring
    if ring then
        WolkaraRoueTouch = { version = 1, wheel = true, inner = Share(ring.inner), outer = Share(ring.outer) }
    else
        WolkaraRoueTouch = { version = 1, wheel = false }
    end
end
