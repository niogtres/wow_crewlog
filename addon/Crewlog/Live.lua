-- Live party sync (DESIGN §5.4): group members running Crewlog see each other's quest logs within seconds.
-- Protocol, prefix CL1, one message <= 250 bytes, fields split by "|":
--   H|guid                              hello: "I'm here, send me your log" (on joining / roster growth)
--   B|guid|gen|name|level|classId       begin a snapshot
--   L|guid|gen|rec;rec;...              snapshot chunk; rec = id,ready,h/n:h/n,title
--   P|guid|gen|map|x|y                  where the sender stands (uiMap, 0-1000 per axis); 0|0|0 when unknown (0.9.0+)
--   T|guid|gen|id,id,...                quests the sender turned in this session (0.9.0+)
--   S|guid|gen|ts|sig                   the snapshot signed with the toon's relay key (0.9.0+, only when its owner allows
--                                       crewmates to relay it; see "Party relay" below)
--   E|guid|gen                          end: the snapshot replaces the peer's quests (missing ones are gone)
-- Addons before 0.9.0 ignore P, T and S.
-- Full snapshots (debounced 1.5 s after a change, plus a 45 s heartbeat) are simpler and more forgiving than
-- deltas: a lost message is fixed by the next snapshot. Own messages echo back, so peers are keyed by GUID and
-- our own GUID is ignored. Live data lives in memory only; the server stays the record.
-- Trust: a message counts only on the group's channels, for a GUID that is in the group, sent by that member (anyone
-- can whisper an addon message, and a member could claim another's GUID). Received text is shown escaped, and how
-- much one peer can send and make us send is capped.
local _, ns = ...
local U, S, Sign = ns.U, ns.Store, ns.Sign
local Live = {}
ns.Live = Live

Live.PREFIX = "CL1"
Live.MAX_BYTES = 250
Live.SPACING = 0.3
Live.DEBOUNCE = 1.5
Live.HEARTBEAT = 45
Live.MAX_QUESTS = 60      -- per peer snapshot (a quest log holds 25)
Live.HELLO_EVERY = 10     -- seconds: answer hellos (and new peers) at most this often
Live.MAX_TURNINS = 25     -- turn-ins per snapshot (this session's)
Live.MAX_OBJECTIVES = 20
Live.RELAY_KEEP = 12 * 3600  -- seconds a stored snapshot for relaying is kept
Live.MAX_RELAY = 40       -- snapshots kept for relaying
Live.peers = {}      -- [guid] = { name, level, classId, quests = { [id] = { title, ready, o = { {h, n}, ... } } }, at }
Live.listeners = {}  -- functions() called when peer data or the roster changed

local db, myGuid, myName
local gen = 0
local turnins = {}   -- quests this toon turned in this session, for T (and its signed snapshot)
local mySig = ""
local queue, pumping = {}, false
local syncPending = false
local lastAnswer = -math.huge
local lastRoster = {}

-- Counters for /cl status, so a party test shows where messages stop: refused by the game, not relayed by the
-- server (our own messages come back to us when they went out), or not arriving from the others.
Live.stats = { sent = 0, refused = 0, echoed = 0, received = 0, prefix = nil }

local function notify()
  for _, fn in ipairs(Live.listeners) do pcall(fn) end
end

local function clean(s) return (tostring(s or ""):gsub("[|;,~:\n]", " ")) end

function Live.channel()
  if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
end

-- Sending ------------------------------------------------------------------------------------

local function pump()
  local item = table.remove(queue, 1)
  if not item then pumping = false return end
  local ch = Live.channel()
  if ch and C_ChatInfo and C_ChatInfo.SendAddonMessage then
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, Live.PREFIX, item.m, ch)
    if ok and (res == nil or res == 0 or res == true) then Live.stats.sent = Live.stats.sent + 1
    else Live.stats.refused = Live.stats.refused + 1; Live.stats.lastCode = ok and tostring(res) or "error" end
    -- The result is an enum on the modern client: 0 = sent; anything else = throttled or refused. Back off.
    if ok and type(res) == "number" and res ~= 0 and item.tries < 3 then
      item.tries = item.tries + 1
      table.insert(queue, 1, item)
      C_Timer.After(2, pump)
      return
    end
  end
  C_Timer.After(Live.SPACING, pump)
end

local function send(m)
  queue[#queue + 1] = { m = m, tries = 0 }
  if not pumping then pumping = true; C_Timer.After(0.05, pump) end
end

-- One line for /cl status.
function Live.statusLine()
  local st = Live.stats
  return string.format("live messages: sent %d · came back %d · received %d from others%s%s", st.sent, st.echoed, st.received,
    st.refused > 0 and (" · refused " .. st.refused .. " (code " .. tostring(st.lastCode) .. ")") or "",
    st.prefix == false and " · prefix NOT registered" or "")
end

-- Our current log as compact records, from the collector's snapshot.
function Live.records()
  local rec = db and myGuid and S.char(db, myGuid)
  local ids = {}
  for id in pairs((rec and rec.log) or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  local out = {}
  for _, id in ipairs(ids) do
    local q = rec.log[id]
    local objs, ready = {}, true
    for i, o in ipairs(q.o or {}) do
      if i <= Live.MAX_OBJECTIVES then objs[i] = (o.h or 0) .. "/" .. (o.n or 0) end
      if not o.f then ready = false end
    end
    out[#out + 1] = id .. "," .. (ready and "1" or "0") .. "," .. table.concat(objs, ":") .. "," .. clean(q.title):sub(1, 40)
  end
  return out
end

-- Party relay ---------------------------------------------------------------------------------
-- A toon's owner can let crewmates' syncs carry the toon's progress to the website while they're grouped (toon page on
-- the website). The website then puts a secret key for the toon into its owner's Inbox; only that PC has it. Our
-- snapshots are signed with it, and a crewmate who has "Upload my party's progress" on stores the last signed
-- snapshot of each party member for their app to upload. The website checks the signature, so a crewmate can pass a
-- snapshot along but never change or invent one.

--- The signed text of a snapshot: built the same way by the sender (from its own log) and by a receiver (from the
--- messages), and parsed by the website. quests = { [id] = { ready = bool, o = { {h, n}, ... } } }.
function Live.canonical(guid, ts, level, pos, quests, done)
  local ids = {}
  for id in pairs(quests or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  local qs = {}
  for _, id in ipairs(ids) do
    local q, objs = quests[id], {}
    for i, o in ipairs(q.o or {}) do
      if i <= Live.MAX_OBJECTIVES then objs[i] = (o.h or 0) .. "/" .. (o.n or 0) end
    end
    qs[#qs + 1] = id .. "," .. (q.ready and "1" or "0") .. "," .. table.concat(objs, ":")
  end
  local t = {}
  for i, id in ipairs(done or {}) do t[i] = id end
  table.sort(t)
  pos = pos or {}
  return table.concat({ "1", guid, ts, level or 0, pos.map or 0, pos.x or 0, pos.y or 0, table.concat(qs, ";"),
    table.concat(t, ",") }, "|")
end

-- Our relay key, from the Inbox (present only while our owner allows relaying).
function Live.key()
  local inbox = rawget(_G, "Crewlog_Inbox")
  local keys = type(inbox) == "table" and type(inbox.relayKeys) == "table" and inbox.relayKeys
  local k = keys and myGuid and keys[myGuid]
  return type(k) == "string" and Sign.unhex(k) and k or nil
end

-- Our position for P: uiMap and 0-1000 per axis, from the collector's last fix.
local function myPos()
  local rec = db and myGuid and S.char(db, myGuid)
  local p = rec and rec.pos
  if not (p and p.map and p.x and p.y) then return nil end
  return { map = p.map, x = math.floor(p.x * 10 + 0.5), y = math.floor(p.y * 10 + 0.5) }
end

-- Our log as the signature sees it.
local function myQuests()
  local rec = db and myGuid and S.char(db, myGuid)
  local out = {}
  for id, q in pairs((rec and rec.log) or {}) do
    local ready, o = true, {}
    for i, x in ipairs(q.o or {}) do
      o[i] = { h = x.h or 0, n = x.n or 0 }
      if not x.f then ready = false end
    end
    out[id] = { ready = ready, o = o }
  end
  return out
end

function Live.noteTurnIn(qid)
  for _, id in ipairs(turnins) do if id == qid then return end end
  turnins[#turnins + 1] = qid
  while #turnins > Live.MAX_TURNINS do table.remove(turnins, 1) end
end

function Live.relayOn() return db and db.ui and db.ui.relay == true end

function Live.setRelay(on)
  db.ui.relay = on or nil
  if not on then db.relay = nil end
end

-- Keep a peer's signed snapshot for our app to upload (newest per toon, a bounded number, none too old).
local function keep(guid, peer, ts, sig, canonical)
  db.relay = db.relay or {}
  db.relay[guid] = { s = canonical, sig = sig, name = peer.name, at = U.now(), ts = ts }
  local n, oldest, oldestAt = 0, nil, math.huge
  for g, r in pairs(db.relay) do
    n = n + 1
    if (r.at or 0) < oldestAt then oldest, oldestAt = g, r.at or 0 end
  end
  if n > Live.MAX_RELAY and oldest then db.relay[oldest] = nil end
end

local function pruneRelay()
  if type(db.relay) ~= "table" then db.relay = nil return end
  if not Live.relayOn() then db.relay = nil return end
  local now = U.now()
  for g, r in pairs(db.relay) do
    if type(r) ~= "table" or now - (tonumber(r.at) or 0) > Live.RELAY_KEEP then db.relay[g] = nil end
  end
end

function Live.sync()
  if not Live.channel() or not myGuid then return end
  -- A new snapshot replaces any older one still waiting to go out (a hello stays).
  for i = #queue, 1, -1 do if queue[i].m:sub(1, 1) ~= "H" then table.remove(queue, i) end end
  gen = gen + 1
  local head = "L|" .. myGuid .. "|" .. gen .. "|"
  local level = UnitLevel and UnitLevel("player") or 0
  local _, _, classId = UnitClass("player")
  send(table.concat({ "B", myGuid, gen, clean(myName), level, classId or 0 }, "|"))
  local cur = head
  for _, r in ipairs(Live.records()) do
    if #cur + #r + 1 > Live.MAX_BYTES and cur ~= head then send(cur); cur = head end
    cur = cur .. (cur == head and "" or ";") .. r
  end
  if cur ~= head then send(cur) end
  local pos = myPos()
  send(table.concat({ "P", myGuid, gen, pos and pos.map or 0, pos and pos.x or 0, pos and pos.y or 0 }, "|"))
  if #turnins > 0 then send("T|" .. myGuid .. "|" .. gen .. "|" .. table.concat(turnins, ",")) end
  local key = Live.key()
  if key then
    local ts = math.floor(U.now())
    local sig = Sign.sign(key, Live.canonical(myGuid, ts, level, pos, myQuests(), turnins))
    if sig then send(table.concat({ "S", myGuid, gen, ts, sig }, "|")) end
  end
  send("E|" .. myGuid .. "|" .. gen)
end

-- Debounced: many quest events arrive at once; one snapshot after things settle.
function Live.schedule(hello)
  if syncPending then return end
  syncPending = true
  C_Timer.After(Live.DEBOUNCE, function()
    syncPending = false
    if not Live.channel() then return end
    if hello then send("H|" .. myGuid) end
    mySig = table.concat(Live.records(), ";")
    Live.sync()
  end)
end

local function heartbeat()
  if Live.channel() then Live.sync() end
  C_Timer.After(Live.HEARTBEAT, heartbeat)
end

-- Receiving ----------------------------------------------------------------------------------

-- Text from another player, made safe to show: "|" starts the game's escape codes (colours, textures, links), so it
-- is doubled to show as itself; cut to a sane length.
local function shown(s, max) return (s:sub(1, max):gsub("|", "||")) end

local function parseRecord(r)
  local id, ready, objs, title = r:match("^(%d+),([01]),([%d/:]*),(.*)$")
  if not id then return end
  local q = { title = title ~= "" and shown(title, 60) or nil, ready = ready == "1", o = {} }
  for h, n in objs:gmatch("(%d+)/(%d+)") do
    if #q.o < 20 then q.o[#q.o + 1] = { h = tonumber(h), n = tonumber(n) } end
  end
  return tonumber(id), q
end

local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }

-- The group unit with this GUID, if any.
local function unitOf(guid)
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  local raid = IsInRaid and IsInRaid()
  for i = 1, n do
    local u = raid and ("raid" .. i) or ("party" .. i)
    if UnitGUID(u) == guid then return u end
  end
end

--- Whether a message about this GUID can be believed: it came over the group's channel, the GUID is a member, and the
--- sender ("Name" or "Name-Realm") is that member.
function Live.trusted(guid, channel, sender)
  if not GROUP_CHANNELS[channel or ""] then return false end
  local unit = unitOf(guid)
  if not unit then return false end
  local name = UnitName(unit)
  local short = sender and sender:match("^([^%-]+)")
  return name ~= nil and short ~= nil and short == name
end

-- Answering costs messages (the game throttles them): hellos and new peers get a snapshot at most every few seconds.
local function answer()
  local now = U.now()
  if now - lastAnswer < Live.HELLO_EVERY then return end
  lastAnswer = now
  Live.schedule(false)
end

function Live.handle(msg, channel, sender)
  local cmd, guid, rest = msg:match("^(%u)|([^|]+)|?(.*)$")
  if not cmd then return end
  if guid == myGuid then Live.stats.echoed = Live.stats.echoed + 1 return end -- our own messages come back to us
  if not Live.trusted(guid, channel, sender) then Live.stats.ignored = (Live.stats.ignored or 0) + 1 return end
  Live.stats.received = Live.stats.received + 1
  if cmd == "H" then
    answer() -- a newcomer: send them our log
    return
  end
  local peer = Live.peers[guid]
  if cmd == "B" then
    local g, name, level, classId = rest:match("^(%d+)|([^|]*)|(%d*)|(%d*)$")
    if not g then return end
    if not peer then peer = { quests = {} }; Live.peers[guid] = peer; answer() end
    peer.name, peer.level, peer.classId = shown(name, 24), tonumber(level), tonumber(classId)
    peer.pendingGen, peer.pending, peer.pendingCount = g, {}, 0
    peer.pendingLevel, peer.pendingPos, peer.pendingDone, peer.pendingSig = tonumber(level), nil, nil, nil
  elseif cmd == "L" then
    local g, body = rest:match("^(%d+)|(.*)$")
    if not (peer and g and peer.pendingGen == g) then return end
    for r in body:gmatch("[^;]+") do
      local id, q = parseRecord(r)
      if id and not peer.pending[id] and peer.pendingCount < Live.MAX_QUESTS then
        peer.pending[id] = q
        peer.pendingCount = peer.pendingCount + 1
      end
    end
  elseif cmd == "P" then
    local g, map, x, y = rest:match("^(%d+)|(%d+)|(%d+)|(%d+)$")
    if not (peer and g and peer.pendingGen == g) then return end
    map, x, y = tonumber(map), tonumber(x), tonumber(y)
    if map > 0 and x <= 1000 and y <= 1000 then peer.pendingPos = { map = map, x = x, y = y } end
  elseif cmd == "T" then
    local g, ids = rest:match("^(%d+)|([%d,]*)$")
    if not (peer and g and peer.pendingGen == g) then return end
    local done = {}
    for id in ids:gmatch("%d+") do if #done < Live.MAX_TURNINS then done[#done + 1] = tonumber(id) end end
    peer.pendingDone = done
  elseif cmd == "S" then
    local g, ts, sig = rest:match("^(%d+)|(%d+)|(%x+)$")
    if not (peer and g and peer.pendingGen == g) or #sig ~= Sign.LENGTH then return end
    peer.pendingSig = { ts = tonumber(ts), sig = sig:lower() }
  elseif cmd == "E" then
    if not (peer and peer.pendingGen == rest and peer.pending) then return end
    peer.quests, peer.pending, peer.pendingGen = peer.pending, nil, nil
    peer.pos, peer.done = peer.pendingPos, peer.pendingDone
    local signed = peer.pendingSig
    if signed and Live.relayOn() then
      keep(guid, peer, signed.ts, signed.sig, Live.canonical(guid, signed.ts, peer.pendingLevel, peer.pos, peer.quests, peer.done))
    end
    peer.pendingSig = nil
    peer.at = U.now()
    notify()
  end
end

-- Roster -------------------------------------------------------------------------------------

local function groupGuids()
  local set = {}
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  local raid = IsInRaid and IsInRaid()
  for i = 1, n do
    local g = UnitGUID(raid and ("raid" .. i) or ("party" .. i))
    if g then set[g] = true end
  end
  return set
end

function Live.onRoster()
  local set = groupGuids()
  local changed = false
  for g in pairs(Live.peers) do
    if not set[g] then Live.peers[g] = nil; changed = true end
  end
  local grew = false
  for g in pairs(set) do if not lastRoster[g] and g ~= myGuid then grew = true end end
  lastRoster = set
  if grew then Live.schedule(true) end
  if changed then notify() end
end

function Live.onQuestLog()
  if not Live.channel() then return end
  local sig = table.concat(Live.records(), ";")
  if sig ~= mySig then Live.schedule(false) end
end

-- Peers as a sorted list for display.
function Live.list()
  local out = {}
  for g, p in pairs(Live.peers) do if p.at then out[#out + 1] = { guid = g, peer = p } end end
  table.sort(out, function(a, b) return (a.peer.name or "") < (b.peer.name or "") end)
  return out
end

-- Colours and markers (both opt-in) ---------------------------------------------------------

local PALETTE = {
  { 1.00, 0.35, 0.35 }, { 0.30, 0.80, 1.00 }, { 0.47, 0.90, 0.43 }, { 1.00, 0.78, 0.24 },
  { 0.78, 0.47, 1.00 }, { 1.00, 0.55, 0.78 }, { 1.00, 0.59, 0.24 }, { 0.47, 1.00, 0.90 },
}

local function classColor(classId)
  local file = classId and GetClassInfo and select(2, GetClassInfo(classId))
  local c = file and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(file)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]))
  if c then return c.r, c.g, c.b end
  return 1, 1, 1
end

-- With member colours on: one colour per member, picked by sorted GUID, so everyone sees the same colours.
-- Off (default): the usual class colours.
function Live.color(guid)
  local peer = Live.peers[guid]
  if not (db and db.ui and db.ui.colors) then return classColor(peer and peer.classId) end
  local all = { myGuid }
  for g in pairs(Live.peers) do all[#all + 1] = g end
  table.sort(all)
  for i, g in ipairs(all) do
    if g == guid then local c = PALETTE[(i - 1) % #PALETTE + 1]; return c[1], c[2], c[3] end
  end
  return 1, 1, 1
end

function Live.hex(guid)
  local r, g, b = Live.color(guid)
  return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local icons = {}
Live._icons = icons -- for tests
local MARKER = "Interface\\AddOns\\Crewlog\\media\\minimap"

local function attach(unit)
  if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
  local plate = C_NamePlate.GetNamePlateForUnit(unit)
  if not plate then return end
  local g = UnitGUID(unit)
  local ic = icons[plate]
  if not (db.ui.markers and g and Live.peers[g]) then
    if ic then ic:Hide() end
    return
  end
  if not ic then
    ic = CreateFrame("Frame", nil, plate)
    ic:SetSize(20, 20)
    ic.tex = ic:CreateTexture(nil, "OVERLAY")
    ic.tex:SetAllPoints()
    ic.tex:SetTexture(MARKER)
    icons[plate] = ic
  end
  ic:ClearAllPoints()
  ic:SetPoint("BOTTOM", plate, "TOP", 0, 4)
  if db.ui.colors then ic.tex:SetVertexColor(Live.color(g)) else ic.tex:SetVertexColor(1, 1, 1) end
  ic:Show()
end

function Live.refreshMarkers()
  if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
  for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
    local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
    if unit then attach(unit) end
  end
end

-- Markers need friendly nameplates. Turning markers on switches them on (out of combat only) and remembers that,
-- so turning markers off puts the setting back the way it was.
function Live.setMarkers(on)
  if InCombatLockdown and InCombatLockdown() then return false, "not in combat" end
  db.ui.markers = on or nil
  if on and GetCVar and GetCVar("nameplateShowFriends") ~= "1" then
    SetCVar("nameplateShowFriends", "1")
    db.ui.markersCVar = true
  elseif not on and db.ui.markersCVar then
    SetCVar("nameplateShowFriends", "0")
    db.ui.markersCVar = nil
  end
  Live.refreshMarkers()
  return true
end

function Live.setColors(on)
  db.ui.colors = on or nil
  Live.refreshMarkers()
  notify()
end

-- Wiring -------------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
for _, e in ipairs({ "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "QUEST_ACCEPTED",
  "QUEST_REMOVED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }) do
  frame:RegisterEvent(e)
end
frame:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
  if not myGuid then return end
  if event == "CHAT_MSG_ADDON" then
    if a1 == Live.PREFIX then Live.handle(a2 or "", a3, a4) end
  elseif event == "GROUP_ROSTER_UPDATE" then
    Live.onRoster()
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    attach(a1)
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(a1)
    if plate and icons[plate] then icons[plate]:Hide() end
  else
    -- quest log changes: the collector updates its snapshot first (0.5 s debounce), so look a moment later
    C_Timer.After(0.6, Live.onQuestLog)
  end
end)

function Live.Start(theDb, guid, name)
  db, myGuid, myName = theDb, guid, name
  db.ui = db.ui or {}
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    local ok, res = pcall(C_ChatInfo.RegisterAddonMessagePrefix, Live.PREFIX)
    Live.stats.prefix = ok and res ~= false and res ~= 2 and res ~= 3 -- 1 = already registered: fine
  end
  Live.listeners[#Live.listeners + 1] = Live.refreshMarkers
  pruneRelay()
  if ns.Collector and ns.Collector.listeners then
    local L = ns.Collector.listeners
    L[#L + 1] = function(ev) if ev.k == "TURNIN" and ev.c == myGuid then Live.noteTurnIn(ev.q) end end
  end
  Live.onRoster()
  C_Timer.After(Live.HEARTBEAT, heartbeat)
end
