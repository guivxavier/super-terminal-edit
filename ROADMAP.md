# Roadmap

## Phase 0: snapshot ✅
The setup as it runs today, imported from `~\.dotfiles` (Kev's two PCs). Not installable yet.

## Terminal: WezTerm ✅
Decided and installed on both PCs (see `docs/terminal-evaluation.md`): native pin in Lua, Ctrl+Alt+T agent, tab restore, sudo/gsudo. The installer (phase 1) must:
- download the pinned WezTerm portable zip;
- compile `terminal/agent/agent.cs`;
- create the shortcuts (`terminal/agent/shortcuts.ps1`);
- link `terminal/wezterm/` → `~\.config\wezterm`.

## Phase 1: anyone can install it
Goal: a colleague runs one command on a clean Windows and gets the same terminal.

- [ ] **`install.ps1`**: checks Windows / winget, installs the dependencies (pwsh 7 MSI, Windows Terminal, fastfetch, fzf, zoxide, eza, bat, rg, fd, uutils, micro, helix, lazygit, delta, yazi, glow, mpv, yt-dlp, chafa, a Nerd Font), creates the links from the repo to where each tool reads its config, backs up what was there before. Idempotent (running it again only fixes what is missing). An `-Uninstall` puts the backups back.
- [ ] **Config per person**, outside the repo, in `~\.config\superterminal\`: the PCs are done (`pcs.json`: name, Tailscale name, user, ssh shell, IP, MAC for wake, written by setup > Tailscale); still to do: name, theme, which modules are on (yt, st, pin...).
- [ ] **Split the profile** (1380 lines in one file) into modules: `prompt`, `nav` (cd/ls/menu), `completion`, `header` (ff/pin), `git`, `pcs` (ssh/get/send/wake), `linux`, `apps`. A slow or broken module can be turned off by itself.
- [ ] **Fewer machine-specific assumptions**: Windows Terminal Store vs portable, Windows 10 vs 11, no WSL, no Tailscale, no second PC: each must work or switch off cleanly.
- [x] **Updates**: `super upgrade` = latest version from GitHub, applied with `install.ps1 -SkipApps` (files changed on this PC are kept, the new one saved as `.new`); `super sync` = this version over ssh to the other named PCs, which apply it; `super status` compares without changing anything. Only by hand: no automatic pulls (a bad commit would otherwise run on every PC by itself).
- [x] **First-run setup** (Kev's request): `setup` (`terminal/setup/setup.ps1`), a guided screen that sets up whatever needs an account or a choice before the terminal is 100%. Opens by itself the first time; each step can be redone later (`setup <step>`):
  Every step is a guided page: numbered steps, the current one with its shortcut keys, and each step ticks itself off when the setup detects it.
  - [x] font: pick a .zip / .ttf (file dialog or path) or download CaskaydiaMono; WezTerm reads `~\.config\superterminal\font.txt`;
  - [x] Tailscale: install, sign in, other PCs, SSH server on this PC, **names for ssh** (`pcs.json` + `~\.ssh\config`, existing `Host` entries are picked up, the Tailscale name works too), copy the key (no password);
  - [x] YouTube for `yt`: shortcuts for the extension, its private-window setting and a private window; the exported cookies are picked up from Downloads and checked;
  - [x] Stremio for `st`: choose with / without Real-Debrid first, then account, Real-Debrid, Stremio Account Bootstrapper (preset standard / http-only), AIOMetadata, each checked on the account;
  - [x] header logo: drawing editor (mouse paints / erases, block letters from text, palettes); the header's columns move right for a wider logo;
  - [x] sudo (Windows 11 setting, inline / gsudo on Windows 10);
  - [x] WSL (optional): install WSL + Ubuntu, create the Linux user, then zsh + tools and guarded lines in `.bashrc` / `.zshrc` (outside SuperTerminal WSL stays as it was).
- [x] **Draw your own ASCII art** (Kev's request): an editor in the terminal to draw the header logo (grid with mouse/keys, colours from the theme, preview in the header), saved to the per-person config. Also importing an image (chafa) or text (figlet-style).
- [x] **Change keybinds** (Kev's request): `setup keys` lists the terminal's shortcuts; a new one is set by pressing it (WezTerm lets go of every key while the editor waits), conflicts are refused; saved to `~\.config\superterminal\keys.json`, read by `wezterm.lua`. Still to do: PSReadLine and yt/st keys.

## Extras (Kev's request)
- [x] **Command palette** (Ctrl+P): commands, apps, recent folders (zoxide), PCs and setup steps in WezTerm's fuzzy selector; enter runs it in the shell. Inside micro / hx / lazygit Ctrl+P stays theirs.
- [x] **Themes**: `theme` (One Dark, Catppuccin Mocha, Tokyo Night) writes `~\.config\superterminal\theme.json`; WezTerm, header, fzf, bat, micro, helix, yt, st, setup and F1 follow it.
- [x] **System monitor**: `monitor` shows CPU, GPU, RAM, temperature and the top processes of this PC and every named PC (over ssh), side by side.
- [x] **Header widgets**: `setup widgets` turns on weather, next calendar event (iCal link, simple events only), now playing (Spotify / mpv) and backup status, in a "today" section of the header.

## UI pass (Kev's request)- [ ] **yt, st, view and the terminal itself**: one visual language (spacing, cards, status bars, skeletons, icons, One Dark colours), the same keys in all of them, the help on `?` in the same format, and loading and error states.
- [ ] Rename `kvn-*` (files, env vars like `KVN_CMD`) to `st-*`/`SUPERTERMINAL_*`. (Careful: `st` is already the Stremio command.)

## Phase 2: clean up what works badly
Known rough edges, from use:
- [ ] **pin**: two panes kept in sync through files in `%TEMP%` and fake keypresses (`keybd_event` for zoom, `move-focus` for focus). Fragile with splits, resizes and Ctrl+D. Look for a simpler model (or a single pane with a redraw on resize).
- [ ] **Startup time**: measure each module; cache what can be cached (zoxide init is already cached).
- [ ] **Folder menu (Ctrl+Space)**: hand-drawn with absolute ANSI positioning; check icon widths and resizes.
- [ ] **WSL parity**: the zsh side repeats PowerShell logic (prompt, menu, fetch). Decide what really has to be the same.
- [ ] **yt / st**: big scripts (thumbnails in sixel, mpv IPC); add a smoke test for each.
- [ ] **Tests**: turn `tests/` into a `tests/run.ps1` that runs the parser check plus the key scenarios (Tab, Ctrl+Space, cd, rm -rf, repo) and fails loudly.
- [ ] Everything a Claude process installs under `%APPDATA%` is virtualized (MSIX): the installer must not depend on that.
