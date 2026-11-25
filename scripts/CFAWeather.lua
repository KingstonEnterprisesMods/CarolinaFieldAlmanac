-- Carolina Field Almanac - weather part. By Kingston Enterprises. Mod for Farming Simulator.
--
-- Each game day is generated from real NOAA data for the chosen weather station (see CFAStationData.lua):
--   * rain or dry: 2-state Markov chain (chance of rain after a dry day / after a rainy day), carried over by the real days a game day stands for (v0.29.11)
--   * rain amount: gamma distribution
--   * high / low: by wet or dry day, with day-to-day persistence and the station's own high-low link (v0.29.10)
--     (WGEN method, Richardson & Wright 1984, USDA-ARS; fitted to NOAA GHCN-Daily 1991-2020,
--      calibrated to NOAA U.S. Climate Normals 1991-2020)
--   * rain start time and length: NOAA Hourly Precipitation Data
--   * thunder / snow on a rainy day: NOAA GHCN-Daily records
--   * humidity, wind and sky through the day: NOAA hourly climate normals 1991-2020
-- The days are fed into the game's own forecast, so sky, rain, ground wetness,
-- the forecast and other mods all see the same weather.

CFAWeather = {}
local W = CFAWeather

W.DEFAULT_STATION = "USW00013995"      -- Springfield, MO: NOAA station nearest the U.S. 2020 center of population (Census: 37.415725 N, 92.346525 W, near Hartville, MO; 95 km)
W.stationId = W.DEFAULT_STATION
W.DAYS_AHEAD = 12
W.MONTH_DAYS = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
W.SLOTS = 20                            -- per-day temperature slots per weather object (> DAYS_AHEAD + 2)
W.WET_MM = 0.254                        -- NOAA rain day: 0.01 in or more
W.SAVE_FILE = "carolinaFieldAlmanacWeather.xml"
W.CONFLICT_MODS = {"FS25_RealisticWaterSoilManagement", "FS25_MoistureSystem"}
W.STATE_NAMES = {
    AK = "Alaska",
    AL = "Alabama",
    AR = "Arkansas",
    AZ = "Arizona",
    CA = "California",
    CO = "Colorado",
    CT = "Connecticut",
    DE = "Delaware",
    FL = "Florida",
    GA = "Georgia",
    HI = "Hawaii",
    IA = "Iowa",
    ID = "Idaho",
    IL = "Illinois",
    IN = "Indiana",
    KS = "Kansas",
    KY = "Kentucky",
    LA = "Louisiana",
    MA = "Massachusetts",
    MD = "Maryland",
    ME = "Maine",
    MI = "Michigan",
    MN = "Minnesota",
    MO = "Missouri",
    MS = "Mississippi",
    MT = "Montana",
    NC = "North Carolina",
    ND = "North Dakota",
    NE = "Nebraska",
    NH = "New Hampshire",
    NJ = "New Jersey",
    NM = "New Mexico",
    NV = "Nevada",
    NY = "New York",
    OH = "Ohio",
    OK = "Oklahoma",
    OR = "Oregon",
    PA = "Pennsylvania",
    RI = "Rhode Island",
    SC = "South Carolina",
    SD = "South Dakota",
    TN = "Tennessee",
    TX = "Texas",
    UT = "Utah",
    VA = "Virginia",
    VT = "Vermont",
    WA = "Washington",
    WI = "Wisconsin",
    WV = "West Virginia",
    WY = "Wyoming",
    -- v0.26 (team 2026-11-11): Canadian farm provinces (CFAStationDataCA.lua)
    AB = "Alberta",
    MB = "Manitoba",
    ON = "Ontario",
    QC = "Quebec",
    SK = "Saskatchewan",
    -- v0.28 (team 2026-11-14): Europe (CFAStationDataEU.lua) - Poland as one list, Germany by state
    POL = "Poland",
    DEBW = "Baden-Wurttemberg",
    DEBY = "Bavaria",
    DEBE = "Berlin",
    DEBB = "Brandenburg",
    DEHB = "Bremen",
    DEHH = "Hamburg",
    DEHE = "Hesse",
    DEMV = "Mecklenburg-Vorpommern",
    DENI = "Lower Saxony",
    DENW = "North Rhine-Westphalia",
    DERP = "Rhineland-Palatinate",
    DESL = "Saarland",
    DESN = "Saxony",
    DEST = "Saxony-Anhalt",
    DESH = "Schleswig-Holstein",
    DETH = "Thuringia",
    -- v0.28 (team 2026-11-14): UK by nation, Republic of Ireland
    GBENG = "England",
    GBSCT = "Scotland",
    GBWLS = "Wales",
    GBNIR = "Northern Ireland",
    IRL = "Ireland",
    -- v0.28 (team 2026-11-14): France by region
    FRARA = "Auvergne-Rhone-Alpes",
    FRBFC = "Bourgogne-Franche-Comte",
    FRBRE = "Brittany",
    FRCVL = "Centre-Val de Loire",
    FRCOR = "Corsica",
    FRGES = "Grand Est",
    FRHDF = "Hauts-de-France",
    FRIDF = "Ile-de-France",
    FRNOR = "Normandy",
    FRNAQ = "Nouvelle-Aquitaine",
    FROCC = "Occitanie",
    FRPDL = "Pays de la Loire",
    FRPAC = "Provence-Alpes-Cote d'Azur"
}
W.CANADA = {AB = true, MB = true, ON = true, QC = true, SK = true}
-- v0.28: European list entries -> country (for the label and the list order)
W.EUROPE = {POL = "Poland", DEBW = "Germany", DEBY = "Germany", DEBE = "Germany", DEBB = "Germany", DEHB = "Germany", DEHH = "Germany",
    DEHE = "Germany", DEMV = "Germany", DENI = "Germany", DENW = "Germany", DERP = "Germany", DESL = "Germany", DESN = "Germany",
    DEST = "Germany", DESH = "Germany", DETH = "Germany",
    GBENG = "UK", GBSCT = "UK", GBWLS = "UK", GBNIR = "UK", IRL = "Ireland",
    FRARA = "France", FRBFC = "France", FRBRE = "France", FRCVL = "France", FRCOR = "France", FRGES = "France", FRHDF = "France",
    FRIDF = "France", FRNOR = "France", FRNAQ = "France", FROCC = "France", FRPDL = "France", FRPAC = "France"}
-- v0.28: list order - U.S. states, then Canadian provinces, then Europe by country
function W.groupOf(code) return (W.CANADA[code] and 1) or (W.EUROPE[code] ~= nil and 2) or 0 end
function W.sortName(code)
    local c = W.EUROPE[code]
    if c ~= nil then return c .. " " .. (W.STATE_NAMES[code] or code) end
    return W.STATE_NAMES[code] or code
end
function W.listLabel(code)
    local name = W.STATE_NAMES[code] or code
    if W.CANADA[code] then return name .. " (Canada)" end
    local c = W.EUROPE[code]
    if c ~= nil and c ~= name then return name .. " (" .. c .. ")" end
    return name
end
-- v0.26 (team 2026-11-11): maps whose real place is known -> the station the team picked for it (pre-select only; the player confirms).
-- Gnadenthal (southern Manitoba): Marquette, MB - nearest station passing the 1991-2020 completeness rule (110 km; Gretna fails it).
W.MAP_STATIONS = {
    {find = "gnadenthal", id = "CAN05021695", name = "Gnadenthal"},
    -- v0.28 (2026-11-14): ModHub maps whose page names a real village or town in Poland or Germany -> nearest station passing
    -- the 1991-2020 completeness rule (same rule as Gnadenthal). Place from the map's own ModHub description, located with
    -- OpenStreetMap Nominatim. Matched on the map's mod name (e.g. FS25_Kreis_Steinfurt).
    {find = "fs25_adelegg", id = "DE02559", name = "Adelegg"},   -- Adelegg, Germany (13 km)
    {find = "fs25_am_mlk", id = "DE00662", name = "Am Mittellandkanal"},   -- Woltorf, Germany (9 km)
    {find = "fs25_bilk", id = "DE01766", name = "BILK"},   -- Bilk, Germany (30 km)
    {find = "fs25_beuren", id = "DE05100", name = "Beuren"},   -- Beuren, Germany (26 km)
    {find = "fs25_birgland", id = "DE00151", name = "Birgland"},   -- Birgland, Germany (18 km)
    {find = "fs25_dalberg", id = "DE04301", name = "Dalberg"},   -- Dalberg, Germany (11 km)
    {find = "fs25_dedelow", id = "DE01869", name = "Dedelow X4 In GDR"},   -- Dedelow, Germany (10 km)
    {find = "fs25_deppenhausen", id = "DE03402", name = "Deppenhausen"},   -- Ehingen (Donau), Germany (21 km)
    {find = "fs25_drensteinfurt", id = "DE01766", name = "District Of Drensteinfurt"},   -- Drensteinfurt, Germany (38 km)
    {find = "fs25_efcoast", id = "DE03631", name = "East Frisian Coast"},   -- Dornumergrode, Germany (19 km)
    {find = "fs25_guelzow", id = "DE05009", name = "Gülzow"},   -- Gülzow, Germany (21 km)
    {find = "fs25_klattenhof", id = "DE00044", name = "Klattenhof"},   -- Klattenhof, Germany (16 km)
    {find = "fs25_krajowlazniki", id = "PL351160415", name = "Krajow And Lazniki"},   -- Krajów, Poland (13 km)
    {find = "fs25_kreis_steinfurt", id = "DE01766", name = "Kreis Steinfurt"},   -- Landersum, Germany (27 km)
    {find = "fs25_lachem", id = "DE04371", name = "Lachem"},   -- Lachem, Germany (36 km)
    {find = "fs25_muensingeralb", id = "DE03402", name = "Münsinger Alb"},   -- Münsingen, Germany (3 km)
    {find = "fs25_new_bartelshagen", id = "DE00298", name = "New Bartelshagen"},   -- Neu Bartelshagen, Germany (10 km)
    {find = "fs25_nordkirchen", id = "DE01766", name = "Nordkirchen"},   -- Nordkirchen, Germany (46 km)
    {find = "fs25_oberschwaben", id = "DE04094", name = "Oberschwaben"},   -- Bad Waldsee, Germany (16 km)
    {find = "fs25_oedberg", id = "DE02319", name = "Oedberg At The Tegernsee"},   -- Gmund, Germany (15 km)
    {find = "fs25_pfraunstetten", id = "DE02814", name = "Pfraunstetten"},   -- Pfraunstetten, Germany (22 km)
    {find = "fs25_przybiernowko", id = "PL353150210", name = "Przybiernowko"},   -- Przybiernówko, Poland (27 km)
    {find = "fs25_ratzinger_hoehe", id = "DE04261", name = "Ratzinger Height"},   -- Greimharting, Germany (14 km)
    {find = "fs25_saaleplatte", id = "DE02444", name = "Saaleplatte"},   -- Pfuhlsborn, Germany (13 km)
    {find = "fs25_schellenberg", id = "DE04094", name = "Schellenberg"},   -- Bad Waldsee, Germany (16 km)
    {find = "fs25_schwesingbahnhof", id = "DE01266", name = "Schwesing Bahnhof"},   -- Schwesing, Germany (25 km)
    {find = "fs25_somewhere_in_thuringia", id = "DE02444", name = "Somewhere In Thuringia IV Crossplay"},   -- Loßnitz, Germany (13 km)
    {find = "fs25_lehndorf", id = "DE00314", name = "Welcome To Lehndorf"},   -- Lehndorf - Lejno, Germany (19 km)
    {find = "fs25_wolazabierzowska", id = "PL350190566", name = "Wola Zabierzowska"},   -- Wola Zabierzowska, Poland (40 km)
    {find = "fs25_wollschow25", id = "DE01869", name = "Wollschow 25"},   -- Wollschow, Germany (20 km)
    -- v0.28 (team 2026-11-14): UK and Ireland maps (village, town or county town named) -> nearest station passing the rule.
    {find = "fs25_ballamroaddairyfarming", id = "MO01111", name = "Ballam Road Dairy Farming"},   -- Lytham St Annes (20 km)
    {find = "fs25_castlereagh", id = "MO01508", name = "Castlereagh"},   -- Castlereagh, Belfast (1 km)
    {find = "fs25_chadlington", id = "MO00606", name = "Chadlington"},   -- Chadlington, Oxfordshire (23 km)
    {find = "fs25_chipping_norton", id = "MO00606", name = "Chipping Norton"},   -- Chipping Norton (27 km)
    {find = "fs25_drumard", id = "MO01494", name = "Drumard Farm", plantCountry = "IE"},   -- Dundalk (34 km); v0.29.11 (team 2026-11-16): farm is in Ireland (Co. Louth) -> Irish planting dates
    {find = "fs25_drumard_extended", id = "MO01494", name = "Drumard Farm Extended", plantCountry = "IE"},   -- Dundalk (34 km); v0.29.11 (team 2026-11-16): farm is in Ireland (Co. Louth) -> Irish planting dates
    {find = "fs25_fieldsoftyrone", id = "MO01551", name = "Fields Of Tyrone"},   -- Omagh (1 km)
    {find = "fs25_ladyhill", id = "MO01501", name = "Ladyhill"},   -- Ladyhill, Antrim (24 km)
    {find = "fs25_wernolaufarm", id = "MO01227", name = "Wernolau Farm"},   -- Carmarthen (18 km)
    -- v0.28 (team 2026-11-14): French maps (commune, town, or region / its main town) -> nearest station passing the rule.
    {find = "fs25_lanrelas", id = "FR56127001", name = "Lanrelas"},   -- village: Lanrelas, Côtes-d'Armor (21 km)
    {find = "fs25_the_pichonniere_valley", id = "FR72181001", name = "The Pichonnière Valley"},   -- town: Le Mans (7 km)
    {find = "fs25_la_campagne_angevine", id = "FR49020001", name = "The Angevin Countryside"},   -- town: Angers (5 km)
    {find = "fs25_des_cagouilles_dans_l_garouil", id = "FR17353001", name = "Des Cagouilles Dans L'Garouil"},   -- town: Surgères (25 km)
    {find = "fs25_pallegney", id = "FR88402002", name = "Pallegney"},   -- village: Pallegney, Vosges (16 km)
    {find = "fs25_vouillynormandy", id = "FR14239001", name = "Vouilly Normandy"},   -- village: Vouilly, Calvados (12 km)
    {find = "fs25_the_mechet", id = "FR58062001", name = "The Mechet"},   -- region: Morvan (12 km)
    {find = "fs25_la_foret_du_haut_doubs", id = "FR25320001", name = "The Haut Doubs Forest"},   -- region (main town of the Haut-Doubs): Pontarlier (15 km)
    {find = "fs25_risouxforest", id = "FR25320001", name = "The Risoux Forest"},   -- region: Forêt du Risoux (26 km)
    -- v0.28 (team 2026-11-14): maps whose page names only a region -> station nearest the region (its OpenStreetMap location)
    -- or its main town / district seat. The player still confirms.
    {find = "fs25_am_nok", id = "DE01266", name = "Along The Kiel Canal"},   -- region: Nord-Ostsee-Kanal (19 km)
    {find = "fs25_bergischland", id = "DE02667", name = "Bergisch Land FS 25"},   -- region: Bergisches Land (23 km)
    {find = "fs25_deichblick", id = "DE01266", name = "Deichblick 25"},   -- region: Husum, Nordfriesland (27 km)
    {find = "fs25_fraenkischeschweiz", id = "DE00282", name = "Franconian Switzerland"},   -- region: Fränkische Schweiz (11 km)
    {find = "fs25_helden", id = "DE05541", name = "Helden"},   -- region: Wiesbaden (8 km)
    {find = "fs25_holzach", id = "DE03730", name = "Holzach"},   -- region: Sonthofen, Germany (12 km)
    {find = "fs25_homeland", id = "DE04466", name = "Homeland"},   -- region: Hüttener Berge, Schleswig-Holstein (18 km)
    {find = "fs25_leybucht_4x", id = "DE03631", name = "Leybucht 4x"},   -- region: Leybucht (18 km)
    {find = "fs25_lodygowo", id = "PL353230295", name = "Lodygowo"},   -- region: Białystok (3 km)
    {find = "fs25_lunow", id = "DE05097", name = "Lunow"},   -- region: Lunow, Mecklenburg-Vorpommern (17 km)
    {find = "fs25_mecklenburg_lake_district", id = "DE05349", name = "Mecklenburg Lake District"},   -- region: Neubrandenburg (40 km)
    {find = "fs25_mindenerwald", id = "DE04371", name = "Mindenerwald – Farming In The Mühlenkreis"},   -- region: Minden, Nordrhein-Westfalen (23 km)
    {find = "fs25_nordfriesisches_land", id = "DE01266", name = "North Frisian 25"},   -- region: Husum, Nordfriesland (27 km)
    {find = "fs25_pfaelzerwald", id = "DE05426", name = "Palatinate Forest"},   -- region: Pfälzerwald (18 km)
    {find = "fs25_pfaffenwinkel", id = "DE02290", name = "Pfaffenwinkel"},   -- region: Weilheim in Oberbayern (district seat, Pfaffenwinkel) (11 km)
    {find = "fs25_rhoenplateu", id = "DE05371", name = "Rhönplateu"},   -- region: Rhön (5 km)
    {find = "fs25_schmiechtal", id = "DE02814", name = "Schmiechtal"},   -- region: Schmiechen, Schelklingen (17 km)
    {find = "fs25_solek", id = "PL352200375", name = "Solek"},   -- region: Warszawa (10 km)
    {find = "fs25_zacieczki", id = "PL353230295", name = "Zacieczki"},   -- region: Białystok (3 km)
    -- v1.0.4 (team yes 2026-11-23): Delta South maps whose own modDesc names a town or county -> the new nearest station
    -- (same rule; place located with OpenStreetMap Nominatim; county maps use the county seat). Matched on the map's mod name.
    {find = "fs25_cruger_ms", id = "USW00013978", name = "Cruger, MS"},   -- Cruger, Holmes County (24 km)
    {find = "fs25_vance_ms", id = "USW00013978", name = "Vance, MS"},   -- Vance, Tallahatchie County (69 km)
    {find = "fs25_sherard_ms", id = "USW00013939", name = "Sherard, MS"},   -- Sherard, Coahoma County (86 km)
    {find = "fs25_cottonport_la", id = "USW00013935", name = "Cottonport, La"},   -- Cottonport, Avoyelles Parish (51 km)
    {find = "fs25_delaplaine_ar", id = "USW00003953", name = "Delaplaine AR"},   -- Delaplaine, Greene County (45 km)
    {find = "fs25_oran_mo", id = "USW00003935", name = "Oran, MO"},   -- Oran, Scott County (17 km)
    {find = "fs25_scottcounty_mo", id = "USW00003935", name = "Scott County, MO"},   -- county seat: Benton (14 km)
    {find = "fs25_goshen_al", id = "USW00003878", name = "Goshen, Al"},   -- Goshen, Pike County (18 km)
    {find = "fs25_lauderdalecounty_tn", id = "USW00053869", name = "Lauderdale County, TN"},   -- county seat: Ripley (35 km)
    -- v1.0.5 (team yes 2026-11-23): towns named by The Real JLP (Delta South Modding & Mapping) -> nearest station
    -- (towns located with OpenStreetMap Nominatim). Black River Farms is matched on its title ("BlackRiver Farms, La").
    {find = "fs25_ar_river_lowlands", id = "USW00093988", name = "AR River Lowlands"},   -- Pine Bluff, AR (8 km)
    {find = "fs25_jones_la", id = "USW00053961", name = "Jones, La"},   -- Jones, Morehouse Parish (44 km)
    {find = "fs25_la_ark_logging", id = "USW00053961", name = "La-Ark Logging"},   -- Jones, Morehouse Parish (44 km)
    {find = "blackriver", id = "USW00013935", name = "BlackRiver Farms, La"},   -- Jonesville, Catahoula Parish (52 km)
}
function W.stationFromMapName()
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    if mi == nil then return nil end
    local names = {mi.mapTitle, mi.mapId}
    if mi.map ~= nil then
        names[#names + 1] = mi.map.title
        names[#names + 1] = mi.map.id
        names[#names + 1] = mi.map.customEnvironment
    end
    for _, raw in ipairs(names) do
        if type(raw) == "string" then
            local low = raw:lower()
            for _, m in ipairs(W.MAP_STATIONS) do
                if low:find(m.find, 1, true) then return m, raw end
            end
        end
    end
    return nil
end
-- v0.21.6 home station per state: the NOAA station in that state closest to the state's 2020 center of population
-- (U.S. Census Bureau, Centers of Population for the 2020 Census, state file). Used only to pre-select; the player confirms.
W.HOME_STATIONS = {
    AK = "USW00026409",
    AL = "USW00013876",
    AR = "USW00013963",
    AZ = "USW00023183",
    CA = "USW00023155",
    CO = "USW00093067",
    CT = "USW00094702",
    DE = "USW00013781",
    FL = "USW00012815",
    GA = "USW00013874",
    HI = "USW00022534",
    IA = "USW00014933",
    ID = "USW00024131",
    IL = "USW00094892",
    IN = "USW00093819",
    KS = "USW00013920",
    KY = "USW00013810",
    LA = "USW00013976",
    MA = "USW00014739",
    MD = "USW00093721",
    ME = "USW00014605",
    MI = "USW00014836",
    MN = "USW00014922",
    MO = "USW00003945",
    MS = "USW00003940",
    MT = "USW00024144",
    NC = "USW00013723",
    ND = "USW00014919",
    NE = "USW00014939",
    NH = "USW00014745",
    NJ = "USW00014734",
    NM = "USW00023050",
    NV = "USW00003160",
    NY = "USW00014757",
    OH = "USW00014821",
    OK = "USW00013967",
    OR = "USW00024232",
    PA = "USW00014778",
    RI = "USW00014765",
    SC = "USW00013883",
    SD = "USW00014936",
    TN = "USW00013897",
    TX = "USW00013959",
    UT = "USW00024127",
    VA = "USW00013740",
    VT = "USW00094705",
    WA = "USW00024233",
    WI = "USW00014837",
    WV = "USW00013729",
    WY = "USW00024089",
}

-- v0.21.6 (team): pre-select the station from the map's name when it names a US state. Full state names first (longest first,
-- so "West Virginia" wins over "Virginia"), then a two-letter state code written in capitals as its own word ("Farmville NC").
function W.stateFromMapName()
    local names = {}
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    if mi ~= nil then
        if mi.map ~= nil then
            names[#names + 1] = mi.map.title
            names[#names + 1] = mi.map.customEnvironment
            names[#names + 1] = mi.map.id
        end
        names[#names + 1] = mi.mapTitle
        names[#names + 1] = mi.mapId
    end
    local full = {}
    for code, name in pairs(W.STATE_NAMES) do
        if W.HOME_STATIONS[code] ~= nil then full[#full + 1] = {code = code, name = name} end
    end
    table.sort(full, function(a, b) return #a.name > #b.name end)
    for _, raw in ipairs(names) do
        if type(raw) == "string" and raw ~= "" then
            local s = " " .. raw:gsub("[_%.%-]", " ") .. " "
            local low = s:lower()
            for _, f in ipairs(full) do
                if low:find("[^%a]" .. f.name:lower() .. "[^%a]") then return f.code, raw end
            end
            for code in s:gmatch("[^%a](%u%u)[^%a]") do
                if W.STATE_NAMES[code] ~= nil and W.HOME_STATIONS[code] ~= nil then return code, raw end
            end
        end
    end
    return nil
end
W.SEASON_MONTHS = nil                   -- filled at load (needs the game's Season table)

W.days = {}
W.state = {wet = false, zx = 0, zn = 0}
W.active = false
W.conflict = nil

local function log(fmt, ...)
    print(string.format("  Info: [CarolinaFieldAlmanac] " .. fmt, ...))
end

local function fToC(f) return (f - 32) / 1.8 end

-- v0.20 day-to-day humidity and wind (NOAA GSOD 1991-2020 percentiles, CFADaily.lua)
local DAILY_P = {2, 5, 10, 25, 50, 75, 90, 95, 98}
local function drawPct(t)
    if t == nil then return nil end
    local u = math.random() * 100
    if u <= DAILY_P[1] then return t[1] end
    if u >= DAILY_P[#DAILY_P] then return t[#t] end
    for i = 2, #DAILY_P do
        if u <= DAILY_P[i] then
            local f = (u - DAILY_P[i - 1]) / (DAILY_P[i] - DAILY_P[i - 1])
            return t[i - 1] + (t[i] - t[i - 1]) * f
        end
    end
    return t[#t]
end

-- saturation vapour pressure (hPa), Magnus formula (same as used to build the NOAA hourly humidity normals)
local function esF(f)
    local c = (f - 32) / 1.8
    return 6.112 * math.exp(17.62 * c / (243.12 + c))
end

local function gauss()
    local u1 = math.max(math.random(), 1e-9)
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * math.random())
end

-- Marsaglia & Tsang gamma sampler (alpha < 1 uses the standard boost)
local function gammaSample(alpha, beta)
    if alpha < 1 then
        return gammaSample(alpha + 1, beta) * math.random() ^ (1 / alpha)
    end
    local d = alpha - 1 / 3
    local c = 1 / math.sqrt(9 * d)
    while true do
        local x, v
        repeat
            x = gauss()
            v = 1 + c * x
        until v > 0
        v = v * v * v
        local u = math.random()
        if u < 1 - 0.0331 * x ^ 4 or math.log(u) < 0.5 * x * x + d * (1 - v + math.log(v)) then
            return d * v * beta
        end
    end
end

-- station data -----------------------------------------------------------------

local P_WD, P_WW, ALPHA, BETA, TXD, TXW, SXD, SXW, TND, TNW, SND, SNW = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12

-- v0.29 silage feed-out: the station's normal mean temperature (C) for a real month (same long-run wet/dry mix as stampSeasonNormals)
function W.monthMeanC(m)
    local st = W.getStation()
    if st == nil or st.months == nil or st.months[m] == nil then return nil end
    local p = st.months[m]
    local pw = p[P_WD] / (1 + p[P_WD] - p[P_WW])
    local hi = pw * p[TXW] + (1 - pw) * p[TXD]
    local lo = pw * p[TNW] + (1 - pw) * p[TND]
    return fToC((hi + lo) / 2)
end

function W.getStation(id)
    return CFAStationData ~= nil and CFAStationData.stations[id or W.stationId] or nil
end

-- v0.16: a station kept from an older version that is no longer shipped -> the nearest shipped station in its state
function W.resolveStation(id)
    if id ~= nil and CFAStationData ~= nil and CFAStationData.stations[id] == nil and CFAStationData.replaced ~= nil
        and CFAStationData.replaced[id] ~= nil then
        return CFAStationData.replaced[id]
    end
    return id
end

-- v0.16: rain timing, snow and thunder tables of the station's own state
function W.region()
    local st = W.getStation()
    local r = st ~= nil and CFAStationData.regions ~= nil and CFAStationData.regions[st.state] or nil
    return r or CFAStationData
end

function W.getHourly(station, month)
    local h = CFAStationData.hourly[station.hourly]
    return h ~= nil and h.months[month] or nil
end

-- state -> sorted city list -> stations in that city
function W.buildCityIndex()
    W.states = {}
    W.cities = {}
    local seen = {}
    for id, s in pairs(CFAStationData.stations) do
        if W.cities[s.state] == nil then
            W.cities[s.state] = {}
            table.insert(W.states, s.state)
        end
        local key = s.state .. "|" .. s.city
        if seen[key] == nil then
            seen[key] = {name = s.city, stations = {}}
            table.insert(W.cities[s.state], seen[key])
        end
        table.insert(seen[key].stations, id)
    end
    table.sort(W.states, function(a, b)   -- v0.26/v0.28: U.S. states first, then Canadian provinces, then Europe
        local ca, cb = W.groupOf(a), W.groupOf(b)
        if ca ~= cb then return ca < cb end
        return W.sortName(a) < W.sortName(b)
    end)
    for _, list in pairs(W.cities) do
        table.sort(list, function(a, b) return a.name < b.name end)
        for _, c in ipairs(list) do
            table.sort(c.stations, function(a, b)
                return CFAStationData.stations[a].part < CFAStationData.stations[b].part
            end)
        end
    end
end

-- FS25 periods start in March (period 1 = March).
-- Counted from today: current period + whole periods ahead (uses the save's days per month).
function W.monthAtDay(day)
    local env = g_currentMission.environment
    local today = env.currentMonotonicDay or day
    local dpp = math.max(1, env.daysPerPeriod or 1)
    local dayInPeriod = math.max(1, env.currentDayInPeriod or 1)
    local offset = math.floor((dayInPeriod - 1 + (day - today)) / dpp)
    local period = ((((env.currentPeriod or 6) - 1 + offset) % 12) + 12) % 12 + 1
    return ((period + 1) % 12) + 1
end

-- Drop future days from 'fromDay' on and make them again.
function W.dropDaysFrom(fromDay)
    for day in pairs(W.days) do
        if day >= fromDay then
            W.days[day] = nil
        end
    end
    W.lastDay = fromDay - 1
end

-- Drop saved future days whose month no longer fits (days per month changed).
function W.checkSavedMonths()
    local today = g_currentMission.environment.currentMonotonicDay or 1
    local firstBad = nil
    for day, d in pairs(W.days) do
        if day >= today and d.month ~= W.monthAtDay(day) and (firstBad == nil or day < firstBad) then
            firstBad = day
        end
    end
    if firstBad ~= nil then
        W.dropDaysFrom(firstBad)
        log("weather: days per month changed - remade the days from day %d", firstBad)
    end
    return firstBad
end

local function pickIndex(probs)
    local r = math.random()
    local acc = 0
    for i, p in ipairs(probs) do
        acc = acc + p
        if r <= acc then
            return i
        end
    end
    return #probs
end

-- Rain length from the NOAA deciles (10 % ... 90 %) for this month and rain amount.
local function sampleDuration(month, inches)
    local t = W.region().rainTiming[month]
    local class = inches < 0.10 and 1 or inches < 0.50 and 2 or inches < 1.00 and 3 or 4
    local q = t.dur[class]
    local i = math.random(1, #q)
    local lo = q[math.max(1, i - 1)]
    return math.max(0.5, lo + (q[i] - lo) * math.random())
end

local function snowChance(hiC)
    local s = W.region().snowChance
    local x = hiC - s.fromC + 1
    if x <= 1 then
        return s.values[1]
    end
    if x >= #s.values then
        return hiC > s.fromC + #s.values + 2 and 0 or s.values[#s.values]
    end
    local i = math.floor(x)
    return s.values[i] + (s.values[i + 1] - s.values[i]) * (x - i)
end

function W.generateDay(day)
    local st = W.getStation()
    local month = W.monthAtDay(day)
    local p = st.months[month]
    local s = W.state

    -- v0.29.11 (team 2026-11-16): rain or dry carries over by the real days a game day stands for. 2-state Markov chain k steps
    -- ahead: share of wet days pi = pWD / (1 - pWW + pWD), link l = pWW - pWD; wet after a wet day = pi + (1 - pi) l^k,
    -- after a dry day = pi (1 - l^k). k = 1 (30 days per month) gives pWW / pWD as before.
    local dppW = math.max(1, (g_currentMission ~= nil and g_currentMission.environment ~= nil and g_currentMission.environment.daysPerPeriod) or 1)
    local kW = math.max(1, (W.MONTH_DAYS[month] or 30) / dppW)
    local pWD, pWW = p[P_WD], p[P_WW]
    local pi = pWD / math.max(1e-6, 1 - pWW + pWD)
    local l = pWW - pWD
    local lk = (l >= 0 and l ^ kW) or (kW <= 1 and l) or 0
    local wet = math.random() < (s.wet and (pi + (1 - pi) * lk) or (pi * (1 - lk)))
    -- v0.29.10 (team 2026-11-16): the day's carry-over follows the real days a game day stands for (AR(1): lag-k = r^k), and the
    -- high and low move together with the station's own lag-0 link (WGEN, Richardson 1981; rxn measured from the same GHCN-Daily
    -- 1991-2020 records the station was fitted to)
    local dpp = math.max(1, (g_currentMission ~= nil and g_currentMission.environment ~= nil and g_currentMission.environment.daysPerPeriod) or 1)
    local k = math.max(1, (W.MONTH_DAYS[month] or 30) / dpp)
    local ax, an = st.rx ^ k, st.rn ^ k
    local ex, en = math.sqrt(1 - ax * ax), math.sqrt(1 - an * an)
    local rho = 0
    if st.rxn ~= nil and ex > 0 and en > 0 then
        rho = math.max(-1, math.min(1, st.rxn * (1 - ax * an) / (ex * en)))   -- innovation link that gives the measured link between the days' values
    end
    -- v0.29.11 (team 2026-11-16): a day's high or low past the station's own 1991-2020 record for the month (highest / lowest daily
    -- high and low, same records; values more than 6 SD from the month mean dropped as in GHCN-Daily QC, Durre et al. 2010) is drawn again
    local rec = st.rec ~= nil and st.rec[month] or nil
    local zx, zn, hi, lo
    for try = 1, 50 do
        local g1 = gauss()
        local g2 = rho * g1 + math.sqrt(1 - rho * rho) * gauss()
        zx = ax * s.zx + ex * g1
        zn = an * s.zn + en * g2
        hi = (wet and p[TXW] or p[TXD]) + zx * (wet and p[SXW] or p[SXD])
        lo = (wet and p[TNW] or p[TND]) + zn * (wet and p[SNW] or p[SND])
        if rec == nil or (hi <= rec[1] and hi >= rec[2] and lo <= rec[3] and lo >= rec[4]) then break end
        if try == 50 then
            hi = math.max(rec[2], math.min(rec[1], hi))
            lo = math.max(rec[4], math.min(rec[3], lo))
        end
    end
    s.zx, s.zn = zx, zn
    s.wet = wet

    if lo > hi - 1 then
        lo = hi - 1
    end

    local d = {month = month, wet = wet, rainMM = 0, hiC = fToC(hi), loC = fToC(lo)}
    local dm = CFAStationData.daily ~= nil and CFAStationData.daily[W.stationId] ~= nil and CFAStationData.daily[W.stationId][month] or nil
    if dm ~= nil then
        local hot = hi >= (dm.nh or hi)
        d.dep = drawPct(dm[(wet and "w" or "d") .. (hot and "h" or "c")])   -- high minus the day's dew point (F)
        d.wnd = drawPct(wet and dm.gw or dm.gd)                             -- the day's mean wind (mph)
    end
    if wet then
        d.rainMM = math.max(W.WET_MM, gammaSample(p[ALPHA], p[BETA]))
        local timing = W.region().rainTiming[month]
        d.rainStart = (pickIndex(timing.start) - 1) + math.random()
        d.rainEnd = math.min(24, d.rainStart + sampleDuration(month, d.rainMM / 25.4))
        d.snow = math.random() < snowChance(d.hiC)
        d.thunder = not d.snow and math.random() < W.region().thunderChance[month]
    else
        local h = W.getHourly(st, month)
        local r = math.random() * 100
        if h == nil or r < h.clear then
            d.sky = "SUN"
        elseif r < 100 - h.overcast then
            d.sky = "PARTLY"
        else
            d.sky = "CLOUDY"
        end
    end
    W.days[day] = d
    return d
end

function W.ensureDays()
    local today = g_currentMission.environment.currentMonotonicDay or 1
    local last = W.lastDay
    if last == nil or last < today - 1 then
        last = today - 1
    end
    while last < today + W.DAYS_AHEAD do
        last = last + 1
        if W.days[last] == nil then
            W.generateDay(last)
        end
    end
    W.lastDay = last
    for day in pairs(W.days) do
        if day < today - 2 then
            W.days[day] = nil
        end
    end
end

function W.getDay(day)
    if W.clientMode and not W.active then return W.days[day] end   -- v0.30 multiplayer: a player only uses the host's days
    if W.days[day] == nil then
        W.ensureDays()
        if W.days[day] == nil then
            -- beyond our window (initial forecast fill): generate in order up to it
            local k = W.lastDay or (day - 1)
            while k < day do
                k = k + 1
                if W.days[k] == nil then
                    W.generateDay(k)
                end
            end
            W.lastDay = math.max(W.lastDay or k, k)
        end
    end
    return W.days[day]
end

-- What the sky should be at a given day / hour, and how many hours until that changes.
function W.targetAt(day, hour)
    local d = W.getDay(day)
    if d.wet then
        if hour < d.rainStart then
            return "PARTLY", d.rainStart - hour
        elseif hour < d.rainEnd then
            if d.snow then
                return "SNOW", d.rainEnd - hour
            end
            return d.thunder and "THUNDER" or "RAIN", d.rainEnd - hour
        end
        return "CLOUDY", 24 - hour
    end
    return d.sky, 24 - hour
end

-- game weather hooks -----------------------------------------------------------

local TYPE_MATCH = {
    SUN = function(t) return t == WeatherType.SUN end,
    PARTLY = function(t) return t == WeatherType.PARTIALLY_CLOUDY end,
    CLOUDY = function(t) return t == WeatherType.CLOUDY end,
    RAIN = function(t) return t == WeatherType.RAIN end,
    THUNDER = function(t) return t == WeatherType.THUNDER end,
    SNOW = function(t) return t == WeatherType.SNOW end
}
-- Never fall back from a dry day to snow, hail or a twister.
local TYPE_FALLBACK = {SUN = {"PARTLY", "CLOUDY"}, PARTLY = {"SUN", "CLOUDY"}, CLOUDY = {"PARTLY", "SUN"},
    RAIN = {"THUNDER", "CLOUDY"}, THUNDER = {"RAIN", "CLOUDY"}, SNOW = {"RAIN", "CLOUDY"}}

local function findObjectIndex(weather, season, target)
    local objects = weather.weatherObjects ~= nil and weather.weatherObjects[season] or nil
    if objects == nil then
        return nil
    end
    local list = {target}
    for _, t in ipairs(TYPE_FALLBACK[target] or {}) do
        table.insert(list, t)
    end
    for _, t in ipairs(list) do
        for index, object in ipairs(objects) do
            if TYPE_MATCH[t](object.weatherType) then
                return index
            end
        end
    end
    return nil
end

-- Give every weather object extra variations (one per day in the forecast window), so the
-- forecast screen can show each day's own high and low. Added right after the map's weather
-- is loaded, before the savegame forecast is read, so saved indices stay valid.
function W.addVariationSlots(weather)
    if W.findConflict() ~= nil or weather.weatherObjects == nil then
        return
    end
    for _, objects in pairs(weather.weatherObjects) do
        for _, object in ipairs(objects) do
            if object.cfaBase == nil and object.variations ~= nil and object.variations[1] ~= nil then
                object.cfaBase = #object.variations
                for _ = 1, W.SLOTS do
                    local copy = {}
                    for k, v in pairs(object.variations[1]) do
                        copy[k] = v
                    end
                    table.insert(object.variations, copy)
                end
            end
        end
    end
end

local function setSlot(object, day)
    if object == nil or object.cfaBase == nil then
        return nil
    end
    local d = W.getDay(day)
    local index = object.cfaBase + (day % W.SLOTS) + 1
    local v = object.variations[index]
    if v ~= nil and d ~= nil then
        v.minTemperature = d.loC
        v.maxTemperature = d.hiC
    end
    return index
end

-- Game asks for the next forecast block: we decide its type, length and temperatures.
function W.createWeatherInstance(weather, superFunc, season, day, dayTime, isInitialSync)
    local instance = superFunc(weather, season, day, dayTime, isInitialSync)
    if instance == nil or not W.active then
        return instance
    end
    local hour = (dayTime or 0) / 3600000
    local target, hoursLeft = W.targetAt(day, hour)
    local useSeason = instance.season or season
    local index = findObjectIndex(weather, useSeason, target)
    if index == nil and useSeason ~= season then
        index = findObjectIndex(weather, season, target)
        if index ~= nil then
            useSeason = season
            instance.season = season
        end
    end
    if index ~= nil then
        instance.objectIndex = index
        instance.variationIndex = 1
    else
        W.missingTypes = (W.missingTypes or 0) + 1
        if W.missingTypes <= 5 then
            log("weather: map has no %s weather for season %s - kept the game's pick", tostring(target), tostring(useSeason))
        end
    end
    local objects = weather.weatherObjects ~= nil and weather.weatherObjects[useSeason] or nil
    local slot = setSlot(objects ~= nil and objects[instance.objectIndex] or nil, day)
    if slot ~= nil then
        instance.variationIndex = slot
    end
    instance.duration = math.floor(math.max(0.25, math.min(hoursLeft, 24)) * 3600000)
    return instance
end

-- v0.25.18 (tester report 2026-11-11): after a save loads, the game's temperature (HUD high/low, "Currently") blended
-- slowly from the saved map temperature (e.g. 77/59 F) toward our day (48/28 F), so the HUD and the Weather tab did not
-- match for game hours. Snap the game's temperature to our day once at load. Every number field of the game's
-- temperature updater named like currentMin / targetMin (or ...Max) is set, so the blend has nothing left to blend from.
function W.snapTemperature(day)
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    local tu = env ~= nil and env.weather ~= nil and env.weather.temperatureUpdater or nil
    local d = W.getDay(day or (env ~= nil and env.currentMonotonicDay) or 1)
    if tu == nil or d == nil or type(tu.currentMin) ~= "number" then
        return false
    end
    local before = string.format("%.0f/%.0f F", tu.currentMax * 1.8 + 32, tu.currentMin * 1.8 + 32)
    local keys = {}
    for k, v in pairs(tu) do
        if type(k) == "string" and type(v) == "number" then
            if k:match("^%l+Min$") then
                tu[k] = d.loC; keys[#keys + 1] = k
            elseif k:match("^%l+Max$") then
                tu[k] = d.hiC; keys[#keys + 1] = k
            end
        end
    end
    table.sort(keys)
    log("weather: game temperature set to today's %s (was %s; %s)", W.getTodayText(), before, table.concat(keys, ", "))
    return true
end

-- When a block starts, give it the day's real high and low.
function W.activateWeatherObject(object, superFunc, instance, changeDuration)
    local d = nil
    if (W.active or W.clientMode) and instance ~= nil and instance.startDay ~= nil and object.variations ~= nil then
        d = W.getDay(instance.startDay)
        local variation = object.variations[instance.variationIndex or 1]
        if d ~= nil and variation ~= nil then
            variation.minTemperature = d.loC
            variation.maxTemperature = d.hiC
        end
    end
    local result = {superFunc(object, instance, changeDuration)}
    if W.snapOnActivate and d ~= nil then
        W.snapOnActivate = false
        W.snapTemperature(instance.startDay)
    end
    return unpack(result)
end

-- Saved forecasts use only the map's own variations, so a save still loads if this mod is removed.
function W.saveWeather(weather, superFunc, ...)
    local changed = {}
    if weather.forecastItems ~= nil and weather.getWeatherObjectByIndex ~= nil then
        for _, item in ipairs(weather.forecastItems) do
            local ok, object = true, weather.getWeatherObjectByIndex(weather, item.season, item.objectIndex)
            if ok and object ~= nil and object.cfaBase ~= nil and (item.variationIndex or 1) > object.cfaBase then
                table.insert(changed, {item, item.variationIndex})
                item.variationIndex = 1
            end
        end
    end
    local result = {superFunc(weather, ...)}
    for _, c in ipairs(changed) do
        c[1].variationIndex = c[2]
    end
    return unpack(result)
end

-- Seasonal outlook: give the map's own variations this station's NOAA normals for each season.
function W.stampSeasonNormals()
    local weather = g_currentMission.environment.weather
    local st = W.getStation()
    if weather == nil or weather.weatherObjects == nil or st == nil or Season == nil then
        return
    end
    local seasonMonths = {
        [Season.SPRING] = {3, 4, 5}, [Season.SUMMER] = {6, 7, 8},
        [Season.AUTUMN] = {9, 10, 11}, [Season.WINTER] = {12, 1, 2}
    }
    for season, objects in pairs(weather.weatherObjects) do
        local months = seasonMonths[season]
        if months ~= nil then
            local hi, lo = 0, 0
            for _, m in ipairs(months) do
                local p = st.months[m]
                local pw = p[P_WD] / (1 + p[P_WD] - p[P_WW])        -- long-run share of rainy days
                hi = hi + (pw * p[TXW] + (1 - pw) * p[TXD]) / 3
                lo = lo + (pw * p[TNW] + (1 - pw) * p[TND]) / 3
            end
            for _, object in ipairs(objects) do
                for i = 1, (object.cfaBase or #object.variations) do
                    local v = object.variations[i]
                    if v ~= nil then
                        v.minTemperature = fToC(lo)
                        v.maxTemperature = fToC(hi)
                    end
                end
            end
        end
    end
end

-- Rebuild the forecast from now on so it follows our days.
function W.rebuildForecast()
    local weather = g_currentMission.environment.weather
    if weather == nil or weather.forecastItems == nil then
        return
    end
    local env = g_currentMission.environment
    local first = weather.forecastItems[1]
    for i = #weather.forecastItems, 2, -1 do
        table.remove(weather.forecastItems, i)
    end
    if first ~= nil then
        -- the block running now ends within a game minute, then our first block starts
        local elapsed = (env.currentMonotonicDay - first.startDay) * 86400000 + env.dayTime - first.startDayTime
        first.duration = math.max(60000, elapsed + 60000)
    end
    if weather.fillWeatherForecast ~= nil then
        local ok, err = true, weather.fillWeatherForecast(weather, false)
        if not ok then
            log("weather: forecast refill failed: %s", tostring(err))
        end
    end
end

-- values for the drying model ----------------------------------------------------

-- Hour-by-hour temperature (F) for a generated day: the day's own NOAA-based high and low, spread over the day
-- in the shape of the NOAA 1991-2020 hourly temperature normals for that month at the nearest hourly station.
-- shape(h) = (normal(h) - coldest normal hour) / (warmest - coldest); temp(h) = low + (high - low) * shape(h).
function W.hourlyTempsF(day)
    local d = W.days[day]
    local st = W.getStation()
    if d == nil or st == nil then return nil end
    local h = W.getHourly(st, d.month)
    if h == nil or h.temp == nil or #h.temp ~= 24 then return nil end
    local nmin, nmax = math.huge, -math.huge
    for i = 1, 24 do
        nmin = math.min(nmin, h.temp[i])
        nmax = math.max(nmax, h.temp[i])
    end
    if nmax <= nmin then return nil end
    local hiF, loF = d.hiC * 1.8 + 32, d.loC * 1.8 + 32
    local t = {}
    for i = 1, 24 do
        t[i] = loF + (hiF - loF) * (h.temp[i] - nmin) / (nmax - nmin)
    end
    return t
end

-- Number of hours in the day at or below (or strictly below) a temperature.
function W.hoursColdF(day, thresholdF, strict)
    local t = W.hourlyTempsF(day)
    if t == nil then return nil end
    local n = 0
    for i = 1, 24 do
        if (strict and t[i] < thresholdF) or (not strict and t[i] <= thresholdF) then n = n + 1 end
    end
    return n
end

-- v0.20: this day's own hourly humidity and wind (nil = use the NOAA hourly normals, e.g. days saved before v0.20)
function W.dayRH(d, i, day)
    if d == nil or d.dep == nil or day == nil then return nil end
    local t = W.hourlyTempsF(day)
    if t == nil then return nil end
    local td = d.hiC * 1.8 + 32 - d.dep
    return math.max(1, math.min(100, 100 * esF(td) / esF(t[i])))
end

function W.dayWind(d, h, i)
    if d == nil or d.wnd == nil or h == nil then return nil end
    local sum = 0
    for k = 1, 24 do sum = sum + h.wind[k] end
    if sum <= 0 then return nil end
    return h.wind[i] * d.wnd / (sum / 24)
end

-- v0.20: hours of the day that are hot, dry and windy at once (K-State / Lin et al. 2022 Nature Communications 13:7438:
-- temperature >= 32 C, relative humidity <= 30 %, wind >= 7 m/s; the study's 10 m wind matches NOAA station wind)
function W.hdwHours(day, tempC, rhPct, windMs)
    local d = W.days[day]
    local h = d ~= nil and W.getHourly(W.getStation(), d.month) or nil
    local t = W.hourlyTempsF(day)
    if d == nil or h == nil or t == nil or d.dep == nil or d.wnd == nil then return 0 end
    local td = d.hiC * 1.8 + 32 - d.dep
    local tF, wMph = (tempC or 32) * 1.8 + 32, (windMs or 7) * 2.23694
    local n = 0
    for i = 1, 24 do
        local rh = 100 * esF(td) / esF(t[i])
        local raining = d.wet and d.rainStart ~= nil and (i - 1) >= d.rainStart and (i - 1) < d.rainEnd
        if not raining and t[i] >= tF and rh <= (rhPct or 30) and (W.dayWind(d, h, i) or 0) >= wMph then
            n = n + 1
        end
    end
    return n
end

function W.getHumidity()
    if not W.active then
        return nil
    end
    local env = g_currentMission.environment
    local d = W.getDay(env.currentMonotonicDay)
    local h = W.getHourly(W.getStation(), d.month)
    if h == nil then
        return nil
    end
    local hour = env.dayTime / 3600000
    local rh = W.dayRH(d, (math.floor(hour) % 24) + 1, env.currentMonotonicDay) or h.rh[(math.floor(hour) % 24) + 1]
    if d.wet then
        if hour >= d.rainStart and hour < d.rainEnd + 2 then
            rh = 97
        else
            rh = math.min(100, rh + 8)
        end
    end
    return rh
end

-- Weather at any game day and hour from CFA's own data (used to replay time skipped by sleeping).
-- Same rules as the live values: hourly NOAA humidity/wind/temperature shape; rain inside the day's rain window.
function W.conditionsAt(day, hour)
    if not W.active then
        return nil
    end
    local d = W.getDay(day)
    local st = W.getStation()
    local h = d ~= nil and W.getHourly(st, d.month) or nil
    if h == nil then
        return nil
    end
    local i = (math.floor(hour) % 24) + 1
    local c = {rain = false, snow = false, humidity = W.dayRH(d, i, day) or h.rh[i], windMph = W.dayWind(d, h, i) or h.wind[i]}
    if d.wet then
        if hour >= d.rainStart and hour < d.rainEnd then
            c.rain = true
            c.snow = d.snow == true
        end
        if hour >= d.rainStart and hour < d.rainEnd + 2 then
            c.humidity = 97
        else
            c.humidity = math.min(100, c.humidity + 8)
        end
    end
    local t = W.hourlyTempsF(day)
    if t ~= nil then
        c.tempC = (t[i] - 32) / 1.8
    end
    return c
end

function W.getWindMph()
    if not W.active then
        return nil
    end
    local env = g_currentMission.environment
    local d = W.getDay(env.currentMonotonicDay)
    local h = W.getHourly(W.getStation(), d.month)
    if h == nil then return nil end
    local i = (math.floor(env.dayTime / 3600000) % 24) + 1
    return W.dayWind(d, h, i) or h.wind[i]
end

function W.getDayText(d)
    if d == nil then
        return "-"
    end
    local hiF, loF = d.hiC * 1.8 + 32, d.loC * 1.8 + 32
    if d.wet then
        return string.format("%.0f/%.0f F, %s %.2f in (%02d:00-%02d:00)", hiF, loF,
            d.snow and "snow" or (d.thunder and "thunderstorm" or "rain"), d.rainMM / 25.4,
            math.floor(d.rainStart), math.floor(d.rainEnd) % 24)
    end
    return string.format("%.0f/%.0f F, %s", hiF, loF, d.sky)
end

function W.getTodayText()
    return W.getDayText(W.getDay(g_currentMission.environment.currentMonotonicDay))
end

function W.getStationText(id)
    local s = W.getStation(id)
    if s == nil then
        return "-"
    end
    local where = s.state
    if W.EUROPE ~= nil and W.EUROPE[s.state] ~= nil then   -- v0.28: "Warszawa-Okecie, Poland" / "Kempten, Bavaria"
        where = W.STATE_NAMES[s.state] or s.state
    end
    return string.format("%s, %s%s", s.city, where, s.part ~= "" and (" (" .. s.part .. ")") or "")
end

-- change station ------------------------------------------------------------------

function W.setStation(id)
    id = W.resolveStation(id)
    if id == W.stationId or W.getStation(id) == nil then
        return
    end
    W.stationId = id
    if W.active then
        local today = g_currentMission.environment.currentMonotonicDay or 1
        W.dropDaysFrom(today + 1)
        W.ensureDays()
        W.stampSeasonNormals()
        W.rebuildForecast()
    end
    log("weather: station set to %s (%s)", id, W.getStationText(id))
end

-- v0.30 multiplayer: a pick on the game's Settings page - on a player's game it goes to the host (host or admin only)
function W.pickStation(id)
    if CFAMP ~= nil and CFAMP.isClientOnly() then
        if not CFAMP.canAdmin() then
            if CarolinaFieldCure ~= nil and CarolinaFieldCure.showPopup ~= nil then
                CarolinaFieldCure.showPopup("info", "Only the host or an admin can change the weather station")
            end
            W.uiPicked = false
            return
        end
        id = W.resolveStation(id)
        if W.getStation(id) == nil then return end
        W.stationId = id   -- the list shows it now; the host's days follow in a moment
        CFAMP.request("station", {id = id})
        return
    end
    W.setStation(id)
end

-- v0.30 multiplayer: a player's game got new days from the host - give every forecast slot its day's high and low, and
-- (first time, or a new station) the seasonal outlook and today's temperature.
function W.clientDaysChanged(full)
    local weather = g_currentMission ~= nil and g_currentMission.environment ~= nil and g_currentMission.environment.weather or nil
    if weather == nil or weather.weatherObjects == nil then return end
    for day, d in pairs(W.days) do
        local idx = (day % W.SLOTS) + 1
        for _, objects in pairs(weather.weatherObjects) do
            for _, object in ipairs(objects) do
                local v = object.cfaBase ~= nil and object.variations ~= nil and object.variations[object.cfaBase + idx] or nil
                if v ~= nil and d ~= nil then
                    v.minTemperature = d.loC
                    v.maxTemperature = d.hiC
                end
            end
        end
    end
    if W.clientStampedFor ~= W.stationId then
        W.clientStampedFor = W.stationId
        W.stampSeasonNormals()
    end
    if full and not W.clientSnapped then
        local today = g_currentMission.environment.currentMonotonicDay
        if W.days[today] ~= nil then
            W.clientSnapped = true
            W.snapTemperature(today)
        end
    end
end

-- save / load ---------------------------------------------------------------------

function W.getSavePath()
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    if mi == nil or mi.savegameDirectory == nil then
        return nil
    end
    return mi.savegameDirectory .. "/" .. W.SAVE_FILE
end

function W.save(path)
    path = path or W.getSavePath()
    if path == nil then
        return
    end
    local xml = XMLFile.create("cfaWeatherXML", path, "carolinaFieldAlmanacWeather")
    if xml == nil then
        return
    end
    local root = "carolinaFieldAlmanacWeather"
    xml:setString(root .. "#station", W.stationId)
    xml:setBool(root .. ".state#wet", W.state.wet)
    xml:setFloat(root .. ".state#zx", W.state.zx)
    xml:setFloat(root .. ".state#zn", W.state.zn)
    xml:setInt(root .. ".state#lastDay", W.lastDay or 0)
    local sorted = {}
    for day in pairs(W.days) do
        table.insert(sorted, day)
    end
    table.sort(sorted)
    for i, day in ipairs(sorted) do
        local d = W.days[day]
        local key = string.format("%s.days.day(%d)", root, i - 1)
        xml:setInt(key .. "#day", day)
        xml:setInt(key .. "#month", d.month)
        xml:setBool(key .. "#wet", d.wet)
        xml:setFloat(key .. "#rainMM", d.rainMM)
        xml:setFloat(key .. "#hiC", d.hiC)
        xml:setFloat(key .. "#loC", d.loC)
        if d.dep ~= nil then xml:setFloat(key .. "#dep", d.dep) end
        if d.wnd ~= nil then xml:setFloat(key .. "#wnd", d.wnd) end
        if d.wet then
            xml:setFloat(key .. "#rainStart", d.rainStart)
            xml:setFloat(key .. "#rainEnd", d.rainEnd)
            xml:setBool(key .. "#thunder", d.thunder == true)
            xml:setBool(key .. "#snow", d.snow == true)
        else
            xml:setString(key .. "#sky", d.sky)
        end
    end
    xml:save()
    xml:delete()
end

function W.load()
    local path = W.getSavePath()
    if path == nil then
        return false
    end
    local xml = XMLFile.loadIfExists("cfaWeatherXML", path)
    if xml == nil then
        return false
    end
    local root = "carolinaFieldAlmanacWeather"
    local id = W.resolveStation(xml:getString(root .. "#station", W.DEFAULT_STATION))
    if W.getStation(id) ~= nil then
        W.stationId = id
    end
    W.state.wet = xml:getBool(root .. ".state#wet", false)
    W.state.zx = xml:getFloat(root .. ".state#zx", 0)
    W.state.zn = xml:getFloat(root .. ".state#zn", 0)
    local lastDay = xml:getInt(root .. ".state#lastDay", 0)
    W.lastDay = lastDay > 0 and lastDay or nil
    xml:iterate(root .. ".days.day", function(_, key)
        local day = xml:getInt(key .. "#day")
        if day ~= nil then
            local d = {
                month = xml:getInt(key .. "#month", 6),
                wet = xml:getBool(key .. "#wet", false),
                rainMM = xml:getFloat(key .. "#rainMM", 0),
                hiC = xml:getFloat(key .. "#hiC", 25),
                loC = xml:getFloat(key .. "#loC", 15),
                dep = xml:getFloat(key .. "#dep"),
                wnd = xml:getFloat(key .. "#wnd")
            }
            if d.wet then
                d.rainStart = xml:getFloat(key .. "#rainStart", 14)
                d.rainEnd = xml:getFloat(key .. "#rainEnd", 16)
                d.thunder = xml:getBool(key .. "#thunder", false)
                d.snow = xml:getBool(key .. "#snow", false)
            else
                d.sky = xml:getString(key .. "#sky", "SUN")
            end
            W.days[day] = d
        end
    end)
    xml:delete()
    return true
end

-- settings menu: State -> City -> Part of town ----------------------------------------

W.ui = {controls = {}}

local function getSettingsPage()
    local menu = g_gui ~= nil and g_gui.screenControllers ~= nil and g_gui.screenControllers[InGameMenu] or nil
    local page = menu ~= nil and menu.pageSettings or nil
    if page == nil or page.generalSettingsLayout == nil then
        return nil
    end
    return page
end

local function giveFocusIds(element)
    element.focusId = FocusManager:serveAutoFocusId()
    for _, child in ipairs(element.elements or {}) do
        giveFocusIds(child)
    end
end

function W.uiStateIndex()
    local s = W.getStation()
    for i, st in ipairs(W.states) do
        if st == s.state then
            return i
        end
    end
    return 1
end

function W.uiCityIndex()
    local s = W.getStation()
    for i, c in ipairs(W.cities[s.state]) do
        if c.name == s.city then
            return i
        end
    end
    return 1
end

function W.uiPartIndex()
    local s = W.getStation()
    local c = W.cities[s.state][W.uiCityIndex()]
    for i, id in ipairs(c.stations) do
        if id == W.stationId then
            return i
        end
    end
    return 1
end

local function stateTexts()
    local t = {}
    for _, st in ipairs(W.states) do
        table.insert(t, W.listLabel(st))
    end
    return t
end

local function cityTexts(state)
    local t = {}
    for _, c in ipairs(W.cities[state]) do
        table.insert(t, c.name)
    end
    return t
end

local function partTexts(city)
    local t = {}
    for _, id in ipairs(city.stations) do
        local part = CFAStationData.stations[id].part
        table.insert(t, part ~= "" and part or "-")
    end
    return t
end

function W.uiRefresh()
    local c = W.ui.controls
    if c.state == nil then
        return
    end
    local s = W.getStation()
    c.state:setTexts(stateTexts())
    c.state:setState(W.uiStateIndex())
    c.city:setTexts(cityTexts(s.state))
    c.city:setState(W.uiCityIndex())
    c.part:setTexts(partTexts(W.cities[s.state][W.uiCityIndex()]))
    c.part:setState(W.uiPartIndex())
end

CFAWeatherControls = {}

-- the option element may hand over (state, element) or (element, state)
function CFAWeatherControls:onCfaOptionChanged(a, b)
    local state, element
    if type(a) == "number" then
        state, element = a, b
    else
        element, state = a, b
    end
    if element == nil or element.id == nil or state == nil then
        return
    end
    local s = W.getStation()
    W.uiPicked = true   -- v0.21.6: the player is choosing a station (confirmed when they leave the menu)
    if element.id == "cfaState" then
        local st = W.states[state]
        if st ~= nil and st ~= s.state then
            W.pickStation(W.cities[st][1].stations[1])
        end
    elseif element.id == "cfaCity" then
        local c = W.cities[s.state][state]
        if c ~= nil then
            W.pickStation(c.stations[1])
        end
    elseif element.id == "cfaPart" then
        local c = W.cities[s.state][W.uiCityIndex()]
        if c.stations[state] ~= nil then
            W.pickStation(c.stations[state])
        end
    end
    W.uiRefresh()
end

local function addOption(page, template, id, title, tooltip)
    local box = template:clone(page.generalSettingsLayout)
    box.id = id .. "Box"
    local option = box.elements ~= nil and box.elements[1] or nil
    if option == nil then
        return nil
    end
    option.id = id
    option.target = CFAWeatherControls
    option:setCallback("onClickCallback", "onCfaOptionChanged")
    option:setDisabled(false)
    if option.elements ~= nil and option.elements[1] ~= nil and option.elements[1].setText ~= nil then
        option.elements[1]:setText(tooltip)
    end
    if box.elements[2] ~= nil and box.elements[2].setText ~= nil then
        box.elements[2]:setText(title)
    end
    giveFocusIds(box)
    table.insert(page.controlsList, box)
    W.ui.controls[id] = option
    return option
end

function W.injectMenu()
    local page = getSettingsPage()
    if page == nil then
        return false
    end
    CFAWeatherControls.name = page.name
    -- prefer a multi-choice option (many entries); a two-state toggle is the last resort
    local template = nil
    for _, element in ipairs(page.generalSettingsLayout.elements) do
        local first = element.elements ~= nil and element.elements[1] or nil
        if first ~= nil and #element.elements >= 2 and MultiTextOptionElement ~= nil and first.isa ~= nil
            and first:isa(MultiTextOptionElement) and not (BinaryOptionElement ~= nil and first:isa(BinaryOptionElement)) then
            template = element
            break
        end
    end
    if template == nil then
        log("weather: no multi-choice template in settings - use the cfaStation console command")
        return true
    end
    if template == nil then
        log("weather: settings menu template not found - use the cfaStation console command")
        return true
    end
    for _, element in ipairs(page.generalSettingsLayout.elements) do
        if element.name == "sectionHeader" then
            local header = element:clone(page.generalSettingsLayout)
            header:setText("Carolina Field Almanac - weather location")
            giveFocusIds(header)
            table.insert(page.controlsList, header)
            break
        end
    end
    W.ui.controls.state = addOption(page, template, "cfaState", "Weather: state / province", "U.S. state, Canadian province or European country / region for the weather station")
    W.ui.controls.city = addOption(page, template, "cfaCity", "Weather: city", "City for the weather station")
    W.ui.controls.part = addOption(page, template, "cfaPart", "Weather: part of town", "If a city has more than one station: north, south, east or west")
    W.ui.controls.cfaState, W.ui.controls.cfaCity, W.ui.controls.cfaPart = nil, nil, nil
    W.uiRefresh()
    page.generalSettingsLayout:invalidateLayout()
    log("weather: location options added to the settings page")
    return true
end

-- keyboard / controller navigation for the added options
if FocusManager ~= nil and FocusManager.setGui ~= nil then
    FocusManager.setGui = Utils.appendedFunction(FocusManager.setGui, function(_, gui)
        if gui ~= "ingameMenuSettings" then
            return
        end
        for _, control in pairs(W.ui.controls) do
            if control ~= nil and (control.focusId == nil
                or FocusManager.currentFocusData.idToElementMapping[control.focusId] == nil) then
                FocusManager:loadElementFromCustomValues(control, nil, nil, false, false)
            end
        end
        local page = getSettingsPage()
        if page ~= nil then
            page.generalSettingsLayout:invalidateLayout()
        end
    end)
end

-- start ------------------------------------------------------------------------------

function W.findConflict()
    if g_modIsLoaded == nil then
        return nil
    end
    for _, name in ipairs(W.CONFLICT_MODS) do
        if g_modIsLoaded[name] then
            return name
        end
    end
    return nil
end

if Weather ~= nil and Weather.load ~= nil then
    Weather.load = Utils.appendedFunction(Weather.load, function(weather)
        local ok, err = true, W.addVariationSlots(weather)
        if not ok then
            log("weather: could not add forecast slots: %s", tostring(err))
        end
    end)
end

function W.start(mission)
    if CFAStationData == nil then
        log("weather: no station data - weather part off")
        return
    end
    W.buildCityIndex()
    W.conflict = W.findConflict()
    if W.conflict ~= nil then
        log("weather: %s also drives the weather - Carolina Field Almanac weather stays off", W.conflict)
        return
    end
    if mission:getIsServer() == false then
        -- v0.30 multiplayer: a player's game takes the host's days (sent by CFAMultiplayer) and gives each forecast block
        -- the same high and low the host's game uses; the station list in Settings sends a pick to the host.
        W.clientMode = true
        WeatherObject.activate = Utils.overwrittenFunction(WeatherObject.activate, W.activateWeatherObject)
        W.menuTries = 0
        log("weather: player in a multiplayer game - days come from the host")
        return
    end
    Weather.createRandomWeatherInstance = Utils.overwrittenFunction(Weather.createRandomWeatherInstance, W.createWeatherInstance)
    WeatherObject.activate = Utils.overwrittenFunction(WeatherObject.activate, W.activateWeatherObject)
    if Weather.saveToXMLFile ~= nil then
        Weather.saveToXMLFile = Utils.overwrittenFunction(Weather.saveToXMLFile, W.saveWeather)
    end
    W.active = true
    local loaded = W.load()
    if not loaded then
        -- v0.21.6: new save - pre-select the home station of the state the map's name gives (the player still confirms it)
        local okm, mp, mfrom = true, W.stationFromMapName()
        local ok, code, from = true, W.stateFromMapName()
        if okm and mp ~= nil and W.getStation(mp.id) ~= nil then
            W.stationId = mp.id
            local stn = W.getStation(mp.id)
            W.preselected = string.format("%s, from the map name \"%s\"", (stn ~= nil and W.STATE_NAMES[stn.state]) or "", tostring(mfrom))
            log("weather: map name \"%s\" -> %s station %s (%s)", tostring(mfrom), mp.name, W.stationId, W.getStationText())
        elseif ok and code ~= nil and W.HOME_STATIONS[code] ~= nil and W.getStation(W.HOME_STATIONS[code]) ~= nil then
            W.stationId = W.HOME_STATIONS[code]
            W.preselected = string.format("%s, from the map name \"%s\"", W.STATE_NAMES[code], tostring(from))
            log("weather: map name \"%s\" -> %s home station %s (%s)", tostring(from), code, W.stationId, W.getStationText())
        else
            log("weather: map name gives no US state or known map - default station until the player picks one (Europe and Canada are in the station list)")
        end
    end
    if loaded then
        W.checkSavedMonths()
    end
    W.ensureDays()
    W.stampSeasonNormals()
    W.rebuildForecast()
    W.snapTemperature()
    W.snapOnActivate = true   -- and once more when our first block starts (the save's running block ends within a game minute)
    log("weather: on, station %s (%s), %s", W.stationId, W.getStationText(), loaded and "days loaded" or "new days generated")
    log("weather: today %s", W.getTodayText())
    W.menuTries = 0
end

function W.update(dt)
    -- v0.25.18 (Denton new save 2026-11-11): a new game sets its start month after the mission loads, so days made at load
    -- can carry the wrong month (Aug days in a June game). About once a second, remake any day whose month no longer
    -- fits the game calendar, before crops or insurance use it.
    if W.active then
        W.monthCheckTick = (W.monthCheckTick or 0) + 1
        if W.monthCheckTick >= 60 then
            W.monthCheckTick = 0
            local ok, bad = true, W.checkSavedMonths()
            if ok and bad ~= nil then
                W.ensureDays()
                W.stampSeasonNormals()
                W.rebuildForecast()
                W.snapTemperature()
                log("weather: calendar month changed - days remade, today %s", W.getTodayText())
            end
        end
    end
    if (W.active or W.clientMode) and not W.menuDone and W.menuTries ~= nil then
        W.menuTries = W.menuTries + 1
        if W.menuTries % 30 == 0 then
            local ok, done = true, W.injectMenu()
            if not ok then
                log("weather: settings menu error: %s", tostring(done))
                W.menuDone = true
            elseif done then
                W.menuDone = true
            elseif W.menuTries > 3000 then
                W.menuDone = true
            end
        end
    end
end
