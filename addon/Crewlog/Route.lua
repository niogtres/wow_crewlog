-- A suggested route (the website's route map) on the world map: numbered stops joined by a line, with what to do at
-- each in the tooltip. Either a journal's route or the toon's own ("Just me", the toon page's map). The Crewlog app
-- writes the routes into Crewlog_Inbox; which one to show is picked from the compass menu and kept per account (for
-- "Just me" that is always the toon you're playing). Drawn only on the route's own zone map.
local ADDON, ns = ...
local Route = {}
ns.Route = Route

local GOLD = "|cffE3A21A"
local MUTED = "|cff8FA39C"
local TEMPLATE = "CrewlogRoutePinTemplate"
local db, provider

local function say(msg) DEFAULT_CHAT_FRAME:AddMessage(GOLD .. "[Crewlog]|r " .. msg) end
local function inbox() return rawget(_G, "Crewlog_Inbox") end

local function hasToon(j, guid)
  for _, t in ipairs(j.toons or {}) do
    if t.guid == guid then return true end
  end
  return false
end

--- Key of the toon's own route in the saved choice; journals are kept by title.
Route.SOLO = "@me"

--- The routes this toon can show: its own first ("Just me"), then the journals it is in that came with a route from
--- the app: { { key, title, route }, ... }.
function Route.journals()
  local list = {}
  local me = ns.Collector and ns.Collector.guid()
  local box = inbox() or {}
  local own = me and box.routes and box.routes[me]
  if own and own.stops and #own.stops > 0 then list[1] = { key = Route.SOLO, title = "Just me", route = own } end
  for _, j in ipairs(box.journals or {}) do
    if j.route and j.route.stops and #j.route.stops > 0 and hasToon(j, me) then
      list[#list + 1] = { key = j.title, title = j.title, route = j.route }
    end
  end
  return list
end

local function find(key)
  for _, j in ipairs(Route.journals()) do
    if j.key == key then return j end
  end
end

--- The route being shown (nil when none is picked, or that one has no route right now).
function Route.current()
  local pick = db and db.ui.route
  local j = pick and find(pick)
  return j and j.route
end

function Route.selected() return db and db.ui.route end

local function refresh()
  if provider and provider:GetMap() then provider:RefreshAllData() end
end

function Route.show(key)
  db.ui.route = key
  local j = find(key)
  local r = j and j.route
  local whose = key == Route.SOLO and "Your own" or ((j and j.title or key) .. "'s")
  if r then
    say(string.format("%s route is on your map: %d stop(s) in %s. Open the map (M) at %s.", whose, #r.stops, r.zone, r.zone))
  else
    say((key == Route.SOLO and "You have" or key .. " has") .. " no route right now.")
  end
  refresh()
end

function Route.clear()
  db.ui.route = nil
  say("route cleared from the map.")
  refresh()
end

-- Pins -------------------------------------------------------------------------------------------

CrewlogRoutePinMixin = CreateFromMixins and MapCanvasPinMixin and CreateFromMixins(MapCanvasPinMixin) or {}

function CrewlogRoutePinMixin:OnLoad()
  self:SetSize(22, 22)
  if self.SetScalingLimits then self:SetScalingLimits(1, 0.9, 1.3) end
  if self.UseFrameLevelType then pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_AREA_POI") end
  local ring = self:CreateTexture(nil, "BACKGROUND")
  ring:SetAllPoints()
  ring:SetColorTexture(0.09, 0.15, 0.19, 1)
  local disc = self:CreateTexture(nil, "ARTWORK")
  disc:SetPoint("TOPLEFT", 2, -2)
  disc:SetPoint("BOTTOMRIGHT", -2, 2)
  disc:SetColorTexture(0.89, 0.64, 0.10, 1)
  if self.CreateMaskTexture then
    for _, tex in ipairs({ ring, disc }) do
      local mask = self:CreateMaskTexture()
      mask:SetAllPoints(tex)
      mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      tex:AddMaskTexture(mask)
    end
  end
  self.label = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  self.label:SetPoint("CENTER", 0, 0)
  self.label:SetTextColor(0.03, 0.06, 0.07)
  self:SetScript("OnEnter", self.OnMouseEnter)
  self:SetScript("OnLeave", self.OnMouseLeave)
end

function CrewlogRoutePinMixin:OnAcquired(stop, x, y)
  if not self.label then self:OnLoad() end
  self.stop = stop
  self.label:SetText(stop.n)
  self:SetPosition((x or stop.x) / 100, (y or stop.y) / 100)
end

function CrewlogRoutePinMixin:OnMouseEnter()
  local s = self.stop
  if not s then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(GOLD .. s.n .. ".|r " .. (s.place or ""), 1, 1, 1)
  for _, t in ipairs(s.tasks or {}) do GameTooltip:AddLine(t, 0.9, 0.93, 0.92, true) end
  local x, y = s.cx or s.x, s.cy or s.y
  GameTooltip:AddLine(MUTED .. string.format("%.1f, %.1f · Crewlog route|r", x, y))
  GameTooltip:Show()
end

function CrewlogRoutePinMixin:OnMouseLeave() GameTooltip:Hide() end

-- The provider: pins for the stops, lines between them on the map canvas (so they zoom with it). -------------------

local lines = {}

local function hideLines()
  for _, l in ipairs(lines) do l:Hide() end
end

local function drawLines(map, stops)
  local canvas = map:GetCanvas()
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  if not canvas.CreateLine or w == 0 then return end
  for i = 2, #stops do
    local l = lines[i - 1]
    if not l or l:GetParent() ~= canvas then
      l = canvas:CreateLine(nil, "ARTWORK")
      l:SetThickness(3)
      l:SetColorTexture(0.89, 0.64, 0.10, 0.75)
      lines[i - 1] = l
    end
    local a, b = stops[i - 1], stops[i]
    l:SetStartPoint("TOPLEFT", canvas, a.x / 100 * w, -a.y / 100 * h)
    l:SetEndPoint("TOPLEFT", canvas, b.x / 100 * w, -b.y / 100 * h)
    l:Show()
  end
end

local function makeProvider()
  local p = CreateFromMixins(MapCanvasDataProviderMixin)
  function p:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
    hideLines()
  end
  function p:RefreshAllData()
    self:RemoveAllData()
    local r = Route.current()
    local map = self:GetMap()
    if not r then return end
    local id = map:GetMapID()
    if id == r.map then
      -- The route's zone: every stop (one in a capital beyond the map's edge sits at the edge) and the line.
      drawLines(map, r.stops)
      for _, s in ipairs(r.stops) do map:AcquirePin(TEMPLATE, s) end
    else
      -- A capital's own map (Orgrimmar from Durotar's route): the stops in it, where they really are.
      for _, s in ipairs(r.stops) do
        if s.cityMap == id and s.cx and s.cy then map:AcquirePin(TEMPLATE, s, s.cx, s.cy) end
      end
    end
  end
  function p:OnMapChanged() self:RefreshAllData() end
  return p
end

function Route.Start(database)
  db = database
  if not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin and CreateFromMixins) then return end
  provider = makeProvider()
  WorldMapFrame:AddDataProvider(provider)
end

--- Whether this game client can draw the route at all.
function Route.supported() return provider ~= nil end
