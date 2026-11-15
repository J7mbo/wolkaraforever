-- The Interface mobile add-on's two Duo arrangements - the corner skill fan (addons/WolkaraRoue/
-- Fan.lua) and the quick bar (addons/WolkaraRoue/QuickBar.lua) - run outside the game. What is
-- asserted: each one fills its own defaults, keeps every stored value inside the range the
-- settings page offers, repairs a value a hand-edited save put outside it, and reports itself
-- on only when the Duo layout is the chosen interface. The fan is a ring of up to fifteen
-- spells with up to four fans (fan 1 always on, each with 5-15 spells); a save from the two
-- pages of ten moves page 2's spells into slots 11-15 once. The quick bar also takes the free
-- slots a save from before pages had.
--
-- usage: luajit test_mobile_addon_duo.lua <addons/WolkaraRoue>

local directory = assert(arg[1], "usage: luajit test_mobile_addon_duo.lua <addons/WolkaraRoue>")

local duo = true
local modules = {}
local ns = {}
ns.db = {}
function ns.Register(name, module) modules[name] = module; return module end
function ns.Clamp(value, low, high)
    if not value or value ~= value then return low end
    if value < low then return low elseif value > high then return high end
    return value
end
function ns.DuoLayout() return duo end
function ns.Print() end
function ns.On() end
function ns.Guard(_, fn, ...) return fn(...) end
ns.MAX_FREE, ns.MAX_SLOTS, ns.MAX_WHEELS = 8, 6, 4
ns.T = function(text) return text end

-- A frame: anything it is asked to do answers nothing, as a stand-in, so a module's own
-- frame at load time cannot stop the suite.
local function Frame()
    local frame = {}
    function frame:GetFrameLevel() return 1 end
    function frame:CreateTexture() return Frame() end
    function frame:CreateFontString() return Frame() end
    setmetatable(frame, { __index = function(_, key)
        if type(key) == "string" and key:match("^%u") then return function() end end
    end })
    return frame
end
CreateFrame = function() return Frame() end
UIParent = Frame()
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

local function Load(file)
    assert(loadfile(directory .. "/" .. file))("WolkaraRoue", ns)
    return modules
end

Load("Fan.lua")
assert(ns.Fan, "Fan.lua registered no module")
local fan = ns.Fan.Settings()
assert(fan.enabled == true and fan.size == 56 and fan.radius == 30, "the fan's defaults are not what ships")
assert(fan.page == 1 and fan.style == "wheel" and fan.duoLayout == 2)
assert(fan.offsets[1] == 0 and fan.offsets[2] == 0, "a fresh fan starts off-centre")
assert(ns.Fan:Enabled() == true, "the fan is off in the Duo layout")
-- Four fans: the first on with fifteen spells, the others off with ten, each with its own
-- spells beside fan 1's (so a preset, which copies fan.pages, carries all of them).
assert(ns.Fan.FANS == 4 and ns.Fan.MIN_COUNT == 5 and ns.Fan.COUNT == 15)
assert(fan.fans[1].on == true and fan.fans[1].count == 15, "fan 1 is not the fifteen-spell ring")
for index = 2, 4 do
    assert(fan.fans[index].on == false and fan.fans[index].count == 10, "an extra fan is on, or not ten spells")
    assert(type(fan.pages["fan" .. index]) == "table", "an extra fan has nowhere to keep its spells")
end
assert(fan.active == 1, "a fresh fan does not start on fan 1")
-- A save a hand edit put outside the ranges the settings page offers is brought back inside.
ns.db.fan.size, ns.db.fan.radius, ns.db.fan.page = 500, 1, 7
ns.db.fan.offsets = { 99, -3, 4 }
ns.db.fan.fans[1].on, ns.db.fan.fans[1].count = false, 40
ns.db.fan.fans[2] = { on = true, count = 99 }
ns.db.fan.fans[3] = { count = 1 }
ns.db.fan.active = 9
fan = ns.Fan.Settings()
assert(fan.size == 80 and fan.radius == 22, "a stored fan size or radius escaped its range")
assert(fan.page == 1, "a stored page was kept")
assert(fan.fans[1].on == true and fan.fans[1].count == 15, "fan 1 was switched off or outgrew fifteen")
assert(fan.fans[2].on == true and fan.fans[2].count == 15, "fan 2's count escaped its range")
assert(fan.fans[3].on == false and fan.fans[3].count == 5, "fan 3's count escaped its range")
assert(fan.offsets[1] == 10 and fan.offsets[2] == 0 and fan.offsets[3] == 0, "a stored offset escaped its range")
assert(fan.active == 1, "a stored fan outside the four was kept")
-- The fan on screen being switched off falls back to fan 1.
ns.db.fan.active = 2
assert(ns.Fan.Settings().active == 2)
ns.db.fan.fans[2].on = false
assert(ns.Fan.Settings().active == 1, "a switched-off fan stayed on screen")
ns.db.fan.style = "star"
assert(ns.Fan.Settings().style == "wheel", "an unknown fan style was kept")
-- A save from the two pages of ten: page 2's first five spells fill the empty slots 11-15 once,
-- a slot already filled is kept, and page 2 itself is left for an older build.
ns.db.fan = { pages = { { [12] = { kind = "spell", id = 99 } },
    { { kind = "spell", id = 1 }, { kind = "spell", id = 2 }, { kind = "spell", id = 3 } } } }
fan = ns.Fan.Settings()
assert(fan.ring15 == true and fan.pages[1][11].id == 1 and fan.pages[1][12].id == 99 and fan.pages[1][13].id == 3,
    "page 2 did not move into slots 11-15")
assert(fan.pages[2][1].id == 1, "page 2 was deleted")
fan.pages[1][11] = nil
assert(ns.Fan.Settings().pages[1][11] == nil, "page 2 moved twice")
ns.db.fan.enabled = false
assert(ns.Fan:Enabled() == false, "a fan switched off still reports itself on")
duo = false
assert(ns.Fan:Enabled() == false, "the fan is on in the Standard interface")
duo = true
-- The cursor angle is not guessed at when the game cannot give the cursor.
assert(ns.FanCursorAngle() == nil, "the fan placed itself from a cursor it does not have")

ns.db = {}
Load("QuickBar.lua")
assert(ns.Quick, "QuickBar.lua registered no module")
local quick = ns.Quick.Settings()
assert(quick.enabled == true and quick.count == 5 and quick.size == 46 and quick.page == 1)
assert(quick.open == true and quick.fiveSlots == true, "the quick bar's defaults are not what ships")
ns.db.quick.count, ns.db.quick.size, ns.db.quick.page = 99, 1, 9
quick = ns.Quick.Settings()
assert(quick.count == 5 and quick.size == 36 and quick.page == 5, "a stored quick bar value escaped its range")
-- From one circle to five, as the settings page offers.
ns.db.quick.count = 0
assert(ns.Quick.Settings().count == 1, "a quick bar with no circles was kept")
ns.db.quick.count = 1
assert(ns.Quick.Settings().count == 1, "a one-circle quick bar was not kept")
-- Dragged in Customize, it keeps where it was put, and a save from before has it in place.
assert(type(ns.Quick.Settings().offset) == "table", "the quick bar has nowhere to keep its position")
-- A save from before the bar had pages: its slots become the first page, once.
ns.db.quick = { enabled = true, entries = { { kind = "spell", id = 11 }, { kind = "spell", id = 12 } } }
quick = ns.Quick.Settings()
assert(quick.pages[1][1].id == 11 and quick.pages[1][2].id == 12, "the old free slots were not taken as page one")
assert(quick.entries == nil, "the old free slots were left behind")
quick = ns.Quick.Settings()
assert(quick.pages[1][1].id == 11, "the old free slots were taken twice")
ns.db.quick.enabled = false
assert(ns.Quick:Enabled() == false, "a quick bar switched off still reports itself on")
ns.db.quick.enabled = true
duo = false
assert(ns.Quick:Enabled() == false, "the quick bar is on in the Standard interface")

print("mobile add-on Duo arrangements: the fan (four fans, 5-15 spells each, fan 1 always on, page 2 into slots 11-15 once) and the quick bar (1-5 circles, a kept position) fill their defaults, keep every stored value in range, repair a hand-edited one, take a pre-pages save once, and are on only in the Duo layout: PASS")
