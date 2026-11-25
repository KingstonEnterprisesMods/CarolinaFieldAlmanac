-- Carolina Field Almanac - in-game menu page. By Kingston Enterprises. Mod for Farming Simulator.
-- One page in the game's menu (ESC), with tabs: Notifications, Fields, Hay, Weather, Insurance, Settings, Sources (team design).
CFAMenuFrame = {}
local CFAMenuFrame_mt = Class(CFAMenuFrame, TabbedMenuFrameElement)

CFAMenuFrame.MOD_DIR = g_currentModDirectory
CFAMenuFrame.TAB_NOTICES, CFAMenuFrame.TAB_FIELDS, CFAMenuFrame.TAB_HAY, CFAMenuFrame.TAB_WEATHER = 1, 2, 3, 4
CFAMenuFrame.TAB_INSURANCE, CFAMenuFrame.TAB_SETTINGS, CFAMenuFrame.TAB_SOURCES = 5, 6, 7
CFAMenuFrame.TAB_NAMES = {"Notifications", "Fields", "Hay", "Weather", "Insurance", "Settings", "Sources"}
CFAMenuFrame.TABLES = {"noticesTable", "fieldsTable", "hayTable", "weatherTable", "insuranceTable", "settingsTable", "sourcesTable"}
local MONTHS = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

local function txt(key, fallback)
    if g_i18n ~= nil and g_i18n:hasText(key) then
        return g_i18n:getText(key)
    end
    return fallback
end

local function cToF(c)
    return c * 1.8 + 32
end

function CFAMenuFrame.new(target)
    local self = TabbedMenuFrameElement.new(target, CFAMenuFrame_mt)
    self.currentTab = CFAMenuFrame.TAB_NOTICES
    self.subCategoryTabs = {}
    self.rows = {{}, {}, {}, {}, {}, {}, {}}
    self.insPick = {}   -- fruit -> {plan, cov} picked on the Insurance tab
    self:setMenuButtonInfo({{inputAction = InputAction.MENU_BACK}})
    return self
end

function CFAMenuFrame:onGuiSetupFinished()
    CFAMenuFrame:superClass().onGuiSetupFinished(self)
    self.tables = {}
    self.empties = {}
    for i, id in ipairs(CFAMenuFrame.TABLES) do
        local list = self:getDescendantById(id)
        if list ~= nil then
            list:setDataSource(self)
            list:setDelegate(self)
            self.tables[i] = list
        end
        self.empties[i] = self:getDescendantById(id:gsub("Table", "Empty"))
    end
    self.headerTitleText = self:getDescendantById("headerTitle")
    self.insNote = self:getDescendantById("insuranceNote")
end

function CFAMenuFrame:initialize()
    self.selectorPrefab:unlinkElement()
    FocusManager:removeElement(self.selectorPrefab)
    for i, name in ipairs(CFAMenuFrame.TAB_NAMES) do
        self.subCategoryPaging:addText(tostring(i))
        self.subCategoryTabs[i] = self.selectorPrefab:clone(self.subCategoryBox)
        FocusManager:loadElementFromCustomValues(self.subCategoryTabs[i])
        self.subCategoryTabs[i]:setText(txt("cfa_menu_tab_" .. i, name))
        self.subCategoryTabs[i]:getDescendantByName("background"):setSize(self.subCategoryTabs[i].size[1], self.subCategoryTabs[i].size[2])
        local idx = i
        self.subCategoryTabs[i].onClickCallback = function() self:switchTab(idx) end
    end
    self.subCategoryBox:invalidateLayout()
    self.subCategoryPaging:setSize(self.subCategoryBox.maxFlowSize + 140 * g_pixelSizeScaledX)
end

function CFAMenuFrame:onFrameOpen()
    CFAMenuFrame:superClass().onFrameOpen(self)
    self:collectAll()
    if self.headerTitleText ~= nil then
        local station = ""
        if CFAWeather ~= nil and CFAWeather.getStationText ~= nil then
            local ok, s = true, CFAWeather.getStationText()
            if ok and s ~= nil then station = " - " .. s end
        end
        self.headerTitleText:setText(txt("cfa_menu_title", "Field Almanac") .. station)
    end
    -- open on Notifications when something was missed
    local tab = self.currentTab or 1
    if CarolinaFieldCure ~= nil and (CarolinaFieldCure.unread or 0) > 0 then
        tab = CFAMenuFrame.TAB_NOTICES
    end
    if CFAMenuFrame.forceTab ~= nil then tab = CFAMenuFrame.forceTab CFAMenuFrame.forceTab = nil end   -- v0.27.1 "Pick station now"
    self:switchTab(tab)
end

function CFAMenuFrame:switchTab(tabIndex)
    self.currentTab = tabIndex
    for i = 1, #CFAMenuFrame.TABLES do
        local c = self["tabContainer" .. i] or self:getDescendantById("tabContainer" .. i)
        if c ~= nil then c:setVisible(i == tabIndex) end
    end
    for i, tab in ipairs(self.subCategoryTabs) do
        tab:setSelected(i == tabIndex)
    end
    if tabIndex == CFAMenuFrame.TAB_NOTICES and CarolinaFieldCure ~= nil then
        CarolinaFieldCure.unread = 0   -- seeing the list counts as reading it
        CarolinaFieldCure.rainAlert = {}   -- v0.23.3: and clears the rain line in the Field Cure box
    end
    self:collectTab(tabIndex)   -- v0.21.2: never show (or act on) rows read before a change on another tab
    local list = self.tables[tabIndex]
    if list ~= nil then
        list:reloadData()
    end
    self:updateButtons()
    local empty = self.empties[tabIndex]
    if empty ~= nil then
        local none = #self.rows[tabIndex] == 0
        empty:setVisible(none)
        if none then
            empty:setText(({txt("cfa_menu_none_notices", "No notices yet."),
                self.myFieldsOnly and txt("cfa_menu_none_mine", "None of your fields has a tracked crop yet.") or txt("cfa_menu_none_fields", "No fields tracked yet - crops show here once they are planted."),
                txt("cfa_menu_none_hay", "No hay curing - cut hay shows here."),
                txt("cfa_menu_none_weather", "Weather part is off."),
                txt("cfa_menu_none_insurance", "No crop insurance data for the crops on this map."),
                "", ""})[tabIndex])
        end
    end
end

function CFAMenuFrame:onClickTab(state)
    self:switchTab(state)
end

-- ---------------------------------------------------------------- data

function CFAMenuFrame:collectAll()
    for i = 1, #CFAMenuFrame.TABLES do
        self:collectTab(i)
    end
end

CFAMenuFrame.COLLECT = {"collectNotices", "collectFields", "collectHay", "collectWeather", "collectInsurance", "collectSettings", "collectSources"}

function CFAMenuFrame:collectTab(i)
    local ok, rows = true, self[CFAMenuFrame.COLLECT[i]](self)
    self.rows[i] = (ok and rows) or {}
    if not ok then
        Logging.error("[CarolinaFieldAlmanac] menu tab %d: %s", i, tostring(rows))
    end
end

-- Re-read one tab and redraw it, keeping the selected row.
function CFAMenuFrame:refreshTab(i)
    self:collectTab(i)
    local list = self.tables[i]
    if list ~= nil then list:reloadData() end
    self:updateButtons()
end

function CFAMenuFrame:selectedRow(tab)
    local list = self.tables[tab]
    if list == nil then return nil end
    local idx = list.selectedIndex or (list.getSelectedIndexInSection ~= nil and list:getSelectedIndexInSection()) or 0
    return self.rows[tab][idx]
end

function CFAMenuFrame:onListSelectionChanged(list, section, index)
    local tab = self:tabOfList(list)
    if tab == CFAMenuFrame.TAB_INSURANCE or tab == CFAMenuFrame.TAB_SETTINGS then
        self:updateButtons()
    end
end

function CFAMenuFrame:onSettingDoubleClick()
    self:onSettingChange()
end

-- Bottom buttons per tab.
function CFAMenuFrame:updateButtons()
    local back = {inputAction = InputAction.MENU_BACK}
    local info = {back}
    local tab = self.currentTab
    if tab == CFAMenuFrame.TAB_INSURANCE then
        local row = self:selectedRow(tab)
        local function add(action, text, fn)
            info[#info + 1] = {inputAction = action, text = text, showWhenPaused = true, callback = fn}
        end
        if row ~= nil and row.kind == "crop" then
            if row.canBuy then add(InputAction.MENU_ACTIVATE, txt("cfa_ins_buy", "Buy policy"), function() self:onInsuranceActivate() end) end
            if row.canUpdate then add(InputAction.MENU_ACTIVATE, txt("cfa_ins_update", "Update policy"), function() self:onInsuranceActivate() end) end
            if row.canCancel then add(InputAction.MENU_ACTIVATE, txt("cfa_ins_cancel", "Cancel policy"), function() self:onInsuranceActivate() end) end
            add(InputAction.MENU_EXTRA_1, txt("cfa_ins_plan", "Plan"), function() self:onInsurancePlan() end)
            if not row.canCancel then add(InputAction.MENU_EXTRA_2, txt("cfa_ins_cov", "Coverage level"), function() self:onInsuranceCoverage() end) end
        elseif row ~= nil and row.canClaim then
            add(InputAction.MENU_ACTIVATE, txt("cfa_ins_claim", "File claim"), function() self:onInsuranceActivate() end)
        end
    elseif tab == CFAMenuFrame.TAB_FIELDS then
        info[#info + 1] = {inputAction = InputAction.MENU_EXTRA_1, showWhenPaused = true,
            text = self.myFieldsOnly and txt("cfa_show_all", "Show all fields") or txt("cfa_show_mine", "Show only my fields"),
            callback = function()
                self.myFieldsOnly = not self.myFieldsOnly
                self:refreshTab(CFAMenuFrame.TAB_FIELDS)
            end}
    elseif tab == CFAMenuFrame.TAB_SETTINGS then
        local row = self:selectedRow(tab)
        if row ~= nil and row.change ~= nil then
            info[#info + 1] = {inputAction = InputAction.MENU_ACTIVATE, text = txt("cfa_set_change", "Change"), showWhenPaused = true,
                callback = function() self:onSettingChange() end}
        end
    end
    if tab == CFAMenuFrame.TAB_INSURANCE and self.insNote ~= nil then
        local row = self:selectedRow(tab)
        local plan = nil
        if row ~= nil and row.kind == "crop" then
            local pk = self:pick(row.fruit)
            plan = pk ~= nil and pk.plan or nil
        elseif row ~= nil and row.kind == "field" and CFACrops.fields[row.id] ~= nil and CFACrops.fields[row.id].ins ~= nil then
            plan = CFACrops.fields[row.id].ins.plan
        end
        self.insNote:setText((CFAMenuFrame.PLAN_TEXT[plan or ""] or "") .. CFAMenuFrame.pickNote())
    end
    self:setMenuButtonInfo(info)
    self:setMenuButtonInfoDirty()
end

-- ---------------------------------------------------------------- insurance tab
CFAMenuFrame.PLAN_TEXT = {
    YP = "Yield Protection: pays when your harvest falls below your coverage % of a normal crop, valued at the price when you planted. ",
    RP = "Revenue Protection: pays when your crop's value (yield x harvest price) falls short - a bad crop, a price drop, or both. If the price rises by harvest, your guarantee rises too. ",
    RPHPE = "RP - Harvest Price Exclusion: like RP, but the guarantee stays at the planting price even if prices rise. Costs less. ",
    APH = "APH: yield-only coverage (potatoes, sugar beets, tobacco). ",
    CANCEL = "Cancel: fields already covered stay covered until harvest; new plantings are not covered. ",
    pick = "You pick the plan and the coverage level (50-85 %) - the premium and liability come from those (USDA RMA).",
}
-- v0.29.1 (team 2026-11-15): the bottom note says where this station's insurance numbers come from.
CFAMenuFrame.PICK_EU = {
    FR = "France: one plan for all crops at 75 % coverage (25 % deductible). Premium and insured value from France's CCR / Ministry of Agriculture 2020 - European sources, not USDA.",
    PL = "Poland: one subsidized plan at 90 % coverage (10 % deductible). Premium and insured value from Poland's Ministry of Agriculture 2023-2024 - European sources, not USDA.",
    DE = "Germany: hail insurance only - 5 % franchise, pays up to 95 % (80 % for vegetables). Premium and insured value from Vereinigte Hagel 2024 and Hagelgilde - European sources, not USDA.",
}
function CFAMenuFrame.pickNote()
    local C = CFACrops
    if C ~= nil and C.inEurope ~= nil and C.inEurope() then
        return CFAMenuFrame.PICK_EU[C.euCountry() or ""]
            or "No crop insurance numbers for this country yet, so insurance is off here (Rule #1)."
    end
    return CFAMenuFrame.PLAN_TEXT.pick
end
-- Top rows: one per crop (buy / change / cancel the crop policy). Below: each covered or growing field.

local function covText(c) return c ~= nil and string.format("%.0f %%", c * 100) or "-" end

-- The plan and coverage picked on a crop row (starts at the policy in force, or RP 75 % where RMA has it).
function CFAMenuFrame:pick(fruit)
    local C = CFACrops
    local d = C.insuranceFor(fruit)
    if d == nil then return nil end
    local pk = self.insPick[fruit]
    if pk == nil then
        local pol = C.myPolicy(fruit)
        pk = pol ~= nil and {plan = pol.plan, cov = pol.cov} or {plan = (C.planData(fruit, "RP") ~= nil and "RP" or d.plans[1].plan), cov = 0.75}
        self.insPick[fruit] = pk
    end
    if pk.plan == "CANCEL" then
        if C.myPolicy(fruit) ~= nil then return pk end
        pk.plan = d.plans[1].plan
    end
    if C.planData(fruit, pk.plan) == nil then pk.plan = d.plans[1].plan end
    if C.rowFor(fruit, pk.plan, pk.cov) == nil then
        local rows = C.planData(fruit, pk.plan).rows
        local best = rows[#rows]
        for _, r in ipairs(rows) do if r.cov <= pk.cov + 0.001 then best = r end end
        pk.cov = best.cov
    end
    return pk
end

function CFAMenuFrame:insuredFruits()
    local list = {}
    local C = CFACrops
    if CFAInsurance == nil then return list end
    local keys = {}
    for fruit, d in pairs(CFAInsurance) do keys[fruit] = d end
    for fruit in pairs(CFAInsurance.PL_CROPS or {}) do keys[fruit] = CFAInsurance.PL_ALL end   -- v0.28 Poland
    for fruit in pairs(CFAInsurance.DE_CROPS or {}) do keys[fruit] = CFAInsurance.DE_HAIL end   -- v0.28 Germany
    if CFAInsurance.FR_ALL ~= nil then for fruit in pairs(C.crops) do if keys[fruit] == nil then keys[fruit] = CFAInsurance.FR_ALL end end end   -- v0.28 France (all crops)
    for fruit, d in pairs(keys) do
        if type(d) == "table" and d.plans ~= nil and C.crops[fruit] ~= nil and C.insuranceFor(fruit) ~= nil
            and (g_fruitTypeManager == nil or g_fruitTypeManager:getFruitTypeByName(fruit) ~= nil) then
            list[#list + 1] = fruit
        end
    end
    table.sort(list, function(a, b) return C.cropTitle(a) < C.cropTitle(b) end)
    return list
end

function CFAMenuFrame:collectInsurance()
    local rows = {}
    local C = CFACrops
    if C == nil or C.fields == nil or C.insuranceFor == nil then return rows end
    for _, fruit in ipairs(self:insuredFruits()) do
        local d = C.insuranceFor(fruit)
        local pol = C.myPolicy(fruit)
        local pk = self:pick(fruit)
        local r = C.rowFor(fruit, pk.plan, pk.cov)
        local row = {C.cropTitle(fruit), pk.plan == "CANCEL" and "Cancel policy" or C.planName(pk.plan), pk.plan == "CANCEL" and "-" or covText(pk.cov), "-",
            r ~= nil and (C.money(r.farmer, 2) .. "/ac") or "-", r ~= nil and (C.money(r.liab) .. "/ac") or "-", "-", "",
            kind = "crop", fruit = fruit}
        if pol ~= nil and pk.plan == "CANCEL" then
            row[8] = string.format("In force: %s %.0f %% - press Cancel policy to end it", pol.plan, pol.cov * 100)
            row.canCancel = true
        elseif pol ~= nil then
            if pol.plan == pk.plan and math.abs(pol.cov - pk.cov) < 0.001 then
                row[8] = "Policy in force - renews each season"
            else
                row[8] = string.format("In force: %s %.0f %% - press Update to change", pol.plan, pol.cov * 100)
                row.canUpdate = true
            end
        elseif not C.stationConfirmed then
            row[8] = "Pick your weather station first - insurance is priced by location"
        else
            row[8] = string.format("No policy (%s) - press Buy", d.src or ("RMA " .. tostring(d.state) .. " data"))
            row.canBuy = true
        end
        rows[#rows + 1] = row
    end
    local ids = {}
    for id, rec in pairs(C.fields) do
        if ((not rec.done and C.insuranceFor(rec.fruit) ~= nil) or (rec.ins ~= nil and rec.ins.paid == nil)) and (C.isMine(id) or rec.ins ~= nil) then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
    for _, id in ipairs(ids) do
        local rec = C.fields[id]
        local p = rec.ins
        local acres = p ~= nil and p.acres or C.fieldAcres(id)
        local row = {string.format("  Field %s - %s", tostring(id), C.cropTitle(rec.fruit)), "-", "-", acres ~= nil and string.format("%.1f", acres) or "?",
            "-", "-", string.format("%.1f %%", C.totalFactor(rec) * 100), "", kind = "field", id = id}
        if p ~= nil then
            row[2] = C.planName(p.plan)
            row[3] = covText(p.cov)
            row[5] = C.money(p.premium) .. " paid"
            row[6] = C.money(p.liab * p.acres)
            local owed = C.claimAmount(rec)
            if rec.ready or rec.done then
                row[8] = string.format("Harvest ready - claim pays %s now", C.money(owed))
                row.canClaim = true
            else
                row[8] = string.format("Covered - would pay %s now", C.money(owed))
            end
        elseif rec.forageYearCovered then
            row[8] = "This year's forage policy is on the field's first cutting"
        elseif C.myPolicy(rec.fruit) == nil then
            -- v0.25.23: say plainly why a field is not covered and when it will be
            if rec.grace and not C.hasDamage(rec) and (rec.startCover or not rec.ready) then
                row[8] = rec.startCover and "Not covered - start-up cover: buy the crop policy this season to cover it (game rule)"
                    or "Not covered - first season: buy the crop policy to cover it"
            elseif rec.ready then
                row[8] = "Harvest-ready - too late to insure; buy a policy to cover your next planting"
            else
                row[8] = "Not covered - no policy; buy one before you plant"
            end
        elseif rec.grace and C.hasDamage(rec) then
            row[8] = "Not covered - damage was recorded before the policy"
        elseif rec.ready then
            row[8] = "Harvest-ready - too late to insure; covered from your next planting"
        else
            row[8] = "Not covered - planted before the policy or bought with the crop in; covered from your next planting"
        end
        rows[#rows + 1] = row
    end
    return rows
end

local function cycle(list, cur, same)
    for i, v in ipairs(list) do
        if same(v, cur) then return list[i + 1] or list[1] end
    end
    return list[1]
end

function CFAMenuFrame:onInsurancePlan()
    local row = self:selectedRow(CFAMenuFrame.TAB_INSURANCE)
    if row == nil or row.kind ~= "crop" then return end
    local d = CFACrops.insuranceFor(row.fruit)
    local pk = self:pick(row.fruit)
    local choices = {}
    for _, p in ipairs(d.plans) do choices[#choices + 1] = p end
    if CFACrops.myPolicy(row.fruit) ~= nil then choices[#choices + 1] = {plan = "CANCEL"} end
    pk.plan = cycle(choices, pk.plan, function(v, c) return v.plan == c end).plan
    self:pick(row.fruit)
    self:refreshTab(CFAMenuFrame.TAB_INSURANCE)
end

function CFAMenuFrame:onInsuranceCoverage()
    local row = self:selectedRow(CFAMenuFrame.TAB_INSURANCE)
    if row == nil or row.kind ~= "crop" then return end
    local pk = self:pick(row.fruit)
    if pk.plan == "CANCEL" then return end
    local rows = CFACrops.planData(row.fruit, pk.plan).rows
    pk.cov = cycle(rows, pk.cov, function(v, c) return math.abs(v.cov - c) < 0.001 end).cov
    self:refreshTab(CFAMenuFrame.TAB_INSURANCE)
end

function CFAMenuFrame:onInsuranceActivate()
    local row = self:selectedRow(CFAMenuFrame.TAB_INSURANCE)
    if row == nil then return end
    -- v0.30 multiplayer: the host does it for this player's farm (in single player: right now, same as before)
    if row.kind == "crop" and row.canCancel then
        CFAMP.request("cancel", {fruit = row.fruit})
        self.insPick[row.fruit] = nil
    elseif row.kind == "crop" and (row.canBuy or row.canUpdate) then
        local pk = self:pick(row.fruit)
        CFAMP.request("buy", {fruit = row.fruit, plan = pk.plan, cov = pk.cov})
    elseif row.kind == "field" and row.canClaim then
        CFAMP.request("claim", {id = row.id})
    end
    self:refreshTab(CFAMenuFrame.TAB_INSURANCE)
end


-- ---------------------------------------------------------------- settings tab

CFAMenuFrame.POPUP_SECS = {5, 10, 15, 20}

function CFAMenuFrame:collectSettings()
    local rows = {}
    local C = CFACrops
    if C ~= nil and C.DAMAGE ~= nil then
        for _, d in ipairs(C.DAMAGE) do
            local key = d.key
            -- v0.21.2: while an insured crop is in the field a switch can only go back ON (more damage), never OFF.
            -- The lock is checked again at the moment of the change, not only when the list was drawn.
            local locked = C.settingsLocked ~= nil and C.settingsLocked()
            local canChange = not locked or not C.on(key)
            local note
            if locked and C.on(key) then
                note = "Locked ON while an insured crop is in the field - unlocks when every claim is settled"
            elseif locked then
                note = "Off - can only be turned back ON while an insured crop is in the field"
            else
                note = C.on(key) and "Taken off the harvest" or "Still tracked, not taken off the harvest or counted for insurance"
            end
            rows[#rows + 1] = {d.name .. " damage", (C.on(key) and "On" or "Off") .. ((locked and C.on(key)) and " (locked)" or ""), note,
                change = canChange and function()
                    if C.on(key) then
                        if C.settingsLocked ~= nil and C.settingsLocked() then return end   -- never OFF while insured
                        CFAMP.request("damage", {key = key, on = false})   -- v0.30: shared - the host changes it (host / admin)
                        if not CFAMP.isClientOnly() then return end
                        if CFAMP.canAdmin() then C.settings.off[key] = true end   -- shows now; the host's value follows
                    else
                        CFAMP.request("damage", {key = key, on = true})
                        if CFAMP.isClientOnly() and CFAMP.canAdmin() then C.settings.off[key] = nil end
                    end
                end or nil}
        end
    end
    local cfc = CarolinaFieldCure
    if cfc ~= nil and cfc.settings ~= nil then
        local MODES = {popup = "Pop-ups", summary = "Summary", menu = "Menu only"}
        local NOTES = {popup = "Every notice shows on screen",
            summary = "Rain warnings pop up right away; the rest in one message per game hour",
            menu = "No pop-ups - read them on the Notifications tab"}
        local mode = cfc.settings.noticeMode or "popup"
        rows[#rows + 1] = {"Notices", MODES[mode] or mode, NOTES[mode] or "",
            change = function()
                local order = {"popup", "summary", "menu"}
                local cur = cfc.settings.noticeMode or "popup"
                local nxt = order[1]
                for i, m in ipairs(order) do if m == cur then nxt = order[i + 1] or order[1] break end end
                cfc.settings.noticeMode = nxt
                if cfc.savePlayerPrefs ~= nil then cfc.savePlayerPrefs() end   -- v0.30: each player's own
            end}
        rows[#rows + 1] = {"Pop-up time", string.format("%d seconds", cfc.settings.popupSec or 10), "How long notices stay on screen (5, 10, 15, 20)",
            change = function()
                local secs, cur = CFAMenuFrame.POPUP_SECS, cfc.settings.popupSec or 10
                local nxt = secs[1]
                for i, s in ipairs(secs) do if s == cur then nxt = secs[i + 1] or secs[1] break end end
                cfc.settings.popupSec = nxt
                if cfc.savePlayerPrefs ~= nil then cfc.savePlayerPrefs() end
            end}
        local cond = cfc.settings.conditioned ~= false
        rows[#rows + 1] = {"Mower conditions hay", cond and "Yes" or "No",
            cond and "Yes: your mower crushes the stems (mower-conditioner / haybine) so water gets out - hay dries at the full rate"
                or "No: plain mower - stems hold water longer, hay dries slower on the 1st and 2nd cut of the year (USDA: 44 % and 27 %)",
            change = function()   -- v0.30: shared - the host changes it (host / admin)
                local v = not (cfc.settings.conditioned ~= false)
                CFAMP.request("cure", {key = "conditioned", value = v})
                if CFAMP.isClientOnly() and CFAMP.canAdmin() then cfc.settings.conditioned = v end
            end}
        local light = cfc.settings.light == true
        rows[#rows + 1] = {"Light mode (big farms / slower PCs)", light and "On" or "Off",
            light and "On: Field Cure does a quarter of its work each frame. Hay dries exactly the same; the boxes, map icons and pop-ups update a few seconds later."
                or "Off: Field Cure updates about once a second. Turn On if you have a lot of cut hay at once or a slower PC.",
            change = function()   -- v0.30: the host's work, so the host's setting
                local v = not (cfc.settings.light == true)
                CFAMP.request("cure", {key = "light", value = v})
                if CFAMP.isClientOnly() and CFAMP.canAdmin() then cfc.settings.light = v end
            end}
    end
    local W = CFAWeather
    if W ~= nil then
        local s = W.stationId or "-"
        if W.getStationText ~= nil then
            local ok, v = true, W.getStationText()
            if ok and v ~= nil then s = v end
        end
        if CFACrops ~= nil and not CFACrops.stationConfirmed then
            rows[#rows + 1] = {"Weather station", s .. " (not confirmed)",
                "Press Change to use this station, or pick yours on the game's Settings page (Field Almanac)",
                change = function() CFAMP.request("confirm", {why = "confirmed on the Settings tab"}) end}
        else
            rows[#rows + 1] = {"Weather station", s, "Change it on the game's Settings page (Field Almanac) - applies from that day on"}
        end
    end
    return rows
end

function CFAMenuFrame:onSettingChange()
    local row = self:selectedRow(CFAMenuFrame.TAB_SETTINGS)
    if row == nil or row.change == nil then return end
    row.change()
    self:refreshTab(CFAMenuFrame.TAB_SETTINGS)
end

-- ---------------------------------------------------------------- sources tab

function CFAMenuFrame:collectSources()
    local rows = {}
    for _, r in ipairs(CFASources or {}) do
        rows[#rows + 1] = {r[1], r[2], r[3], r[4]}
    end
    return rows
end

function CFAMenuFrame:collectNotices()
    local rows = {}
    local cfc = CarolinaFieldCure
    if cfc == nil or cfc.notices == nil then return rows end
    for i, n in ipairs(cfc.visibleNotices ~= nil and cfc.visibleNotices() or cfc.notices) do   -- newest first (v0.30: my farm's)
        rows[#rows + 1] = {n.date or "", (i <= (cfc.unread or 0) and "(new) " or "") .. (n.text or ""), kind = n.kind}
    end
    return rows
end

-- v0.30 multiplayer: Own / another player's farm (its name) / NPC
function CFAMenuFrame.ownerText(id)
    local C = CFACrops
    if C.isMine(id) then return txt("cfa_owner_own", "Own") end
    local owner = C.fieldOwner(id)
    if owner ~= nil and owner ~= 0 and g_farmManager ~= nil and g_farmManager.getFarmById ~= nil then
        local ok, farm = true, g_farmManager.getFarmById(g_farmManager, owner)
        if ok and farm ~= nil and farm.isSpectator ~= true then return tostring(farm.name or ("Farm " .. owner)) end
    end
    return txt("cfa_owner_npc", "NPC")
end

function CFAMenuFrame:collectFields()
    local rows = {}
    local C = CFACrops
    if C == nil or C.fields == nil then return rows end
    -- v0.21.5 (team): Owner column, your fields first, button to show only yours
    local ids = {}
    for id in pairs(C.fields) do
        if not self.myFieldsOnly or C.isMine(id) then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b)
        local ma, mb = C.isMine(a), C.isMine(b)
        if ma ~= mb then return ma end
        return (tonumber(a) or 0) < (tonumber(b) or 0)
    end)
    for _, id in ipairs(ids) do
        local rec = C.fields[id]
        local crop = C.cropFor(rec.fruit, rec.plantedMonth)
        local stage = "-"
        if crop ~= nil then
            local si = C.currentStage(crop, rec)
            if si > 0 then stage = crop.stages[si].name end
        end
        local planted = rec.plantedMonth ~= nil and MONTHS[rec.plantedMonth] or "?"
        if rec.backfill ~= nil and rec.backfill ~= "none" then
            planted = planted .. " (NASS " .. (rec.backfill:match("^(%a+ [%d/]+)") or "") .. ")"
        end
        local losses = {}
        local function add(name, v, key)
            if (v or 0) >= 0.05 then
                local off = C.on ~= nil and not C.on(key)
                losses[#losses + 1] = string.format("%s %.1f%%%s", name, v, off and " (off)" or "")
            end
        end
        add(txt("cfa_loss_freeze", "freeze"), rec.loss, "freeze")
        add(txt("cfa_loss_rain", "rain"), rec.weatherLoss, "rain")
        add(txt("cfa_loss_hail", "hail"), rec.hailLoss, "hail")
        add(txt("cfa_loss_wind", "wind"), rec.windLoss, "wind")
        add(txt("cfa_loss_tornado", "tornado"), rec.tornadoLoss, "tornado")
        add(txt("cfa_loss_rmacold", "freeze/frost (USDA)"), rec.rmaColdLoss, "freeze")
        add(txt("cfa_loss_hurricane", "hurricane"), rec.hurricaneLoss, "hurricane")
        add(txt("cfa_loss_heat", "heat"), rec.heatLoss, "heat")
        add(txt("cfa_loss_drought", "drought"), rec.droughtLoss, "drought")
        add(txt("cfa_loss_waterlog", "waterlog"), rec.wlLoss, "waterlog")
        add(txt("cfa_loss_delay", "harvest delay"), rec.delayLoss, "delay")
        add(txt("cfa_loss_winter", "winterkill"), rec.winterLoss, "winter")
        local wt = CFAWinter ~= nil and CFAWinter.fieldText(id) or nil
        if wt ~= nil then stage = (stage ~= "-" and (stage .. ", ") or "") .. wt end
        local status = (not C.stationConfirmed) and txt("cfa_status_wait", "Waiting for station") or rec.done and txt("cfa_status_done", "Done") or rec.ready and txt("cfa_status_ready", "Harvest ready") or txt("cfa_status_growing", "Growing")
        local fruitName = rec.fruit
        local desc = g_fruitTypeManager ~= nil and g_fruitTypeManager:getFruitTypeByName(rec.fruit) or nil
        if desc ~= nil and desc.fillType ~= nil and desc.fillType.title ~= nil then fruitName = desc.fillType.title end
        rows[#rows + 1] = {tostring(id), CFAMenuFrame.ownerText(id), fruitName, planted, string.format("%.0f", rec.dd or 0), stage,
            #losses > 0 and table.concat(losses, ", ") or txt("cfa_loss_none", "none"), status}
    end
    return rows
end

function CFAMenuFrame:collectHay()
    local rows = {}
    local cfc = CarolinaFieldCure
    if cfc == nil or cfc.getFieldSummaries == nil then return rows end
    local ids = {}
    local sums = cfc.getFieldSummaries()
    for id in pairs(sums) do ids[#ids + 1] = id end
    table.sort(ids)
    local ha = cfc.CELL_SIZE * cfc.CELL_SIZE / 10000
    for _, id in ipairs(ids) do
      local s = sums[id]
      if not (cfc.isTiny ~= nil and cfc.isTiny(s)) then
        local readyText = cfc.getReadyText(s)
        local area = g_i18n ~= nil and g_i18n.formatArea ~= nil and g_i18n:formatArea(s.total * ha, 1) or string.format("%.1f ha", s.total * ha)
        rows[#rows + 1] = {cfc.getFieldLabel(id, s), area, readyText, string.format("%.0f %% / %.0f %%", s.minM * 100, s.maxM * 100),
            cfc.getFieldStatus(s), s.rained and txt("cfa_hay_soaked", "Soaked - drying back") or "-"}
      end
    end
    return rows
end

function CFAMenuFrame:collectWeather()
    local rows = {}
    local W = CFAWeather
    if W == nil or not (W.active or W.clientMode) or W.days == nil then return rows end
    local env = g_currentMission.environment
    local today = env.currentMonotonicDay or 0
    local dpp = math.max(1, env.daysPerPeriod or 1)
    local dip = env.currentDayInPeriod or 1
    for day = today, today + (W.DAYS_AHEAD or 12) do
        local d = W.days[day]
        if d ~= nil then
            local dom = ((dip - 1 + (day - today)) % dpp) + 1
            local label = string.format("%s %d", MONTHS[d.month] or "?", dom)
            if day == today then label = label .. " (" .. txt("cfa_today", "today") .. ")" end
            local SKY = {SUN = txt("cfa_sky_sun", "Sunny"), PARTLY = txt("cfa_sky_partly", "Partly cloudy"), CLOUDY = txt("cfa_sky_cloudy", "Cloudy")}
            local rain, rtime, storm, sky = "-", "-", "-", SKY[d.sky or ""] or d.sky or "-"
            if d.wet then
                rain = string.format("%.2f in", (d.rainMM or 0) / 25.4)
                if d.rainStart ~= nil and d.rainEnd ~= nil then
                    rtime = string.format("%02d:%02d - %02d:%02d", math.floor(d.rainStart), math.floor((d.rainStart % 1) * 60),
                        math.floor(d.rainEnd), math.floor((d.rainEnd % 1) * 60))
                end
                storm = d.snow and txt("cfa_snow", "Snow") or d.thunder and txt("cfa_thunder", "Thunder") or txt("cfa_rain", "Rain")
                sky = d.snow and txt("cfa_snow", "Snow") or txt("cfa_rain", "Rain")   -- v0.29.9: the day's own type, not "Rain or snow"
            end
            rows[#rows + 1] = {label, string.format("%.0f / %.0f F", cToF(d.hiC), cToF(d.loC)), rain, rtime, storm, sky}
        end
    end
    return rows
end

-- ---------------------------------------------------------------- list data source

CFAMenuFrame.COLUMNS = {
    {"colDate", "colText"},
    {"colField", "colOwner", "colCrop", "colPlanted", "colDD", "colStage", "colLoss", "colStatus"},
    {"colFarmland", "colArea", "colReady", "colRange", "colState", "colRain"},
    {"colDay", "colTemp", "colRainAmt", "colRainTime", "colStorm", "colSky"},
    {"colName", "colPlan", "colCov", "colAcres", "colPrem", "colLiab", "colKept", "colIns"},
    {"colSetting", "colValue", "colNote"},
    {"colTopic", "colCrops", "colNums", "colSrc"},
}

function CFAMenuFrame:tabOfList(list)
    for i, l in pairs(self.tables) do
        if l == list then return i end
    end
    return self.currentTab
end

function CFAMenuFrame:getNumberOfItemsInSection(list, section)
    return #self.rows[self:tabOfList(list)]
end

function CFAMenuFrame:populateCellForItemInSection(list, section, index, cell)
    local tab = self:tabOfList(list)
    local row = self.rows[tab][index]
    if row == nil then return end
    for c, name in ipairs(CFAMenuFrame.COLUMNS[tab]) do
        local el = cell:getDescendantByName(name)
        if el ~= nil then
            el:setText(row[c] or "")
            if tab == CFAMenuFrame.TAB_NOTICES then
                if row.kind == "warning" then
                    el:setTextColor(1, 0.35, 0.3, 1)
                elseif row.kind == "ok" then
                    el:setTextColor(0.55, 0.9, 0.35, 1)
                else
                    el:setTextColor(1, 1, 1, 1)
                end
            end
        end
    end
end

-- ---------------------------------------------------------------- add the page to the game's menu (ESC)

CFAMenu = {}

function CFAMenu.addPage()
    local inGameMenu = g_gui.screenControllers[InGameMenu]
    if inGameMenu == nil then return end
    local frame = CFAMenuFrame.new()
    CFAMenu.frame = frame
    g_gui:loadProfiles(CFAMenuFrame.MOD_DIR .. "gui/cfaGuiProfiles.xml")
    g_gui:loadGui(CFAMenuFrame.MOD_DIR .. "gui/CFAMenuFrame.xml", "cfaMenuFrame", frame, true)

    local pageName = "cfaMenuFrame"
    inGameMenu.controlIDs[pageName] = nil
    local insertPos = 2
    for i = 1, #inGameMenu.pagingElement.elements do
        if inGameMenu.pagingElement.elements[i] == inGameMenu["pageStatistics"] then
            insertPos = i
            break
        end
    end
    inGameMenu[pageName] = frame
    inGameMenu.pagingElement:addElement(frame)
    inGameMenu:exposeControlsAsFields(pageName)
    for i = 1, #inGameMenu.pagingElement.elements do
        if inGameMenu.pagingElement.elements[i] == frame then
            table.remove(inGameMenu.pagingElement.elements, i)
            table.insert(inGameMenu.pagingElement.elements, insertPos, frame)
            break
        end
    end
    for i = 1, #inGameMenu.pagingElement.pages do
        local child = inGameMenu.pagingElement.pages[i]
        if child.element == frame then
            table.remove(inGameMenu.pagingElement.pages, i)
            table.insert(inGameMenu.pagingElement.pages, insertPos, child)
            break
        end
    end
    inGameMenu.pagingElement:updateAbsolutePosition()
    inGameMenu.pagingElement:updatePageMapping()
    inGameMenu:registerPage(frame, insertPos, function() return true end)
    inGameMenu:addPageTab(frame, Utils.getFilename("gui/cfa_menu_icon.dds", CFAMenuFrame.MOD_DIR), GuiUtils.getUVs({0, 0, 1024, 1024}))
    for i = 1, #inGameMenu.pageFrames do
        if inGameMenu.pageFrames[i] == frame then
            table.remove(inGameMenu.pageFrames, i)
            table.insert(inGameMenu.pageFrames, insertPos, frame)
            break
        end
    end
    inGameMenu:rebuildTabList()
    frame:initialize()
end

function CFAMenu.removePage()
    local inGameMenu = g_gui.screenControllers[InGameMenu]
    local frame = CFAMenu.frame
    if inGameMenu == nil or frame == nil then return end
    for i = #inGameMenu.pagingElement.elements, 1, -1 do
        if inGameMenu.pagingElement.elements[i] == frame then table.remove(inGameMenu.pagingElement.elements, i) end
    end
    for i = #inGameMenu.pagingElement.pages, 1, -1 do
        if inGameMenu.pagingElement.pages[i].element == frame then table.remove(inGameMenu.pagingElement.pages, i) end
    end
    for i = #inGameMenu.pageFrames, 1, -1 do
        if inGameMenu.pageFrames[i] == frame then table.remove(inGameMenu.pageFrames, i) end
    end
    inGameMenu["cfaMenuFrame"] = nil
    do (function() inGameMenu:rebuildTabList() end)() end
    CFAMenu.frame = nil
end
