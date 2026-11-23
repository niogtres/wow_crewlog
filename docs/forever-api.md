# WoW: Forever client: addon API facts

Source: the `Crewlog_Probe` 0.0.1 run on 2026-11-23, fixture `fixtures/private/Crewlog_Probe.lua` (git-ignored). The character was a level 1 Troll Rogue (Horde) in Valley of Trials, Durotar. We ran 2 probe runs, accepted 3 quests, turned in 1 and made 5 kills toward an objective.
Summary tool: `lua5.1 addon/tests/probe_report.lua <file>` (Docker: `nickblah/lua:5.1`).

## The big picture

**Forever runs on the modern (retail) client engine, not the Classic one.**

| Fact | Value |
|---|---|
| Version / build | `1.60.1` / `71037` (Nov 18 2026) |
| TOC `## Interface:` | **16001**. Other numbers, or a list without it, show *Incompatible* |
| `WOW_PROJECT_ID` | **18** (`WOW_PROJECT_CAMELOT`). Mainline = 1, Classic = 2 |
| Max level / expansion | 60 / 0 |
| `C_GameRules.GetActiveGameMode()` | 1 |
| Lua | 5.1 (as always) |
| `C_*` namespaces | 271. Includes `C_Housing*`, `C_Discord`, `C_EncodingUtil` and `C_LevelSquish`: this is the modern client with retail systems switched off |
| `GetRealmName()` | `""` (empty). The GUID still carries a realm ID (`Player-6949-…`) |

Consequences:
- Use **only modern APIs** (`C_QuestLog`, `C_ChatInfo`, `C_AddOns`, `C_Map`, `Settings`). The Classic globals are gone: `GetQuestsCompleted`, `GetQuestLogTitle`, `GetNumQuestLogEntries`, `SelectQuestLogEntry`, `IsQuestFlaggedCompleted`, `SendAddonMessage`, `GetAddOnMetadata`, `InterfaceOptions_AddCategory`.
- Retail addon libraries and patterns work. Classic-only code paths can be dropped.
- **Don't rely on realm names.** Identify characters by GUID (already the design), and keep the name only for display.

## Quest data

| Need | API that works | Notes |
|---|---|---|
| All completed quests | `C_QuestLog.GetAllCompletedQuestIDs()` | Array of IDs. It went from 0 to 2 after one turn-in |
| Single check | `C_QuestLog.IsQuestFlaggedCompleted(id)` | `IsQuestFlaggedCompletedOnAccount` exists too (account-wide flags) |
| Log size | `C_QuestLog.GetNumQuestLogEntries()` → `(entries, quests)` | Entries **include zone headers** (`isHeader = true`, `questID = 0`) |
| Log entry | `C_QuestLog.GetInfo(index)` → table | `questID, title, level, difficultyLevel, isHeader, isHidden, isTask, isScaling (true), questClassification (7 = normal), suggestedGroup, frequency, isOnMap, hasLocalPOI` |
| Objectives | `C_QuestLog.GetQuestObjectives(questID)` | `{ text = "5/10 Mottled Boar slain", type = "monster" \| "item" …, numFulfilled, numRequired, finished }`. Use the numbers, not the text |
| Turn-in ready | `C_QuestLog.ReadyForTurnIn(questID)` | |
| Quests on map | `C_QuestLog.GetQuestsOnMap(mapID)` | Active quests with POI `x, y` (0–1) |
| Quest lines | `C_QuestLine.GetAvailableQuestLines(mapID)` | Returned **empty** right after `RequestQuestLinesForMap`. It's async: `QUESTLINE_UPDATE` fires later. Needs a retest that waits for the event |
| Zone story | `C_QuestLog.GetZoneStoryInfo(mapID)` | Nothing in the starting zone |

**Quest IDs:** classic quests keep their **original vanilla IDs** (`788` *Cutting Teeth*, `4641` *Your Place in the World*). Reworked or new Forever quests have **new high IDs** (`97279` *Wayward Weapons*, `3911` seen completed). So QuestieDB's vanilla data matches the old quests directly, and new quests need the Forever QuestieDB build or our own harvest.

## Events (all 36 we asked for exist)

Observed payloads:

| Event | Args | Use |
|---|---|---|
| `QUEST_ACCEPTED` | `questID` | Modern: one argument (no log index) |
| `QUEST_TURNED_IN` | `questID, xpReward, moneyReward` | The completion event |
| `QUEST_REMOVED` | `questID, wasReplayQuest` | Also fires right after a turn-in. Abandon = `REMOVED` without a preceding `TURNED_IN` |
| `QUEST_WATCH_UPDATE` | `questID` | **Fires on every objective tick.** Re-read `GetQuestObjectives` then |
| `UNIT_QUEST_LOG_CHANGED` | `"player"` | Coarse "something changed" |
| `QUEST_LOG_UPDATE` | — | Very chatty. Only debounce on it |
| `QUEST_DETAIL` | `questStartItemID` (0) | Quest-offer dialog. `GetQuestID()`, `UnitGUID("npc")` and the position are valid here, so this is where we harvest **quest givers** |
| `QUEST_COMPLETE` | — | Turn-in dialog. Same data, so this is where we harvest **turn-in NPCs** |
| `QUEST_DATA_LOAD_RESULT` | `questID, success` | After the quest cache loads |
| `GOSSIP_SHOW` / `GOSSIP_CLOSED` | — | NPC chat. `GetQuestID()` is 0 here |
| `UI_INFO_MESSAGE` | `msgType (315), "Mottled Boar slain: 3/10"` | Objective text toast. Not needed |
| `QUESTLINE_UPDATE` | `false` | Answer to `RequestQuestLinesForMap` |
| `PLAYER_XP_UPDATE`, `ZONE_CHANGED*`, `PLAYER_LOGOUT` | — | As expected |

Kill → `QUEST_WATCH_UPDATE(788)` + `UNIT_QUEST_LOG_CHANGED` + `UI_INFO_MESSAGE` within the same frame.

## NPC and position harvesting

- `UnitGUID("npc")` during `QUEST_DETAIL` / `QUEST_COMPLETE` → `Creature-0-58868-1-14556280-3143-82878CE44C`. The **6th field is the NPC ID**: 3143 = Gornek, 10176 = Kaltunk. Those are vanilla NPC IDs, so they match QuestieDB.
- `C_Map.GetBestMapForUnit("player")` → uiMapID (1411 = Durotar, parent 1414 = Kalimdor). These are the modern uiMapIDs, so convert them when joining QuestieDB zone IDs.
- `C_Map.GetPlayerMapPosition(map, "player"):GetXY()` → 0–1 coordinates. `UnitPosition("player")` → world coordinates plus instance ID.

## Addon messages

- `C_ChatInfo.RegisterAddonMessagePrefix("CREWLOGPROBE")` → `0` (success) on the first call and `1` (already registered) on the second, so it returns an enum, not a boolean.
- `C_ChatInfo.SendAddonMessage(prefix, msg, "WHISPER", "Zarnokk")` → `0`, but the server answered *"No player named 'Zarnokk' is currently playing"*, and `CHAT_MSG_ADDON` never arrived. Whispering yourself by bare name fails. That's probably the empty realm name; try `UnitName` + `"-"` + `GetNormalizedRealmName()`, or skip self-whispers altogether.
- **PARTY/RAID is not tested yet** (the character was solo). This is the main open risk for live sync.
- Available helpers: `C_EncodingUtil.SerializeCBOR` / `CompressString`, which are handy for compact messages and SavedVariables. `C_Timer`, `Settings.RegisterCanvasLayoutCategory` and `C_AddOns.GetAddOnMetadata` are also present.

## Still to verify (probe 0.0.2 / during M1)

1. **Party addon messages** between two clients (needs a second player).
2. **Quest lines:** call `RequestQuestLinesForMap`, wait for `QUESTLINE_UPDATE`, then read `GetAvailableQuestLines` / `GetQuestLineQuests`. Test in a zone with a story chain, not the starting valley.
3. `GetAllCompletedQuestIDs()` size and speed on a high-level character (hundreds of IDs).
4. Whether TOC file-name suffixes (`_Mainline`, `_Vanilla`, …) are honoured. A plain `<Name>.toc` works, so this is not a blocker.
