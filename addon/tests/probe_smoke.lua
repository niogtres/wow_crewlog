-- Smoke test for Crewlog_Probe outside the game: stub a minimal WoW API, load Probe.lua,
-- fire the login events, run /crewprobe, and check what lands in Crewlog_ProbeDB.
-- Run: lua5.1 addon/tests/probe_smoke.lua   (from the repo root)

local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }

local handlers, registeredEvents = {}, {}
function CreateFrame()
  local f = {}
  function f:RegisterEvent(ev)
    if ev == "QUEST_LOG_CRITERIA_UPDATE" then error("unknown event " .. ev) end -- pretend one doesn't exist
    registeredEvents[ev] = true
  end
  function f:SetScript(_, fn) handlers[#handlers + 1] = fn end
  return f
end
local function fire(ev, ...) for _, h in ipairs(handlers) do h(nil, ev, ...) end end

SlashCmdList = {}
time = os.time -- WoW exposes these as globals
date = os.date
WOW_PROJECT_ID = 2
WOW_PROJECT_CLASSIC = 2
WOW_PROJECT_MAINLINE = 1
function GetBuildInfo() return "1.60.1", "71037", "Nov 18 2026", 16001 end
function GetLocale() return "enUS" end
function GetRealmName() return "Testrealm" end
function GetServerTime() return 1795450000 end
function GetMaxPlayerLevel() return 60 end
function UnitGUID(u) return u == "player" and "Player-1234-0A1B2C3D" or nil end
function UnitName() return "Thornwick" end
function UnitLevel() return 18 end
function UnitRace() return "Dwarf", "Dwarf", 3 end
function UnitClass() return "Warrior", "WARRIOR", 1 end
function UnitFactionGroup() return "Alliance", "Alliance" end
function GetRealZoneText() return "Westfall" end
function GetSubZoneText() return "Sentinel Hill" end
function IsInGroup() return false end
function IsInRaid() return false end
-- Classic-style quest API, with a nil in the middle of GetQuestLogTitle's returns.
function GetQuestsCompleted(t) t[176] = true; t[239] = true; t[783] = true; return t end
function IsQuestFlaggedCompleted(id) return id == 783 end
function GetNumQuestLogEntries() return 2, 2 end
function GetQuestLogTitle(i) return (i == 1 and "Westfall Stew" or "Patrolling Westfall"), 14, nil, false, false, false, nil, (i == 1 and 36 or 102) end
function GetNumQuestLeaderBoards() return 1 end
function GetQuestLogLeaderBoard(j, i) return "Goretusk Liver: 4/8", "item", false end
C_Map = {
  GetBestMapForUnit = function() return 1436 end,
  GetMapInfo = function(id) return { mapID = id, name = "Westfall", mapType = 3 } end,
  GetPlayerMapPosition = function() return { GetXY = function() return 0.56, 0.47 end } end,
}
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() return true end,
  IsAddonMessagePrefixRegistered = function() return true end,
  SendAddonMessage = function() return true end,
}
C_Timer = { After = function() end }

-- Load the addon the way WoW does: the chunk receives (addonName, addonTable).
local chunk = assert(loadfile("addon/Crewlog_Probe/Probe.lua"))
chunk("Crewlog_Probe", {})

fire("ADDON_LOADED", "Crewlog_Probe")
fire("PLAYER_LOGIN")
fire("QUEST_ACCEPTED", 3, 102)
fire("QUEST_TURNED_IN", 36, 450, 0)
SlashCmdList.CREWLOGPROBE()

-- Assertions
local db = assert(Crewlog_ProbeDB, "SavedVariables table missing")
local run = assert(db.runs and db.runs[1], "no probe run recorded")
assert(run.environment.build.ok and run.environment.build[4] == 16001, "build info not captured")
assert(run.completed.classic and run.completed.classic.count == 3, "classic completed count wrong")
assert(run.completed.modern == nil, "modern API should be absent in this stub")
assert(#run.log.entries == 2, "expected 2 quest log entries")
assert(run.log.entries[1].questID == 36, "questID lost behind a nil return (select('#') regression)")
assert(run.log.entries[1].oldTitle.n == 8, "return count should be 8 including nils")
assert(run.player.mapPos and math.abs(run.player.mapPos.x - 0.56) < 1e-9, "map position missing")
assert(#db.events.rejected == 1 and db.events.rejected[1] == "QUEST_LOG_CRITERIA_UPDATE", "unknown event not handled")
assert(db.eventCounts.QUEST_TURNED_IN == 1, "event logger did not count QUEST_TURNED_IN")
assert(run.comms.sendSelf.ok, "self whisper addon message failed")
local foundMissing = false
for _, p in ipairs(run.functions.missing) do if p == "C_QuestLog.GetAllCompletedQuestIDs" then foundMissing = true end end
assert(foundMissing, "missing-function detection broken")

print("chat output:")
for _, m in ipairs(chat) do print("  " .. m:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
print(string.format("OK: %d APIs present, %d missing, %d events registered, %d logged",
  #run.functions.present, #run.functions.missing, #db.events.registered, #db.eventLog))
