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

-- Above every other pin on the map (the game's quest markers, other addons' pins), so the numbers can always be read.
-- The map gives each kind of pin an absolute frame level from its pin-level manager (2000 and up; quest markers among
-- the highest), and re-applies it on every move and zoom through ApplyFrameLevel. So we take the manager's top level
-- (PIN_FRAME_LEVEL_TOPMOST, the layer reserved for this) plus a margin, every time.
local ABOVE_TOP = 10

--- The frame level for our pins, from the map's pin-level manager: just above its highest layer.
function Route.topLevel(map)
  local mgr = map and map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
  local top = mgr and tonumber(mgr.maxLevel)
  if not top and mgr and mgr.GetValidFrameLevel then
    local ok, level = pcall(mgr.GetValidFrameLevel, mgr, "PIN_FRAME_LEVEL_TOPMOST", 1)
    top = ok and tonumber(level) or nil
  end
  return math.min((top or 2000) + ABOVE_TOP, 9000)
end

function CrewlogRoutePinMixin:ApplyFrameLevel()
  self:SetFrameLevel(Route.topLevel(self.GetMap and self:GetMap() or WorldMapFrame))
end

function CrewlogRoutePinMixin:OnAcquired(stop, x, y)
  if not self.label then self:OnLoad() end
  self.stop = stop
  self.label:SetText(stop.n)
  self:SetPosition((x or stop.x) / 100, (y or stop.y) / 100)
  self:ApplyFrameLevel()
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

local lines = {}   -- { casing, core } per segment

local function hideLines()
  for _, pair in ipairs(lines) do pair[1]:Hide(); pair[2]:Hide() end
end

local function clamp(v) return math.max(0, math.min(100, tonumber(v) or 0)) end

--- The segments of the route, in zone coordinates: each leg along the ground (the path the website sends, around
--- cliffs, mountains and water; a flight is a line of its own), or straight where there's no path.
function Route.segments(stops)
  local out = {}
  for i = 2, #stops do
    local a, b = stops[i - 1], stops[i]
    local drawn = false
    for _, line in ipairs(type(b.path) == "table" and b.path or {}) do
      if type(line) == "table" then
        for k = 3, #line - 1, 2 do
          out[#out + 1] = { clamp(line[k - 2]), clamp(line[k - 1]), clamp(line[k]), clamp(line[k + 1]) }
          drawn = true
        end
      end
    end
    if not drawn then out[#out + 1] = { a.x, a.y, b.x, b.y } end
  end
  return out
end

local function drawLines(map, stops)
  local canvas = map:GetCanvas()
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  if not canvas.CreateLine or w == 0 then return end
  -- A dark line on a black casing: it stands out on the map's yellow and tan.
  for i, seg in ipairs(Route.segments(stops)) do
    local pair = lines[i]
    if not pair or pair[1]:GetParent() ~= canvas then
      local casing = canvas:CreateLine(nil, "ARTWORK", nil, 1)
      casing:SetThickness(6)
      casing:SetColorTexture(0.04, 0.03, 0.02, 0.85)
      local core = canvas:CreateLine(nil, "ARTWORK", nil, 2)
      core:SetThickness(3)
      core:SetColorTexture(0.55, 0.22, 0.04, 1)
      pair = { casing, core }
      lines[i] = pair
    end
    for _, l in ipairs(pair) do
      l:SetStartPoint("TOPLEFT", canvas, seg[1] / 100 * w, -seg[2] / 100 * h)
      l:SetEndPoint("TOPLEFT", canvas, seg[3] / 100 * w, -seg[4] / 100 * h)
      l:Show()
    end
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
