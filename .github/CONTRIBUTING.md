# Contributing

Crewlog is a small fan project. Bug reports and ideas are very welcome as
[issues](https://github.com/niogtres/wow_crewlog/issues/new/choose), including for the website at crewlog.dk.

This repository holds the addon and the Windows app. Before you send a pull request for anything bigger than a fix,
open an issue first so we can agree on the approach. Some ground rules:

- **Data leaves the game only through SavedVariables**, which WoW writes on `/reload` and logout. The addon can't
  talk to the internet; the Windows app reads that file and syncs it.
- **Only the official addon interface.** No automation, no memory reading, nothing that changes the game.
- **In-game visuals and settings are opt-in.** Anything that changes how the game looks starts switched off.
- **Tests:** `dotnet test Crewlog.slnx` and the Lua tests in `addon/tests` (see the README). Add a test with your change.
- **Changelog:** add a line to [CHANGELOG.md](CHANGELOG.md), written for players, not developers.

By contributing you agree that your contribution is licensed under the [GPL-3.0](LICENSE), like the rest of the project.
