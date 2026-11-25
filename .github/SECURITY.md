# Security

Please report security problems **privately**: use
[Report a vulnerability](https://github.com/niogtres/wow_crewlog/security/advisories/new) on this repository,
not a public issue. Say what you found and how to reproduce it; you'll get an answer within a few days.

In scope: the website and API at https://crewlog.dk, the Windows app (including its updater) and the
addon. Please don't test against other people's accounts or journals, and don't run load or denial-of-service tests
against the live site.

## How Crewlog handles data

- HTTPS only. The app signs in with a device token: a random 256-bit value, of which the site stores only a SHA-256 hash.
- No passwords of our own except **journal passwords**, which are stored PBKDF2-SHA256-hashed. Account login is
  Discord only, and the site stores just the Discord id, name and avatar.
- Journal members see the quest data, level and zone of the **toons attached to that journal**, plus the owning
  account's Discord name and avatar. Nothing else.
- Journal keys are 10 random characters (about 50 bits). Joining is rate-limited per account and per IP: 10 wrong
  keys or passwords per 15 minutes.
- No Battle.net credentials are ever touched. The app only reads the addon's own SavedVariables file.
