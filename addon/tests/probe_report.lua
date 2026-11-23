-- Summarizes a Crewlog_Probe SavedVariables file.
-- Run: lua5.1 addon/tests/probe_report.lua fixtures/private/Crewlog_Probe.lua
local path = assert(arg[1], "usage: probe_report.lua <Crewlog_Probe.lua>")
assert(loadfile(path))()
local db = assert(Crewlog_ProbeDB, "no Crewlog_ProbeDB in file")

local function dump(v, indent, depth)
  indent, depth = indent or "", depth or 0
  if type(v) ~= "table" then return tostring(v) end
  if depth > 3 then return "{...}" end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = indent .. "  " .. tostring(k) .. " = " .. dump(v[k], indent .. "  ", depth + 1) end
  return "{\n" .. table.concat(parts, "\n") .. "\n" .. indent .. "}"
end
local function h(t) print("\n==== " .. t .. " ====") end

print("probeVersion", db.probeVersion, "sessions", db.sessions, "runs", db.runs and #db.runs or 0)
local runs = db.runs or {}
local run = runs[#runs]
local first = runs[1]

h("ENVIRONMENT (last run)")
print(dump(run and run.environment or db.environment))

if run then
  h("FUNCTIONS PRESENT (" .. #run.functions.present .. ")")
  print(table.concat(run.functions.present, "\n"))
  h("FUNCTIONS MISSING (" .. #run.functions.missing .. ")")
  print(table.concat(run.functions.missing, ", "))
  h("C_ NAMESPACES (" .. #run.functions.namespaces .. ")")
  print(table.concat(run.functions.namespaces, ", "))
  h("QUEST NAMESPACE MEMBERS")
  for ns, names in pairs(run.functions.questNamespaces) do print(ns .. ": " .. table.concat(names, ", ")) end

  for i, r in ipairs(runs) do
    h("RUN " .. i .. " @ " .. tostring(r.at))
    print("player", dump(r.player))
    print("completed", dump(r.completed))
    print("log count modern/old", dump(r.log.countModern), dump(r.log.countOld))
    for _, e in ipairs(r.log.entries) do print("log entry", dump(e)) end
    print("questLines", dump(r.questLines))
    print("comms", dump(r.comms))
  end
end

h("EVENTS")
print("registered:", table.concat(db.events.registered, ", "))
print("rejected:", table.concat(db.events.rejected, ", "))
local counts = {}
for k, v in pairs(db.eventCounts) do counts[#counts + 1] = k .. "=" .. v end
table.sort(counts)
print("counts:", table.concat(counts, ", "))

h("EVENT LOG (non-ADDON_LOADED)")
for _, e in ipairs(db.eventLog) do
  if e.e ~= "ADDON_LOADED" then
    local a = {}
    for i = 1, (e.n or 0) do a[i] = type(e.args[i]) == "table" and dump(e.args[i]) or tostring(e.args[i]) end
    local extra = ""
    if e.npcGuid or e.questID or e.title then
      extra = string.format("  npc=%s (%s) quest=%s title=%s map=%s xy=%s,%s", tostring(e.npcGuid), tostring(e.npcName), tostring(e.questID), tostring(e.title), tostring(e.mapId), tostring(e.x), tostring(e.y))
    end
    print(e.t, e.e, table.concat(a, " | ") .. extra)
  end
end
