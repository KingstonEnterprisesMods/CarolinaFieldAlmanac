-- Carolina Field Almanac: silage (v0.29.0, team 2026-11-14)
-- Author: Kingston Enterprises
--
-- 1. Chopping moisture readout + warning (no loss: no source gives a % loss curve for chopping too wet / too dry).
--    Penn State Extension, "From Harvest to Feed: Understanding Silage Management", Table 4: horizontal (bunker) silo
--    65-70 % moisture for alfalfa, grass and corn silage. Avoid over 70 % (clostridia above 70-72 %, seepage above
--    70-75 %) and under 40 % (heat damage). Oregon State Forage Information System: under 40 % moisture heats, fire risk.
--    Grass / alfalfa: moisture of the Field Cure windrow cells being picked up (pickup header or loader wagon).
-- 2. Corn chopped early (team: whole-plant moisture, not milk line - the milk line heat-unit sources disagree:
--    K-State MF3305 575 GDD dent to maturity, Purdue 337-360, UW-Madison 200-240, Iowa State PMR 1009 250).
--    Penn State Extension, "Corn Silage Production and Management", Table 3 (65 % moisture basis):
--      early dent 73 % moisture 16.0 t/A; 1/2 milkline 66 % 18.0; 3/4 milkline 63 % 18.3; no milkline 60 % 18.0.
--    Moisture = 73 % at R5 (early dent), drying 0.75 points a real day (Penn State: 0.50-0.75, high end, Rule #1).
--    Yield kept = table yield / 18.3, straight line between rows, held at the end rows.
--    The base game gives the same chaff at any stage it lets you chop (maize.xml litersPerSqm 0.935), so no double count.
-- 3. Feed-out face loss on opened bunker silos.
--    Holmes & Muck 2007, as drawn in Borreani et al. 2018, J. Dairy Sci. 101:3952, Fig. 13: DM loss at the silo face
--    by feed-out rate, bulk density 641 kg/m3 (team: Penn State ideal bunker density, about 40 lb/ft3).
--    Points read off the figure (m/week, % DM lost). Below 0.18 m/wk and above 2.14 m/wk the end values are held.
--    Removal rate: face meters removed over the last game month (game month = real month, team) / weeks in it.
--    Recommended minimum removal rate (notice only): Borreani & Tabacco 2012a, in Borreani 2018 Fig. 15:
--      rate (m/wk) = 0.0014 T^2 + 0.0133 T + 1.079, T = seasonal mean temperature (C) - Table 6 uses
--      Nov-Mar (winter) and May-Sep (summer) means; April and October use that month's mean.
--    The game only ferments a pile that is packed to 100 % and covered, so the "no cover" losses never happen.

CFASilage = {}
local S = CFASilage

S.TARGET_LO, S.TARGET_HI = 0.65, 0.70     -- Penn State Table 4, horizontal silo
S.WET_WARN, S.DRY_WARN = 0.70, 0.40       -- Penn State: avoid over 70 % and under 40 %
S.CORN_R5_MOIST = 0.73                    -- Penn State Table 3, early dent
S.CORN_DRYDOWN = 0.0075                   -- Penn State 0.50-0.75 points a day, high end (team 2026-11-14)
S.CORN_TABLE = {{0.73, 16.0}, {0.66, 18.0}, {0.63, 18.3}, {0.60, 18.0}}
S.CORN_TOP = 18.3
S.FEEDOUT_641 = {{0.18, 18.0}, {0.22, 14.4}, {0.27, 12.0}, {0.31, 10.3}, {0.36, 9.0}, {0.53, 6.0}, {0.71, 4.5}, {0.89, 3.6},
                 {1.07, 3.0}, {1.25, 2.5}, {1.42, 2.2}, {1.60, 2.0}, {1.78, 1.8}, {1.96, 1.6}, {2.14, 1.5}}
S.WARN_GAP_MS = 120000                    -- the same warning again at most every 2 minutes (real time)

S.bunkers = {}      -- key -> {open = day opened, full = liters when opened, hist = {{day, fill, scale}}, spoiled, debt, warnPeriod}
S.lastWarn = {}
S.chopLog = {}      -- field id -> last logged moisture band

local function log(fmt, ...) Logging.info("[CarolinaFieldAlmanac] silage: " .. fmt, ...) end

local function notice(kind, msg)
    if CarolinaFieldCure ~= nil and CarolinaFieldCure.addNotice ~= nil then CarolinaFieldCure.addNotice(kind, msg) end
end

local function on(key)
    return CFACrops == nil or CFACrops.on == nil or CFACrops.on(key)
end

local function pct(m) return math.floor(m * 100 + 0.5) end

-- straight line through a table of {x, y} (x falling or rising), end values held
local function interp(t, x)
    local n = #t
    local rising = t[n][1] > t[1][1]
    if (rising and x <= t[1][1]) or (not rising and x >= t[1][1]) then return t[1][2] end
    if (rising and x >= t[n][1]) or (not rising and x <= t[n][1]) then return t[n][2] end
    for i = 1, n - 1 do
        local a, b = t[i], t[i + 1]
        if (x - a[1]) * (x - b[1]) <= 0 then
            local f = (x - a[1]) / (b[1] - a[1])
            return a[2] + f * (b[2] - a[2])
        end
    end
    return t[n][2]
end
S.interp = interp

-- ------------------------------------------------------------------ chopping moisture readout

function S.moistureText(what, m)
    local s = string.format("Chopping %s: %d %% moisture (bunker target %d-%d %%, Penn State)", what, pct(m), pct(S.TARGET_LO), pct(S.TARGET_HI))
    if m > S.WET_WARN then
        s = s .. " - TOO WET"
    elseif m < S.DRY_WARN then
        s = s .. " - TOO DRY"
    end
    return s
end

function S.warnFor(key, what, m)
    local band = (m > S.WET_WARN and "wet") or (m < S.DRY_WARN and "dry") or nil
    if band == nil then return end
    local now = g_time or 0
    local k = key .. band
    if S.lastWarn[k] ~= nil and now - S.lastWarn[k] < S.WARN_GAP_MS then return end
    S.lastWarn[k] = now
    if band == "wet" then
        notice("warning", string.format("%s is %d %% moisture - over 70 %% it leaks and can spoil in the silo (Penn State). Target 65-70 %%.", what, pct(m)))
    else
        notice("warning", string.format("%s is %d %% moisture - under 40 %% it heats in the silo and can catch fire (Penn State, Oregon State). Target 65-70 %%.", what, pct(m)))
    end
end

function S.showReadout(text)
    if g_currentMission ~= nil and g_currentMission.addExtraPrintText ~= nil then
        g_currentMission.addExtraPrintText(g_currentMission, text)
    end
end

-- grass / alfalfa windrow picked up for silage: moisture of the Field Cure cells under the pickup
function S.onWindrowPickup(vehicle, workArea)
    local CFC = CarolinaFieldCure
    if CFC == nil or not CFC.started or CFC.getNodeArea == nil or CFC.getAverageMoisture == nil then return end
    local sx, sz, wx, wz, hx, hz = CFC.getNodeArea(workArea)
    if sx == nil then return end
    local m = CFC.getAverageMoisture(sx, sz, wx, wz, hx, hz)
    if m == nil then return end
    S.showReadout(S.moistureText("windrow", m))
    S.warnFor("windrow" .. tostring(vehicle.rootNode or vehicle.id or ""), "This windrow", m)
end

-- ------------------------------------------------------------------ corn whole-plant moisture and yield

-- whole-plant moisture (fraction) of a corn field, or nil if it is not known
-- returns m, beforeDent
function S.cornMoisture(rec, crop)
    if rec == nil or crop == nil or crop.stageIndex == nil or crop.stageIndex["R5"] == nil then return nil end
    -- v0.29.1: a crop that was already growing when CFA first saw it and could not be backfilled (no planting date or no
    -- daily normals for the station, e.g. Europe) has a clock that started late - its dent day is not known
    if rec.backfill == "none" then return nil end
    if rec.r5Days == nil then
        local r5 = crop.stages[crop.stageIndex["R5"]].dd
        if r5 ~= nil and (rec.dd or 0) < r5 then return S.CORN_R5_MOIST, true end
        return nil   -- past dent before v0.29 tracked it: not known
    end
    local days = math.max(0, (rec.days or 0) - rec.r5Days)
    return math.max(0, S.CORN_R5_MOIST - S.CORN_DRYDOWN * days), false
end

function S.cornYieldKept(m)
    return interp(S.CORN_TABLE, m) / S.CORN_TOP
end

-- called from the crops harvest hook when a forage harvester header cuts a crop on a tracked field
function S.cornChopFactor(id, rec, crop)
    if CFACrops == nil or crop == nil or crop ~= CFACrops.crops["MAIZE"] then return 1 end
    local m, before = S.cornMoisture(rec, crop)
    if m == nil then
        S.showReadout("Chopping corn: moisture not known (CFA did not see this crop reach dent) - no yield change")
        return 1
    end
    local what = before and "corn (before dent, 73 % or wetter)" or "corn"
    S.showReadout(S.moistureText(what, m))
    local P = CarolinaFieldCure
    if P ~= nil and CFACrops.fieldOwner ~= nil then P.noticeFarm = CFACrops.fieldOwner(id) end   -- v0.30: the field's farm
    S.warnFor("corn" .. tostring(id), "This corn", m)
    if P ~= nil then P.noticeFarm = nil end
    local kept = on("silage") and S.cornYieldKept(m) or 1
    local band = string.format("%d", pct(m))
    if S.chopLog[id] ~= band then
        S.chopLog[id] = band
        log("field %s corn chopped at %d %% whole-plant moisture%s: keeps %.1f %% of top silage yield (Penn State Table 3)%s",
            tostring(id), pct(m), before and " (before dent)" or "", kept * 100, on("silage") and "" or " - switched off")
    end
    return kept
end

-- ------------------------------------------------------------------ bunker feed-out face

function S.feedoutLossPct(rateMWk)
    return interp(S.FEEDOUT_641, rateMWk)
end

function S.minRateMWk(T)
    return 0.0014 * T * T + 0.0133 * T + 1.079
end

-- seasonal mean temperature (C) for a real month (Borreani 2018 Table 6 seasons)
function S.seasonMeanC(month)
    local W = CFAWeather
    if W == nil or W.monthMeanC == nil or month == nil then return nil end
    local months
    if month >= 5 and month <= 9 then months = {5, 6, 7, 8, 9}
    elseif month >= 11 or month <= 3 then months = {11, 12, 1, 2, 3}
    else months = {month} end
    local sum, n = 0, 0
    for _, m in ipairs(months) do
        local t = W.monthMeanC(m)
        if t ~= nil then sum = sum + t n = n + 1 end
    end
    return n > 0 and sum / n or nil
end

local function bunkerKey(b)
    local a = b.bunkerSiloArea
    if a == nil or a.sx == nil then return nil end
    return string.format("%.0f_%.0f", a.sx, a.sz)
end

local function bunkerLength(b)
    local a = b.bunkerSiloArea
    if a == nil or a.dhx == nil then return nil end
    return math.sqrt(a.dhx * a.dhx + (a.dhy or 0) * (a.dhy or 0) + a.dhz * a.dhz)
end

function S.eachBunker(fn)
    local ps = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if ps == nil or ps.placeables == nil then return end
    for _, p in pairs(ps.placeables) do
        local spec = p.spec_bunkerSilo
        if spec ~= nil and spec.bunkerSilo ~= nil then fn(spec.bunkerSilo) end
    end
end

-- take spoiled silage out of the opened part of the bunker (the face area)
function S.removeSpoiled(b, liters)
    local a = b.bunkerSiloArea and b.bunkerSiloArea.inner
    if a == nil or liters <= 0 then return 0 end
    local terrain = g_currentMission.terrainRootNode
    local y0 = getTerrainHeightAtWorldPos(terrain, a.sx, 0, a.sz)
    local y1 = getTerrainHeightAtWorldPos(terrain, a.wx, 0, a.wz)
    local y2 = getTerrainHeightAtWorldPos(terrain, a.hx, 0, a.hz)
    local lsx, lsy, lsz, lex, ley, lez, radius = DensityMapHeightUtil.getLineByAreaDimensions(a.sx, y0, a.sz, a.wx, y1, a.wz, a.hx, y2, a.hz, true)
    local removed = DensityMapHeightUtil.tipToGroundAroundLine(nil, -liters, b.outputFillType, lsx, lsy, lsz, lex, ley, lez, radius, nil, nil, false, nil)
    return math.abs(tonumber(removed) or 0)
end

function S.onDay(day, scale, month)
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    scale = scale or 1
    local dpp = math.max(1, (g_currentMission.environment and g_currentMission.environment.daysPerPeriod) or 1)
    local seen = {}
    S.eachBunker(function(b)
        local key = bunkerKey(b)
        if key == nil then return end
        seen[key] = true
        local P = CarolinaFieldCure
        if P ~= nil and P.objectFarm ~= nil then P.noticeFarm = P.objectFarm(b) end   -- v0.30: the silo owner's farm
        local e = S.bunkers[key]
        if b.state ~= BunkerSilo.STATE_DRAIN then
            if e ~= nil then log("bunker %s: no longer open (state %s) - feed-out record closed", key, tostring(b.state)) end
            S.bunkers[key] = nil
            return
        end
        local fill = b.fillLevel or 0
        if e == nil then
            e = {open = day, full = fill, hist = {{day, fill, scale}}, spoiled = 0, debt = 0}
            S.bunkers[key] = e
            log("bunker %s opened: %.0f l, %.1f m long - feed-out face tracking on (Holmes & Muck 2007, 641 kg/m3)", key, fill, bunkerLength(b) or 0)
            return
        end
        local last = e.hist[#e.hist]
        local takenToday = math.max(0, last[2] - fill)   -- what the player took since yesterday (our spoilage was already counted out)
        e.hist[#e.hist + 1] = {day, fill, scale}
        while #e.hist > dpp + 1 do table.remove(e.hist, 1) end
        local first = e.hist[1]
        local realDays = 0
        for i = 2, #e.hist do realDays = realDays + (e.hist[i][3] or scale) end
        local len = bunkerLength(b)
        if len == nil or e.full <= 0 or realDays <= 0 then return end
        -- face meters removed by the player over the window (our own spoilage removal taken back out)
        local spoiledInWindow = 0
        for i = 2, #e.hist do spoiledInWindow = spoiledInWindow + (e.hist[i][4] or 0) end
        local takenL = math.max(0, first[2] - fill - spoiledInWindow)
        local rate = (takenL / e.full) * len / (realDays / 7)
        local lossPct = S.feedoutLossPct(rate)
        local want = takenToday * lossPct / 100 + (e.debt or 0)
        local got = 0
        if on("feedout") and want > 0 then
            got = S.removeSpoiled(b, want)
            e.debt = math.max(0, want - got)
            e.spoiled = (e.spoiled or 0) + got
            e.hist[#e.hist][4] = got
            b.fillLevel = math.max(0, fill - got)
            e.hist[#e.hist][2] = b.fillLevel
        end
        log("bunker %s day %d: face moving %.2f m/week over %.1f real days -> %.1f %% spoiled at the face; took %.0f l today, spoiled %.0f l (total %.0f l)%s",
            key, day, rate, realDays, lossPct, takenToday, got, e.spoiled or 0, on("feedout") and "" or " - switched off")
        -- notice once a game month when the face moves slower than the recommended minimum for the season
        local T = S.seasonMeanC(month)
        if T ~= nil and realDays >= 7 then
            local minRate = S.minRateMWk(T)
            local period = math.floor(day / dpp)
            if rate < minRate and e.warnPeriod ~= period then
                e.warnPeriod = period
                notice("warning", string.format("Bunker silo face moves %.1f m a week - at %.0f C season mean take at least %.1f m a week (Borreani & Tabacco 2012). About %.0f %% of what you take is spoiled.",
                    rate, T, minRate, lossPct))
            end
        end
    end)
    if CarolinaFieldCure ~= nil then CarolinaFieldCure.noticeFarm = nil end
    for key in pairs(S.bunkers) do
        if not seen[key] then S.bunkers[key] = nil end
    end
end

-- ------------------------------------------------------------------ hooks, save, load

function S.installHooks()
    if S.hooked then return end
    S.hooked = true
    if Cutter ~= nil and Cutter.processPickupCutterArea ~= nil then
        Cutter.processPickupCutterArea = Utils.overwrittenFunction(Cutter.processPickupCutterArea, function(self, superFunc, workArea, dt, ...)
            if self.isServer and self.spec_cutter ~= nil and self.spec_cutter.workAreaParameters ~= nil
                and self.spec_cutter.workAreaParameters.combineVehicle ~= nil then
                local P = CarolinaFieldCure
                if P ~= nil and P.objectFarm ~= nil then P.noticeFarm = P.objectFarm(self) end   -- v0.30: warnings to this machine's farm
                local ok, err = true, S.onWindrowPickup(self, workArea)
                if P ~= nil then P.noticeFarm = nil end
                if not ok and not S.errPick then S.errPick = true Logging.error("[CarolinaFieldAlmanac] silage pickup readout: %s", tostring(err)) end
            end
            return superFunc(self, workArea, dt, ...)
        end)
    end
    if ForageWagon ~= nil and ForageWagon.processForageWagonArea ~= nil then
        ForageWagon.processForageWagonArea = Utils.overwrittenFunction(ForageWagon.processForageWagonArea, function(self, superFunc, workArea, ...)
            if self.isServer then
                local P = CarolinaFieldCure
                if P ~= nil and P.objectFarm ~= nil then P.noticeFarm = P.objectFarm(self) end
                local ok, err = true, S.onWindrowPickup(self, workArea)
                if P ~= nil then P.noticeFarm = nil end
                if not ok and not S.errWagon then S.errWagon = true Logging.error("[CarolinaFieldAlmanac] silage wagon readout: %s", tostring(err)) end
            end
            return superFunc(self, workArea, ...)
        end)
    end
    log("hooks installed (pickup header %s, loader wagon %s)", tostring(Cutter ~= nil), tostring(ForageWagon ~= nil))
end

function S.save(xml, root)
    local i = 0
    for key, e in pairs(S.bunkers) do
        local k = string.format("%s.silageBunker(%d)", root, i)
        xml:setString(k .. "#key", key)
        xml:setInt(k .. "#open", e.open)
        xml:setString(k .. "#full", string.format("%.1f", e.full))
        xml:setString(k .. "#spoiled", string.format("%.1f", e.spoiled or 0))
        xml:setString(k .. "#debt", string.format("%.1f", e.debt or 0))
        if e.warnPeriod ~= nil then xml:setInt(k .. "#warnPeriod", e.warnPeriod) end
        local parts = {}
        for _, h in ipairs(e.hist) do
            parts[#parts + 1] = string.format("%d:%.1f:%.4f:%.1f", h[1], h[2], h[3] or 1, h[4] or 0)
        end
        xml:setString(k .. "#hist", table.concat(parts, ";"))
        i = i + 1
    end
end

function S.load(xml, root)
    S.bunkers = {}
    xml:iterate(root .. ".silageBunker", function(_, k)
        local key = xml:getString(k .. "#key")
        if key == nil then return end
        local e = {open = xml:getInt(k .. "#open", 0), full = tonumber(xml:getString(k .. "#full", "0")) or 0,
                   spoiled = tonumber(xml:getString(k .. "#spoiled", "0")) or 0, debt = tonumber(xml:getString(k .. "#debt", "0")) or 0,
                   warnPeriod = xml:getInt(k .. "#warnPeriod"), hist = {}}
        for d, f, sc, sp in (xml:getString(k .. "#hist", "") or ""):gmatch("(%-?%d+):([%d%.]+):([%d%.]+):([%d%.]+)") do
            e.hist[#e.hist + 1] = {tonumber(d), tonumber(f), tonumber(sc), tonumber(sp)}
        end
        if #e.hist > 0 then S.bunkers[key] = e end
    end)
end
