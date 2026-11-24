-- /way: a map pin from coordinates copied on the website ("/way Durotar 42.9 69.2"), with the game's own waypoint
-- (C_Map.SetUserWaypoint), so no other addon is needed. TomTom-style addons own /way when installed: then Crewlog
-- leaves it to them (they read the same command) and answers only /cl way.
local _, ns = ...
local Way = {}
ns.Way = Way

local GOLD = "|cffE3A21A"
local function say(msg) DEFAULT_CHAT_FRAME:AddMessage(GOLD .. "[Crewlog]|r " .. msg) end

local function key(name) return (name or ""):lower():gsub("[^%w]", "") end

--- "[zone] x y [note]" -> zone (or nil), x, y (0-100), note. Commas between the numbers are fine.
function Way.parse(text)
  text = (text or ""):gsub(",", " ")
  local words = {}
  for w in text:gmatch("%S+") do words[#words + 1] = w end
  for i = 1, #words - 1 do
    local x, y = tonumber(words[i]), tonumber(words[i + 1])
    if x and y then
      local zone = table.concat(words, " ", 1, i - 1)
      local note = table.concat(words, " ", i + 2)
      return zone ~= "" and zone or nil, x, y, note ~= "" and note or nil
    end
  end
end

local zones
--- A zone name to its map, from the game's own map tree (all zones under Azeroth); nil if unknown.
function Way.zone(name)
  if not zones then
    zones = {}
    local list = C_Map.GetMapChildrenInfo and C_Map.GetMapChildrenInfo(947, nil, true) or {}
    for _, m in ipairs(list) do
      local k = key(m.name)
      if k ~= "" and (not zones[k] or m.mapType == 3) then zones[k] = m.mapID end   -- 3: zone, wins over a namesake
    end
  end
  return zones[key(name)]
end

--- Sets the pin. Returns true, or false and why.
function Way.set(text)
  local zone, x, y = Way.parse(text)
  if not x or x < 0 or x > 100 or y < 0 or y > 100 then return false, "usage: /way [zone] x y, e.g. /way Durotar 42.9 69.2" end
  local map
  if zone then
    map = Way.zone(zone)
    if not map then return false, "unknown zone: " .. zone end
  else
    map = C_Map.GetBestMapForUnit("player")
    if not map then return false, "can't tell where you are: add the zone, e.g. /way Durotar 42.9 69.2" end
  end
  if not (C_Map.SetUserWaypoint and UiMapPoint) then return false, "this game version has no map pins" end
  if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(map) then return false, "no map pins allowed on that map" end
  C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
  local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
  return true, string.format("map pin set: %s %.1f, %.1f", info and info.name or (zone or "here"), x, y)
end

function Way.run(text)
  local ok, msg = Way.set(text)
  say(ok and msg or ("|cffFF6B6B" .. msg .. "|r"))
end

--- Takes /way unless another addon already has it (call once all addons are loaded).
function Way.Start()
  for k, v in pairs(_G) do
    if type(k) == "string" and k:match("^SLASH_") and type(v) == "string" and v:lower() == "/way" then return false end
  end
  SLASH_CREWLOGWAY1 = "/way"
  SlashCmdList.CREWLOGWAY = Way.run
  return true
end

return Way
