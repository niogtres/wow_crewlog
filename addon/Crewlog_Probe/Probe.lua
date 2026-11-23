-- Crewlog_Probe: finds out which quest, map, comm and harvest APIs the WoW: Forever client exposes.
-- Everything goes through pcall; the result lands in SavedVariables (Crewlog_ProbeDB) on /reload or logout.
-- Usage:  /crewprobe          full API sweep (repeat any time)
--         play a few minutes: accept a quest, progress an objective, turn one in, talk to a quest giver
--         /reload           writes WTF\Account\<ACCOUNT>\SavedVariables\Crewlog_Probe.lua

local ADDON = ...
local PREFIX = "|cffE3A21A[Crewlog Probe]|r "
local MAX_EVENT_LOG = 400

local function say(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg)) end

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

-- Resolve "C_QuestLog.GetInfo" style paths without erroring on missing tables.
local function resolve(path)
  local cur = _G
  for part in string.gmatch(path, "[^%.]+") do
    if type(cur) ~= "table" then return nil end
    cur = cur[part]
  end
  return cur
end

-- Plain-data copy, bounded so SavedVariables stays small and never hits a cycle.
local function snap(v, depth, budget)
  depth = depth or 0
  budget = budget or { n = 0 }
  local t = type(v)
  if t == "string" or t == "number" or t == "boolean" or t == "nil" then return v end
  if t ~= "table" then return "<" .. t .. ">" end
  if depth >= 4 then return "<table depth>" end
  local out, count = {}, 0
  for k, val in pairs(v) do
    count = count + 1
    budget.n = budget.n + 1
    if count > 60 or budget.n > 2000 then out["<truncated>"] = true break end
    local key = (type(k) == "string" or type(k) == "number") and k or tostring(k)
    out[key] = snap(val, depth + 1, budget)
  end
  return out
end

-- Call a function safely and keep every return value.
-- select('#') keeps the true count even when nils sit between return values (GetQuestLogTitle does that).
local function collect(ok, ...)
  if not ok then return { ok = false, err = tostring((...)) } end
  local n = select("#", ...)
  local out = { ok = true, n = n }
  for i = 1, n do out[i] = snap((select(i, ...))) end
  return out
end

local function try(fn, ...)
  if type(fn) ~= "function" then return { ok = false, err = "missing" } end
  return collect(pcall(fn, ...))
end

local function tryPath(path, ...) return try(resolve(path), ...) end

-- ---------------------------------------------------------------------------
-- what to look for
-- ---------------------------------------------------------------------------

local FUNCTIONS = {
  -- completed quests
  "GetQuestsCompleted", "C_QuestLog.GetAllCompletedQuestIDs", "C_QuestLog.IsQuestFlaggedCompleted",
  "IsQuestFlaggedCompleted", "C_QuestLog.IsOnQuest", "C_QuestLog.ReadyForTurnIn", "IsQuestComplete",
  -- quest log
  "GetNumQuestLogEntries", "C_QuestLog.GetNumQuestLogEntries", "GetQuestLogTitle", "C_QuestLog.GetInfo",
  "GetQuestLogLeaderBoard", "GetNumQuestLeaderBoards", "C_QuestLog.GetQuestObjectives", "GetQuestLogSelection",
  "SelectQuestLogEntry", "GetQuestLogQuestText", "C_QuestLog.GetLogIndexForQuestID", "C_QuestLog.GetQuestIDForLogIndex",
  "GetQuestLogIndexByID", "C_QuestLog.GetTitleForQuestID", "C_QuestLog.GetQuestTagInfo", "GetQuestTagInfo",
  "C_QuestLog.GetQuestDifficultyLevel", "GetQuestDifficultyColor", "GetQuestGreenRange", "UnitXP", "C_QuestLog.GetMaxNumQuests",
  "C_QuestLog.GetMaxNumQuestsCanAccept", "C_QuestLog.RequestLoadQuestByID", "C_QuestLog.GetQuestInfo", "QuestUtils_GetQuestName",
  -- quest lines / map quests (structure harvesting)
  "C_QuestLine.GetAvailableQuestLines", "C_QuestLine.GetQuestLineQuests", "C_QuestLine.GetQuestLineInfo",
  "C_QuestLine.RequestQuestLinesForMap", "C_QuestLog.GetQuestsOnMap", "C_TaskQuest.GetQuestsForPlayerByMapID",
  "C_QuestLog.GetZoneStoryInfo", "C_CampaignInfo.GetCampaignID", "C_QuestLog.GetQuestAdditionalHighlights",
  -- quest giver interaction (harvest giver/turn-in NPCs)
  "GetQuestID", "GetTitleText", "GetObjectiveText", "GetQuestText", "GetNumAvailableQuests", "GetNumActiveQuests",
  "GetAvailableTitle", "GetAvailableQuestInfo", "C_GossipInfo.GetAvailableQuests", "C_GossipInfo.GetActiveQuests",
  "C_GossipInfo.GetNumAvailableQuests", "GetGossipAvailableQuests", "UnitGUID",
  -- maps & position
  "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition", "C_Map.GetMapInfo", "C_Map.GetMapChildrenInfo",
  "GetZoneText", "GetRealZoneText", "GetSubZoneText", "GetCurrentMapAreaID", "SetMapToCurrentZone", "UnitPosition",
  -- player
  "UnitLevel", "UnitRace", "UnitClass", "UnitFactionGroup", "GetRealmName", "GetNormalizedRealmName", "UnitName",
  "C_PlayerInfo.GetPlayerMythicPlusRatingSummary", "GetAccountExpansionLevel", "GetExpansionLevel", "GetMaxPlayerLevel",
  -- addon comms
  "C_ChatInfo.SendAddonMessage", "C_ChatInfo.RegisterAddonMessagePrefix", "C_ChatInfo.IsAddonMessagePrefixRegistered",
  "SendAddonMessage", "RegisterAddonMessagePrefix", "C_ChatInfo.SendAddonMessageLogged",
  -- group
  "IsInGroup", "IsInRaid", "GetNumGroupMembers", "UnitInParty",
  -- addon infrastructure
  "C_AddOns.GetAddOnMetadata", "GetAddOnMetadata", "C_AddOns.IsAddOnLoaded", "IsAddOnLoaded", "C_Timer.After",
  "C_Timer.NewTicker", "Settings.RegisterCanvasLayoutCategory", "InterfaceOptions_AddCategory", "GetServerTime", "time",
  "date", "C_DateAndTime.GetCurrentCalendarTime", "strsplit", "bit.band", "C_Texture.GetAtlasInfo", "CreateFrame",
  "BackdropTemplateMixin", "C_EncodingUtil.SerializeCBOR", "C_EncodingUtil.CompressString", "LibStub",
  -- misc that matter for Forever specifics
  "C_Seasons.GetActiveSeason", "C_GameRules.IsHardcoreActive", "C_GameRules.GetActiveGameMode", "C_TransmogCollection.GetAppearanceSources",
}

local EVENTS = {
  "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT",
  "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_COMPLETE", "QUEST_FINISHED", "QUEST_DETAIL",
  "QUEST_PROGRESS", "QUEST_GREETING", "QUEST_ACCEPT_CONFIRM", "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE",
  "QUEST_WATCH_LIST_CHANGED", "UNIT_QUEST_LOG_CHANGED", "QUEST_DATA_LOAD_RESULT", "QUEST_POI_UPDATE",
  "QUESTLINE_UPDATE", "QUEST_LOG_CRITERIA_UPDATE", "QUEST_ITEM_UPDATE", "GOSSIP_SHOW", "GOSSIP_CLOSED",
  "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS",
  "GROUP_ROSTER_UPDATE", "GROUP_JOINED", "GROUP_LEFT", "CHAT_MSG_ADDON", "CHAT_MSG_ADDON_LOGGED",
  "UI_INFO_MESSAGE", "CHAT_MSG_SYSTEM",
}

local NOISY = { ADDON_LOADED = true, QUEST_LOG_UPDATE = true, PLAYER_XP_UPDATE = true, UNIT_QUEST_LOG_CHANGED = true, QUEST_POI_UPDATE = true, ZONE_CHANGED_INDOORS = true }

-- ---------------------------------------------------------------------------
-- probes
-- ---------------------------------------------------------------------------

local db -- Crewlog_ProbeDB, set on ADDON_LOADED

local function probeEnvironment()
  local env = {}
  env.build = tryPath("GetBuildInfo")
  env.locale = tryPath("GetLocale")
  env.luaVersion = _VERSION
  env.projectId = WOW_PROJECT_ID
  local projects = {}
  for k, v in pairs(_G) do
    if type(k) == "string" and k:match("^WOW_PROJECT_") and type(v) == "number" then projects[k] = v end
  end
  env.projectConstants = projects
  env.realm = tryPath("GetRealmName")
  env.serverTime = tryPath("GetServerTime")
  env.maxLevel = tryPath("GetMaxPlayerLevel")
  env.expansion = tryPath("GetExpansionLevel")
  env.addonMetadataInterface = tryPath("C_AddOns.GetAddOnMetadata", ADDON, "Interface")
  env.seasons = tryPath("C_Seasons.GetActiveSeason")
  env.gameMode = tryPath("C_GameRules.GetActiveGameMode")
  return env
end

local function probeFunctions()
  local present, missing = {}, {}
  for _, path in ipairs(FUNCTIONS) do
    local v = resolve(path)
    if v ~= nil then present[#present + 1] = path .. " (" .. type(v) .. ")" else missing[#missing + 1] = path end
  end
  -- Namespaces that exist at all, to spot Forever-specific C_ tables we didn't think of.
  local namespaces = {}
  for k, v in pairs(_G) do
    if type(k) == "string" and k:match("^C_") and type(v) == "table" then namespaces[#namespaces + 1] = k end
  end
  table.sort(namespaces)
  local questy = {}
  for _, ns in ipairs({ "C_QuestLog", "C_QuestLine", "C_QuestInfoSystem", "C_QuestSession", "C_QuestOffer", "C_QuestItemUse", "C_QuestHub" }) do
    local t = _G[ns]
    if type(t) == "table" then
      local names = {}
      for fk in pairs(t) do names[#names + 1] = fk end
      table.sort(names)
      questy[ns] = names
    end
  end
  return { present = present, missing = missing, namespaces = namespaces, questNamespaces = questy }
end

local function probePlayer()
  local p = {}
  p.guid = tryPath("UnitGUID", "player")
  p.name = tryPath("UnitName", "player")
  p.level = tryPath("UnitLevel", "player")
  p.race = tryPath("UnitRace", "player")
  p.class = tryPath("UnitClass", "player")
  p.faction = tryPath("UnitFactionGroup", "player")
  p.xp = tryPath("UnitXP", "player")
  p.mapId = tryPath("C_Map.GetBestMapForUnit", "player")
  local mapId = p.mapId.ok and p.mapId[1] or nil
  if mapId then
    p.mapInfo = tryPath("C_Map.GetMapInfo", mapId)
    local pos = resolve("C_Map.GetPlayerMapPosition")
    if pos then
      local ok, v = pcall(pos, mapId, "player")
      if ok and v and v.GetXY then local x, y = v:GetXY(); p.mapPos = { x = x, y = y } else p.mapPos = { ok = ok, err = tostring(v) } end
    end
  end
  p.zone = { real = tryPath("GetRealZoneText"), sub = tryPath("GetSubZoneText") }
  p.unitPosition = tryPath("UnitPosition", "player")
  return p, mapId
end

local function probeCompleted()
  local c = {}
  local all = resolve("C_QuestLog.GetAllCompletedQuestIDs")
  if all then
    local ok, ids = pcall(all)
    if ok and type(ids) == "table" then
      c.modern = { count = #ids, sample = {} }
      for i = 1, math.min(#ids, 40) do c.modern.sample[i] = ids[i] end
    else c.modern = { ok = ok, err = tostring(ids) } end
  end
  local classic = resolve("GetQuestsCompleted")
  if classic then
    local t = {}
    local ok, ret = pcall(classic, t)
    local src = (ok and type(ret) == "table") and ret or t
    local n, sample = 0, {}
    for id in pairs(src) do n = n + 1; if #sample < 40 then sample[#sample + 1] = id end end
    c.classic = { ok = ok, count = n, sample = sample, returnedTable = type(ret) == "table" }
  end
  -- Spot check: is the flag API consistent with the bulk list?
  local flag = resolve("C_QuestLog.IsQuestFlaggedCompleted") or resolve("IsQuestFlaggedCompleted")
  if flag then
    c.flagCheck = {}
    for _, qid in ipairs({ 783, 7, 33, 5261, 18, 3, 176, 239 }) do c.flagCheck[tostring(qid)] = try(flag, qid) end
  end
  return c
end

local function probeLog()
  local log = { entries = {} }
  local numModern = resolve("C_QuestLog.GetNumQuestLogEntries")
  local numOld = resolve("GetNumQuestLogEntries")
  log.countModern = try(numModern)
  log.countOld = try(numOld)
  local n = (log.countModern.ok and log.countModern[1]) or (log.countOld.ok and log.countOld[1]) or 0
  for i = 1, math.min(n, 40) do
    local e = { index = i }
    e.modernInfo = tryPath("C_QuestLog.GetInfo", i)
    e.oldTitle = tryPath("GetQuestLogTitle", i)
    local qid = (e.modernInfo.ok and type(e.modernInfo[1]) == "table" and e.modernInfo[1].questID)
      or (e.oldTitle.ok and e.oldTitle[8]) or nil
    e.questID = qid
    if qid and qid ~= 0 then
      e.objectivesModern = tryPath("C_QuestLog.GetQuestObjectives", qid)
      e.tag = tryPath("C_QuestLog.GetQuestTagInfo", qid)
      e.difficulty = tryPath("C_QuestLog.GetQuestDifficultyLevel", qid)
      e.readyForTurnIn = tryPath("C_QuestLog.ReadyForTurnIn", qid)
    end
    local nb = tryPath("GetNumQuestLeaderBoards", i)
    if nb.ok and type(nb[1]) == "number" then
      e.leaderBoards = {}
      for j = 1, math.min(nb[1], 8) do e.leaderBoards[j] = tryPath("GetQuestLogLeaderBoard", j, i) end
    end
    log.entries[#log.entries + 1] = e
  end
  return log
end

local function probeQuestLines(mapId)
  if not mapId then return { skipped = "no map id" } end
  local q = { mapId = mapId }
  q.request = tryPath("C_QuestLine.RequestQuestLinesForMap", mapId)
  q.available = tryPath("C_QuestLine.GetAvailableQuestLines", mapId)
  q.onMap = tryPath("C_QuestLog.GetQuestsOnMap", mapId)
  q.zoneStory = tryPath("C_QuestLog.GetZoneStoryInfo", mapId)
  if q.available.ok and type(q.available[1]) == "table" then
    local first = q.available[1][1]
    if type(first) == "table" and first.questLineID then
      q.firstLineQuests = tryPath("C_QuestLine.GetQuestLineQuests", first.questLineID)
    end
  end
  q.children = tryPath("C_Map.GetMapChildrenInfo", mapId)
  return q
end

local function probeComms()
  local c = {}
  c.registerModern = tryPath("C_ChatInfo.RegisterAddonMessagePrefix", "CREWLOGPROBE")
  c.registerOld = tryPath("RegisterAddonMessagePrefix", "CREWLOGPROBE")
  c.isRegistered = tryPath("C_ChatInfo.IsAddonMessagePrefixRegistered", "CREWLOGPROBE")
  c.inGroup = tryPath("IsInGroup")
  if c.inGroup.ok and c.inGroup[1] then
    c.sendParty = tryPath("C_ChatInfo.SendAddonMessage", "CREWLOGPROBE", "hello|" .. tostring(time()), (IsInRaid and IsInRaid()) and "RAID" or "PARTY")
  end
  -- WHISPER to self works solo and proves the round trip.
  c.sendSelf = tryPath("C_ChatInfo.SendAddonMessage", "CREWLOGPROBE", "self|" .. tostring(time()), "WHISPER", UnitName("player"))
  return c
end

-- ---------------------------------------------------------------------------
-- event logger (runs all session; shows what really fires and with which args)
-- ---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local registered, rejected = {}, {}

local function logEvent(event, ...)
  if not db then return end
  db.eventCounts[event] = (db.eventCounts[event] or 0) + 1
  if NOISY[event] and db.eventCounts[event] > 5 then return end
  if #db.eventLog >= MAX_EVENT_LOG then return end
  local args = { ... }
  for i = 1, #args do args[i] = snap(args[i]) end
  local entry = { e = event, t = GetServerTime and GetServerTime() or time(), args = args, n = select("#", ...) }
  -- Harvest-relevant context: who are we talking to, where are we?
  if event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" or event == "QUEST_PROGRESS" or event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then
    entry.npcGuid = UnitGUID and UnitGUID("npc") or nil
    entry.npcName = UnitName and UnitName("npc") or nil
    entry.questID = (GetQuestID and GetQuestID()) or nil
    entry.title = GetTitleText and GetTitleText() or nil
    local mapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
    entry.mapId = mapId
    if mapId and C_Map.GetPlayerMapPosition then
      local pos = C_Map.GetPlayerMapPosition(mapId, "player")
      if pos and pos.GetXY then entry.x, entry.y = pos:GetXY() end
    end
  end
  if event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN" or event == "QUEST_REMOVED" then
    say(event .. " " .. table.concat((function() local s = {} for i = 1, #args do s[i] = tostring(args[i]) end return s end)(), ", "))
  end
  db.eventLog[#db.eventLog + 1] = entry
end

for _, ev in ipairs(EVENTS) do
  local ok = pcall(frame.RegisterEvent, frame, ev)
  if ok then registered[#registered + 1] = ev else rejected[#rejected + 1] = ev end
end

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" and ... == ADDON then
    Crewlog_ProbeDB = Crewlog_ProbeDB or {}
    db = Crewlog_ProbeDB
    db.probeVersion = "0.0.1"
    db.sessions = (db.sessions or 0) + 1
    db.eventCounts = {}
    db.eventLog = {}
    db.events = { registered = registered, rejected = rejected }
  end
  logEvent(event, ...)
  if event == "PLAYER_LOGIN" then
    db.environment = probeEnvironment()
    say("loaded. Type |cffF2C25B/crewprobe|r to run the full check, play a few minutes, then |cffF2C25B/reload|r.")
  end
end)

-- ---------------------------------------------------------------------------
-- slash command
-- ---------------------------------------------------------------------------

SLASH_CREWLOGPROBE1 = "/crewprobe"
SlashCmdList.CREWLOGPROBE = function()
  if not db then say("SavedVariables not ready yet, try again in a second.") return end
  local run = { at = GetServerTime and GetServerTime() or time() }
  run.environment = probeEnvironment()
  run.functions = probeFunctions()
  local player, mapId = probePlayer()
  run.player = player
  run.completed = probeCompleted()
  run.log = probeLog()
  run.questLines = probeQuestLines(mapId)
  run.comms = probeComms()
  db.runs = db.runs or {}
  db.runs[#db.runs + 1] = run
  while #db.runs > 5 do table.remove(db.runs, 1) end

  local build = run.environment.build
  local completed = (run.completed.modern and run.completed.modern.count) or (run.completed.classic and run.completed.classic.count) or "?"
  say(string.format("build %s (toc %s), project %s", tostring(build[1]), tostring(build[4]), tostring(run.environment.projectId)))
  say(string.format("%d of %d APIs present · %d completed quests · %d quest log entries · %d events registered",
    #run.functions.present, #FUNCTIONS, tonumber(completed) or 0, #run.log.entries, #registered))
  say("Now accept / progress / turn in a quest or two, then type |cffF2C25B/reload|r to save the results.")
end
