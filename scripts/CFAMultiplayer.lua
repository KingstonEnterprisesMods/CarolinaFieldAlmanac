-- Carolina Field Almanac - multiplayer (v0.30.0, team 2026-11-19: host in game, same farm or separate farms)
--
-- How it works:
--   * The host (server) runs everything: weather days, crop clocks and damage, hay curing, insurance premiums and claims, saves.
--     Nothing changes on that side - it is the same code single player uses.
--   * About every 2 seconds the host compares what the menus need (weather days, crop records, policies, hay summaries,
--     notices, shared settings) with what it last sent, and sends only what changed to the other players.
--   * A player who joins asks the host for everything once ("full").
--   * Buttons a player presses (station, settings, buy / cancel a policy, file a claim) go to the host as a request; the host
--     checks them and does them for that player's farm. Station and shared settings: host or admin only.
--   * Separate farms: policies, premiums, claims and notices belong to a farm; each player sees and pays for their own farm.
-- In single player none of this runs (no network, no extra work).

CFAMP = {}
local MP = CFAMP

MP.SEND_MS = 2000          -- how often the host looks for changes (real time)
MP.CHUNK = 3000            -- characters per network message
MP.cache = {}              -- host: channel -> key -> last sent encoding
MP.inbox = {}              -- player: message id -> parts
MP.msgId = 0
MP.timer = 0
MP.requestedFull = false
MP.gotFull = {}

local function log(fmt, ...)
    Logging.info("[CarolinaFieldAlmanac] mp: " .. fmt, ...)
end

-- ---------------------------------------------------------------- who / where

function MP.isMP()
    local m = g_currentMission
    local d = m ~= nil and m.missionDynamicInfo or nil
    return d ~= nil and d.isMultiplayer == true
end

function MP.isServer()
    return g_currentMission ~= nil and g_currentMission:getIsServer()
end

-- a player (not the host) in a multiplayer game
function MP.isClientOnly()
    return MP.isMP() and not MP.isServer()
end

function MP.myFarm()
    if CFACrops ~= nil and CFACrops.playerFarmId ~= nil then return CFACrops.playerFarmId() end
    return 1
end

-- notices / rows that belong to a farm: nil or 0 = everyone
function MP.forMe(farmId)
    return farmId == nil or farmId == 0 or farmId == MP.myFarm()
end

-- host or admin (master user) may change the station and the shared settings
function MP.canAdmin()
    if not MP.isMP() or MP.isServer() then return true end
    local m = g_currentMission
    if m ~= nil and m.isMasterUser ~= nil then return m.isMasterUser == true end
    return true
end

-- ---------------------------------------------------------------- encode / decode (plain data only, never run as code)

local fmt = string.format
local function enc(v, out, depth)
    local t = type(v)
    if t == "nil" then out[#out + 1] = "n"
    elseif t == "boolean" then out[#out + 1] = v and "T" or "F"
    elseif t == "number" then
        if v ~= v then out[#out + 1] = "f0;"
        elseif v == math.huge then out[#out + 1] = "f1e999;"
        elseif v == -math.huge then out[#out + 1] = "f-1e999;"
        elseif v == math.floor(v) and math.abs(v) < 2 ^ 53 then out[#out + 1] = fmt("i%d;", v)
        else out[#out + 1] = fmt("f%.10g;", v) end
    elseif t == "string" then out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "table" then
        if depth > 12 then out[#out + 1] = "n" return end
        out[#out + 1] = "t"
        for k, x in pairs(v) do
            local kt, xt = type(k), type(x)
            if (kt == "string" or kt == "number" or kt == "boolean") and (xt == "string" or xt == "number" or xt == "boolean" or xt == "table") then
                enc(k, out, depth + 1)
                enc(x, out, depth + 1)
            end
        end
        out[#out + 1] = "e"
    else
        out[#out + 1] = "n"
    end
end

function MP.encode(v)
    local out = {}
    enc(v, out, 0)
    return table.concat(out)
end

local function dec(s, i)
    local c = s:sub(i, i)
    if c == "n" then return nil, i + 1
    elseif c == "T" then return true, i + 1
    elseif c == "F" then return false, i + 1
    elseif c == "i" or c == "f" then
        local j = s:find(";", i + 1, true)
        if j == nil then error("bad number") end
        return tonumber(s:sub(i + 1, j - 1)) or 0, j + 1
    elseif c == "s" then
        local j = s:find(":", i + 1, true)
        if j == nil then error("bad string") end
        local n = tonumber(s:sub(i + 1, j - 1))
        if n == nil then error("bad string length") end
        return s:sub(j + 1, j + n), j + n + 1
    elseif c == "t" then
        local t = {}
        i = i + 1
        while true do
            if i > #s then error("table not closed") end
            if s:sub(i, i) == "e" then return t, i + 1 end
            local k, x
            k, i = dec(s, i)
            x, i = dec(s, i)
            if k ~= nil then t[k] = x end
        end
    end
    error("bad data at " .. tostring(i))
end

function MP.decode(s)
    if s == nil or s == "" then return nil end
    local v = dec(s, 1)
    return v
end

-- ---------------------------------------------------------------- events

CFAMPStateEvent = {}
local CFAMPStateEvent_mt = Class(CFAMPStateEvent, Event)
InitEventClass(CFAMPStateEvent, "CFAMPStateEvent")

function CFAMPStateEvent.emptyNew()
    return Event.new(CFAMPStateEvent_mt)
end

function CFAMPStateEvent.new(id, part, total, data)
    local self = CFAMPStateEvent.emptyNew()
    self.id, self.part, self.total, self.data = id, part, total, data
    return self
end

function CFAMPStateEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.id)
    streamWriteInt32(streamId, self.part)
    streamWriteInt32(streamId, self.total)
    streamWriteString(streamId, self.data)
end

function CFAMPStateEvent:readStream(streamId, connection)
    self.id = streamReadInt32(streamId)
    self.part = streamReadInt32(streamId)
    self.total = streamReadInt32(streamId)
    self.data = streamReadString(streamId)
    self:run(connection)
end

function CFAMPStateEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then   -- we are a player, this came from the host
        local ok, err = true, MP.receivePart(self.id, self.part, self.total, self.data)
        if not ok then Logging.error("[CarolinaFieldAlmanac] mp: state from host not applied: %s", tostring(err)) end
    end
end

CFAMPRequestEvent = {}
local CFAMPRequestEvent_mt = Class(CFAMPRequestEvent, Event)
InitEventClass(CFAMPRequestEvent, "CFAMPRequestEvent")

function CFAMPRequestEvent.emptyNew()
    return Event.new(CFAMPRequestEvent_mt)
end

function CFAMPRequestEvent.new(action, args, farmId)
    local self = CFAMPRequestEvent.emptyNew()
    self.action, self.args, self.farmId = action, args or "", farmId or 0
    return self
end

function CFAMPRequestEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.action)
    streamWriteString(streamId, self.args)
    streamWriteInt32(streamId, self.farmId)
end

function CFAMPRequestEvent:readStream(streamId, connection)
    self.action = streamReadString(streamId)
    self.args = streamReadString(streamId)
    self.farmId = streamReadInt32(streamId)
    self:run(connection)
end

function CFAMPRequestEvent:run(connection)
    if connection ~= nil and not connection:getIsServer() then   -- we are the host, a player asked
        local ok, err = true, MP.execRemote(self.action, self.args, self.farmId, connection)
        if not ok then Logging.error("[CarolinaFieldAlmanac] mp: request '%s' failed: %s", tostring(self.action), tostring(err)) end
    end
end

-- ---------------------------------------------------------------- sending

local function sendPayload(payload, connection)
    MP.msgId = MP.msgId + 1
    local n = math.max(1, math.ceil(#payload / MP.CHUNK))
    for part = 1, n do
        local data = payload:sub((part - 1) * MP.CHUNK + 1, part * MP.CHUNK)
        local ev = CFAMPStateEvent.new(MP.msgId, part, n, data)
        if connection ~= nil then
            connection:sendEvent(ev)
        else
            g_server:broadcastEvent(ev, false)
        end
    end
end

-- ---------------------------------------------------------------- what is shared (channels)
-- get(): key -> value (host). apply(key, value): set one entry on a player (value nil = removed). done(full): after a message.

MP.channels = {}

local function addChannel(name, get, apply, done)
    MP.channels[#MP.channels + 1] = {name = name, get = get, apply = apply, done = done}
end

-- weather: station, the days the forecast and menus use
addChannel("wx", function()
    local W = CFAWeather
    local t = {}
    if W == nil then return t end
    t.meta = {station = W.stationId, pre = W.preselected, active = W.active == true, conflict = W.conflict, lastDay = W.lastDay}
    for day, d in pairs(W.days or {}) do t["d" .. day] = d end
    return t
end, function(key, v)
    local W = CFAWeather
    if W == nil then return end
    if key == "meta" then
        if v ~= nil then
            W.stationId = v.station or W.stationId
            W.preselected = v.pre
            W.hostActive = v.active
            W.conflict = v.conflict
            W.lastDay = v.lastDay
        end
    else
        local day = tonumber(key:sub(2))
        if day ~= nil then W.days[day] = v end
    end
end, function(full)
    if CFAWeather ~= nil and CFAWeather.clientDaysChanged ~= nil then CFAWeather.clientDaysChanged(full) end
end)

-- crops: records, policies, the station wait, damage switches
addChannel("cr", function()
    local C = CFACrops
    local t = {}
    if C == nil or not C.active then return t end
    for id, rec in pairs(C.fields or {}) do t["f" .. tostring(id)] = rec end
    for farm, list in pairs(C.policies or {}) do t["p" .. tostring(farm)] = list end
    if CFAWinter ~= nil and CFAWinter.fields ~= nil then   -- alfalfa / grass winter stands (Fields tab)
        for id, st in pairs(CFAWinter.fields) do t["w" .. tostring(id)] = st end
    end
    t.meta = {confirmed = C.stationConfirmed == true, waitStart = C.waitStartDay, off = C.settings ~= nil and C.settings.off or {},
              forageYear = C.forageYear, snow = C.winterSnowDays, active = true}
    return t
end, function(key, v)
    local C = CFACrops
    if C == nil then return end
    local kind, rest = key:sub(1, 1), key:sub(2)
    if key == "meta" then
        if v ~= nil then
            C.stationConfirmed = v.confirmed == true
            C.waitStartDay = v.waitStart
            C.settings.off = v.off or {}
            C.forageYear = v.forageYear
            C.winterSnowDays = v.snow
            C.hostActive = v.active == true
        end
    elseif kind == "f" then
        C.fields[tonumber(rest) or rest] = v
    elseif kind == "p" then
        C.policies[tonumber(rest) or rest] = v
    elseif kind == "w" then
        if CFAWinter ~= nil and CFAWinter.fields ~= nil then CFAWinter.fields[tonumber(rest) or rest] = v end
    end
end, nil)

-- hay curing: field summaries (box, map icons, Hay tab), rain lines, shared settings, the drying weather line
addChannel("cu", function()
    local P = CarolinaFieldCure
    local t = {}
    if P == nil or not P.started then return t end
    for id, s in pairs(P.getFieldSummaries() or {}) do t["s" .. tostring(id)] = s end
    local s = P.settings or {}
    t.meta = {curingDays = s.curingDays, conditioned = s.conditioned, light = s.light, rainAlert = P.rainAlert,
              humidity = P.lastWeather ~= nil and P.lastWeather.humidity or nil}
    return t
end, function(key, v)
    local P = CarolinaFieldCure
    if P == nil then return end
    if key == "meta" then
        if v ~= nil then
            P.settings.curingDays = v.curingDays or P.settings.curingDays
            if v.conditioned ~= nil then P.settings.conditioned = v.conditioned end
            if v.light ~= nil then P.settings.light = v.light end
            P.rainAlert = v.rainAlert or {}
            P.lastWeather = P.lastWeather or {}
            P.lastWeather.humidity = v.humidity
        end
    else
        P.sumCache = P.sumCache or {}
        P.sumCache[tonumber(key:sub(2)) or key:sub(2)] = v
    end
end, function(full)
    local P = CarolinaFieldCure
    if P ~= nil and P.updateHotspots ~= nil and P.sumCache ~= nil then P.updateHotspots(P.sumCache) end
end)

-- notices (each has its farm; a player sees and is told about their own farm's and everyone's)
addChannel("nt", function()
    local P = CarolinaFieldCure
    local t = {}
    if P == nil then return t end
    for _, n in ipairs(P.notices or {}) do
        if n.id ~= nil then t["n" .. n.id] = {id = n.id, date = n.date, text = n.text, kind = n.kind, farm = n.farm} end
    end
    return t
end, function(key, v)
    local P = CarolinaFieldCure
    if P == nil then return end
    MP.noticeSet = MP.noticeSet or {}
    local id = tonumber(key:sub(2))
    if id == nil then return end
    if v == nil then MP.noticeSet[id] = nil return end
    local isNew = MP.noticeSet[id] == nil
    MP.noticeSet[id] = v
    if isNew and not MP.applyingFull and P.receiveNotice ~= nil then P.receiveNotice(v) end
end, function(full)
    local P = CarolinaFieldCure
    if P == nil or MP.noticeSet == nil then return end
    local list = {}
    for _, n in pairs(MP.noticeSet) do list[#list + 1] = n end
    table.sort(list, function(a, b) return (a.id or 0) > (b.id or 0) end)
    P.notices = list
end)

-- ---------------------------------------------------------------- host side

local function channelDelta(ch, full)
    local cache = MP.cache[ch.name]
    if cache == nil then cache = {} MP.cache[ch.name] = cache end
    local ok, entries = true, ch.get()
    if not ok or entries == nil then return nil end
    local set, del, any = {}, {}, false
    local seen = {}
    for key, v in pairs(entries) do
        local e = MP.encode(v)
        seen[key] = true
        if full or cache[key] ~= e then
            set[key] = v
            any = true
        end
        if not full then cache[key] = e end
    end
    if not full then
        for key in pairs(cache) do
            if not seen[key] then
                del[#del + 1] = key
                cache[key] = nil
                any = true
            end
        end
    end
    if not any and not full then return nil end
    return MP.encode({c = ch.name, full = full or nil, s = set, d = del})
end

function MP.serverTick(dt)
    if not MP.isMP() or not MP.isServer() or g_server == nil then return end
    MP.timer = MP.timer + (dt or 0)
    if MP.timer < MP.SEND_MS then return end
    MP.timer = 0
    for _, ch in ipairs(MP.channels) do
        local payload = channelDelta(ch, false)
        if payload ~= nil then sendPayload(payload, nil) end
    end
end

-- everything, to one player (on join)
function MP.sendFull(connection)
    for _, ch in ipairs(MP.channels) do
        local payload = channelDelta(ch, true)
        if payload ~= nil then sendPayload(payload, connection) end
    end
    log("sent everything to a player who joined")
end

-- the farm and admin status of the player behind a connection (host checks; falls back to what the player sent)
function MP.whoIs(connection, sentFarm)
    local farmId, admin = sentFarm, true
    local m = g_currentMission
    local um = m ~= nil and m.userManager or nil
    if um ~= nil and um.getUserByConnection ~= nil and connection ~= nil then
        local ok, user = true, um.getUserByConnection(um, connection)
        if ok and user ~= nil then
            if user.getIsMasterUser ~= nil then
                local ok2, isMaster = true, user.getIsMasterUser(user)
                if ok2 then admin = isMaster == true end
            end
            if g_farmManager ~= nil and g_farmManager.getFarmByUserId ~= nil and user.getId ~= nil then
                local ok3, farm = true, (function() return g_farmManager:getFarmByUserId(user:getId()) end)()
                if ok3 and farm ~= nil and farm.farmId ~= nil then farmId = farm.farmId end
            end
        end
    end
    return farmId, admin
end

function MP.execRemote(action, argsText, sentFarm, connection)
    if action == "full" then
        MP.sendFull(connection)
        return
    end
    local farmId, admin = MP.whoIs(connection, sentFarm)
    local args = MP.decode(argsText) or {}
    MP.exec(action, args, farmId, admin)
end

-- do a player's (or the host's own) request on the host
function MP.exec(action, a, farmId, admin)
    local C, W, P = CFACrops, CFAWeather, CarolinaFieldCure
    local function no(why)
        if P ~= nil and P.addNotice ~= nil then P.addNotice("info", why, farmId) end
    end
    if action == "buy" then
        local ok, why = C.buyPolicy(a.fruit, a.plan, a.cov, farmId)
        if ok == false and why ~= nil then no(why) end
    elseif action == "cancel" then
        local ok, why = C.cancelPolicy(a.fruit, farmId)
        if ok == false and why ~= nil then no(why) end
    elseif action == "claim" then
        local rec = C.fields[a.id]
        local owner = C.fieldOwner(a.id)
        if rec == nil or (owner ~= nil and owner ~= farmId) then no("Field " .. tostring(a.id) .. ": not your field") return end
        local ok, why = C.fileClaim(a.id, false)
        if ok == false and why ~= nil then no(why) end
    elseif not admin then
        no("Only the host or an admin can change the weather station and the shared Field Almanac settings")
    elseif action == "station" then
        if W ~= nil then W.setStation(a.id) end
    elseif action == "confirm" then
        if C ~= nil then C.confirmStation(a.why or "confirmed by a player") end
    elseif action == "damage" then
        if a.on then
            C.settings.off[a.key] = nil
        elseif not (C.settingsLocked ~= nil and C.settingsLocked()) then
            C.settings.off[a.key] = true
        end
    elseif action == "cure" then
        if a.key == "conditioned" or a.key == "light" then P.settings[a.key] = a.value == true end
        if a.key == "curingDays" and tonumber(a.value) ~= nil then P.settings.curingDays = math.max(1, math.min(10, tonumber(a.value))) end
    end
end

-- what the menus call: on the host do it now, on a player send it to the host
function MP.request(action, args)
    if MP.isClientOnly() then
        if g_client ~= nil then
            g_client:getServerConnection():sendEvent(CFAMPRequestEvent.new(action, MP.encode(args or {}), MP.myFarm()))
        end
        return true
    end
    MP.exec(action, args or {}, MP.myFarm(), true)
    return true
end

-- ---------------------------------------------------------------- player side

function MP.receivePart(id, part, total, data)
    local box = MP.inbox[id]
    if box == nil then box = {n = 0, parts = {}} MP.inbox[id] = box end
    if box.parts[part] == nil then
        box.parts[part] = data
        box.n = box.n + 1
    end
    if box.n < total then return end
    MP.inbox[id] = nil
    local msg = MP.decode(table.concat(box.parts, "", 1, total))
    if type(msg) ~= "table" then return end
    MP.applyMessage(msg)
end

function MP.applyMessage(msg)
    local ch = nil
    for _, c in ipairs(MP.channels) do if c.name == msg.c then ch = c break end end
    if ch == nil then return end
    MP.applyingFull = msg.full == true
    if msg.full then
        -- a full message replaces what this player had for that channel
        if ch.name == "wx" and CFAWeather ~= nil then CFAWeather.days = {} end
        if ch.name == "cr" and CFACrops ~= nil then
            CFACrops.fields = {} CFACrops.policies = {}
            if CFAWinter ~= nil then CFAWinter.fields = {} end
        end
        if ch.name == "cu" and CarolinaFieldCure ~= nil then CarolinaFieldCure.sumCache = {} end
        if ch.name == "nt" then MP.noticeSet = {} end
        MP.gotFull[ch.name] = true
    end
    for key, v in pairs(msg.s or {}) do ch.apply(key, v) end
    for _, key in ipairs(msg.d or {}) do ch.apply(key, nil) end
    if ch.done ~= nil then ch.done(msg.full == true) end
    MP.applyingFull = false
end

-- every frame on a player: ask for everything once in the world; the station banner and reminders
function MP.clientTick(dt)
    if not MP.isClientOnly() then return end
    if not MP.requestedFull and g_client ~= nil and g_currentMission ~= nil and g_currentMission.gameStarted ~= false then
        MP.joinWait = (MP.joinWait or 0) + (dt or 0)
        if MP.joinWait > 1500 then
            MP.requestedFull = true
            g_client:getServerConnection():sendEvent(CFAMPRequestEvent.new("full", "", MP.myFarm()))
            log("asked the host for the Field Almanac state")
        end
    end
    if CFACrops ~= nil and CFACrops.clientTick ~= nil then CFACrops.clientTick(dt) end
end
