-- The crew in game. Party members running Crewlog show live (Live.lua, within seconds); everyone else in your
-- journals comes from the Inbox the Crewlog app writes (as fresh as their last sync and your last /reload).
local ADDON, ns = ...
local U = ns.U
local Crew = {}
ns.Crew = Crew

local GOLD = "|cffE3A21A"
local MUTED = "|cff8FA39C"
local TEAL = "|cff6DCFC4"
local WHITE = "|cffFFFFFF"

local function inbox() return rawget(_G, "Crewlog_Inbox") end

local function ago(t)
  if not t or t == 0 then return "never" end
  local d = U.now() - t
  if d < 90 then return "just now" end
  if d < 3600 then return math.floor(d / 60) .. " min ago" end
  if d < 86400 then return math.floor(d / 3600) .. " h ago" end
  return math.floor(d / 86400) .. " days ago"
end

-- Quest ids in the current character's log.
function Crew.myQuests()
  local mine = {}
  if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries then return mine end
  for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
    local info = C_QuestLog.GetInfo(i)
    if info and not info.isHeader and info.questID then mine[info.questID] = true end
  end
  return mine
end

-- Crewmates (any toon in any of your journals other than the one you're playing), deduplicated.
function Crew.mates(data, myGuid)
  local seen, list = {}, {}
  for _, j in ipairs((data and data.journals) or {}) do
    for _, t in ipairs(j.toons or {}) do
      if t.guid ~= myGuid and not seen[t.guid] then
        seen[t.guid] = true
        list[#list + 1] = t
      end
    end
  end
  return list
end

-- Who else is on this quest.
function Crew.onQuest(data, myGuid, questId)
  local who = {}
  for _, t in ipairs(Crew.mates(data, myGuid)) do
    for _, q in ipairs(t.quests or {}) do
      if q.id == questId then who[#who + 1] = { toon = t, quest = q } end
    end
  end
  return who
end

local function progress(q)
  if q.ready then return GOLD .. "ready|r" end
  if (q.total or 0) > 0 then return string.format("%d/%d", q.done or 0, q.total) end
  return ""
end

local function liveProgress(q)
  if q.ready then return GOLD .. "ready|r" end
  if #q.o == 1 then return string.format("%d/%d", q.o[1].h, q.o[1].n) end
  local done = 0
  for _, o in ipairs(q.o) do if o.h >= o.n then done = done + 1 end end
  return #q.o > 0 and string.format("%d/%d done", done, #q.o) or ""
end

-- Party members running Crewlog, live. live = Live.list() entries { guid, peer }.
local function liveLines(out, live, myQuests)
  out[#out + 1] = GOLD .. "Live in your party|r"
  for _, e in ipairs(live) do
    local p = e.peer
    local name = (ns.Live and ns.Live.hex(e.guid) or WHITE) .. (p.name or "?") .. "|r"
    local ids = {}
    for id in pairs(p.quests) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
      local sa, sb = myQuests and myQuests[a] and 0 or 1, myQuests and myQuests[b] and 0 or 1
      if sa ~= sb then return sa < sb end
      return a < b
    end)
    out[#out + 1] = string.format("  %s %s(lvl %s · %d quest%s · just now)|r", name, MUTED, tostring(p.level or "?"), #ids, #ids == 1 and "" or "s")
    if #ids == 0 then out[#out + 1] = MUTED .. "      nothing in the quest log" end
    for _, id in ipairs(ids) do
      local q = p.quests[id]
      local shared = myQuests and myQuests[id]
      out[#out + 1] = string.format("      %s%s|r  %s%s", shared and GOLD or "", q.title or ("Quest " .. id), liveProgress(q),
        shared and (TEAL .. "  · you too|r") or "")
    end
  end
  out[#out + 1] = " "
end

-- Text lines for the crew window: the live party first, then per journal each toon and its quests;
-- quests you share are gold. Toons shown live are not repeated under their journal.
function Crew.lines(data, myGuid, myQuests, live)
  local out = {}
  live = live or {}
  local isLive = {}
  for _, e in ipairs(live) do isLive[e.guid] = true end
  if #live > 0 then liveLines(out, live, myQuests) end
  local journals = (data and data.journals) or {}
  if #journals == 0 then
    if #live > 0 then return out end
    out[#out + 1] = MUTED .. "You're not in a journal yet, or the Crewlog app hasn't synced since you joined."
    out[#out + 1] = MUTED .. "Create or join one on the Crewlog website, then click the compass to sync."
    return out
  end
  for _, j in ipairs(journals) do
    out[#out + 1] = GOLD .. (j.title or "Journal") .. "|r"
    local any = false
    for _, t in ipairs(j.toons or {}) do
      if t.guid ~= myGuid and isLive[t.guid] then
        any = true
        out[#out + 1] = string.format("  %s%s|r %s(live above)|r", WHITE, t.name or "?", MUTED)
      elseif t.guid ~= myGuid then
        any = true
        local who = t.mine and "you" or (t.owner or "?")
        out[#out + 1] = string.format("  %s%s|r %s(lvl %s · %s · %s · synced %s)|r",
          WHITE, t.name or "?", MUTED, tostring(t.level or "?"), who, t.zone or "somewhere", ago(t.updated))
        local quests = t.quests or {}
        if #quests == 0 then out[#out + 1] = MUTED .. "      nothing in the quest log" end
        for _, q in ipairs(quests) do
          local shared = myQuests and myQuests[q.id]
          out[#out + 1] = string.format("      %s%s|r  %s%s", shared and GOLD or "", q.title or ("Quest " .. q.id), progress(q),
            shared and (TEAL .. "  · you too|r") or "")
        end
      end
    end
    if not any then out[#out + 1] = MUTED .. "  Nobody else's toons are in this journal yet." end
    out[#out + 1] = " "
  end
  return out
end

-- Short summary for the minimap tooltip.
function Crew.tooltip(tt, myGuid)
  local live = ns.Live and ns.Live.list() or {}
  if #live > 0 then
    tt:AddLine(" ")
    tt:AddLine(GOLD .. "Party|r " .. MUTED .. string.format("%d with Crewlog, live", #live))
    for _, e in ipairs(live) do
      local n = 0
      for _ in pairs(e.peer.quests) do n = n + 1 end
      tt:AddLine(string.format("  %s%s|r · %d quest(s)", ns.Live.hex(e.guid), e.peer.name or "?", n), 1, 1, 1)
    end
  end
  local data = inbox()
  local mates = Crew.mates(data, myGuid)
  if #mates == 0 then return end
  local mine = Crew.myQuests()
  local shared = 0
  for _, t in ipairs(mates) do
    for _, q in ipairs(t.quests or {}) do if mine[q.id] then shared = shared + 1 end end
  end
  tt:AddLine(" ")
  tt:AddLine(GOLD .. "Crew|r " .. MUTED .. string.format("%d toon(s) · %d on your quests", #mates, shared))
  for i, t in ipairs(mates) do
    if i > 6 then tt:AddLine(MUTED .. string.format("  +%d more", #mates - 6)) break end
    tt:AddLine(string.format("  %s · %d quest(s) · %s", t.name or "?", #(t.quests or {}), t.zone or "somewhere"), 1, 1, 1)
  end
end

-- The window -------------------------------------------------------------------------------

local win
local function build()
  win = CreateFrame("Frame", "CrewlogCrewFrame", UIParent, "BasicFrameTemplateWithInset")
  win:SetSize(440, 420)
  win:SetPoint("CENTER")
  win:SetMovable(true)
  win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  win:SetFrameStrata("DIALOG")
  if type(win.TitleText) == "table" then win.TitleText:SetText("Crewlog · Crew") end
  tinsert(UISpecialFrames, "CrewlogCrewFrame") -- Escape closes it

  -- Two tabs: the crew (journal + live party) and Next up (what to pick up where you are).
  win.tabs = {}
  for i, def in ipairs({ { "crew", "Crew" }, { "next", "Next up" } }) do
    local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    b:SetSize(96, 22)
    b:SetPoint("TOPLEFT", 12 + (i - 1) * 100, -28)
    b:SetText(def[2])
    b:SetScript("OnClick", function() Crew.Show(win.guid, def[1]) end)
    win.tabs[def[1]] = b
  end

  local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -56)
  scroll:SetPoint("BOTTOMRIGHT", -30, 34)
  local body = CreateFrame("Frame", nil, scroll)
  body:SetSize(390, 10)
  scroll:SetScrollChild(body)
  win.text = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  win.text:SetPoint("TOPLEFT")
  win.text:SetWidth(390)
  win.text:SetJustifyH("LEFT")
  win.text:SetSpacing(3)
  win.body = body

  win.foot = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  win.foot:SetPoint("BOTTOMLEFT", 14, 12)
  win.foot:SetPoint("BOTTOMRIGHT", -14, 12)
  win.foot:SetJustifyH("LEFT")
end

function Crew.Show(myGuid, mode)
  if not win then build() end
  win.guid = myGuid
  win.mode = mode or win.mode or "crew"
  for name, b in pairs(win.tabs or {}) do
    if b.SetEnabled then b:SetEnabled(name ~= win.mode) end -- the active tab is the one you can't click
  end
  local data = inbox()
  local lines = win.mode == "next" and ns.Next.currentLines(myGuid)
    or Crew.lines(data, myGuid, Crew.myQuests(), ns.Live and ns.Live.list() or {})
  win.text:SetText(table.concat(lines, "\n"))
  win.body:SetHeight(math.max(10, win.text:GetStringHeight() + 8))
  win.foot:SetText("From the app " .. ago(data and data.generatedAt) .. " · click the compass to refresh")
  win:Show()
end

-- Live party changes redraw the window while it's open.
function Crew.Refresh(myGuid)
  if win and win:IsShown() then Crew.Show(myGuid, win.mode) end
end

function Crew.Toggle(myGuid, mode)
  if win and win:IsShown() and (mode == nil or mode == win.mode) then win:Hide() else Crew.Show(myGuid, mode) end
end
