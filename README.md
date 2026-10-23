# SuperTerminal

A complete terminal environment for Windows: PowerShell 7 + Windows Terminal, with the same Linux commands as in WSL, a live system header, folder menus, its own TUIs (YouTube, Stremio, viewer), editors with IntelliSense, and sync between your PCs over Tailscale.

> **State:** phase 1 in progress. See [ROADMAP.md](ROADMAP.md).

> Based on [kevgoncalves/SuperTerminal](https://github.com/kevgoncalves/SuperTerminal), with extras: TorBox in `st`, `setup prompt` (your own prompt text and colours), colour gradients for the header logo, `super doctor`, more programs (`spotify`, `cloud`, `calc`, `share`, `pcping`, `speedtest`, `trip`, `ouch`, `xh`, `pastel`, `gh`, `hyperfine`, `super upgrade --all`), SSH firewall limited to Tailscale and the local network, and `tests/run.ps1` on every push.

## Install

In PowerShell, on a clean Windows 10 / 11 (nothing needed beforehand, not even git):

```powershell
irm https://raw.githubusercontent.com/guivxavier/super-terminal-edit/main/get.ps1 | iex
```

Or by hand:

1. Get this folder on the PC (Code > Download ZIP, or clone it).
2. Double click `install.cmd` (or `powershell -ExecutionPolicy Bypass -File install.ps1`). It installs the programs with winget, downloads WezTerm, puts the config files in place (backing up anything that was there) and adds SuperTerminal to the Start menu and Ctrl+Alt+T.
3. Open SuperTerminal: the setup opens by itself the first time (font, Tailscale and ssh, YouTube, Stremio, logo, sudo). `setup` opens it again later.

Everything only loads inside the SuperTerminal window: VS Code, Windows Terminal and other PowerShell / WSL windows stay as they were.

## What is in it

| | |
|---|---|
| **Header** | fastfetch + commands box + Tailscale status; `pin` keeps it in its own pane on top |
| **Linux commands** | uutils coreutils + grep/sed/awk from Git: `rm -rf`, `cp -r`, `mkdir -p`... same as WSL |
| **Navigation** | `cd` with a folder menu (Ctrl+Space), Tab like VS Code, zoxide, `ls` with icons |
| **Git** | prompt with branch/state, completion of branches and subcommands, `repo` (read-only dashboard), `lg` (lazygit) |
| **Editors** | `micro` (simple, `nano` opens it), `hx` (helix, with pylsp and clangd) |
| **Apps** | `yt` (YouTube in the terminal, mpv), `st` (Stremio), `view` (markdown + mermaid, pdf, images) |
| **Between PCs** | `ssh <pc>`, `get` / `send` / `rls`, `wake` / `suspend`, config `sync` over git |
| **Your own commands** | `mkcmd <name>` creates a command with flags; F1 shows everything |

## Layout

```
shell/     profile.ps1 (the PowerShell profile), help.ps1 (F1)
apps/      yt, st, view
system/    background tasks (Windows Terminal keepalive, home tidy, Tailscale cache)
config/    mpv, micro, helix, lazygit, fastfetch, Windows Terminal
wsl/       zshrc (the same experience in WSL)
tests/     test harnesses (real keys in a hidden console, zsh in tmux, parser check)
docs/      notes
```

On the PCs today the files live in `~\.config\...` and `Documents\PowerShell\` (paths are hardcoded). Phase 1 makes the repo the source and the installer creates the links.
