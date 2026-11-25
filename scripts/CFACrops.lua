-- Carolina Field Almanac - crop part. By Kingston Enterprises. Mod for Farming Simulator.
--
-- Every field keeps its own degree-day clock from the day it is planted, fed by the day's high and low
-- from the weather part. Crop stages come from sourced degree-day numbers in data/cropWeather.xml.
-- Freezes and rain take a sourced share of the yield; the loss is applied when the field is harvested.
-- Rule #1: a blank number in the table = that rule stays off. Unknown crops get no effect.
--
-- Time: a game "month" has only daysPerPeriod days, so each game day stands for (days in that month / daysPerPeriod)
-- real days. Degree days and rain inches are scaled by that, so a season adds up like a real season.

CFACrops = {}
local C = CFACrops

-- v0.26.1 (team 2026-11-12): own rows on the game's Finances page for crop insurance, instead of "Misc".
-- Same way other mods add finance rows (e.g. Realistic Livestock): the stat names go in at load time, the money types at loadMap.
-- v0.26.2 (team 2026-11-12): two rows, "CFA Insurance Premium" and "CFA Insurance Claim".
C.FIN_STATS = {
    {stat = "cfaInsurancePremium", key = "finance_cfaInsurancePremium", text = "CFA Insurance Premium"},
    {stat = "cfaInsuranceClaim", key = "finance_cfaInsuranceClaim", text = "CFA Insurance Claim"},
}
if FinanceStats ~= nil and type(FinanceStats.statNames) == "table" and type(FinanceStats.statNameToIndex) == "table" then
    for _, f in ipairs(C.FIN_STATS) do
        if FinanceStats.statNameToIndex[f.stat] == nil then
            table.insert(FinanceStats.statNames, f.stat)
            FinanceStats.statNameToIndex[f.stat] = #FinanceStats.statNames
        end
    end
end
-- v0.26.2: the Finances page looks the row names up with no mod attached, so FS25 cannot see our modDesc texts
-- ("Missing 'finance_cfaInsurancePremium' in l10n_en.xml" in game). Send just these two keys to our own texts
-- (same fix Realistic Livestock uses for its finance rows).
C.MOD_NAME = g_currentModName
C.FIN_KEYS = {finance_cfaInsurancePremium = true, finance_cfaInsuranceClaim = true}
if I18N ~= nil and I18N.getText ~= nil and Utils ~= nil and Utils.overwrittenFunction ~= nil then
    I18N.getText = Utils.overwrittenFunction(I18N.getText, function(self, superFunc, text, modEnv)
        if modEnv == nil and text ~= nil and C.FIN_KEYS[text] and C.MOD_NAME ~= nil then
            return superFunc(self, text, C.MOD_NAME)
        end
        return superFunc(self, text, modEnv)
    end)
end
function C.registerMoneyTypes()
    if g_i18n ~= nil then
        for _, f in ipairs(C.FIN_STATS) do
            if type(g_i18n.texts) == "table" and g_i18n.texts[f.key] == nil then g_i18n.texts[f.key] = f.text end
        end
    end
    if MoneyType == nil or MoneyType.register == nil or FinanceStats == nil or FinanceStats.statNameToIndex == nil then return end
    if FinanceStats.statNameToIndex.cfaInsurancePremium ~= nil and MoneyType.CFA_INSURANCE_PREMIUM == nil then
        MoneyType.CFA_INSURANCE_PREMIUM = MoneyType.register("cfaInsurancePremium", "finance_cfaInsurancePremium")
        MoneyType.LAST_ID = MoneyType.LAST_ID + 1
    end
    if FinanceStats.statNameToIndex.cfaInsuranceClaim ~= nil and MoneyType.CFA_INSURANCE_CLAIM == nil then
        MoneyType.CFA_INSURANCE_CLAIM = MoneyType.register("cfaInsuranceClaim", "finance_cfaInsuranceClaim")
        MoneyType.LAST_ID = MoneyType.LAST_ID + 1
    end
end

C.MOD_DIR = g_currentModDirectory
C.DATA_FILE = "data/cropWeather.xml"
C.SAVE_FILE = "carolinaFieldAlmanacCrops.xml"
C.MONTH_DAYS = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}

C.crops = {}           -- fruit name (upper) -> default crop definition
C.variants = {}        -- fruit name (upper) -> list of definitions (some limited to planting months)
C.fields = {}          -- field id -> record
-- v0.21.6 (team): crop tracking and damage wait until the player confirms the weather station, so crops are never built from the
-- wrong place. Reminders: box line, a pop-up on load and each game morning. After 12 game days the station that is set is used.
C.stationConfirmed = false
C.waitStartDay = nil
C.WAIT_DAYS = 12
C.active = false
C.settings = {rangePick = "high", off = {}}  -- sourced loss ranges (e.g. 73-77 %): high end (team, 2026-10-31). Never a midpoint.
-- v0.21 Settings tab: each damage type can be switched off. Off = that loss is still tracked but NOT taken off the harvest
-- (and not counted for insurance). Switching it back on brings it back.
C.DAMAGE = {
    {key = "freeze",   field = "loss",        name = "Freeze / cold nights"},
    {key = "rain",     field = "weatherLoss", name = "Rain on ready crop"},
    {key = "hail",     field = "hailLoss",    name = "Hail"},
    {key = "wind",     field = "windLoss",    name = "Wind"},
    {key = "tornado",  field = "tornadoLoss", name = "Tornado"},                     -- v0.25.20 CFAStormData.lua, station's state
    {key = "hurricane", field = "hurricaneLoss", name = "Hurricane / tropical storm"},   -- v0.25.20 CFAStormData.lua, station's state
    {key = "freeze",   field = "rmaColdLoss", name = "Freeze / frost / cold winter (USDA claims)"},   -- v0.27 <coldLoss>, same switch as freeze
    {key = "heat",     field = "heatLoss",    name = "Heat"},
    {key = "drought",  field = "droughtLoss", name = "Drought"},
    {key = "waterlog", field = "wlLoss",      name = "Waterlogging"},
    {key = "delay",    field = "delayLoss",   name = "Harvest delay"},
    {key = "winter",   field = "winterLoss",  name = "Winterkill (alfalfa and grass)"},   -- v0.23 model or USDA by state (CFAWinter.lua)
    -- v0.25 alfalfa cuttings (CFAWinter.lua). Management, not weather: never counted for insurance (mgmt = true).
    {key = "cutorder", field = "cutLoss",     name = "Alfalfa cutting order", mgmt = true},
    {key = "fallcut",  field = "fallCutLoss", name = "Alfalfa late fall cut", mgmt = true},
    -- v0.29 silage (CFASilage.lua). Management, not weather. Not stored on the field record: taken when chopped / fed out.
    {key = "silage",   field = "silageNone",  name = "Corn silage chopped early", mgmt = true},
    {key = "feedout",  field = "feedoutNone", name = "Silage feed-out face", mgmt = true},
}

function C.on(key)
    return not C.settings.off[key]
end

-- Share of the yield the field keeps (0-1), with only the damage types that are switched on.
-- insured = true: weather damage only (v0.25: management losses such as cutting order are not insured).
function C.totalFactor(rec, insured)
    local f = 1
    for _, d in ipairs(C.DAMAGE) do
        if C.on(d.key) and not (insured and d.mgmt) then f = f * (1 - (rec[d.field] or 0) / 100) end
    end
    return math.max(0, math.min(1, f))
end

local function log(fmt, ...)
    Logging.info("[CarolinaFieldAlmanac] crops: " .. fmt, ...)
end

local function cToF(c) return c * 1.8 + 32 end

-- ------------------------------------------------------------------ data

local function num(xml, key)
    local s = xml:getString(key)
    if s == nil or s == "" then return nil end
    return tonumber(s)
end

function C.loadData()
    local xml = XMLFile.load("cfaCropWeather", C.MOD_DIR .. C.DATA_FILE)
    if xml == nil then
        log("crop table %s not found - crop part off", C.DATA_FILE)
        return false
    end
    local count = 0
    xml:iterate("cropWeather.crop", function(_, key)
        local fruit = xml:getString(key .. "#fruit")
        if fruit == nil then return end
        local crop = {fruit = fruit:upper(), stages = {}, stageIndex = {}, tables = {}, stageRules = {}, curves = {}}
        -- v0.12: a crop entry can be limited to planting months (e.g. fall-sown wheat has its own stages and rules)
        local pm = xml:getString(key .. "#plantedMonths")
        if pm ~= nil then
            crop.plantedMonths = {}
            for m in pm:gmatch("%d+") do crop.plantedMonths[tonumber(m)] = true end
        end
        crop.growth = {
            method = xml:getString(key .. ".growth#method", "mean"),
            baseF = num(xml, key .. ".growth#baseF"),
            capF = num(xml, key .. ".growth#capF"),
            earlyCapF = num(xml, key .. ".growth#earlyCapF"),   -- NDAWN: max clipped here until switchDD
            switchDD = num(xml, key .. ".growth#switchDD"),
            startDays = num(xml, key .. ".growth#startDays")   -- v0.19: clock starts this many real days after planting (rice: emergence)
        }
        -- v0.20: hot-dry-windy hours (K-State): loss per 10 hours inside a stage window
        if xml:hasProperty(key .. ".hdw") then
            local k = key .. ".hdw"
            crop.hdw = {from = xml:getString(k .. "#fromStage", ""), untilStage = xml:getString(k .. "#untilStage"),
                        lossPer10h = num(xml, k .. "#lossPer10h"), tempC = num(xml, k .. "#tempC"), rhPct = num(xml, k .. "#rhPct"),
                        windMs = num(xml, k .. "#windMs"), source = xml:getString(k .. "#source", "")}
            if crop.hdw.lossPer10h == nil then crop.hdw = nil end
        end
        -- v0.20.1: heat-wave rule - loss when the high stays this far above the NOAA daily normal high for this many days in a row in a stage window
        if xml:hasProperty(key .. ".harvestDelay") then
            local k = key .. ".harvestDelay"
            crop.harvestDelay = {from = xml:getString(k .. "#fromStage", ""), perDay = num(xml, k .. "#lossPerDay"), source = xml:getString(k .. "#source", "")}
            if crop.harvestDelay.perDay == nil or crop.harvestDelay.from == "" then crop.harvestDelay = nil end
        end
        if xml:hasProperty(key .. ".heatWave") then
            local k = key .. ".heatWave"
            crop.heatWave = {from = xml:getString(k .. "#fromStage", ""), untilStage = xml:getString(k .. "#untilStage"),
                             aboveF = num(xml, k .. "#aboveNormalF"), days = num(xml, k .. "#days"), loss = num(xml, k .. "#loss"),
                             source = xml:getString(k .. "#source", "")}
            if crop.heatWave.aboveF == nil or crop.heatWave.days == nil or crop.heatWave.loss == nil then crop.heatWave = nil end
        end
        -- v0.25.8 corn heat at pollination (team 2026-11-07)
        if xml:hasProperty(key .. ".pollinationHeat") then
            local k = key .. ".pollinationHeat"
            crop.pollHeat = {from = xml:getString(k .. "#fromStage", ""), untilStage = xml:getString(k .. "#untilStage"),
                             atOrAboveF = num(xml, k .. "#atOrAboveF"), freeDays = num(xml, k .. "#freeDays"), lossPerDay = num(xml, k .. "#lossPerDay"),
                             source = xml:getString(k .. "#source", "")}
            if crop.pollHeat.atOrAboveF == nil or crop.pollHeat.freeDays == nil or crop.pollHeat.lossPerDay == nil then crop.pollHeat = nil end
        end
        -- v0.19: cold-night rules - loss when the low stays at or below lowF for this many nights in a row inside a stage window
        crop.coldNights = {}
        xml:iterate(key .. ".coldNights", function(_, wk)
            local r = {from = xml:getString(wk .. "#fromStage", ""), untilStage = xml:getString(wk .. "#untilStage"), lowF = num(xml, wk .. "#lowAtOrBelowF"),
                       nights = num(xml, wk .. "#nights"), loss = num(xml, wk .. "#loss"), source = xml:getString(wk .. "#source", "")}
            if r.lowF ~= nil and r.nights ~= nil and r.loss ~= nil then table.insert(crop.coldNights, r) end
        end)
        -- v0.14.2: waterlogging rules - loss when the root zone stays waterlogged this many days in a row inside a stage window
        crop.waterlog = {}
        xml:iterate(key .. ".waterlog", function(_, wk)
            local r = {from = xml:getString(wk .. "#fromStage", ""), untilStage = xml:getString(wk .. "#untilStage"),
                       days = num(xml, wk .. "#days"), loss = num(xml, wk .. "#loss"), source = xml:getString(wk .. "#source", "")}
            if r.days ~= nil and r.loss ~= nil then table.insert(crop.waterlog, r) end
        end)
        -- v0.21.8: Texas AGFL flood model (base % by month of growth + % per flooded day)
        if xml:hasProperty(key .. ".floodModel") then
            local k = key .. ".floodModel"
            local base = {}
            for v in (xml:getString(k .. "#base", "")):gmatch("%-?[%d%.]+") do base[#base + 1] = tonumber(v) end
            crop.floodModel = {base = base, perDay = num(xml, k .. "#perDay"), source = xml:getString(k .. "#source", "")}
            if #base == 0 or crop.floodModel.perDay == nil then crop.floodModel = nil end
        end
        -- v0.21.8: corn left standing over winter (Lauer 2004), heavy / light snow rows by the farm's snow days since Nov 1
        if xml:hasProperty(key .. ".winterStand") then
            local k = key .. ".winterStand"
            local function list(a) local r = {} for v in (xml:getString(k .. "#" .. a, "")):gmatch("%-?[%d%.]+") do r[#r + 1] = tonumber(v) end return r end
            crop.winterStand = {heavy = list("heavy"), light = list("light"), heavyDays = list("heavyDays"), source = xml:getString(k .. "#source", "")}
            if #crop.winterStand.heavy ~= 6 or #crop.winterStand.light ~= 6 or #crop.winterStand.heavyDays ~= 6 then crop.winterStand = nil end
        end
        crop.dormantBelowF = num(xml, key .. "#dormantBelowF")   -- v0.21.8 alfalfa: FAO-56 / Everson 1978 season = -4 C to -4 C
        -- v0.14: lead-state planting date (USDA NASS Crop Progress 5-yr avg, first week at or above 50 % planted) - used by the backfill
        if xml:hasProperty(key .. ".plant") then
            crop.plant = {state = xml:getString(key .. ".plant#state", "?"), month = xml:getInt(key .. ".plant#month"), day = xml:getInt(key .. ".plant#day")}
            if crop.plant.month == nil or crop.plant.day == nil then crop.plant = nil end
        end
        -- v0.29.3: planting dates for countries outside the U.S. (team 2026-11-15). A country without one is not backfilled.
        xml:iterate(key .. ".plantIn", function(_, pk)
            local cc, mo, dy = xml:getString(pk .. "#country"), xml:getInt(pk .. "#month"), xml:getInt(pk .. "#day")
            local stt = xml:getString(pk .. "#state")   -- v0.29.5: optional province (Canada: one date per province)
            local reg = xml:getString(pk .. "#region")  -- v0.29.8: optional region inside a province (Ontario spring cereals)
            if cc ~= nil and mo ~= nil and dy ~= nil then
                crop.plantIn = crop.plantIn or {}
                local key = stt ~= nil and (cc .. ":" .. stt) or cc
                if reg ~= nil then key = key .. ":" .. reg end
                crop.plantIn[key] = {state = stt or cc, month = mo, day = dy}
            end
        end)
        xml:iterate(key .. ".stage", function(_, sk)
            local st = {name = xml:getString(sk .. "#name"), dd = num(xml, sk .. "#dd"), from = xml:getString(sk .. "#from"),
                        days = num(xml, sk .. "#days")}   -- v0.12: days after planting (real days)
            table.insert(crop.stages, st)
            crop.stageIndex[st.name] = #crop.stages
        end)
        xml:iterate(key .. ".freezeTable", function(_, tk)
            local t = {after = xml:getString(tk .. "#after"), method = xml:getString(tk .. "#method", "mean"),
                       baseF = num(xml, tk .. "#baseF"), capF = num(xml, tk .. "#capF"), damage = {}}
            xml:iterate(tk .. ".damage", function(_, dk)
                local d = {name = xml:getString(dk .. "#name"), below = num(xml, dk .. "#lowBelowF"),
                           atOrBelow = num(xml, dk .. "#lowAtOrBelowF"), minHours = num(xml, dk .. "#minHours"), rows = {}}
                xml:iterate(dk .. ".row", function(_, rk)
                    table.insert(d.rows, {hu = num(xml, rk .. "#hu"), loss = num(xml, rk .. "#loss")})
                end)
                table.sort(d.rows, function(a, b) return a.hu < b.hu end)
                table.insert(t.damage, d)
            end)
            table.insert(crop.tables, t)
        end)
        xml:iterate(key .. ".freezeStage", function(_, rk)
            table.insert(crop.stageRules, {
                stage = xml:getString(rk .. "#stage"), untilStage = xml:getString(rk .. "#untilStage"),
                atOrBelow = num(xml, rk .. "#lowAtOrBelowF"), below = num(xml, rk .. "#lowBelowF"), minHours = num(xml, rk .. "#minHours"),
                loss = num(xml, rk .. "#loss"), lossLow = num(xml, rk .. "#lossLow"), lossHigh = num(xml, rk .. "#lossHigh")
            })
        end)
        -- v0.12: graded freeze curve (loss by how cold the day's low gets), e.g. Lindsey et al. 2021 Table 1
        xml:iterate(key .. ".freezeCurve", function(_, ck)
            local c = {stage = xml:getString(ck .. "#stage"), untilStage = xml:getString(ck .. "#untilStage"),
                       minHours = num(xml, ck .. "#minHours"), rows = {}}
            xml:iterate(ck .. ".row", function(_, rk)
                table.insert(c.rows, {atOrBelow = num(xml, rk .. "#lowAtOrBelowF"), loss = num(xml, rk .. "#loss")})
            end)
            table.insert(crop.curves, c)
        end)
        -- v0.13: drought (FAO-56 root-zone water balance + FAO-33 seasonal yield response)
        if xml:hasProperty(key .. ".drought") then
            local k = key .. ".drought"
            local d = {ky = num(xml, k .. "#ky"), kcIni = num(xml, k .. "#kcIni"), kcMid = num(xml, k .. "#kcMid"), kcEnd = num(xml, k .. "#kcEnd"),
                       lIni = num(xml, k .. "#lIni"), lDev = num(xml, k .. "#lDev"), lMid = num(xml, k .. "#lMid"), lLate = num(xml, k .. "#lLate"),
                       rootM = num(xml, k .. "#rootM"), p = num(xml, k .. "#p")}
            if d.ky and d.kcIni and d.kcMid and d.kcEnd and d.lIni and d.lDev and d.lMid and d.lLate and d.rootM and d.p then crop.drought = d end
        end
        -- v0.12: hail from USDA RMA crop-insurance hail claims in the crop's lead state (see data file for the source rows)
        if xml:hasProperty(key .. ".hail") then
            local h = {state = xml:getString(key .. ".hail#state"), lossPct = num(xml, key .. ".hail#lossPct"), chance = {}}
            local cs = xml:getString(key .. ".hail#chance") or ""
            for v in cs:gmatch("[%d%.eE%-]+") do table.insert(h.chance, tonumber(v)) end
            if h.lossPct ~= nil and #h.chance == 12 then crop.hail = h end
        end
        -- v0.19: wind from USDA RMA "Wind/Excess Wind" claims in the crop's lead state (same method as hail)
        if xml:hasProperty(key .. ".wind") then
            local h = {state = xml:getString(key .. ".wind#state"), lossPct = num(xml, key .. ".wind#lossPct"), chance = {}}
            local cs = xml:getString(key .. ".wind#chance") or ""
            for v in cs:gmatch("[%d%.eE%-]+") do table.insert(h.chance, tonumber(v)) end
            if h.lossPct ~= nil and #h.chance == 12 then crop.wind = h end
        end
        -- v0.27 (team 2026-11-12): USDA RMA "Freeze" / "Frost" / "Cold Winter" claims in the lead state, used where Extension gives no loss %
        crop.coldLoss = {}
        xml:iterate(key .. ".coldLoss", function(_, ck)
            local h = {cause = xml:getString(ck .. "#cause", "freeze"), state = xml:getString(ck .. "#state"), lossPct = num(xml, ck .. "#lossPct"), chance = {}}
            for v in (xml:getString(ck .. "#chance") or ""):gmatch("[%d%.eE%-]+") do table.insert(h.chance, tonumber(v)) end
            if h.lossPct ~= nil and #h.chance == 12 then table.insert(crop.coldLoss, h) end
        end)
        -- v0.19: drought stress rules - loss when soil water stays below the readily available amount this many days in a row inside a stage window
        crop.droughtStress = {}
        xml:iterate(key .. ".droughtStress", function(_, wk)
            local r = {from = xml:getString(wk .. "#fromStage", ""), untilStage = xml:getString(wk .. "#untilStage"),
                       days = num(xml, wk .. "#days"), loss = num(xml, wk .. "#loss"), source = xml:getString(wk .. "#source", "")}
            if r.days ~= nil and r.loss ~= nil then table.insert(crop.droughtStress, r) end
        end)
        if xml:hasProperty(key .. ".earlyEnd") then
            crop.earlyEnd = {after = xml:getString(key .. ".earlyEnd#after"), method = xml:getString(key .. ".earlyEnd#method", "mean"),
                             baseF = num(xml, key .. ".earlyEnd#baseF"), fullHu = num(xml, key .. ".earlyEnd#fullHu"),
                             lossPer100 = num(xml, key .. ".earlyEnd#lossPer100"), killF = num(xml, key .. ".earlyEnd#killingFreezeF"),
                             minHours = num(xml, key .. ".earlyEnd#minHours")}
        end
        -- clocks that start at a stage (one per stage name; first definition wins)
        crop.clocks = {}
        local function addClock(after, method, baseF, capF, earlyCapF, switchDD)
            if after ~= nil and crop.clocks[after] == nil then
                -- for an "ndawn" clock, switchDD is read on the planting clock (e.g. Haun 2.0 = 395 GDD after planting)
                crop.clocks[after] = {method = method or "mean", baseF = baseF, capF = capF, earlyCapF = earlyCapF, switchDD = switchDD}
            end
        end
        xml:iterate(key .. ".clock", function(_, ck)
            addClock(xml:getString(ck .. "#after"), xml:getString(ck .. "#method", "mean"), num(xml, ck .. "#baseF"), num(xml, ck .. "#capF"),
                num(xml, ck .. "#earlyCapF"), num(xml, ck .. "#switchDD"))
        end)
        for _, t in ipairs(crop.tables) do addClock(t.after, t.method, t.baseF, t.capF) end
        if crop.earlyEnd ~= nil then addClock(crop.earlyEnd.after, crop.earlyEnd.method, crop.earlyEnd.baseF, nil) end
        -- freeze rules off for these planting months (the stage sources are spring-sown; fall plantings have no sourced clock)
        crop.freezeOffMonths = {}
        local fo = xml:getString(key .. ".freezeOff#plantedMonths")
        if fo ~= nil then
            for m in fo:gmatch("%d+") do crop.freezeOffMonths[tonumber(m)] = true end
        end
        if xml:hasProperty(key .. ".weathering") then
            crop.weatherPerInch = num(xml, key .. ".weathering#perInchRain")
        end
        local hasDays = false
        for _, st in ipairs(crop.stages) do if st.days ~= nil then hasDays = true end end
        crop.winterOnly = xml:getString(key .. "#winterOnly", "") == "true"   -- v0.23 grass: record only for winterkill (CFAWinter.lua)
        if crop.growth.baseF ~= nil or hasDays or crop.hail ~= nil or crop.wind ~= nil or #crop.waterlog > 0 or crop.floodModel ~= nil or crop.winterOnly or #crop.coldLoss > 0 then
            C.variants[crop.fruit] = C.variants[crop.fruit] or {}
            table.insert(C.variants[crop.fruit], crop)
            if crop.plantedMonths == nil or C.crops[crop.fruit] == nil then C.crops[crop.fruit] = crop end
            count = count + 1
        end
    end)
    -- v0.27.2 (team 2026-11-13): map crops that are the same plant as a crop we have (e.g. Sandy Hills Farms FEEDCORN = corn)
    xml:iterate("cropWeather.alias", function(_, ak)
        local f, same = xml:getString(ak .. "#fruit"), xml:getString(ak .. "#sameAs")
        if f ~= nil and same ~= nil and C.variants[same] ~= nil and C.variants[f] == nil then
            C.variants[f] = C.variants[same]
            C.crops[f] = C.crops[same]
            log("crop %s uses the %s numbers (same plant)", f, same)
        end
    end)
    C.soil = {name = xml:getString("cropWeather.soil#name"), awc = num(xml, "cropWeather.soil#awc"), layers = {}}
    xml:iterate("cropWeather.soilLayer", function(_, lk)
        local l = {top = num(xml, lk .. "#topCm"), bottom = num(xml, lk .. "#bottomCm"), sat = num(xml, lk .. "#sat"), fc = num(xml, lk .. "#fc")}
        if l.top and l.bottom and l.sat and l.fc then table.insert(C.soil.layers, l) end
    end)
    C.waterlogging = {airFilled = num(xml, "cropWeather.waterlogging#airFilled"), drainDays = num(xml, "cropWeather.waterlogging#drainDays"),
                      depthM = num(xml, "cropWeather.waterlogging#depthM")}
    xml:delete()
    log("loaded %d crops from %s (soil %s, water held %.2f m3/m3)", count, C.DATA_FILE, tostring(C.soil.name), C.soil.awc or 0)
    return count > 0
end

-- The definition that fits this field: one limited to its planting month wins, otherwise the general one.
function C.cropFor(fruit, plantedMonth)
    local list = C.variants[fruit or ""]
    if list == nil then return nil end
    local general = nil
    for _, crop in ipairs(list) do
        if crop.plantedMonths ~= nil then
            if plantedMonth ~= nil and crop.plantedMonths[plantedMonth] then return crop end
        elseif general == nil then
            general = crop
        end
    end
    return general
end

-- ------------------------------------------------------------------ degree days

function C.degreeDays(method, baseF, capF, hiF, loF, g, ddSoFar)
    if baseF == nil then return 0 end
    if method == "ndawn" then
        -- NDAWN (Bauer et al.): max and min below base set to base; max capped at earlyCapF until switchDD, then at capF
        local cap = capF or math.huge
        if g ~= nil and g.earlyCapF ~= nil and g.switchDD ~= nil and (ddSoFar or 0) < g.switchDD then cap = g.earlyCapF end
        local hi = math.max(math.min(hiF, cap), baseF)
        local lo = math.max(loF, baseF)
        return math.max(0, (hi + lo) / 2 - baseF)
    end
    if method == "dd50ar" then
        -- U of Arkansas Rice DD50: max set to 94 F when above 94, min set to 70 F when above 70 (at most 32 units a day)
        local hi = math.min(hiF, 94)
        local lo = math.min(loF, 70)
        return math.max(0, (hi + lo) / 2 - baseF)
    end
    if method == "capped" then
        local cap = capF or math.huge
        local hi = math.max(math.min(hiF, cap), baseF)
        local lo = math.min(math.max(loF, baseF), cap)
        return math.max(0, (hi + lo) / 2 - baseF)
    end
    return math.max(0, (hiF + loF) / 2 - baseF)
end

function C.currentStage(crop, rec)
    local idx = 0
    for i, st in ipairs(crop.stages) do
        if st.days ~= nil then
            if (rec.days or 0) >= st.days then idx = i end
        elseif st.dd ~= nil then
            if st.from ~= nil then
                -- counted on the clock that starts at another stage (e.g. NDSU W-564 counts from emergence)
                local v = rec.after[st.from]
                if v ~= nil and v >= st.dd then idx = i end
            elseif rec.dd >= st.dd then
                idx = i
            end
        end
    end
    return idx
end

-- ------------------------------------------------------------------ fields

local function fieldId(field)
    if type(field.getId) == "function" then
        local ok, id = true, field.getId(field)
        if ok and id ~= nil then return id end
    end
    return field.fieldId or field.id
end

local function fieldState(field)
    local s = field.fieldState
    if type(s) ~= "table" and type(field.getFieldState) == "function" then
        local ok, v = true, field.getFieldState(field)
        if ok then s = v end
    end
    if type(s) ~= "table" then return nil end
    -- v0.16.1: the game's stored field state is not refreshed when the player works the field (test field 25:
    -- planted canola, stored state still said rye). Read the ground at the field's marker first, as the game's own
    -- field tools do (EasyDevControls: field:getIndicatorPosition() -> fieldState:update(x, z)).
    if type(s.update) == "function" and type(field.getIndicatorPosition) == "function" then
        local okP, x, z = true, field.getIndicatorPosition(field)
        if okP and x ~= nil and z ~= nil then
            s.update(s, x, z)
        end
    end
    if s.isValid == false then return nil end
    return s
end

C.fieldIdOf = fieldId          -- v0.23: shared with CFAWinter
C.fieldStateOf = fieldState

local function polygonOf(field)
    if field.cfaPoly ~= nil then return field.cfaPoly end
    local pts = nil
    if type(field.getPolygonPoints) == "function" then
        local ok, v = true, field.getPolygonPoints(field)
        if ok then pts = v end
    end
    pts = pts or field.polygonPoints
    if type(pts) ~= "table" then return nil end
    local poly = {minX = math.huge, maxX = -math.huge, minZ = math.huge, maxZ = -math.huge}
    for _, p in ipairs(pts) do
        local x, z
        if type(p) == "table" then
            x, z = p.x or p[1], p.z or p[2]
        else
            local wx, _, wz = getWorldTranslation(p)
            x, z = wx, wz
        end
        if x ~= nil and z ~= nil then
            table.insert(poly, {x, z})
            poly.minX, poly.maxX = math.min(poly.minX, x), math.max(poly.maxX, x)
            poly.minZ, poly.maxZ = math.min(poly.minZ, z), math.max(poly.maxZ, z)
        end
    end
    if #poly < 3 then return nil end
    field.cfaPoly = poly
    return poly
end

local function inPolygon(poly, x, z)
    if x < poly.minX or x > poly.maxX or z < poly.minZ or z > poly.maxZ then return false end
    local inside, j = false, #poly
    for i = 1, #poly do
        local xi, zi, xj, zj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]
        if ((zi > z) ~= (zj > z)) and (x < (xj - xi) * (z - zi) / (zj - zi) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

function C.fieldAt(x, z)
    if g_fieldManager == nil then return nil end
    for _, field in pairs(g_fieldManager.fields) do
        local poly = polygonOf(field)
        if poly ~= nil and inPolygon(poly, x, z) then return field end
    end
    return nil
end

local function isGrowingState(desc, gs)
    if gs == nil or gs <= 0 then return false end
    if desc.witheredState ~= nil and gs == desc.witheredState then return false end
    if desc.cutState ~= nil and gs == desc.cutState then return false end
    if desc.maxHarvestingGrowthState ~= nil and gs > desc.maxHarvestingGrowthState then return false end
    return true
end

local function isHarvestReady(desc, gs)
    return desc.minHarvestingGrowthState ~= nil and gs ~= nil
        and gs >= desc.minHarvestingGrowthState and gs <= (desc.maxHarvestingGrowthState or gs)
end

function C.monthOf(day)
    if CFAWeather ~= nil and CFAWeather.active then
        local d = CFAWeather.getDay ~= nil and CFAWeather.getDay(day) or nil
        if d ~= nil and d.month ~= nil then return d.month end
        if CFAWeather.monthAtDay ~= nil then return CFAWeather.monthAtDay(day) end
    end
    return nil
end

-- Hourly: notice new plantings, harvest-ready crops and finished crops.
function C.scanFields()
    if g_fieldManager == nil then return end
    local today = g_currentMission.environment.currentMonotonicDay
    for _, field in pairs(g_fieldManager.fields) do
        C.scanField(field, today)
    end
end

-- v0.25.8 (team 2026-11-07): the hourly scan is spread over frames, SCAN_PER_FRAME fields a frame, so it never lands as one spike.
C.SCAN_PER_FRAME = 16
function C.startScan()
    if g_fieldManager == nil then return end
    local q = {}
    for _, field in pairs(g_fieldManager.fields) do q[#q + 1] = field end
    C.scanQueue, C.scanPos, C.scanDay = q, 1, g_currentMission.environment.currentMonotonicDay
end

-- returns true when the scan has finished
function C.scanSlice()
    local q = C.scanQueue
    if q == nil then return true end
    local last = math.min(#q, C.scanPos + C.SCAN_PER_FRAME - 1)
    for i = C.scanPos, last do C.scanField(q[i], C.scanDay) end
    C.scanPos = last + 1
    if C.scanPos > #q then C.scanQueue = nil; return true end
    return false
end

function C.scanField(field, today)
    do
        local id = fieldId(field)
        local s = fieldState(field)
        if id ~= nil and s ~= nil then
            local fi = s.fruitTypeIndex
            local desc = (fi ~= nil and fi ~= FruitType.UNKNOWN) and g_fruitTypeManager:getFruitTypeByIndex(fi) or nil
            local rec = C.fields[id]
            if desc ~= nil and isGrowingState(desc, s.growthState) and C.crops[desc.name:upper()] ~= nil then
                local name = desc.name:upper()
                if rec == nil or rec.fruit ~= name or (rec.done and not isHarvestReady(desc, s.growthState)) then
                    if rec ~= nil then C.autoClaim(id, rec) end
                    rec = {fruit = name, planted = today, plantedMonth = C.monthOf(today), dd = 0, after = {}, loss = 0, weatherLoss = 0, rainIn = 0,
                           ready = false, lastDay = today - 1, events = {}}
                    C.fields[id] = rec
                    if s.growthState >= 2 then rec.needBackfill = true end   -- v0.14: already past sowing when first seen
                    C.onPlanted(id, rec)
                    if not C.stationConfirmed and not rec.needBackfill then rec.waitPlanted = true end
                end
                if rec.needBackfill and C.stationConfirmed then
                    if s.growthState < 2 then
                        rec.needBackfill = nil
                    elseif C.backfill(id, rec) ~= nil then
                        rec.needBackfill = nil
                    end
                end
                rec.ready = isHarvestReady(desc, s.growthState)
                rec.growthState = s.growthState
                rec.maxGrowth = desc.minHarvestingGrowthState
            elseif rec ~= nil and not rec.done then
                -- v0.25.11: a harvest-ready peanut field that leaves harvest-ready was dug into windrows
                if rec.fruit == "PEANUT" and rec.ready and CFAPeanut ~= nil then
                    CFAPeanut.onDug(field, id, today, C.lastScale)
                end
                rec.done = true   -- harvested, withered, or cleared
                C.autoClaim(id, rec)
            end
        end
    end
end

-- ------------------------------------------------------------------ daily step

local function rangeValue(rule)
    if rule.loss ~= nil then return rule.loss end
    if rule.lossLow ~= nil and rule.lossHigh ~= nil then
        if C.settings.rangePick == "high" then return rule.lossHigh end
        if C.settings.rangePick == "low" then return rule.lossLow end
        return nil   -- off: a range is never turned into one number on its own
    end
    return nil
end

-- A rule is hit when the day's low reaches its temperature. If the source names a duration (minHours, e.g. K-State /
-- Kentucky "two hours or more"), the hour-by-hour day (NOAA hourly shape) must stay there that many hours.
local function hits(rule, loF, cold)
    local function check(th, strict)
        if th == nil then return false end
        if strict then
            if not (loF < th) then return false end
        elseif not (loF <= th) then
            return false
        end
        if rule.minHours ~= nil then
            local n = cold ~= nil and cold(th, strict) or nil
            if n == nil then return false end   -- no hourly shape available: a duration rule cannot be checked = off
            return n >= rule.minHours
        end
        return true
    end
    return check(rule.atOrBelow, false) or check(rule.below, true)
end

-- Freeze check for one field on one day. Returns the loss % (or nil) and a label.
function C.freezeLoss(crop, rec, loF, cold)
    if rec.ready then return nil end              -- harvest-ready = mature: no freeze loss
    if rec.plantedMonth ~= nil and crop.freezeOffMonths ~= nil and crop.freezeOffMonths[rec.plantedMonth] then return nil end
    local best, label = nil, nil
    local stageIdx = C.currentStage(crop, rec)
    -- stage-table rules (heat units after a stage)
    for _, t in ipairs(crop.tables) do
        local hu = rec.after[t.after]
        if hu ~= nil then
            for _, d in ipairs(t.damage) do
                if hits(d, loF, cold) then
                    local loss = nil
                    for _, row in ipairs(d.rows) do
                        if row.hu ~= nil and hu >= row.hu then loss = row.loss end
                    end
                    if loss ~= nil and (best == nil or loss > best) then
                        best, label = loss, string.format("%s, %.0f HU after %s", d.name, hu, t.after)
                    end
                end
            end
        end
    end
    -- fixed stage rules
    for _, r in ipairs(crop.stageRules) do
        local from = crop.stageIndex[r.stage]
        local to = r.untilStage ~= nil and crop.stageIndex[r.untilStage] or nil
        if from ~= nil and stageIdx >= from and (to == nil or stageIdx < to) and hits(r, loF, cold) then
            local loss = rangeValue(r)
            if loss ~= nil and (best == nil or loss > best) then
                best, label = loss, "at " .. r.stage
            end
        end
    end
    -- graded freeze curves: the worst row the day's low reaches
    for _, c in ipairs(crop.curves or {}) do
        local from = crop.stageIndex[c.stage]
        local to = c.untilStage ~= nil and crop.stageIndex[c.untilStage] or nil
        if from ~= nil and stageIdx >= from and (to == nil or stageIdx < to) then
            for _, row in ipairs(c.rows) do
                if row.loss ~= nil and hits({atOrBelow = row.atOrBelow, minHours = c.minHours}, loF, cold) and (best == nil or row.loss > best) then
                    best, label = row.loss, string.format("at %s, low at or below %.1f F", c.stage, row.atOrBelow)
                end
            end
        end
    end
    -- early end (cotton): killing freeze ends boll fill
    local e = crop.earlyEnd
    if e ~= nil and e.killF ~= nil and hits({atOrBelow = e.killF, minHours = e.minHours}, loF, cold) then
        local hu = rec.after[e.after]
        if hu ~= nil and e.fullHu ~= nil and e.lossPer100 ~= nil then
            local short = math.max(0, e.fullHu - hu)
            local loss = math.min(100, short / 100 * e.lossPer100)
            if best == nil or loss > best then
                best, label = loss, string.format("killing freeze %.0f DD60 short", short)
            end
        end
    end
    return best, label
end

-- Share of this step that falls after a stage was reached: 1 if the stage was reached before the step,
-- otherwise the part of the step past the stage, assuming the step's degree days are spread evenly.
function C.shareAfterStage(st, ddBefore, ddAfter, afterBefore, afterNow)
    if st == nil or st.dd == nil then return 1 end
    local before, now = ddBefore, ddAfter
    if st.from ~= nil then
        before, now = afterBefore[st.from], afterNow[st.from]
        if now == nil then return 0 end
        before = before or 0
    end
    if before >= st.dd then return 1 end
    local added = now - before
    if added <= 0 then return 0 end
    return math.max(0, math.min(1, (now - st.dd) / added))
end

-- Share of game days in a month that are thunder days in CFA's weather (long-run wet-day share x thunder share of wet days).
function C.thunderDayShare(month)
    if CFAWeather == nil or CFAStationData == nil or CFAStationData.thunderChance == nil then return nil end
    local st = CFAWeather.getStation ~= nil and CFAWeather.getStation() or nil
    local p = st ~= nil and st.months ~= nil and st.months[month] or nil
    if p == nil then return nil end
    local pwd, pww = p[1], p[2]
    local denom = 1 - pww + pwd
    if denom <= 0 then return nil end
    local th = (CFAWeather.region ~= nil and CFAWeather.region() or CFAStationData).thunderChance   -- v0.16: station's own state
    return (pwd / denom) * (th[month] or 0)
end

-- FAO-56 Eq. 21-25: extraterrestrial radiation Ra (mm/day equivalent, x 0.408) for a latitude and day of year.
function C.raMm(latDeg, doy)
    local phi = latDeg * math.pi / 180
    local dr = 1 + 0.033 * math.cos(2 * math.pi * doy / 365)
    local delta = 0.409 * math.sin(2 * math.pi * doy / 365 - 1.39)
    local x = math.max(-1, math.min(1, -math.tan(phi) * math.tan(delta)))
    local ws = math.acos(x)
    local ra = (24 * 60 / math.pi) * 0.0820 * dr * (ws * math.sin(phi) * math.sin(delta) + math.cos(phi) * math.cos(delta) * math.sin(ws))
    return 0.408 * ra
end

-- FAO-56 Eq. 52 (Hargreaves): ETo mm/day from Tmax/Tmin in C.
function C.et0(tmaxC, tminC, latDeg, doy)
    local tmean = (tmaxC + tminC) / 2
    return math.max(0, 0.0023 * (tmean + 17.8) * math.sqrt(math.max(0, tmaxC - tminC)) * C.raMm(latDeg, doy))
end

C.MID_DOY = {15, 46, 74, 105, 135, 166, 196, 227, 258, 288, 319, 349}   -- day of year of the 15th of each month

-- Kc for where the crop is in its season (FAO-56 Table 11 stage lengths as fractions; Table 12 Kc ini / mid / end).
function C.kcAt(d, f)
    local T = d.lIni + d.lDev + d.lMid + d.lLate
    local b1, b2, b3 = d.lIni / T, (d.lIni + d.lDev) / T, (d.lIni + d.lDev + d.lMid) / T
    if f < b1 then return d.kcIni end
    if f < b2 then return d.kcIni + (d.kcMid - d.kcIni) * (f - b1) / (b2 - b1) end
    if f < b3 then return d.kcMid end
    return d.kcMid + (d.kcEnd - d.kcMid) * math.min(1, (f - b3) / (1 - b3))
end

-- v0.14.2: root-zone average water content at saturation and at field capacity (m3/m3), depth-weighted over 0..rootM.
function C.soilWindow(rootM)
    if C.soil == nil or C.soil.layers == nil or #C.soil.layers == 0 then return nil end
    local zcm = rootM * 100
    local sumSat, sumFc, sumT = 0, 0, 0
    for _, l in ipairs(C.soil.layers) do
        local t = math.max(0, math.min(l.bottom, zcm) - l.top)
        if t > 0 then sumSat, sumFc, sumT = sumSat + l.sat * t, sumFc + l.fc * t, sumT + t end
    end
    if sumT <= 0 then return nil end
    return sumSat / sumT, sumFc / sumT
end

-- Is the field's current stage inside [from, until)? from "" = planting; until nil = to harvest.
function C.inStageWindow(crop, rec, from, untilStage)
    local si = C.currentStage(crop, rec)
    local a = (from == nil or from == "") and 0 or crop.stageIndex[from]
    if a == nil or si < a then return false end
    if untilStage ~= nil and untilStage ~= "" then
        local b = crop.stageIndex[untilStage]
        if b == nil or si >= b then return false end
    end
    return true
end

-- One game day of the root-zone water balance (FAO-56 Eq. 82-86), done in 1-day steps for the real days it stands for.
function C.droughtStep(rec, crop, hiF, loF, rainIn, scale, month)
    local d = crop.drought
    if d == nil or C.soil == nil or C.soil.awc == nil or month == nil or rec.ready then return end
    local st = CFAWeather ~= nil and CFAWeather.getStation ~= nil and CFAWeather.getStation() or nil
    if st == nil or st.lat == nil then return end
    local f = 0
    if rec.growthState ~= nil and rec.maxGrowth ~= nil and rec.maxGrowth > 1 then
        f = math.max(0, math.min(1, (rec.growthState - 1) / (rec.maxGrowth - 1)))
    end
    local kc = C.kcAt(d, f)
    local tmax, tmin = (hiF - 32) / 1.8, (loF - 32) / 1.8
    local et0 = C.et0(tmax, tmin, st.lat, C.MID_DOY[month])
    local taw = 1000 * C.soil.awc * d.rootM
    local rainMm = (rainIn or 0) * 25.4
    local steps = math.max(1, math.floor(scale + 0.5))
    local w = scale / steps
    rec.dr = rec.dr or 0
    rec.wx = rec.wx or 0
    -- v0.14.2 waterlogging: water above field capacity is held up to saturation and drains back over drainDays (UGA B-892)
    local wl = C.waterlogging
    local zw = (wl ~= nil and wl.depthM ~= nil) and math.min(wl.depthM, d.rootM) or nil   -- surface zone checked (SEW30: top 30 cm)
    local sat, fc = nil, nil
    if zw ~= nil then sat, fc = C.soilWindow(zw) end
    local useWl = wl ~= nil and wl.airFilled ~= nil and wl.drainDays ~= nil and sat ~= nil and (#crop.waterlog > 0 or crop.floodModel ~= nil)
    local cap = useWl and math.max(0, 1000 * (sat - fc) * zw) or 0                       -- mm the surface zone holds above field capacity
    local tawZ = useWl and 1000 * C.soil.awc * zw or 0
    -- Time compression: one game day stands for 'steps' real days. For the drought total the day's rain is counted on every one of
    -- them (season totals stay right). For waterlogging that would turn one rainy day into a 10-day flood, so the rain is placed as
    -- ONE wet spell: its length = the station's mean wet-spell length 1 / (1 - P(wet|wet)) from the NOAA-fitted WGEN parameters
    -- (same station data the weather uses), then dry days. A separate copy of the root-zone deficit is used for this.
    local wetDays, wdr = 0, (taw > 0 and useWl) and (rec.dr / taw) * tawZ or 0   -- surface zone starts as dry (relatively) as the root zone
    if useWl and rainMm > 0 then
        local stn = st.months ~= nil and st.months[month] or nil
        local pww = stn ~= nil and stn[2] or nil
        wetDays = (pww ~= nil and pww < 1) and math.max(1, math.min(steps, math.floor(1 / (1 - pww) + 0.5))) or 1
    end
    for k = 1, steps do
        local etc = kc * et0
        local p = math.max(0.1, math.min(0.8, d.p + 0.04 * (5 - etc)))
        local raw = p * taw
        local ks = 1
        if rec.dr > raw then ks = math.max(0, (taw - rec.dr) / ((1 - p) * taw)) end
        local eta = ks * etc
        if #crop.droughtStress > 0 then
            if ks < 1 then
                rec.dsRun = (rec.dsRun or 0) + w
                for _, r in ipairs(crop.droughtStress) do
                    if rec.dsRun >= r.days and r.loss > (rec.dsLoss or 0) and C.inStageWindow(crop, rec, r.from, r.untilStage) then
                        rec.dsLoss = r.loss
                        table.insert(rec.events, string.format("water stress %.0f days (%s-%s): %.0f %% (%s)", rec.dsRun,
                            r.from ~= "" and r.from or "planting", r.untilStage or "harvest", r.loss, r.source))
                        log("%s: water stress %.0f days -> %.0f %% yield loss (%s)", rec.fruit, rec.dsRun, r.loss, r.source)
                    end
                end
            else
                rec.dsRun = 0
            end
        end
        rec.etm = (rec.etm or 0) + etc * w
        rec.eta = (rec.eta or 0) + eta * w
        rec.dr = math.max(0, math.min(taw, rec.dr - rainMm * w + eta * w))
        if useWl then
            local rainWl = (k <= wetDays) and rainMm or 0
            local b = rec.wx - wdr + rainWl * w - eta * w           -- storage relative to field capacity (mm)
            if b > 0 then b = math.max(0, b - cap / wl.drainDays * w) end
            b = math.min(cap, b)                                    -- above saturation runs off
            rec.wx = math.max(0, b)
            wdr = math.max(0, math.min(tawZ, -b))
            local air = (sat - fc) - rec.wx / (1000 * zw)            -- air-filled pore space in the surface zone, m3/m3
            if air < wl.airFilled and not rec.dormant then
                rec.wlRun = (rec.wlRun or 0) + w
                local fm = crop.floodModel
                if fm ~= nil and rec.plantedMonth ~= nil and month ~= nil and month >= rec.plantedMonth then
                    local b = fm.base[month - rec.plantedMonth + 1]
                    if b ~= nil and b ~= 0 then
                        -- the AGFL tool takes 1-30 flood days ("values limited to 1 to 30 days")
                        local loss = math.max(0, math.min(100, b + fm.perDay * math.min(rec.wlRun, 30)))
                        if loss > (rec.wlLoss or 0) then
                            rec.wlLoss = loss
                        end
                        if loss >= (rec.wlLogged or 0) + 5 then
                            rec.wlLogged = loss
                            table.insert(rec.events, string.format("flooded %.0f days in growth month %d: %.1f %% (%s)", rec.wlRun, month - rec.plantedMonth + 1, loss, fm.source))
                            log("%s: flooded %.0f days (growth month %d) -> %.1f %% yield loss (%s)", rec.fruit, rec.wlRun, month - rec.plantedMonth + 1, loss, fm.source)
                        end
                    end
                end
                for _, r in ipairs(crop.waterlog) do
                    if rec.wlRun >= r.days and r.loss > (rec.wlLoss or 0) and C.inStageWindow(crop, rec, r.from, r.untilStage) then
                        rec.wlLoss = r.loss
                        table.insert(rec.events, string.format("waterlogged %.0f days (%s-%s): %.0f %% (%s)", rec.wlRun,
                            r.from ~= "" and r.from or "planting", r.untilStage or "harvest", r.loss, r.source))
                        log("%s: waterlogged %.0f days -> %.0f %% yield loss (%s)", rec.fruit, rec.wlRun, r.loss, r.source)
                    end
                end
            else
                rec.wlRun = 0
            end
        end
    end
    if rec.etm > 0 then
        rec.droughtLoss = math.max(0, math.min(100, 100 * d.ky * (1 - rec.eta / rec.etm)))
    end
    if (rec.dsLoss or 0) > (rec.droughtLoss or 0) then
        rec.droughtLoss = rec.dsLoss   -- v0.19: a stage stress rule counts when it is worse than the seasonal Ky loss
    end
end

-- v0.28 (team 2026-11-14): the weather station is in Europe. Wind and freeze-claim numbers come from USDA RMA claims (U.S. farms
-- only), so they are off in Europe until European numbers are found (Rule #1). Weather, growth, frost thresholds, drought
-- (FAO-56), heat and hay curing run. Hail and insurance use the European numbers below.
function C.inEurope()
    local st = CFAWeather ~= nil and CFAWeather.getStation ~= nil and CFAWeather.getStation() or nil
    return st ~= nil and CFAWeather.EUROPE ~= nil and CFAWeather.EUROPE[st.state] ~= nil
end
function C.euCountry()
    local st = CFAWeather ~= nil and CFAWeather.getStation ~= nil and CFAWeather.getStation() or nil
    if st == nil or not C.inEurope() then return nil end
    return st.country
end
-- v0.28 (team 2026-11-14, "US hit size, EU total"): Europe publishes only the yearly hail loss for all crops together, as a share
-- of the insured crop value. A hit takes the crop's USDA hail loss (its size), and hits come just often enough that the year's
-- expected loss equals the European number, spread over the station's thunder days.
--   DE: GDV crop hail insurance loss rate (claims / sum insured), 1991-2020 mean 0.863 % a year (GDV Naturgefahrenreport 2024,
--       Datenservice p. 57; 1993 = 2.17 % and 2021 = 0.89 % match UBA indicator LW-I-3).
--   PL: Ministry of Agriculture, payouts for hail / storm / heavy rain / lightning over sum insured, 2023 0.741 % and
--       2024 1.325 % - high end of the two years (Rule #1).
C.EU_HAIL_PCT = {DE = 0.863, PL = 1.325}
C.EU_HAIL_SRC = {DE = "GDV Germany 1991-2020", PL = "Poland MRiRW 2024"}
function C.thunderDaysPerYear()
    local t = 0
    for m = 1, 12 do t = t + C.MONTH_DAYS[m] * (C.thunderDayShare(m) or 0) end
    return t
end
-- v0.28 (2026-11-14, same method as European hail): POLAND spring frost and winter-kill. Size of a hit: the crop's USDA claim
-- loss for that cause (spring frost: "frost", else "freeze"; winter-kill: "coldWinter"). How often: so the year's expected loss
-- equals Poland's payouts over sum insured, on freezing days (low <= 32 F) in the policy's risk months.
--   Spring frost (risk period 15 Apr - 30 Jun): 2023 0.351 %, 2024 1.192 % -> 1.192 % (high end, Rule #1).
--   Winter-kill (risk period 1 Dec - 30 Apr): 2023 0.023 %, 2024 0.089 %, 2017-2019 (first half) 0.257 % -> 0.257 % (high end).
--   Sources: Ministry of Agriculture answer to Sejm interpellation 10824 (2023, 2024); NIK audit "System ubezpieczen rolniczych"
--   (2017-2019 H1: sum insured 48,884,466.5 thousand zl; winter-kill 125,741.2, spring frost 146,422.8 = 0.300 %, hail group
--   430,192.6 = 0.880 % - both below the 2024 numbers); risk periods: Rzecznik Finansowy analysis 2023.
--   April counts whole in both windows (the game's days carry the month only). Germany: no published split - off.
C.EU_COLD = {PL = {
    {cause = "spring frost", pct = 1.192, months = {[4] = true, [5] = true, [6] = true}, use = {"frost", "freeze"}},
    {cause = "winter-kill", pct = 0.257, months = {[12] = true, [1] = true, [2] = true, [3] = true, [4] = true}, use = {"coldWinter"}},
}}
function C.euColdRoll(crop, month, scale)
    local list = C.EU_COLD[C.euCountry() or ""]
    if list == nil then return nil end
    for _, r in ipairs(list) do
        if r.months[month] then
            local h = nil
            for _, want in ipairs(r.use) do
                for _, x in ipairs(crop.coldLoss) do
                    if h == nil and x.cause == want and (x.lossPct or 0) > 0 then h = x end
                end
            end
            if h ~= nil then
                local D = 0
                for m in pairs(r.months) do D = D + C.MONTH_DAYS[m] * (C.freezeDayShare(m) or 0) end
                if D > 0 and math.random() < math.min(1, (r.pct / h.lossPct) * scale / D) then
                    return h.lossPct, {cause = r.cause, state = "size USDA " .. tostring(h.state) .. ", how often Poland MRiRW 2024"}
                end
            end
        end
    end
    return nil
end

-- Poland: one subsidized policy for the crops the law covers (CFAInsurance.PL_ALL); Germany: no premium numbers yet (off).
function C.euInsurance(fruit)
    local cc = C.euCountry()
    if CFAInsurance == nil then return nil end
    if cc == "PL" and CFAInsurance.PL_CROPS ~= nil then
        if CFAInsurance.PL_CROPS[fruit] then return CFAInsurance.PL_ALL end
    elseif cc == "FR" and CFAInsurance.FR_ALL ~= nil then   -- v0.28 (team 2026-11-14): French all-weather (MRC) policy, all crops
        return CFAInsurance.FR_ALL
    elseif cc == "DE" and CFAInsurance.DE_CROPS ~= nil then   -- v0.28 (team 2026-11-14): German hail policy
        local plan = CFAInsurance.DE_CROPS[fruit]
        if plan == "DEH" then return CFAInsurance.DE_HAIL elseif plan == "DEHV" then return CFAInsurance.DE_HAIL_VEG end
    end
    return nil
end

-- Hail: the lead state's monthly chance that an acre has an insured hail loss (RMA determined acres / NASS planted acres),
-- spread over this month's thunder days; a hit takes the lead state's insured hail loss share on damaged acres.
function C.hailRoll(crop, month, scale, thunder)
    local h = crop.hail
    if h == nil or not thunder or month == nil then return nil end
    if C.inEurope() then
        local L = C.EU_HAIL_PCT[C.euCountry() or ""]
        if L == nil or h.lossPct == nil or h.lossPct <= 0 then return nil end
        local T = C.thunderDaysPerYear()
        if T <= 0 then return nil end
        local p = math.min(1, (L / h.lossPct) * scale / T)
        if math.random() < p then return h.lossPct end
        return nil
    end
    local share = C.thunderDayShare(month)
    if share == nil or share <= 0 then return nil end
    local p = math.min(1, (h.chance[month] or 0) * scale / (C.MONTH_DAYS[month] * share))
    if math.random() < p then return h.lossPct end
    return nil
end

-- v0.27: share of days in a month with a low at or below 32 F at the station, from the station's own WGEN numbers
-- (dry / wet day low mean and spread, wet-day share) - normal distribution, the same model that makes CFA's days.
local function phi(z)   -- standard normal CDF (Abramowitz & Stegun 26.2.17)
    local t = 1 / (1 + 0.2316419 * math.abs(z))
    local d = 0.3989423 * math.exp(-z * z / 2)
    local p = d * t * (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274))))
    if z > 0 then return 1 - p end
    return p
end
function C.freezeDayShare(month)
    if CFAWeather == nil or CFAWeather.getStation == nil then return nil end
    local st = CFAWeather.getStation()
    local p = st ~= nil and st.months ~= nil and st.months[month] or nil
    if p == nil then return nil end
    local denom = 1 - p[2] + p[1]
    if denom <= 0 then return nil end
    local w = p[1] / denom
    local pd = (p[11] or 0) > 0 and phi((32 - p[9]) / p[11]) or 0
    local pw = (p[12] or 0) > 0 and phi((32 - p[10]) / p[12]) or 0
    return (1 - w) * pd + w * pw
end

-- v0.27 (team option B): RMA freeze / frost / cold-winter claims. The month's chance is spread over the station's freezing days,
-- the same way hail is spread over thunder days: only a day with a low at or below 32 F can bring one.
function C.coldRoll(crop, month, scale, loF)
    if crop.coldLoss == nil or #crop.coldLoss == 0 or month == nil or loF == nil or loF > 32 then return nil end
    if C.inEurope() then return C.euColdRoll(crop, month, scale) end
    local share = C.freezeDayShare(month)
    if share == nil or share <= 0.001 then return nil end
    for _, h in ipairs(crop.coldLoss) do
        local p = math.min(1, (h.chance[month] or 0) * scale / (C.MONTH_DAYS[month] * share))
        if math.random() < p then return h.lossPct, h end
    end
    return nil
end

-- v0.19 Wind: the lead state's monthly chance of an insured wind loss, spread over all days of the month (not only thunder days).
function C.windRoll(crop, month, scale)
    local h = crop.wind
    if h == nil or month == nil or C.inEurope() then return nil end
    local p = math.min(1, (h.chance[month] or 0) * scale / C.MONTH_DAYS[month])
    if math.random() < p then return h.lossPct end
    return nil
end

-- v0.25.20 (team 2026-11-11): tornado and hurricane / tropical storm by the weather station's STATE (CFAStormData.lua).
-- A state that grows the crop uses its own RMA numbers (0 if no claims in 25 years); a state with no acres uses the lead state.
function C.stormFor(cause, fruit)
    if CFAStormData == nil or CFAStormData[cause] == nil then return nil end
    local t = CFAStormData[cause][fruit]
    if t == nil then return nil end
    local st = CFAWeather ~= nil and CFAWeather.getStation ~= nil and CFAWeather.getStation() or nil
    local code = st ~= nil and st.state or nil
    if st ~= nil and st.country ~= nil then return nil end   -- v0.26/v0.28: USDA RMA storm numbers are U.S. only; Canada / Europe = no effect (Rule #1)
    local e, used = nil, nil
    if code ~= nil and t[code] ~= nil then
        e, used = t[code], code
    elseif CFAStormData.lead ~= nil and CFAStormData.lead[fruit] ~= nil then
        used = CFAStormData.lead[fruit]
        e = t[used]
    end
    if e == nil or (e.l or 0) <= 0 or e.c == nil then return nil, used end
    return e, used
end

-- Share of days in a month that are wet at the station (WGEN two-state chain: pwd / (1 - pww + pwd)).
function C.wetDayShare(month)
    if CFAWeather == nil or CFAWeather.getStation == nil then return nil end
    local st = CFAWeather.getStation()
    local p = st ~= nil and st.months ~= nil and st.months[month] or nil
    if p == nil then return nil end
    local denom = 1 - p[2] + p[1]
    if denom <= 0 then return nil end
    return p[1] / denom
end

-- Tornado: monthly chance spread over all days of the month (like wind).
function C.tornadoRoll(fruit, month, scale)
    if month == nil then return nil end
    local e, used = C.stormFor("tornado", fruit)
    if e == nil then return nil end
    local p = math.min(1, (e.c[month] or 0) * scale / C.MONTH_DAYS[month])
    if math.random() < p then return e.l, used end
    return nil
end

-- Hurricane / tropical storm: only on a rainy day, monthly chance spread over the month's wet days (like hail on thunder days).
function C.hurricaneRoll(fruit, month, scale, wet)
    if month == nil or not wet then return nil end
    local e, used = C.stormFor("hurricane", fruit)
    if e == nil then return nil end
    local share = C.wetDayShare(month)
    if share == nil or share <= 0 then return nil end
    local p = math.min(1, (e.c[month] or 0) * scale / (C.MONTH_DAYS[month] * share))
    if math.random() < p then return e.l, used end
    return nil
end

-- Move a field's clocks forward by one step: real days, the planting degree-day clock, and clocks that start at a stage.
function C.advanceClocks(rec, crop, hiF, loF, scale)
    local g = crop.growth
    rec.days = (rec.days or 0) + scale   -- real days since planting (v0.12)
    local ddBefore = rec.dd          -- planting clock before this step (NDAWN cap switch reads this)
    local afterBefore = {}
    for k, v in pairs(rec.after) do afterBefore[k] = v end
    local share = 1
    if g.startDays ~= nil then   -- v0.19: no clock before emergence (only the part of the step after it counts)
        share = math.max(0, math.min(1, (rec.days - g.startDays) / scale))
    end
    rec.dd = ddBefore + C.degreeDays(g.method, g.baseF, g.capF, hiF, loF, g, ddBefore) * scale * share
    -- v0.29 silage: the real day the crop reached R5 (dent) - corn whole-plant moisture dries down from there (Penn State)
    if rec.r5Days == nil and crop.stageIndex ~= nil and crop.stageIndex["R5"] ~= nil then
        local r5 = crop.stages[crop.stageIndex["R5"]].dd
        if r5 ~= nil and rec.dd >= r5 then
            local step = rec.dd - ddBefore
            local frac = step > 0 and math.max(0, math.min(1, (rec.dd - r5) / step)) or 0
            rec.r5Days = rec.days - scale * frac
        end
    end
    local stageIdx = C.currentStage(crop, rec)
    for afterName, ck in pairs(crop.clocks) do
        local si = crop.stageIndex[afterName]
        if si ~= nil and stageIdx >= si then
            local full = C.degreeDays(ck.method, ck.baseF, ck.capF, hiF, loF, ck, ddBefore) * scale
            rec.after[afterName] = (rec.after[afterName] or 0) + full * C.shareAfterStage(crop.stages[si], ddBefore, rec.dd, afterBefore, rec.after)
        end
    end
end

-- ------------------------------------------------------------------ backfill (v0.14)
-- A crop that was already growing when CFA first saw it (mod added mid-season, a map's pre-planted fields, or a save from
-- before v0.14) gets its clocks rebuilt instead of starting at zero:
--   planting date = the lead state's USDA NASS Crop Progress 5-year average, first week at or above 50 % planted (<plant> in the table);
--   weather from planting to today = NOAA U.S. Climate Normals 1991-2020 DAILY normal high / low for the CFA weather station
--   (CFANormals.lua; same "normal" idea as NDAWN: the 1991-2020 average for each calendar day).
-- Only the clocks are rebuilt. No freeze, hail, rain or drought loss is added for days CFA did not see (no weather was played).
local CUM = {0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334}
local function doyOf(m, d) return CUM[m] + d end
local function dateOfDoy(doy)
    doy = ((doy - 1) % 365) + 1
    for m = 12, 1, -1 do if doy > CUM[m] then return m, doy - CUM[m] end end
    return 1, doy
end

-- Real calendar date that a game day stands for (a game month of daysPerPeriod days spread over the real month).
function C.realDateOfDay(day)
    local m = C.monthOf(day)
    if m == nil then return nil end
    local env = g_currentMission.environment
    local today = env.currentMonotonicDay or day
    local dpp = math.max(1, env.daysPerPeriod or 1)
    local dip = math.max(1, env.currentDayInPeriod or 1)
    local idx = (dip - 1 + (day - today)) % dpp
    local d = math.min(C.MONTH_DAYS[m], math.floor(idx * C.MONTH_DAYS[m] / dpp) + 1)
    return m, d
end

C.normalCache = {}
function C.normalsFor(stationId)
    if stationId == nil or CFANormals == nil or CFANormals[stationId] == nil then return nil end
    local c = C.normalCache[stationId]
    if c == nil then
        local n = CFANormals[stationId]
        c = {hi = {}, lo = {}}
        for v in n.hi:gmatch("-?%d+") do table.insert(c.hi, tonumber(v) / 10) end
        for v in n.lo:gmatch("-?%d+") do table.insert(c.lo, tonumber(v) / 10) end
        if #c.hi ~= 365 or #c.lo ~= 365 then return nil end
        C.normalCache[stationId] = c
    end
    return c
end

-- Pick the definition (spring / fall variant) whose sourced planting date is the latest one on or before today.
-- A spring crop whose date is still ahead this year is not backfilled (it cannot be last year's crop).
-- v0.29.3: the weather station's country when it is not the U.S. (Canada or Europe) - planting dates must come from that country
function C.stationCountry()
    -- v0.29.11 (team): a map set in one country whose nearest station is across a border (Drumard: Dundalk, Ireland -> station in
    -- Northern Ireland) uses its own country's planting dates while that map's station is in use
    if CFAWeather ~= nil and CFAWeather.stationFromMapName ~= nil then
        local m = CFAWeather.stationFromMapName()
        if m ~= nil and m.plantCountry ~= nil and m.id == CFAWeather.stationId then return m.plantCountry end
    end
    local st = CFAWeather ~= nil and CFAWeather.getStation ~= nil and CFAWeather.getStation() or nil
    local cc = st ~= nil and st.country or nil
    if cc == nil or cc == "US" then return nil end
    return cc
end
function C.plantFor(crop)
    local cc = C.stationCountry()
    if cc == nil then return crop.plant end
    if crop.plantIn == nil then return nil end
    local st = CFAWeather ~= nil and CFAWeather.getStation ~= nil and CFAWeather.getStation() or nil
    local prov = st ~= nil and st.state ~= nil and crop.plantIn[cc .. ":" .. st.state] or nil
    -- v0.29.8: Ontario spring cereals have OMAFRA target dates by region (north = 46 N and up; southwest = west of 81 W; central / east = rest)
    if prov == nil and st ~= nil and st.state == "ON" and st.lat ~= nil and st.lon ~= nil then
        local reg = (st.lat >= 46 and "north") or (st.lon <= -81 and "southwest") or "central"
        prov = crop.plantIn[cc .. ":ON:" .. reg]
    end
    return prov or crop.plantIn[cc]
end

function C.backfillPlan(fruit, m, d)
    local list = C.variants[fruit or ""]
    if list == nil then return nil end
    local todayDoy = doyOf(m, d)
    -- v0.29.5: in months a fall-sown variant could be in the ground, a country with no fall date for it is not guessed (it could be
    -- a fall crop, and the spring date would be wrong)
    for _, crop in ipairs(list) do
        if crop.plantedMonths ~= nil and crop.plantedMonths[m] and C.plantFor(crop) == nil then return nil end
    end
    local best, bestDays = nil, nil
    for _, crop in ipairs(list) do
        local p = C.plantFor(crop)
        if p ~= nil then
            local days = todayDoy - doyOf(p.month, p.day)
            if days < 0 and crop.plantedMonths ~= nil and crop.plantedMonths[p.month] then days = days + 365 end   -- fall-sown: last year's sowing
            if days >= 0 and (bestDays == nil or days < bestDays) then best, bestDays = crop, days end
        end
    end
    return best, bestDays
end

function C.backfill(id, rec)
    local today = g_currentMission.environment.currentMonotonicDay
    local m, d = C.realDateOfDay(today)
    if m == nil then return nil end   -- weather part not ready yet: try again on the next scan
    local crop, days = C.backfillPlan(rec.fruit, m, d)
    if crop == nil then
        log("field %s %s: already growing, but no sourced planting date on or before %d/%d - clock starts today", tostring(id), rec.fruit, m, d)
        rec.backfill = "none"
        return false
    end
    local stationId = CFAWeather ~= nil and CFAWeather.stationId or nil
    local n = C.normalsFor(stationId)
    if n == nil then
        log("field %s %s: no daily normals for station %s - clock starts today", tostring(id), rec.fruit, tostring(stationId))
        rec.backfill = "none"
        return false
    end
    rec.dd, rec.days, rec.after, rec.r5Days = 0, 0, {}, nil
    local p = C.plantFor(crop)
    local start = doyOf(p.month, p.day)
    for k = 1, days do   -- NDAWN: degree days counted from the day after planting
        local doy = ((start + k - 1) % 365) + 1
        C.advanceClocks(rec, crop, n.hi[doy], n.lo[doy], 1)
    end
    rec.plantedMonth = p.month
    rec.backfill = string.format("%s %d/%d, %d days", p.state, p.month, p.day, days)
    rec.lastDay = today - 1
    log("field %s %s: backfilled from %s %s planting %d/%d (see Sources tab) to %d/%d: %d days, %.0f DD (daily normals, station %s)",
        tostring(id), rec.fruit, (C.stationCountry() == "DE" and "DWD phenology") or (C.stationCountry() == "FR" and "FranceAgriMer Cere'Obs") or (C.stationCountry() == "CA" and "Canadian") or (C.stationCountry() == "PL" and "COBORU trials") or (C.stationCountry() == "GB" and "AHDB crop reports") or (C.stationCountry() == "IE" and "Teagasc advice") or "NASS", p.state, p.month, p.day, m, d, days, rec.dd, tostring(stationId))
    return true
end

function C.stepDay(day, hiF, loF, rainIn, scale, cold, month, thunder)
    C.lastScale = scale
    if CFAPeanut ~= nil then CFAPeanut.onDay(day, loF, scale) end   -- v0.25.11 peanut freeze in the windrow
    if CFASilage ~= nil then
        local ok, err = true, CFASilage.onDay(day, scale, month)   -- v0.29 bunker feed-out face
        if not ok then log("silage day error: %s", tostring(err)) end
    end
    for id, rec in pairs(C.fields) do
        if not rec.done and day > rec.lastDay and day >= rec.planted then
            local crop = C.cropFor(rec.fruit, rec.plantedMonth)
            if crop ~= nil then
                local wl0, wx0, rain0 = rec.wlLoss or 0, rec.weatherLoss or 0, rec.rainIn or 0   -- v0.25.20: for the hurricane rule
                C.advanceClocks(rec, crop, hiF, loF, scale)

                local loss, label = C.freezeLoss(crop, rec, loF, cold)
                if loss ~= nil and loss > rec.loss then
                    rec.loss = loss
                    table.insert(rec.events, string.format("day %d low %.0f F: %.1f %% (%s)", day, loF, loss, label))
                    log("field %s %s: freeze %.0f F -> %.1f %% yield loss (%s)", tostring(id), rec.fruit, loF, loss, label)
                end
                if #crop.coldNights > 0 then
                    if loF ~= nil and not rec.ready then
                        for _, r in ipairs(crop.coldNights) do
                            if loF <= r.lowF and C.inStageWindow(crop, rec, r.from, r.untilStage) then
                                rec.cnRun = (rec.cnRun or 0) + scale
                                if rec.cnRun >= r.nights and r.loss > rec.loss then
                                    rec.loss = r.loss
                                    table.insert(rec.events, string.format("day %d: %.0f nights at or below %.0f F (%s-%s): %.1f %% (%s)", day, rec.cnRun, r.lowF,
                                        r.from, r.untilStage or "harvest", r.loss, r.source))
                                    log("field %s %s: cold nights -> %.1f %% yield loss (%s)", tostring(id), rec.fruit, r.loss, r.source)
                                end
                            else
                                rec.cnRun = 0
                            end
                        end
                    end
                end
                C.droughtStep(rec, crop, hiF, loF, rainIn, scale, month)
                local hw = crop.heatWave
                if hw ~= nil and not rec.ready and C.inStageWindow(crop, rec, hw.from, hw.untilStage) then
                    local nrm = C.normalsFor(CFAWeather ~= nil and CFAWeather.stationId or nil)
                    local m, dm = C.realDateOfDay(day)
                    local nHi = (nrm ~= nil and m ~= nil) and nrm.hi[math.min(365, doyOf(m, dm))] or nil
                    if nHi ~= nil and hiF >= nHi + hw.aboveF then
                        rec.hwRun = (rec.hwRun or 0) + scale
                        if rec.hwRun >= hw.days and hw.loss > (rec.heatLoss or 0) and not rec.hwHit then
                            rec.hwHit = true
                            rec.heatLoss = 100 - (100 - (rec.heatLoss or 0)) * (1 - hw.loss / 100)
                            table.insert(rec.events, string.format("day %d: high %.0f F vs normal %.0f F for %.0f days -> heat loss %.1f %% (%s)", day, hiF, nHi, rec.hwRun, rec.heatLoss, hw.source))
                            log("field %s %s: heat wave (%.0f F vs normal %.0f F) -> heat loss %.1f %%", tostring(id), rec.fruit, hiF, nHi, rec.heatLoss)
                        end
                    else
                        rec.hwRun = 0
                    end
                end
                local ph = crop.pollHeat
                if ph ~= nil and not rec.ready and hiF ~= nil and C.inStageWindow(crop, rec, ph.from, ph.untilStage) then
                    if hiF >= ph.atOrAboveF then
                        local before = math.max(0, (rec.phRun or 0) - ph.freeDays)
                        rec.phRun = (rec.phRun or 0) + scale
                        local add = (math.max(0, rec.phRun - ph.freeDays) - before) * ph.lossPerDay
                        if add > 0 then
                            rec.heatLoss = math.min(100, (rec.heatLoss or 0) + add)
                            table.insert(rec.events, string.format("day %d: high %.0f F, %.1f days in a row at or above %.0f F at pollination -> heat loss %.1f %% (%s)",
                                day, hiF, rec.phRun, ph.atOrAboveF, rec.heatLoss, ph.source))
                            log("field %s %s: pollination heat %.0f F, %.1f days in a row -> heat loss %.1f %%", tostring(id), rec.fruit, hiF, rec.phRun, rec.heatLoss)
                        end
                    else
                        rec.phRun = 0
                    end
                elseif ph ~= nil then
                    rec.phRun = 0
                end
                local hz = crop.hdw
                if hz ~= nil and not rec.ready and CFAWeather ~= nil and CFAWeather.hdwHours ~= nil and C.inStageWindow(crop, rec, hz.from, hz.untilStage) then
                    local hrs = CFAWeather.hdwHours(day, hz.tempC, hz.rhPct, hz.windMs)
                    if hrs > 0 then
                        rec.hdwHours = (rec.hdwHours or 0) + hrs * scale
                        rec.heatLoss = math.min(100, hz.lossPer10h * rec.hdwHours / 10)
                        table.insert(rec.events, string.format("day %d: %d hot-dry-windy hours (x%.1f days) -> heat loss %.1f %% (%s)", day, hrs, scale, rec.heatLoss, hz.source))
                        log("field %s %s: %d hot-dry-windy hours -> heat loss %.1f %%", tostring(id), rec.fruit, hrs, rec.heatLoss)
                    end
                end
                if crop.dormantBelowF ~= nil and loF ~= nil then
                    local nrm0 = C.normalsFor(CFAWeather ~= nil and CFAWeather.stationId or nil)
                    if rec.dormant == nil then
                        -- first day seen: Jan-Jun = dormant while the station's normal low is still at or below the line
                        local m1, d1 = C.realDateOfDay(day)
                        local lo1 = (nrm0 ~= nil and m1 ~= nil) and nrm0.lo[math.min(365, doyOf(m1, d1))] or nil
                        rec.dormant = (month ~= nil and month < 7 and lo1 ~= nil and lo1 <= crop.dormantBelowF) or false
                    end
                    if month ~= nil and month >= 7 and loF <= crop.dormantBelowF then
                        rec.dormant = true
                    elseif rec.dormant and month ~= nil and month < 7 then
                        local nrm = C.normalsFor(CFAWeather ~= nil and CFAWeather.stationId or nil)
                        local m2, d2 = C.realDateOfDay(day)
                        local nLo = (nrm ~= nil and m2 ~= nil) and nrm.lo[math.min(365, doyOf(m2, d2))] or nil
                        if nLo ~= nil and nLo > crop.dormantBelowF then rec.dormant = false end
                    end
                end
                local ws = crop.winterStand
                if ws ~= nil and rec.ready and month ~= nil then
                    local idx = ({[11] = 1, [12] = 2, [1] = 3, [2] = 4, [3] = 5, [4] = 6})[month]
                    if idx ~= nil then
                        local heavy = (C.winterSnowDays or 0) >= ws.heavyDays[idx]
                        local loss = heavy and ws.heavy[idx] or ws.light[idx]
                        -- v0.21.9 (team): a loss never goes back down - standing mature corn cannot regain yield
                        if loss > (rec.delayLoss or 0) then
                            rec.delayLoss = math.max(0, loss)
                            table.insert(rec.events, string.format("day %d: corn standing in month %d, %s winter (%.0f snow days): %.0f %% (%s)", day, month,
                                heavy and "heavy-snow" or "light-snow", C.winterSnowDays or 0, loss, ws.source))
                        end
                    end
                end
                local hd = crop.harvestDelay
                if hd ~= nil and C.inStageWindow(crop, rec, hd.from, nil) then
                    rec.delayDays = (rec.delayDays or 0) + scale
                    rec.delayLoss = math.min(100, hd.perDay * rec.delayDays)
                end
                local hl = C.hailRoll(crop, month, scale, thunder)
                if hl ~= nil then
                    rec.hailLoss = 100 - (100 - (rec.hailLoss or 0)) * (1 - hl / 100)
                    table.insert(rec.events, string.format("day %d hail: %.1f %% of yield (total hail %.1f %%)", day, hl, rec.hailLoss))
                    log("field %s %s: hail -> %.1f %% yield loss (%s)", tostring(id), rec.fruit, hl,
                        C.inEurope() and ("size USDA " .. tostring(crop.hail.state) .. ", how often " .. tostring(C.EU_HAIL_SRC[C.euCountry() or ""])) or ("lead state " .. tostring(crop.hail.state)))
                end
                local wd = C.windRoll(crop, month, scale)
                if wd ~= nil then
                    rec.windLoss = 100 - (100 - (rec.windLoss or 0)) * (1 - wd / 100)
                    table.insert(rec.events, string.format("day %d wind: %.1f %% of yield (total wind %.1f %%)", day, wd, rec.windLoss))
                    log("field %s %s: wind -> %.1f %% yield loss (lead state %s)", tostring(id), rec.fruit, wd, tostring(crop.wind.state))
                end
                local cl, ch = C.coldRoll(crop, month, scale, loF)
                if cl ~= nil then
                    rec.rmaColdLoss = 100 - (100 - (rec.rmaColdLoss or 0)) * (1 - cl / 100)
                    local how = C.inEurope() and tostring(ch.state) or ("USDA RMA " .. tostring(ch.state))
                    table.insert(rec.events, string.format("day %d %s (low %.0f F): %.1f %% of yield (total %.1f %%, %s)", day, ch.cause, loF, cl, rec.rmaColdLoss, how))
                    log("field %s %s: %s -> %.1f %% yield loss (%s)", tostring(id), rec.fruit, ch.cause, cl, how)
                end
                if rec.ready and crop.weatherPerInch ~= nil and rainIn > 0 then
                    rec.rainIn = rec.rainIn + rainIn * scale
                    rec.weatherLoss = math.min(100, rec.rainIn * crop.weatherPerInch)
                end
                local tl, tst = C.tornadoRoll(rec.fruit, month, scale)
                if tl ~= nil then
                    rec.tornadoLoss = 100 - (100 - (rec.tornadoLoss or 0)) * (1 - tl / 100)
                    table.insert(rec.events, string.format("day %d tornado: %.1f %% of yield (total tornado %.1f %%)", day, tl, rec.tornadoLoss))
                    log("field %s %s: tornado -> %.1f %% yield loss (USDA RMA, %s)", tostring(id), rec.fruit, tl, tostring(tst))
                end
                -- Hurricane (team rule): RMA hurricane losses already include the storm's flooding and rain, so on the storm day the
                -- field takes the larger of the hurricane loss and that day's own flood / rain-on-ready-crop loss, never both.
                local hu, hst = C.hurricaneRoll(rec.fruit, month, scale, (rainIn or 0) > 0)
                if hu ~= nil then
                    local before = 100 - (100 - wl0) * (100 - wx0) / 100
                    local after = 100 - (100 - (rec.wlLoss or 0)) * (100 - (rec.weatherLoss or 0)) / 100
                    local dayFlood = math.max(0, after - before)
                    if hu >= dayFlood then
                        rec.wlLoss, rec.weatherLoss, rec.rainIn = wl0, wx0, rain0
                        rec.hurricaneLoss = 100 - (100 - (rec.hurricaneLoss or 0)) * (1 - hu / 100)
                        table.insert(rec.events, string.format("day %d hurricane / tropical storm: %.1f %% of yield (total %.1f %%)%s", day, hu, rec.hurricaneLoss,
                            dayFlood > 0 and string.format(" - replaces this storm's %.1f %% flood/rain loss", dayFlood) or ""))
                        log("field %s %s: hurricane / tropical storm -> %.1f %% yield loss (USDA RMA, %s)%s", tostring(id), rec.fruit, hu, tostring(hst),
                            dayFlood > 0 and string.format(", replaces %.1f %% flood/rain that day", dayFlood) or "")
                    else
                        table.insert(rec.events, string.format("day %d hurricane / tropical storm: %.1f %% - this storm's flood/rain loss (%.1f %%) is larger and counts instead", day, hu, dayFlood))
                        log("field %s %s: hurricane / tropical storm %.1f %% < flood/rain %.1f %% that day - flood/rain counts", tostring(id), rec.fruit, hu, dayFlood)
                    end
                end
            end
            rec.lastDay = day
        end
    end
end

function C.dayWeather(day)
    if CFAWeather ~= nil and CFAWeather.active then
        local d = CFAWeather.days[day]
        if d ~= nil then
            return cToF(d.hiC), cToF(d.loC), (d.rainMM or 0) / 25.4, d.month, d.thunder == true, d.wet == true and d.snow == true
        end
    end
    return nil
end

-- v0.25.23: read which fields the player owns at the start of a new save (retried for up to 2 real minutes until the
-- game has handed out the starting land), then give the start-up cover to crop records already made on those fields.
function C.captureStartFields()
    local cap = C.startCapture
    if cap == nil or g_fieldManager == nil then return end
    local t = g_time or 0
    cap.t0 = cap.t0 or t
    local owned, n = {}, 0
    for _, field in pairs(g_fieldManager.fields) do
        local id = fieldId(field)
        if id ~= nil and C.isMine(id) then owned[tostring(id)] = true; n = n + 1 end
    end
    if n == 0 and t - cap.t0 < 120000 then return end
    C.startCapture = nil
    C.startOwned, C.startScans = owned, 0
    local given = 0
    for id, rec in pairs(C.fields) do
        if owned[tostring(id)] and not rec.done and rec.ins == nil then
            owned[tostring(id)] = nil
            rec.grace, rec.startCover = true, true
            given = given + 1
        end
    end
    log("start-up cover: %d field(s) owned at the start of this save; %d crop(s) already in them can be insured this first season (game rule)", n, given)
end

function C.update(dt)
    if not C.active then return end
    if C.startCapture ~= nil then C.captureStartFields() end
    local env = g_currentMission.environment
    local hour = env.currentHour
    local P = CarolinaFieldCure
    local now = P ~= nil and P.profNow or nil
    if hour ~= C.lastHour then
        C.lastHour = hour
        C.startScan()
    end
    if C.scanQueue ~= nil then
        -- v0.25.8: a slice of the hourly scan this frame; the day step waits until the whole scan is done (next frame at the soonest)
        local t0 = now ~= nil and now() or nil
        C.scanSlice()
        if t0 ~= nil then P.profAdd("crops hourly scan", now() - t0) end
        if C.scanQueue == nil and C.startOwned ~= nil and C.startCapture == nil then
            -- start fields with no crop found after two full scans had no start crop: nothing left to cover
            C.startScans = (C.startScans or 0) + 1
            if C.startScans >= 2 then C.startOwned = nil end
        end
        return
    end
    local today = env.currentMonotonicDay
    if not C.stationConfirmed then
        C.waitTick(today, hour)
        C.lastDay = today - 1   -- nothing is stepped while waiting; the confirm rebuilds every crop from its planting
        return
    end
    if C.lastDay == nil then C.lastDay = today - 1 end
    local d0 = (C.lastDay < today - 1 and now ~= nil) and now() or nil
    while C.lastDay < today - 1 do
        local day = C.lastDay + 1
        local hiF, loF, rainIn, month, thunder, snow = C.dayWeather(day)
        if hiF ~= nil then
            -- v0.21.8: the farm's snow days this winter (Nov 1 on), counted in real days like the clocks
            local dppS = math.max(1, env.daysPerPeriod or 1)
            if month >= 5 and month <= 10 then
                C.winterSnowDays = 0
            elseif snow then
                C.winterSnowDays = (C.winterSnowDays or 0) + C.MONTH_DAYS[month] / dppS
            end
            local dpp = math.max(1, env.daysPerPeriod or 1)
            local scale = C.MONTH_DAYS[month] / dpp
            local cold = nil
            if CFAWeather ~= nil and CFAWeather.hoursColdF ~= nil then
                cold = function(th, strict) return CFAWeather.hoursColdF(day, th, strict) end
            end
            C.stepDay(day, hiF, loF, rainIn, scale, cold, month, thunder)
            if CFAWinter ~= nil then CFAWinter.stepDay(day, scale) end   -- v0.23 snow, alfalfa and grass winter
        end
        C.lastDay = day
    end
    if d0 ~= nil then P.profAdd("crops day step", now() - d0) end
end

-- ------------------------------------------------------------------ weather station confirmation (v0.21.6)

function C.stationText()
    if CFAWeather ~= nil and CFAWeather.getStationText ~= nil then
        local ok, s = true, CFAWeather.getStationText()
        if ok and s ~= nil then return s end
    end
    return "?"
end

function C.waitMessage()
    local pre = (CFAWeather ~= nil and CFAWeather.preselected ~= nil) and (" (set: " .. C.stationText() .. ", " .. CFAWeather.preselected .. ")")
        or (" (set now: " .. C.stationText() .. ")")
    return "Field Almanac: pick your weather station - ESC > Settings > Field Almanac, or confirm it on the Field Almanac Settings tab" .. pre ..
        ". Crops are not tracked and insurance is locked until then."
end

-- v0.27.1 (team 2026-11-12): must-see station reminder - a window that stops the game on load, and a big red banner
-- that stays up until the station is confirmed (the game's blinking warning does not show on every PC).
-- v0.30.1: once the station is confirmed, drop any "pick your weather station" warning still waiting in the game's queue
C.STATION_WARN_PREFIX = "Field Almanac: pick your weather station"
function C.purgeStationWarnings()
    local CFC = CarolinaFieldCure
    if CFC ~= nil and CFC.purgeQueuedNotices ~= nil then CFC.purgeQueuedNotices(C.STATION_WARN_PREFIX) end
end
function C.daysLeft()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env == nil or C.waitStartDay == nil then return C.WAIT_DAYS end
    return math.max(0, C.WAIT_DAYS - (env.currentMonotonicDay - C.waitStartDay))
end
function C.updateBanner()
    local CFC = CarolinaFieldCure
    if CFC == nil or CFC.setBanner == nil then return end
    if C.stationConfirmed then CFC.clearBanner("station") return end
    CFC.setBanner("station", "PICK YOUR WEATHER STATION - crops and insurance on hold",
        string.format("ESC > Field Almanac > Settings   |   Set now: %s   |   Auto-pick in %d day(s)", C.stationText(), C.daysLeft()))
end
function C.remind(firstOnLoad)
    local CFC = CarolinaFieldCure
    if CFC ~= nil and CFC.showPopup ~= nil then
        CFC.showPopup("warning", C.waitMessage())
    end
    C.updateBanner()
    if firstOnLoad and CFC ~= nil and CFC.showDialog ~= nil then
        local pre = (CFAWeather ~= nil and CFAWeather.preselected ~= nil) and ("Set now: " .. C.stationText() .. " (" .. CFAWeather.preselected .. ").")
            or ("Set now: " .. C.stationText() .. ".")
        CFC.showDialog("Carolina Field Almanac - pick your weather station",
            "Your crops are not tracked and crop insurance is locked until you pick or confirm your weather station.\n\n" .. pre ..
            "\n\nPick station now opens ESC > Field Almanac > Settings. If nothing is picked in " .. C.WAIT_DAYS .. " game days, the station that is set is used.",
            "Pick station now", "Later", function() CFC.openSettingsTab() end)
    end
    log("%s", C.waitMessage())
end

function C.waitTick(today, hour)
    if C.waitStartDay == nil then C.waitStartDay = today end
    -- the player changed the station in the game's Settings: confirm once they are back in the game
    if CFAWeather ~= nil and CFAWeather.uiPicked and g_gui ~= nil and not g_gui:getIsGuiVisible() then
        CFAWeather.uiPicked = false
        C.confirmStation("picked in Settings")
        return
    end
    if C.bannerDay ~= today then C.bannerDay = today C.updateBanner() end   -- v0.27.1 days-left count on the banner
    if today - C.waitStartDay >= C.WAIT_DAYS then
        C.confirmStation(string.format("%d game days with no pick - using the station that is set", C.WAIT_DAYS))
        return
    end
    if not C.remindedLoad and g_currentMission.hud ~= nil then
        -- v0.25.21 (tester report 2026-11-11: the pop-up ran out on the start screen): wait until the player is in the world -
        -- no menu or start screen up and the HUD showing - for 3 seconds in a row, then show it.
        local inWorld = g_gui ~= nil and not g_gui:getIsGuiVisible() and g_currentMission.gameStarted ~= false
        if inWorld and CarolinaFieldCure ~= nil and CarolinaFieldCure.hudShown ~= nil then
            local ok, shown = true, CarolinaFieldCure.hudShown()
            if ok and shown == false then inWorld = false end
        end
        local t = g_time or 0
        if not inWorld then
            C.inWorldSince = nil
        elseif C.inWorldSince == nil then
            C.inWorldSince = t
        elseif t - C.inWorldSince >= 3000 then
            C.remindedLoad = true
            C.remindedDay = today   -- v0.21.10: loading at 6:00 gave two reminders
            C.remind(true)
        end
    elseif hour == 6 and C.remindedDay ~= today then
        C.remindedDay = today
        C.remind()
    end
end

-- v0.30 multiplayer: a player (not the host) gets the same station banner and reminders from what the host sends; a station
-- picked in the game's Settings is sent to the host to confirm (host or admin only - the host says so if not allowed).
function C.clientTick(dt)
    if not C.clientMode or g_currentMission == nil or g_currentMission.environment == nil then return end
    if CFAMP == nil or CFAMP.gotFull == nil or not CFAMP.gotFull.cr then return end   -- nothing from the host yet
    local P = CarolinaFieldCure
    local env = g_currentMission.environment
    local today, hour = env.currentMonotonicDay, env.currentHour
    if C.stationConfirmed or not C.hostActive then
        if C.clientWaiting and P ~= nil and P.clearBanner ~= nil then P.clearBanner("station") C.purgeStationWarnings() end
        C.clientWaiting = false
        return
    end
    C.clientWaiting = true
    if CFAWeather ~= nil and CFAWeather.uiPicked and g_gui ~= nil and not g_gui:getIsGuiVisible() then
        CFAWeather.uiPicked = false
        CFAMP.request("confirm", {why = "picked in Settings by a player"})
        return
    end
    if C.bannerDay ~= today then C.bannerDay = today C.updateBanner() end
    if not C.remindedLoad then
        local inWorld = g_gui ~= nil and not g_gui:getIsGuiVisible() and g_currentMission.gameStarted ~= false
        local t = g_time or 0
        if not inWorld then
            C.inWorldSince = nil
        elseif C.inWorldSince == nil then
            C.inWorldSince = t
        elseif t - C.inWorldSince >= 3000 then
            C.remindedLoad = true
            C.remindedDay = today
            C.remind(true)
        end
    elseif hour == 6 and C.remindedDay ~= today then
        C.remindedDay = today
        C.remind()
    end
end

-- Rebuild a crop planted in the game while waiting: its own planting day to today, with the confirmed station's daily normals.
function C.rebuildFromPlanting(id, rec)
    local crop = C.cropFor(rec.fruit, rec.plantedMonth)
    local n = C.normalsFor(CFAWeather ~= nil and CFAWeather.stationId or nil)
    local env = g_currentMission.environment
    local today = env.currentMonotonicDay
    if crop == nil or n == nil then rec.lastDay = today - 1 return end
    local dpp = math.max(1, env.daysPerPeriod or 1)
    rec.dd, rec.days, rec.after, rec.r5Days = 0, 0, {}, nil
    for day = rec.planted, today - 1 do
        local m, d = C.realDateOfDay(day)
        if m ~= nil then
            local doy = math.min(365, doyOf(m, d))
            C.advanceClocks(rec, crop, n.hi[doy], n.lo[doy], C.MONTH_DAYS[m] / dpp)
        end
    end
    rec.lastDay = today - 1
    log("field %s %s: planted while waiting - rebuilt from day %d to today with station %s normals: %.0f DD", tostring(id), rec.fruit, rec.planted,
        tostring(CFAWeather and CFAWeather.stationId), rec.dd)
end

function C.confirmStation(why)
    if C.stationConfirmed then return end
    C.stationConfirmed = true
    if CarolinaFieldCure ~= nil and CarolinaFieldCure.clearBanner ~= nil then CarolinaFieldCure.clearBanner("station") end
    C.purgeStationWarnings()
    if why ~= nil and why:find("no pick", 1, true) and CarolinaFieldCure ~= nil and CarolinaFieldCure.showDialog ~= nil then
        CarolinaFieldCure.showDialog("Carolina Field Almanac - station picked for you",
            string.format("No weather station was picked in %d game days, so %s is used. Crops are tracked and insurance is open now.\n\nYou can change it any time: ESC > Field Almanac > Settings.", C.WAIT_DAYS, C.stationText()),
            "Open Settings", "OK", function() CarolinaFieldCure.openSettingsTab() end)
    end
    local today = g_currentMission.environment.currentMonotonicDay
    -- v0.29.11 (team 2026-11-16): say how many crops were rebuilt from a planting date and how many start today
    local n, rebuilt, fresh = 0, 0, 0
    for id, rec in pairs(C.fields) do
        if not rec.done then
            if rec.needBackfill or (rec.backfill ~= nil and rec.backfill ~= "none") then
                local r = C.backfill(id, rec)
                if r ~= nil then rec.needBackfill = nil end
                n = n + 1
                if r == true then rebuilt = rebuilt + 1 elseif r == false then fresh = fresh + 1 end
            elseif rec.waitPlanted then
                C.rebuildFromPlanting(id, rec)
                n = n + 1
                rebuilt = rebuilt + 1
            end
            rec.waitPlanted = nil
        end
    end
    C.lastDay = today - 1
    local insOff = C.inEurope ~= nil and C.inEurope() and CFAMenuFrame ~= nil and CFAMenuFrame.PICK_EU ~= nil
        and CFAMenuFrame.PICK_EU[(C.euCountry ~= nil and C.euCountry()) or ""] == nil
    local msg = string.format("Weather station confirmed: %s (%s). %d crop(s) tracked: %d rebuilt from planting dates, %d start today. %s",
        C.stationText(), why or "confirmed", n, rebuilt, fresh,
        insOff and "Tracking is on; no crop insurance numbers for this country yet, so insurance is off (Rule #1)." or "Tracking and insurance are on.")
    if CarolinaFieldCure ~= nil and CarolinaFieldCure.addNotice ~= nil then CarolinaFieldCure.addNotice("ok", msg) end
    log("%s", msg)
end

-- ------------------------------------------------------------------ harvest

function C.factorAt(x, z, fruitTypeIndex, forage)
    local field = C.fieldAt(x, z)
    if field == nil then return 1 end
    local id = fieldId(field)
    local rec = C.fields[id]
    local desc = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
    if rec == nil or desc == nil or rec.fruit ~= desc.name:upper() then return 1 end
    local f = C.totalFactor(rec)
    -- v0.29: chopped with a forage harvester header -> corn silage yield by whole-plant moisture (CFASilage, Penn State)
    if forage and CFASilage ~= nil and CFASilage.cornChopFactor ~= nil then
        f = f * CFASilage.cornChopFactor(id, rec, C.cropFor(rec.fruit, rec.plantedMonth))
    end
    return f
end

function C.installHarvestHook()
    if FSDensityMapUtil == nil or FSDensityMapUtil.cutFruitArea == nil or C.hooked then return end
    local original = FSDensityMapUtil.cutFruitArea
    FSDensityMapUtil.cutFruitArea = function(fruitTypeIndex, xs, zs, xw, zw, xh, zh, ...)
        local factor = 1
        if C.active then
            local forage = select(2, ...) == true   -- Cutter: (destroySpray, allowsForageGrowthState, excludedSprayType)
            local ok, f = true, C.factorAt((xw + xh) * 0.5, (zw + zh) * 0.5, fruitTypeIndex, forage)
            if ok and f ~= nil then factor = math.max(0, math.min(1, f)) end
        end
        local r = {original(fruitTypeIndex, xs, zs, xw, zw, xh, zh, ...)}
        if factor < 1 and tonumber(r[1]) ~= nil then
            r[1] = r[1] * factor   -- yield-weighted area: what the harvester fills with
        end
        return unpack(r, 1, table.maxn(r))
    end
    C.hooked = true
end

-- ------------------------------------------------------------------ crop insurance (v0.21.1)
-- Numbers: CFAInsurance.lua = USDA RMA Summary of Business 2021-2025, lead state, per acre, per plan and coverage level.
-- How it works (the real way, team 2026-11-03):
--   * A policy is bought for a CROP (plan + coverage level), not a field. It covers every field of that crop planted while the
--     policy is in force, and it renews every season until it is cancelled (RMA Insurance Cycle: "Insurance coverage is continuous").
--   * Insurance attaches when the crop is planted (RMA Insurance Cycle). A field planted before the policy was bought is not covered
--     that season (sales closing date comes before planting - Center for Rural Affairs, Crop Insurance 101).
--   * The premium is charged when coverage begins (RMA: premium "earned and payable at the time insurance coverage begins"):
--     farmer-paid premium per acre x the field's acres, on the day CFA sees the field planted.
--   * First-season grace (game rule, not RMA): the first time insurance runs on a save, crops already in the ground can be covered
--     when the crop policy is bought, if no damage has been recorded on them yet.
-- Claim (per field, at harvest). V = liability per acre / coverage = expected yield x projected price per acre.
--   Projected price = the game's sell price for the crop on the day the field is covered; harvest price = the game's price at the claim
--   (average over the selling points that buy it). k = share of the yield kept (only damage types switched on).
--   YP / APH: payout = V x max(0, coverage - k)
--   RP:       guarantee = V x coverage x max(1, h); revenue = V x k x h; h = harvest / projected price, at most 2.00
--             (RMA Commodity Exchange Price Provisions, Section 2(f): "The harvest price will not be greater than the projected price multiplied by 2.00")
--   RP-HPE:   guarantee = V x coverage; revenue = V x k x h, h at most 1.00 (harvest price not to exceed the projected price - ProAg RP-HPE)
--   payout = max(0, guarantee - revenue) x acres.

C.ACRES_PER_HA = 2.4710538   -- NIST: 1 acre = 0.40468564224 ha
C.RP_PRICE_CAP = 2.00
C.policies = {}              -- v0.30 multiplayer: farm id -> fruit name -> {plan, cov, farmId} (was fruit -> policy)

-- v0.30 (team 2026-11-19: separate farms): each farm has its own policies
function C.policyFor(farmId, fruit)
    local t = farmId ~= nil and C.policies[farmId] or nil
    return t ~= nil and t[fruit] or nil
end
function C.myPolicy(fruit) return C.policyFor(C.playerFarmId(), fruit) end
C.insMarker = false          -- save already has v0.21.1 insurance data (grace is used up)
C.graceOpen = false
-- v0.25.23 (team 2026-11-11): first-season START-UP cover (game rule, not RMA). The fields the player owns when a new save
-- starts can be insured that first season even if the crop is already harvest-ready (FS25 starts most fields ready), as long
-- as no damage was recorded. Captured once at the start, so confirming the station later or buying land first gains nothing.
-- Fields bought later with a crop in them are NOT covered that season (team pick A: RMA Basic Provisions sec. 28 moves
-- coverage only from an insured seller, and NPC farms have no insurance; sec. 11(a): coverage begins at the later of the
-- application and planting). In multiplayer a player-to-player sale could transfer coverage (sec. 28) - not built (MP not supported yet).
C.startOwned = nil           -- field id -> true, fields owned at save start whose first crop record has not been made yet
C.startCapture = nil         -- {} while waiting to read the start fields
C.startScans = 0

function C.insuranceFor(fruit)
    if CFAInsurance == nil or fruit == nil then return nil end
    if C.inEurope() then return C.euInsurance(fruit) end   -- v0.28 Poland / Germany
    local d = CFAInsurance[fruit]
    if type(d) ~= "table" or d.plans == nil then return nil end
    return d
end

function C.planData(fruit, plan)
    local d = C.insuranceFor(fruit)
    if d == nil then return nil end
    for _, p in ipairs(d.plans) do
        if p.plan == plan then return p end
    end
    return nil
end

function C.rowFor(fruit, plan, cov)
    local p = C.planData(fruit, plan)
    if p == nil or cov == nil then return nil end
    for _, r in ipairs(p.rows) do
        if math.abs(r.cov - cov) < 0.001 then return r end
    end
    return nil
end

function C.planName(plan)
    return (CFAInsurance ~= nil and CFAInsurance.PLAN_NAMES ~= nil and CFAInsurance.PLAN_NAMES[plan]) or plan or "-"
end

function C.fieldById(id)
    if g_fieldManager == nil then return nil end
    if g_fieldManager.getFieldById ~= nil then
        local ok, f = true, g_fieldManager.getFieldById(g_fieldManager, tonumber(id) or id)
        if ok and f ~= nil then return f end
    end
    for _, field in pairs(g_fieldManager.fields or {}) do
        if fieldId(field) == id then return field end
    end
    return nil
end

function C.fieldAcres(id)
    local field = C.fieldById(id)
    if field == nil then return nil end
    local ha = nil
    if type(field.getAreaHa) == "function" then
        local ok, v = true, field.getAreaHa(field)
        if ok then ha = v end
    end
    ha = ha or field.areaHa
    if ha == nil then return nil end
    return ha * C.ACRES_PER_HA
end

function C.playerFarmId()
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        local ok, f = true, g_currentMission.getFarmId(g_currentMission)
        if ok and f ~= nil and f ~= 0 then return f end
    end
    return 1
end

function C.fieldOwner(id)
    local field = C.fieldById(id)
    if field == nil or field.farmland == nil or g_farmlandManager == nil then return nil end
    return g_farmlandManager:getFarmlandOwner(field.farmland.id)
end

-- v0.21.5: the player's own field (Fields tab "Own" / "NPC", Insurance tab)
function C.isMine(id)
    local owner = C.fieldOwner(id)
    return owner ~= nil and owner == C.playerFarmId()
end

function C.hasDamage(rec)
    for _, d in ipairs(C.DAMAGE) do
        if not d.mgmt and (rec[d.field] or 0) > 0 then return true end
    end
    return false
end

-- The game's sell price for the crop: average over the selling points that buy it (per liter).
function C.cropPrice(fruit)
    if g_fruitTypeManager == nil then return nil end
    local desc = g_fruitTypeManager:getFruitTypeByName(fruit)
    local ft = desc ~= nil and desc.fillType ~= nil and desc.fillType.index or nil
    if ft == nil then return nil end
    local sum, n = 0, 0
    local ss = g_currentMission ~= nil and g_currentMission.storageSystem or nil
    if ss ~= nil and ss.getUnloadingStations ~= nil then
        for _, st in pairs(ss:getUnloadingStations()) do
            if st.isSellingPoint and st.acceptedFillTypes ~= nil and st.acceptedFillTypes[ft] and st.getEffectiveFillTypePrice ~= nil then
                local ok, p = true, st.getEffectiveFillTypePrice(st, ft)
                if ok and p ~= nil and p > 0 then sum = sum + p; n = n + 1 end
            end
        end
    end
    if n > 0 then return sum / n end
    local em = g_currentMission ~= nil and g_currentMission.economyManager or nil
    if em ~= nil and em.getPricePerLiter ~= nil then
        local ok, p = true, em.getPricePerLiter(em, ft)
        if ok and p ~= nil and p > 0 then return p end
    end
    return nil
end

function C.addMoney(amount, farmId, kind)
    local m = g_currentMission
    if m == nil or m.addMoney == nil then return false end
    local mt = MoneyType ~= nil and MoneyType.OTHER or nil
    if MoneyType ~= nil then   -- v0.26.1: own Finances rows; falls back to Misc if they could not be added
        if kind == "premium" and MoneyType.CFA_INSURANCE_PREMIUM ~= nil then mt = MoneyType.CFA_INSURANCE_PREMIUM end
        if kind == "claim" and MoneyType.CFA_INSURANCE_CLAIM ~= nil then mt = MoneyType.CFA_INSURANCE_CLAIM end
    end
    local ok = true, m.addMoney(m, amount, farmId, mt, true, true)
    return ok
end

function C.notice(kind, msg, farmId)   -- v0.30: farmId = the farm it is about (nil = everyone)
    if CarolinaFieldCure ~= nil and CarolinaFieldCure.addNotice ~= nil then
        CarolinaFieldCure.addNotice(kind, msg, farmId)
    end
    log("%s", msg)
end

function C.money(v, decimals)
    decimals = decimals or 0
    if g_i18n ~= nil and g_i18n.formatMoney ~= nil then
        local ok, s = true, g_i18n.formatMoney(g_i18n, v, decimals, true, true)
        if ok and s ~= nil then return s end
    end
    return string.format("$%." .. decimals .. "f", v)
end

function C.cropTitle(fruit)
    local desc = g_fruitTypeManager ~= nil and g_fruitTypeManager:getFruitTypeByName(fruit) or nil
    if desc ~= nil and desc.fillType ~= nil and desc.fillType.title ~= nil then return desc.fillType.title end
    return fruit
end

-- Cover one field under its crop's policy and charge the premium. Returns true when covered.
function C.attach(id, rec, policy, why)
    if rec.ins ~= nil or policy == nil then return false end
    if C.weatherConflict() ~= nil then return false end   -- v0.26.3: no premiums while another weather mod is installed
    local owner = C.fieldOwner(id)
    if owner ~= nil and owner ~= policy.farmId then return false end
    local row = C.rowFor(rec.fruit, policy.plan, policy.cov)
    local acres = C.fieldAcres(id)
    if row == nil or acres == nil then return false end
    local premium = row.farmer * acres
    if not C.addMoney(-premium, policy.farmId, "premium") then return false end
    rec.ins = {plan = policy.plan, cov = row.cov, liab = row.liab, farmer = row.farmer, acres = acres, premium = premium,
               farmId = policy.farmId, projPrice = C.cropPrice(rec.fruit)}
    rec.grace = nil
    C.notice("info", string.format("Field %s: %s covered%s - %s %.0f %%, %.1f acres, premium %s", tostring(id), C.cropTitle(rec.fruit),
        why or "", C.planName(policy.plan), row.cov * 100, acres, C.money(premium)), policy.farmId)
    return true
end

-- Called when CFA sees a field newly planted.
-- v0.23: Forage Production insures a year of forage (all cuttings): one policy year per field. Each new growth of
-- alfalfa or grass is a new CFA record, so only the first growth of the game year is covered and charged.
function C.isForage(fruit) return fruit == "ALFALFA" or fruit == "GRASS" or fruit == "CLOVER" end   -- v0.27 clover (Forage Production)

function C.forageCoveredThisYear(id, rec)
    if not C.isForage(rec.fruit) or C.forageYear == nil then return false end
    local y = CFAWinter ~= nil and CFAWinter.yearOf() or 1
    return C.forageYear[tostring(id)] == y
end

function C.onPlanted(id, rec)
    if CFAWinter ~= nil then CFAWinter.onPlanted(id, rec) end   -- v0.23: this year's winter stand loss
    if C.graceOpen then rec.grace = true end
    if C.startOwned ~= nil and C.startOwned[tostring(id)] then   -- v0.25.23: the start crop of a field owned at save start
        C.startOwned[tostring(id)] = nil
        rec.grace, rec.startCover = true, true
    end
    if C.forageCoveredThisYear(id, rec) then
        rec.forageYearCovered = true   -- this year's policy is on an earlier cutting of the field
        return
    end
    local p = C.policyFor(C.fieldOwner(id), rec.fruit)   -- v0.30: the policy of the farm that owns the field
    if p ~= nil and not C.graceOpen then
        if C.attach(id, rec, p, " at planting") and C.isForage(rec.fruit) then
            C.forageYear = C.forageYear or {}
            C.forageYear[tostring(id)] = CFAWinter ~= nil and CFAWinter.yearOf() or 1
        end
    end
end

-- v0.26.3 (team 2026-11-12): CFA insurance pays only on damage CFA records from its own weather. With another weather mod
-- driving the weather CFA records none, so no premiums are taken (a policy that cannot pay out is not real insurance).
function C.weatherConflict()
    if CFAWeather ~= nil and CFAWeather.findConflict ~= nil then return CFAWeather.findConflict() end
    return nil
end

function C.cannotBuy(fruit, plan, cov)
    local wc = C.weatherConflict()
    if wc ~= nil then return "off - " .. wc .. " is installed and is not compatible with Carolina Field Almanac" end
    if not C.stationConfirmed then return "pick your weather station first (ESC > Settings) - insurance is priced by location" end
    if C.inEurope() and C.insuranceFor(fruit) == nil then
        local cc = C.euCountry()
        if cc == "DE" then return "not covered by German hail insurance" end
        if cc == "PL" then return "not covered by Poland's subsidized crop insurance" end
        return "off here - no crop insurance numbers for this country yet (Rule #1)"
    end
    if C.insuranceFor(fruit) == nil then return "no RMA policy data for this crop" end
    if C.rowFor(fruit, plan, cov) == nil then return "no RMA row for this plan and coverage" end
    return nil
end

-- Buy a crop policy, or change an existing one (the change applies to fields planted after it).
function C.buyPolicy(fruit, plan, cov, farmId)
    local why = C.cannotBuy(fruit, plan, cov)
    if why ~= nil then return false, why end
    farmId = farmId or C.playerFarmId()   -- v0.30: the farm that buys it
    local old = C.policyFor(farmId, fruit)
    local p = {plan = plan, cov = cov, farmId = farmId}
    C.policies[farmId] = C.policies[farmId] or {}
    C.policies[farmId][fruit] = p
    if old ~= nil then
        C.notice("info", string.format("%s policy changed to %s %.0f %% - applies to fields planted from now on", C.cropTitle(fruit), C.planName(plan), cov * 100), farmId)
        return true
    end
    C.notice("info", string.format("%s policy bought: %s %.0f %% - every %s field you plant is covered, renews each season until cancelled",
        C.cropTitle(fruit), C.planName(plan), cov * 100, C.cropTitle(fruit)), farmId)
    local late = 0
    for id, rec in pairs(C.fields) do
        if rec.fruit == fruit and not rec.done and rec.ins == nil and C.fieldOwner(id) == farmId then
            if rec.grace and (rec.startCover or not rec.ready) and not C.hasDamage(rec) then
                C.attach(id, rec, p, rec.startCover and " (first-season start-up cover - game rule)" or " (first season)")
            else
                late = late + 1
            end
        end
    end
    if late > 0 then
        C.notice("info", string.format("%s: %d field(s) planted before the policy (or bought with the crop in) are not covered this season - covered from their next planting", C.cropTitle(fruit), late), farmId)
    end
    return true
end

function C.cancelPolicy(fruit, farmId)
    farmId = farmId or C.playerFarmId()
    if C.policyFor(farmId, fruit) == nil then return false, "no policy" end
    C.policies[farmId][fruit] = nil
    C.notice("info", string.format("%s policy cancelled - fields already covered stay covered until harvest", C.cropTitle(fruit)), farmId)
    return true
end

-- Payout for a record right now (0 if nothing is owed).
function C.claimAmount(rec, harvestPrice)
    local p = rec.ins
    if p == nil or p.cov == nil or p.cov <= 0 then return 0 end
    local V = p.liab / p.cov
    local cap = CFAInsurance ~= nil and CFAInsurance.DE_CAP ~= nil and CFAInsurance.DE_CAP[p.plan] or nil
    if cap ~= nil then   -- v0.28 German hail policy: hail damage only, nothing under 5 %, then the full loss up to the cap
        local hl = (rec.hailLoss or 0) / 100
        if hl < 0.05 then return 0, 1 end
        return V * math.min(hl, cap) * p.acres, 1
    end
    local k = C.totalFactor(rec, true)
    local h = 1
    if p.plan == "RP" or p.plan == "RPHPE" then
        local hp = harvestPrice or C.cropPrice(rec.fruit)
        if hp ~= nil and p.projPrice ~= nil and p.projPrice > 0 then h = hp / p.projPrice end
        h = math.min(h, p.plan == "RP" and C.RP_PRICE_CAP or 1)
        local guarantee = V * p.cov * (p.plan == "RP" and math.max(1, h) or 1)
        return math.max(0, guarantee - V * k * h) * p.acres, h
    end
    return V * math.max(0, p.cov - k) * p.acres, 1
end

function C.cannotClaim(rec)
    if rec == nil or rec.ins == nil then return "not insured" end
    if rec.ins.paid ~= nil then return "claim already settled" end
    if not (rec.ready or rec.done) then return "claims are filed at harvest" end
    return nil
end

function C.fileClaim(id, auto)
    local rec = C.fields[id]
    local why = C.cannotClaim(rec)
    if why ~= nil and not (auto and rec ~= nil and rec.ins ~= nil and rec.ins.paid == nil) then return false, why end
    local p = rec.ins
    local amount, h = C.claimAmount(rec)
    local kept = C.totalFactor(rec, true)
    local priceText = (p.plan == "RP" or p.plan == "RPHPE") and string.format(", harvest price %.0f %% of projected", (h or 1) * 100) or ""
    if amount > 0 then
        if not C.addMoney(amount, p.farmId or C.playerFarmId(), "claim") then return false, "could not pay the claim" end
        C.notice("ok", string.format("Field %s: insurance claim paid %s (yield kept %.1f %%, %s %.0f %%%s)", tostring(id), C.money(amount),
            kept * 100, C.planName(p.plan), p.cov * 100, priceText), p.farmId)
    else
        C.notice("info", string.format("Field %s: insurance claim - nothing owed (yield kept %.1f %%, %s %.0f %%%s)", tostring(id),
            kept * 100, C.planName(p.plan), p.cov * 100, priceText), p.farmId)
    end
    p.paid = amount
    return true
end

-- A record ends (harvested, cleared, replanted): coverage with no claim yet is settled on its own.
function C.autoClaim(id, rec)
    if rec ~= nil and rec.ins ~= nil and rec.ins.paid == nil then
        C.fileClaim(id, true)
    end
end

-- Damage switches are locked while any covered field is not settled yet (team: no cheating the system).
function C.settingsLocked()
    for _, rec in pairs(C.fields) do
        if rec.ins ~= nil and rec.ins.paid == nil then return true end
    end
    return false
end

-- ------------------------------------------------------------------ save / load

function C.save(path)
    local xml = XMLFile.create("cfaCropsSave", path, "carolinaFieldAlmanacCrops")
    if xml == nil then return end
    xml:setString("carolinaFieldAlmanacCrops#rangePick", C.settings.rangePick)
    local off = {}
    for _, d in ipairs(C.DAMAGE) do if C.settings.off[d.key] then off[#off + 1] = d.key end end
    xml:setString("carolinaFieldAlmanacCrops#off", table.concat(off, " "))
    xml:setBool("carolinaFieldAlmanacCrops#insurance", true)
    xml:setBool("carolinaFieldAlmanacCrops#stationConfirmed", C.stationConfirmed == true)
    xml:setString("carolinaFieldAlmanacCrops#winterSnowDays", string.format("%.2f", C.winterSnowDays or 0))
    if C.waitStartDay ~= nil then xml:setInt("carolinaFieldAlmanacCrops#waitStartDay", C.waitStartDay) end
    if C.startOwned ~= nil then   -- v0.25.23: start fields whose start crop has not been seen yet
        local ids = {}
        for fid in pairs(C.startOwned) do ids[#ids + 1] = fid end
        xml:setString("carolinaFieldAlmanacCrops#startOwned", table.concat(ids, " "))
    end
    local fi = 0
    for fid, y in pairs(C.forageYear or {}) do
        local fk = string.format("carolinaFieldAlmanacCrops.forageYear(%d)", fi)
        xml:setString(fk .. "#field", tostring(fid))
        xml:setInt(fk .. "#year", y)
        fi = fi + 1
    end
    local pi = 0
    for farmId, list in pairs(C.policies) do   -- v0.30: per farm (same XML rows as before; farmId was already saved)
        for fruit, p in pairs(list) do
            local pk = string.format("carolinaFieldAlmanacCrops.policy(%d)", pi)
            xml:setString(pk .. "#fruit", fruit)
            xml:setString(pk .. "#plan", p.plan)
            xml:setString(pk .. "#cov", string.format("%.2f", p.cov))
            xml:setInt(pk .. "#farmId", p.farmId or farmId or 1)
            pi = pi + 1
        end
    end
    xml:setString("carolinaFieldAlmanacCrops#version", "0.14")
    xml:setInt("carolinaFieldAlmanacCrops#lastDay", C.lastDay or 0)
    local i = 0
    for id, rec in pairs(C.fields) do
        do
            local k = string.format("carolinaFieldAlmanacCrops.field(%d)", i)
            xml:setString(k .. "#id", tostring(id))
            xml:setString(k .. "#fruit", rec.fruit)
            xml:setInt(k .. "#planted", rec.planted)
            if rec.plantedMonth ~= nil then xml:setInt(k .. "#plantedMonth", rec.plantedMonth) end
            xml:setInt(k .. "#lastDay", rec.lastDay)
            xml:setString(k .. "#dd", string.format("%.1f", rec.dd))
            xml:setString(k .. "#days", string.format("%.2f", rec.days or 0))
            if rec.r5Days ~= nil then xml:setString(k .. "#r5Days", string.format("%.2f", rec.r5Days)) end
            xml:setString(k .. "#loss", string.format("%.2f", rec.loss))
            xml:setString(k .. "#rainIn", string.format("%.3f", rec.rainIn))
            xml:setString(k .. "#hailLoss", string.format("%.2f", rec.hailLoss or 0))
            xml:setString(k .. "#dr", string.format("%.2f", rec.dr or 0))
            xml:setString(k .. "#eta", string.format("%.3f", rec.eta or 0))
            xml:setString(k .. "#etm", string.format("%.3f", rec.etm or 0))
            xml:setString(k .. "#droughtLoss", string.format("%.2f", rec.droughtLoss or 0))
            xml:setString(k .. "#wx", string.format("%.2f", rec.wx or 0))
            xml:setString(k .. "#wlRun", string.format("%.2f", rec.wlRun or 0))
            xml:setString(k .. "#wlLoss", string.format("%.2f", rec.wlLoss or 0))
            xml:setString(k .. "#windLoss", string.format("%.2f", rec.windLoss or 0))
            xml:setString(k .. "#tornadoLoss", string.format("%.2f", rec.tornadoLoss or 0))       -- v0.25.20
            xml:setString(k .. "#rmaColdLoss", string.format("%.2f", rec.rmaColdLoss or 0))       -- v0.27
            xml:setString(k .. "#hurricaneLoss", string.format("%.2f", rec.hurricaneLoss or 0))
            xml:setString(k .. "#delayDays", string.format("%.2f", rec.delayDays or 0))
            xml:setString(k .. "#delayLoss", string.format("%.2f", rec.delayLoss or 0))
            xml:setString(k .. "#winterLoss", string.format("%.2f", rec.winterLoss or 0))   -- v0.23
            xml:setString(k .. "#cutLoss", string.format("%.2f", rec.cutLoss or 0))   -- v0.25
            xml:setString(k .. "#fallCutLoss", string.format("%.2f", rec.fallCutLoss or 0))
            if rec.cutNo ~= nil then xml:setInt(k .. "#cutNo", rec.cutNo) end
            xml:setString(k .. "#frostLoss", string.format("%.2f", rec.frostLoss or 0))
            if rec.forageYearCovered then xml:setBool(k .. "#forageYearCovered", true) end   -- v0.23
            xml:setString(k .. "#hdwHours", string.format("%.1f", rec.hdwHours or 0))
            if (rec.phRun or 0) > 0 then xml:setString(k .. "#phRun", string.format("%.2f", rec.phRun)) end   -- v0.25.8
            xml:setString(k .. "#heatLoss", string.format("%.2f", rec.heatLoss or 0))
            if rec.hwHit then xml:setBool(k .. "#hwHit", true) end
            xml:setString(k .. "#dsRun", string.format("%.2f", rec.dsRun or 0))
            xml:setString(k .. "#dsLoss", string.format("%.2f", rec.dsLoss or 0))
            xml:setBool(k .. "#done", rec.done == true)
            if rec.backfill ~= nil then xml:setString(k .. "#backfill", rec.backfill) end
            if rec.needBackfill then xml:setBool(k .. "#needBackfill", true) end
            if rec.retry293 then xml:setBool(k .. "#retry293", true) end
            xml:setBool(k .. "#ready", rec.ready == true)
            if rec.grace then xml:setBool(k .. "#grace", true) end
            if rec.startCover then xml:setBool(k .. "#startCover", true) end   -- v0.25.23
            if rec.waitPlanted then xml:setBool(k .. "#waitPlanted", true) end
            if rec.dormant then xml:setBool(k .. "#dormant", true) end
            if rec.ins ~= nil then
                local p = rec.ins
                xml:setString(k .. ".insurance#plan", p.plan or "YP")
                if p.projPrice ~= nil then xml:setString(k .. ".insurance#projPrice", string.format("%.6f", p.projPrice)) end
                xml:setString(k .. ".insurance#cov", string.format("%.2f", p.cov))
                xml:setString(k .. ".insurance#liab", string.format("%.2f", p.liab))
                xml:setString(k .. ".insurance#farmer", string.format("%.2f", p.farmer))
                xml:setString(k .. ".insurance#acres", string.format("%.3f", p.acres))
                xml:setString(k .. ".insurance#premium", string.format("%.2f", p.premium))
                xml:setInt(k .. ".insurance#farmId", p.farmId or 1)
                if p.paid ~= nil then xml:setString(k .. ".insurance#paid", string.format("%.2f", p.paid)) end
            end
            local j = 0
            for name, hu in pairs(rec.after) do
                xml:setString(string.format("%s.after(%d)#stage", k, j), name)
                xml:setString(string.format("%s.after(%d)#hu", k, j), string.format("%.1f", hu))
                j = j + 1
            end
            i = i + 1
        end
    end
    if CFAWinter ~= nil then CFAWinter.save(xml, "carolinaFieldAlmanacCrops") end   -- v0.23
    if CFAPeanut ~= nil then CFAPeanut.save(xml, "carolinaFieldAlmanacCrops") end   -- v0.25.11
    if CFASilage ~= nil then CFASilage.save(xml, "carolinaFieldAlmanacCrops") end   -- v0.29
    xml:save()
    xml:delete()
end

function C.load()
    local info = g_currentMission.missionInfo
    if info == nil or info.savegameDirectory == nil then return end
    local xml = XMLFile.loadIfExists("cfaCropsSave", info.savegameDirectory .. "/" .. C.SAVE_FILE)
    if xml == nil then return end
    C.settings.rangePick = xml:getString("carolinaFieldAlmanacCrops#rangePick", C.settings.rangePick)
    C.insMarker = xml:getBool("carolinaFieldAlmanacCrops#insurance", false)
    C.stationConfirmed = xml:getBool("carolinaFieldAlmanacCrops#stationConfirmed", false)
    C.winterSnowDays = tonumber(xml:getString("carolinaFieldAlmanacCrops#winterSnowDays", "0")) or 0
    C.waitStartDay = xml:getInt("carolinaFieldAlmanacCrops#waitStartDay")
    local so = xml:getString("carolinaFieldAlmanacCrops#startOwned")
    if so ~= nil then
        C.startOwned = {}
        for fid in so:gmatch("%S+") do C.startOwned[fid] = true end
    end
    C.forageYear = {}
    xml:iterate("carolinaFieldAlmanacCrops.forageYear", function(_, fk)
        local f, y = xml:getString(fk .. "#field"), xml:getInt(fk .. "#year")
        if f ~= nil and y ~= nil then C.forageYear[f] = y end
    end)
    C.policies = {}
    xml:iterate("carolinaFieldAlmanacCrops.policy", function(_, pk)
        local fruit = xml:getString(pk .. "#fruit")
        local cov = tonumber(xml:getString(pk .. "#cov", ""))
        if fruit ~= nil and cov ~= nil then
            local farmId = xml:getInt(pk .. "#farmId", 1)
            C.policies[farmId] = C.policies[farmId] or {}
            C.policies[farmId][fruit] = {plan = xml:getString(pk .. "#plan", "YP"), cov = cov, farmId = farmId}
        end
    end)
    C.settings.off = {}
    for key in string.gmatch(xml:getString("carolinaFieldAlmanacCrops#off", ""), "%S+") do C.settings.off[key] = true end
    local preV14 = xml:getString("carolinaFieldAlmanacCrops#version") == nil
    local ld = xml:getInt("carolinaFieldAlmanacCrops#lastDay")
    if ld ~= nil and ld > 0 then C.lastDay = ld end
    local n = 0
    xml:iterate("carolinaFieldAlmanacCrops.field", function(_, k)
        local id = xml:getString(k .. "#id")
        local rec = {fruit = xml:getString(k .. "#fruit"), planted = xml:getInt(k .. "#planted", 0),
                     lastDay = xml:getInt(k .. "#lastDay", 0), dd = tonumber(xml:getString(k .. "#dd", "0")) or 0,
                     days = tonumber(xml:getString(k .. "#days", "")),
                     loss = tonumber(xml:getString(k .. "#loss", "0")) or 0,
                     rainIn = tonumber(xml:getString(k .. "#rainIn", "0")) or 0,
                     hailLoss = tonumber(xml:getString(k .. "#hailLoss", "0")) or 0,
                     dr = tonumber(xml:getString(k .. "#dr", "0")) or 0, eta = tonumber(xml:getString(k .. "#eta", "0")) or 0,
                     etm = tonumber(xml:getString(k .. "#etm", "0")) or 0, droughtLoss = tonumber(xml:getString(k .. "#droughtLoss", "0")) or 0,
                     wx = tonumber(xml:getString(k .. "#wx", "0")) or 0, wlRun = tonumber(xml:getString(k .. "#wlRun", "0")) or 0,
                     wlLoss = tonumber(xml:getString(k .. "#wlLoss", "0")) or 0,
                     windLoss = tonumber(xml:getString(k .. "#windLoss", "0")) or 0,
                     tornadoLoss = tonumber(xml:getString(k .. "#tornadoLoss", "0")) or 0, rmaColdLoss = tonumber(xml:getString(k .. "#rmaColdLoss", "0")) or 0, hurricaneLoss = tonumber(xml:getString(k .. "#hurricaneLoss", "0")) or 0,
                     delayDays = tonumber(xml:getString(k .. "#delayDays", "0")) or 0, delayLoss = tonumber(xml:getString(k .. "#delayLoss", "0")) or 0,
                     winterLoss = tonumber(xml:getString(k .. "#winterLoss", "0")) or 0,
                     cutLoss = tonumber(xml:getString(k .. "#cutLoss", "0")) or 0, fallCutLoss = tonumber(xml:getString(k .. "#fallCutLoss", "0")) or 0,
                     cutNo = xml:getInt(k .. "#cutNo"), frostLoss = tonumber(xml:getString(k .. "#frostLoss", "0")) or 0, forageYearCovered = xml:getBool(k .. "#forageYearCovered", false) or nil,
                     hdwHours = tonumber(xml:getString(k .. "#hdwHours", "0")) or 0, heatLoss = tonumber(xml:getString(k .. "#heatLoss", "0")) or 0,
                     dsRun = tonumber(xml:getString(k .. "#dsRun", "0")) or 0, dsLoss = tonumber(xml:getString(k .. "#dsLoss", "0")) or 0,
                     after = {}, events = {}, ready = xml:getBool(k .. "#ready", false), done = xml:getBool(k .. "#done", false)}
        rec.backfill = xml:getString(k .. "#backfill")
        if xml:getBool(k .. "#hwHit", false) then rec.hwHit = true end
        rec.phRun = tonumber(xml:getString(k .. "#phRun", "0")) or 0
        if xml:getBool(k .. "#grace", false) then rec.grace = true end
        if xml:getBool(k .. "#startCover", false) then rec.startCover = true end
        if xml:getBool(k .. "#waitPlanted", false) then rec.waitPlanted = true end
        if xml:getBool(k .. "#dormant", false) then rec.dormant = true end
        local cov = tonumber(xml:getString(k .. ".insurance#cov", ""))
        if cov ~= nil then
            rec.ins = {plan = xml:getString(k .. ".insurance#plan", "YP"), projPrice = tonumber(xml:getString(k .. ".insurance#projPrice", "")),
                       cov = cov, liab = tonumber(xml:getString(k .. ".insurance#liab", "0")) or 0,
                       farmer = tonumber(xml:getString(k .. ".insurance#farmer", "0")) or 0,
                       acres = tonumber(xml:getString(k .. ".insurance#acres", "0")) or 0,
                       premium = tonumber(xml:getString(k .. ".insurance#premium", "0")) or 0,
                       farmId = xml:getInt(k .. ".insurance#farmId", 1),
                       paid = tonumber(xml:getString(k .. ".insurance#paid", ""))}
        end
        if xml:getBool(k .. "#needBackfill", false) then rec.needBackfill = true end
        -- v0.29.3: Canada / Europe now have daily normals and some planting dates - a crop that could not be rebuilt before gets one retry
        rec.retry293 = xml:getBool(k .. "#retry293", false)
        if rec.backfill == "none" and not rec.retry293 then
            rec.backfill, rec.needBackfill, rec.retry293 = nil, true, true
        end
        rec.plantedMonth = xml:getInt(k .. "#plantedMonth")
        if rec.plantedMonth == nil then rec.plantedMonth = C.monthOf(rec.planted) end   -- saves before v0.11.8
        if rec.days == nil then
            -- saves before v0.12: rebuild real days since planting from the days already stepped
            local dpp = math.max(1, (g_currentMission.environment and g_currentMission.environment.daysPerPeriod) or 1)
            local days = 0
            for d = rec.planted, math.min(rec.lastDay, rec.planted + 3650) do
                local m = C.monthOf(d)
                if m ~= nil then days = days + C.MONTH_DAYS[m] / dpp end
            end
            rec.days = days
        end
        rec.r5Days = tonumber(xml:getString(k .. "#r5Days", ""))   -- v0.29
        xml:iterate(k .. ".after", function(_, ak)
            rec.after[xml:getString(ak .. "#stage")] = tonumber(xml:getString(ak .. "#hu", "0")) or 0
        end)
        local crop = C.cropFor(rec.fruit, rec.plantedMonth)
        -- v0.11.7 repair: a stage clock with the same method and base as the planting clock can never be more than
        -- (planting clock - stage dd). Saves from v0.11.6 could overshoot on the step the stage was reached.
        if crop ~= nil then
            local g = crop.growth
            for name, hu in pairs(rec.after) do
                local ck, si = crop.clocks[name], crop.stageIndex[name]
                local st = si ~= nil and crop.stages[si] or nil
                if ck ~= nil and st ~= nil and st.dd ~= nil and st.from == nil and ck.method == g.method and ck.baseF == g.baseF then
                    local maxHu = math.max(0, rec.dd - st.dd)
                    if hu > maxHu then
                        log("field %s %s: %s clock %.0f -> %.0f (v0.11.7 repair)", tostring(id), rec.fruit, name, hu, maxHu)
                        rec.after[name] = maxHu
                    end
                end
            end
        end
        rec.weatherLoss = (crop ~= nil and crop.weatherPerInch ~= nil) and math.min(100, rec.rainIn * crop.weatherPerInch) or 0
        C.fields[tonumber(id) or id] = rec
        n = n + 1
    end)
    if CFAWinter ~= nil then CFAWinter.load(xml, "carolinaFieldAlmanacCrops") end   -- v0.23
    if CFAPeanut ~= nil then CFAPeanut.load(xml, "carolinaFieldAlmanacCrops") end   -- v0.25.11
    if CFASilage ~= nil then CFASilage.load(xml, "carolinaFieldAlmanacCrops") end   -- v0.29
    xml:delete()
    -- v0.14: saves made before the backfill existed. Records CFA created on its very first day saw crops that were already
    -- in the ground; the next field scan rebuilds them if they are past sowing.
    if preV14 then
        local first = nil
        for _, rec in pairs(C.fields) do if not rec.done and (first == nil or rec.planted < first) then first = rec.planted end end
        local k = 0
        for _, rec in pairs(C.fields) do
            if not rec.done and rec.planted == first and rec.backfill == nil then rec.needBackfill = true; k = k + 1 end
        end
        if k > 0 then log("save from before v0.14: %d records from CFA's first day will be backfilled", k) end
    end
    log("loaded %d field records", n)
end

-- ------------------------------------------------------------------ start / console

function C.start(mission)
    if mission:getIsServer() == false then
        -- v0.30 multiplayer: a player's game only shows what the host sends (crop table loaded for the menus)
        if C.loadData() then C.clientMode = true end
        return
    end
    if not C.loadData() then return end
    C.load()
    C.installHarvestHook()
    C.active = true
    if not C.insMarker then
        -- first time insurance runs on this save: crops already in the ground get the one-time grace (game rule)
        for _, rec in pairs(C.fields) do
            if not rec.done and rec.ins == nil then rec.grace = true end
        end
        C.graceOpen = true
        C.startCapture = {}   -- v0.25.23: new save - read the start fields once the game has handed them out
    end
    C.scanFields()
    C.graceOpen = false
    -- v0.21.4: write the game's own yield-bonus settings to the log (rolling: FS25 manual says 2.5 %; team asked to confirm from the game)
    do (function()
        local parts = {}
        for k, v in pairs(mission) do
            if type(k) == "string" and type(v) == "number" and k:lower():find("harvest") and k:find("Ratio") then
                parts[#parts + 1] = string.format("%s=%s", k, tostring(v))
            end
        end
        table.sort(parts)
        log("game yield settings: %s", #parts > 0 and table.concat(parts, ", ") or "none found on the mission")
    end)() end
    C.insMarker = true
    if CFAPeanut ~= nil then CFAPeanut.installPickupHook() end   -- v0.25.11
    if CFASilage ~= nil then CFASilage.installHooks() end   -- v0.29
    log("on - %d crops in the table, harvest hook %s", (function() local n = 0 for _ in pairs(C.crops) do n = n + 1 end return n end)(),
        C.hooked and "installed" or "NOT installed")
end

function C.statusText(id, rec)
    local crop = C.cropFor(rec.fruit, rec.plantedMonth)
    local stage = "-"
    if crop ~= nil then
        local si = C.currentStage(crop, rec)
        if si > 0 then stage = crop.stages[si].name end
    end
    local after = {}
    for name, hu in pairs(rec.after) do table.insert(after, string.format("%s+%.0f", name, hu)) end
    local fall = crop ~= nil and rec.plantedMonth ~= nil and crop.freezeOffMonths[rec.plantedMonth] and ", freeze off (no sourced clock for this planting month)" or ""
    local bf = (rec.backfill ~= nil and rec.backfill ~= "none") and (", backfilled: NASS planting " .. rec.backfill) or ""
    return string.format("field %s %s: planted day %d (month %s)%s, %.0f DD, stage %s %s, freeze loss %.1f %%, rain loss %.1f %%, hail loss %.1f %%, wind loss %.1f %%, heat loss %.1f %%, drought loss %.1f %% (soil water short %.0f mm), waterlog loss %.1f %% (water above field capacity %.0f mm)%s%s%s",
        tostring(id), rec.fruit, rec.planted, tostring(rec.plantedMonth or "?"), bf, rec.dd, stage, table.concat(after, " "), rec.loss, rec.weatherLoss, rec.hailLoss or 0, rec.windLoss or 0, rec.heatLoss or 0, rec.droughtLoss or 0, rec.dr or 0, rec.wlLoss or 0, rec.wx or 0,
        fall, rec.ready and ", harvest-ready" or "", rec.done and " (done)" or "")
end

function C.consoleCrops()
    if not C.active then return "Carolina Field Almanac crops: off" end
    local ids = {}
    for id in pairs(C.fields) do table.insert(ids, id) end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    for _, id in ipairs(ids) do
        local rec = C.fields[id]
        print(C.statusText(id, rec))
        for _, e in ipairs(rec.events) do print("    " .. e) end
    end
    return string.format("%d fields tracked, range pick: %s", #ids, C.settings.rangePick)
end
