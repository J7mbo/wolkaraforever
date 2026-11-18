-- Corner skill wheel (iPhone Duo layout): the spinning wheel, chosen with Fan style; the
-- classic fan (FanClassic.lua) is the fan otherwise.
--
-- A ring of up to fifteen spells around the bottom-right corner, five in view at a time, and up
-- to four such fans with a button to switch between them. Drag a spell along the arc and the
-- ring follows the finger; flick it and it keeps spinning, slows down and settles on a spell,
-- with a bounce when it runs into either end. A tap without a drag casts the spell under the
-- finger.
--
-- Out of combat the real spell buttons are moved every frame, so what is drawn is exactly what
-- is tapped. In combat the game only lets secure code move spell buttons, and only in answer to
-- a click or a mouse wheel: each wheel tick turns the ring by one spell (the app turns a drag
-- on the ring into wheel ticks), and the switch is a secure click.
local _, ns = ...

local Fan = ns.Register("Corner fan (spinning)", {})
ns.FanSpin = Fan

-- Up to FANS fans share the corner, one on screen at a time, each with its own spells and its
-- own number of them (MIN_COUNT to COUNT). The switch button turns to the next fan that is on.
local COUNT, SHOWN = 15, 5
local FANS, MIN_COUNT = 4, 5
local FIRST, LAST = 9, 81
local STEP = (LAST - FIRST) / (SHOWN - 1)
local TOP_RING = 13
local TAB_ANGLE = 58
local SMALL = 0.72
local REACH = 0.22
local REACH_SMALL = 0.40
local SWIPE = 0.35
local HOLD = 3
-- How far past either end the ring may be pulled, as a share of the finger's travel.
local RUBBER = 0.35
-- Slots per second lost to friction while coasting, as an exponential rate.
local FRICTION = 3.2
-- Below this speed (slots per second) a coast stops and settles on the nearest spell.
local SETTLE_SPEED = 1.6
-- The settling spring: stiff enough to be quick, under-damped enough to bounce once.
local SPRING, DAMPING = 220, 15
-- How far past the visible arc a spell is still drawn while it fades, in slots.
local FADE = 0.6

local root, tab, jump, flash, holder, switch
local buttons = {}
-- Every fan's secure ring and buttons; `holder` and `buttons` are the fan on screen.
local holders, fanButtons = {}, {}
local active = 1
-- The fan on screen: how many spells it has, and the furthest it turns.
local count, most = COUNT, COUNT - SHOWN
local JUMP = 0.16
-- The fan switch: between the jump (out to JUMP) and the ring.
local SWITCH_RADIUS, SWITCH_ANGLE = 0.20, 45
-- The ring the app leaves to the wheel (FanSelect.lua saves it for the app), as shares of the
-- height: from just inside the fan switch out to the spells' outer edge and the reach around
-- them, so a thumb just beyond the spells is the camera stick again.
local RING_INNER, RING_MARGIN = 0.17, 0.75

local DEFAULTS = { enabled = true, size = 56, radius = 30, page = 1, seeded = false, style = "wheel" }
local DUO_LAYOUT = 2

local function Settings()
    local db = ns.db
    if type(db.fan) ~= "table" then db.fan = {} end
    local fan = db.fan
    for key, value in pairs(DEFAULTS) do
        if fan[key] == nil then fan[key] = value end
    end
    if type(fan.pages) ~= "table" then fan.pages = {} end
    if type(fan.offsets) ~= "table" then fan.offsets = {} end
    for page = 1, 2 do
        if type(fan.pages[page]) ~= "table" then fan.pages[page] = {} end
    end
    -- The two pages of ten became one ring of fifteen: the second page's first five spells move
    -- into the new slots 11-15 once, where those are still empty. Nothing is deleted, so an older
    -- build still finds its second page.
    if not fan.ring15 then
        fan.ring15 = true
        local ring, second = fan.pages[1], fan.pages[2]
        for index = 1, COUNT - 10 do
            if ring[10 + index] == nil and type(second[index]) == "table" then
                local entry = {}
                for key, value in pairs(second[index]) do entry[key] = value end
                ring[10 + index] = entry
            end
        end
    end
    if type(fan.fans) ~= "table" then fan.fans = {} end
    for index = 1, FANS do
        local entry = fan.fans[index]
        if type(entry) ~= "table" then entry = {}; fan.fans[index] = entry end
        if entry.on == nil then entry.on = index == 1 end
        entry.count = ns.Clamp(math.floor(tonumber(entry.count) or (index == 1 and COUNT or 10)), MIN_COUNT, COUNT)
        -- Fan 1 is the fan: the Skill fan switch turns all of them off.
        if index == 1 then entry.on = true end
        -- Fan 1 keeps the spells it always had; the others live beside them, so a preset
        -- (which copies fan.pages) carries every fan.
        local key = index == 1 and 1 or ("fan" .. index)
        if type(fan.pages[key]) ~= "table" then fan.pages[key] = {} end
        fan.offsets[index] = ns.Clamp(math.floor(tonumber(fan.offsets[index]) or 0), 0,
            math.max(0, entry.count - SHOWN))
    end
    fan.active = ns.Clamp(math.floor(tonumber(fan.active) or 1), 1, FANS)
    if not fan.fans[fan.active].on then fan.active = 1 end
    if fan.duoLayout ~= DUO_LAYOUT then
        fan.duoLayout = DUO_LAYOUT
        fan.size, fan.radius = DEFAULTS.size, DEFAULTS.radius
    end
    fan.size = ns.Clamp(tonumber(fan.size) or 56, 40, 80)
    fan.radius = ns.Clamp(tonumber(fan.radius) or 30, 22, 50)
    return fan
end

Fan.Settings = function() return Settings() end
Fan.FANS, Fan.MIN_COUNT, Fan.COUNT = FANS, MIN_COUNT, COUNT
local function Entries(index)
    local fan = Settings()
    return fan.pages[index == 1 and 1 or ("fan" .. index)]
end

function Fan:Enabled()
    return ns.DuoLayout() and type(ns.db.fan) == "table" and ns.db.fan.enabled == true
end

local function Seed(fan)
    if fan.seeded then return end
    fan.seeded = true
    local source = ns.db.free and ns.db.free.buttons
    if type(source) ~= "table" then return end
    local slot = 1
    for index = 1, ns.MAX_FREE do
        local stored = source[index]
        if slot > SHOWN then break end
        if type(stored) == "table" and type(stored.entry) == "table" and stored.entry.kind then
            local entry = {}
            for key, value in pairs(stored.entry) do entry[key] = value end
            fan.pages[1][slot] = entry
            slot = slot + 1
        end
    end
end

local function Icon(path, fallback)
    if GetFileIDFromPath and not GetFileIDFromPath(path) then return fallback end
    return path
end

local function Polar(radius, degrees)
    local angle = math.rad(degrees)
    return -radius * math.cos(angle), radius * math.sin(angle)
end

local function BuildSmall(name, template)
    local button = CreateFrame("Button", name, root, template)
    ns.Disc(button, "BACKGROUND", 0.05, 0.05, 0.08, 0.85, 4)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ns.Circle(button, button.icon)
    button.label = ns.Label(button, "GameFontNormal")
    button.label:SetPoint("CENTER", 0, 0)
    button.label:SetShadowOffset(1, -1)
    local highlight = ns.Disc(button, "HIGHLIGHT", 1, 1, 1, 0.18, 0)
    highlight:SetBlendMode("ADD")
    return button
end

function ns.HoldToSwap(button, onHeld, slot)
    local sweep = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    sweep:SetAllPoints()
    if sweep.SetHideCountdownNumbers then sweep:SetHideCountdownNumbers(true) end
    if sweep.SetSwipeColor then sweep:SetSwipeColor(1, 0.82, 0.2, 0.6) end
    if sweep.SetReverse then sweep:SetReverse(true) end
    local since, fromX, fromY
    local function Stop()
        since = nil
        if sweep.Clear then sweep:Clear() else sweep:Hide() end
    end
    button:HookScript("OnMouseDown", function()
        if InCombatLockdown() or ns.editing then return end
        button:SetAttribute("held", nil)
        since = 0
        fromX, fromY = GetCursorPosition()
        sweep:SetCooldown(GetTime(), HOLD)
    end)
    button:HookScript("OnMouseUp", Stop)
    button:HookScript("OnHide", Stop)
    button:HookScript("OnUpdate", function(self, elapsed)
        if not since then return end
        if InCombatLockdown() then Stop(); return end
        since = since + elapsed
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        if fromX and x and scale and scale > 0 and math.abs(x - fromX) + math.abs(y - fromY) > 48 * scale then Stop(); return end
        if since >= HOLD then
            Stop()
            if onHeld then onHeld() else self:SetAttribute("held", true) end
            if ns.EnterEditMode then ns.EnterEditMode(slot) else ns.SetEditing(true) end
        end
    end)
end

-- The secure side. In combat only this code may move the spell buttons, and it runs only in
-- answer to a press, a click or a wheel tick. Each snippet works on the fan's own ring, the
-- secure frame its buttons belong to (their owner).

-- A press starts with no drag recorded.
local DOWN = [=[
    owner:SetAttribute("dragmoved", nil)
]=]

-- Places every button for a whole-number offset: in view at its slot's precomputed position,
-- hidden otherwise. Arithmetic and attribute reads only.
local PLACE = [=[
    local offset = owner:GetAttribute("offset")
    local shown = owner:GetAttribute("shown")
    for index = 1, owner:GetAttribute("count") do
        local button = owner:GetFrameRef("b" .. index)
        local slot = index - offset
        if slot >= 1 and slot <= shown then
            button:ClearAllPoints()
            button:SetPoint("CENTER", owner, "BOTTOMRIGHT", owner:GetAttribute("x" .. slot), owner:GetAttribute("y" .. slot))
            button:Show()
        else
            button:Hide()
        end
    end
]=]

-- A click casts only after a tap: out of combat the insecure side marks a drag on the ring's
-- secure frame as it happens, and that click is dropped. No other check, so a tap can never be
-- swallowed.
local CLICK = [=[
    if owner:GetAttribute("dragmoved") then
        owner:SetAttribute("dragmoved", nil)
        return false
    end
]=]

-- The scroll wheel: each tick turns the ring by one spell, scrolling down for the later ones.
-- Like a click, a wheel tick is an event the game lets secure code answer in combat. The tick's
-- size arrives as "offset" (or "delta", depending on the client); either is read.
local WHEEL = [=[
    local tick = delta or offset
    if not tick or tick == 0 then return end
    local pos = owner:GetAttribute("offset") or 0
    local most = owner:GetAttribute("most")
    if tick < 0 then pos = pos + 1 else pos = pos - 1 end
    if pos < 0 then pos = 0 elseif pos > most then pos = most end
    if pos == owner:GetAttribute("offset") then return end
    owner:SetAttribute("offset", pos)
]=] .. PLACE

-- The switch button: the next fan that is on, in combat too. Only the fan rings are shown
-- and hidden; each keeps its own turn.
local SWITCH = [=[
    local fans = self:GetAttribute("fans") or 1
    local current = self:GetAttribute("active") or 1
    local nextFan = current
    for _ = 1, fans do
        nextFan = nextFan % fans + 1
        if self:GetAttribute("on" .. nextFan) then break end
    end
    self:SetAttribute("active", nextFan)
    for index = 1, fans do
        local ring = self:GetFrameRef("fan" .. index)
        if ring then
            if index == nextFan then ring:Show() else ring:Hide() end
        end
    end
]=]

-- ---------------------------------------------------------------------------------------
-- Motion. `pos` is the ring's rotation in slots: 0 shows spells 1-5, `most` the last five, and a
-- fraction is between two spells. Everything below is insecure and only draws.

local geometry = { outer = 100, size = 56 }
-- Out of combat, tell the secure click that the ring was dragged, so it does not cast.
local function MarkDragged()
    if not InCombatLockdown() and holder and not holder:GetAttribute("dragmoved") then
        holder:SetAttribute("dragmoved", true)
    end
end
local motion = { pos = 0, vel = 0, target = 0, mode = nil, samples = {} }

local function Nearest(value)
    return ns.Clamp(math.floor(value + 0.5), 0, most)
end

local function Rubber(raw)
    if raw < 0 then return raw * RUBBER end
    if raw > most then return most + (raw - most) * RUBBER end
    return raw
end

-- Where spell `index` sits for a rotation, and how visible it is there (1 inside the arc,
-- fading to 0 just beyond it).
local function Spot(index, pos)
    local angle = FIRST + (index - 1 - pos) * STEP
    local fade = 1
    if angle < FIRST then fade = 1 - (FIRST - angle) / (STEP * FADE)
    elseif angle > LAST then fade = 1 - (angle - LAST) / (STEP * FADE) end
    local x, y = Polar(geometry.outer, angle)
    return x, y, math.max(0, math.min(1, fade))
end

local function BaseAlpha(button)
    return (button:GetEntry() or ns.editing or ns.slotEditing) and 1 or 0.35
end

-- Draw the ring at `pos` by moving the real buttons. Out of combat only: in combat the secure
-- code has placed them.
local function Render(pos)
    if not root then return end
    local size = geometry.size
    for index = 1, COUNT do
        local x, y, fade = Spot(index, pos)
        if index > count then fade = 0 end
        local button = buttons[index]
        if not InCombatLockdown() then
            if fade > 0 then
                button:ClearAllPoints()
                button:SetPoint("CENTER", UIParent, "BOTTOMRIGHT", x, y)
                button:SetAlpha(BaseAlpha(button) * fade)
                button:Show()
            else
                -- Hidden spells keep their full look: in combat the game shows them again
                -- without this code, and a half-faded one would look greyed out.
                button:SetAlpha(BaseAlpha(button))
                button:Hide()
            end
        end
    end
end

-- Out of combat, make the settled offset the secure one too, so the next swipe in combat starts
-- from what is on screen.
local function Commit(offset)
    if InCombatLockdown() then return end
    holder:SetAttribute("offset", offset)
    motion.pos, motion.vel, motion.target = offset, 0, offset
    Render(offset)
    local db = ns.db and ns.db.fan
    if type(db) == "table" and type(db.offsets) == "table" then db.offsets[active] = offset end
end

local function Finish()
    local target = motion.target
    local changed = target ~= motion.settledAt
    motion.mode, motion.pos, motion.vel = nil, target, 0
    Commit(target)
    motion.settledAt = target
    if changed then ns.FanFeedback() end
end

local function SpringTo(target)
    motion.target, motion.mode = target, "spring"
end

-- After a wheel tick: out of combat glide from where the ring was to where the secure side put
-- it; in combat the secure side has already placed the buttons, so only the state follows.
function Fan.Wheeled()
    local offset = holder:GetAttribute("offset") or 0
    if offset == motion.settledAt and offset == motion.target then return end
    if InCombatLockdown() then
        motion.mode, motion.pos, motion.vel, motion.target, motion.settledAt = nil, offset, 0, offset, offset
        local db = ns.db and ns.db.fan
        if type(db) == "table" and type(db.offsets) == "table" then db.offsets[active] = offset end
        ns.FanFeedback()
    else
        motion.vel = 0
        SpringTo(offset)
    end
end

local function Sample(raw)
    local now = GetTime()
    local samples = motion.samples
    samples[#samples + 1] = { now, raw }
    while #samples > 2 and now - samples[1][1] > 0.12 do table.remove(samples, 1) end
end

-- Slots per second over the last tenth of a second of the drag; nothing if the finger had
-- stopped before it lifted.
local function Velocity()
    local samples = motion.samples
    local last, first = samples[#samples], samples[1]
    if not last or not first or last == first then return 0 end
    local span = last[1] - first[1]
    if span <= 0 or GetTime() - last[1] > 0.08 then return 0 end
    return (last[2] - first[2]) / span
end

local function Step(dt)
    if motion.mode == "coast" then
        motion.pos = motion.pos + motion.vel * dt
        motion.vel = motion.vel * math.exp(-FRICTION * dt)
        if motion.pos < 0 then
            SpringTo(0); ns.FanBump()
        elseif motion.pos > most then
            SpringTo(most); ns.FanBump()
        elseif math.abs(motion.vel) < SETTLE_SPEED then
            SpringTo(Nearest(motion.pos))
        end
    elseif motion.mode == "spring" then
        local accel = -SPRING * (motion.pos - motion.target) - DAMPING * motion.vel
        motion.vel = motion.vel + accel * dt
        motion.pos = motion.pos + motion.vel * dt
        if math.abs(motion.pos - motion.target) < 0.004 and math.abs(motion.vel) < 0.05 then Finish() end
    end
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, elapsed)
    if not motion.mode or not root or not root:IsShown() then return end
    if motion.mode == "drag" then
        local angle = ns.FanCursorAngle()
        if angle and motion.downAngle then
            local raw = motion.startPos + (motion.downAngle - angle) / STEP
            motion.raw = raw
            Sample(raw)
            motion.pos = Rubber(raw)
            if math.abs(raw - motion.startPos) >= SWIPE then MarkDragged() end
        end
    else
        local left = math.min(elapsed, 1 / 20)
        while left > 0 and motion.mode and motion.mode ~= "drag" do
            local dt = math.min(left, 1 / 240)
            Step(dt)
            left = left - dt
        end
    end
    Render(motion.pos)
end)

local function PressStarted()
    -- In combat the spells stay where the secure code put them and nothing is drawn over them:
    -- what is on screen is always what a tap casts. Wheel ticks turn the ring there.
    if InCombatLockdown() then motion.mode = nil; return end
    motion.startPos = motion.mode and motion.pos or (holder:GetAttribute("offset") or 0)
    motion.downAngle = ns.FanCursorAngle()
    motion.raw = motion.startPos
    motion.vel = 0
    wipe(motion.samples)
    motion.mode = "drag"
end

local function PressEnded()
    if motion.mode ~= "drag" then return end
    local raw = motion.raw or motion.startPos
    local moved = math.abs(raw - motion.startPos) >= SWIPE
    motion.vel = 0
    if not moved then
        SpringTo(Nearest(motion.startPos))
    else
        local speed = Velocity()
        if math.abs(speed) > SETTLE_SPEED then
            motion.vel, motion.mode = speed, "coast"
            if motion.pos < 0 or motion.pos > most then SpringTo(Nearest(motion.pos)) end
        else
            SpringTo(Nearest(raw))
        end
    end
end

-- Combat starts while the ring is still moving on its own: settle it now, while the game still
-- allows its buttons to be placed.
ns.On("PLAYER_REGEN_DISABLED", function()
    if not holder or not motion.mode then return end
    motion.target = motion.mode == "drag" and Nearest(motion.raw or motion.pos) or Nearest(motion.target or motion.pos)
    Finish()
end)

function Fan:Init()
    if ns.FanMode() ~= "spin" then return end
    ns.FanBuilt = "spin"
    ns.DuoLayout()
    local fan = Settings()
    Seed(fan)

    root = CreateFrame("Frame", "WolkaraMobileFan", UIParent)
    root:SetAllPoints(UIParent)
    root:SetFrameStrata("LOW")
    root:Hide()

    for fanIndex = 1, FANS do
        local ring = CreateFrame("Frame", "WolkaraMobileFanPage" .. fanIndex, root, "SecureHandlerBaseTemplate")
        ring:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT")
        ring:SetSize(2, 2)
        ring:EnableMouse(false)
        ring:Hide()
        holders[fanIndex] = ring
        fanButtons[fanIndex] = {}
        for index = 1, COUNT do
            local button = ns.CreateActionButton("WolkaraMobileFan" .. fanIndex .. "Skill" .. index, ring, fan.size,
                function() return Entries(fanIndex)[index] end,
                function(entry) Entries(fanIndex)[index] = entry end)
            SecureHandlerWrapScript(button, "OnMouseDown", ring, DOWN)
            SecureHandlerWrapScript(button, "OnClick", ring, CLICK)
            button:EnableMouseWheel(true)
            SecureHandlerWrapScript(button, "OnMouseWheel", ring, WHEEL)
            button:HookScript("OnMouseWheel", function() Fan.Wheeled() end)
            button:HookScript("OnMouseDown", PressStarted)
            button:HookScript("OnMouseUp", PressEnded)
            ring:SetFrameRef("b" .. index, button)
            fanButtons[fanIndex][index] = button
        end
    end
    holder, buttons = holders[1], fanButtons[1]

    -- The switch: shown when more than one fan is on.
    -- The switch: the small arrow button between the jump and the fan, where the old page
    -- button was, shown when more than one fan is on.
    switch = CreateFrame("Button", "WolkaraMobileFanSwitch", root, "SecureHandlerClickTemplate")
    switch:RegisterForClicks("AnyUp")
    for fanIndex = 1, FANS do switch:SetFrameRef("fan" .. fanIndex, holders[fanIndex]) end
    switch:SetAttribute("fans", FANS)
    switch:SetAttribute("active", 1)
    switch:SetAttribute("_onclick", SWITCH)
    ns.Disc(switch, "BACKGROUND", 0.05, 0.05, 0.08, 0.75, 0)
    switch.arrow = switch:CreateTexture(nil, "ARTWORK")
    switch.arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    switch.arrow:SetPoint("CENTER")
    switch.arrow:SetRotation(math.rad(135))
    local switchHighlight = ns.Disc(switch, "HIGHLIGHT", 1, 1, 1, 0.18, 0)
    switchHighlight:SetBlendMode("ADD")
    switch:HookScript("OnClick", function(self)
        Fan.Activate(self:GetAttribute("active") or 1)
        ns.FanFeedback()
    end)
    Fan.switch = switch

    jump = CreateFrame("Frame", "WolkaraMobileJumpArt", root)
    jump:EnableMouse(false)
    jump:SetFrameLevel(root:GetFrameLevel() + 1)
    jump.disc = ns.Disc(jump, "BACKGROUND", 0.06, 0.06, 0.09, 0.72, 0)
    jump.rim = ns.Disc(jump, "BORDER", 1, 0.82, 0.3, 0.18, 0)
    jump.rim:ClearAllPoints()
    jump.icon = jump:CreateTexture(nil, "ARTWORK")
    jump.icon:SetTexture(Icon("Interface\\Icons\\Ability_HeroicLeap", "Interface\\Icons\\Ability_Kick"))
    jump.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    jump.iconFrame = CreateFrame("Frame", nil, jump)
    jump.icon:SetParent(jump.iconFrame)
    ns.Circle(jump.iconFrame, jump.icon)
    jump.label = ns.Label(jump, "GameFontNormalSmall", "Jump")
    flash = CreateFrame("Frame", nil, root)
    flash:EnableMouse(false)
    flash:SetFrameLevel(root:GetFrameLevel() + 2)
    flash.disc = ns.Disc(flash, "BACKGROUND", 1, 0.82, 0.3, 1, 0)
    flash:SetAlpha(0)
    flash.anim = flash:CreateAnimationGroup()
    local rise = flash.anim:CreateAnimation("Alpha")
    rise:SetFromAlpha(0); rise:SetToAlpha(0.28); rise:SetDuration(0.07); rise:SetOrder(1)
    local fall = flash.anim:CreateAnimation("Alpha")
    fall:SetFromAlpha(0.28); fall:SetToAlpha(0); fall:SetDuration(0.25); fall:SetOrder(2)
    tab = BuildSmall("WolkaraMobileFanTab", "SecureActionButtonTemplate")
    tab:RegisterForClicks("AnyUp", "AnyDown")
    tab:SetAttribute("useOnKeyDown", true)
    tab:SetAttribute("type", "macro")
    tab:SetAttribute("macrotext", "/targetenemy")
    tab.icon:SetTexture(Icon("Interface\\Icons\\Ability_Hunter_SniperTraining", "Interface\\Icons\\Ability_Hunter_SniperShot"))
    tab.icon:SetAlpha(0.55)
    tab.label:SetText("Tab")
end

-- The fan on screen changed (the switch, in or out of combat, or a layout): point the drawing
-- code at its ring and buttons. Out of combat this also shows that ring and hides the others;
-- in combat the switch's secure code already has.
function Fan.Activate(index)
    if not holders[index] then index = 1 end
    active = index
    holder, buttons = holders[index], fanButtons[index]
    count = holder:GetAttribute("count") or COUNT
    most = holder:GetAttribute("most") or math.max(0, count - SHOWN)
    local offset = holder:GetAttribute("offset") or 0
    motion.mode, motion.pos, motion.vel, motion.target, motion.settledAt = nil, offset, 0, offset, offset
    local db = ns.db and ns.db.fan
    if type(db) == "table" then db.active = index end
    if not InCombatLockdown() then
        if switch then switch:SetAttribute("active", index) end
        for fanIndex, ring in ipairs(holders) do ring:SetShown(fanIndex == index) end
        Render(offset)
    end
    if Fan.Refresh then Fan:Refresh() end
end

function ns.FanFirstSlot()
    if not holder then return nil end
    return buttons[(holder:GetAttribute("offset") or 0) + 1]
end

function ns.FanLockIcon() end

-- The ring settled on a new spell: the page-turn sound, unless it is switched off. The gold
-- flash is kept for running into an end (FanBump).
function ns.FanFeedback()
    if PlaySound and Settings().sound ~= false then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN) or 836, "Master") end
end

-- The ring ran into one of its ends: a short flash, and the spring does the bounce.
function ns.FanBump()
    if flash and flash.anim then flash.anim:Stop(); flash.anim:Play() end
end

function ns.FanCursorAngle()
    if not GetCursorPosition then return nil end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if not x or not scale or scale == 0 then return nil end
    local dx, dy = UIParent:GetWidth() - x / scale, y / scale
    if dx <= 0 then return 90 end
    return math.deg(math.atan(dy / dx))
end

local function Place(button, x, y, size, reach)
    button:ClearAllPoints()
    button:SetSize(size, size)
    button:SetPoint("CENTER", UIParent, "BOTTOMRIGHT", x, y)
    local extra = math.floor(size * reach + 0.5)
    button:SetHitRectInsets(-extra, -extra, -extra, -extra)
end

function Fan:Layout()
    if not root or InCombatLockdown() then return end
    local fan = Settings()
    -- The classic fan was chosen: it takes over once the interface reloads.
    if not fan.enabled or not ns.DuoLayout() or ns.FanMode() ~= "spin" then Fan.ring = nil; root:Hide(); return end

    local height = UIParent:GetHeight()
    local outer = height * fan.radius / 100
    local top = height * (fan.radius + TOP_RING) / 100
    local size, small = fan.size, math.floor(fan.size * SMALL + 0.5)
    geometry.outer, geometry.size = outer, size
    motion.mode = nil
    local span = outer + size * 1.5
    local on = 0
    for fanIndex, ring in ipairs(holders) do
        local settings = fan.fans[fanIndex]
        local fanCount = settings.count
        local fanMost = math.max(0, fanCount - SHOWN)
        local offset = ns.Clamp(fan.offsets[fanIndex] or 0, 0, fanMost)
        fan.offsets[fanIndex] = offset
        ring:SetSize(span, span)
        ring:SetAttribute("shown", SHOWN)
        ring:SetAttribute("count", fanCount)
        ring:SetAttribute("most", fanMost)
        ring:SetAttribute("offset", offset)
        for slot = 1, SHOWN do
            local x, y = Polar(outer, FIRST + (slot - 1) * STEP)
            ring:SetAttribute("x" .. slot, x)
            ring:SetAttribute("y" .. slot, y)
        end
        for index, button in ipairs(fanButtons[fanIndex]) do
            button:SetAttribute("useOnKeyDown", false)
            local x, y = Polar(outer, FIRST + (index - 1 - offset) * STEP)
            Place(button, x, y, size, REACH)
            button:SetFrameLevel(root:GetFrameLevel() + 4)
            local slot = index - offset
            button:SetShown(index <= fanCount and slot >= 1 and slot <= SHOWN)
            ns.ApplyButton(button)
        end
        switch:SetAttribute("on" .. fanIndex, settings.on and true or nil)
        if settings.on then on = on + 1 end
    end

    local tx, ty = Polar(top, TAB_ANGLE)
    Place(tab, tx, ty, small, REACH_SMALL)
    tab:SetFrameLevel(root:GetFrameLevel() + 6)
    local radius = height * JUMP
    jump:ClearAllPoints()
    jump:SetSize(radius * 2, radius * 2)
    jump:SetPoint("CENTER", UIParent, "BOTTOMRIGHT", 0, 0)
    jump.rim:SetPoint("TOPLEFT", -2, 2)
    jump.rim:SetPoint("BOTTOMRIGHT", 2, -2)
    local iconSize = radius * 0.55
    jump.iconFrame:ClearAllPoints()
    jump.iconFrame:SetSize(iconSize, iconSize)
    jump.iconFrame:SetPoint("CENTER", UIParent, "BOTTOMRIGHT", -radius * 0.42, radius * 0.42)
    jump.icon:SetAllPoints(jump.iconFrame)
    local sx, sy = Polar(height * SWITCH_RADIUS, SWITCH_ANGLE)
    local switchSize = math.floor(size * 0.62 + 0.5)
    switch:ClearAllPoints()
    switch:SetSize(switchSize, switchSize)
    switch:SetPoint("CENTER", UIParent, "BOTTOMRIGHT", sx, sy)
    switch:SetHitRectInsets(-8, -8, -8, -8)
    switch.arrow:SetSize(switchSize * 1.15, switchSize * 1.15)
    switch:SetFrameLevel(root:GetFrameLevel() + 6)
    switch:SetShown(on > 1)
    local reach = (outer + size * 0.7) * 2
    flash:ClearAllPoints()
    flash:SetSize(reach, reach)
    flash:SetPoint("CENTER", UIParent, "BOTTOMRIGHT", 0, 0)
    jump.label:Hide()
    root:Show()
    Fan.ring = height > 0 and { inner = RING_INNER, outer = (outer + size * RING_MARGIN) / height } or nil
    Fan.Activate(fan.active)
end

local function EveryButton(fn)
    for _, list in ipairs(fanButtons) do
        for _, button in ipairs(list) do fn(button) end
    end
end

function Fan:Refresh()
    if not root then return end
    EveryButton(ns.RefreshButton)
    if not InCombatLockdown() then
        Render(motion.pos)
    else
        for _, button in ipairs(buttons) do button:SetAlpha(BaseAlpha(button)) end
    end
end

function Fan:SetEditing() self:Refresh(); ns.FanLockIcon() end

function Fan:CombatStarts()
    EveryButton(function(button)
        if button.suppressed then ns.ApplyButton(button) end
    end)
end

local function Each(fn)
    if not root then return end
    EveryButton(fn)
end

local ticker = CreateFrame("Frame")
local since = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < 0.2 or not root or not root:IsShown() then return end
    since = 0
    for _, button in ipairs(buttons) do
        if button:IsShown() then ns.UpdateState(button) end
    end
end)

local function Cooldowns() if ns.db then Each(ns.UpdateCooldown) end end
ns.On("SPELL_UPDATE_COOLDOWN", Cooldowns)
ns.On("BAG_UPDATE_COOLDOWN", Cooldowns)
ns.On("PLAYER_TARGET_CHANGED", Cooldowns)
ns.On("UNIT_AURA", function(unit) if unit == "player" or unit == "target" then Cooldowns() end end)
ns.On("BAG_UPDATE", function() if ns.db then Fan:Refresh() end end)
ns.On("SPELLS_CHANGED", function()
    if not ns.db then return end
    Fan:Refresh()
    if not InCombatLockdown() then Each(ns.ApplyButton) end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    if not (ns.db and holder and type(ns.db.fan) == "table") then return end
    for fanIndex, ring in ipairs(holders) do ns.db.fan.offsets[fanIndex] = ring:GetAttribute("offset") or 0 end
    local offset = holder:GetAttribute("offset") or 0
    if not motion.mode then motion.pos, motion.target, motion.settledAt = offset, offset, offset; Render(offset) end
end)

local function HideRight()
    if not ns.DuoLayout() then return end
    for index = 1, ns.MAX_FREE do
        local button = _G["WolkaraMobileFree" .. index]
        if button then button:Hide() end
    end
end
local baseLayout = Fan.Layout
function Fan:Layout()
    baseLayout(self)
    if root and not InCombatLockdown() and self:Enabled() then HideRight() end
end

local slash = SlashCmdList.WOLKARAMOBILE
SlashCmdList.WOLKARAMOBILE = function(message)
    local command, value = (message or ""):lower():match("^%s*fan%s*(%S*)%s*(%S*)")
    if not command or not ns.db or ns.FanMode() ~= "spin" then return slash(message) end
    if InCombatLockdown() then ns.Print("change the fan out of combat."); return end
    local fan = Settings()
    local number = tonumber(value)
    if command == "on" then fan.enabled = true
    elseif command == "off" then fan.enabled = false
    elseif command == "size" and number then fan.size = ns.Clamp(number, 40, 80)
    elseif command == "reach" and number then fan.radius = ns.Clamp(number, 22, 50)
    else
        ns.Print("/mobile fan on, off, size 40-80, reach 22-50. Now: " .. (fan.enabled and "on" or "off")
            .. ", size " .. fan.size .. ", reach " .. fan.radius .. ".")
        return
    end
    ns.MarkChanged(); ns.Layout(); ns.Refresh()
    ns.Print("fan " .. (fan.enabled and "on" or "off") .. ", size " .. fan.size .. ", reach " .. fan.radius .. ".")
end
