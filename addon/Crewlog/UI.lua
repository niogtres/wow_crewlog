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
  tt:AddLine(GOLD .. "Click|r for the menu: sync, crew, next up, route on map, options", 1, 1, 1)
  tt:AddLine(GOLD .. "Shift-click|r to sync right away", 1, 1, 1)
  tt:AddLine(GOLD .. "Right-click|r for your crew", 1, 1, 1)
  tt:AddLine(MUTED .. "Drag to move · logging out syncs too")
end

-- The compass menu: everything /cl can do, one click away ---------------------------------------

-- What the menu offers, in order. Checkboxes carry isOn; the rest just run.
function UI.MenuItems()
  local Live, guid = ns.Live, ns.Collector.guid
  return {
    { text = "Sync now", hint = "reloads your UI for a moment", run = function() UI.Sync(true) end },
    { text = "Crew", run = function() Crew.Show(guid(), "crew") end },
    { text = "Next up", run = function() Crew.Show(guid(), "next") end },
    UI.RouteItem(),
    { text = "Member colours", isOn = function() return db.ui.colors == true end, run = function() Live.setColors(not db.ui.colors) end },
    { text = "Markers over party", isOn = function() return db.ui.markers == true end,
      run = function()
        local ok, why = Live.setMarkers(not db.ui.markers)
        if not ok then say("can't change markers " .. why) end
      end },
    { text = "Upload my party's progress", hint = "your syncs carry crewmates' progress to the website, for those who allow it",
      isOn = function() return Live.relayOn() == true end,
      run = function()
        Live.setRelay(not Live.relayOn())
        say(Live.relayOn() and "your syncs now also upload the progress of journal crewmates in your group who allow it (/cl relay turns it off)."
          or "party upload off: your syncs carry only your own toons.")
      end },
    { text = "Hide minimap button", hint = "/cl minimap brings it back", run = function()
        UI.SetMinimapShown(false)
        say("minimap button hidden. |cffF2C25B/cl minimap|r shows it again.")
      end },
  }
end

-- "Route on map": the toon's own route ("Just me") and one choice per journal that has a route, plus Clear. A submenu
-- in the game's own menu; the fallback menu lists the choices inline.
function UI.RouteItem()
  local Route = ns.Route
  local children = {}
  for _, j in ipairs(Route.journals()) do
    local key = j.key
    children[#children + 1] = { text = j.title, hint = #j.route.stops .. " stops in " .. j.route.zone,
      isOn = function() return Route.selected() == key end,
      run = function() if Route.selected() == key then Route.clear() else Route.show(key) end end }
  end
  if #children == 0 then
    children[1] = { text = "No routes yet", hint = "sync with quests in your log", run = function()
      say("no route yet. Routes come from the Crewlog app after a sync (they need quests in one zone).")
    end }
  end
  if Route.selected() then
    children[#children + 1] = { text = "Next 3 stops", hint = Route.hasMore() and "the three after these" or "no more stops",
      run = function() Route.nextThree() end }
    children[#children + 1] = { text = "Arrow to the next stop", isOn = function() return ns.Arrow.on() end,
      run = function() ns.Arrow.setOn(not ns.Arrow.on()) end }
    children[#children + 1] = { text = "Clear route", run = function() Route.clear() end }
  end
  return { text = "Route on map", children = children }
end

-- Flattens submenus for the fallback menu.
local function flat(items)
  local out = {}
  for _, it in ipairs(items) do
    if it.children then
      for _, c in ipairs(it.children) do
        out[#out + 1] = { text = it.text .. ": " .. c.text, hint = c.hint, isOn = c.isOn, run = c.run }
      end
    else
      out[#out + 1] = it
    end
  end
  return out
end

local menuFrame
-- The game's own context menu where it exists (modern client), else a small menu of our own.
function UI.Menu(anchor)
  local items = UI.MenuItems()
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(anchor, function(_, root)
      root:CreateTitle("Crewlog")
      for _, it in ipairs(items) do
        if it.children then
          local sub = root:CreateButton(it.text)
          for _, c in ipairs(it.children) do
            if c.isOn then sub:CreateRadio(c.text, c.isOn, c.run)
            else sub:CreateButton(c.text, c.run) end
          end
        elseif it.isOn then root:CreateCheckbox(it.text, it.isOn, it.run)
        else root:CreateButton(it.text, it.run) end
      end
    end)
    return "native"
  end
  items = flat(items)
  if not menuFrame then
    menuFrame = CreateFrame("Frame", "CrewlogMenu", UIParent, "TooltipBackdropTemplate")
    menuFrame:SetFrameStrata("DIALOG")
    menuFrame:SetClampedToScreen(true)
    menuFrame:EnableMouse(true)
    menuFrame.buttons = {}
    tinsert(UISpecialFrames, "CrewlogMenu") -- Escape closes it
    local title = menuFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Crewlog")
  end
  for i, it in ipairs(items) do
    local b = menuFrame.buttons[i]
    if not b then
      b = CreateFrame("Button", nil, menuFrame)
      b:SetSize(200, 20)
      b:SetPoint("TOPLEFT", 10, -10 - i * 20)
      b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      b.label:SetPoint("LEFT", 4, 0)
      menuFrame.buttons[i] = b
    end
    b.label:SetText((it.isOn and ((it.isOn() and "|cff6DCFC4[x]|r " or "|cff8FA39C[ ]|r ")) or "") .. it.text
      .. (it.hint and (" |cff8FA39C(" .. it.hint .. ")|r") or ""))
    b:SetScript("OnClick", function() menuFrame:Hide(); it.run() end)
    b:Show()
  end
  menuFrame:SetSize(250, 20 + (#items + 1) * 20)
  menuFrame:ClearAllPoints()
  menuFrame:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 0, 0)
  menuFrame:Show()
  return "own", menuFrame
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

  button:SetScript("OnClick", function(self, mouse)
    if mouse == "RightButton" then Crew.Toggle(ns.Collector.guid(), "crew") return end
    if IsShiftKeyDown and IsShiftKeyDown() then UI.Sync(true) return end
    UI.Menu(self)
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
function Crewlog_OnAddonCompartmentClick(_, mouse, menuButton)
  if mouse == "RightButton" then Crew.Toggle(ns.Collector.guid(), "crew") return end
  if IsShiftKeyDown and IsShiftKeyDown() then UI.Sync(true) return end
  UI.Menu(menuButton or button or UIParent)
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
