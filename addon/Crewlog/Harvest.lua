-- Records quest facts QuestieDB may lack: who gives / takes a quest, where, and which quest came right before.
-- Facts are kept per quest and merged; the client uploads them, the server reconciles (DESIGN §8.4).
local _, ns = ...
local U = ns.U
local H = {}
ns.Harvest = H

H.CHAIN_WINDOW = 120 -- seconds: an accept this soon after a turn-in at the same NPC counts as "follows"

local lastTurnIn -- { q = questID, npc = id, t = time }

local function playerPos()
  local map = C_Map.GetBestMapForUnit("player")
  if not map then return nil end
  local x, y
  local pos = C_Map.GetPlayerMapPosition(map, "player")
  if pos and pos.GetXY then x, y = pos:GetXY() end
  return map, U.round(x, 4), U.round(y, 4)
end

-- Who is the quest dialog talking to? NPC, object, or an item that started the quest.
local function source(startItemID)
  if type(startItemID) == "number" and startItemID > 0 then return { item = startItemID } end
  local id, kind = U.parseUnitGuid(UnitGUID("npc"))
  if not id then return nil end
  local map, x, y = playerPos()
  local s = { map = map, x = x, y = y }
  if kind == "object" then s.object = id else s.npc = id end
  return s
end

local function entry(db, qid)
  local e = db.harvest.quests[qid]
  if not e then e = {}; db.harvest.quests[qid] = e end
  e.t = U.now()
  return e
end

-- QUEST_DETAIL(questStartItemID): the offer dialog.
function H.onDetail(db, startItemID)
  local qid = GetQuestID()
  if not qid or qid == 0 then return end
  local e = entry(db, qid)
  e.title = GetTitleText()
  e.obj = U.trim(GetObjectiveText(), 300)
  e.giver = source(startItemID) or e.giver
  if lastTurnIn and e.giver and e.giver.npc and lastTurnIn.npc == e.giver.npc and (U.now() - lastTurnIn.t) <= H.CHAIN_WINDOW then
    e.after = lastTurnIn.q
  end
end

-- QUEST_COMPLETE: the turn-in dialog.
function H.onComplete(db)
  local qid = GetQuestID()
  if not qid or qid == 0 then return end
  local e = entry(db, qid)
  e.title = e.title or GetTitleText()
  e.ender = source(nil) or e.ender
  lastTurnIn = { q = qid, npc = e.ender and e.ender.npc, t = U.now() }
end

-- QUEST_ACCEPTED: now the log knows level and grouping hints.
function H.onAccepted(db, qid)
  local idx = C_QuestLog.GetLogIndexForQuestID(qid)
  local info = idx and C_QuestLog.GetInfo(idx)
  if not info then return end
  local e = entry(db, qid)
  e.title = e.title or info.title
  e.lvl = info.level
  e.grp = (info.suggestedGroup and info.suggestedGroup > 0) and info.suggestedGroup or nil
  e.scaling = info.isScaling or nil
end

function H.reset() lastTurnIn = nil end
