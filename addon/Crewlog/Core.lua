-- Wiring: SavedVariables lifecycle, event dispatch, /cl command.
local ADDON, ns = ...
local U, S, C, UI = ns.U, ns.Store, ns.Collector, ns.UI

local VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"
local GOLD = "|cffE3A21A"
local function say(msg) DEFAULT_CHAT_FRAME:AddMessage(GOLD .. "[Crewlog]|r " .. msg) end

local db
local debugEvents = false

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
for ev in pairs(C.handlers) do frame:RegisterEvent(ev) end

local function describe(ev)
  if ev.k == "PROGRESS" then return string.format("%s %d · objective %d: %d/%d", ev.k, ev.q, ev.o, ev.h, ev.n) end
  if ev.q then return ev.k .. " " .. ev.q end
  if ev.l then return ev.k .. " " .. ev.l end
  if ev.m then return ev.k .. " map " .. ev.m end
  return ev.k
end

C.listeners[#C.listeners + 1] = function(ev)
  if debugEvents then say("|cff8FA39C#" .. ev.s .. "|r " .. describe(ev)) end
end

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    db = S.init(CrewlogDB, VERSION)
    CrewlogDB = db
    local inbox = rawget(_G, "Crewlog_Inbox")
    local dEv, dH = S.prune(db, inbox)
    db.lastInbox = inbox and inbox.generatedAt or nil
    if dEv > 0 or dH > 0 then db.lastPrune = { t = U.now(), events = dEv, harvest = dH } end
    return
  end
  if event == "PLAYER_LOGIN" then
    if not db then return end
    C.start(db)
    UI.Start(db)
    ns.Live.listeners[#ns.Live.listeners + 1] = function() ns.Crew.Refresh(C.guid()) end
    ns.Live.Start(db, C.guid(), UnitName("player"))
    ns.Tooltips.Start(C.guid)
    ns.Way.Start()
    ns.Route.Start(db)
    return
  end
  if event == "PLAYER_REGEN_ENABLED" then UI.OnCombatEnded() return end
  if not db or not C.guid() then return end
  local h = C.handlers[event]
  if h then h(...) end
end)

SLASH_CREWLOG1 = "/cl"
SLASH_CREWLOG2 = "/crewlog"
SlashCmdList.CREWLOG = function(msg)
  local way = (msg or ""):match("^%s*[Ww][Aa][Yy]%s+(.*)$")
  if way then ns.Way.run(way) return end
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if not db then say("not loaded yet") return end
  if msg == "sync" then UI.Sync(true) return end
  if msg == "" or msg == "crew" then ns.Crew.Toggle(C.guid(), "crew") return end
  if msg == "next" then ns.Crew.Toggle(C.guid(), "next") return end
  if msg == "colors" or msg == "colours" then
    ns.Live.setColors(not db.ui.colors)
    say(db.ui.colors and "member colours on: each party member gets their own colour (the same for everyone running Crewlog)"
      or "member colours off: class colours")
    return
  end
  if msg == "markers" then
    local ok, why = ns.Live.setMarkers(not db.ui.markers)
    if not ok then say("can't change markers " .. why) return end
    say(db.ui.markers and "markers on: party members running Crewlog get a compass over their head (friendly nameplates are on)"
      or "markers off")
    return
  end
  if msg == "relay" then
    ns.Live.setRelay(not ns.Live.relayOn())
    say(ns.Live.relayOn() and "party upload on: your syncs also carry the progress of journal crewmates in your group who allow it on the website"
      or "party upload off: your syncs carry only your own toons")
    return
  end
  if msg == "minimap" then
    UI.SetMinimapShown(db.ui.hideMinimap == true)
    say("minimap button " .. (db.ui.hideMinimap and "hidden (/cl minimap shows it again)" or "shown"))
    return
  end
  if msg == "debug" then
    debugEvents = not debugEvents
    say("event echo " .. (debugEvents and "on" or "off"))
    return
  end
  local rec = db.chars[C.guid()]
  local evs, harvest = S.pendingCount(db)
  local nChars = 0
  for _ in pairs(db.chars) do nChars = nChars + 1 end
  local inboxAge = db.lastInbox and (U.now() - db.lastInbox) or nil
  say(string.format("v%s · %d toon(s) on this account · this toon: %d completed, seq %d",
    VERSION, nChars, rec and #rec.completed or 0, rec and rec.seq or 0))
  say(string.format("waiting for the client: %d event(s), %d harvested quest(s) · inbox %s",
    evs, harvest, inboxAge and (math.floor(inboxAge / 60) .. " min old") or "not received yet"))
  local live = #ns.Live.list()
  local relayed = 0
  for _ in pairs(db.relay or {}) do relayed = relayed + 1 end
  say(string.format("party: %s · member colours %s · markers %s · party upload %s", ns.Live.channel() and (live .. " with Crewlog, live") or "not in a group",
    db.ui.colors and "on" or "off", db.ui.markers and "on" or "off",
    ns.Live.relayOn() and ("on (" .. relayed .. " waiting)") or "off"))
  say("this toon's progress " .. (ns.Live.key() and "may be uploaded by crewmates (allowed on the website)" or "is uploaded only by you"))
  if ns.Live.channel() or ns.Live.stats.sent > 0 then say(ns.Live.statusLine()) end
  say("Click the |cffF2C25Bcompass|r on the minimap (or |cffF2C25B/cl sync|r) to sync now; logging out syncs too. |cffF2C25B/cl|r (or right-click) shows your crew, |cffF2C25B/cl next|r what to pick up next. Coordinates copied on the website set a map pin: |cffF2C25B/way Durotar 42.9 69.2|r (or |cffF2C25B/cl way …|r when a waypoint addon owns /way). Optional: |cffF2C25B/cl colors|r (a colour per party member), |cffF2C25B/cl markers|r (icon over their heads), |cffF2C25B/cl relay|r (your syncs also upload crewmates' progress). |cffF2C25B/cl minimap|r hides the button.")
end
