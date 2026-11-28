-- A suggested route (the website's route map) on the world map, three stops at a time: the next three numbered stops,
-- each with the way there along the ground (green to the first, blue to the second, grey to the third), and an arrow
-- (Arrow.lua) to the next one. Reaching a stop moves the arrow on; after the third the next three come up, or the
-- player picks "Next 3 stops". What to do at each stop is in its tooltip. Either a journal's route or the toon's own
-- ("Just me", the toon page's map). The Crewlog app writes the routes into Crewlog_Inbox; which one to show is picked
-- from the compass menu and kept per account (for "Just me" that is always the toon you're playing). Drawn only on the
-- route's own zone map.
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

--- How many stops are drawn at a time.
Route.SHOWN = 3

--- The colour of the way to the first, second and third stop drawn.
Route.COLORS = {
  { 0.20, 0.80, 0.25 },   -- green: the next stop
  { 0.25, 0.55, 1.00 },   -- blue
  { 0.62, 0.62, 0.62 },   -- grey
}

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
  if ns.Arrow then ns.Arrow.update() end
end

-- Progress -----------------------------------------------------------------------------------------
-- The first stop drawn (from) and the one the arrow points to (at), kept per route: a new route (after a sync the
-- website plans again from where you are) starts over.

local function signature(r)
  local a, b = r.stops[1], r.stops[#r.stops]
  return table.concat({ r.map or 0, #r.stops, a.place or "", a.x or 0, b.place or "", b.x or 0 }, "|")
end

--- from, at (1-based stop indexes; #stops + 1 once the route is done) for the route shown; nil when none.
function Route.progress()
  local r = Route.current()
  if not r then return nil end
  local sig = signature(r)
  if db.ui.routeSig ~= sig then db.ui.routeSig, db.ui.routeFrom, db.ui.routeAt = sig, 1, 1 end
  local from = math.max(1, math.min(tonumber(db.ui.routeFrom) or 1, #r.stops + 1))
  local at = math.max(from, math.min(tonumber(db.ui.routeAt) or from, from + Route.SHOWN - 1, #r.stops + 1))
  return from, at
end

--- The stops drawn now, up to three: { { stop, index, slot (1-3) }, ... }.
function Route.window()
  local r = Route.current()
  local from = Route.progress()
  local out = {}
  if not from then return out end
  for i = from, math.min(from + Route.SHOWN - 1, #r.stops) do out[#out + 1] = { stop = r.stops[i], index = i, slot = i - from + 1 } end
  return out
end

--- The stop the arrow points to and its index; nil when no route is shown or it's done.
function Route.target()
  local r = Route.current()
  local _, at = Route.progress()
  if r and at then return r.stops[at], at end
end

local function setProgress(from, at)
  db.ui.routeFrom, db.ui.routeAt = from, at
  refresh()
end

--- The arrow's stop is reached (or skipped): point to the next one; after the third drawn, the next three come up.
function Route.reached()
  local r = Route.current()
  local from, at = Route.progress()
  if not (from and r.stops[at]) then return end
  local nxt = at + 1
  if nxt > #r.stops then
    setProgress(#r.stops + 1, #r.stops + 1)
    say("that was the last stop of the route. Sync for a new one.")
  elseif nxt >= from + Route.SHOWN then
    setProgress(nxt, nxt)
    say(string.format("on to the next stops: %d to %d.", nxt, math.min(nxt + Route.SHOWN - 1, #r.stops)))
  else
    setProgress(from, nxt)
  end
end

--- Whether there are stops after the ones drawn now.
function Route.hasMore()
  local r = Route.current()
  local from = Route.progress()
  return from ~= nil and from + Route.SHOWN <= #r.stops
end

--- "Next 3 stops": the three after the ones drawn now.
function Route.nextThree()
  local r = Route.current()
  if not r then return end
  if not Route.hasMore() then
    say("there are no more stops on this route. Sync for a new one.")
    return
  end
  local nxt = Route.progress() + Route.SHOWN
  setProgress(nxt, nxt)
  say(string.format("stops %d to %d are on your map.", nxt, math.min(nxt + Route.SHOWN - 1, #r.stops)))
end

function Route.show(key)
  db.ui.route = key
  db.ui.routeSig = nil
  local j = find(key)
  local r = j and j.route
  local whose = key == Route.SOLO and "Your own" or ((j and j.title or key) .. "'s")
  if r then
    say(string.format("%s route is on your map: %d stop(s) in %s, three at a time, with an arrow to the next. Open the map (M) at %s.",
      whose, #r.stops, r.zone, r.zone))
  else
    say((key == Route.SOLO and "You have" or key .. " has") .. " no route right now.")
  end
  refresh()
end

function Route.clear()
  db.ui.route, db.ui.routeSig, db.ui.routeFrom, db.ui.routeAt = nil, nil, nil, nil
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
  self.ring = ring
  local disc = self:CreateTexture(nil, "ARTWORK")
  disc:SetPoint("TOPLEFT", 3, -3)
  disc:SetPoint("BOTTOMRIGHT", -3, 3)
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

-- slot: 1-3, which of the stops drawn (its ring has the colour of the way there).
function CrewlogRoutePinMixin:OnAcquired(stop, x, y, slot)
  if not self.label then self:OnLoad() end
  self.stop = stop
  local c = Route.COLORS[slot or 0] or { 0.09, 0.15, 0.19 }
  if self.ring then self.ring:SetColorTexture(c[1], c[2], c[3], 1) end
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

-- The provider: pins for the stops drawn, the way to each on the map canvas (so it zooms with it). -----------------

local lines = {}   -- { casing, core } per segment

local function hideLines()
  for _, pair in ipairs(lines) do pair[1]:Hide(); pair[2]:Hide() end
end

local function clamp(v) return math.max(0, math.min(100, tonumber(v) or 0)) end

--- The way to each stop drawn, in zone coordinates: { { slot, { {x1, y1, x2, y2}, ... } }, ... }. Along the ground
--- where the website sent a path (around cliffs, mountains and water; a flight is a line of its own), else straight
--- from the stop before (nothing to the route's first stop without a path).
function Route.legs(stops, from)
  local out = {}
  for i = from, math.min(from + Route.SHOWN - 1, #stops) do
    local b, segs = stops[i], {}
    for _, line in ipairs(type(b.path) == "table" and b.path or {}) do
      if type(line) == "table" then
        for k = 3, #line - 1, 2 do
          segs[#segs + 1] = { clamp(line[k - 2]), clamp(line[k - 1]), clamp(line[k]), clamp(line[k + 1]) }
        end
      end
    end
    local a = stops[i - 1]
    if #segs == 0 and a then segs[1] = { a.x, a.y, b.x, b.y } end
    out[#out + 1] = { i - from + 1, segs }
  end
  return out
end

local function drawLines(map, stops, from)
  local canvas = map:GetCanvas()
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  if not canvas.CreateLine or w == 0 then return end
  -- A coloured line on a black casing: it stands out on the map's yellow and tan.
  local n = 0
  for _, leg in ipairs(Route.legs(stops, from)) do
    local c = Route.COLORS[leg[1]]
    for _, seg in ipairs(leg[2]) do
      n = n + 1
      local pair = lines[n]
      if not pair or pair[1]:GetParent() ~= canvas then
        local casing = canvas:CreateLine(nil, "ARTWORK", nil, 1)
        casing:SetThickness(6)
        casing:SetColorTexture(0.04, 0.03, 0.02, 0.85)
        local core = canvas:CreateLine(nil, "ARTWORK", nil, 2)
        core:SetThickness(3)
        pair = { casing, core }
        lines[n] = pair
      end
      pair[2]:SetColorTexture(c[1], c[2], c[3], 1)
      for _, l in ipairs(pair) do
        l:SetStartPoint("TOPLEFT", canvas, seg[1] / 100 * w, -seg[2] / 100 * h)
        l:SetEndPoint("TOPLEFT", canvas, seg[3] / 100 * w, -seg[4] / 100 * h)
        l:Show()
      end
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
      -- The route's zone: the stops drawn (one in a capital beyond the map's edge sits at the edge) and the way to each.
      drawLines(map, r.stops, (Route.progress()))
      for _, w in ipairs(Route.window()) do map:AcquirePin(TEMPLATE, w.stop, nil, nil, w.slot) end
    else
      -- A capital's own map (Orgrimmar from Durotar's route): those of them in it, where they really are.
      for _, w in ipairs(Route.window()) do
        local s = w.stop
        if s.cityMap == id and s.cx and s.cy then map:AcquirePin(TEMPLATE, s, s.cx, s.cy, w.slot) end
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
