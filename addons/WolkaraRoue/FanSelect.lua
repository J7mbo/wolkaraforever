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
