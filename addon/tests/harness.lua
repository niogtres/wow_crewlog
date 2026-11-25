-- Minimal fake WoW client for running the Crewlog addon under plain Lua 5.1.
-- The game state is plain tables the test mutates; C_Timer callbacks queue up until H.flush().
local H = {}

H.state = {
  time = 1795450000,
  guid = "Player-6949-0A1B2C3D",
  name = "Zarnokk",
  level = 1,
  map = 1411,
  pos = { 0.4323, 0.6885 },
  completed = {},        -- array of ids
  log = {},              -- ordered: { {header = "Durotar"} | {id, title, level, objs = {{have, need, finished, type, text}}} }
  npcGuid = nil,         -- UnitGUID("npc") while a quest dialog is open
  dialogQuest = 0,       -- GetQuestID()
  dialogTitle = "",
  dialogObjective = "",
}
local st = H.state

local timers = {}
H.chat = {}

-- globals the addon uses ------------------------------------------------------
time = function() return st.time end
date = os.date
GetServerTime = function() return st.time end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) H.chat[#H.chat + 1] = m end }
SlashCmdList = {}
UnitGUID = function(u)
  if u == "player" then return st.guid end
  if u == "npc" then return st.npcGuid end
  local i = tonumber((u or ""):match("^party(%d)$") or (u or ""):match("^raid(%d+)$") or "")
  local m = i and H.group and H.group.members[i]
  return m and m[1]
end
UnitName = function() return st.name end
UnitClass = function() return "Rogue", "ROGUE", 4 end
UnitRace = function() return "Troll", "Troll", 8 end
UnitSex = function() return 3 end
UnitFactionGroup = function() return "Horde", "Horde" end
UnitLevel = function() return st.level end
GetQuestID = function() return st.dialogQuest end
GetTitleText = function() return st.dialogTitle end
GetObjectiveText = function() return st.dialogObjective end

C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = st.time + delay, fn = fn } end }
C_AddOns = { GetAddOnMetadata = function(_, field) if field == "Version" then return "0.1.0-test" end end }
H.pin = nil   -- the map pin /way set: {map, x, y}
C_Map = {
  GetBestMapForUnit = function() return st.map end,
  GetPlayerMapPosition = function() if not st.pos then return nil end return { GetXY = function() return st.pos[1], st.pos[2] end } end,
  GetMapChildrenInfo = function() return {
    { mapID = 1411, name = "Durotar", mapType = 3 }, { mapID = 1454, name = "Orgrimmar", mapType = 3 },
    { mapID = 1456, name = "Thunder Bluff", mapType = 3 }, { mapID = 1412, name = "Mulgore", mapType = 3 } } end,
  GetMapInfo = function(id) for _, m in ipairs(C_Map.GetMapChildrenInfo()) do if m.mapID == id then return m end end end,
  CanSetUserWaypointOnMap = function() return true end,
  SetUserWaypoint = function(p) H.pin = p end,
}
UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { map = map, x = x, y = y } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) H.tracked = on end }

local function logIndexOf(qid)
  for i, e in ipairs(st.log) do if e.id == qid then return i end end
end

C_QuestLog = {
  GetAllCompletedQuestIDs = function()
    local out = {}
    for i, v in ipairs(st.completed) do out[i] = v end
    return out
  end,
  IsQuestFlaggedCompleted = function(qid)
    for _, v in ipairs(st.completed) do if v == qid then return true end end
    return false
  end,
  GetNumQuestLogEntries = function()
    local q = 0
    for _, e in ipairs(st.log) do if e.id then q = q + 1 end end
    return #st.log, q
  end,
  GetInfo = function(i)
    local e = st.log[i]
    if not e then return nil end
    if e.header then return { title = e.header, isHeader = true, questID = 0, questLogIndex = i } end
    return { title = e.title, level = e.level, questID = e.id, questLogIndex = i, isHeader = false, isScaling = true, suggestedGroup = e.group or 0 }
  end,
  GetLogIndexForQuestID = function(qid) return logIndexOf(qid) end,
  GetQuestObjectives = function(qid)
    local i = logIndexOf(qid)
    if not i then return {} end
    local out = {}
    for j, o in ipairs(st.log[i].objs or {}) do
      out[j] = { numFulfilled = o[1], numRequired = o[2], finished = o[3], type = o[4] or "monster", text = string.format("%d/%d %s", o[1], o[2], o[5] or "Mottled Boar slain") }
    end
    return out
  end,
}

-- Frames: real event wiring, every other widget method is a permissive no-op (UI code runs, nothing draws).
local frames = {}
local noop = function(self) return self end
local widgetMeta = { __index = function() return noop end }
CreateFrame = function(_, name)
  local f = setmetatable({ events = {}, scripts = {} }, widgetMeta)
  if name then _G[name] = f end
  function f:CreateFontString()
    local fs = setmetatable({}, widgetMeta)
    function fs:SetText(t) self.text = t end
    function fs:GetStringHeight() return 100 end
    return fs
  end
  function f:RegisterEvent(ev) self.events[ev] = true end
  function f:SetScript(name, fn) self.scripts[name] = fn; if name == "OnEvent" then self.onEvent = fn end end
  function f:CreateTexture() return setmetatable({}, widgetMeta) end
  frames[#frames + 1] = f
  return f
end

-- UI globals
UIParent = setmetatable({}, widgetMeta)
UISpecialFrames = {}
tinsert = table.insert
H.reloads, H.popups, H.inCombat, H.shift = 0, {}, false, false
Minimap = setmetatable({ GetWidth = function() return 140 end, GetCenter = function() return 500, 500 end, GetEffectiveScale = function() return 1 end }, widgetMeta)
GameTooltip = setmetatable({ lines = {}, AddLine = function(self, l) self.lines[#self.lines + 1] = l end }, widgetMeta)
StaticPopupDialogs = {}
StaticPopup_Show = function(name) H.popups[#H.popups + 1] = name end
ReloadUI = function() H.reloads = H.reloads + 1 end
InCombatLockdown = function() return H.inCombat end
IsShiftKeyDown = function() return H.shift end
GetCursorPosition = function() return 0, 0 end

-- Group + addon messages: H.group.members = { {guid, name}, ... } (others, not the player); sent messages pile up
-- in H.sent so a test can deliver them to another simulated client.
H.group = { members = {}, raid = false }
H.sent = {}
H.cvars = { nameplateShowFriends = "0" }
IsInGroup = function(category)
  if category == LE_PARTY_CATEGORY_INSTANCE then return H.group.instance == true end
  return #H.group.members > 0
end
IsInRaid = function() return H.group.raid end
GetNumGroupMembers = function() return #H.group.members > 0 and #H.group.members + 1 or 0 end
LE_PARTY_CATEGORY_INSTANCE = 2
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() return 0 end,
  SendAddonMessage = function(prefix, msg, channel)
    assert(#msg <= 255, "addon message too long: " .. #msg)
    H.sent[#H.sent + 1] = { prefix = prefix, msg = msg, channel = channel }
    return 0
  end,
}
-- hooksecurefunc(table, "method", fn) / hooksecurefunc("globalFunction", fn): run fn after the original.
hooksecurefunc = function(a, b, c)
  local t, name, fn = a, b, c
  if type(a) == "string" then t, name, fn = _G, a, b end
  local orig = t[name]
  t[name] = function(...) local r = { orig(...) } fn(...) return unpack(r) end
end
GetCVar = function(k) return H.cvars[k] end
SetCVar = function(k, v) H.cvars[k] = v end
GetClassInfo = function(id) if id == 4 then return "Rogue", "ROGUE", 4 end if id == 1 then return "Warrior", "WARRIOR", 1 end end
RAID_CLASS_COLORS = { ROGUE = { r = 1, g = 0.96, b = 0.41 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
H.plates = {}
C_NamePlate = {
  GetNamePlateForUnit = function(unit) return H.plates[unit] end,
  GetNamePlates = function() local out = {} for u, p in pairs(H.plates) do p.namePlateUnitToken = u; out[#out + 1] = p end return out end,
}
function H.addPlate(unit) H.plates[unit] = setmetatable({}, widgetMeta) return H.plates[unit] end

-- driving ------------------------------------------------------------------------
function H.load(addonName, files)
  local ns = {}
  for _, file in ipairs(files) do
    local chunk = assert(loadfile("addon/" .. addonName .. "/" .. file))
    chunk(addonName, ns)
  end
  return ns
end

function H.fire(event, ...)
  for _, f in ipairs(frames) do
    if f.events[event] and f.onEvent then f.onEvent(f, event, ...) end
  end
end

-- Moves time forward in small steps, so chains of timers (a send queue pumping every 0.3 s) play out as in game.
function H.advance(seconds)
  local target = st.time + seconds
  while st.time < target do
    st.time = math.min(target, st.time + 0.05)
    H.flush()
  end
end

function H.flush()
  local again = true
  while again do
    again = false
    for i = #timers, 1, -1 do
      local t = timers[i]
      if t.at <= st.time then
        table.remove(timers, i)
        t.fn()
        again = true
      end
    end
  end
end

function H.addQuest(id, title, level, objs, group)
  st.log[#st.log + 1] = { id = id, title = title, level = level, objs = objs or {}, group = group }
end

function H.removeQuest(id)
  local i = logIndexOf(id)
  if i then table.remove(st.log, i) end
end

function H.setObjective(id, n, have)
  local o = st.log[logIndexOf(id)].objs[n]
  o[1] = have
  o[3] = have >= o[2]
end

-- WoW-style SavedVariables writer ---------------------------------------------------
-- Mirrors the format the game writes: `Name = {` + `["key"] = value,` lines, sequences as bare values,
-- numbers in %.14g, strings with %q escaping. `withIndexComments` adds the `-- [n]` comments older
-- clients emit, so the .NET parser gets tested on both.
local function isSequence(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  for i = 1, n do if t[i] == nil then return false end end
  return true, n
end

local function writeValue(out, v, indent, withIndexComments)
  local tv = type(v)
  if tv == "string" then out[#out + 1] = string.format("%q", v)
  elseif tv == "number" then
    if v == math.floor(v) and math.abs(v) < 1e15 then out[#out + 1] = string.format("%d", v)
    else out[#out + 1] = string.format("%.14g", v) end
  elseif tv == "boolean" then out[#out + 1] = tostring(v)
  elseif tv == "table" then
    out[#out + 1] = "{\n"
    local seq, n = isSequence(v)
    if seq then
      for i = 1, n do
        out[#out + 1] = indent .. "\t"
        writeValue(out, v[i], indent .. "\t", withIndexComments)
        out[#out + 1] = withIndexComments and (", -- [" .. i .. "]\n") or ",\n"
      end
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
      end)
      for _, k in ipairs(keys) do
        out[#out + 1] = indent .. "\t["
        writeValue(out, k, "", withIndexComments)
        out[#out + 1] = "] = "
        writeValue(out, v[k], indent .. "\t", withIndexComments)
        out[#out + 1] = ",\n"
      end
    end
    out[#out + 1] = indent .. "}"
  else
    out[#out + 1] = "nil"
  end
end

function H.writeSavedVariables(path, name, value, withIndexComments)
  local out = { "\n", name, " = " }
  writeValue(out, value, "", withIndexComments)
  out[#out + 1] = "\n"
  local f = assert(io.open(path, "wb"))
  f:write(table.concat(out))
  f:close()
end

return H
