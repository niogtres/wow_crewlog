-- CrewlogDB: the SavedVariables schema (docs/DESIGN.md §5.3). Account-wide, one record per character GUID.
local _, ns = ...
local U = ns.U
local S = {}
ns.Store = S

S.SCHEMA = 1
S.MAX_EVENTS = 20000

local function migrate(db)
  -- schema 1 is the first; future migrations go here as `if db.schema == 1 then ... db.schema = 2 end`.
  db.schema = db.schema or S.SCHEMA
end

function S.init(sv, addonVersion)
  local db = type(sv) == "table" and sv or {}
  migrate(db)
  db.installId = db.installId or U.newId()
  db.addonVersion = addonVersion
  db.chars = db.chars or {}
  db.events = db.events or {}
  db.harvest = db.harvest or {}
  db.harvest.quests = db.harvest.quests or {}
  return db
end

function S.char(db, guid)
  local rec = db.chars[guid]
  if not rec then
    rec = { seq = 0, completed = {}, log = {} }
    db.chars[guid] = rec
  end
  return rec
end

-- Append one event for a character. `ev` carries k (kind) plus kind-specific short fields.
function S.append(db, guid, ev)
  local rec = S.char(db, guid)
  rec.seq = rec.seq + 1
  ev.c = guid
  ev.s = rec.seq
  ev.t = ev.t or U.now()
  local events = db.events
  events[#events + 1] = ev
  -- Safety valve: drop the oldest. The next snapshot still carries the truth.
  local over = #events - S.MAX_EVENTS
  if over > 0 then
    for _ = 1, over do table.remove(events, 1) end
    db.droppedEvents = (db.droppedEvents or 0) + over
  end
  return ev
end

-- Drop what the server has acknowledged (ack arrives through the Inbox addon on /reload).
-- inbox.ack[guid] = highest seq stored server-side; inbox.harvestAck = time of the newest harvest entry stored.
function S.prune(db, inbox)
  if type(inbox) ~= "table" then return 0, 0 end
  local ack = type(inbox.ack) == "table" and inbox.ack or {}
  local kept, droppedEv = {}, 0
  for _, ev in ipairs(db.events) do
    local a = ack[ev.c]
    if a and ev.s <= a then droppedEv = droppedEv + 1 else kept[#kept + 1] = ev end
  end
  db.events = kept
  local droppedH = 0
  local hAck = tonumber(inbox.harvestAck)
  if hAck then
    for qid, h in pairs(db.harvest.quests) do
      if (h.t or 0) <= hAck then db.harvest.quests[qid] = nil; droppedH = droppedH + 1 end
    end
  end
  return droppedEv, droppedH
end

function S.pendingCount(db)
  local n = 0
  for _ in pairs(db.harvest.quests) do n = n + 1 end
  return #db.events, n
end
