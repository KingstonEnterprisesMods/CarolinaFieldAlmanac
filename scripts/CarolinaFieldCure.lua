-- Carolina Field Cure - by Kingston Enterprises. Mod for Farming Simulator.
--
-- v0.22 (team, Rule #1): hay curing rebuilt on the published USDA-ARS model, replacing all of our old unsourced numbers.
--   Drying (daylight):  Rotz & Chen 1985, Transactions of the ASAE 28(5):1686-1691, equation [2]  M = Mo e^(-DR T)  (dry basis)
--                       and equation [4]  DR = SI / (61.4 SM + SD (1.82 - 0.83 DAY) 1.68 + 2767) + 43.8 VPD / (same)   (AR = 0, no chemical)
--                       SI solar W/m2, VPD kPa, SM soil moisture % dry basis, SD swath density g DM/m2, DAY = 1 on the day of mowing or raking.
--                       The paper recommends [4] (vapor pressure deficit) for areas with lower humidity; CFA has hourly humidity everywhere.
--                       The USDA IFSM Reference Manual v3.6 prints Eq. 6.3 with an exponent 0.868 - the original paper has none (copy error).
--   No conditioning:    IFSM Reference Manual v3.6 p.57 (Rotz et al. 1987): drying rate -44 % first cutting, -27 % second, 0 % third and later.
--   Fresh-cut moisture: IFSM p.57: 5.0 dry basis spring / fall, 4.5 summer (2nd and 3rd cuttings), minus 0.03 per hour after sunrise.
--   Night dew:          IFSM p.58 Eq. 6.4 / 6.5 (Rotz 1985): Mf = Me + (Mi - Me) e^(-4 T / SD); Me = (0.4 + 3.6 / e^(0.2 WIND)) / e^(2.5 (1 - RH)).
--   Rain:               IFSM p.59 Eq. 6.8: M = 4.0 + (Mo - 4.0) e^(-150 rn / SD)  (the manual prints the rate as +150; it must act as absorption
--                       toward 4.0, like the dew rate -4.0 - written with the minus sign here).
--   Respiration loss:   Rotz 1995, Trans. ASAE 38(6):1621, Eq. 2: R = 0.00017 T m^2.6 (fraction of DM per hour; T 0-40 C, m wet basis 0.2-0.9).
--                       (v0.23.2: the IFSM manual's Eq. 6.9 prints it without the ^2.6 - the original paper has the exponent.)
--   Hay at 20 % (wet basis): NC State Extension; Rotz & Chen fitted 80 % to 20 %.
--   Inputs: sun = FAO-56 Eq. 50 (Hargreaves, kRs 0.16 interior) from the day's high/low and the station latitude, spread over daylight
--   (FAO-56 day length); temperature, humidity, wind, rain = CFA's NOAA weather hour by hour; swath density = the game's windrow amount
--   in each 4 m square; soil moisture = 17 % dry basis (Rotz & Chen 1985 Table 2 "typical").

CarolinaFieldCure = {}
local CFC = CarolinaFieldCure

CFC.MOD_NAME = g_currentModName
CFC.MOD_DIR = g_currentModDirectory
CFC.VERSION = "1.0.6"
CFC.SAVE_FILE = "carolinaFieldCure.xml"

CFC.CELL_SIZE = 4.0          -- metres
CFC.HAY_MOISTURE = 0.20      -- hay at or below this (wet basis) - NC State; end of Rotz & Chen's fitted range
CFC.SOIL_MOISTURE_DB = 17    -- % dry basis, Rotz & Chen 1985 Table 2 "typical"
CFC.SD_MIN, CFC.SD_MAX, CFC.SD_TYPICAL = 150, 1500, 450   -- g/m2, Rotz & Chen 1985 Table 2 min / max / typical (range the model was tested on)
CFC.KRS = 0.16               -- FAO-56 Eq. 50, interior locations
CFC.DEW_RATE = -4.0          -- g/m2-h, IFSM Eq. 6.4
CFC.RAIN_RATE = -150         -- g/m2-mm, IFSM Eq. 6.8 (absorption)
CFC.RAIN_EQ_DB = 4.0         -- IFSM Eq. 6.8
CFC.TED_LOSS_K = 0.044       -- IFSM v3.6 p.61 Eq. 6.13: tedding loss = 0.044 (1 + 6 fl) (1 - m)^1.5, grass fl = 0
CFC.ALFALFA_LEAF = 0.6368     -- leaves share at cutting, high end (3rd cut 63.68/36.32): Stavarache et al., Lucrari Stiintifice vol. 56 (Iasi), 2010 trial
CFC.TED_FACTOR = 1.30        -- IFSM v3.6 p.58: tedding increases the drying rate by 30 % for the rest of that day
CFC.RESP_K = 0.00017         -- Rotz 1995 Eq. 2 (IFSM Eq. 6.9)
CFC.RESP_EXP = 2.6           -- Rotz 1995 Eq. 2 exponent on m
-- v0.23.2 rain damage while curing - Rotz, C.A. 1995. Loss models for forage harvest. Trans. ASAE 38(6):1621-1631 (team copy):
--   Eq. 5 leaf shatter (legumes): Ll = 0.011 fl (2 - m) sqrt(rn / Ds)   fl 0-0.7, rn 0-50 mm per rain, Ds 0.2-2.0 kg DM/m2
--   Eq. 7 leaching:               Lr = 0.0061 Fc (1 - NDF)(0.9 - m) rn / Ds   Fc 1.0 conditioned / 0.8 not, NDF 0.3-0.7
--   (The IFSM manual's Eq. 6.10/6.11 drop the square root and the / Ds - the paper has them.)
--   Grass: fl = 0, so no leaf shatter (paper). Inputs held to the paper's tested ranges.
-- NDF, high end of the published range (Rule #1): Feedipedia alfalfa hay 31.3-59.4 % DM (n 1038); timothy hay 61.8-71.5 % DM (n 20),
-- held to the model's 0.7 maximum.
CFC.LEACH_K = 0.0061
CFC.LEAF_K = 0.011
CFC.NDF_ALFALFA = 0.594
CFC.NDF_GRASS = 0.70
CFC.RAIN_EVT_MAX = 50
CFC.FC_CONDITIONED, CFC.FC_NONE = 1.0, 0.8
-- v0.23.2 machine losses - Rotz 1995 (same paper):
--   Eq. 8 mowing & conditioning: Lm = 0.006 fm (1 + 2 fl) Sd   fm 1.0 roll/light flail conditioner, 0.5 no conditioner;
--        Sd stage factor 1 (vegetative / boot) to 3 (late-full bloom / anthesis) - the game cannot tell bloom stage, so the
--        v0.25.1: Sd = 2 (team pick 2026-11-06, middle of the paper's 1-3 scale, because the other hay losses are all high end).
--        Gives alfalfa 2.7 %, grass 1.2 % with a conditioner; the paper reports 1-5 %.
--   Eq. 13 side-delivery rake: Lrk = 0.02 (1 + 2 fl)(1 - m)^1.5 / Ds   (the paper's only rake model; used for every rake)
CFC.MOW_K, CFC.MOW_SD = 0.006, 2
CFC.FM_CONDITIONED, CFC.FM_NONE = 1.0, 0.5
CFC.RAKE_K = 0.02
CFC.NO_CONDITIONING = {0.56, 0.73}   -- IFSM p.57: -44 % first cutting, -27 % second
CFC.REMOVE_STEP = 10         -- liters removed at a time for respiration loss (game step, no effect on the total)

CFC.MODE_SWATH = 1
CFC.MODE_SPREAD = 2
CFC.MODE_WINDROW = 3

CFC.UPDATE_INTERVAL = 1000   -- ms real time
CFC.EMPTY_CHECK_PER_UPDATE = 150
-- v0.23.0.2 (team: stutter every few seconds, gone once the hay was baled): every curing cell used to be stepped in ONE frame
-- each second, with 4 ground reads per cell (8,444 cells = ~34,000 reads in one frame). Now each frame steps a slice of the
-- cells (every cell still once per STEP_CYCLE_MS), using the cell's stored liters; the liters are re-read a few cells per frame
-- (every cell once per LEVEL_CYCLE_MS) and right away when our own code changes them. Same drying model, same numbers.
CFC.STEP_CYCLE_MS = 1000
CFC.LEVEL_CYCLE_MS = 10000
-- v0.25.3 (team 2026-11-06, test laptop showed 6-7 ms worst frames with 2,088 cells): a hard limit per frame. Cells left over wait
-- for the next frame; stepOne replays the missed time in the same 15-minute steps with each step's own weather, so a late
-- cell dries exactly the same - only a little later on screen. Big frames (a hitch from anything) no longer make us do more.
CFC.MAX_STEP_PER_FRAME = 64       -- 64 x 40 FPS = 2,560 cells a second
CFC.MAX_REFRESH_PER_FRAME = 8     -- ground re-reads (two density reads each)
CFC.SLICE_BUDGET_MS = 2           -- stop for this frame once 2 ms of the engine clock (1 ms ticks) have passed
-- v0.25.5: the field summaries (map icons, Field Cure box, notices, the hourly log line) are built over several frames too,
-- 128 cells a frame, a new pass at most once a second (was: two full passes over every cell in one frame, every second).
CFC.SUM_PER_FRAME = 128
-- v0.25.5 Light mode (Settings): a quarter of the per-frame work. Same drying numbers (the replay catches up exactly);
-- the boxes and pop-ups just update a few seconds later on big farms.
CFC.LIGHT_DIV = 4
function CFC.frameCaps()
    if CFC.settings.light then
        return math.max(1, math.floor(CFC.MAX_STEP_PER_FRAME / CFC.LIGHT_DIV)), math.max(1, math.floor(CFC.MAX_REFRESH_PER_FRAME / CFC.LIGHT_DIV)),
            math.max(1, math.floor(CFC.SUM_PER_FRAME / CFC.LIGHT_DIV))
    end
    return CFC.MAX_STEP_PER_FRAME, CFC.MAX_REFRESH_PER_FRAME, CFC.SUM_PER_FRAME
end
CFC.HUD_REFRESH = 300
CFC.VEH_PANEL_BOTTOM = 0.245   -- v1.0.2: screen height share; just above the mini map (default size, 1080p screenshot 2026-11-22)

CFC.settings = {curingDays = 3, popupSec = 10, noticeMode = "popup", conditioned = true, light = false}   -- v0.22 conditioned: Settings "Mower conditions hay"   -- v0.21.5 noticeMode: popup / summary / menu (team)   -- v0.21: pop-up seconds (Settings tab: 5/10/15/20)

CFC.cells = {}
CFC.cellList = {}
CFC.cellListDirty = true
CFC.emptyCursor = 1
CFC.timer = 0
CFC.started = false
CFC.pairs = {}
CFC.srcSet = {}
CFC.dstSet = {}
CFC.dstToSrc = {}
CFC.lastWeather = nil
CFC.stats = {created = 0, removed = 0, toHay = 0, toGrass = 0, mowerDrops = 0, soakLoss = 0, tedLoss = 0}

local function log(fmt, ...)
    Logging.info("[CarolinaFieldCure] " .. fmt, ...)
end

local function text(key, fallback)
    if g_i18n ~= nil and g_i18n:hasText(key) then
        return g_i18n:getText(key)
    end
    return fallback
end

-- ---------------------------------------------------------------- helpers

-- Other mods run in their own script environments; reach them through their mod name.
function CFC.getModEnv(modName)
    if _G ~= nil and type(_G[modName]) == "table" then
        return _G[modName]
    end
    return nil
end

function CFC.getWaterSoilAPI()
    if CFC.waterSoilAPI ~= nil then
        return CFC.waterSoilAPI
    end
    local api = nil
    if g_modIsLoaded ~= nil then
        for modName, loaded in pairs(g_modIsLoaded) do
            if loaded then
                local env = CFC.getModEnv(modName)
                if env ~= nil and type(env.WaterSoilAPI) == "table" then
                    api = env.WaterSoilAPI
                    break
                end
            end
        end
    end
    if api == nil and type(WaterSoilAPI) == "table" then
        api = WaterSoilAPI
    end
    CFC.waterSoilAPI = api
    return api
end

function CFC.isServer()
    return g_currentMission ~= nil and g_currentMission:getIsServer()
end

function CFC.isContractAt(x, z)
    if g_farmlandManager == nil or g_missionManager == nil then
        return false
    end
    local farmland = g_farmlandManager:getFarmlandAtWorldPosition(x, z)
    if farmland == nil then
        return false
    end
    return g_missionManager:getIsMissionRunningOnFarmland(farmland) == true
end

function CFC.buildFillTypePairs()
    CFC.pairs = {}
    CFC.srcSet = {}
    CFC.dstSet = {}
    CFC.dstToSrc = {}
    local converter = g_fillTypeManager:getConverterDataByName("TEDDER")
    if converter ~= nil then
        for src, data in pairs(converter) do
            local dst = data.targetFillTypeIndex
            if dst ~= nil and dst ~= src then
                table.insert(CFC.pairs, {src = src, dst = dst})
                CFC.srcSet[src] = true
                CFC.dstSet[dst] = true
                if CFC.dstToSrc[dst] == nil then
                    CFC.dstToSrc[dst] = src
                end
            end
        end
    end
    if #CFC.pairs == 0 and FillType.GRASS_WINDROW ~= nil and FillType.DRYGRASS_WINDROW ~= nil then
        table.insert(CFC.pairs, {src = FillType.GRASS_WINDROW, dst = FillType.DRYGRASS_WINDROW})
        CFC.srcSet[FillType.GRASS_WINDROW] = true
        CFC.dstSet[FillType.DRYGRASS_WINDROW] = true
        CFC.dstToSrc[FillType.DRYGRASS_WINDROW] = FillType.GRASS_WINDROW
    end
    local names = {}
    for _, p in ipairs(CFC.pairs) do
        table.insert(names, g_fillTypeManager:getFillTypeNameByIndex(p.src) .. ">" .. g_fillTypeManager:getFillTypeNameByIndex(p.dst))
    end
    log("curing fill types: %s", table.concat(names, ", "))
    -- v0.22: the game's mass per liter for the swath (fresh grass) and hay fill types, for the swath density in the drying model
    local p1 = CFC.pairs[1]
    if p1 ~= nil then
        local fs, fd = g_fillTypeManager:getFillTypeByIndex(p1.src), g_fillTypeManager:getFillTypeByIndex(p1.dst)
        CFC.mplSrc = fs ~= nil and fs.massPerLiter or nil
        CFC.mplDst = fd ~= nil and fd.massPerLiter or nil
        log("swath mass per liter (t/l): grass %s, hay %s", tostring(CFC.mplSrc), tostring(CFC.mplDst))
    end
end

-- ---------------------------------------------------------------- cells

function CFC.getCellKey(gx, gz)
    return gx .. ":" .. gz
end

function CFC.getCellArea(gx, gz)
    local s = CFC.CELL_SIZE
    local x0, z0 = gx * s, gz * s
    return x0, z0, x0 + s, z0, x0, z0 + s
end

function CFC.getLevels(gx, gz)
    local x0, z0, x1, z1, x2, z2 = CFC.getCellArea(gx, gz)
    local grass, hay = 0, 0
    for _, p in ipairs(CFC.pairs) do
        grass = grass + (DensityMapHeightUtil.getFillLevelAtArea(p.src, x0, z0, x1, z1, x2, z2) or 0)
        hay = hay + (DensityMapHeightUtil.getFillLevelAtArea(p.dst, x0, z0, x1, z1, x2, z2) or 0)
    end
    return grass, hay
end

-- v0.23.0.2: a cell's liters, stored on the cell; read from the ground only when missing or marked stale.
function CFC.storeLevels(cell, grass, hay)
    cell.lvGrass, cell.lvHay, cell.lvStale = grass, hay, nil
end

function CFC.cellLevels(cell)
    if cell.lvGrass == nil or cell.lvStale then
        CFC.storeLevels(cell, CFC.getLevels(cell.gx, cell.gz))
    end
    return cell.lvGrass, cell.lvHay
end

-- Grid cells whose centre lies inside the parallelogram start/width/height (plus a half-cell margin).
function CFC.getCellsForArea(sx, sz, wx, wz, hx, hz)
    local s = CFC.CELL_SIZE
    local ux, uz = wx - sx, wz - sz
    local vx, vz = hx - sx, hz - sz
    local det = ux * vz - uz * vx
    local result = {}
    local cx = sx + (ux + vx) * 0.5
    local cz = sz + (uz + vz) * 0.5
    local centreKey = nil
    local cgx, cgz = math.floor(cx / s), math.floor(cz / s)

    if math.abs(det) > 0.0001 then
        local lu = math.sqrt(ux * ux + uz * uz)
        local lv = math.sqrt(vx * vx + vz * vz)
        local mu = lu > 0 and (s * 0.5) / lu or 0
        local mv = lv > 0 and (s * 0.5) / lv or 0
        local minX = math.min(sx, wx, hx, wx + vx) - s
        local maxX = math.max(sx, wx, hx, wx + vx) + s
        local minZ = math.min(sz, wz, hz, wz + vz) - s
        local maxZ = math.max(sz, wz, hz, wz + vz) + s
        for gx = math.floor(minX / s), math.floor(maxX / s) do
            for gz = math.floor(minZ / s), math.floor(maxZ / s) do
                local px = (gx + 0.5) * s - sx
                local pz = (gz + 0.5) * s - sz
                local a = (px * vz - pz * vx) / det
                local b = (ux * pz - uz * px) / det
                if a >= -mu and a <= 1 + mu and b >= -mv and b <= 1 + mv then
                    table.insert(result, {gx = gx, gz = gz})
                    if gx == cgx and gz == cgz then
                        centreKey = true
                    end
                end
            end
        end
    end
    if centreKey == nil then
        table.insert(result, {gx = cgx, gz = cgz})
    end
    return result
end

function CFC.getNodeArea(area)
    if area == nil or area.start == nil or area.width == nil or area.height == nil then
        return nil
    end
    local sx, _, sz = getWorldTranslation(area.start)
    local wx, _, wz = getWorldTranslation(area.width)
    local hx, _, hz = getWorldTranslation(area.height)
    return sx, sz, wx, wz, hx, hz
end

function CFC.markCellListDirty()
    CFC.cellListDirty = true
end

-- v0.22: which cutting of the year this is on the farmland (for the no-conditioning slowdown, IFSM p.57).
-- A new cutting starts when the farmland had no cut grass or hay left from the last one.
CFC.cuts = {}
CFC.fidCount = {}   -- tracked cells per farmland
function CFC.cuttingNumber(cell)
    local fid = CFC.getCellFarmland(cell) or 0
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    local year = env ~= nil and (env.currentYear or 1) or 1
    local c = CFC.cuts[fid]
    if c == nil or c.year ~= year then
        c = {year = year, n = 0}
        CFC.cuts[fid] = c
    end
    if (CFC.fidCount[fid] or 0) == 0 then c.n = c.n + 1 end   -- no cells left from the last cutting on this farmland
    return math.max(1, c.n)
end

function CFC.createCell(gx, gz, moisture, mode)
    local key = CFC.getCellKey(gx, gz)
    local grass, hay = CFC.getLevels(gx, gz)
    local cell = {
        gx = gx, gz = gz,
        m = math.min(0.84, math.max(0, moisture)),
        mCut = (mode == nil or mode == CFC.MODE_SWATH) and math.min(0.84, math.max(0, moisture)) or nil,   -- v0.25.4
        mode = mode or CFC.MODE_SWATH,
        isHay = hay > grass
    }
    CFC.storeLevels(cell, grass, hay)
    cell.lastH = CFC.nowHours()
    if mode == CFC.MODE_SWATH then
        local env = g_currentMission ~= nil and g_currentMission.environment or nil
        cell.cutDay = env ~= nil and env.currentMonotonicDay or nil
        cell.cutNo = CFC.cuttingNumber(cell)
    end
    CFC.cells[key] = cell
    local fid = CFC.getCellFarmland(cell) or 0
    CFC.fidCount[fid] = (CFC.fidCount[fid] or 0) + 1
    CFC.stats.created = CFC.stats.created + 1
    CFC.markCellListDirty()
    return cell
end

-- Add material with a given moisture into the cells of an area, blending with what is already there.
function CFC.addToArea(sx, sz, wx, wz, hx, hz, moisture, liters, mode)
    local cells = CFC.getCellsForArea(sx, sz, wx, wz, hx, hz)
    local share = (liters or 0) / math.max(1, #cells)
    for _, c in ipairs(cells) do
        local key = CFC.getCellKey(c.gx, c.gz)
        local cell = CFC.cells[key]
        if cell == nil then
            local grass, hay = CFC.getLevels(c.gx, c.gz)
            if grass + hay > 0 then
                CFC.createCell(c.gx, c.gz, moisture, mode)
            end
        else
            local grass, hay = CFC.getLevels(c.gx, c.gz)
            CFC.storeLevels(cell, grass, hay)
            local total = grass + hay
            local old = math.max(0, total - share)
            if total > 0 and share > 0 then
                cell.m = (cell.m * old + moisture * share) / (old + share)
                if mode == CFC.MODE_SWATH then   -- v0.25.4 fresh-cut grass added: blend the cutting moisture too
                    local mc = cell.mCut or CFC.freshMoisture(nil)
                    cell.mCut = (mc * old + moisture * share) / (old + share)
                end
            end
            if mode ~= nil then
                cell.mode = mode
            end
        end
    end
end

function CFC.getAverageMoisture(sx, sz, wx, wz, hx, hz)
    local cells = CFC.getCellsForArea(sx, sz, wx, wz, hx, hz)
    local sum, weight = 0, 0
    for _, c in ipairs(cells) do
        local cell = CFC.cells[CFC.getCellKey(c.gx, c.gz)]
        if cell ~= nil then
            local grass, hay = CFC.getLevels(c.gx, c.gz)
            cell.lvStale = true   -- v0.23.0.2: material is being picked up here - re-read on the next step
            local w = math.max(1, grass + hay)
            sum = sum + cell.m * w
            weight = weight + w
        end
    end
    if weight == 0 then
        return nil
    end
    return sum / weight
end

function CFC.convertCell(cell, toHay)
    local x0, z0, x1, z1, x2, z2 = CFC.getCellArea(cell.gx, cell.gz)
    for _, p in ipairs(CFC.pairs) do
        if toHay then
            DensityMapHeightUtil.changeFillTypeAtArea(x0, z0, x1, z1, x2, z2, p.src, p.dst)
        else
            DensityMapHeightUtil.changeFillTypeAtArea(x0, z0, x1, z1, x2, z2, p.dst, p.src)
        end
    end
    cell.isHay = toHay
    if cell.lvGrass ~= nil then   -- v0.23.0.2: the whole cell changed fill type - move the stored liters with it
        local t = cell.lvGrass + cell.lvHay
        if toHay then cell.lvGrass, cell.lvHay = 0, t else cell.lvGrass, cell.lvHay = t, 0 end
    end
    -- v0.22: dew can lift hay above 20 % overnight (tough hay - wait for it to dry off); only rain counts as "rained on"
    cell.rewet = (not toHay) and cell.wetByRain == true
    if toHay then cell.wetByRain = nil; cell.rained = false; cell.wasHay = true end
    if toHay then
        CFC.stats.toHay = CFC.stats.toHay + 1
    else
        CFC.stats.toGrass = CFC.stats.toGrass + 1
    end
end

-- ---------------------------------------------------------------- weather

-- ---- v0.22 Rotz & Chen / USDA IFSM model helpers -------------------------------------------------------------

local function dbOf(m) return m / math.max(1e-6, 1 - m) end         -- wet basis -> dry basis
local function wbOf(M) return M / (1 + M) end                        -- dry basis -> wet basis
local function esKpa(tC) return 0.6108 * math.exp(17.27 * tC / (tC + 237.3)) end   -- FAO-56 Eq. 11

function CFC.monotonicHours(env)
    return (env.currentMonotonicDay or 0) * 24 + (env.dayTime or 0) / 3600000
end

-- Solar position for the station: FAO-56 day length N (Eq. 34) and daily Ra (Eq. 21) from CFACrops.raMm.
function CFC.sunFor(day)
    local st = CFAWeather ~= nil and CFAWeather.getStation ~= nil and CFAWeather.getStation() or nil
    if st == nil or st.lat == nil or CFACrops == nil or CFACrops.realDateOfDay == nil then return nil end
    local m, d = CFACrops.realDateOfDay(day)
    if m == nil then return nil end
    local CUM = {0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334}
    local doy = CUM[m] + d
    local phi = st.lat * math.pi / 180
    local delta = 0.409 * math.sin(2 * math.pi * doy / 365 - 1.39)
    local ws = math.acos(math.max(-1, math.min(1, -math.tan(phi) * math.tan(delta))))
    local N = 24 / math.pi * ws
    local raMJ = CFACrops.raMm(st.lat, doy) / 0.408
    return {N = N, sunrise = 12 - N / 2, sunset = 12 + N / 2, raMJ = raMJ, month = m}
end

-- One hour's inputs from CFA's NOAA weather. nil = no CFA weather (then nothing dries - no sourced inputs).
function CFC.hourInputs(day, hour)
    if CFAWeather == nil or not CFAWeather.active or CFAWeather.conditionsAt == nil then return nil end
    local d = CFAWeather.getDay ~= nil and CFAWeather.getDay(day) or (CFAWeather.days and CFAWeather.days[day])
    local c = CFAWeather.conditionsAt(day, hour)
    local sun = CFC.sunFor(day)
    if d == nil or c == nil or sun == nil then return nil end
    local tC = c.tempC or (d.hiC + d.loC) / 2
    -- Humidity straight from the day's NOAA dew point and the hour's temperature (CFAWeather.dayRH);
    -- skips the unsourced +8 / 97 rain-day bumps used for the HUD.
    local rhSrc = CFAWeather.dayRH ~= nil and CFAWeather.dayRH(d, (math.floor(hour) % 24) + 1, day) or nil
    local rh = math.max(0, math.min(100, rhSrc or c.humidity or 70))
    local inp = {tempC = tC, rh = rh, windMs = (c.windMph or 0) * 0.44704, rainMm = 0, si = 0,
                 meanC = (d.hiC + d.loC) / 2, sunrise = sun.sunrise, month = sun.month, day = day, hour = hour}
    if c.rain and d.wet then
        local len = math.max(0.25, (d.rainEnd or 0) - (d.rainStart or 0))
        inp.rainMm = (d.rainMM or 0) / len
    end
    -- FAO-56 Eq. 50: Rs = kRs sqrt(Tmax - Tmin) Ra (MJ/m2/day), spread over daylight as a half sine (integral = 2N/pi hours)
    if hour > sun.sunrise and hour < sun.sunset then
        local rs = CFC.KRS * math.sqrt(math.max(0, d.hiC - d.loC)) * sun.raMJ
        inp.si = rs * 1e6 / 3600 * (math.pi / (2 * sun.N)) * math.sin(math.pi * (hour - sun.sunrise) / sun.N)
    end
    inp.vpd = esKpa(tC) * (1 - rh / 100)
    return inp
end

-- Swath density of a cell, g dry matter per m2 (game windrow liters x the fill type's mass per liter x dry share / 16 m2).
function CFC.swathDensity(cell)
    local grass, hay = CFC.cellLevels(cell)
    local liters = grass + hay
    if liters <= 0 or (CFC.mplSrc or 0) <= 0 then return CFC.SD_TYPICAL, liters end
    -- v0.25.4 FIX: dry matter does not grow as the swath dries. The game keeps grass-windrow liters the same while it cures,
    -- so its mass per liter is the fresh-cut mass: DM = fresh mass x (1 - moisture at cutting). Hay liters (after the game
    -- turns them to hay) are at the hay moisture. Was: whole mass x (1 - current moisture), which made a drying swath look
    -- up to 4x heavier (capped at 1,500 g/m2) and slowed the end of drying (Rotz & Chen Eq. 4), and under-stated Ds.
    local mCut = cell.mCut or CFC.freshMoisture(nil)
    local dm = grass * CFC.mplSrc * (1 - mCut) + hay * (CFC.mplDst or CFC.mplSrc) * (1 - CFC.HAY_MOISTURE)
    local sd = dm * 1e6 / (CFC.CELL_SIZE * CFC.CELL_SIZE)
    return math.max(CFC.SD_MIN, math.min(CFC.SD_MAX, sd)), liters
end

function CFC.dryingRate(inp, sd, dayFlag, cutNo)
    -- Rotz & Chen 1985 Eq. [4], AR = 0
    local den = 61.4 * CFC.SOIL_MOISTURE_DB + sd * (1.82 - 0.83 * dayFlag) * 1.68 + 2767
    local dr = (inp.si + 43.8 * math.max(0, inp.vpd)) / den
    if not CFC.settings.conditioned then
        dr = dr * (CFC.NO_CONDITIONING[cutNo or 1] or 1)
    end
    return dr
end

-- Fresh-cut moisture (wet basis), IFSM p.57
function CFC.freshMoisture(inp)
    local M = (inp ~= nil and inp.month ~= nil and inp.month >= 6 and inp.month <= 8) and 4.5 or 5.0
    if inp ~= nil and inp.hour ~= nil and inp.sunrise ~= nil and inp.hour > inp.sunrise then
        M = M - 0.03 * (inp.hour - inp.sunrise)
    end
    return wbOf(math.max(0.25, M))
end

function CFC.readWeather()
    local env = g_currentMission.environment
    local weather = env ~= nil and env.weather or nil
    local w = {rain = 0, temperature = 20, wetness = 0, windKmh = 0, sun = 0, factor = 0, hour = 12}
    if weather == nil then
        return w
    end
    w.rain = (weather:getRainFallScale() or 0) + (weather:getSnowFallScale() or 0) + (weather:getHailFallScale() or 0)
    w.temperature = weather:getCurrentTemperature() or 20
    if weather.getGroundWetness ~= nil then
        w.wetness = weather:getGroundWetness() or 0
    end
    if weather.windUpdater ~= nil and weather.windUpdater.getCurrentValues ~= nil then
        local _, _, speed = weather.windUpdater:getCurrentValues()
        w.windKmh = (speed or 0) * 3.6
    end

    local hour = (env.dayTime or 43200000) / 3600000
    w.hour = hour
    local dayStart, dayEnd = 6, 20
    if env.daylight ~= nil and env.daylight.getDaylightTimes ~= nil then
        local s, e = env.daylight:getDaylightTimes()
        if s ~= nil and e ~= nil and e > s then
            dayStart, dayEnd = s, e
        end
    end
    if hour > dayStart and hour < dayEnd then
        w.sun = math.sin(math.pi * (hour - dayStart) / (dayEnd - dayStart))
    end

    -- Realistic Water & Soil Management: use its regional humidity and sunshine when available.
    w.humidity = nil
    -- Carolina Field Almanac weather: NOAA hourly humidity for the station
    if CFAWeather ~= nil and CFAWeather.active then
        w.humidity = CFAWeather.getHumidity()
    end
    local api = CFC.getWaterSoilAPI()
    if w.humidity == nil and api ~= nil and api.isReady ~= nil and api.isReady() and api.getDetailedSoilStateAtWorldPosition ~= nil then
        local px, pz = 0, 0
        if g_localPlayer ~= nil and g_localPlayer.getPosition ~= nil then
            local x, _, z = g_localPlayer:getPosition()
            px, pz = x or 0, z or 0
        end
        local state = api.getDetailedSoilStateAtWorldPosition(px, pz)
        if type(state) == "table" and type(state.weather) == "table" then
            local rh = tonumber(state.weather.humidityPercent)
            local solar = tonumber(state.weather.solar01)
            -- Base FS25 weather has no humidity or sunshine values; RWSM then reports a fixed
            -- 70 % humidity and no sun. Only use them when they are real (another weather mod).
            if rh ~= nil and math.abs(rh - 70) > 0.01 then
                w.humidity = rh
            end
            if solar ~= nil and solar > 0.08 and w.sun > 0 then
                w.sun = math.min(w.sun, math.clamp(solar, 0, 1.25))
            end
        end
    end

    w.dayStart, w.dayEnd = dayStart, dayEnd
    return CFC.applyFactor(w, hour, dayStart, env)
end

-- Turn a weather reading into the drying factor (shared by live readings and replayed hours).
function CFC.applyFactor(w, hour, dayStart, env)
    -- Cool fall days still cure hay, just slower (13 C about 3 days, 30 C about 2).
    local tempFactor = math.clamp((w.temperature + 5) / 25, 0.25, 1.3)
    local wetFactor = 1 - 0.6 * math.clamp(w.wetness, 0, 1)
    local windFactor = 1 + math.clamp(w.windKmh / 40, 0, 0.3)
    local seasonFactor = (env.currentSeason == Season.WINTER) and 0.4 or 1
    -- Hay stops losing water in humid air (NC State: above about 70 %).
    local humidityFactor = 1
    if w.humidity ~= nil then
        humidityFactor = math.clamp((80 - w.humidity) / 30, 0, 1)
    end
    w.humidityFactor = humidityFactor
    -- Carolina mornings: dew has to burn off before the hay really starts drying (about 3 hours).
    local dewOff = 1
    if w.sun > 0 then
        dewOff = math.clamp((hour - dayStart) / 3, 0.2, 1)
    end
    w.dewOff = dewOff
    w.factor = w.sun * tempFactor * wetFactor * windFactor * seasonFactor * humidityFactor * dewOff
    w.tempFactor, w.wetFactor, w.seasonFactor = tempFactor, wetFactor, seasonFactor
    return w
end

-- Weather for an hour that was skipped (sleep / fast time), rebuilt from CFA's day data.
-- Ground wetness and the season come from the live game (CFA has no value for them).
CFC.REPLAY_STEP_HOURS = 0.25   -- time is stepped in 15-minute pieces

-- v0.23.2: is this cell alfalfa? Read once per cell (which curing fill type has the most liters), kept on the cell.
function CFC.cellIsAlfalfa(cell)
    if cell.alf ~= nil then return cell.alf end
    local x0, z0, x1, z1, x2, z2 = CFC.getCellArea(cell.gx, cell.gz)
    local best, bestFt = 0, nil
    for _, p in ipairs(CFC.pairs) do
        for _, ft in ipairs({p.src, p.dst}) do
            local level = DensityMapHeightUtil.getFillLevelAtArea(ft, x0, z0, x1, z1, x2, z2) or 0
            if level > best then best, bestFt = level, ft end
        end
    end
    local name = bestFt ~= nil and g_fillTypeManager ~= nil and g_fillTypeManager:getFillTypeNameByIndex(bestFt) or nil
    cell.alf = name ~= nil and string.find(string.upper(name), "ALFALFA", 1, true) ~= nil
    return cell.alf
end

function CFC.stepCell(cell, hours, inp)
    local sd, liters = CFC.swathDensity(cell)
    local M = dbOf(cell.m)
    if inp.rainMm > 0 and liters > 0 then
        -- v0.23.2 Rotz 1995 Eq. 5 + 7, per rain event, with the moisture at the start of the event
        if cell.evtRain == nil then cell.evtRain, cell.evtM, cell.evtLeaf = 0, cell.m, 0 end
        local ds = math.max(0.2, math.min(2.0, sd / 1000))
        local m0 = math.max(0.2, math.min(0.9, cell.evtM))
        local alf = CFC.cellIsAlfalfa(cell)
        local ndf = alf and CFC.NDF_ALFALFA or CFC.NDF_GRASS
        local fc = (CFC.settings.conditioned ~= false) and CFC.FC_CONDITIONED or CFC.FC_NONE
        local before = math.min(CFC.RAIN_EVT_MAX, cell.evtRain)
        cell.evtRain = cell.evtRain + inp.rainMm * hours
        local rn = math.min(CFC.RAIN_EVT_MAX, cell.evtRain) - before
        local dml = CFC.LEACH_K * fc * (1 - ndf) * (0.9 - m0) * rn / ds
        if alf then
            local leaf = CFC.LEAF_K * CFC.ALFALFA_LEAF * (2 - m0) * math.sqrt(math.min(CFC.RAIN_EVT_MAX, cell.evtRain) / ds)
            dml = dml + math.max(0, leaf - cell.evtLeaf)
            cell.evtLeaf = leaf
        end
        if dml > 0 then
            cell.lossAcc = (cell.lossAcc or 0) + liters * dml
            CFC.stats.leachLiters = (CFC.stats.leachLiters or 0) + liters * dml
            if cell.lossAcc >= CFC.REMOVE_STEP then CFC.removeLiters(cell) end
        end
    elseif inp.rainMm <= 0 and cell.evtRain ~= nil then
        cell.evtRain, cell.evtM, cell.evtLeaf = nil, nil, nil   -- the rain event is over
    end
    if inp.rainMm > 0 then
        if not cell.rained then cell.newRain = true end   -- a fresh soaking (the notice check reads and clears this)
        M = CFC.RAIN_EQ_DB + (M - CFC.RAIN_EQ_DB) * math.exp(CFC.RAIN_RATE * inp.rainMm * hours / sd)
        cell.rained = true
        cell.wetByRain = true
    elseif inp.si > 0 then
        local dayFlag = (cell.cutDay == inp.day or cell.rakeDay == inp.day) and 1 or 0
        local dr = CFC.dryingRate(inp, sd, dayFlag, cell.cutNo)
        if cell.tedDay == inp.day then dr = dr * CFC.TED_FACTOR end
        M = M * math.exp(-dr * hours)
    else
        local rh = inp.rh / 100
        local me = (0.4 + 3.6 / math.exp(0.2 * inp.windMs)) / math.exp(2.5 * (1 - rh))
        M = me + (M - me) * math.exp(CFC.DEW_RATE * hours / sd)
    end
    cell.m = math.max(0.01, math.min(0.84, wbOf(math.max(0, M))))
    -- respiration loss (IFSM Eq. 6.9) while the crop is still above hay moisture
    if cell.m > CFC.HAY_MOISTURE and liters > 0 then
        local ta = math.max(0, math.min(40, inp.meanC))
        local r = CFC.RESP_K * ta * math.min(0.9, cell.m) ^ CFC.RESP_EXP * hours
        cell.lossAcc = (cell.lossAcc or 0) + liters * r
        if cell.lossAcc >= CFC.REMOVE_STEP then CFC.removeLiters(cell) end
    end
    if not cell.isHay and cell.m <= CFC.HAY_MOISTURE then
        CFC.convertCell(cell, true)
    elseif cell.isHay and cell.m > CFC.HAY_MOISTURE then
        CFC.convertCell(cell, false)
    end
end

function CFC.removeLiters(cell)
    local fillType, best = nil, 0
    local x0, z0, x1, z1, x2, z2 = CFC.getCellArea(cell.gx, cell.gz)
    for _, p in ipairs(CFC.pairs) do
        for _, ft in ipairs({p.src, p.dst}) do
            local level = DensityMapHeightUtil.getFillLevelAtArea(ft, x0, z0, x1, z1, x2, z2) or 0
            if level > best then best, fillType = level, ft end
        end
    end
    if fillType == nil then cell.lossAcc = 0 return end
    local y0 = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x0, 0, z0)
    local y1 = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x1, 0, z1)
    local y2 = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x2, 0, z2)
    local lsx, lsy, lsz, lex, ley, lez, radius = DensityMapHeightUtil.getLineByAreaDimensions(x0, y0, z0, x1, y1, z1, x2, y2, z2, true)
    local removed = DensityMapHeightUtil.tipToGroundAroundLine(nil, -CFC.REMOVE_STEP, fillType, lsx, lsy, lsz, lex, ley, lez, radius, nil, nil, false, nil)
    cell.lvStale = true   -- v0.23.0.2: liters changed - re-read on the next step
    if removed ~= nil and removed ~= 0 then
        cell.lossAcc = cell.lossAcc - CFC.REMOVE_STEP
        CFC.stats.soakLoss = CFC.stats.soakLoss + math.abs(removed)
    else
        cell.lossAcc = 0
    end
end

-- Keep Moisture System's swath piles in step with Field Cure, so its HUD, bales,
-- bale quality and bale rotting all use the same moisture as the field.
CFC.MS_GRASS_MAX = 0.40
function CFC.syncMoistureSystemCell(cell)
    if not CFC.msHooked then
        return
    end
    local tracker = g_currentMission.groundPropertyTracker
    if tracker == nil or tracker.getGridKey == nil or tracker.getStorageForFillType == nil then
        return
    end
    local s = CFC.CELL_SIZE
    local x0, z0 = cell.gx * s, cell.gz * s
    for ox = 0.5, s, 1 do
        for oz = 0.5, s, 1 do
            local px, pz = x0 + ox, z0 + oz
            for _, p in ipairs(CFC.pairs) do
                for _, ft in ipairs({p.src, p.dst}) do
                    local storage = tracker:getStorageForFillType(ft)
                    if storage ~= nil then
                        local key = tracker:getGridKey(px, pz, ft)
                        local pile = storage[key]
                        local m = cell.m
                        if ft == p.src then
                            m = math.min(m, CFC.MS_GRASS_MAX)
                        end
                        if pile ~= nil and pile.properties ~= nil then
                            pile.properties.moisture = m
                        elseif ft == p.dst and cell.isHay and tracker.queuePileUpdate ~= nil and tracker.getGridPosition ~= nil then
                            local gx, gz = tracker:getGridPosition(px, pz)
                            tracker:queuePileUpdate(key, {moisture = m}, ft, gx, gz)
                        end
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------- v0.23.0.2 frame-sliced stepping

function CFC.nowHours()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    return env ~= nil and CFC.monotonicHours(env) or 0
end

function CFC.ensureCellList()
    if CFC.cellListDirty then
        CFC.cellList = {}
        for key in pairs(CFC.cells) do
            table.insert(CFC.cellList, key)
        end
        CFC.cellListDirty = false
    end
    return CFC.cellList
end

-- One hour's inputs, shared by every cell stepping through the same game minute (cuts ~140 lookups a frame to 1-2).
CFC.inpCache, CFC.inpCacheN = {}, 0
function CFC.cachedInputs(tt)
    local key = math.floor(tt * 60 + 0.5)
    local hit = CFC.inpCache[key]
    if hit ~= nil then return hit ~= false and hit or nil end
    if CFC.inpCacheN > 512 then CFC.inpCache, CFC.inpCacheN = {}, 0 end
    local t = key / 60
    local day = math.floor(t / 24)
    local inp = CFC.hourInputs(day, t - day * 24)
    CFC.inpCache[key] = inp or false
    CFC.inpCacheN = CFC.inpCacheN + 1
    return inp
end

-- v1.0.1 (team 2026-11-22, streamers' report: "cut one day, bale the next"): hay follows the game calendar.
-- A game month has only daysPerPeriod days, so each game hour stands for (days in that real month / daysPerPeriod)
-- real hours - the same scale the crop part uses (CFACrops). Drying, dew, rain soak and respiration all run on that
-- real time, with that game hour's weather. No new numbers: real month lengths from the calendar. No cap - the player
-- picks when to cut (grass/silage: pick it up quickly on short months; hay: don't cut too wet or before rain).
function CFC.timeScale(inp)
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    local dpp = math.max(1, (env ~= nil and env.daysPerPeriod) or 1)
    local md = CFACrops ~= nil and CFACrops.MONTH_DAYS or nil
    local m = inp ~= nil and inp.month or nil
    if md == nil or m == nil or md[m] == nil then return 1 end
    return md[m] / dpp
end

-- v0.22 model unchanged: the time since this cell's last step, in 15-minute pieces, each with that time's
-- NOAA-based weather from CFA, through the Rotz & Chen / USDA IFSM model.
function CFC.stepOne(cell, tNow)
    local last = cell.lastH
    cell.lastH = tNow
    if last == nil or tNow <= last then return end
    local hours = tNow - last
    local done = 0
    while done < hours - 1e-6 do
        local step = math.min(CFC.REPLAY_STEP_HOURS, hours - done)
        local inp = CFC.cachedInputs(last + done + step / 2)
        if inp ~= nil then
            CFC.stepCell(cell, step * CFC.timeScale(inp), inp)
        elseif not CFC.noInputsLogged then
            CFC.noInputsLogged = true
            log("no CFA weather for some hours (weather part off?) - hay does not dry in those hours (no sourced inputs)")
        end
        done = done + step
    end
    CFC.syncMoistureSystemCell(cell)
end

function CFC.stepSlice(dt)
    local list = CFC.ensureCellList()
    local n = #list
    if n == 0 then return end
    local tNow = CFC.nowHours()
    local now = CFC.profNow
    local t0 = now ~= nil and now() or nil
    local capStep, capRefresh = CFC.frameCaps()
    local count = math.min(n, capStep, math.max(1, math.ceil(n * dt / CFC.STEP_CYCLE_MS)))
    CFC.stepCursor = CFC.stepCursor or 1
    for i = 1, count do
        if t0 ~= nil and i % 8 == 0 and now() - t0 >= CFC.SLICE_BUDGET_MS then return end
        if CFC.stepCursor > n then CFC.stepCursor = 1 end
        local cell = CFC.cells[list[CFC.stepCursor]]
        if cell ~= nil then CFC.stepOne(cell, tNow) end
        CFC.stepCursor = CFC.stepCursor + 1
    end
    -- fresh liters from the ground, a few cells a frame (rakes, balers and wagons pick up without telling us); empty cells are dropped
    local count2 = math.min(n, capRefresh, math.max(1, math.ceil(n * dt / CFC.LEVEL_CYCLE_MS)))
    CFC.levelCursor = CFC.levelCursor or 1
    for _ = 1, count2 do
        if t0 ~= nil and now() - t0 >= CFC.SLICE_BUDGET_MS then return end
        if CFC.levelCursor > n then CFC.levelCursor = 1 end
        local key = list[CFC.levelCursor]
        local cell = CFC.cells[key]
        if cell ~= nil then CFC.refreshCell(key, cell) end
        CFC.levelCursor = CFC.levelCursor + 1
    end
end

-- ---------------------------------------------------------------- main loop

-- ---------------------------------------------------------------- v0.25.2 self-measurement (team 2026-11-06)
-- Times every piece of CFA work (our code only: the game's own work inside a hooked function is subtracted) and logs
-- a report every 10 real minutes and at each save: calls, average and worst ms, share of real time, and Lua memory.
CFC.prof = {}
CFC.profStart = nil
CFC.PROF_REPORT_MS = 600000
local function profNow()
    if netGetTime ~= nil then return netGetTime() end   -- ms, high resolution (engine)
    if getTimeSec ~= nil then return getTimeSec() * 1000 end
    return nil
end
CFC.profNow = profNow
function CFC.profAdd(name, ms)
    local p = CFC.prof[name]
    if p == nil then p = {n = 0, sum = 0, max = 0}; CFC.prof[name] = p end
    p.n = p.n + 1
    p.sum = p.sum + ms
    if ms > p.max then p.max = ms end
end
local function pack(...) return {n = select("#", ...), ...} end
local unpack = unpack or table.unpack
-- wrap an overwrittenFunction-style hook: time it, minus the time spent in the game's own superFunc
function CFC.profHook(name, fn)
    return function(self, superFunc, ...)
        local t0 = profNow()
        if t0 == nil then return fn(self, superFunc, ...) end
        local inner = 0
        local timedSuper = function(...)
            local s0 = profNow()
            local r = pack(superFunc(...))
            inner = inner + (profNow() - s0)
            return unpack(r, 1, r.n)
        end
        local r = pack(fn(self, timedSuper, ...))
        CFC.profAdd(name, math.max(0, profNow() - t0 - inner))
        return unpack(r, 1, r.n)
    end
end
local function countKeys(t) local n = 0; if t ~= nil then for _ in pairs(t) do n = n + 1 end end; return n end
function CFC.profReport(why)
    local now = profNow()
    if now == nil or CFC.profStart == nil then return end
    local span = math.max(1, now - CFC.profStart)
    local names, total = {}, 0
    local nested = {weather = true, crops = true, ["hay cells"] = true, ["summaries+notices"] = true, ["once a second"] = true,
        ["crops hourly scan"] = true, ["crops day step"] = true}   -- already inside "frame update"
    for k, p in pairs(CFC.prof) do names[#names + 1] = k; if not nested[k] then total = total + p.sum end end
    table.sort(names, function(a, b) return CFC.prof[a].sum > CFC.prof[b].sum end)
    Logging.info("[CarolinaFieldAlmanac] performance (%s): %.1f real min, CFA total %.0f ms = %.2f %% of real time; Lua memory (all mods) %.0f MB",
        why, span / 60000, total, 100 * total / span, (gcinfo ~= nil and gcinfo() or 0) / 1024)
    for _, k in ipairs(names) do
        local p = CFC.prof[k]
        Logging.info("[CarolinaFieldAlmanac]   %s%-20s calls %7d  avg %.3f ms  worst %.2f ms  total %.0f ms", nested[k] and "  - " or "", k, p.n, p.sum / p.n, p.max, p.sum)
    end
    local crops = CFACrops ~= nil and countKeys(CFACrops.fields) or 0
    local wdays = CFAWeather ~= nil and countKeys(CFAWeather.days) or 0
    Logging.info("[CarolinaFieldAlmanac]   tracked: curing cells %d, wet bales %d, crop fields %d, weather days %d, forage stands %d",
        countKeys(CFC.cells), #(CFC.wetBales or {}), crops, wdays, CFAWinter ~= nil and countKeys(CFAWinter.fields) or 0)
    CFC.prof = {}
    CFC.profStart = now
end

function CFC:update(dt)
    local t0 = profNow()
    if t0 ~= nil and CFC.profStart == nil then CFC.profStart = t0 end
    CFC.updateInner(dt)
    if t0 ~= nil then
        local t1 = profNow()
        CFC.profAdd("frame update", t1 - t0)
        if t1 - CFC.profStart >= CFC.PROF_REPORT_MS then CFC.profReport("every 10 min") end
    end
end

-- v0.25.22 check build helpers (log only, no effect on play)
local function diagScalars(t)
    local parts = {}
    for k, v in pairs(t) do
        local tv = type(v)
        if type(k) == "string" and (tv == "string" or tv == "number" or tv == "boolean") then
            local s = tostring(v)
            if #s > 60 then s = s:sub(1, 60) .. "..." end
            parts[#parts + 1] = k .. "=" .. s
        end
    end
    table.sort(parts)
    return table.concat(parts, " ", 1, math.min(#parts, 14))
end

function CFC.diagSource()
    -- v1.0.0 (ModHub TestRunner): no debug library in released scripts; the source check was only a test aid.
end

function CFC.diagTick()
    local now = g_time or 0
    if CFC.diagUntil == nil then return end
    if now > CFC.diagUntil then CFC.diagUntil = nil log("check: end") return end
    if now < (CFC.diagNext or 0) then return end
    CFC.diagNext = now + 1000
    local m = g_currentMission
    local found = 0
    for _, root in ipairs({m, m ~= nil and m.hud or nil}) do
        if type(root) == "table" then
            for k, v in pairs(root) do
                if type(k) == "string" and (k:find("[Bb]link") or k:find("[Ww]arning")) then
                    found = found + 1
                    if type(v) == "table" then
                        log("check t+%.0fs: %s = {%s}", (now - (CFC.diagUntil - 15000)) / 1000, k, diagScalars(v))
                    elseif type(v) ~= "function" then
                        log("check t+%.0fs: %s = %s", (now - (CFC.diagUntil - 15000)) / 1000, k, tostring(v))
                    end
                end
            end
        end
    end
    if found == 0 then log("check: no blink/warning fields found on mission or hud") end
    local gv = g_gui ~= nil and g_gui:getIsGuiVisible() or false
    local hv = CFC.hudShown ~= nil and CFC.hudShown() or "?"
    log("check: gui open = %s, hud shown = %s", tostring(gv), tostring(hv))
end

-- in the world (no menu, HUD showing, game started) for 3 seconds in a row - same rule as the station reminder (v0.25.21)
function CFC.inWorldFor(ms)
    local m = g_currentMission
    local inWorld = m ~= nil and g_gui ~= nil and not g_gui:getIsGuiVisible() and m.gameStarted ~= false and CFC.hudShown()
    local t = g_time or 0
    if not inWorld then CFC.inWorldT = nil return false end
    if CFC.inWorldT == nil then CFC.inWorldT = t end
    return t - CFC.inWorldT >= ms
end

function CFC.updateInner(dt)
    if CFC.openSettingsPending then CFC.openSettingsTick() end
    if CFC.incompatText ~= nil and not CFC.incompatShown and CFC.inWorldFor(3000) then
        CFC.incompatShown = true
        CFC.showDialog("Carolina Field Almanac - NOT COMPATIBLE", CFC.incompatText, "OK", "Close")
    end
    if CFC.started and (CFC.settings.noticeMode or "popup") == "summary" then CFC.flushSummary() end
    -- v0.21.4: the player's HUD updater does not run while driving, so drive the Field Cure box from here then
    if g_localPlayer ~= nil and g_localPlayer.getCurrentVehicle ~= nil and g_localPlayer:getCurrentVehicle() ~= nil then
        CFC.updateHud(nil)
    end
    if CFC.started and CFAMP ~= nil then   -- v0.30 multiplayer: players ask the host / show the station banner; the host sends changes
        if CFAMP.isClientOnly() then
            CFAMP.clientTick(dt)
        elseif CFAMP.isMP() then
            local okM, errM = true, CFAMP.serverTick(dt)
            if not okM and not CFC.mpErrLogged then
                CFC.mpErrLogged = true
                Logging.error("[CarolinaFieldAlmanac] multiplayer send: %s", tostring(errM))
            end
        end
    end
    local p0 = profNow()
    if CFC.started and CFAWeather ~= nil then
        CFAWeather.update(dt)
    end
    local p1 = profNow()
    if p0 ~= nil then CFC.profAdd("weather", p1 - p0) end
    if CFC.started and CFACrops ~= nil and CFACrops.active then
        local ok, err = true, CFACrops.update(dt)
        if p1 ~= nil then CFC.profAdd("crops", profNow() - p1) end
        if not ok and not CFC.cropErrLogged then
            CFC.cropErrLogged = true
            Logging.error("[CarolinaFieldAlmanac] crops update error: %s", tostring(err))
        end
    end
    if not CFC.started or not CFC.isServer() then
        return
    end
    -- v0.23.0.2: a slice of the cells every frame (was: all cells in one frame each second)
    local s0 = profNow()
    CFC.stepSlice(dt)
    local s1 = profNow()
    if s0 ~= nil then CFC.profAdd("hay cells", s1 - s0) end
    CFC.stepSummary()
    if s1 ~= nil then CFC.profAdd("summaries+notices", profNow() - s1) end

    CFC.timer = CFC.timer + dt
    if CFC.timer < CFC.UPDATE_INTERVAL then
        return
    end
    CFC.timer = 0
    local k0 = profNow()

    local w = CFC.readWeather()
    CFC.lastWeather = w
    local env = g_currentMission.environment
    if env ~= nil then
        local tNow = CFC.monotonicHours(env)
        local day = math.floor(tNow / 24)
        local inp = CFC.hourInputs(day, tNow - day * 24)
        if inp ~= nil then CFC.logDry(inp) end
        local okB, errB = true, CFC.updateWetBales(tNow, env)
        if not okB and not CFC.wetBaleErrLogged then
            CFC.wetBaleErrLogged = true
            Logging.error("[CarolinaFieldCure] bale storage loss: %s", tostring(errB))
        end
    end

    if k0 ~= nil then CFC.profAdd("once a second", profNow() - k0) end
    if CFC.msPresent and not CFC.msHooked and CFC.msHookTries < 30 then
        CFC.msHookTries = CFC.msHookTries + 1
        if not CFC.tryHookMoistureSystem() and CFC.msHookTries == 30 then
            Logging.warning("[CarolinaFieldCure] Moisture System is loaded but its ground tracker was not found. Both mods may convert grass.")
        end
    end
end

-- v0.21.7 (team: hay cut Sep 1 did not dry until Feb): one log line per game hour while hay is curing, with every number
-- that goes into drying, so the next test shows exactly what holds it back.
function CFC.logDry(inp)
    if next(CFC.cells) == nil or inp == nil then return end
    local key = inp.day * 24 + math.floor(inp.hour)
    if CFC.lastDryLog == key then return end
    CFC.lastDryLog = key
    local n, sum, hay = 0, 0, 0   -- v0.25.5: from the latest summary pass (was a full pass over every cell)
    for _, s in pairs(CFC.getFieldSummaries()) do
        n = n + s.total; sum = sum + s.sumM; hay = hay + s.hay
    end
    local any = next(CFC.cells) ~= nil and CFC.cells[next(CFC.cells)] or nil
    local sd = any ~= nil and CFC.swathDensity(any) or 0
    local dr = (inp.si > 0 and inp.rainMm <= 0) and CFC.dryingRate(inp, sd, 0, any and any.cutNo) or 0
    log("dry day %d %02d:00 | sun %.0f W/m2 temp %.1fC RH %.0f%% VPD %.2f kPa wind %.1f m/s rain %.2f mm/h | swath %.0f g/m2 DR %.3f/h | x%.2f real h per game h | cells %d mean %.1f %% hay %d",
        inp.day, math.floor(inp.hour), inp.si, inp.tempC, inp.rh, inp.vpd, inp.windMs, inp.rainMm, sd, dr, CFC.timeScale(inp), n, 100 * sum / math.max(1, n), hay)
end

-- v0.23.0.2: read one cell's liters from the ground; drop it when empty (was: 150 cells in one frame each second,
-- now part of the per-frame slice in CFC.stepSlice).
function CFC.refreshCell(key, cell)
    local grass, hay = CFC.getLevels(cell.gx, cell.gz)
    CFC.storeLevels(cell, grass, hay)
    if grass + hay <= 0 then
        local fid = CFC.getCellFarmland(cell) or 0
        CFC.fidCount[fid] = math.max(0, (CFC.fidCount[fid] or 1) - 1)
        CFC.cells[key] = nil
        CFC.stats.removed = CFC.stats.removed + 1
        CFC.markCellListDirty()
        return true
    elseif cell.isHay and grass > hay and cell.m > CFC.HAY_MOISTURE then
        cell.isHay = false
    elseif not cell.isHay and hay > grass and cell.m <= CFC.HAY_MOISTURE then
        cell.isHay = true
    end
    return false
end

-- ---------------------------------------------------------------- vehicle hooks

local function getAddedLevels(sx, sz, wx, wz, hx, hz)
    local grass, hay = 0, 0
    for _, p in ipairs(CFC.pairs) do
        grass = grass + (DensityMapHeightUtil.getFillLevelAtArea(p.src, sx, sz, wx, wz, hx, hz) or 0)
        hay = hay + (DensityMapHeightUtil.getFillLevelAtArea(p.dst, sx, sz, wx, wz, hx, hz) or 0)
    end
    return grass, hay
end

-- Mower: every swath that lands gets fresh-cut moisture.
function CFC.mowerProcessDropArea(vehicle, superFunc, dropArea, ...)
    if not CFC.started or not CFC.isServer() or dropArea == nil or not CFC.srcSet[dropArea.fillType] then
        return superFunc(vehicle, dropArea, ...)
    end
    local sx, sz, wx, wz, hx, hz = CFC.getNodeArea(dropArea)
    if sx == nil then
        return superFunc(vehicle, dropArea, ...)
    end
    -- The mower tells us how much it dropped: litersToDrop goes down by the dropped amount.
    local before = dropArea.litersToDrop or 0
    local result = superFunc(vehicle, dropArea, ...)
    local added = before - (dropArea.litersToDrop or 0)
    if added > 0 then
        CFC.stats.mowerDrops = CFC.stats.mowerDrops + 1
        -- v0.22: fresh-cut moisture from IFSM p.57 (season and hour after sunrise)
        local env = g_currentMission.environment
        local day = env.currentMonotonicDay
        local inp = CFC.hourInputs(day, (env.dayTime or 0) / 3600000)
        local moisture = CFC.freshMoisture(inp)
        CFC.addToArea(sx, sz, wx, wz, hx, hz, moisture, added, CFC.MODE_SWATH)
        -- v0.23.2 Rotz 1995 Eq. 8 mowing & conditioning loss
        local fl = CFC.tedLeafShare(dropArea.fillType)
        if fl ~= nil then
            local fm = (CFC.settings.conditioned ~= false) and CFC.FM_CONDITIONED or CFC.FM_NONE
            CFC.addLossToArea(sx, sz, wx, wz, hx, hz, CFC.MOW_K * fm * (1 + 2 * fl) * CFC.MOW_SD * added, "mowLoss")
        end
    end
    return result
end

-- v0.23.2: spread a loss (liters) over the curing cells of an area; removed from the ground in REMOVE_STEP pieces.
function CFC.addLossToArea(sx, sz, wx, wz, hx, hz, lossL, statKey)
    if lossL == nil or lossL <= 0 then return end
    local cells = {}
    for _, c in ipairs(CFC.getCellsForArea(sx, sz, wx, wz, hx, hz)) do
        local cell = CFC.cells[CFC.getCellKey(c.gx, c.gz)]
        if cell ~= nil then cells[#cells + 1] = cell end
    end
    if #cells == 0 then return end
    local share = lossL / #cells
    for _, cell in ipairs(cells) do
        cell.lossAcc = (cell.lossAcc or 0) + share
        if cell.lossAcc >= CFC.REMOVE_STEP then CFC.removeLiters(cell) end
    end
    CFC.stats[statKey] = (CFC.stats[statKey] or 0) + lossL
end

-- Rake: moisture travels with the grass/hay into the new windrow.
function CFC.windrowerProcessArea(vehicle, superFunc, workArea, dt)
    if not CFC.started or not CFC.isServer() then
        return superFunc(vehicle, workArea, dt)
    end
    local sx, sz, wx, wz, hx, hz = CFC.getNodeArea(workArea)
    local carried = nil
    local ds = nil
    if sx ~= nil then
        carried = CFC.getAverageMoisture(sx, sz, wx, wz, hx, hz)
        -- v0.23.2: swath density of the picked-up area, for Rotz 1995 Eq. 13
        local sum, n = 0, 0
        for _, c in ipairs(CFC.getCellsForArea(sx, sz, wx, wz, hx, hz)) do
            local cell = CFC.cells[CFC.getCellKey(c.gx, c.gz)]
            if cell ~= nil then
                sum = sum + (CFC.swathDensity(cell))
                n = n + 1
            end
        end
        if n > 0 then ds = math.max(0.2, math.min(2.0, sum / n / 1000)) end
    end
    local dropped, area = superFunc(vehicle, workArea, dt)
    local fillType = workArea.lastValidPickupFillType
    if carried ~= nil and (workArea.lastDroppedLiters or 0) > 0 and (CFC.srcSet[fillType] or CFC.dstSet[fillType]) then
        local dropArea = vehicle.spec_workArea.workAreas[workArea.dropWindrowWorkAreaIndex]
        local dx, dz, dwx, dwz, dhx, dhz = CFC.getNodeArea(dropArea)
        if dx ~= nil then
            CFC.addToArea(dx, dz, dwx, dwz, dhx, dhz, carried, workArea.lastDroppedLiters, CFC.MODE_WINDROW)
            -- v0.23.2 Rotz 1995 Eq. 13 rake loss
            local fl = CFC.tedLeafShare(fillType)
            -- v0.23.3: not for mowers that also form a windrow (team test: 94 l "raking" with no rake used)
            if fl ~= nil and ds ~= nil and vehicle.spec_mower == nil then
                local m = math.max(0, math.min(1, carried))
                local frac = CFC.RAKE_K * (1 + 2 * fl) * (1 - m) ^ 1.5 / ds
                CFC.addLossToArea(dx, dz, dwx, dwz, dhx, dhz, frac * workArea.lastDroppedLiters, "rakeLoss")
                -- v0.25.6 check (team): liters raked and their moisture / swath density, so the save line shows the real %
                local st = CFC.stats
                st.rakedL = (st.rakedL or 0) + workArea.lastDroppedLiters
                st.rakeML = (st.rakeML or 0) + workArea.lastDroppedLiters * m
                st.rakeDsL = (st.rakeDsL or 0) + workArea.lastDroppedLiters * ds
            end
            -- v0.22: Rotz & Chen DAY = 1 on the day of raking
            local today = g_currentMission.environment.currentMonotonicDay
            for _, c in ipairs(CFC.getCellsForArea(dx, dz, dwx, dwz, dhx, dhz)) do
                local cell = CFC.cells[CFC.getCellKey(c.gx, c.gz)]
                if cell ~= nil then cell.rakeDay = today end
            end
        end
    end
    return dropped, area
end

-- Tedder (base game path): spread the grass without instantly turning it into hay.
function CFC.tedderProcessArea(vehicle, superFunc, workArea, dt)
    local spec = vehicle.spec_tedder
    if CFC.started and CFC.isServer() and spec ~= nil then
        local sx, sz, wx, wz, hx, hz = CFC.getNodeArea(workArea)
        if sx ~= nil and not CFC.isContractAt((sx + wx) * 0.5, (sz + hz) * 0.5) then
            local grass, hay = getAddedLevels(sx, sz, wx, wz, hx, hz)
            spec.cfcKeepGrass = grass > 0 and grass >= hay
        end
    end
    local r1, r2 = superFunc(vehicle, workArea, dt)
    if spec ~= nil then
        spec.cfcKeepGrass = nil
    end
    return r1, r2
end

function CFC.tedderProcessDropArea(vehicle, superFunc, dropArea, fillType, litersToDrop)
    local spec = vehicle.spec_tedder
    if spec ~= nil and spec.cfcKeepGrass and CFC.dstToSrc[fillType] ~= nil then
        fillType = CFC.dstToSrc[fillType]
    end
    return superFunc(vehicle, dropArea, fillType, litersToDrop)
end

-- IFSM v3.6 Eq. 6.13 (Rotz 1995), grass (fl = 0): share of the crop lost in one tedding pass at wet-basis moisture m.
function CFC.tedLossFraction(m, fl)
    return CFC.TED_LOSS_K * (1 + 6 * (fl or 0)) * (1 - m) ^ 1.5
end

-- Leaf share fl for Eq. 6.13 by the tedded fill type: grass 0 (IFSM), alfalfa CFC.ALFALFA_LEAF, anything else nil (no loss).
function CFC.tedLeafShare(ft)
    if ft == nil then return nil end
    if ft == FillType.GRASS_WINDROW or ft == FillType.DRYGRASS_WINDROW then return 0 end
    local name = g_fillTypeManager ~= nil and g_fillTypeManager:getFillTypeNameByIndex(ft) or nil
    if name ~= nil and string.find(string.upper(name), "ALFALFA", 1, true) then return CFC.ALFALFA_LEAF end
    return nil
end

-- After any tedder pass (base game or Moisture System): mark the ground as spread out.
function CFC.tedderOnEndWorkAreaProcessing(vehicle, dt, hasProcessed)
    if not CFC.started or not CFC.isServer() or vehicle.spec_workArea == nil then
        return
    end
    for _, workArea in ipairs(vehicle.spec_workArea.workAreas) do
        if workArea.tedderWorkAreaIndex ~= nil and (workArea.lastDroppedLiters or 0) > 0 then
            local sx, sz, wx, wz, hx, hz = CFC.getNodeArea(workArea)
            local carried = sx ~= nil and CFC.getAverageMoisture(sx, sz, wx, wz, hx, hz) or nil
            local dropArea = vehicle.spec_workArea.workAreas[workArea.dropWindrowWorkAreaIndex]
            local dx, dz, dwx, dwz, dhx, dhz = CFC.getNodeArea(dropArea)
            if dx ~= nil then
                CFC.addToArea(dx, dz, dwx, dwz, dhx, dhz, carried or CFC.freshMoisture(nil), 0, CFC.MODE_SPREAD)
                -- v0.22.1: IFSM p.58 tedding +30 % drying for the rest of that game day
                local today = g_currentMission.environment.currentMonotonicDay
                for _, c in ipairs(CFC.getCellsForArea(dx, dz, dwx, dwz, dhx, dhz)) do
                    local cell = CFC.cells[CFC.getCellKey(c.gx, c.gz)]
                    if cell ~= nil then cell.tedDay = today end
                end
                -- v0.22.3: IFSM Eq. 6.13 tedding loss - grass fl = 0, alfalfa fl = Stavarache leaf share
                local fl = CFC.tedLeafShare(workArea.lastDropFillType)
                if fl ~= nil then
                    local m = math.max(0, math.min(1, carried or CFC.freshMoisture(nil)))
                    local lossL = CFC.tedLossFraction(m, fl) * workArea.lastDroppedLiters
                    local cells = CFC.getCellsForArea(dx, dz, dwx, dwz, dhx, dhz)
                    local share = lossL / math.max(1, #cells)
                    for _, c in ipairs(cells) do
                        local cell = CFC.cells[CFC.getCellKey(c.gx, c.gz)]
                        if cell ~= nil then
                            cell.lossAcc = (cell.lossAcc or 0) + share
                            CFC.stats.tedLoss = CFC.stats.tedLoss + share
                            if cell.lossAcc >= CFC.REMOVE_STEP then CFC.removeLiters(cell) end
                        end
                    end
                end
            end
        end
    end
end

Mower.processDropArea = Utils.overwrittenFunction(Mower.processDropArea, CFC.profHook("mower", CFC.mowerProcessDropArea))
Windrower.processWindrowerArea = Utils.overwrittenFunction(Windrower.processWindrowerArea, CFC.profHook("rake", CFC.windrowerProcessArea))
Tedder.processTedderArea = Utils.overwrittenFunction(Tedder.processTedderArea, CFC.profHook("tedder pickup", CFC.tedderProcessArea))
Tedder.processDropArea = Utils.overwrittenFunction(Tedder.processDropArea, CFC.profHook("tedder drop", CFC.tedderProcessDropArea))
Tedder.onEndWorkAreaProcessing = Utils.appendedFunction(Tedder.onEndWorkAreaProcessing, CFC.tedderOnEndWorkAreaProcessing)

-- ---------------------------------------------------------------- other hay mods

function CFC.tryHookMoistureSystem()
    if CFC.msHooked then
        return true
    end
    -- Moisture System: keep everything, except its own grass<->hay switching on the ground.
    local tracker = g_currentMission ~= nil and g_currentMission.groundPropertyTracker or nil
    if tracker == nil or tracker.processHayConversions == nil or tracker.processGrassConversions == nil then
        return false
    end
    local origHay = tracker.processHayConversions
    local origGrass = tracker.processGrassConversions
    tracker.processHayConversions = function(self, ...)
        if CFC.started then
            return
        end
        return origHay(self, ...)
    end
    tracker.processGrassConversions = function(self, ...)
        if CFC.started then
            return
        end
        return origGrass(self, ...)
    end
    -- Its grass rot deletes whole swaths after an hour of rain; Field Cure handles rain damage instead.
    if tracker.tickRainExposureAndRot ~= nil then
        local origRot = tracker.tickRainExposureAndRot
        tracker.tickRainExposureAndRot = function(self, key, pile, rotAccumulators, ...)
            if CFC.started and rotAccumulators ~= nil and rotAccumulators == self.grassRotAccumulators then
                return origRot(self, key, pile, {}, ...)
            end
            return origRot(self, key, pile, rotAccumulators, ...)
        end
    end
    CFC.msHooked = true
    log("Moisture System found: NOT compatible with Carolina Field Almanac - CFA weather and Field Cure hay curing are off; remove it")
    return true
end

function CFC.handleOtherMods()
    CFC.msHooked = false
    CFC.msHookTries = 0
    CFC.msPresent = g_modIsLoaded ~= nil and g_modIsLoaded["FS25_MoistureSystem"] == true
    if CFC.msPresent then
        CFC.tryHookMoistureSystem()
    end

    CFC.conflicts = {}
    if g_modIsLoaded ~= nil then
        for _, name in ipairs({"FS25_ImprovedHay", "FS25_lsfmRealisticHayDrying"}) do
            if g_modIsLoaded[name] then
                table.insert(CFC.conflicts, name)
                Logging.warning("[CarolinaFieldCure] %s also dries grass into hay. Please use only one hay drying mod.", name)
            end
        end
    end
end

-- ---------------------------------------------------------------- save / load

function CFC.getSavePath()
    local info = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    if info == nil or info.savegameDirectory == nil or info.savegameDirectory == "" then
        return nil
    end
    return info.savegameDirectory .. "/" .. CFC.SAVE_FILE
end

function CFC.saveToFile(path)
    local xmlFile = XMLFile.create("carolinaFieldCureXML", path, "carolinaFieldCure")
    if xmlFile == nil then
        return
    end
    xmlFile:setInt("carolinaFieldCure.settings#curingDays", CFC.settings.curingDays)
    xmlFile:setBool("carolinaFieldCure.settings#conditioned", CFC.settings.conditioned ~= false)
    xmlFile:setInt("carolinaFieldCure.settings#popupSec", CFC.settings.popupSec)
    xmlFile:setString("carolinaFieldCure.settings#noticeMode", CFC.settings.noticeMode or "popup")
    xmlFile:setBool("carolinaFieldCure.settings#light", CFC.settings.light == true)
    local i = 0
    for _, cell in pairs(CFC.cells) do
        local key = string.format("carolinaFieldCure.cells.cell(%d)", i)
        xmlFile:setInt(key .. "#x", cell.gx)
        xmlFile:setInt(key .. "#z", cell.gz)
        xmlFile:setString(key .. "#m", string.format("%.4f", cell.m))
        if cell.mCut ~= nil then xmlFile:setString(key .. "#mCut", string.format("%.4f", cell.mCut)) end
        xmlFile:setInt(key .. "#mode", cell.mode)
        xmlFile:setBool(key .. "#hay", cell.isHay)
        xmlFile:setString(key .. "#wet", string.format("%.2f", cell.wetHours or 0))
        xmlFile:setBool(key .. "#rained", cell.rained == true)
        if cell.wetByRain then xmlFile:setBool(key .. "#wetByRain", true) end
        if cell.wasHay then xmlFile:setBool(key .. "#wasHay", true) end
        if cell.cutDay ~= nil then xmlFile:setInt(key .. "#cutDay", cell.cutDay) end
        if cell.rakeDay ~= nil then xmlFile:setInt(key .. "#rakeDay", cell.rakeDay) end
        if cell.tedDay ~= nil then xmlFile:setInt(key .. "#tedDay", cell.tedDay) end
        if cell.cutNo ~= nil then xmlFile:setInt(key .. "#cutNo", cell.cutNo) end
        xmlFile:setString(key .. "#loss", string.format("%.2f", cell.lossAcc or 0))
        i = i + 1
    end
    CFC.saveWetBales(xmlFile)
    xmlFile:setInt("carolinaFieldCure.notices#unread", CFC.unread)
    for n, nt in ipairs(CFC.notices) do
        local key = string.format("carolinaFieldCure.notices.notice(%d)", n - 1)
        xmlFile:setString(key .. "#date", nt.date or "")
        xmlFile:setString(key .. "#kind", nt.kind or "info")
        xmlFile:setString(key .. "#text", nt.text or "")
        if nt.farm ~= nil then xmlFile:setInt(key .. "#farm", nt.farm) end
    end
    xmlFile:save()
    xmlFile:delete()
    for id, sm in pairs(CFC.computeFieldSummaries()) do
        log("Farmland %d: %d cells, moisture %.0f-%.0f %% (mean %.0f %%), hay %d, rained %s", id, sm.total, sm.minM * 100, sm.maxM * 100,
            sm.meanM * 100, sm.hay, tostring(sm.rained))
    end
    local st = CFC.stats
    log("saved %d curing cells (session: mower drops %d, cells created %d, removed %d, to hay %d, back to grass %d, liters removed %.0f, of that tedding %.0f l, rain damage owed %.0f l, mowing owed %.0f l, raking owed %.0f l, baler pickup %.0f l, baler chamber %.0f l)",
        i, st.mowerDrops, st.created, st.removed, st.toHay, st.toGrass, st.soakLoss, st.tedLoss, st.leachLiters or 0, st.mowLoss or 0, st.rakeLoss or 0,
        st.pickupLoss or 0, st.chamberLoss or 0)
    if (st.rakedL or 0) > 0 then
        log("raking check: %.0f l raked at %.0f %% moisture (average), swath %.2f kg DM/m2 (average) -> rake loss %.0f l = %.1f %% (Rotz 1995: 1-20 %% reported)",
            st.rakedL, 100 * st.rakeML / st.rakedL, st.rakeDsL / st.rakedL, st.rakeLoss or 0, 100 * (st.rakeLoss or 0) / st.rakedL)
    end
end

function CFC.loadFromFile()
    local path = CFC.getSavePath()
    if path == nil then
        return
    end
    local xmlFile = XMLFile.loadIfExists("carolinaFieldCureXML", path)
    if xmlFile == nil then
        return
    end
    CFC.settings.curingDays = math.clamp(xmlFile:getInt("carolinaFieldCure.settings#curingDays", CFC.settings.curingDays), 1, 10)
    CFC.settings.conditioned = xmlFile:getBool("carolinaFieldCure.settings#conditioned", true)
    CFC.settings.popupSec = math.clamp(xmlFile:getInt("carolinaFieldCure.settings#popupSec", CFC.settings.popupSec), 5, 20)
    CFC.settings.noticeMode = xmlFile:getString("carolinaFieldCure.settings#noticeMode", CFC.settings.noticeMode)
    CFC.settings.light = xmlFile:getBool("carolinaFieldCure.settings#light", false)
    local count = 0
    xmlFile:iterate("carolinaFieldCure.cells.cell", function(_, key)
        local gx = xmlFile:getInt(key .. "#x")
        local gz = xmlFile:getInt(key .. "#z")
        if gx ~= nil and gz ~= nil then
            CFC.cells[CFC.getCellKey(gx, gz)] = {
                gx = gx, gz = gz,
                m = tonumber(xmlFile:getString(key .. "#m", "0.5")) or 0.5,
                mode = xmlFile:getInt(key .. "#mode", CFC.MODE_SWATH),
                isHay = xmlFile:getBool(key .. "#hay", false),
                wetHours = tonumber(xmlFile:getString(key .. "#wet", "0")) or 0,
                rained = xmlFile:getBool(key .. "#rained", false),
                wetByRain = xmlFile:getBool(key .. "#wetByRain", false) or nil,
                wasHay = xmlFile:getBool(key .. "#wasHay", false) or nil,
                cutDay = xmlFile:getInt(key .. "#cutDay"), rakeDay = xmlFile:getInt(key .. "#rakeDay"), tedDay = xmlFile:getInt(key .. "#tedDay"), cutNo = xmlFile:getInt(key .. "#cutNo"),
                lossAcc = tonumber(xmlFile:getString(key .. "#loss", "0")) or 0,
                mCut = tonumber(xmlFile:getString(key .. "#mCut", ""))
            }
            if not CFC.cells[CFC.getCellKey(gx, gz)].rained then
                CFC.cells[CFC.getCellKey(gx, gz)].wetHours = 0
            end
            count = count + 1
        end
    end)
    CFC.notices = {}
    xmlFile:iterate("carolinaFieldCure.notices.notice", function(_, key)
        table.insert(CFC.notices, {date = xmlFile:getString(key .. "#date", ""), kind = xmlFile:getString(key .. "#kind", "info"),
            text = xmlFile:getString(key .. "#text", ""), farm = xmlFile:getInt(key .. "#farm")})
    end)
    for i = #CFC.notices, 1, -1 do   -- v0.30: ids for sending to players (oldest = 1)
        CFC.noticeSeq = CFC.noticeSeq + 1
        CFC.notices[i].id = CFC.noticeSeq
    end
    CFC.unread = math.min(#CFC.notices, xmlFile:getInt("carolinaFieldCure.notices#unread", 0))
    CFC.loadWetBales(xmlFile)
    xmlFile:delete()
    CFC.markCellListDirty()
    CFC.fidCount = {}
    for _, cell in pairs(CFC.cells) do
        local fid = CFC.getCellFarmland(cell) or 0
        CFC.fidCount[fid] = (CFC.fidCount[fid] or 0) + 1
    end
    log("loaded %d curing cells (drying: Rotz & Chen 1985 / USDA IFSM, mower conditions hay: %s)", count, tostring(CFC.settings.conditioned ~= false))
end

function CFC.onSaveCareer(missionInfo)
    CFC.profReport("at save")
    if missionInfo ~= nil and missionInfo.savegameDirectory ~= nil and CFC.started then
        CFC.saveToFile(missionInfo.savegameDirectory .. "/" .. CFC.SAVE_FILE)
    end
    if missionInfo ~= nil and missionInfo.savegameDirectory ~= nil and CFAWeather ~= nil and CFAWeather.active then
        CFAWeather.save(missionInfo.savegameDirectory .. "/" .. CFAWeather.SAVE_FILE)
    end
    if missionInfo ~= nil and missionInfo.savegameDirectory ~= nil and CFACrops ~= nil and CFACrops.active then
        local ok, err = true, CFACrops.save(missionInfo.savegameDirectory .. "/" .. CFACrops.SAVE_FILE)
        if not ok then Logging.error("[CarolinaFieldAlmanac] crops save error: %s", tostring(err)) end
    end
end

FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, CFC.onSaveCareer)

-- ---------------------------------------------------------------- start

-- v0.30 multiplayer: a player's own notice settings (pop-ups / summary / menu, pop-up time) are kept on their PC
function CFC.playerPrefsPath()
    if getUserProfileAppPath == nil then return nil end
    return getUserProfileAppPath() .. "modSettings/FS25_CarolinaFieldAlmanac_player.xml"
end
function CFC.savePlayerPrefs()
    if CFAMP == nil or not CFAMP.isClientOnly() then return end
    local path = CFC.playerPrefsPath()
    if path == nil then return end
    do (function()
        if createFolder ~= nil then createFolder(getUserProfileAppPath() .. "modSettings") end
        local xml = XMLFile.create("cfaPlayerPrefs", path, "carolinaFieldAlmanacPlayer")
        if xml == nil then return end
        xml:setString("carolinaFieldAlmanacPlayer#noticeMode", CFC.settings.noticeMode or "popup")
        xml:setInt("carolinaFieldAlmanacPlayer#popupSec", CFC.settings.popupSec or 10)
        xml:save()
        xml:delete()
    end)() end
end
function CFC.loadPlayerPrefs()
    local path = CFC.playerPrefsPath()
    if path == nil then return end
    do (function()
        local xml = XMLFile.loadIfExists("cfaPlayerPrefs", path)
        if xml == nil then return end
        CFC.settings.noticeMode = xml:getString("carolinaFieldAlmanacPlayer#noticeMode", CFC.settings.noticeMode)
        CFC.settings.popupSec = xml:getInt("carolinaFieldAlmanacPlayer#popupSec", CFC.settings.popupSec)
        xml:delete()
    end)() end
end

function CFC.onStartMission(mission)
    if CFARegrowth ~= nil then CFARegrowth.apply() end   -- v0.25.1 regrowth after a cut
    CFC.buildFillTypePairs()
    CFC.handleOtherMods()
    if CFC.isServer() then
        CFC.loadFromFile()
    else
        CFC.loadPlayerPrefs()   -- v0.30: a player in someone else's game
    end
    CFC.started = true
    if CFAWeather ~= nil then
        local ok, err = true, CFAWeather.start(mission)
        if not ok then
            Logging.error("[CarolinaFieldAlmanac] weather start failed: %s", tostring(err))
            CFAWeather.active = false
        end
    end
    if CFACrops ~= nil then
        local ok, err = true, CFACrops.start(mission)
        if not ok then
            Logging.error("[CarolinaFieldAlmanac] crops start failed: %s", tostring(err))
            CFACrops.active = false
        end
    end
    addConsoleCommand("cfaCrops", "Carolina Field Almanac: show each field's degree days, stage and weather losses", "consoleCrops", CFC)
    addConsoleCommand("cfaStation", "Carolina Field Almanac: show or set the NOAA weather station", "consoleStation", CFC)
    addConsoleCommand("cfaWeather", "Carolina Field Almanac: show today's and the next days' weather", "consoleWeather", CFC)
    addConsoleCommand("cfcCuringDays", "Carolina Field Cure: old setting, no longer used (hay dries from the real weather)", "consoleCuringDays", CFC)
    addConsoleCommand("cfcInfo", "Carolina Field Cure: show curing status", "consoleInfo", CFC)
    addConsoleCommand("cfaNotices", "Carolina Field Almanac: list Field Cure notices (marks them read)", "consoleNotices", CFC)
    log("loaded v%s (drying model Rotz & Chen 1985 / USDA IFSM; Realistic Water & Soil humidity %s)", CFC.VERSION,
        CFC.getWaterSoilAPI() ~= nil and "found" or "not found")
    -- v0.26.3 (team 2026-11-12): other weather / hay drying mods are NOT compatible with CFA. Tell the player plainly,
    -- in a pop-up and on the Notifications tab, every time the save loads.
    local msgs = {}
    local wc = (CFAWeather ~= nil and CFAWeather.findConflict ~= nil) and CFAWeather.findConflict() or nil
    if wc ~= nil then
        table.insert(msgs, string.format(text("cfa_incompatible_weather",
            "Carolina Field Almanac is NOT compatible with %s. Our real weather (NOAA, Environment Canada and European weather services), crop weather damage, CFA crop insurance and Field Cure hay curing are off while it is installed. Remove it to use Carolina Field Almanac."), wc))
    end
    if #(CFC.conflicts or {}) > 0 then
        table.insert(msgs, string.format(text("cfa_incompatible_hay",
            "Carolina Field Almanac is NOT compatible with %s. It also dries grass into hay and fights with Carolina Field Cure. Remove it."),
            table.concat(CFC.conflicts, ", ")))
    end
    for _, msg in ipairs(msgs) do
        Logging.warning("[CarolinaFieldAlmanac] %s", msg)
        CFC.addNotice("warning", msg)
        if mission ~= nil and mission.addIngameNotification ~= nil then
            mission.addIngameNotification(mission, FSBaseMission.INGAME_NOTIFICATION_CRITICAL, msg)
        end
    end
    if #msgs > 0 then   -- v0.27.1 must-see: window once the player is in the world, and a banner that stays up this session
        CFC.incompatText = table.concat(msgs, "\n\n")
        local names = {}
        if wc ~= nil then names[#names + 1] = wc end
        for _, n in ipairs(CFC.conflicts or {}) do names[#names + 1] = n end
        CFC.incompatNames = table.concat(names, ", ")
        CFC.setBanner("incompatible", "NOT COMPATIBLE: " .. CFC.incompatNames, wc ~= nil and "CFA weather, crop damage, insurance and hay curing are off - remove that mod"
            or "It fights with Carolina Field Cure hay drying - remove that mod")
    end
end

FSBaseMission.onStartMission = Utils.appendedFunction(FSBaseMission.onStartMission, CFC.onStartMission)

-- v0.18: the Field Almanac page in the game's menu (ESC)
function CFC:loadMap()
    if CFACrops ~= nil and CFACrops.registerMoneyTypes ~= nil then
        local ok, err = true, CFACrops.registerMoneyTypes()
        log("finances: insurance rows %s", ok and ((MoneyType ~= nil and MoneyType.CFA_INSURANCE_PREMIUM ~= nil) and "added (CFA Insurance Premium / CFA Insurance Claim)" or "not available - insurance stays under Misc") or ("failed: " .. tostring(err)))
    end
    if CFAMenu ~= nil and g_gui ~= nil then
        local ok, err = true, CFAMenu.addPage()
        if not ok then
            Logging.error("[CarolinaFieldAlmanac] menu page not added: %s", tostring(err))
        else
            log("Field Almanac menu page added")
        end
    end
end

-- v0.21.10 panel for driving: same API as the game's key/value box
CFC.vehBox = {lines = {}, title = "", untilTime = 0}
function CFC.vehBox:clear() self.lines = {} end
function CFC.vehBox:setTitle(s) self.title = s or "" end
function CFC.vehBox:addLine(k, v) self.lines[#self.lines + 1] = {tostring(k or ""), tostring(v or "")} end
function CFC.vehBox:showNextFrame() self.untilTime = (g_time or 0) + 250 end

-- v0.25.9 (team 2026-11-08): our own vehicle box follows the game's HUD on/off, like every other HUD element.
function CFC.hudShown()
    local hud = g_currentMission ~= nil and g_currentMission.hud or nil
    if hud == nil then return true end
    if hud.getIsVisible ~= nil then
        local ok, v = true, hud.getIsVisible(hud)
        if ok and v ~= nil then return v end
    end
    if hud.isVisible ~= nil then return hud.isVisible end
    return true
end

-- ------------------------------------------------------------------ must-see messages (v0.27.1, team 2026-11-12)
-- The game's blinking warning box does not show on every PC (on a test laptop: accepted, never visible), and the small
-- orange top line is hard to read. For messages a player must not miss we use two layers that do not depend on it:
-- 1) a window that stops the game (the game's own Yes/No dialog - the same window system as its menus), and
-- 2) our own big red banner, drawn like the Field Cure box, that stays up until the problem is fixed.
CFC.banners = {}   -- id -> {title, line, untilTime (nil = until removed)}
function CFC.setBanner(id, title, line, seconds)
    CFC.banners[id] = {title = title, line = line, untilTime = seconds ~= nil and ((g_time or 0) + seconds * 1000) or nil}
end
function CFC.clearBanner(id) CFC.banners[id] = nil end

function CFC.showDialog(title, text, yesText, noText, onYes, onNo)
    local function cb(yes)
        if yes then
            if onYes ~= nil then onYes() end
        elseif onNo ~= nil then
            onNo()
        end
    end
    if YesNoDialog ~= nil and YesNoDialog.show ~= nil then
        local ok, err = true, YesNoDialog.show(cb, nil, text, title, yesText, noText)
        if ok then log("must-see: window shown (YesNoDialog) - %s", title) return true end
        log("must-see: YesNoDialog.show failed: %s", tostring(err))
    end
    if g_gui ~= nil and g_gui.showYesNoDialog ~= nil then
        local ok, err = true, g_gui.showYesNoDialog(g_gui, {text = text, title = title, yesText = yesText, noText = noText, callback = cb})
        if ok then log("must-see: window shown (showYesNoDialog) - %s", title) return true end
        log("must-see: showYesNoDialog failed: %s", tostring(err))
    end
    if InfoDialog ~= nil and InfoDialog.show ~= nil then
        local ok, err = true, InfoDialog.show(text)
        if ok then log("must-see: window shown (InfoDialog) - %s", title) return true end
        log("must-see: InfoDialog.show failed: %s", tostring(err))
    end
    log("must-see: no window could be shown - banner only (%s)", title)
    return false
end

-- open ESC > Field Almanac > Settings tab (after the window has closed)
function CFC.openSettingsTab()
    CFC.openSettingsPending = true
end
function CFC.openSettingsTick()
    if not CFC.openSettingsPending or g_gui == nil then return end
    if g_gui:getIsGuiVisible() then return end   -- wait for the window to close
    CFC.openSettingsPending = false
    if CFAMenuFrame ~= nil then CFAMenuFrame.forceTab = CFAMenuFrame.TAB_SETTINGS end
    local ok, err = true, (function()
        g_gui:showGui("InGameMenu")
        local igm = g_gui.screenControllers[InGameMenu]
        if igm ~= nil and CFAMenu ~= nil and CFAMenu.frame ~= nil and igm.goToPage ~= nil then igm:goToPage(CFAMenu.frame) end
    end)()
    log("must-see: open Field Almanac Settings tab %s", ok and "ok" or ("failed: " .. tostring(err)))
end

function CFC.drawBanners()
    if next(CFC.banners) == nil then return end
    if g_gui ~= nil and g_gui:getIsGuiVisible() then return end
    if not CFC.hudShown() then return end
    local now = g_time or 0
    local y = 0.84
    for id, b in pairs(CFC.banners) do
        if b.untilTime ~= nil and now > b.untilTime then
            CFC.banners[id] = nil
        else
            local w, h = 0.62, 0.072
            local x = 0.5 - w / 2
            local pulse = (math.floor(now / 600) % 2 == 0) and 0.95 or 0.70   -- flashes so the eye catches it
            if drawFilledRect ~= nil then
                drawFilledRect(x - 0.003, y - 0.005, w + 0.006, h + 0.010, 1, 1, 1, 0.9)        -- white outline
                drawFilledRect(x, y - 0.002, w, h + 0.004, 0.75, 0.02, 0.02, pulse)             -- red box
            end
            setTextAlignment(RenderText.ALIGN_CENTER)
            setTextBold(true)
            setTextColor(1, 1, 1, 1)
            renderText(0.5, y + h - 0.030, 0.026, b.title or "")
            setTextBold(false)
            renderText(0.5, y + 0.010, 0.016, b.line or "")
            setTextAlignment(RenderText.ALIGN_LEFT)
            y = y - h - 0.02
        end
    end
end

function CFC:draw()
    CFC.drawBanners()
    local b = CFC.vehBox
    if b == nil or (g_time or 0) > b.untilTime or #b.lines == 0 then return end
    if g_localPlayer == nil or g_localPlayer.getCurrentVehicle == nil or g_localPlayer:getCurrentVehicle() == nil then return end
    if g_gui ~= nil and g_gui:getIsGuiVisible() then return end
    if not CFC.hudShown() then return end   -- v0.25.9: hide with the game's HUD (Scroll Lock / hide-HUD key)
    local w, lh, size = 0.20, 0.019, 0.0125
    -- v1.0.2 (team 2026-11-22): panel sits bottom-left, right above the game's mini map, so the Field Cure box and CFA's map
    -- icons are seen together and the right side stays free for other mods' cards (Lifestyle). Was right side, top 0.62.
    local x = 0.012
    local h = lh * (#b.lines + 1) + 0.012
    local yTop = CFC.VEH_PANEL_BOTTOM + h
    if drawFilledRect ~= nil then drawFilledRect(x - 0.006, yTop - h, w + 0.012, h + 0.008, 0, 0, 0, 0.6) end
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
    renderText(x, yTop - lh, size * 1.1, b.title or "")
    setTextBold(false)
    for i, l in ipairs(b.lines) do
        local y = yTop - lh * (i + 1)
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextColor(0.85, 0.85, 0.85, 1)
        renderText(x, y, size, l[1])
        setTextAlignment(RenderText.ALIGN_RIGHT)
        setTextColor(1, 1, 1, 1)
        renderText(x + w, y, size, l[2])
    end
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end

function CFC:deleteMap()
    if CFAMenu ~= nil then
        CFAMenu.removePage()
    end
    CFC.cells = {}
    CFC.cellList = {}
    CFC.cellListDirty = true
    CFC.stepCursor, CFC.levelCursor = 1, 1
    CFC.inpCache, CFC.inpCacheN = {}, 0
    CFC.started = false
    CFC.waterSoilAPI = nil
    removeConsoleCommand("cfcCuringDays")
    removeConsoleCommand("cfcInfo")
    removeConsoleCommand("cfaNotices")
    for id in pairs(CFC.hotspots or {}) do
        CFC.removeHotspot(id)
    end
    CFC.hotspots = {}
    CFC.rainAlert = {}
    CFC.wetBales = {}
    CFC.notices = {}
    CFC.unread = 0
    CFC.fieldNotice = nil
    removeConsoleCommand("cfaCrops")
    if CFACrops ~= nil then
        CFACrops.active = false
        CFACrops.fields = {}
        CFACrops.crops = {}
        CFACrops.lastDay = nil
        CFACrops.lastHour = nil
    end
    if CFC.hudBox == CFC.vehBox then CFC.hudBox = CFC.realBox end
    CFC.realBox = nil
    if CFC.hudBox ~= nil and g_currentMission ~= nil and g_currentMission.hud ~= nil then
        g_currentMission.hud.infoDisplay:destroyBox(CFC.hudBox)
    end
    CFC.hudBox = nil
end

function CFC:consoleCuringDays(value)
    local days = tonumber(value)
    if days == nil then
        return string.format("Curing days: %d - old setting, no longer used: hay dries from the real weather (Rotz & Chen 1985)", CFC.settings.curingDays)
    end
    CFC.settings.curingDays = math.clamp(math.floor(days), 1, 10)
    return string.format("Curing days set to %d - old setting, no longer used: hay dries from the real weather (Rotz & Chen 1985)", CFC.settings.curingDays)
end

function CFC:consoleWeather()
    if CFAWeather == nil or not CFAWeather.active then
        return "Carolina Field Almanac weather is off" .. (CFAWeather ~= nil and CFAWeather.conflict ~= nil and (" (" .. CFAWeather.conflict .. " drives the weather)") or "")
    end
    local env = g_currentMission.environment
    local lines = {string.format("Station %s - %s. Humidity now %.0f %%, temp now %.1f C", CFAWeather.stationId, CFAWeather.getStationText(),
        CFAWeather.getHumidity() or -1, env.weather:getCurrentTemperature() or -99)}
    for i = 0, 6 do
        local d = CFAWeather.getDay(env.currentMonotonicDay + i)
        table.insert(lines, string.format("day +%d (month %d): %s", i, d.month, CFAWeather.getDayText(d)))
    end
    if CFAWeather.missingTypes ~= nil then
        table.insert(lines, string.format("note: map lacked a weather type %d times", CFAWeather.missingTypes))
    end
    return table.concat(lines, "\n")
end

-- cfaStation            -> current station
-- cfaStation springfield -> list matching stations
-- cfaStation USW00013995 -> use that station
function CFC:consoleStation(arg)
    if CFAWeather == nil or CFAStationData == nil then
        return "weather part not loaded"
    end
    if arg == nil or arg == "" then
        return string.format("Station %s - %s (usage: cfaStation <city or station id>)", CFAWeather.stationId, CFAWeather.getStationText())
    end
    if CFAStationData.stations[arg] ~= nil then
        CFAWeather.setStation(arg)
        CFAWeather.uiRefresh()
        return "Station set: " .. CFAWeather.getStationText()
    end
    local found = {}
    local q = string.lower(arg)
    for id, st in pairs(CFAStationData.stations) do
        if string.find(string.lower(st.city), q, 1, true) then
            table.insert(found, string.format("%s  %s", id, CFAWeather.getStationText(id)))
        end
    end
    table.sort(found)
    if #found == 0 then
        return "No station matches " .. arg
    end
    return table.concat(found, "\n")
end

function CFC:consoleCrops()
    if CFACrops == nil then return "crops part not loaded" end
    return CFACrops.consoleCrops()
end

function CFC:consoleInfo()
    local count = 0
    local hay = 0
    for _, cell in pairs(CFC.cells) do
        count = count + 1
        if cell.isHay then
            hay = hay + 1
        end
    end
    local w = CFC.lastWeather or CFC.readWeather()
    local st = CFC.stats
    log("info: mower drops %d, created %d, removed %d, to hay %d, back to grass %d, RWSM %s, Moisture System hooked %s",
        st.mowerDrops, st.created, st.removed, st.toHay, st.toGrass, tostring(CFC.getWaterSoilAPI() ~= nil), tostring(CFC.msHooked == true))
    local env = g_currentMission.environment
    local inp = CFC.hourInputs(env.currentMonotonicDay, (env.dayTime or 0) / 3600000)
    if inp == nil then return string.format("Cells %d (hay %d) | no CFA weather - no drying", count, hay) end
    local any = next(CFC.cells) ~= nil and CFC.cells[next(CFC.cells)] or nil
    local sd = any ~= nil and CFC.swathDensity(any) or CFC.SD_TYPICAL
    return string.format("Cells %d (hay %d) | sun %.0f W/m2 temp %.1fC RH %.0f%% VPD %.2f kPa rain %.2f mm/h | swath %.0f g/m2 -> drying rate %.3f /h (Rotz & Chen 1985) | conditioned %s",
        count, hay, inp.si, inp.tempC, inp.rh, inp.vpd, inp.rainMm, sd, CFC.dryingRate(inp, sd, 0, any and any.cutNo), tostring(CFC.settings.conditioned ~= false))
end

-- ---------------------------------------------------------------- HUD (stand on a swath)

function CFC.getStatusText(cell)
    if cell.m <= CFC.HAY_MOISTURE then
        return text("cfc_status_bale", "Ready to bale")
    elseif cell.wetByRain then
        return text("cfc_status_rained", "Rained on - curing")
    end
    return text("cfc_status_curing", "Curing")
end

-- ---------------------------------------------------------------- v0.15 field summary (team design)
-- The whole field at once: how much of the cut area is hay yet, driest / wettest spot, status.
-- Area = tracked 4 m x 4 m cells x 16 m2 (no new numbers).

CFC.RAIN_EVENT_GAP_HOURS = 12   -- v0.21.4: one rain warning per rain; a new rain = 12 game hours with no rain on that patch (team game rule)
CFC.NOTICE_STEP = 10   -- pop-up every 10 % of the cut area that turns to hay (team: "50% ... 60% ... til it hit hay")

function CFC.getCellFarmland(cell)
    if cell.farmlandId == nil then
        local id = 0
        if g_farmlandManager ~= nil and g_farmlandManager.getFarmlandIdAtWorldPosition ~= nil then
            local s = CFC.CELL_SIZE
            id = g_farmlandManager:getFarmlandIdAtWorldPosition((cell.gx + 0.5) * s, (cell.gz + 0.5) * s) or 0
        end
        cell.farmlandId = id
    end
    return cell.farmlandId
end

-- v0.23.0.2: the HUD box reads the field summaries at most once a second (was every 0.3 s over every curing cell).
CFC.NEAR_CUT_M = 50   -- v1.0.3: how close (metres) to cut hay the Field Cure box shows

-- v1.0.3: is there tracked cut grass / hay of this farmland within NEAR_CUT_M of (x, z)?
function CFC.nearCut(x, z, fid)
    local s = CFC.CELL_SIZE
    local r = math.ceil(CFC.NEAR_CUT_M / s)
    local gx, gz = math.floor(x / s), math.floor(z / s)
    local r2 = CFC.NEAR_CUT_M * CFC.NEAR_CUT_M
    for ox = -r, r do
        for oz = -r, r do
            local c = CFC.cells[CFC.getCellKey(gx + ox, gz + oz)]
            if c ~= nil then
                local dx = (c.gx + 0.5) * s - x
                local dz = (c.gz + 0.5) * s - z
                if dx * dx + dz * dz <= r2 and (fid == nil or CFC.getCellFarmland(c) == fid) then return true end
            end
        end
    end
    return false
end

function CFC.hudSummaries()
    return CFC.getFieldSummaries()   -- v0.25.5: the sliced pass keeps it fresh (about once a second)
end

-- v0.25.5: add one cell to a summary table (shared by the full build and the sliced pass)
local function sumAdd(sums, cell)
        local id = CFC.getCellFarmland(cell)
        if id ~= nil and id > 0 then
            local s = sums[id]
            if s == nil then
                s = {id = id, fieldCells = 0, total = 0, hay = 0, minM = math.huge, maxM = 0, rewet = false, sumM = 0, rained = false, newRain = 0, x = 0, z = 0}
                sums[id] = s
            end
            s.total = s.total + 1
            if CFC.getCellOnField(cell) then s.fieldCells = s.fieldCells + 1 end
            if cell.isHay then
                s.hay = s.hay + 1
            elseif cell.rewet then
                s.rewet = true
            end
            if cell.m < s.minM then s.minM = cell.m end
            if cell.m > s.maxM then s.maxM = cell.m end
            s.sumM = s.sumM + cell.m
            if cell.rained then s.rained = true end
            if cell.newRain then s.newRain = s.newRain + 1 end
            if cell.wasHay and not cell.isHay and not cell.wetByRain then s.dew = (s.dew or 0) + 1 end
            s.x = s.x + (cell.gx + 0.5) * CFC.CELL_SIZE
            s.z = s.z + (cell.gz + 0.5) * CFC.CELL_SIZE
        end
end
local function sumFinish(sums)
    for _, s in pairs(sums) do
        s.meanM = s.sumM / s.total
        s.x, s.z = s.x / s.total, s.z / s.total   -- middle of the cut hay on this farmland (map icon)
    end
    return sums
end

-- Full build in one go (save, console, first look before a pass has finished).
function CFC.computeFieldSummaries()
    local sums = {}
    for _, cell in pairs(CFC.cells) do sumAdd(sums, cell) end
    return sumFinish(sums)
end

-- The latest finished pass (refreshed about once a second), or a full build if no pass has finished yet.
function CFC.getFieldSummaries()
    if CFC.sumCache ~= nil then return CFC.sumCache end
    return CFC.computeFieldSummaries()
end

-- v0.25.5 one slice of the summary pass; when a pass is done: publish it, then the notices run on it.
function CFC.stepSummary()
    local now = g_time or 0
    local P = CFC.sumPass
    if P == nil then
        if CFC.sumPassAt ~= nil and now - CFC.sumPassAt < CFC.UPDATE_INTERVAL and now >= CFC.sumPassAt then return end
        local keys = {}
        for k in pairs(CFC.cells) do keys[#keys + 1] = k end
        P = {keys = keys, i = 1, sums = {}}
        CFC.sumPass, CFC.sumPassAt = P, now
    end
    local _, _, capSum = CFC.frameCaps()
    local stop = math.min(#P.keys, P.i + capSum - 1)
    for i = P.i, stop do
        local cell = CFC.cells[P.keys[i]]
        if cell ~= nil then
            sumAdd(P.sums, cell)
            cell.newRain = nil   -- counted once (was cleared in checkFieldNotices)
        end
    end
    P.i = stop + 1
    if P.i > #P.keys then
        CFC.sumPass = nil
        CFC.sumCache = sumFinish(P.sums)
        if CFC.started then
            local okN, errN = true, CFC.checkFieldNotices(CFC.sumCache)
            CFC.noticeFarm = nil
            if not okN and not CFC.noticeErrLogged then
                CFC.noticeErrLogged = true
                Logging.error("[CarolinaFieldCure] field notice error: %s", tostring(errN))
            end
        end
    end
end

-- v0.21.3: is this cell inside a field (the game's field outlines)? Cached per cell.
function CFC.getCellOnField(cell)
    if cell.onField == nil then
        local on = true   -- unknown = treat as field (no change from before)
        if CFACrops ~= nil and CFACrops.fieldAt ~= nil and g_fieldManager ~= nil then
            local s = CFC.CELL_SIZE
            local ok, f = true, CFACrops.fieldAt((cell.gx + 0.5) * s, (cell.gz + 0.5) * s)
            if ok then on = f ~= nil end
        end
        cell.onField = on
    end
    return cell.onField
end

-- v0.21.3 (team): cut grass under 0.05 acre (stray squares over a line) gets no map icon, no Hay tab row and no pop-ups.
CFC.MIN_SHOW_ACRES = 0.05
function CFC.isTiny(s)
    return s.total * CFC.CELL_SIZE * CFC.CELL_SIZE / 4046.8564224 < CFC.MIN_SHOW_ACRES
end

function CFC.getFieldLabel(farmlandId, s)
    -- v0.16.1: the summary covers all cut hay on this farmland (fields, driveways, yards), so say Farmland, as the game's Field Info does
    -- v0.21.3: mostly outside the game's fields = roadside / ditch / yard grass (team)
    if s ~= nil and s.fieldCells ~= nil and s.fieldCells * 2 < s.total then
        return string.format("%s (%s %s)", text("cfc_roadside", "Roadside"), text("cfc_farmland", "Farmland"), tostring(farmlandId))
    end
    return text("cfc_farmland", "Farmland") .. " " .. tostring(farmlandId)
end

local function formatHa(ha)
    if g_i18n ~= nil and g_i18n.formatArea ~= nil then
        return g_i18n:formatArea(ha, 1)
    end
    return string.format("%.1f ha", ha)
end

function CFC.getReadyText(s)
    local ha = CFC.CELL_SIZE * CFC.CELL_SIZE / 10000
    local pct = math.floor(100 * s.hay / s.total + 1e-6)
    return string.format("%s %s %s (%d %%)", formatHa(s.hay * ha), text("cfc_of", "of"), formatHa(s.total * ha), pct), pct
end

function CFC.getFieldStatus(s)
    -- v0.22: one sourced line - hay at 20 % or less (NC State). Overnight dew can lift it back over 20 % (tough hay): wait for it to dry off.
    if s.hay >= s.total then
        return text("cfc_status_bale", "Ready to bale")
    end
    if s.rewet then
        return text("cfc_status_rained", "Rained on - curing")
    end
    if (s.dew or 0) > 0 and s.dew + s.hay >= s.total then
        return text("cfc_status_tough", "Dew - wait for it to dry off")
    end
    return text("cfc_status_curing", "Curing")
end

-- v0.17 notices (team design): every notice is kept (saved with the game) so a missed pop-up can be read later.
-- "warning" = red blinking warning in the middle of the screen + side notice; others = side notice under the money, shown longer.
CFC.notices = {}
CFC.unread = 0
CFC.MAX_NOTICES = 100
CFC.SIDE_NOTICE_MS = 10000
CFC.WARNING_MS = 6000
local MONTHS = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

function CFC.dateText()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env == nil then return "" end
    local day = env.currentMonotonicDay or 0
    local month = nil
    if CFAWeather ~= nil and CFAWeather.monthAtDay ~= nil then
        local ok, m = true, CFAWeather.monthAtDay(day)
        if ok then month = m end
    end
    local h = (env.dayTime or 0) / 3600000
    local hh, mm = math.floor(h), math.floor((h - math.floor(h)) * 60)
    if month ~= nil and MONTHS[month] ~= nil then
        return string.format("%s %d %02d:%02d", MONTHS[month], env.currentDayInPeriod or 1, hh, mm)
    end
    return string.format("Day %d %02d:%02d", day, hh, mm)
end

-- v0.30 multiplayer: a notice belongs to a farm (farmId, or the farm of the vehicle / field being worked: CFC.noticeFarm;
-- nil = everyone). Every game keeps all of them; each player sees and is told about their own farm's and everyone's.
CFC.noticeSeq = 0
CFC.noticeFarm = nil
function CFC.farmlandFarm(fid)
    if fid == nil or g_farmlandManager == nil or g_farmlandManager.getFarmlandOwner == nil then return nil end
    local ok, owner = true, g_farmlandManager.getFarmlandOwner(g_farmlandManager, fid)
    if ok and owner ~= nil and owner ~= 0 then return owner end
    return nil
end
function CFC.objectFarm(obj)
    if obj ~= nil and obj.getOwnerFarmId ~= nil then
        local ok, f = true, obj.getOwnerFarmId(obj)
        if ok and f ~= nil and f ~= 0 then return f end
    end
    return nil
end
function CFC.forMe(farmId)
    if CFAMP ~= nil then return CFAMP.forMe(farmId) end
    return true
end
function CFC.visibleNotices()
    local list = {}
    for _, n in ipairs(CFC.notices) do
        if CFC.forMe(n.farm) then list[#list + 1] = n end
    end
    return list
end

function CFC.addNotice(kind, msg, farmId)
    if CFAMP ~= nil and CFAMP.isClientOnly() then   -- a player's game: notices come from the host
        if CFC.forMe(farmId) then CFC.showPopup(kind, msg) end
        return
    end
    farmId = farmId or CFC.noticeFarm
    local date = CFC.dateText()
    CFC.noticeSeq = CFC.noticeSeq + 1
    table.insert(CFC.notices, 1, {id = CFC.noticeSeq, date = date, text = msg, kind = kind, farm = farmId})
    while #CFC.notices > CFC.MAX_NOTICES do
        table.remove(CFC.notices)
    end
    log("notice (%s%s): %s %s", kind, farmId ~= nil and (", farm " .. tostring(farmId)) or "", date, msg)
    if not CFC.forMe(farmId) then return end   -- another farm's: kept for that farm, not shown here
    CFC.unread = CFC.unread + 1
    CFC.notifyLocal(kind, msg)
end

-- a notice the host sent to this player's game
function CFC.receiveNotice(n)
    if n == nil or not CFC.forMe(n.farm) then return end
    CFC.unread = CFC.unread + 1
    CFC.notifyLocal(n.kind or "info", n.text or "")
end

function CFC.notifyLocal(kind, msg)
    local mode = CFC.settings.noticeMode or "popup"
    if mode == "menu" then
        return   -- v0.21.5: menu only - kept for the Notifications tab, no pop-up
    end
    if mode == "summary" and kind ~= "warning" then
        CFC.pending = CFC.pending or {}
        table.insert(CFC.pending, msg)   -- shown in one message at the next game hour
        return
    end
    CFC.showPopup(kind, msg)
end

function CFC.showPopup(kind, msg)
    local mission = g_currentMission
    if mission == nil then return end
    local color = FSBaseMission.INGAME_NOTIFICATION_INFO
    if kind == "ok" then
        color = FSBaseMission.INGAME_NOTIFICATION_OK
    elseif kind == "warning" then
        color = FSBaseMission.INGAME_NOTIFICATION_CRITICAL
    end
    -- v0.23 (team: rain warning in the log but not on screen): the game's own in-game notification first - the call other
    -- FS25 mods use for warnings (addIngameNotification with INGAME_NOTIFICATION_CRITICAL) - then the side notification.
    -- Any failure is written to the log instead of being silently dropped.
    local shown = false
    if kind ~= "warning" and mission.hud ~= nil and mission.hud.addSideNotification ~= nil then   -- info / ok: unchanged path (works)
        local ok, err = true, mission.hud.addSideNotification(mission.hud, color or {1, 1, 1, 1}, msg, (CFC.settings.popupSec or 10) * 1000)
        if ok then shown = true else log("pop-up failed (addSideNotification): %s", tostring(err)) end
    end
    if not shown and mission.addIngameNotification ~= nil and color ~= nil then
        local ok, err = true, mission.addIngameNotification(mission, color, msg)
        if ok then shown = true else log("pop-up failed (addIngameNotification): %s", tostring(err)) end
    end
    if not shown and mission.hud ~= nil and mission.hud.addSideNotification ~= nil then
        local ok, err = true, mission.hud.addSideNotification(mission.hud, color or {1, 1, 1, 1}, msg, (CFC.settings.popupSec or 10) * 1000)
        if ok then shown = true else log("pop-up failed (addSideNotification): %s", tostring(err)) end
    end
    if kind == "warning" and mission.showBlinkingWarning ~= nil then
        local ok, err = true, mission.showBlinkingWarning(mission, msg, (CFC.settings.popupSec or 10) * 1000)
        if ok then shown = true else log("pop-up failed (showBlinkingWarning): %s", tostring(err)) end
    end
    if not shown then log("pop-up not shown (no notification call worked): %s", msg) end
end

-- v0.30.1 (team 2026-11-21: a "pick your weather station" warning made at load reached the screen 24 minutes later,
-- after the station was confirmed): the game shows its in-game notifications one at a time from a queue, so a warning
-- can wait behind other mods' notices. This removes our own not-yet-shown messages that start with a given text from
-- any notification queue under the HUD. Only tables of messages are touched; a failure is logged, never raised.
function CFC.purgeQueuedNotices(prefix)
    local mission = g_currentMission
    if mission == nil or mission.hud == nil or prefix == nil then return 0 end
    local removed, seen = 0, {}
    local function msgText(e)
        if type(e) == "string" then return e end
        if type(e) ~= "table" then return nil end
        local t = e.text or e.message or e.msg or e[1]
        if type(t) == "string" then return t end
        return nil
    end
    local function walk(t, depth)
        if type(t) ~= "table" or seen[t] or depth > 4 then return end
        seen[t] = true
        if #t > 0 then
            for i = #t, 1, -1 do
                local m = msgText(t[i])
                if m ~= nil and m:sub(1, #prefix) == prefix then
                    table.remove(t, i)
                    removed = removed + 1
                end
            end
        end
        for k, v in pairs(t) do
            if type(v) == "table" and type(k) ~= "number" and k ~= "parent" and k ~= "target" and k ~= "mission" then
                walk(v, depth + 1)
            end
        end
    end
    local ok, err = true, walk(mission.hud, 0)
    if not ok then log("purge of queued notices failed: %s", tostring(err)) end
    if removed > 0 then log("removed %d queued notice(s) that were out of date: %s...", removed, prefix) end
    return removed
end

-- v0.21.5 summary mode: once per game hour, one message for everything that came in
function CFC.flushSummary()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env == nil then return end
    local hour = (env.currentMonotonicDay or 0) * 24 + (env.currentHour or 0)
    if CFC.summaryHour == hour then return end
    CFC.summaryHour = hour
    local p = CFC.pending
    if p == nil or #p == 0 then return end
    CFC.pending = {}
    local msg
    if #p == 1 then
        msg = p[1]
    else
        msg = string.format("%d %s - %s (%s)", #p, text("cfc_summary_new", "new Field Almanac notices"), p[#p], text("cfc_summary_see", "see ESC"))
    end
    CFC.showPopup("info", msg)
end

function CFC.checkFieldNotices(sums)
    sums = sums or CFC.getFieldSummaries()
    CFC.fieldNotice = CFC.fieldNotice or {}
    for id, s in pairs(sums) do
      if not CFC.isTiny(s) then
        local readyText, pct = CFC.getReadyText(s)
        local bucket = math.floor(pct / CFC.NOTICE_STEP) * CFC.NOTICE_STEP
        local prev = CFC.fieldNotice[id]
        local env = g_currentMission ~= nil and g_currentMission.environment or nil
        local nowH = env ~= nil and ((env.currentMonotonicDay or 0) * 24 + (env.dayTime or 0) / 3600000) or 0
        CFC.noticeFarm = CFC.farmlandFarm(id)   -- v0.30: hay notices go to the farm that owns the farmland
        if prev == nil then
            -- first look (load / fresh cut): no pop-up
            CFC.fieldNotice[id] = {bucket = bucket, said = bucket, rewet = s.rewet, rained = s.rained, meanM = s.meanM}
        else
            -- v0.21.4: rain on this patch inside the same rain event does not warn again
            local sameRain = prev.lastRainH ~= nil and (nowH - prev.lastRainH) < CFC.RAIN_EVENT_GAP_HOURS
            if s.newRain > 0 then
                if not sameRain then prev.rainWarned, prev.rewetWarned, prev.readySaid, prev.said = false, false, false, 0 end
                prev.lastRainH = nowH
            end
            local label = CFC.getFieldLabel(id, s)
            if s.newRain > 0 and not prev.rainWarned then
                prev.rainWarned = true
                CFC.rainAlert[id] = true   -- v0.23.3: also a line in the Field Cure box that stays until read or dry (team)
                -- v0.17: rain or snow on curing grass or hay -> red warning (team)
                CFC.addNotice("warning", string.format("%s: %s (%s %.0f %%)", label,
                    text("cfc_notice_soaked", "rain on curing hay - soaking"), text("cfc_was", "was"), (prev.meanM or s.meanM) * 100))
            elseif bucket > prev.bucket and bucket > (prev.said or prev.bucket) then
                prev.said = bucket   -- v0.21.4: each 10 % step once per drying, not again after every shower
                if bucket >= 100 and prev.readySaid then
                    -- already said "ready" since the last rain: no repeat
                elseif bucket >= 100 then
                    prev.readySaid = true
                    CFC.addNotice("ok", string.format("%s: %s - %s (100 %%)", label,
                        text("cfc_notice_ready", "hay ready to bale"), formatHa(s.total * CFC.CELL_SIZE * CFC.CELL_SIZE / 10000)))
                else
                    CFC.addNotice("info", string.format("%s: %s %s", label, text("cfc_notice_progress", "hay ready"), readyText))
                end
            elseif s.rewet and not prev.rewet and not prev.rewetWarned then
                prev.rewetWarned = true
                -- v0.21.10 (team): one red warning per rain - this follow-up is a plain notice
                CFC.addNotice(prev.rainWarned and "info" or "warning", string.format("%s: %s", label, text("cfc_notice_rained", "rained on - hay back to wet grass")))
            end
            prev.bucket = bucket
            prev.rewet = s.rewet
            prev.rained = s.rained
            prev.meanM = s.meanM
        end
      end
    end
    CFC.noticeFarm = nil
    for id in pairs(CFC.fieldNotice) do
        if sums[id] == nil then CFC.fieldNotice[id] = nil end
    end
    -- v0.23.3: the box line goes when that hay is baled away or back to 100 % hay
    for id in pairs(CFC.rainAlert) do
        local s = sums[id]
        if s == nil or s.total == nil or s.total <= 0 or s.hay >= s.total then CFC.rainAlert[id] = nil end
    end
    CFC.updateHotspots(sums)
end

-- v0.17 map icons (team design): hay pile = cut and curing, bale = 100 % hay and ready, raindrop = rained on.
CFCHotspot = {}
local CFCHotspot_mt = Class(CFCHotspot, MapHotspot)
CFC.ICON_FILES = {curing = "icons/cfc_curing.dds", ready = "icons/cfc_ready.dds", rained = "icons/cfc_rained.dds"}

function CFCHotspot.new()
    local self = MapHotspot.new(CFCHotspot_mt)
    self.width, self.height = getNormalizedScreenValues(44, 44)
    self.cfcState = nil
    -- v0.21.10: no click area - the map's popup for a mod icon came up empty (team screenshots)
    return self
end


function CFCHotspot:getCategory()
    return MapHotspot.CATEGORY_OTHER
end

function CFCHotspot:getName()
    return self.cfcName
end

function CFCHotspot:setCfcState(state, name, x, z)
    self.cfcName = name
    self.cfcX, self.cfcZ = x, z
    self:setWorldPosition(x, z)
    if state ~= self.cfcState then
        if self.icon ~= nil then
            self.icon:delete()
        end
        self.icon = Overlay.new(Utils.getFilename(CFC.ICON_FILES[state], CFC.MOD_DIR), 0, 0, self.width, self.height)
        self.cfcState = state
        self.scale = nil   -- v0.21.4: the map scales an icon only when the scale changes - make it scale the new picture (team: icon grew)
    end
end

CFC.hotspots = {}

function CFC.removeHotspot(id)
    local h = CFC.hotspots[id]
    if h ~= nil then
        if g_currentMission ~= nil then
            g_currentMission:removeMapHotspot(h)
        end
        h:delete()
        CFC.hotspots[id] = nil
    end
end

function CFC.updateHotspots(sums)
    if CFC.hotspotsBroken or g_currentMission == nil or g_currentMission.addMapHotspot == nil then return end
    local ok, err = true, (function()
        for id, s in pairs(sums) do
          if CFC.isTiny(s) then
            CFC.removeHotspot(id)
          else
            local state = "curing"
            if s.rained then
                state = "rained"
            elseif s.hay >= s.total then
                state = "ready"
            end
            local ha = s.total * CFC.CELL_SIZE * CFC.CELL_SIZE / 10000
            local name = string.format("%s - %s - %s", CFC.getFieldLabel(id, s), CFC.getFieldStatus(s), formatHa(ha))
            local h = CFC.hotspots[id]
            if h == nil then
                h = CFCHotspot.new()
                CFC.hotspots[id] = h
                h:setCfcState(state, name, s.x, s.z)
                g_currentMission:addMapHotspot(h)
            else
                h:setCfcState(state, name, s.x, s.z)
            end
          end
        end
        for id in pairs(CFC.hotspots) do
            if sums[id] == nil then CFC.removeHotspot(id) end
        end
    end)()
    if not ok then
        CFC.hotspotsBroken = true
        Logging.error("[CarolinaFieldCure] map icons turned off: %s", tostring(err))
    end
end

function CFC:consoleNotices()
    local list = CFC.visibleNotices()
    if #list == 0 then
        return "No Field Cure notices yet"
    end
    local lines = {}
    for i = math.min(#list, 30), 1, -1 do
        local n = list[i]
        lines[#lines + 1] = string.format("%s%s  %s", i <= CFC.unread and "* " or "  ", n.date, n.text)
    end
    CFC.unread = 0
    return table.concat(lines, "\n") .. string.format("\n%d notices (newest last, * = was new)", #list)
end

-- v0.17: "you missed something" line (team). Read them with the console command cfaNotices until the Field Almanac menu page has its Notifications tab.
-- v0.23.3 (team: the rain pop-up never showed on screen even though the code called it): a rain line in the Field Cure box
-- that stays until the Field Almanac notices are opened, or that hay is baled / back to 100 % hay.
CFC.rainAlert = {}
function CFC.addNoticeLine(box)
    local ids = {}
    for id in pairs(CFC.rainAlert) do
        if CFC.forMe(CFC.farmlandFarm(id)) then ids[#ids + 1] = id end   -- v0.30: my farm's (or no one's) farmland
    end
    if #ids > 0 then
        table.sort(ids)
        local names = {}
        for _, id in ipairs(ids) do names[#names + 1] = tostring(id) end
        box:addLine(text("cfc_hud_rain", "(!) RAIN on curing hay"), text("cfc_farmland", "Farmland") .. " " .. table.concat(names, ", "))
    end
    if CFACrops ~= nil and (CFACrops.active or (CFACrops.clientMode and CFACrops.hostActive)) and not CFACrops.stationConfirmed then
        box:addLine(text("cfc_hud_station", "(!) Weather station"), text("cfc_hud_station_how", "pick it - ESC > Settings"))
    end
    if CFC.unread > 0 then
        box:addLine(text("cfc_hud_notices", "(!) New notices"), string.format("%d - %s", CFC.unread, text("cfc_hud_notices_how", "see Field Almanac (ESC)")))
    end
end

function CFC.updateHud(hudUpdater)
    if not CFC.started or g_localPlayer == nil or g_currentMission == nil or g_currentMission.hud == nil then
        return
    end
    if hudUpdater ~= nil and g_localPlayer ~= hudUpdater.player and hudUpdater.player ~= nil then
        return
    end
    local now = g_time or 0
    if CFC.hudNext ~= nil and now < CFC.hudNext then
        if CFC.hudBox ~= nil and CFC.hudVisible then
            CFC.hudBox:showNextFrame()
        end
        return
    end
    CFC.hudNext = now + CFC.HUD_REFRESH
    CFC.hudVisible = false

    -- v0.21.4 (team): the box also shows from a vehicle (mowing, raking, baling) - read the vehicle's position
    local x, z
    local vehicle = g_localPlayer:getCurrentVehicle()
    -- v0.21.10 (team: box not showing in the tractor): the game does not draw its info boxes while driving, so in a vehicle the
    -- same lines go to CFA's own small panel (CFC:draw), on foot to the game's box as before.
    if vehicle ~= nil then
        if CFC.hudBox ~= nil and CFC.hudBox ~= CFC.vehBox then CFC.realBox = CFC.hudBox end
        CFC.hudBox = CFC.vehBox
    elseif CFC.hudBox == CFC.vehBox then
        CFC.hudBox = CFC.realBox
    end
    if vehicle ~= nil then
        if vehicle.rootNode == nil then return end
        local vx, _, vz = getWorldTranslation(vehicle.rootNode)
        x, z = vx, vz
    else
        local px, _, pz = g_localPlayer:getPosition()
        x, z = px, pz
    end
    if x == nil then
        return
    end
    -- v0.15: anywhere in a field that has hay curing -> whole-field summary
    if g_farmlandManager ~= nil and g_farmlandManager.getFarmlandIdAtWorldPosition ~= nil then
        local fid = g_farmlandManager:getFarmlandIdAtWorldPosition(x, z)
        local sum = fid ~= nil and fid > 0 and CFC.hudSummaries()[fid] or nil
        -- v1.0.3 (team yes 2026-11-23): the farmland summary shows only on or near the cut hay itself (within NEAR_CUT_M),
        -- not anywhere on a large farmland. Missed notices and the rain line still show everywhere (below).
        if sum ~= nil and not CFC.nearCut(x, z, fid) then sum = nil end
        if sum ~= nil then
            if CFC.hudBox == nil then
                CFC.hudBox = g_currentMission.hud.infoDisplay:createBox(InfoDisplayKeyValueBox)
            end
            local box = CFC.hudBox
            box:clear()
            box:setTitle(text("cfc_hud_title", "Field Cure"))
            CFC.addNoticeLine(box)
            box:addLine(CFC.getFieldLabel(fid, sum), CFC.getFieldStatus(sum))
            box:addLine(text("cfc_hud_ready", "Hay ready"), (CFC.getReadyText(sum)))
            box:addLine(text("cfc_hud_range", "Driest / wettest"),
                string.format("%.0f %% / %.0f %%", sum.minM * 100, sum.maxM * 100))
            box:addLine(text("cfc_hud_target", "Hay at"), string.format("%.0f %%", CFC.HAY_MOISTURE * 100))
            local w = CFC.lastWeather
            if w ~= nil and w.humidity ~= nil and w.humidity > 0 then
                box:addLine(text("cfc_hud_humidity", "Air humidity"), string.format("%.0f %%", w.humidity))
            end
            box:showNextFrame()
            CFC.hudVisible = true
            return
        end
    end

    local s = CFC.CELL_SIZE
    local gx, gz = math.floor(x / s), math.floor(z / s)
    local cell = CFC.cells[CFC.getCellKey(gx, gz)]
    if cell == nil then
        local best = nil
        local bestDist = math.huge
        for ox = -1, 1 do
            for oz = -1, 1 do
                local c = CFC.cells[CFC.getCellKey(gx + ox, gz + oz)]
                if c ~= nil then
                    local dx = (c.gx + 0.5) * s - x
                    local dz = (c.gz + 0.5) * s - z
                    local d = dx * dx + dz * dz
                    if d < bestDist then
                        best, bestDist = c, d
                    end
                end
            end
        end
        cell = best
    end
    if cell == nil then
        -- v0.17: missed notices still show, anywhere on foot (v0.23.3: and the rain line)
        if CFC.unread > 0 or next(CFC.rainAlert) ~= nil then
            if CFC.hudBox == nil then
                CFC.hudBox = g_currentMission.hud.infoDisplay:createBox(InfoDisplayKeyValueBox)
            end
            CFC.hudBox:clear()
            CFC.hudBox:setTitle(text("cfc_hud_title", "Field Cure"))
            CFC.addNoticeLine(CFC.hudBox)
            CFC.hudBox:showNextFrame()
            CFC.hudVisible = true
        end
        return
    end
    if CFC.hudBox == nil then
        CFC.hudBox = g_currentMission.hud.infoDisplay:createBox(InfoDisplayKeyValueBox)
    end
    local box = CFC.hudBox
    box:clear()
    box:setTitle(text("cfc_hud_title", "Field Cure"))
    CFC.addNoticeLine(box)
    box:addLine(text("cfc_hud_moisture", "Moisture"), string.format("%.0f %%", cell.m * 100))
    box:addLine(text("cfc_hud_target", "Hay at"), string.format("%.0f %%", CFC.HAY_MOISTURE * 100))
    box:addLine(text("cfc_hud_status", "Status"), CFC.getStatusText(cell))
    local w = CFC.lastWeather
    if w ~= nil and w.humidity ~= nil and w.humidity > 0 then
        box:addLine(text("cfc_hud_humidity", "Air humidity"), string.format("%.0f %%", w.humidity))
    end
    box:showNextFrame()
    CFC.hudVisible = true
end

PlayerHUDUpdater.update = Utils.appendedFunction(PlayerHUDUpdater.update, CFC.updateHud)

addModEventListener(CFC)

-- ---------------------------------------------------------------- v0.23.1 map "Field Info" row (team)
-- The map's Field Info box shows the STANDING crop ("Growth: Ready to harvest" = regrowth) while cut hay lies curing on top.
-- Base-game calls found with the v0.23.0.3 probe (laptop log 2026-11-05 21:24): InGameMenuMapFrame:clearFieldInfoBox(), then
-- InGameMenuMapFrame:addFieldInfoKeyValue(key, value) once per row; first row = Farmland (value = farmland id).
-- v0.23.2: the game's texts are not readable by key (laptop log 22:32: "0 growth labels"), so the Growth row is found as the row
-- right after the Crop type row (value = the crop's fill type title). The crop and stage are read fresh at the field marker
-- (the game's stored field state is stale after the player works a field - CFACrops v0.16.1 note).
--   Growth row: + " (50 % yield)" / " (100 % yield)" from desc.yieldScales[state] (FruitTypeDesc reads each isHarvestReady
--   foliageState's #yieldScale: base grass.xml / map alfalfa.xml greenMiddle 0.5, harvestReady 1.0), or " (now: cut)" /
--   " (now: regrowing)".  Then the hay row: "Hay (Curing)  1 ac of 2.4 ac (42 %)".
CFC.mapBox = {}

local function mapBoxReset()
    CFC.mapBox = {n = 0, fid = nil, added = false, cropRow = nil, cropTitle = nil, desc = nil, gs = nil}
end
mapBoxReset()

function CFC.mapFieldInfo(fid)
    if g_fieldManager == nil or CFACrops == nil or CFACrops.fieldStateOf == nil or g_fruitTypeManager == nil then return nil end
    -- v0.23.3: match the farmland by field.farmland.id or by the fresh FieldState.farmlandId (FieldState.new has farmlandId;
    -- the v0.23.2 test showed no stage, so field.farmland is probably not set on these fields)
    local found, why = nil, "no field on this farmland"
    for _, field in pairs(g_fieldManager.fields or {}) do
        local direct = field.farmland ~= nil and field.farmland.id == fid
        local st = nil
        if direct or field.farmland == nil then
            st = CFACrops.fieldStateOf(field)
        end
        if direct or (st ~= nil and st.farmlandId == fid) then
            found = field
            if st == nil or st.fruitTypeIndex == nil or st.fruitTypeIndex == 0 then
                why = "field has no crop"
                break
            end
            local desc = g_fruitTypeManager:getFruitTypeByIndex(st.fruitTypeIndex)
            if desc == nil then why = "crop not known" break end
            local title = desc.fillType ~= nil and desc.fillType.title or nil
            CFC.mapDiag(fid, string.format("crop %s, title '%s', stage %s, yield %s", tostring(desc.name), tostring(title),
                tostring(st.growthState), tostring(desc.yieldScales ~= nil and desc.yieldScales[st.growthState] or "-")))
            return desc, st.growthState, title
        end
    end
    CFC.mapDiag(fid, why)
    return nil
end

-- v0.23.3: one log line per farmland per session, so the next test shows what the map box found
CFC.mapDiagDone = {}
function CFC.mapDiag(fid, msg)
    if CFC.mapDiagDone[fid] then return end
    CFC.mapDiagDone[fid] = true
    log("map Field Info: farmland %s - %s", tostring(fid), msg)
end

function CFC.mapStageText(desc, gs)
    if desc == nil or gs == nil then return nil end
    local scale = desc.yieldScales ~= nil and desc.yieldScales[gs] or nil
    if scale ~= nil then
        return string.format(" (%d %% %s)", math.floor(scale * 100 + 0.5), text("cfc_mapYield", "yield"))
    end
    if desc.cutStates ~= nil and desc.cutStates[gs] then
        return " (" .. text("cfc_mapNowCut", "now: cut") .. ")"
    end
    if desc.getIsGrowing ~= nil then
        local ok, growing = true, desc.getIsGrowing(desc, gs)
        if ok and growing then return " (" .. text("cfc_mapNowGrowing", "now: regrowing") .. ")" end
    end
    return nil
end

function CFC.mapHayRow(fid)
    local s = CFC.hudSummaries()[fid]
    if s == nil or s.total == nil or s.total <= 0 or CFC.isTiny(s) then return nil end
    local key = string.format("%s (%s)", text("cfc_mapHay", "Hay"), CFC.getFieldStatus(s))
    return key, (CFC.getReadyText(s))
end

if InGameMenuMapFrame ~= nil and InGameMenuMapFrame.addFieldInfoKeyValue ~= nil and InGameMenuMapFrame.clearFieldInfoBox ~= nil then
    InGameMenuMapFrame.clearFieldInfoBox = Utils.appendedFunction(InGameMenuMapFrame.clearFieldInfoBox, function()
        mapBoxReset()
    end)
    InGameMenuMapFrame.addFieldInfoKeyValue = Utils.overwrittenFunction(InGameMenuMapFrame.addFieldInfoKeyValue, CFC.profHook("map box",
        function(frame, superFunc, key, value, ...)
            local b = CFC.mapBox
            local isGrowthRow = false
            local ok0, err0 = true, (function()
                b.n = b.n + 1
                if b.fid == nil and b.n <= 2 and value ~= nil then
                    b.fid = tonumber(value)
                    if b.fid ~= nil then
                        b.desc, b.gs, b.cropTitle = CFC.mapFieldInfo(b.fid)
                    end
                elseif b.fid ~= nil and b.cropRow == nil and b.cropTitle ~= nil and value == b.cropTitle then
                    b.cropRow = b.n
                elseif b.fid ~= nil and b.cropRow == nil and b.n == 3 and b.cropTitle ~= nil then
                    CFC.mapDiag(-b.fid, string.format("row 3 is '%s' = '%s', crop title '%s' did not match", tostring(key), tostring(value), b.cropTitle))
                elseif b.cropRow ~= nil and b.n == b.cropRow + 1 then
                    isGrowthRow = true
                end
            end)()
            if isGrowthRow and type(value) == "string" then
                local okS, suffix = true, CFC.mapStageText(b.desc, b.gs)
                if okS and suffix ~= nil then value = value .. suffix end
            end
            superFunc(frame, key, value, ...)
            local ok, err = true, (function()
                if b.added or b.fid == nil then return end
                -- hay row right under Growth; with no crop on the field, right under Farmland
                -- (fallback if the crop title was not matched: after the 4th row = Farmland, Owned by, Crop type, Growth)
                if isGrowthRow or (b.n == 1 and b.desc == nil) or (b.n == 4 and b.cropRow == nil) then
                    b.added = true
                    local k, v = CFC.mapHayRow(b.fid)
                    if k ~= nil then superFunc(frame, k, v) end
                end
            end)()
            if (not ok or not ok0) and not CFC.mapRowErrLogged then
                CFC.mapRowErrLogged = true
                Logging.error("[CarolinaFieldCure] map Field Info row: %s", tostring(err or err0))
            end
        end))
else
    log("map Field Info row off: InGameMenuMapFrame.addFieldInfoKeyValue not found")
end


-- ---------------------------------------------------------------- v0.24 bale storage loss by baling moisture (team)
-- v0.25.1 (team pick 2026-11-06): IFSM Reference Manual (Rotz et al., USDA-ARS) ch. 7 "Hay storage", Buckmaster et al. 1989b:
--   Eq 7.1 bale density D = 100 + 440 Mo (kg/m3)
--   Eq 7.2 heat Q = 104 Mo^2.18 D^0.5 + 5.72 Mo^1.23 D^0.94 (kJ/kg DM)
--   Eq 7.3 first-month DM loss = [Q + 2433 (Mo - Mf (1-Mo)/(1-Mf))] / [(1-Mo)(14206 - 2433 Mf/(1-Mf))], Mf = 0.12
--   Eq 7.4 after the first month: +0.3 % of DM per month.
--   First month: 12 % 0.5, 15 % 1.5, 18 % 2.6, 20 % 3.4, 25 % 5.7, 30 % 8.6 %. Never below 0.
--   (Was UC Orloff, 1 point per point over 10 % + 0.5 %/month, in v0.24.0. The gentler IFSM was picked because every other
--   hay loss in the mod is already the high end.)
-- Game: the first-month loss is spread evenly over one game month (one period), then 0.3 % per game month.
-- Only hay bales (the dry fill type of a curing pair) whose moisture the mod knows (picked up from curing cells).
-- Wrapped bales stop losing (wrapped = baleage, not dry hay storage).
CFC.BALE_MF = 0.12              -- IFSM Eq 7.3 final moisture
CFC.UNCURED_MAX_M = 0.34        -- v0.25.11: un-cured bales up to this moisture get the hay losses (Wilcke et al. 1999 top band 25-34 %)
CFC.BALE_AFTER_PER_MONTH = 0.003   -- IFSM Eq 7.4
CFC.wetBales = {}

function CFC.isHayFillType(ft)
    for _, p in ipairs(CFC.pairs or {}) do
        if p.dst == ft then return true end
    end
    return false
end

-- v0.25.1 baler losses - Rotz 1995 Trans. ASAE 38(6), "Baling and chopping" (team 2026-11-06: keep as the paper gives it):
--   Eq 12 pickup:  Lp = 0.003 / (m Ds)          (m wet-basis moisture, Ds windrow density kg DM/m2)
--   Eq 14 chamber: Lb = 0.0025 fb m^-1.2        fb: 1.0 small rectangular (day), 0.5 small rectangular (night),
--                  0.5 midsize rectangular, 1.0 variable-chamber round, 2.5 fixed-chamber round.
--   The paper: total baler loss typically 2-5 % of yield (Fig. 6, 10-35 % moisture).
--   Game: round baler with more than one bale diameter = variable chamber, one diameter = fixed chamber;
--   square bales 0.8 m wide or wider = midsize (the paper has no large-square factor; midsize is the nearest);
--   night = the game's sun is down. m held to 0.10 or more (the paper's data start at 10 %), Ds to 0.2-2.0 as for the rake.
CFC.PICKUP_K = 0.003
CFC.CHAMBER_K = 0.0025
CFC.SQUARE_MIDSIZE_W = 0.8
-- v0.25.7 (team 2026-11-07): Eq 12's Ds is the density of the crop "laying in the swath or windrow" (Rotz 1995 p. 1628),
-- not the 4 m cell average. Windrow width = the baler's own pickup width: K-State MF2834, "The ideal windrow width for
-- round balers is between one-half and near full width of the baler pickup" - high end (Rule #1) = full pickup width.
-- Ds windrow = cell Ds x cell width / pickup width (only when the pickup is narrower than a cell; never lowers Ds).
-- No readable pickup width = the cell average as before.
function CFC.pickupWidth(sx, sz, wx, wz)
    if sx == nil or wx == nil then return nil end
    local w = math.sqrt((wx - sx) ^ 2 + (wz - sz) ^ 2)
    if w < 0.1 then return nil end
    return w
end

function CFC.balerFactor(vehicle)
    local spec = vehicle.spec_baler
    if spec == nil or spec.baleTypes == nil then return 1.0, "unknown baler" end
    local bt = spec.baleTypes[spec.currentBaleTypeIndex or 1] or spec.baleTypes[1]
    if bt == nil then return 1.0, "unknown baler" end
    if bt.isRoundBale then
        local seen, n = {}, 0
        for _, t in ipairs(spec.baleTypes) do
            if t.isRoundBale and t.diameter ~= nil and not seen[t.diameter] then seen[t.diameter] = true; n = n + 1 end
        end
        if n > 1 then return 1.0, "variable-chamber round" end
        return 2.5, "fixed-chamber round"
    end
    if (bt.width or 0) >= CFC.SQUARE_MIDSIZE_W then return 0.5, "midsize/large square" end
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env ~= nil and env.isSunOn == false then return 0.5, "small square at night" end
    return 1.0, "small square"
end

function CFC.balerLossFractions(m, ds, fb)
    m = math.max(0.10, math.min(0.90, m))
    ds = math.max(0.2, math.min(2.0, ds or CFC.SD_TYPICAL / 1000))
    return CFC.PICKUP_K / (m * ds), CFC.CHAMBER_K * fb * m ^ -1.2
end

-- pickup: remember the moisture of what this baler picks up (liters-weighted), and the pickup + chamber loss
if Baler ~= nil and Baler.processBalerArea ~= nil then
    Baler.processBalerArea = Utils.overwrittenFunction(Baler.processBalerArea, CFC.profHook("baler pickup", function(vehicle, superFunc, workArea, dt)
        local m, ds = nil, nil
        if vehicle.isServer and CFC.started then
            local sx, sz, wx, wz, hx, hz = CFC.getNodeArea(workArea)
            if sx ~= nil then
                m = CFC.getAverageMoisture(sx, sz, wx, wz, hx, hz)
                if m ~= nil then
                    local sum, n = 0, 0
                    for _, c in ipairs(CFC.getCellsForArea(sx, sz, wx, wz, hx, hz)) do
                        local cell = CFC.cells[CFC.getCellKey(c.gx, c.gz)]
                        if cell ~= nil then sum = sum + CFC.swathDensity(cell); n = n + 1 end
                    end
                    if n > 0 then
                        ds = sum / n / 1000
                        local pw = CFC.pickupWidth(sx, sz, wx, wz)
                        if pw ~= nil and pw < CFC.CELL_SIZE then
                            ds = ds * CFC.CELL_SIZE / pw
                            vehicle.cfcPickupW = pw
                        end
                    end
                end
            end
        end
        local spec = vehicle.spec_baler
        local before = spec ~= nil and spec.workAreaParameters ~= nil and spec.workAreaParameters.lastPickedUpLiters or 0
        local a, b = superFunc(vehicle, workArea, dt)
        if m ~= nil and spec ~= nil and spec.workAreaParameters ~= nil then
            local picked = (spec.workAreaParameters.lastPickedUpLiters or 0) - before
            if picked > 0 then
                vehicle.cfcBaleL = (vehicle.cfcBaleL or 0) + picked
                vehicle.cfcBaleML = (vehicle.cfcBaleML or 0) + picked * m
                local fb = CFC.balerFactor(vehicle)
                local lp, lb = CFC.balerLossFractions(m, ds, fb)
                vehicle.cfcPickupL = (vehicle.cfcPickupL or 0) + picked * lp
                vehicle.cfcChamberL = (vehicle.cfcChamberL or 0) + picked * lb
                vehicle.cfcBaleDsL = (vehicle.cfcBaleDsL or 0) + picked * math.max(0.2, math.min(2.0, ds or CFC.SD_TYPICAL / 1000))
            end
        end
        return a, b
    end))
end

-- bale made: tag it with the moisture of what went into it
if Baler ~= nil and Baler.createBale ~= nil then
    Baler.createBale = Utils.overwrittenFunction(Baler.createBale, CFC.profHook("bale made", function(vehicle, superFunc, baleFillType, fillLevel, baleServerId, baleTime, xmlFilename, ownerFarmId, variationId, loadFromSavegame, ...)
        local r1, r2 = superFunc(vehicle, baleFillType, fillLevel, baleServerId, baleTime, xmlFilename, ownerFarmId, variationId, loadFromSavegame, ...)
        CFC.noticeFarm = ownerFarmId or CFC.objectFarm(vehicle)   -- v0.30: bale notices go to the baler's farm
        local ok, err = true, (function()
            if loadFromSavegame or not vehicle.isServer then return end
            local liters, ml = vehicle.cfcBaleL or 0, vehicle.cfcBaleML or 0
            local pickL, chamL = vehicle.cfcPickupL or 0, vehicle.cfcChamberL or 0
            local dsL = vehicle.cfcBaleDsL or 0
            vehicle.cfcBaleL, vehicle.cfcBaleML, vehicle.cfcPickupL, vehicle.cfcChamberL, vehicle.cfcBaleDsL = 0, 0, 0, 0, 0
            local uncured = liters > 0 and not CFC.isHayFillType(baleFillType) and CFC.srcSet ~= nil and CFC.srcSet[baleFillType]
            if uncured then
                -- v0.25.6 check / v0.25.11 rule (team 2026-11-09, "do what the numbers say"):
                -- a wet grass bale does not dry into hay. Up to 34 % moisture it is stored like (tough) hay, so the hay
                -- losses apply (Wilcke, Cuomo & Fox 1999 measured storage loss to 34 %; IFSM storage model).
                -- Above 34 % no source gives an unwrapped loss: no effect - wrap it for baleage (UMN: 40-55 %, wrap
                -- within 24 h; UGA B1508: 40-60 %, within 12 h), which the game already turns into silage.
                local nm = g_fillTypeManager ~= nil and g_fillTypeManager:getFillTypeNameByIndex(baleFillType) or tostring(baleFillType)
                local mPct = 100 * ml / liters
                if ml / liters > CFC.UNCURED_MAX_M then
                    log("bale made from un-cured %s (not hay) at %.0f %% moisture (%.0f l) - too wet to store as hay; wrap it within 24 h for baleage (UMN Extension 40-55 %%)", tostring(nm), mPct, fillLevel or 0)
                    CFC.addNotice("warning", string.format(text("cfc_bale_uncured", "Un-cured bale at %.0f %% moisture - wrap it within 24 h (baleage)"), mPct))
                    return
                end
                log("bale made from un-cured %s (not hay) at %.0f %% moisture (%.0f l) - stored like tough hay: hay losses apply", tostring(nm), mPct, fillLevel or 0)
            end
            if liters <= 0 or not (CFC.isHayFillType(baleFillType) or uncured) then return end
            local spec = vehicle.spec_baler
            local bale = spec ~= nil and spec.bales ~= nil and spec.bales[#spec.bales] or nil
            local obj = bale ~= nil and bale.baleObject or nil
            if obj == nil then return end
            -- v0.25.1 Rotz Eq 12 + 14: the share of what went in that was lost at the pickup and in the chamber
            local full = fillLevel
            local lostFrac = math.max(0, math.min(1, (pickL + chamL) / liters))
            if lostFrac > 0 and full ~= nil and full > 0 and obj.setFillLevel ~= nil then
                local lost = full * lostFrac
                full = full - lost
                obj:setFillLevel(full)
                local share = (pickL + chamL) > 0 and pickL / (pickL + chamL) or 0
                CFC.stats.pickupLoss = (CFC.stats.pickupLoss or 0) + lost * share
                CFC.stats.chamberLoss = (CFC.stats.chamberLoss or 0) + lost * (1 - share)
                local _, kind = CFC.balerFactor(vehicle)
                log("baler losses (Rotz 1995 Eq 12+14, %s): pickup %.1f %%, chamber %.1f %% - bale %.0f l -> %.0f l (%.0f %% moisture, windrow %.2f kg DM/m2, pickup %s)",
                    kind, 100 * pickL / liters, 100 * chamL / liters, fillLevel, full, 100 * ml / liters, dsL / liters,
                    vehicle.cfcPickupW ~= nil and string.format("%.2f m", vehicle.cfcPickupW) or "width not read - cell average")
            end
            CFC.trackBale(obj, ml / liters, full)
        end)()
        if not ok and not CFC.baleTagErrLogged then
            CFC.baleTagErrLogged = true
            Logging.error("[CarolinaFieldCure] bale moisture tag: %s", tostring(err))
        end
        CFC.noticeFarm = nil
        return r1, r2
    end))
end

function CFC.trackBale(obj, m, full)
    local uid = obj.getUniqueId ~= nil and obj:getUniqueId() or nil
    local entry = {obj = obj, uid = uid, m = m, full = full or obj.fillLevel or 0, startH = CFC.nowHours()}
    table.insert(CFC.wetBales, entry)
    local pct1 = CFC.baleFirstMonth(m) * 100
    log("bale baled at %.0f %% moisture (%.0f l): storage loss %.1f %% in its first month, then %.1f %% a month (IFSM, Buckmaster 1989b)",
        m * 100, entry.full, pct1, CFC.BALE_AFTER_PER_MONTH * 100)
    if m > 0.20 then
        CFC.addNotice("warning", string.format("%s %.0f %% - %s", text("cfc_bale_wet", "Bale baled at"), m * 100,
            string.format(text("cfc_bale_wet_loss", "about %.0f %% dry matter lost in storage in the first month"), pct1)))
    end
end

-- IFSM Eq 7.1-7.3: fraction of DM lost in the first month for a bale made at moisture Mo (wet basis, 0-1)
function CFC.baleFirstMonth(Mo)
    if Mo == nil or Mo <= 0 or Mo >= 1 then return 0 end
    local Mf = CFC.BALE_MF
    local D = 100 + 440 * Mo
    local Q = 104 * Mo ^ 2.18 * D ^ 0.5 + 5.72 * Mo ^ 1.23 * D ^ 0.94
    local L = (Q + 2433 * (Mo - Mf * (1 - Mo) / (1 - Mf))) / ((1 - Mo) * (14206 - 2433 * Mf / (1 - Mf)))
    return math.max(0, math.min(1, L))
end

-- fraction of the bale's DM lost after `months` game months
function CFC.baleLossAt(m, months)
    local first = CFC.baleFirstMonth(m)
    if months <= 1 then return first * math.max(0, months) end
    return first + CFC.BALE_AFTER_PER_MONTH * (months - 1)
end

function CFC.updateWetBales(tNow, env)
    if #CFC.wetBales == 0 then return end
    local hourKey = math.floor(tNow)
    if CFC.wetBaleHour == hourKey then return end
    CFC.wetBaleHour = hourKey
    local monthH = (env.daysPerPeriod or 1) * 24
    local keep = {}
    for _, e in ipairs(CFC.wetBales) do
        if e.obj == nil and e.uid ~= nil and g_currentMission.getObjectByUniqueId ~= nil then
            e.obj = g_currentMission:getObjectByUniqueId(e.uid)
            e.tries = (e.tries or 0) + 1
        end
        local obj = e.obj
        local alive = obj ~= nil and not obj.isDeleted and obj.nodeId ~= nil and obj.nodeId ~= 0
        if alive then
            local wrapped = obj.wrappingState ~= nil and obj.wrappingState > 0
            if not wrapped and obj.setFillLevel ~= nil then
                local target = e.full * (1 - CFC.baleLossAt(e.m, (tNow - e.startH) / monthH))
                local cur = obj.fillLevel or (obj.getFillLevel ~= nil and obj:getFillLevel()) or e.full
                if target < cur - 0.5 then
                    obj:setFillLevel(math.max(0, target))
                end
            end
            keep[#keep + 1] = e
        elseif obj == nil and (e.tries or 0) < 48 then
            keep[#keep + 1] = e   -- after a load the bale may not be registered yet
        end
    end
    CFC.wetBales = keep
end

function CFC.saveWetBales(xmlFile)
    local n = 0
    for _, e in ipairs(CFC.wetBales) do
        local uid = e.uid or (e.obj ~= nil and e.obj.getUniqueId ~= nil and e.obj:getUniqueId()) or nil
        if uid ~= nil then
            local key = string.format("carolinaFieldCure.bales.bale(%d)", n)
            xmlFile:setString(key .. "#uid", uid)
            xmlFile:setString(key .. "#m", string.format("%.4f", e.m))
            xmlFile:setString(key .. "#full", string.format("%.1f", e.full))
            xmlFile:setString(key .. "#startH", string.format("%.3f", e.startH))
            n = n + 1
        end
    end
end

function CFC.loadWetBales(xmlFile)
    CFC.wetBales = {}
    xmlFile:iterate("carolinaFieldCure.bales.bale", function(_, key)
        local uid = xmlFile:getString(key .. "#uid")
        local m = tonumber(xmlFile:getString(key .. "#m", ""))
        local full = tonumber(xmlFile:getString(key .. "#full", ""))
        local startH = tonumber(xmlFile:getString(key .. "#startH", ""))
        if uid ~= nil and m ~= nil and full ~= nil and startH ~= nil then
            table.insert(CFC.wetBales, {uid = uid, m = m, full = full, startH = startH})
        end
    end)
end
