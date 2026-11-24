-- Turns quest events into the per-character snapshot + append-only event log (DESIGN §5.1–5.3).
-- Event kinds: ACCEPT, TURNIN, ABANDON, PROGRESS, LEVEL, ZONE.
local _, ns = ...
local U, S, H = ns.U, ns.Store, ns.Harvest
local C = {}
ns.Collector = C

C.REMOVE_CHECK_DELAY = 0.3 -- seconds to let QUEST_TURNED_IN / completion flags settle before calling it an abandon
C.LOG_DEBOUNCE = 0.5

local db, guid
local recentTurnIn = {} -- [questID] = time, to tell turn-ins from abandons on QUEST_REMOVED
C.listeners = {}        -- functions(ev) called after each recorded event (debug printing)

local function emit(ev)
  ev = S.append(db, guid, ev)
  for _, fn in ipairs(C.listeners) do fn(ev) end
  return ev
end

-- One quest as stored in rec.log: { title, lvl, o = { { h = have, n = need, f = finished }, ... } }
local function readQuest(qid)
  local idx = C_QuestLog.GetLogIndexForQuestID(qid)
  local info = idx and C_QuestLog.GetInfo(idx)
  local q = { title = info and info.title, lvl = info and info.level, o = {} }
  local objs = C_QuestLog.GetQuestObjectives(qid)
  if type(objs) == "table" then
    for i, o in ipairs(objs) do
      q.o[i] = { h = o.numFulfilled or 0, n = o.numRequired or 0, f = o.finished and true or false, t = U.objectiveLabel(o.text) }
    end
  end
  return q
end

-- Whole log, skipping zone headers (isHeader rows have questID 0).
local function readLog()
  local log = {}
  local n = C_QuestLog.GetNumQuestLogEntries() or 0
  for i = 1, n do
    local info = C_QuestLog.GetInfo(i)
    if info and not info.isHeader and info.questID and info.questID > 0 then
      log[info.questID] = readQuest(info.questID)
    end
  end
  return log
end

-- Compare stored vs fresh objectives of one quest; emit PROGRESS per changed objective.
local function diffQuest(qid, old, new)
  if not old then return end
  for i, o in ipairs(new.o) do
    local prev = old.o[i]
    if prev and (prev.h ~= o.h or prev.f ~= o.f) and o.h >= prev.h then
      emit({ k = "PROGRESS", q = qid, o = i, h = o.h, n = o.n, f = o.f or nil })
    end
  end
end

local function refreshQuest(qid)
  local rec = S.char(db, guid)
  local old = rec.log[qid]
  if not old then return end
  local new = readQuest(qid)
  diffQuest(qid, old, new)
  rec.log[qid] = new
end

local function refreshLog()
  local rec = S.char(db, guid)
  local fresh = readLog()
  for qid, new in pairs(fresh) do diffQuest(qid, rec.log[qid], new) end
  -- Quests that appeared without QUEST_ACCEPTED (shared/auto quests) or vanished silently are just synced;
  -- accepts and removals proper come from their own events.
  rec.log = fresh
end

local function completedList()
  local ids = C_QuestLog.GetAllCompletedQuestIDs() or {}
  return U.copySorted(ids)
end

-- PLAYER_LOGIN: refresh the full snapshot for the current character.
function C.start(theDb)
  db = theDb
  guid = UnitGUID("player")
  local rec = S.char(db, guid)
  local _, class, classId = UnitClass("player")
  local _, race, raceId = UnitRace("player")
  rec.name = UnitName("player")
  rec.realmId = U.realmIdFromPlayerGuid(guid)
  rec.class, rec.race = class, race
  -- numeric ids match QuestieDB's requiredRaces/requiredClasses masks (Skyborne = 95/96)
  rec.classId, rec.raceId = classId, raceId
  rec.faction = UnitFactionGroup("player")
  rec.level = UnitLevel("player")
  rec.map = C_Map.GetBestMapForUnit("player")
  rec.completed = completedList()
  rec.completedHash = U.hashIds(rec.completed)
  rec.log = readLog()
  rec.lastSeen = U.now()
  H.reset()
  return rec
end

function C.guid() return guid end

C.handlers = {
  QUEST_ACCEPTED = function(qid)
    local rec = S.char(db, guid)
    if rec.log[qid] then return end
    rec.log[qid] = readQuest(qid)
    emit({ k = "ACCEPT", q = qid })
    H.onAccepted(db, qid)
  end,

  QUEST_TURNED_IN = function(qid, xp)
    local rec = S.char(db, guid)
    recentTurnIn[qid] = U.now()
    rec.log[qid] = nil
    if U.sortedInsert(rec.completed, qid) then rec.completedHash = U.hashIds(rec.completed) end
    emit({ k = "TURNIN", q = qid, x = (xp and xp > 0) and xp or nil })
  end,

  QUEST_REMOVED = function(qid)
    if recentTurnIn[qid] then recentTurnIn[qid] = nil return end
    C_Timer.After(C.REMOVE_CHECK_DELAY, function()
      if recentTurnIn[qid] then recentTurnIn[qid] = nil return end
      local rec = S.char(db, guid)
      if not rec.log[qid] then return end -- already handled
      rec.log[qid] = nil
      if C_QuestLog.IsQuestFlaggedCompleted(qid) then
        -- turned in without QUEST_TURNED_IN reaching us
        if U.sortedInsert(rec.completed, qid) then rec.completedHash = U.hashIds(rec.completed) end
        emit({ k = "TURNIN", q = qid })
      else
        emit({ k = "ABANDON", q = qid })
      end
    end)
  end,

  QUEST_WATCH_UPDATE = function(qid)
    -- objectives settle on the next frame
    C_Timer.After(0, function() refreshQuest(qid) end)
  end,

  QUEST_LOG_UPDATE = function()
    U.debounce("log", C.LOG_DEBOUNCE, refreshLog)
  end,

  PLAYER_LEVEL_UP = function(level)
    local rec = S.char(db, guid)
    rec.level = level
    emit({ k = "LEVEL", l = level })
  end,

  ZONE_CHANGED_NEW_AREA = function()
    local rec = S.char(db, guid)
    local map = C_Map.GetBestMapForUnit("player")
    if not map or map == rec.map then return end
    -- At PLAYER_LOGIN the map is often not known yet; the first fix is a position, not a zone change.
    local known = rec.map ~= nil
    rec.map = map
    if known then emit({ k = "ZONE", m = map }) end
  end,

  QUEST_DETAIL = function(startItemID) H.onDetail(db, startItemID) end,
  QUEST_COMPLETE = function() H.onComplete(db) end,

  PLAYER_LOGOUT = function()
    local rec = S.char(db, guid)
    rec.lastSeen = U.now()
  end,

  -- Where the toon stands when the game saves (a /reload, which is what Sync does, or logging out), for the
  -- website's route map: zone map id plus 0-100 coordinates, the same scale as quest data.
  PLAYER_LEAVING_WORLD = function()
    local rec = S.char(db, guid)
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    local x, y
    if pos and pos.GetXY then x, y = pos:GetXY() end
    if x and y and (x > 0 or y > 0) then
      rec.pos = { map = map, x = math.floor(x * 1000 + 0.5) / 10, y = math.floor(y * 1000 + 0.5) / 10 }
    else
      rec.pos = nil -- inside an instance or no position: say nothing rather than something old
    end
  end,
}
C.handlers.UNIT_QUEST_LOG_CHANGED = function(unit) if unit == "player" then C.handlers.QUEST_LOG_UPDATE() end end
