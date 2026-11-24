-- Live party sync (Live.lua): message format, round trip, snapshots, roster, and the opt-in colours and markers.
-- Run from the repo root: lua5.1 addon/tests/live_test.lua
local H = dofile("addon/tests/harness.lua")
local st = H.state

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

local BOB = "Player-6949-0B0B0B0B"
st.log = { { header = "Durotar" } }
H.addQuest(789, "Sting of the Scorpid", 3, { { 4, 10, false, "item", "Scorpid Worker Tail" } })
H.addQuest(4641, "Your Place In The World", 1, {})
CrewlogDB = nil

local ns = H.load("Crewlog", { "Util.lua", "Store.lua", "Harvest.lua", "Collector.lua", "Live.lua", "Crew.lua", "Next.lua", "Tooltips.lua", "UI.lua", "Core.lua" })
local Live = ns.Live
H.fire("ADDON_LOADED", "Crewlog")
H.fire("PLAYER_LOGIN")
H.advance(2)
local db = CrewlogDB

local function deliver(list, asGuid)
  for _, m in ipairs(list) do
    local msg = m.msg
    if asGuid then msg = msg:gsub(st.guid:gsub("%-", "%%-"), asGuid) end
    H.fire("CHAT_MSG_ADDON", m.prefix, msg, m.channel, "Someone")
  end
end
local function kinds(list)
  local out = {}
  for _, m in ipairs(list) do out[#out + 1] = m.msg:sub(1, 1) end
  return table.concat(out)
end

-- 1. Solo: nothing is sent.
check(#H.sent == 0, "no addon messages outside a group")

-- 2. Bob joins: hello, then a full snapshot over PARTY, every message within 250 bytes.
H.group.members = { { BOB, "Brogg" } }
H.fire("GROUP_ROSTER_UPDATE")
H.advance(3)
check(kinds(H.sent) == "HBLE", "join sends hello + B/L/E snapshot, got " .. kinds(H.sent))
local okLen, okPrefix = true, true
for _, m in ipairs(H.sent) do
  if #m.msg > 250 then okLen = false end
  if m.prefix ~= "CL1" or m.channel ~= "PARTY" then okPrefix = false; print("  bad:", m.prefix, m.channel, m.msg) end
end
check(okLen and okPrefix, "prefix CL1 on PARTY, <= 250 bytes")
check(H.sent[3].msg:find("789,0,4/10,Sting of the Scorpid", 1, true) and H.sent[3].msg:find("4641,1,,Your Place In The World", 1, true),
  "records carry id, ready flag, objective counts and title")

-- 3. Our own messages echo back: ignored.
deliver(H.sent)
check(next(Live.peers) == nil, "own messages are ignored (keyed by GUID)")

-- 4. Round trip as Bob: Bob's client sends the same log; we decode it fully.
local mine = H.sent
H.sent = {}
deliver(mine, BOB)
local bob = Live.peers[BOB]
check(bob and bob.name == "Zarnokk" and bob.level == 1 and bob.classId == 4, "peer identity from B")
check(bob and bob.quests[789] and bob.quests[789].o[1].h == 4 and bob.quests[789].o[1].n == 10 and bob.quests[789].title == "Sting of the Scorpid", "objective counts decoded")
check(bob and bob.quests[4641] and bob.quests[4641].ready, "ready flag decoded")
H.advance(3)
check(kinds(H.sent):find("BLE"), "a new peer gets our snapshot back")
H.sent = {}

-- 5. A snapshot only counts once it is complete; quests missing from it are dropped.
local gen = "99"
H.fire("CHAT_MSG_ADDON", "CL1", "B|" .. BOB .. "|" .. gen .. "|Brogg|5|1", "PARTY", "Brogg")
H.fire("CHAT_MSG_ADDON", "CL1", "L|" .. BOB .. "|" .. gen .. "|789,0,9/10,Sting of the Scorpid", "PARTY", "Brogg")
check(bob.quests[4641] ~= nil, "half a snapshot changes nothing yet")
H.fire("CHAT_MSG_ADDON", "CL1", "E|" .. BOB .. "|" .. gen, "PARTY", "Brogg")
check(bob.quests[4641] == nil and bob.quests[789].o[1].h == 9 and bob.name == "Brogg" and bob.classId == 1, "complete snapshot replaces the old one")
H.fire("CHAT_MSG_ADDON", "CL1", "L|" .. BOB .. "|100|1,0,,X", "PARTY", "Brogg")
check(bob.quests[1] == nil, "chunks without a matching begin are ignored")
H.fire("CHAT_MSG_ADDON", "OTHER", "B|" .. BOB .. "|1|x|1|1", "PARTY", "Brogg")
check(bob.name == "Brogg", "other prefixes are ignored")

-- 6. A big log splits into several chunks and survives the round trip.
for i = 1, 30 do H.addQuest(5000 + i, "A Rather Long Quest Title With Words " .. i, 10, { { 1, 8, false }, { 0, 3, false } }) end
H.fire("QUEST_LOG_UPDATE")
H.advance(8) -- 10+ messages, one every 0.3 s
local chunks = 0
for _, m in ipairs(H.sent) do if m.msg:sub(1, 1) == "L" then chunks = chunks + 1 end end
check(chunks >= 3, "long log is split into several L chunks (" .. chunks .. ")")
local big = H.sent
H.sent = {}
local CARL = "Player-6949-0CA0CA0C"
H.group.members = { { BOB, "Brogg" }, { CARL, "Carl" } }
H.fire("GROUP_ROSTER_UPDATE")
deliver(big, CARL)
local n = 0
for _ in pairs(Live.peers[CARL].quests) do n = n + 1 end
check(n == 32, "all 32 quests arrive across chunks (" .. n .. ")")
check(Live.peers[CARL].quests[5007].o[2].n == 3, "multi-objective counts survive")

-- 7. Objective progress triggers a fresh snapshot (debounced).
H.advance(12) -- let Carl's welcome snapshot finish sending
H.sent = {}
H.setObjective(789, 1, 5)
H.fire("QUEST_WATCH_UPDATE", 789)
H.fire("QUEST_LOG_UPDATE")
H.advance(1)
check(#H.sent == 0, "debounced: nothing sent immediately")
H.advance(3)
check(kinds(H.sent):sub(1, 1) == "B" and table.concat((function() local t = {} for _, m in ipairs(H.sent) do t[#t + 1] = m.msg end return t end)(), "\n"):find("789,0,5/10", 1, true),
  "progress goes out within a few seconds")

-- 8. A hello from someone makes us send our log.
H.sent = {}
H.fire("CHAT_MSG_ADDON", "CL1", "H|" .. CARL, "PARTY", "Carl")
H.advance(3)
check(kinds(H.sent):find("BL"), "hello answered with a snapshot")

-- 9. Crew window: live party on top, shared quests marked, journal duplicates collapsed.
Crewlog_Inbox = { journals = { { title = "Tuesday crew", toons = { { guid = BOB, name = "Brogg", quests = {} } } } } }
local text = table.concat(ns.Crew.lines(Crewlog_Inbox, st.guid, ns.Crew.myQuests(), Live.list()), "\n")
check(text:find("Live in your party", 1, true) and text:find("Brogg", 1, true) and text:find("you too", 1, true), "crew window shows the live party")
check(text:find("(live above)", 1, true), "journal toon who is live isn't repeated")
check(text:find("9/10", 1, true), "live progress shown")
GameTooltip.lines = {}
ns.UI.Tooltip(GameTooltip)
check(table.concat(GameTooltip.lines, "\n"):find("with Crewlog, live", 1, true), "tooltip shows the live party")

-- 10. Colours are opt-in: class colours by default, a per-member palette when switched on.
local r, g, b = Live.color(BOB)
check(not db.ui.colors and r == 0.78 and g == 0.61, "default: class colour (Brogg is a warrior)")
SlashCmdList.CREWLOG("colors")
local r2 = Live.color(BOB)
check(db.ui.colors and r2 ~= 0.78, "after /cl colors: palette colour")
SlashCmdList.CREWLOG("colors")
check(not db.ui.colors, "/cl colors toggles off again")

-- 11. Markers are opt-in and put the nameplate setting back when switched off.
local plate = H.addPlate("party1")
H.fire("NAME_PLATE_UNIT_ADDED", "party1")
check(Live._icons[plate] == nil and H.cvars.nameplateShowFriends == "0", "no marker and no setting change by default")
H.inCombat = true
SlashCmdList.CREWLOG("markers")
check(not db.ui.markers and H.cvars.nameplateShowFriends == "0", "markers can't be switched in combat")
H.inCombat = false
SlashCmdList.CREWLOG("markers")
check(db.ui.markers and H.cvars.nameplateShowFriends == "1", "markers on: friendly nameplates switched on")
check(Live._icons[plate] ~= nil, "marker attached to the party member's nameplate")
SlashCmdList.CREWLOG("markers")
check(not db.ui.markers and H.cvars.nameplateShowFriends == "0", "markers off: nameplate setting restored")
H.cvars.nameplateShowFriends = "1"
SlashCmdList.CREWLOG("markers")
SlashCmdList.CREWLOG("markers")
check(H.cvars.nameplateShowFriends == "1", "a setting the player had on themselves is left on")

-- 11b. Counters for /cl status: what went out, came back, arrived; refusals with the game's code.
local ls = Live.stats
check(ls.sent > 0 and ls.received > 0 and ls.prefix == true, "counters: sent " .. ls.sent .. ", received " .. ls.received)
local echoedBefore = ls.echoed
Live.handle("E|" .. H.state.guid .. "|1")
check(ls.echoed == echoedBefore + 1, "our own message coming back counts as echoed, not received")
local realSend = C_ChatInfo.SendAddonMessage
C_ChatInfo.SendAddonMessage = function() return 3 end
Live.sync()
H.advance(10)
C_ChatInfo.SendAddonMessage = realSend
H.advance(10)
check(ls.refused > 0 and ls.lastCode == "3", "refused sends counted with the game's code")
local line = Live.statusLine()
check(line:find("sent %d+") and line:find("came back") and line:find("refused") and line:find("code 3"), "status line: " .. line)

-- 12. Leaving: peers are dropped, nothing more is sent.
H.group.members = {}
H.fire("GROUP_ROSTER_UPDATE")
check(next(Live.peers) == nil, "peers dropped after leaving the group")
H.sent = {}
H.advance(60)
check(#H.sent == 0, "no heartbeat outside a group")

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
