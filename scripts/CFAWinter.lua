-- Carolina Field Almanac - winter for perennial forage (v0.23). By Kingston Enterprises.
-- Every number below is from a named source (Rule #1). Team decisions 2026-11-04
-- (team notes: forage winter plan and winter state table, 2026-11-04).
-- Same rule on every map: winterkill is real everywhere. Each state uses the model where it passed the check against USDA,
-- otherwise USDA's own year-by-year numbers for that state (CFAUsdaWinter.lua). The game's weather is never changed.
--
-- SNOW (timothy): Ritchie 1991, as given in Kanneganti, Rotz & Walgenbach 1998 (Agron. J. 90:687-697):
--   snow if the day's high is below 1 C; 10 cm per 10 mm; melts 1 cm per C of high above 1 C and 4 cm per 10 mm of rain.
--
-- ALFALFA, FIRST WINTER AFTER SEEDING (model):
--   4-inch soil low for the winter: NOAA measured winters at the soil station nearest the weather station (CFASoilData.lua).
--   The game winter is ranked among the weather station's own winters (CFAWinterClimate.lua); the soil low is the soil station's
--   measured winter at the same rank (coldest with coldest), so each station keeps NOAA's measured soil frequencies.
--   Kill point: Iowa State Extension (Lang & Vittetoe 2019; Michel 2023): hardened alfalfa takes 4-inch soil to 15 F (-9.44 C).
--   Kill % below that: Leep, Andresen & Jeranyama 2001, Agron. J. 93:1142, Tables 2 and 6-8 (fall-seeded plots, first winter),
--   Vernal (fall dormancy 2): 10-cm soil -10.5 C 0 %, -12.3 C 0 %, -13.2 C 45 %, -15.9 C 40 %; high end of the measured points
--   at or warmer than the winter's soil low (team rule).
-- ALFALFA, ESTABLISHED (2nd winter on) and every USDA state: USDA RMA Cause of Loss + Summary of Business 2005-2025 (CFAUsdaWinter.lua),
--   the USDA year at the same rank as the game winter (a hard game winter gets one of the state's bad years).
-- Plants -> yield: start 160 plants/m2 (Kanneganti et al. 1998, Wisconsin average); MSU Extension E-2310 (Hesterman & Durling 1991)
--   Table 3; this year's loss = % last fall - % now (Example 2).
--
-- TIMOTHY (FS25 grass = timothy, team): BASGRA_2014 (Van Oijen, Hoglind, Cameron, Thorsen; Zenodo 27867; timothy cv. Grindstad):
--   Tsurf = mean air x exp(-65 x snow m); hardening/dehardening; frost kill min(0.5, 1 - 1/(1 + exp(-(Tsurf - LT50)))) per day.
--   Tillers killed this winter come off the yield in proportion (BASGRA: killed tillers carry no growth) - or USDA in USDA states.
-- Ice sheets: off (no source for when they form).
--
-- v0.25 ALFALFA CUTTINGS (team 2026-11-06, alfalfa bundle notes):
-- CUTTING ORDER: yield of each cutting of the year as a share of the year's best cutting, high end of each position over:
--   Djaman, Owen, Koudahe & O'Neill 2020, Agronomy 10:136 (NMSU Farmington, 4 cuts at 10 % bloom): 7.3/6.5/4.9/3.8 and 7.9/6.8/4.9/3.7 Mg/ha;
--   Xu, Min & McDonald 2021, J. Anim. Sci. Technol. 63:1098 Table 4 (Kansas State, 28- and 35-day intervals, 2016 and 2017).
--   1st 100 %, 2nd 100 %, 3rd 90.8 %, 4th 68.3 %, 5th 65.3 % (5th = last cutting measured; later cuttings keep it).
--   A cutting less than 14 days after the last one is the same cutting (half of the shortest interval measured, 28 days).
-- LATE FALL CUT: McDonald, Min & Baral 2021, J. Anim. Sci. Technol. 63:799 Table 6 (Kansas State, Manhattan):
--   next year's total yield vs the best last-cut date (Sep 30): Oct 15 cut -12.1 / -6.8 % (not significant), Oct 30 cut -14.8 / -14.9 %
--   (significant both years). Paper: last cut by Sep 30 - Oct 15 without harm. Dates are tied to the freeze: Manhattan's median first
--   28 F freeze is Oct 29 (NOAA Normals 1991-2020, USC00144972), so Oct 15 = 14 days before, Oct 30 = 1 day after.
--   Each map uses its own station's median 28 F freeze (CFAFrostData.lua): 14+ days before = 0; 1 day after or later = 14.9 %
--   (high end); straight line between. Station with no 28 F median = no effect.
--   Cutting interval and stand (Ventroni, Volenec & Cangiano 2010): only 20-day cutting hurt (survival 54 % vs 83/85 %);
--   the game cannot regrow alfalfa that fast (v0.25.1: fastest is one month, CFARegrowth.lua), so no rule is needed.

CFAWinter = {}
local WN = CFAWinter

WN.SNOW_TMAX_C = 1.0      -- Ritchie 1991
WN.SNOW_CM_PER_MM = 1.0   -- 10 cm per 10 mm
WN.MELT_CM_PER_C = 1.0
WN.MELT_CM_PER_MM_RAIN = 0.4   -- 4 cm per 10 mm
WN.DS_CAP_CM = 15

WN.ALF = {POP0 = 160}                -- Kanneganti et al. 1998 (Wisconsin average)
WN.KILL_SOIL_C = -9.44               -- Iowa State: 15 F at 4 inches
WN.LEEP_FD2 = {{-10.5, 0}, {-12.3, 0}, {-13.2, 45}, {-15.9, 40}}   -- Leep et al. 2001, Vernal: 10-cm soil low C, winterkill %
WN.GRASS = {gamma = 65, Hparam = 0.0055925, Dparam = 0.0031796, THARDMX = 14.7052, TsurfDiff = 0.62279, RATEDMX = 2,
            LT50MN = -26.6839, LT50MX = -4.7894, KRSR3H = 1, reHardRedDay = 145, reHardRedEnd = 91}

-- MSU E-2310 Table 3: % of potential yield. Rows = year seeded (1 = last year ... 5 = more than 4 years ago).
-- Columns = viable plants per square foot: 1, 2, 3, 4, 5-6, 7-9, 10-15, >15.
WN.MSU = {
    {15, 25, 30, 40, 50, 65, 80, 100},
    {30, 50, 60, 70, 85, 100, 100, 100},
    {30, 65, 70, 85, 100, 100, 100, 100},
    {50, 70, 85, 100, 100, 100, 100, 100},
    {75, 90, 100, 100, 100, 100, 100, 100},
}
WN.M2_PER_FT2 = 0.09290304   -- NIST: 1 ft2 = 0.09290304 m2

WN.CUT_SHARE = {1.000, 1.000, 0.908, 0.683, 0.653}   -- v0.25 Djaman 2020; Xu, Min & McDonald 2021 Table 4 (high end per cutting)
WN.SAME_CUT_DAYS = 14                                -- half of the shortest interval measured (28 days)
WN.FALLCUT = {safeDays = 14, fullDays = -1, loss = 14.9}   -- McDonald, Min & Baral 2021 Table 6; Manhattan 28 F median Oct 29

WN.snowCm = 0
WN.fields = {}   -- field id -> state

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

function WN.plantsPerFt2(popM2) return popM2 * WN.M2_PER_FT2 end

-- MSU Table 3 lookup. Below 1 plant/ft2 uses the "1" column (team rule: the table starts at 1). Between columns: the lower count.
function WN.msuPct(age, popM2)
    local row = WN.MSU[clamp(age or 1, 1, 5)]
    local p = WN.plantsPerFt2(popM2)
    local col
    if p > 15 then col = 8 elseif p >= 10 then col = 7 elseif p >= 7 then col = 6 elseif p >= 5 then col = 5
    elseif p >= 4 then col = 4 elseif p >= 3 then col = 3 elseif p >= 2 then col = 2 else col = 1 end
    return row[col]
end

local function doyOf(m, d)
    local CUM = {0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334}
    return CUM[m] + d
end

function WN.yearOf()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    return env ~= nil and (env.currentYear or 1) or 1
end

-- ------------------------------------------------------------------ fields

function WN.kindOf(fruitName)
    if fruitName == nil then return nil end
    if fruitName == "ALFALFA" then return "ALFALFA" end
    if fruitName == "GRASS" then return "GRASS" end
    return nil
end

function WN.newState(kind, growthState)
    -- A stand CFA first sees already growing (an existing save) is treated as established: its age is unknown.
    local s = {kind = kind, seededYear = WN.yearOf(), winters = (growthState ~= nil and growthState >= 2) and 1 or 0, winterLoss = 0}
    if kind == "ALFALFA" then
        s.pop = WN.ALF.POP0
    else
        s.lt50 = WN.GRASS.LT50MX; s.kill = 0
    end
    return s
end

function WN.scan()
    local C = CFACrops
    if g_fieldManager == nil or C == nil or C.fieldIdOf == nil then return end
    local seen = {}
    for _, field in pairs(g_fieldManager.fields) do
        local id = C.fieldIdOf(field)
        local s = C.fieldStateOf(field)
        if id ~= nil and s ~= nil then
            local fi = s.fruitTypeIndex
            local desc = (fi ~= nil and fi ~= FruitType.UNKNOWN) and g_fruitTypeManager:getFruitTypeByIndex(fi) or nil
            local kind = desc ~= nil and WN.kindOf(desc.name:upper()) or nil
            if kind ~= nil then
                seen[id] = true
                local st = WN.fields[id]
                if st == nil or st.kind ~= kind then
                    st = WN.newState(kind, WN.scanned and 0 or s.growthState)
                    WN.fields[id] = st
                end
                st.gs, st.cutState = s.growthState, desc.cutState   -- v0.25 cut detection
                st.minH, st.maxH = desc.minHarvestingGrowthState, desc.maxHarvestingGrowthState
            end
        end
    end
    WN.scanned = true   -- after the first scan, a new stand is a new seeding
    for id in pairs(WN.fields) do
        if not seen[id] then WN.fields[id] = nil end   -- plowed, reseeded or changed crop: a new stand starts next time
    end
end

-- ------------------------------------------------------------------ the end-of-winter verdict (April 1)

function WN.stationInfo()
    local W = CFAWeather
    local st = W ~= nil and W.getStation ~= nil and W.getStation() or nil
    if st == nil then return nil end
    if st.country ~= nil then return nil end   -- v0.26/v0.28: soil and USDA winter numbers are U.S. only; Canada / Europe = no effect (Rule #1)
    return st.state, st.lat, st.lon
end

function WN.nearestSoil(lat, lon)
    if CFASoilData == nil or lat == nil then return nil end
    local best, bd = nil, nil
    local k = math.cos(math.rad(lat))
    for _, s in ipairs(CFASoilData.stations) do
        local d = (s.lat - lat) ^ 2 + ((s.lon - lon) * k) ^ 2
        if bd == nil or d < bd then best, bd = s, d end
    end
    return best
end

-- How cold this game winter was: its rank among the weather station's own 100 winters (CFAWinterClimate), 0 = colder than all, 1 = warmest.
-- A station without that list is ranked among the soil station's real winters.
function WN.rankOf(stn, airLow)
    local W = CFAWeather
    local list = CFAWinterClimate ~= nil and W ~= nil and CFAWinterClimate[W.stationId or ""] or nil
    local n, colder = 0, 0
    if list ~= nil then
        n = #list
        for _, v in ipairs(list) do if v < airLow then colder = colder + 1 end end
    else
        n = #stn.w
        for _, w in ipairs(stn.w) do if w[1] < airLow then colder = colder + 1 end end
    end
    if n == 0 then return 0.5 end
    return (colder + 0.5) / (n + 1)
end

-- The soil station's measured 4-inch soil low at the same rank (coldest air winter <-> coldest soil winter).
function WN.soilAtRank(stn, p)
    local soil = {}
    for _, w in ipairs(stn.w) do soil[#soil + 1] = w[2] end
    table.sort(soil)
    return soil[clamp(math.ceil(p * #soil), 1, #soil)]
end

-- The USDA year at the same rank (lists are worst year first).
function WN.usdaAtRank(list, p)
    if list == nil or #list == 0 then return nil end
    return list[clamp(math.ceil(p * #list), 1, #list)]
end

function WN.leepKill(soilC)
    if soilC == nil or soilC > WN.KILL_SOIL_C then return 0 end
    local k = nil
    for _, p in ipairs(WN.LEEP_FD2) do
        if p[1] >= soilC then k = math.max(k or 0, p[2]) end   -- high end of the measured points at or warmer than the soil low
    end
    return k or WN.LEEP_FD2[1][2]
end

function WN.verdict()
    local state, lat, lon = WN.stationInfo()
    local stn = WN.nearestSoil(lat, lon)
    local airLow = WN.winterLow
    if stn == nil or airLow == nil then return end
    local p = WN.rankOf(stn, airLow)
    local soilLow = WN.soilAtRank(stn, p)
    local U = CFAUsdaWinter ~= nil and CFAUsdaWinter[state or ""] or {}
    local seedV = WN.usdaAtRank(U.seeding, p)
    local prodV = WN.usdaAtRank(U.production, p)
    WN.last = {airLow = airLow, rank = p, soilLow = soilLow, station = stn.name .. ", " .. stn.state, state = state}
    for _, st in pairs(WN.fields) do
        local kill, how
        if st.kind == "ALFALFA" then
            if (st.winters or 0) == 0 then
                if U.alf == "usda" and seedV ~= nil then kill, how = seedV, "USDA"
                else kill, how = WN.leepKill(soilLow), "model" end
            else
                kill, how = prodV or 0, prodV ~= nil and "USDA" or "none"
            end
            local age = clamp((st.winters or 0) + 1, 1, 5)
            local popFall = st.pop
            st.pop = st.pop * (1 - kill / 100)
            st.winterLoss = math.max(0, WN.msuPct(age, popFall) - WN.msuPct(age, st.pop))
        else
            if U.tim == "usda" and prodV ~= nil then kill, how = prodV, "USDA"
            else kill, how = 100 * (st.kill or 0), "model" end
            st.winterLoss = kill
        end
        st.lastKill, st.lastHow = kill, how
        st.winters = (st.winters or 0) + 1
    end
end

-- ------------------------------------------------------------------ v0.25 alfalfa cuttings

-- Station's median first 28 F freeze (day of year; January = 365 + day), or nil.
function WN.freezeDoy()
    local W = CFAWeather
    return CFAFrostData ~= nil and W ~= nil and CFAFrostData[W.stationId or ""] or nil
end

-- Next year's yield loss % for a last cut on day-of-year 'doy' (McDonald, Min & Baral 2021).
function WN.fallCutLoss(doy)
    local fz = WN.freezeDoy()
    if fz == nil or doy == nil then return 0 end
    local F = WN.FALLCUT
    local before = fz - doy
    if before >= F.safeDays then return 0 end
    if before <= F.fullDays then return F.loss end
    return F.loss * (F.safeDays - before) / (F.safeDays - F.fullDays)
end

function WN.cutShare(n)
    local t = WN.CUT_SHARE
    return t[math.max(1, math.min(#t, n or 1))]
end

-- A cut seen on the field today (alfalfa went to its cut state).
function WN.onCut(id, st, day, scale, m, d)
    local realDays = st.lastCutDay ~= nil and (day - st.lastCutDay) * (scale or 1) or nil
    if realDays ~= nil and realDays >= 0 and realDays < WN.SAME_CUT_DAYS then return end   -- same cutting
    st.cutsN = (st.cutsN or 0) + 1
    st.lastCutDay = day
    st.lastCutDoy = (m ~= nil and d ~= nil) and doyOf(m, d) or nil
    st.fallUsed = nil
    Logging.info("[CarolinaFieldAlmanac] crops: field %s alfalfa cutting %d of the year (%s/%s), yield %.1f %% of the best cutting",
        tostring(id), st.cutsN, tostring(m), tostring(d), 100 * WN.cutShare(st.cutsN))
end

-- New calendar year: the last cut of last year sets this year's late-fall-cut loss; the cutting count starts over.
function WN.newYear()
    for id, st in pairs(WN.fields) do
        if st.kind == "ALFALFA" then
            local loss = 0
            if not st.fallUsed and st.lastCutDoy ~= nil then loss = WN.fallCutLoss(st.lastCutDoy) end
            st.fallCutLoss = loss
            st.fallUsed = true
            st.cutsN = 0
            if loss > 0 then
                local fz = WN.freezeDoy()
                Logging.info("[CarolinaFieldAlmanac] crops: field %s alfalfa last cut day %d, %d days before the median 28 F freeze -> %.1f %% less yield this year",
                    tostring(id), st.lastCutDoy, (fz or 0) - st.lastCutDoy, loss)
                if CarolinaFieldCure ~= nil and CarolinaFieldCure.addNotice ~= nil then
                    CarolinaFieldCure.addNotice("warn", string.format(
                        "Field %s alfalfa: last cut was too close to the first hard freeze - %.0f %% less hay this year (Kansas State trial)", tostring(id), loss))
                end
            end
        end
    end
end

-- The cutting the field's standing alfalfa will be, today.
function WN.cutIndex(st, day, scale, m)
    if st.lastCutDay ~= nil and (day - st.lastCutDay) * (scale or 1) < WN.SAME_CUT_DAYS then return math.max(1, st.cutsN or 1) end
    return (st.cutsN or 0) + 1
end

-- ------------------------------------------------------------------ daily step (one game day = 'scale' real days)

function WN.snowStep(tmaxC, precipMm)
    if tmaxC < WN.SNOW_TMAX_C then
        WN.snowCm = WN.snowCm + precipMm * WN.SNOW_CM_PER_MM
    else
        WN.snowCm = WN.snowCm - (tmaxC - WN.SNOW_TMAX_C) * WN.MELT_CM_PER_C - precipMm * WN.MELT_CM_PER_MM_RAIN
    end
    if WN.snowCm < 0 then WN.snowCm = 0 end
end

function WN.grassStep(st, tmx, tmn, m, d)
    local G = WN.GRASS
    if not st.armed then   -- same start rule as alfalfa (BASGRA runs also start before winter)
        if m ~= nil and m >= 7 and m <= 8 then st.armed = true else return end
    end
    local tsurf = ((tmx + tmn) / 2) * math.exp(-G.gamma * WN.snowCm / 100)
    local doy = (m ~= nil and d ~= nil) and doyOf(m, d) or 1
    local start = (G.reHardRedEnd - G.reHardRedDay) % 365
    local since = (doy - start) % 365
    local period = 1
    if since < (G.reHardRedDay + 0.5 * (365 - G.reHardRedDay)) then period = math.max(0, 1 - since / G.reHardRedDay) end
    local rateH = 0
    if tsurf <= G.THARDMX and st.lt50 >= G.LT50MN then rateH = period * G.Hparam * (G.THARDMX - tsurf) * (st.lt50 - G.LT50MN) end
    local rated = math.min(G.Dparam * (G.LT50MX - st.lt50) * (tsurf + G.TsurfDiff), G.LT50MX - st.lt50)
    local deH = math.max(0, math.min(G.RATEDMX, rated))
    st.lt50 = st.lt50 + deH - rateH
    local rdr = math.min(0.5, 1 - 1 / (1 + math.exp(-G.KRSR3H * (tsurf - st.lt50))))
    if m ~= nil and m == 8 and d == 1 then st.kill = 0 end   -- new winter count each year (display)
    st.kill = 1 - (1 - (st.kill or 0)) * (1 - rdr)
    st.tsurf = tsurf
end

function WN.stepDay(day, scale)
    local W = CFAWeather
    if W == nil or not W.active then return end
    local x = W.days ~= nil and W.days[day] or nil
    if x == nil then return end
    local C = CFACrops
    WN.scan()
    local m, d = C.realDateOfDay(day)
    WN.lastScale = scale
    -- v0.25: a new calendar year, then cuts seen today
    if m ~= nil then
        if WN.lastMonth ~= nil and m < WN.lastMonth then WN.newYear() end
        WN.lastMonth = m
    end
    for id, st in pairs(WN.fields) do
        if st.kind == "ALFALFA" and st.gs ~= nil then
            -- cut: it was harvestable last time and now it is cut (or already regrowing below harvestable)
            local wasReady = st.prevGs ~= nil and st.minH ~= nil and st.minH > 0 and st.prevGs >= st.minH and st.prevGs <= (st.maxH or st.prevGs)
            local isCut = (st.cutState ~= nil and st.gs == st.cutState) or (st.minH ~= nil and st.gs < st.minH)
            if wasReady and isCut then WN.onCut(id, st, day, scale, m, d) end
            st.prevGs = st.gs
        end
    end
    if m == 8 then WN.winterLow = nil end                       -- a new winter is counted from August
    if m == 11 or m == 12 or m <= 3 then
        WN.winterLow = math.min(WN.winterLow or 99, x.loC)      -- this game winter's coldest low (Nov-Mar)
    end
    local steps = math.max(1, math.floor((scale or 1) + 0.5))
    for _ = 1, steps do
        WN.snowStep(x.hiC, x.wet and (x.rainMM or 0) or 0)
        for _, st in pairs(WN.fields) do
            if st.kind == "GRASS" then WN.grassStep(st, x.hiC, x.loC, m, d) end
        end
    end
    if m == 4 and WN.lastVerdict ~= WN.yearOf() then
        WN.lastVerdict = WN.yearOf()
        WN.verdict()
    end
    -- this year's loss goes on every growth on the field (applied at harvest through CFACrops.totalFactor)
    for id, st in pairs(WN.fields) do
        local rec = C.fields[id]
        if rec ~= nil and not rec.done and rec.fruit == st.kind then
            rec.winterLoss = st.winterLoss or 0
            WN.setCutLoss(rec, st, day, scale, m)
        end
    end
end

-- v0.25: cutting order and late-fall-cut loss on the growth (alfalfa only)
function WN.setCutLoss(rec, st, day, scale, m)
    if st.kind ~= "ALFALFA" then return end
    local n = WN.cutIndex(st, day or (g_currentMission and g_currentMission.environment.currentMonotonicDay) or 0, scale or WN.lastScale, m)
    rec.cutLoss = 100 * (1 - WN.cutShare(n))
    rec.cutNo = n
    rec.fallCutLoss = st.fallCutLoss or 0
end

-- New growth on a field picks up this year's loss right away.
function WN.onPlanted(id, rec)
    local st = WN.fields[id]
    if st ~= nil and rec.fruit == st.kind then
        rec.winterLoss = st.winterLoss or 0
        WN.setCutLoss(rec, st, nil, nil, nil)
    end
end

-- Menu text
function WN.fieldText(id)
    local st = WN.fields[id]
    if st == nil then return nil end
    local w = st.winters or 0
    local last = ""
    if st.lastKill ~= nil then
        last = string.format(", last winter lost %.0f%% (%s)", st.lastKill, st.lastHow or "-")
    end
    if st.kind == "ALFALFA" then
        local cuts = string.format(", %d cutting(s) this year", st.cutsN or 0)
        if (st.fallCutLoss or 0) > 0 then cuts = cuts .. string.format(", late fall cut -%.0f%% this year", st.fallCutLoss) end
        return string.format("%s, %.1f plants/sq ft%s%s", w == 0 and "first winter ahead" or (w .. " winter(s)"), WN.plantsPerFt2(st.pop), last, cuts)
    end
    return string.format("timothy, %s%s", w == 0 and "first winter ahead" or (w .. " winter(s)"), last)
end

-- ------------------------------------------------------------------ save / load (inside the crops save file)

function WN.save(xml, root)
    xml:setString(root .. ".winter#snowCm", string.format("%.2f", WN.snowCm))
    if WN.winterLow ~= nil then xml:setString(root .. ".winter#winterLow", string.format("%.2f", WN.winterLow)) end
    if WN.lastVerdict ~= nil then xml:setInt(root .. ".winter#lastVerdict", WN.lastVerdict) end
    if WN.lastMonth ~= nil then xml:setInt(root .. ".winter#lastMonth", WN.lastMonth) end   -- v0.25
    local i = 0
    for id, st in pairs(WN.fields) do
        local k = string.format("%s.winter.field(%d)", root, i)
        xml:setString(k .. "#id", tostring(id))
        xml:setString(k .. "#kind", st.kind)
        xml:setInt(k .. "#seededYear", st.seededYear or 1)
        xml:setInt(k .. "#winters", st.winters or 0)
        xml:setString(k .. "#winterLoss", string.format("%.3f", st.winterLoss or 0))
        if st.lastKill ~= nil then
            xml:setString(k .. "#lastKill", string.format("%.3f", st.lastKill))
            xml:setString(k .. "#lastHow", st.lastHow or "-")
        end
        if st.kind == "ALFALFA" then
            xml:setString(k .. "#pop", string.format("%.4f", st.pop))
            xml:setInt(k .. "#cutsN", st.cutsN or 0)   -- v0.25
            if st.lastCutDay ~= nil then xml:setInt(k .. "#lastCutDay", st.lastCutDay) end
            if st.lastCutDoy ~= nil then xml:setInt(k .. "#lastCutDoy", st.lastCutDoy) end
            if st.prevGs ~= nil then xml:setInt(k .. "#prevGs", st.prevGs) end
            if st.fallUsed then xml:setBool(k .. "#fallUsed", true) end
            xml:setString(k .. "#fallCutLoss", string.format("%.3f", st.fallCutLoss or 0))
        else
            xml:setBool(k .. "#armed", st.armed == true)
            xml:setString(k .. "#lt50", string.format("%.4f", st.lt50))
            xml:setString(k .. "#kill", string.format("%.5f", st.kill or 0))
        end
        i = i + 1
    end
end

function WN.load(xml, root)
    WN.snowCm = tonumber(xml:getString(root .. ".winter#snowCm", "0")) or 0
    WN.winterLow = tonumber(xml:getString(root .. ".winter#winterLow", ""))
    WN.lastVerdict = xml:getInt(root .. ".winter#lastVerdict")
    WN.lastMonth = xml:getInt(root .. ".winter#lastMonth")   -- v0.25
    WN.fields = {}
    -- a save from before v0.23 has no winter data: the stands already on the map are existing (established) stands
    WN.scanned = xml:getString(root .. ".winter#snowCm") ~= nil
    xml:iterate(root .. ".winter.field", function(_, k)
        local idS = xml:getString(k .. "#id")
        local id = tonumber(idS) or idS
        local kind = xml:getString(k .. "#kind")
        if id ~= nil and (kind == "ALFALFA" or kind == "GRASS") then
            local st = {kind = kind, seededYear = xml:getInt(k .. "#seededYear", 1), winters = xml:getInt(k .. "#winters", 1),
                        winterLoss = tonumber(xml:getString(k .. "#winterLoss", "0")) or 0,
                        lastKill = tonumber(xml:getString(k .. "#lastKill", "")), lastHow = xml:getString(k .. "#lastHow")}
            if kind == "ALFALFA" then
                st.pop = tonumber(xml:getString(k .. "#pop", tostring(WN.ALF.POP0))) or WN.ALF.POP0
                st.cutsN = xml:getInt(k .. "#cutsN", 0)   -- v0.25
                st.lastCutDay = xml:getInt(k .. "#lastCutDay")
                st.lastCutDoy = xml:getInt(k .. "#lastCutDoy")
                st.prevGs = xml:getInt(k .. "#prevGs")
                st.fallUsed = xml:getBool(k .. "#fallUsed", false) or nil
                st.fallCutLoss = tonumber(xml:getString(k .. "#fallCutLoss", "0")) or 0
            else
                st.armed = xml:getBool(k .. "#armed", false)
                st.lt50 = tonumber(xml:getString(k .. "#lt50", tostring(WN.GRASS.LT50MX))) or WN.GRASS.LT50MX
                st.kill = tonumber(xml:getString(k .. "#kill", "0")) or 0
            end
            WN.fields[id] = st
        end
    end)
end
