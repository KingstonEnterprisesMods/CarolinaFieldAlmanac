-- Carolina Field Almanac: peanut freeze in the windrow, taken as a price (grade) loss (v0.25.11, team 2026-11-09)
-- Author: Kingston Enterprises
--
-- Sources (Rule #1):
--   NC State Extension, Jordan et al., "Digging Date and Freeze Damage" (2024), Nov 2023 freeze (31 F, then 29 F),
--     Lewiston and Rocky Mount NC: freeze-damaged kernels when dug 60 h before the freeze 3.8 %, 48 h 5.1 %, 14 h 6.0 %,
--     dug the day after the freeze 8.8 %. Every one is over the Seg II line.
--   NC State Peanut Information 2023 (Jordan), "Peanut Production Practices": do not dig when freezing temperatures are
--     expected; "at least three days (72 hours), and in many cases more than three days" between digging and frost.
--     NC State advised 96 h in 2023 -> high end 96 h (Rule #1).
--   Seminole Co. (UGA) Extension 2012 "Frosty Peanuts": freeze damage of 2.5 % or more = Segregation 2.
--   USDA FSA "Guidelines for Peanut Marketing Activity" (2014 crop): Seg. 2 & Seg. 3 loan rate = 35 % of the national
--     loan rate for the type (runner $354.86 -> $124.20 per ton). So a Seg 2 load keeps 35 % of its value.
-- Freeze line: 32 F ("freezing temperatures", NC State). The measured event was 31 F.
-- Game: peanuts are dug into a PEANUT_CUT windrow, then picked. FS25 has one price per fill type, so the value cut is
-- taken as fewer peanuts out of the picker (same money as a 35 % price).

CFAPeanut = {}
local P = CFAPeanut

P.FREEZE_F = 32         -- NC State: freezing temperatures
P.DUG_BEFORE_H = 96     -- dug up to 96 h before the freeze night (NC State 2023 advice, high end)
P.DUG_AFTER_H = 24      -- dug the day after the freeze (NC State 2023 trial: 8.8 %)
P.VALUE_KEPT = 0.35     -- USDA FSA: Seg 2 loan rate = 35 % of the national loan rate
P.KEEP_DAYS = 60        -- forget a dug field after 60 real days (picked long ago)
P.dug = {}              -- farmland id -> {day = game day dug, seg2 = bool, logged = bool}
P.lastFreezeDay = nil

local function log(fmt, ...) Logging.info("[CarolinaFieldAlmanac] peanuts: " .. fmt, ...) end

local function farmlandOf(field)
    if field == nil then return nil end
    if field.farmland ~= nil and field.farmland.id ~= nil then return field.farmland.id end
    if type(field.getFarmland) == "function" then
        local ok, fl = true, field.getFarmland(field)
        if ok and fl ~= nil and fl.id ~= nil then return fl.id end
    end
    return nil
end

local function notice(msg)
    if CarolinaFieldCure ~= nil and CarolinaFieldCure.addNotice ~= nil then
        CarolinaFieldCure.addNotice("warning", msg)
    end
end

-- called by the crops scan when a harvest-ready peanut field is dug (state left harvest-ready)
function P.onDug(field, id, day, scale)
    local fl = farmlandOf(field)
    if fl == nil then return end
    local e = {day = day, seg2 = false}
    if P.lastFreezeDay ~= nil and (day - P.lastFreezeDay) * (scale or 1) * 24 <= P.DUG_AFTER_H then
        e.seg2 = true
        e.why = "dug the day after a freeze"
    end
    P.dug[fl] = e
    log("farmland %d (field %s) dug on day %d%s", fl, tostring(id), day, e.seg2 and " - Seg 2 (dug right after a freeze)" or "")
    if e.seg2 then notice(string.format("Farmland %d peanuts dug after a freeze - Seg 2 grade, 35 %% of value", fl)) end
end

-- once a game day, with the day's low
function P.onDay(day, loF, scale)
    scale = scale or 1
    for fl, e in pairs(P.dug) do
        if (day - e.day) * scale > P.KEEP_DAYS then P.dug[fl] = nil end
    end
    if loF == nil or loF > P.FREEZE_F then return end
    P.lastFreezeDay = day
    for fl, e in pairs(P.dug) do
        local ageH = (day - e.day) * scale * 24
        if not e.seg2 and ageH >= 0 and ageH <= P.DUG_BEFORE_H then
            e.seg2 = true
            e.why = string.format("in the windrow at %.0f F, dug %.0f h before", loF, ageH)
            log("farmland %d: freeze %.0f F with peanuts dug %.0f h before -> Seg 2, 35 %% of value (NC State 2024; USDA FSA)", fl, loF, ageH)
            notice(string.format("Farmland %d: peanuts froze in the windrow (%.0f F) - Seg 2 grade, 35 %% of value", fl, loF))
        end
    end
end

-- picker hook: Seg 2 windrows give 35 % of the peanuts (the value cut)
function P.installPickupHook()
    if P.hooked or Cutter == nil or Cutter.processPickupCutterArea == nil then return end
    P.hooked = true
    Cutter.processPickupCutterArea = Utils.overwrittenFunction(Cutter.processPickupCutterArea, function(self, superFunc, workArea, dt, ...)
        local a, b = superFunc(self, workArea, dt, ...)
        local ok, err = true, (function()
            if not self.isServer or a == nil or a <= 0 or next(P.dug) == nil then return end
            local spec = self.spec_cutter
            local wp = spec ~= nil and spec.workAreaParameters or nil
            if wp == nil or (wp.lastLiters or 0) <= 0 or spec.currentInputFillType == nil then return end
            if P.cutIndex == nil and g_fillTypeManager ~= nil then
                P.cutIndex = g_fillTypeManager:getFillTypeIndexByName("PEANUT_CUT") or -1
            end
            if spec.currentInputFillType ~= P.cutIndex then return end
            local x, _, z = getWorldTranslation(workArea.start)
            local fl = g_farmlandManager ~= nil and g_farmlandManager:getFarmlandIdAtWorldPosition(x, z) or nil
            local e = fl ~= nil and P.dug[fl] or nil
            if e == nil or not e.seg2 then return end
            local before = wp.lastLiters
            wp.lastLiters = before * P.VALUE_KEPT
            P.lostL = (P.lostL or 0) + (before - wp.lastLiters)
            if not e.logged then
                e.logged = true
                log("farmland %d: picking Seg 2 peanuts (%s) - 35 %% of value kept", fl, e.why or "freeze")
            end
        end)()
        if not ok and not P.errLogged then
            P.errLogged = true
            Logging.error("[CarolinaFieldAlmanac] peanut pickup hook: %s", tostring(err))
        end
        return a, b
    end)
end

function P.save(xml, root)
    local i = 0
    for fl, e in pairs(P.dug) do
        local k = string.format("%s.peanutDug(%d)", root, i)
        xml:setInt(k .. "#farmland", fl)
        xml:setInt(k .. "#day", e.day)
        xml:setBool(k .. "#seg2", e.seg2 == true)
        if e.why ~= nil then xml:setString(k .. "#why", e.why) end
        i = i + 1
    end
    if P.lastFreezeDay ~= nil then xml:setInt(root .. "#peanutLastFreezeDay", P.lastFreezeDay) end
end

function P.load(xml, root)
    P.dug = {}
    xml:iterate(root .. ".peanutDug", function(_, k)
        local fl, d = xml:getInt(k .. "#farmland"), xml:getInt(k .. "#day")
        if fl ~= nil and d ~= nil then
            P.dug[fl] = {day = d, seg2 = xml:getBool(k .. "#seg2", false), why = xml:getString(k .. "#why")}
        end
    end)
    P.lastFreezeDay = xml:getInt(root .. "#peanutLastFreezeDay")
end
