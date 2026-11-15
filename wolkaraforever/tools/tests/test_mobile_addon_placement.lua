-- The Interface mobile add-on's window placement in the iPhone Duo layout (addons/WolkaraRoue/
-- Placement.lua), run outside the game. What is asserted: the game's windows keep the Screen
-- edges margin clear on both the left and the right - room for the Dynamic Island, on whichever
-- side it is - the margin follows the setting and stays inside the range the settings page
-- offers (0-15 % of the width), a window is never enlarged, and a fitted window is clamped to
-- the area left once the margin is taken.
--
-- usage: luajit test_mobile_addon_placement.lua <path to Placement.lua>

local path = assert(arg[1], "usage: luajit test_mobile_addon_placement.lua <Placement.lua>")

local ns = { db = {} }
local modules = {}
function ns.Register(name, module) modules[name] = module; return module end
function ns.Clamp(value, low, high)
    if not value or value ~= value then return low end
    if value < low then return low elseif value > high then return high end
    return value
end
function ns.On() end
ns.Fan = { Enabled = function() return true end }

local W, H = 1000, 460
local combat = false
InCombatLockdown = function() return combat end
UIParent = {
    GetEffectiveScale = function() return 1 end,
    GetWidth = function() return W end,
    GetHeight = function() return H end,
}

assert(loadfile(path))("WolkaraRoue", ns)
local Placement = assert(ns.Placement, "Placement.lua registered nothing")

-- Defaults: the large windows, and a 7 % margin.
local settings = Placement.Settings()
assert(settings.size == "large" and settings.edge == 7, "the window defaults are not what ships")

local function area(width, height)
    local scale, chosen = Placement.Best(W, H, width, height, 1)
    return scale, chosen
end

-- A small window keeps its own size and the margin on both sides.
local scale, chosen = area(300, 300)
assert(scale == 1, "a window that fits was resized")
assert(chosen.left == 70 and chosen.right == 70, "the Screen edges margin was not kept on both sides")

-- The margin follows the setting, and stays within 0-15 %.
settings.edge = 12
scale, chosen = area(300, 300)
assert(chosen.left == 120 and chosen.right == 120, "a changed margin was not used")
settings.edge = 50
scale, chosen = area(300, 300)
assert(chosen.left == 150 and chosen.right == 150, "a margin above 15 % was used")
settings.edge = -5
scale, chosen = area(300, 300)
assert(chosen.left >= 0 and chosen.left < 70, "a negative margin was used")
settings.edge = 7

-- A window wider than the room left is shrunk to fit between the margins, never enlarged.
scale = area(2000, 200)
assert(math.abs(scale - (W - 2 * 70) / 2000) < 1e-9, "a wide window does not fit between the margins")
assert(area(10, 10) == 1, "a tiny window was enlarged")

-- Fitting a window clamps it to the screen less that area, with its own scale.
local fitted = {}
local frame = {
    IsShown = function() return true end,
    IsProtected = function() return false end,
    GetNumPoints = function() return 1 end,
    GetWidth = function() return 300 end,
    GetHeight = function() return 300 end,
    GetScale = function() return fitted.scale or 1 end,
    GetParent = function() return UIParent end,
    GetName = function() return "GossipFrame" end,
    GetRight = function() return nil end,
    SetScale = function(_, value) fitted.scale = value end,
    SetClampedToScreen = function(_, on) fitted.clamped = on end,
    SetClampRectInsets = function(_, left, right, top, bottom) fitted.insets = { left, right, top, bottom } end,
}
ns.Windows = { Fit = function() error("the Duo layout used the Standard placement") end }
Placement:Init()
ns.Windows.Fit(frame)
assert(fitted.clamped == true and fitted.insets, "the window was not clamped")
assert(fitted.insets[1] == -70 and fitted.insets[2] == 70, "the clamp does not keep the margin clear")

print("mobile add-on window placement: Screen edges keeps the game's windows clear of the Dynamic Island on both sides, follows the setting within 0-15 %, never enlarges a window, and clamps a fitted one to the room left: PASS")
