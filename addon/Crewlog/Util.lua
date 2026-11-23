-- Small pure helpers. No WoW frames here, so everything runs under plain Lua 5.1 in tests.
local _, ns = ...
local U = {}
ns.U = U

function U.now()
  return (GetServerTime and GetServerTime()) or time()
end

-- Split on a single literal character. GUID fields are never empty, so gmatch is fine.
function U.split(s, sep)
  local out = {}
  for part in string.gmatch(s, "[^%" .. sep .. "]+") do out[#out + 1] = part end
  return out
end

-- "Creature-0-58868-1-14556280-3143-82878CE44C" -> 3143, "npc"
-- "GameObject-0-...-<id>-<spawn>"                -> id,   "object"
function U.parseUnitGuid(guid)
  if type(guid) ~= "string" then return nil end
  local p = U.split(guid, "-")
  local kind = p[1]
  if kind == "Creature" or kind == "Vehicle" then return tonumber(p[6]), "npc" end
  if kind == "GameObject" then return tonumber(p[6]), "object" end
  return nil
end

-- "Player-6949-0A1B2C3D" -> 6949 (Forever returns "" from GetRealmName, the GUID still has the realm id)
function U.realmIdFromPlayerGuid(guid)
  if type(guid) ~= "string" then return nil end
  local p = U.split(guid, "-")
  if p[1] ~= "Player" then return nil end
  return tonumber(p[2])
end

function U.round(x, places)
  if type(x) ~= "number" then return nil end
  local m = 10 ^ (places or 3)
  return math.floor(x * m + 0.5) / m
end

-- Order-dependent 32-bit polynomial hash of a sorted id list. Pure arithmetic (no bit library),
-- exact in doubles because h * 31 + id stays far below 2^53.
function U.hashIds(ids)
  local h = 7
  for i = 1, #ids do h = (h * 31 + ids[i]) % 4294967296 end
  return string.format("%08x", h)
end

-- Insert into a sorted array of numbers; returns true when it was not there yet.
function U.sortedInsert(list, value)
  local lo, hi = 1, #list
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    local v = list[mid]
    if v == value then return false end
    if v < value then lo = mid + 1 else hi = mid - 1 end
  end
  table.insert(list, lo, value)
  return true
end

function U.copySorted(ids)
  local out = {}
  for i = 1, #ids do out[i] = ids[i] end
  table.sort(out)
  return out
end

function U.newId()
  local t = {}
  for i = 1, 32 do t[i] = string.format("%x", math.random(0, 15)) end
  return table.concat(t)
end

-- Debounce by key on C_Timer: only the last call within `delay` seconds runs.
local tokens = {}
function U.debounce(key, delay, fn)
  tokens[key] = (tokens[key] or 0) + 1
  local mine = tokens[key]
  C_Timer.After(delay, function()
    if tokens[key] == mine then fn() end
  end)
end

-- "5/10 Mottled Boar slain" or "Mottled Boar slain: 5/10" -> "Mottled Boar slain" (the counts live in h/n).
function U.objectiveLabel(text)
  if type(text) ~= "string" or text == "" then return nil end
  local s = text:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub("%s*:%s*%d+%s*/%s*%d+%s*$", "")
  if s == "" then return nil end
  return U.trim(s, 120)
end

function U.trim(s, max)
  if type(s) ~= "string" then return nil end
  if #s > max then return s:sub(1, max) end
  return s
end
