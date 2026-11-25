# Security

Please report security problems **privately**: use
[Report a vulnerability](https://github.com/niogtres/wow_crewlog/security/advisories/new) on this repository,
not a public issue. Say what you found and how to reproduce it; you'll get an answer within a few days.

In scope: the Windows app (including its updater), the addon, and the website and API at https://crewlog.dk that
they talk to. Please don't test against other people's accounts or journals, and don't run load or denial-of-service
tests against the live site.

## What the app and the addon do

- The app reads only the addon's own SavedVariables file, and never touches your Battle.net login or the game's memory.
- It signs in to the website with a device token, kept on your PC encrypted for your Windows user. **Unlink** in its
  tray menu ends that link, on the website as well.
- It talks to the website over HTTPS, checks the addon and installer it downloads against their published hashes, and
  opens only pages on the website.
- What the website keeps about you, and who sees it, is in its Privacy page (the footer at https://crewlog.dk).
