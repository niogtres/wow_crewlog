# Crewlog Probe

A one-time check of which quest, map, chat and addon APIs the **WoW: Forever** client provides. It only reads data and changes nothing in the game.

## Steps (on the gaming PC)

1. Unzip `Crewlog_Probe.zip` into `World of Warcraft\_forever_\Interface\AddOns\` (the folder name may differ slightly; it is the one that has `Wow.exe` or `WowClassic.exe` next to it).
   You should end up with `...\Interface\AddOns\Crewlog_Probe\Crewlog_Probe.toc`.
2. Start the game. On the character screen, open **AddOns** and make sure *Crewlog Probe* is ticked.
   If it says *Out of date*, tick **Load out of date AddOns** at the top.
3. Log in with a character that has a few quests done and a few in the log. Standing in a questing zone is best.
4. Type `/crewprobe`. Four lines in chat confirm it ran.
5. Play for 5 minutes. Accept a quest, kill or loot something for an objective, turn a quest in, and talk to a quest giver. If a friend is around, invite them to a party; that tests the live sync channel.
6. Type `/crewprobe` once more, then `/reload`.
7. Copy this file back to the dev machine:
   `WTF\Account\<YOUR ACCOUNT>\SavedVariables\Crewlog_Probe.lua`
   and put it in `fixtures/private/` in the repo. That folder is git-ignored.

Afterwards you can delete the `Crewlog_Probe` folder.

## What it records

- Client build, TOC interface number, project ID, locale, max level.
- Which of 109 functions and 36 events exist, plus every `C_*` namespace and the functions in the quest namespaces.
- Your character's GUID format, level, race, class, map ID and position.
- Completed quests: count plus a sample of 40 IDs, read through whichever API exists.
- The quest log with each objective's progress, read through both old and new APIs.
- Quest-line and zone-story data for the current map.
- An addon message sent to yourself and to your party.
- Quest-related events as they fire, with the NPC GUID and coordinates when you talk to a quest giver.

It records no chat text and nothing about other players beyond the addon-message test.
