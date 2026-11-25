-- Plays a short session through the Crewlog addon and checks the SavedVariables it produces.
-- Also writes fixtures/generated/CrewlogDB*.lua, which the .NET parser tests read.
-- Run from the repo root: lua5.1 addon/tests/collector_test.lua
local H = dofile("addon/tests/harness.lua")
local st = H.state

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end
local function eventsOf(db, kind)
  local out = {}
  for _, e in ipairs(db.events) do if e.k == kind then out[#out + 1] = e end end
  return out
end

-- Starting state: two quests done, header + one quest in the log.
st.completed = { 4641, 3911 }
st.log = {}
st.log[1] = { header = "Valley of Trials" }
H.addQuest(788, "Cutting Teeth", 2, { { 5, 10, false, "monster" } })

-- An inbox from a previous sync acknowledging seq <= 2 for this character + old harvest.
Crewlog_Inbox = { schema = 1, generatedAt = st.time - 600, ack = { [st.guid] = 2 }, harvestAck = st.time - 700 }
CrewlogDB = {
  schema = 1, installId = "abc",
  chars = { [st.guid] = { seq = 3, completed = { 3911 }, log = {} } },
  events = {
    { c = st.guid, s = 1, t = 1, k = "ACCEPT", q = 4641 },
    { c = st.guid, s = 2, t = 2, k = "TURNIN", q = 4641 },
    { c = st.guid, s = 3, t = 3, k = "ACCEPT", q = 788 },
  },
  harvest = { quests = { [4641] = { t = st.time - 800, title = "old" }, [788] = { t = st.time - 100, title = "kept" } } },
}

local ns = H.load("Crewlog", { "Util.lua", "Store.lua", "Harvest.lua", "Collector.lua", "Live.lua", "Crew.lua", "Next.lua", "Tooltips.lua", "Way.lua", "Route.lua", "UI.lua", "Core.lua" })
H.fire("ADDON_LOADED", "Crewlog")
H.fire("PLAYER_LOGIN")
local db = CrewlogDB

-- 1. load + prune + snapshot
check(#db.events == 1 and db.events[1].s == 3, "acked events pruned, unacked kept")
check(db.harvest.quests[4641] == nil and db.harvest.quests[788] ~= nil, "acked harvest pruned")
local rec = db.chars[st.guid]
check(rec.name == "Zarnokk" and rec.class == "ROGUE" and rec.race == "Troll" and rec.realmId == 6949 and rec.raceId == 8 and rec.classId == 4 and rec.sex == 3, "character attributes")
check(#rec.completed == 2 and rec.completed[1] == 3911 and rec.completed[2] == 4641, "completed list sorted from API")
check(rec.log[788] and rec.log[788].o[1].h == 5 and rec.log[0] == nil, "log snapshot skips headers")
check(rec.log[788].o[1].t == "Mottled Boar slain", "objective text kept without the counter")
check(ns.U.objectiveLabel("Goretusk Liver: 4/8") == "Goretusk Liver" and ns.U.objectiveLabel("Speak with Gornek") == "Speak with Gornek" and ns.U.objectiveLabel("") == nil, "objective label formats")
check(rec.seq == 3, "sequence continues from SavedVariables")

-- 2. accept a quest at an NPC (offer dialog first)
st.npcGuid = "Creature-0-58868-1-14556280-3143-82878CE44C"
st.dialogQuest, st.dialogTitle, st.dialogObjective = 97279, "Wayward Weapons", "Collect 6 Abandoned Training Weapons."
H.fire("QUEST_DETAIL", 0)
H.addQuest(97279, "Wayward Weapons", 2, { { 0, 6, false, "item" } })
H.fire("QUEST_ACCEPTED", 97279)
local acc = eventsOf(db, "ACCEPT")
check(#acc == 2 and acc[2].q == 97279 and acc[2].s == 4, "ACCEPT recorded with next seq")
local hv = db.harvest.quests[97279]
check(hv and hv.giver and hv.giver.npc == 3143 and hv.giver.map == 1411 and hv.giver.x == 0.4323, "quest giver harvested")
check(hv.lvl == 2 and hv.title == "Wayward Weapons", "harvest enriched on accept")

-- 3. objective progress
H.setObjective(788, 1, 6)
H.fire("QUEST_WATCH_UPDATE", 788)
H.flush()
H.setObjective(788, 1, 7)
H.fire("QUEST_LOG_UPDATE")
H.fire("QUEST_LOG_UPDATE")
H.advance(1)
local prog = eventsOf(db, "PROGRESS")
check(#prog == 2 and prog[1].h == 6 and prog[2].h == 7 and prog[2].n == 10, "PROGRESS via watch update and debounced log update")

-- 4. turn in, then the chained quest from the same NPC
H.setObjective(788, 1, 10)
H.fire("QUEST_WATCH_UPDATE", 788); H.flush()
st.dialogQuest, st.dialogTitle = 788, "Cutting Teeth"
H.fire("QUEST_COMPLETE")
H.removeQuest(788)
st.completed[#st.completed + 1] = 788
H.fire("QUEST_TURNED_IN", 788, 450, 0)
H.fire("QUEST_REMOVED", 788, false)
H.advance(1)
check(#eventsOf(db, "TURNIN") == 1 and #eventsOf(db, "ABANDON") == 0, "turn-in is not mistaken for abandon")
check(rec.completed[3] == 4641 or rec.completed[#rec.completed] == 4641, "completed still sorted")
local has788 = false
for _, v in ipairs(rec.completed) do if v == 788 then has788 = true end end
check(has788 and rec.log[788] == nil, "turned-in quest moved from log to completed")
check(db.harvest.quests[788].ender.npc == 3143, "turn-in NPC harvested")
local f = eventsOf(db, "PROGRESS")
check(f[#f].f == true and f[#f].h == 10, "final objective marks finished")

H.advance(5)
st.dialogQuest, st.dialogTitle = 790, "Sarkoth"
H.fire("QUEST_DETAIL", 0)
check(db.harvest.quests[790].after == 788, "chain hint: accepted right after turn-in at same NPC")

-- 5. abandon
H.fire("QUEST_ACCEPTED", 97279) -- duplicate accept is ignored
H.removeQuest(97279)
H.fire("QUEST_REMOVED", 97279, false)
H.advance(1)
local ab = eventsOf(db, "ABANDON")
check(#ab == 1 and ab[1].q == 97279, "abandon detected")

-- 6. level + zone
-- Map unknown at login (as on the real client): the first fix is stored silently, not a ZONE event.
rec.map = nil
st.map = 1411
H.fire("ZONE_CHANGED_NEW_AREA")
check(rec.map == 1411 and #eventsOf(db, "ZONE") == 0, "first map fix after login is not a zone change")
st.level = 2
H.fire("PLAYER_LEVEL_UP", 2)
st.map = 1412
H.fire("ZONE_CHANGED_NEW_AREA")
H.fire("ZONE_CHANGED_NEW_AREA")
check(#eventsOf(db, "LEVEL") == 1 and rec.level == 2, "level up")
check(#eventsOf(db, "ZONE") == 1 and rec.map == 1412, "zone change deduplicated")

-- 7. seq is gapless and strictly increasing
local okSeq = true
for i = 2, #db.events do if db.events[i].s ~= db.events[i - 1].s + 1 then okSeq = false end end
check(okSeq, "event sequence numbers are consecutive")

-- 8. Sync button: confirm popup, shift-click skips it, never reload in combat
local mm = _G.CrewlogMinimapButton
ns.UI.Sync(false)
check(H.popups[#H.popups] == "CREWLOG_SYNC" and H.reloads == 0, "click asks before reloading")
StaticPopupDialogs.CREWLOG_SYNC.OnAccept()
check(H.reloads == 1, "accepting the popup reloads (= sync)")
H.inCombat = true
ns.UI.Sync(true)
check(H.reloads == 1, "no reload in combat")
H.inCombat = false
H.fire("PLAYER_REGEN_ENABLED")
check(H.popups[#H.popups] == "CREWLOG_SYNC", "sync offered again after combat")
Crewlog_OnAddonCompartmentClick(nil, "LeftButton")
H.shift = true
Crewlog_OnAddonCompartmentClick(nil, "LeftButton")
check(H.reloads == 2, "shift-click in the addon compartment syncs without asking")
H.shift = false
GameTooltip.lines = {}
ns.UI.Tooltip(GameTooltip)
check(GameTooltip.lines[2] and GameTooltip.lines[2]:match("waiting to sync"), "tooltip shows pending updates")
SlashCmdList.CREWLOG("minimap")
check(db.ui.hideMinimap == true, "/cl minimap hides the button")
SlashCmdList.CREWLOG("minimap")
check(db.ui.hideMinimap == false, "/cl minimap shows it again")

-- 9. Journal crew from the Inbox
local me = ns.Collector.guid()
local inboxData = { generatedAt = 1, journals = {
  { title = "Tuesday crew", toons = {
    { guid = me, name = "Me", mine = true, quests = { { id = 789, title = "Sting", done = 0, total = 1 } } },
    { guid = "Player-1-BOB", name = "Brogg", owner = "Bob", level = 5, zone = "Durotar", updated = 1,
      quests = { { id = 789, title = "Sting of the Scorpid", done = 1, total = 1, ready = true }, { id = 790, title = "Sarkoth", done = 0, total = 1 } } },
  } },
  { title = "Alts", toons = { { guid = me, name = "Me", mine = true, quests = {} } } },
  { title = "Raid", toons = { { guid = "Player-1-BOB", name = "Brogg", quests = {} } } },
} }
local mates = ns.Crew.mates(inboxData, me)
check(#mates == 1 and mates[1].name == "Brogg", "crew excludes the toon you play and duplicates across journals")
check(#ns.Crew.onQuest(inboxData, me, 789) == 1, "who else is on a quest")
local text = table.concat(ns.Crew.lines(inboxData, me, { [789] = true }), "\n")
check(text:find("Sting of the Scorpid", 1, true) and text:find("you too", 1, true), "crew window marks shared quests")
check(text:find("Nobody else", 1, true), "journal without others says so")
check(ns.Crew.lines(nil, me, {})[1]:find("not in a journal", 1, true), "no inbox: explains what to do")
_G.Crewlog_Inbox = inboxData
GameTooltip.lines = {}
ns.UI.Tooltip(GameTooltip)
local tip = table.concat(GameTooltip.lines, "\n")
check(tip:find("Crew", 1, true) and tip:find("Brogg", 1, true), "tooltip lists the crew")
SlashCmdList.CREWLOG("crew")
check(_G.CrewlogCrewFrame ~= nil, "/cl opens the crew window")
_G.Crewlog_Inbox = nil

-- 10. slash command does not error
SlashCmdList.CREWLOG("status")
SlashCmdList.CREWLOG("debug")
check(#H.chat >= 4, "slash output")

st.map, st.pos = 1411, { 0.4323, 0.6871 }
H.fire("PLAYER_LEAVING_WORLD")
do
  local p = db.chars[st.guid].pos
  check(p and p.map == 1411 and p.x == 43.2 and p.y == 68.7, "position saved for the route map (0-100)")
end
H.fire("PLAYER_LOGOUT")

-- Fixtures for the .NET parser (two serializer styles).
os.execute("mkdir -p fixtures/generated")
H.writeSavedVariables("fixtures/generated/CrewlogDB.lua", "CrewlogDB", db, false)
H.writeSavedVariables("fixtures/generated/CrewlogDB.indexcomments.lua", "CrewlogDB", db, true)

print(string.format("%d passed, %d failed · %d events, seq %d, harvest %d quests",
  passed, failed, #db.events, rec.seq, (function() local n = 0 for _ in pairs(db.harvest.quests) do n = n + 1 end return n end)()))
if failed > 0 then os.exit(1) end
