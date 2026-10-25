# tvplayer

Cross-platform IPTV player written in Flutter. Targets: Linux desktop first,
then Android; iOS possibly later.

## Standing rules

### Public repository — no personal data
This repo is public. Never commit:
- personal emails, real names, domains, IP addresses
- tokens, API keys, passwords
- stream URLs, provider names, Xtream/M3U credentials or playlist URLs

Use placeholders such as `example.com`, `user`, `pass`, `192.0.2.1` (RFC 5737)
in code, tests, docs and fixtures. User-specific values come from runtime
settings or a gitignored local config file (e.g. `config.local.json`), with a
committed `config.example.*` alongside showing the shape with placeholder values.
Before committing, check the staged diff for anything that looks personal.

### Git
- Never run `git push`, never add remotes, never touch GitHub credentials.
  Local commits are fine.
- The git identity for this repo is set in the repo-local config. Never change
  global git config, and never write the commit email address into any file
  in the repo.

### Scope
- Ship a player only: no bundled playlists, providers or content.

### Architecture
- Keep core logic (Xtream/M3U parsing, EPG, models) in a UI-independent pure
  Dart package (no Flutter imports) so it can be reused across platforms. The
  Flutter app depends on it; it never depends on the app.

### UI
- UI styling follows docs/design.md; use the tokens in lib/ui/theme/ instead of hard-coded colours.

### Environment
- Don't use `sudo`. If something needs root, stop and give the user the exact
  command to run.
