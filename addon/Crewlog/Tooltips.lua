-- Crew lines on quest tooltips (DESIGN §5.5): "Brogg 3/8 · Ashka done ✓". From the live party (Live.lua) and the
-- journal crew in the Inbox. Hooks whatever quest tooltips this client has; each hook only if the function exists.
local _, ns = ...
local Tips = {}
ns.Tooltips = Tips

local GOLD = "|cffE3A21A"
local MUTED = "|cff8FA39C"

local function inbox() return rawget(_G, "Crewlog_Inbox") end

local function progressText(done, total, ready)
  if ready then return GOLD .. "ready to turn in|r" end
  if (total or 0) > 0 then return string.format("%d/%d", done or 0, total) end
  return "on it"
end

-- Lines for one quest: each crewmate who has it (live party first, then journal crew) or has done it.
function Tips.lines(questId, myGuid)
  local out, seen = {}, { [myGuid or ""] = true }
  local Live = ns.Live
  for _, e in ipairs(Live and Live.list() or {}) do
    local q = e.peer.quests[questId]
    if q then
      seen[e.guid] = true
      local done = 0
      for _, o in ipairs(q.o) do if o.h >= o.n then done = done + 1 end end
      local txt = (#q.o == 1 and not q.ready) and string.format("%d/%d", q.o[1].h, q.o[1].n) or progressText(done, #q.o, q.ready)
      out[#out + 1] = string.format("%s%s|r %s  %s(live)|r", Live.hex(e.guid), e.peer.name or "?", txt, MUTED)
    end
  end
  local data = inbox()
  for _, j in ipairs((data and data.journals) or {}) do
    for _, t in ipairs(j.toons or {}) do
      if not seen[t.guid] then
        for _, q in ipairs(t.quests or {}) do
          if q.id == questId then
            seen[t.guid] = true
            out[#out + 1] = string.format("%s %s", t.name or "?", progressText(q.done, q.total, q.ready))
          end
        end
        if not seen[t.guid] then
          for _, id in ipairs(t.doneIds or {}) do
            if id == questId then
              seen[t.guid] = true
              out[#out + 1] = string.format("%s %sdone ✓|r", t.name or "?", MUTED)
              break
            end
          end
        end
      end
    end
  end
  return out
end

function Tips.add(tt, questId, myGuid)
  if not (tt and questId and questId > 0) then return end
  local lines = Tips.lines(questId, myGuid)
  if #lines == 0 then return end
  tt:AddLine(" ")
  tt:AddLine(GOLD .. "Crewlog|r")
  for i, l in ipairs(lines) do
    if i > 8 then tt:AddLine(MUTED .. string.format("+%d more", #lines - 8)) break end
    tt:AddLine(l, 1, 1, 1)
  end
  if tt.Show then tt:Show() end
end

-- Hook every quest tooltip this client offers. Called once at login.
function Tips.Start(guidFn)
  local function me() return guidFn() end
  -- Modern tooltip pipeline (quest links, map pins, the objective tracker where it uses it).
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Quest then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Quest, function(tt, data)
      if data and data.id then Tips.add(tt, data.id, me()) end
    end)
  elseif hooksecurefunc and GameTooltip and GameTooltip.SetHyperlink then
    -- Older pipeline: quest links in chat.
    hooksecurefunc(GameTooltip, "SetHyperlink", function(tt, link)
      local id = type(link) == "string" and tonumber(link:match("quest:(%d+)"))
      if id then Tips.add(tt, id, me()) end
    end)
  end
  if not hooksecurefunc then return end
  -- The modern quest log (map side panel) shows a tooltip on hover: add to it.
  if QuestMapLogTitleButton_OnEnter then
    hooksecurefunc("QuestMapLogTitleButton_OnEnter", function(self)
      if self and self.questID then Tips.add(GameTooltip, self.questID, me()) end
    end)
  end
  -- The classic quest log shows no tooltip on hover: show ours when the crew has something to say.
  if QuestLogTitleButton_OnEnter then
    hooksecurefunc("QuestLogTitleButton_OnEnter", function(self)
      local idx = self and self.GetID and self:GetID()
      local info = idx and C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetInfo(idx)
      if info and info.questID and #Tips.lines(info.questID, me()) > 0 then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(info.title or "", 1, 1, 1)
        Tips.add(GameTooltip, info.questID, me())
      end
    end)
  end
end
