-- In-game entry points: a minimap button and the addon compartment. "Sync" = ReloadUI(), the only moment
-- WoW writes SavedVariables to disk for the Crewlog client to pick up (besides logout).
local ADDON, ns = ...
local U, S, Crew = ns.U, ns.Store, ns.Crew
local UI = {}
ns.UI = UI

local GOLD = "|cffE3A21A"
local MUTED = "|cff8FA39C"
local ICON = "Interface\\AddOns\\Crewlog\\media\\minimap"
local db

local function say(msg) DEFAULT_CHAT_FRAME:AddMessage(GOLD .. "[Crewlog]|r " .. msg) end

local function ago(t)
  if not t then return "never" end
  local d = U.now() - t
  if d < 90 then return "just now" end
  if d < 3600 then return math.floor(d / 60) .. " min ago" end
  if d < 86400 then return math.floor(d / 3600) .. " h ago" end
  return math.floor(d / 86400) .. " days ago"
end

-- Sync = reload the UI (saves SavedVariables). Never in combat: a reload mid-fight is worse than waiting.
local pendingAfterCombat = false
function UI.Sync(skipConfirm)
  if InCombatLockdown and InCombatLockdown() then
    pendingAfterCombat = true
    say("In combat. Crewlog will offer to sync as soon as the fight is over.")
    return
  end
  if skipConfirm or not StaticPopup_Show then
    ReloadUI()
    return
  end
  StaticPopup_Show("CREWLOG_SYNC")
end

if StaticPopupDialogs then
  StaticPopupDialogs.CREWLOG_SYNC = {
    text = "Sync Crewlog now?\n\nYour UI reloads for a moment so the Crewlog app can pick up your progress.",
    button1 = "Sync",
    button2 = "Not now",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
  }
end

function UI.Tooltip(tt)
  local events, harvest = S.pendingCount(db)
  local guid = ns.Collector.guid()
  local rec = guid and db.chars[guid]
  tt:AddLine(GOLD .. "Crewlog|r")
  if events + harvest > 0 then
    tt:AddLine(string.format("%d update(s) waiting to sync", events + harvest), 1, 1, 1)
  else
    tt:AddLine("Everything synced", 1, 1, 1)
  end
  if rec then tt:AddLine(MUTED .. string.format("%s · %d quests done", rec.name or "?", #rec.completed)) end
  tt:AddLine(MUTED .. "Last data from the app: " .. ago(db.lastInbox ~= 0 and db.lastInbox or nil))
  Crew.tooltip(tt, guid)
  tt:AddLine(" ")
  tt:AddLine(GOLD .. "Click|r to sync (reloads your UI briefly)", 1, 1, 1)
  tt:AddLine(GOLD .. "Shift-click|r to sync without asking", 1, 1, 1)
  tt:AddLine(GOLD .. "Right-click|r for your journal crew", 1, 1, 1)
  tt:AddLine(MUTED .. "Drag to move · logging out syncs too")
end

-- Minimap button ---------------------------------------------------------------------------

local button
local function place()
  local angle = math.rad(db.ui.minimapAngle or 225)
  local r = (Minimap:GetWidth() / 2) + 10
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function createMinimapButton()
  if not Minimap or button then return end
  button = CreateFrame("Button", "CrewlogMinimapButton", Minimap)
  button:SetSize(32, 32)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints()
  icon:SetTexture(ICON)
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  button:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then Crew.Toggle(ns.Collector.guid()) return end
    UI.Sync(IsShiftKeyDown and IsShiftKeyDown())
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    UI.Tooltip(GameTooltip)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      db.ui.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
      place()
    end)
  end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  place()
  if db.ui.hideMinimap then button:Hide() end
end

-- Addon compartment (modern client's addon dropdown); the TOC points here.
function Crewlog_OnAddonCompartmentClick(_, mouse)
  if mouse == "RightButton" then Crew.Toggle(ns.Collector.guid()) return end
  UI.Sync(IsShiftKeyDown and IsShiftKeyDown())
end

function Crewlog_OnAddonCompartmentEnter(_, menuButton)
  GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
  UI.Tooltip(GameTooltip)
  GameTooltip:Show()
end

function Crewlog_OnAddonCompartmentLeave() GameTooltip:Hide() end

function UI.SetMinimapShown(shown)
  db.ui.hideMinimap = not shown
  if button then if shown then button:Show() else button:Hide() end end
end

function UI.Start(theDb)
  db = theDb
  db.ui = db.ui or {}
  createMinimapButton()
end

-- Offer the postponed sync once combat ends.
function UI.OnCombatEnded()
  if pendingAfterCombat then
    pendingAfterCombat = false
    UI.Sync(false)
  end
end
