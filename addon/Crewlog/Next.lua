-- "Next up" in game (DESIGN §5.5): what to pick up next where you are, from the server's recommendations in the Inbox,
-- checked against your log right now (things you've accepted or finished since show as done), plus the quests your
-- journals could pick up together.
local _, ns = ...
local Next = {}
ns.Next = Next

local GOLD = "|cffE3A21A"
local MUTED = "|cff8FA39C"
local TEAL = "|cff6DCFC4"
local WHITE = "|cffFFFFFF"
local SOON = "|cffF2C25B"

local function inbox() return rawget(_G, "Crewlog_Inbox") end

local function inLog(id)
  return C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id) ~= nil
end

local function completed(id)
  return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) == true
end

-- The Next block for this toon: the zone the player is in, else the first one the server sent.
function Next.pick(data, myGuid, uiMap)
  local first
  for _, n in ipairs((data and data.next) or {}) do
    if n.guid == myGuid then
      if uiMap and n.uiMap == uiMap then return n, true end
      first = first or n
    end
  end
  return first, false
end

function Next.lines(data, myGuid, uiMap)
  local out = {}
  local n, here = Next.pick(data, myGuid, uiMap)
  if not n then
    out[#out + 1] = MUTED .. "No suggestions for this toon yet. Click the compass to sync, then open this again."
  else
    out[#out + 1] = GOLD .. "Next up in " .. (n.zone or "this zone") .. "|r" .. (here and "" or (MUTED .. "  (where your quests are)|r"))
    for _, q in ipairs(n.quests or {}) do
      local title = string.format("%s |cff8FA39C(%s)|r", q.title or ("Quest " .. q.id), tostring(q.level or "?"))
      if completed(q.id) then
        out[#out + 1] = string.format("  %s✓ %s  done|r", MUTED, q.title or q.id)
      elseif inLog(q.id) then
        out[#out + 1] = string.format("  %s✓ %s  in your log|r", MUTED, q.title or q.id)
      else
        out[#out + 1] = "  " .. (q.soon and SOON or WHITE) .. title .. "|r" .. (q.soon and (SOON .. "  soon|r") or "")
        -- separate short lines: a wrapped line would lose its indent
        if q.giver then out[#out + 1] = "      " .. MUTED .. q.giver .. "|r" end
        if q.why then out[#out + 1] = "      " .. MUTED .. q.why .. "|r" end
      end
    end
  end
  -- Quests two or more of your journal crew can pick up now.
  for _, j in ipairs((data and data.journals) or {}) do
    if j.together and #j.together > 0 then
      out[#out + 1] = " "
      out[#out + 1] = GOLD .. "Pick up together|r " .. MUTED .. "· " .. (j.title or "journal") .. "|r"
      for _, p in ipairs(j.together) do
        local done = completed(p.id) or inLog(p.id)
        out[#out + 1] = string.format("  %s%s|r %s(%s)|r  %s%s|r", done and MUTED or WHITE, p.title or p.id, MUTED, tostring(p.level or "?"), TEAL, p.who or "")
        if p.giver and not done then out[#out + 1] = "      " .. MUTED .. p.giver .. "|r" end
      end
    end
  end
  return out
end

function Next.currentLines(myGuid)
  local uiMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  return Next.lines(inbox(), myGuid, uiMap)
end
