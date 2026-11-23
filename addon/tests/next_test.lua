-- M5 in game: the Next up tab (Next.lua) and crew lines on quest tooltips (Tooltips.lua).
-- Run from the repo root: lua5.1 addon/tests/next_test.lua
local H = dofile("addon/tests/harness.lua")
local st = H.state

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

st.completed = { 788 }
st.log = { { header = "Durotar" } }
H.addQuest(789, "Sting of the Scorpid", 3, { { 2, 10, false, "item", "Scorpid Worker Tail" } })
st.map = 1411 -- Durotar
CrewlogDB = nil

local ns = H.load("Crewlog", { "Util.lua", "Store.lua", "Harvest.lua", "Collector.lua", "Live.lua", "Crew.lua", "Next.lua", "Tooltips.lua", "UI.lua", "Core.lua" })
H.fire("ADDON_LOADED", "Crewlog")
H.fire("PLAYER_LOGIN")
H.advance(1)
local me = st.guid

Crewlog_Inbox = {
  generatedAt = st.time,
  next = {
    { guid = me, area = 215, uiMap = 1412, zone = "Mulgore", quests = { { id = 743, title = "Dangers of the Windfury", level = 8 } } },
    { guid = me, area = 14, uiMap = 1411, zone = "Durotar", quests = {
      { id = 788, title = "Cutting Teeth", level = 2 },
      { id = 789, title = "Sting of the Scorpid", level = 3 },
      { id = 792, title = "Vile Familiars", level = 4, soon = true, why = "unlocks 1 more", giver = "Zureetha Fargaze · Durotar (42.9, 69.2)" },
    } },
    { guid = "Player-1-SOMEONEELSE", area = 14, uiMap = 1411, zone = "Durotar", quests = { { id = 1, title = "Not mine", level = 1 } } },
  },
  journals = {
    { title = "Tuesday crew",
      toons = {
        { guid = "Player-1-BROGG", name = "Brogg", quests = { { id = 789, title = "Sting of the Scorpid", done = 1, total = 3 } } },
        { guid = "Player-1-ASHKA", name = "Ashka", doneIds = { 788, 789 }, quests = {} },
      },
      together = { { id = 790, title = "Sarkoth", level = 5, who = "Brogg, Ashka", giver = "Hana'zua" } } },
  },
}

-- 1. Next up for the zone you're in, checked against your log right now.
local text = table.concat(ns.Next.currentLines(me), "\n")
check(text:find("Next up in Durotar", 1, true), "Next up picks the zone you're in")
check(text:find("Cutting Teeth  done", 1, true), "a quest you've finished since shows as done")
check(text:find("Sting of the Scorpid  in your log", 1, true), "a quest you've accepted since shows as in your log")
check(text:find("Vile Familiars", 1, true) and text:find("soon", 1, true) and text:find("Zureetha Fargaze", 1, true) and text:find("unlocks 1 more", 1, true),
  "open suggestions show level, soon, giver and why")
check(not text:find("Not mine", 1, true), "only this toon's suggestions")
check(text:find("Pick up together", 1, true) and text:find("Sarkoth", 1, true) and text:find("Brogg, Ashka", 1, true), "journal pick-ups listed")

st.map = 9999
text = table.concat(ns.Next.currentLines(me), "\n")
check(text:find("Next up in Mulgore", 1, true) and text:find("where your quests are", 1, true), "elsewhere: falls back to the first zone and says so")

local saved = Crewlog_Inbox
Crewlog_Inbox = { journals = {} }
check(ns.Next.currentLines(me)[1]:find("No suggestions", 1, true), "no data yet: explains what to do")
Crewlog_Inbox = saved

-- 2. Tooltip lines: who else is on it (with progress) and who has done it; live party first.
ns.Live.peers["Player-1-CARL"] = { name = "Carl", classId = 1, at = st.time, quests = { [789] = { title = "Sting of the Scorpid", o = { { h = 7, n = 10 } } } } }
local tip = ns.Tooltips.lines(789, me)
check(#tip == 3, "three crewmates on/through Sting (got " .. #tip .. ")")
check(tip[1]:find("Carl", 1, true) and tip[1]:find("7/10", 1, true) and tip[1]:find("live", 1, true), "live party member first, with progress")
check(tip[2]:find("Brogg 1/3", 1, true), "journal crewmate with progress")
check(tip[3]:find("Ashka", 1, true) and tip[3]:find("done", 1, true), "crewmate who has done it")
check(#ns.Tooltips.lines(4641, me) == 0, "nobody: no lines")

-- 3. The hook adds them to quest-link tooltips.
GameTooltip.lines = {}
GameTooltip:SetHyperlink("quest:789:3")
local joined = table.concat(GameTooltip.lines, "\n")
check(joined:find("Crewlog", 1, true) and joined:find("Brogg 1/3", 1, true), "quest link tooltip gets the crew lines")
GameTooltip.lines = {}
GameTooltip:SetHyperlink("item:6948")
check(#GameTooltip.lines == 0, "other links untouched")

-- 4. Commands: /cl and /crewlog, /cl next opens the Next tab.
check(SLASH_CREWLOG1 == "/cl" and SLASH_CREWLOG2 == "/crewlog", "slash commands /cl and /crewlog")
st.map = 1411
SlashCmdList.CREWLOG("next")
local win = _G.CrewlogCrewFrame
check(win and win.text and win.text.text and win.text.text:find("Next up in Durotar", 1, true), "/cl next opens the window on Next up")
SlashCmdList.CREWLOG("")
check(win.text.text:find("Tuesday crew", 1, true), "/cl switches to the crew tab")

-- 5. Clicking the compass opens a menu with everything /cl can do.
local db = CrewlogDB
local items = ns.UI.MenuItems()
local names = {}
for _, it in ipairs(items) do names[#names + 1] = it.text end
check(table.concat(names, ",") == "Sync now,Crew,Next up,Member colours,Markers over party,Hide minimap button", "menu items: " .. table.concat(names, ","))
local kind, frame = ns.UI.Menu(UIParent)                       -- no MenuUtil in the harness: our own menu
check(kind == "own" and frame and #frame.buttons == 6, "fallback menu with six entries")
frame.buttons[4].scripts.OnClick()                               -- Member colours
check(db.ui.colors == true, "menu toggles member colours")
frame.buttons[1].scripts.OnClick()                               -- Sync now
check(H.reloads == 1, "menu Sync now reloads straight away")
local built = {}
MenuUtil = { CreateContextMenu = function(_, gen)
  gen(nil, { CreateTitle = function(_, t) built[#built + 1] = "title:" .. t end,
             CreateButton = function(_, t) built[#built + 1] = "button:" .. t end,
             CreateCheckbox = function(_, t, isOn) built[#built + 1] = "check:" .. t .. ":" .. tostring(isOn()) end })
end }
check(ns.UI.Menu(UIParent) == "native", "the game's own menu when it exists")
check(built[1] == "title:Crewlog" and built[5] == "check:Member colours:true" and built[6] == "check:Markers over party:false", "native menu: title, buttons, checkboxes with state")
MenuUtil = nil
GameTooltip.lines = {}
ns.UI.Tooltip(GameTooltip)
check(table.concat(GameTooltip.lines, "\n"):find("for the menu", 1, true), "tooltip explains the click")

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
