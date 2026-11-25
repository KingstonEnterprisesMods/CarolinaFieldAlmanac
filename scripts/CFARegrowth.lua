-- Carolina Field Almanac: regrowth time after a cut (v0.25.1, team 2026-11-06)
-- Author: Kingston Enterprises
--
-- The game regrows grass and alfalfa one growth stage per period (month): cut -> greenSmall -> greenMiddle -> harvestReady,
-- so full regrowth takes 3 months. Real numbers (high end, Rule #1):
--   Alfalfa: UC IPM (UC ANR) Alfalfa Harvest - "alternating 'short' (26 day) with 'long' (35 day) intervals". High end 35 days
--            = 1.15 months -> 1 period: cut -> harvestReady in one month.
--   Grass (FS25 grass = timothy in CFA): Penn State Extension, "Timing Second Cutting Grass Hay" (Frankenfield & Brackenrich 2025)
--            - "cutting schedules can range from 30 to 60 days". High end 60 days = 1.97 months -> 2 periods:
--            cut -> greenMiddle -> harvestReady.
-- Only the growing-season periods are changed (the ones whose own steps carry the regrowth start all the way to the
-- harvest-ready state); late autumn and winter keep the map's own steps. Done through the game's own loader
-- (FruitTypeDesc:loadGrowth) on the fruit's own foliage XML, with only the cut -> regrowth-start steps re-pointed.

CFARegrowth = {}
local R = CFARegrowth

R.PERIODS = {ALFALFA = 1, GRASS = 2}   -- periods from cut to harvest ready (sources above)
R.applied = {}

local function log(fmt, ...) Logging.info("[CarolinaFieldAlmanac] regrowth: " .. fmt, ...) end
local function low(s) return s ~= nil and string.lower(s) or nil end

-- Re-point the cut steps in one fruit's foliage XML. Returns the number of steps changed.
function R.editXml(xmlFile, desc, nPeriods)
    local names = desc.growthStateToName or {}
    local original = {}   -- lower-case name -> the name as the map writes it
    for _, nm in pairs(names) do original[low(nm)] = nm end
    local regrow = low(names[desc.firstRegrowthState or -1])
    local maxH = low(names[desc.maxHarvestingGrowthState or -1])
    if regrow == nil or maxH == nil then return 0, "no regrowth start or harvest state" end
    local cutNames = {}
    for k in pairs(desc.cutStates or {}) do if names[k] ~= nil then cutNames[low(names[k])] = true end end
    if desc.cutState ~= nil and names[desc.cutState] ~= nil then cutNames[low(names[desc.cutState])] = true end
    if desc.rolledCutState ~= nil and names[desc.rolledCutState] ~= nil then cutNames[low(names[desc.rolledCutState])] = true end

    local changed, report = 0, {}
    xmlFile:iterate("foliageType.growth.seasonal.period", function(_, pKey)
        local steps = {}
        xmlFile:iterate(pKey .. ".update", function(_, uKey)
            local s, e = low(xmlFile:getString(uKey .. "#startState")), low(xmlFile:getString(uKey .. "#endState"))
            if s ~= nil and e ~= nil then steps[s] = e end
        end)
        -- the period's own chain from the regrowth start
        local chain, seen, cur = {regrow}, {[regrow] = true}, regrow
        while steps[cur] ~= nil and not seen[steps[cur]] do
            cur = steps[cur]
            seen[cur] = true
            chain[#chain + 1] = cur
        end
        if chain[#chain] == maxH and #chain > nPeriods then
            local target = chain[#chain - nPeriods + 1]
            local pName = xmlFile:getString(pKey .. "#name") or "?"
            xmlFile:iterate(pKey .. ".update", function(_, uKey)
                local s, e = low(xmlFile:getString(uKey .. "#startState")), low(xmlFile:getString(uKey .. "#endState"))
                if s ~= nil and cutNames[s] and e == regrow then
                    xmlFile:setString(uKey .. "#endState", original[target] or target)
                    changed = changed + 1
                end
            end)
            report[#report + 1] = pName .. ": cut -> " .. target
        end
    end)
    return changed, table.concat(report, ", ")
end

function R.applyOne(name, nPeriods)
    if g_fruitTypeManager == nil then return end
    local desc = g_fruitTypeManager:getFruitTypeByName(name)
    if desc == nil then return end
    if desc.xmlFilename == nil or desc.loadGrowth == nil or XMLFile == nil then
        log("%s left as the map has it (no foliage XML or loader)", name)
        return
    end
    local xmlFile = XMLFile.load("cfaRegrowth", desc.xmlFilename)
    if xmlFile == nil then
        log("%s left as the map has it (could not read %s)", name, tostring(desc.xmlFilename))
        return
    end
    local n, report = R.editXml(xmlFile, desc, nPeriods)
    if n > 0 then
        local ok, err = true, desc.loadGrowth(desc, xmlFile, "foliageType.growth")
        if ok then
            R.applied[name] = nPeriods
            log("%s regrows in %d month(s) after a cut (%d steps; %s)", name, nPeriods, n, report)
        else
            Logging.error("[CarolinaFieldAlmanac] regrowth: %s loadGrowth failed: %s", name, tostring(err))
        end
    else
        log("%s left as the map has it (%s)", name, report ~= "" and report or "no growing-season cut steps found")
    end
    xmlFile:delete()
end

function R.apply()
    for name, n in pairs(R.PERIODS) do
        local ok, err = true, R.applyOne(name, n)
        if not ok then Logging.error("[CarolinaFieldAlmanac] regrowth %s: %s", name, tostring(err)) end
    end
end
