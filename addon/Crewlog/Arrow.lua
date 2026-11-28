-- The arrow to the route's next stop (Route.lua): a small frame on screen that turns toward the stop as you move and
-- turn, with its number, place and distance. Reaching the stop moves it on to the next. Drag to move it; right-click
-- skips the stop. Shown while a route is picked and "Arrow to the next stop" is on (compass menu).
local ADDON, ns = ...
local Arrow = {}
ns.Arrow = Arrow

local GOLD = "|cffE3A21A"
local MUTED = "|cff8FA39C"
Arrow.REACHED_YARDS = 30       -- this close counts as there
Arrow.REACHED_MAP = 0.8        -- ... in zone coordinates (0-100), when the game can't tell yards
local EVERY = 0.1              -- seconds between updates
local db, frame

function Arrow.on() return db ~= nil and db.ui.arrow ~= false end

function Arrow.setOn(on)
  if on then db.ui.arrow = nil else db.ui.arrow = false end
  Arrow.update()
end

local function xy(v)
  if not v then return nil end
  if v.GetXY then return v:GetXY() end
  return v.x, v.y
end

--- From (px, py) to (tx, ty), zone coordinates (0-100) on uiMap: distance in yards (nil when the game can't tell),
--- the direction as an angle counter-clockwise from north (as GetPlayerFacing counts), and the distance on the map.
function Arrow.heading(uiMap, px, py, tx, ty)
  local mapDist = math.sqrt((tx - px) ^ 2 + (ty - py) ^ 2)
  local toWorld = C_Map and C_Map.GetWorldPosFromMapPos
  if toWorld and CreateVector2D then
    local _, a = toWorld(uiMap, CreateVector2D(px / 100, py / 100))
    local _, b = toWorld(uiMap, CreateVector2D(tx / 100, ty / 100))
    local ax, ay = xy(a)
    local bx, by = xy(b)
    if ax and bx then
      -- World coordinates: x grows to the north, y to the west.
      local dn, dw = bx - ax, by - ay
      return math.sqrt(dn * dn + dw * dw), math.atan2(dw, dn), mapDist
    end
  end
  -- On the map north is up and y grows downwards.
  return nil, math.atan2(-(tx - px), -(ty - py)), mapDist
end

--- Where the player and the stop are, on a map both are on: uiMap, px, py, tx, ty (zone coordinates); nil when the
--- player is elsewhere.
function Arrow.positions(route, stop)
  local get = C_Map and C_Map.GetPlayerMapPosition
  if not get then return nil end
  local p = get(route.map, "player")
  local px, py = xy(p)
  if px and px > 0 then return route.map, px * 100, py * 100, stop.x, stop.y end
  if stop.cityMap and stop.cx then
    p = get(stop.cityMap, "player")
    px, py = xy(p)
    if px and px > 0 then return stop.cityMap, px * 100, py * 100, stop.cx, stop.cy end
  end
end

local function yards(d)
  if d >= 1000 then return string.format("%.1fk yd", d / 1000) end
  return string.format("%d yd", math.floor(d + 0.5))
end

--- One update: turn the arrow, show the distance, and move on when the stop is reached. Returns what it showed
--- ("here", "far", "off" or nil) for the tests.
function Arrow.tick()
  local Route = ns.Route
  local route = Route.current()
  local stop, at = Route.target()
  if not (frame and route and stop and Arrow.on()) then return nil end
  local from = Route.progress()
  local c = Route.COLORS[at - from + 1] or Route.COLORS[1]
  frame.title:SetText(GOLD .. stop.n .. ".|r " .. (stop.place or ""))
  local map, px, py, tx, ty = Arrow.positions(route, stop)
  if not map then
    frame.arrow:Hide()
    frame.dist:SetText(MUTED .. "in " .. (route.zone or "another zone") .. "|r")
    return "off"
  end
  local dist, angle, mapDist = Arrow.heading(map, px, py, tx, ty)
  if (dist and dist <= Arrow.REACHED_YARDS) or (not dist and mapDist <= Arrow.REACHED_MAP) then
    Route.reached()
    return "here"
  end
  local facing = GetPlayerFacing and GetPlayerFacing()
  if facing then
    frame.arrow:SetVertexColor(c[1], c[2], c[3])
    frame.arrow:SetRotation(angle - facing)
    frame.arrow:Show()
  else
    frame.arrow:Hide()   -- the game hides your facing (instances)
  end
  frame.dist:SetText(dist and yards(dist) or string.format("%.0f%% of the map", mapDist))
  return "far"
end

local function savePosition()
  local point, _, rel, x, y = frame:GetPoint(1)
  if point then db.ui.arrowPos = { point, rel, x, y } end
end

local function build()
  frame = CreateFrame("Button", "CrewlogArrowFrame", UIParent)
  frame:SetSize(120, 84)
  frame:SetFrameStrata("MEDIUM")
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:RegisterForClicks("RightButtonUp")
  local pos = db.ui.arrowPos
  if type(pos) == "table" and pos[1] then
    frame:SetPoint(pos[1], UIParent, pos[2] or pos[1], tonumber(pos[3]) or 0, tonumber(pos[4]) or 0)
  else
    frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
  end
  frame.arrow = frame:CreateTexture(nil, "ARTWORK")
  frame.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
  frame.arrow:SetSize(48, 48)
  frame.arrow:SetPoint("TOP", 0, 0)
  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.title:SetPoint("TOP", frame.arrow, "BOTTOM", 0, 0)
  frame.dist = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.dist:SetPoint("TOP", frame.title, "BOTTOM", 0, -2)
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition() end)
  frame:SetScript("OnClick", function() ns.Route.reached() end)
  frame:SetScript("OnEnter", function(self)
    local stop = ns.Route.target()
    if not stop then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(GOLD .. stop.n .. ".|r " .. (stop.place or ""), 1, 1, 1)
    for _, t in ipairs(stop.tasks or {}) do GameTooltip:AddLine(t, 0.9, 0.93, 0.92, true) end
    GameTooltip:AddLine(MUTED .. "Drag to move · right-click to skip this stop|r", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local wait = 0
  frame:SetScript("OnUpdate", function(_, elapsed)
    wait = wait - (elapsed or 0)
    if wait > 0 then return end
    wait = EVERY
    Arrow.tick()
  end)
  frame:Hide()
end

--- Shows or hides the arrow for the route and setting as they are now.
function Arrow.update()
  if not db then return end
  local show = Arrow.on() and ns.Route.target() ~= nil
  if show and not frame then build() end
  if not frame then return end
  if show then
    frame:Show()
    Arrow.tick()
  else
    frame:Hide()
  end
end

function Arrow.Start(database)
  db = database
  Arrow.update()
end
