# Changelog

What changed in the Crewlog app and addon, newest first.

## 0.8.19 — 2026-11-26
- Website and addon: Get in step. For each toon, the few things to do on your own so you're on the same quests as most of your crew: hand in or finish an earlier part of a chain, pick a quest up, or reach a level. On the journal page and the toon page, and in game first on the Next up tab, where each one ticks off as soon as you've done it. The minimap button's tooltip says how many are left.
- Website and addon: quests that share a name along a chain show which part they are, like Arugal's Folly (part 2), so crewmates on different steps no longer look like they're on the same quest.
- Website and addon: a quest that several NPCs can give or take (a class quest any trainer hands out) points to one of your own faction, not to Thunder Bluff for a dwarf.

## 0.8.18 — 2026-11-25
- Addon: party sync only counts messages from the members of your group, each about themselves.
- App and addon: toon names and quest titles from other players are shown as plain text, game colour and picture codes included.
- App: Unlink in the tray menu now cuts the PC off on the website too. The app only opens pages on the Crewlog website, and checks the installer it downloads before running it.

## 0.8.17 — 2026-11-25
- The app tells the website which app and addon versions your PC has whenever it runs, so Linked PCs is right while WoW is closed. It adds no extra traffic: the versions ride along on the call the app already makes for your crew.

## 0.8.16 — 2026-11-25
- No changes to the app or the addon in this version.

## 0.8.15 — 2026-11-25
- Addon: The route map starts where your toon stands again. The addon noted your position only at the moment the game saved, when the game often can't tell any more, so the website never got one. It now notes it as you play (every 20 seconds and when you change zone) and keeps the last one when you log out or sync. Inside a dungeon it keeps none.

## 0.8.14 — 2026-11-25
- Addon: Your own route in the game: click the compass by the minimap → Route on map → Just me. It's the route from your toon's page on the website: your current quests, and quests to pick up along the way if you want them. Your journals' routes are still there below it.
- Addon: `/cl next` follows each toon's own settings (order, and whether grey and red quests are left out).

## 0.8.13 — 2026-11-25
- App and addon: The Windows app and the addon stay open source on GitHub (GPL-3.0), now in a repository of their own; the website's code is no longer published there. Nothing changes for you: updates arrive as before.

## 0.8.12 — 2026-11-25
- No changes to the app or the addon in this version.

## 0.8.11 — 2026-11-24
- Website and addon (route): Quests in a capital (Undercity, Orgrimmar, Thunder Bluff…) are no longer stops on the zone around it, where Undercity's NPCs ended up in Tirisfal's lake. A city is its own zone: its quests show under "Also in Undercity", and you get its route by picking the city.

## 0.8.10 — 2026-11-24
- Addon: Route on map lists only the journals the toon you're playing is in.
- Addon: Route stops in a capital beyond the zone's map (Ug'thok in the north of Orgrimmar on Durotar's route) no longer fall off the map: they sit at its edge, show on the city's own map in game, and their /way points into the city.

## 0.8.9 — 2026-11-24
- Addon: Your journal's route in the game: click the compass by the minimap → Route on map, and pick a journal. Its stops show as numbered gold markers joined by a line on that zone's world map; hover one to see what to do there and for whom. Pick it again, or Clear route, to take it off.

## 0.8.8 — 2026-11-24
- App: Windows 11 can hide Crewlog's tray icon (with no ^ to find it under). The status window now spots that and offers a "Show icon" button that puts it by the clock.
- App: The status window's text no longer gets cut off when Windows display scaling is above 100 %.

## 0.8.7 — 2026-11-24
- Website and addon: Click any coordinates on the website to copy a /way command, then paste it in the game's chat. With TomTom or a similar addon you get their waypoint; without one, Crewlog drops the game's own map pin and tracks it (/cl way works either way).

## 0.8.6 — 2026-11-24
- The addon notes where you stand when the game saves (every sync and logout), so the website's route map can start from your crew's position.

## 0.8.5 — 2026-11-24
- App: Crewlog has moved to https://crewlog.dk. The app switches to the new address by itself; if yours stopped syncing, download Crewlog-Setup.exe from crewlog.dk and run it over the old one (your settings and link stay).

## 0.8.4 — 2026-11-24
- No changes to the app or the addon in this version.

## 0.8.3 — 2026-11-24
- App: The installer's welcome splash says what Crewlog is for: group questing, made easy.

## 0.8.2 — 2026-11-24
- Addon: /cl status shows how party sync is doing: messages sent, how many came back from the server, how many arrived from the others, and any the game refused. Helps when a party member doesn't show up live.

## 0.8.1 — 2026-11-23
- Addon: Clicking the compass by the minimap opens a menu: Sync now, Crew, Next up, Member colours, Markers over party, Hide minimap button. Shift-click still syncs right away, right-click opens your crew.
- Website and addon: Next up leaves out quests far above your level and ranks a little-too-hard ones lower. Each suggestion's giver and reasons sit on their own lines.
- Addon: The crew window shows which tab you're on.

## 0.8.0 — 2026-11-23
- Addon: In game, the command is now /cl (or /crewlog): /cl opens the crew window, /cl next what to pick up next.
- Addon: Next up in game: the crew window has a "Next up" tab with the best quests to pick up where you are, who gives them and why they're worth it. Quests you've picked up or finished since are ticked off right away. Below it, quests your journal crew can pick up together.
- Addon: Quest tooltips show your crew: who else is on the quest and how far they are (party members live), and who has already done it.

## 0.7.0 — 2026-11-23
- App and addon: Under the hood: tidied up everything left over from the project's first working name.
- App: Fixed: "Check for updates" could fail with "failed its checksum" because a cache in front of the website handed out the previous addon download.

## 0.6.5 — 2026-11-23
- App: Your journal crew in game stays fresh: the app fetches what everyone is on every 2 minutes while WoW is running (every 15 minutes otherwise), so /reload shows the latest without you syncing first.

## 0.6.4 — 2026-11-23
- App: Updates arrive sooner: Crewlog looks for a new version every 30 minutes (was every 6 hours).

## 0.6.3 — 2026-11-23
- App: A clearer compass by the clock: a simple bright gold star that stays sharp at small sizes, on dark and light taskbars.

## 0.6.2 — 2026-11-23
- App: Point at the compass by the clock to see the Crewlog version and what it's doing.

## 0.6.1 — 2026-11-23
- App: A status window says Crewlog is running and what's left to do (find WoW, install the addon, link Discord), with a button for each. It opens after installing and whenever you start Crewlog yourself, and stays until you click "Got it". Starting with Windows stays quiet.
- App: Starting Crewlog while it's already running brings up that window instead of doing nothing. Double-click the compass by the clock (or Status… in its menu) to open it any time.
- App: Fixed: some messages from the tray app could come from the wrong thread.

## 0.6.0 — 2026-11-23
- App: Crewlog now comes with an installer, Crewlog-Setup.exe. It installs for your Windows user (no admin rights needed), adds a Start menu shortcut, starts with Windows (switch that off in the tray menu) and uninstalls from Windows' app list.
- App: Updates install themselves in the background: the app downloads only what changed and restarts in a second; the addon updates too (/reload in game to load it). No more update prompts.
- App: Already using Crewlog? Your copy moves itself into the installer on its next update. Your settings and link stay.

## 0.5.0 — 2026-11-23
- Addon: Live party sync: party members who also run Crewlog see each other's quest log and progress within seconds, without anyone reloading. Shared quests show in gold in the crew window (/cl).
- Addon: Optional member colours: type /cl colors to give every party member their own colour (the same for everyone in the group). Off by default; class colours otherwise.
- Addon: Optional markers: type /cl markers to put a small compass over party members who run Crewlog. Off by default. It switches on friendly nameplates and puts that setting back when you turn markers off.

## 0.4.0 — 2026-11-23
- Addon: In game: /cl opens the crew window, /cl status shows the sync status.

## 0.3.0 — 2026-11-23
- Addon: In game: right-click the compass to see what your journal crew is on, with the quests you share in gold.
- App: Journals… in the tray menu, to tick which toons go in which journal.

## 0.2.2 — 2026-11-23
- Addon: Quest objectives show their names (for example "Scorpid Worker Tail 4/10"), not just numbers.
- The app and the addon update themselves from the website.

## 0.2.1 — 2026-11-23
- Addon: A compass button by the minimap syncs with one click; shift-click skips the question. Never during combat.

## 0.2.0 — 2026-11-23
- App and addon: First version: the addon records your quests, the Windows app uploads them, and the website shows your current quests and what to do next.
