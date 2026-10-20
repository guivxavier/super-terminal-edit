#!/usr/bin/env bash
# Prepara o WSL para o SuperTerminal (corre-o o setup > WSL; so o sudo do apt pede palavra-passe)
#   - fastfetch, zoxide, eza, bat em ~/.local/bin (releases oficiais)
#   - config do fastfetch derivada da do Windows desta maquina
#   - zsh: plugins, linhas protegidas no .bashrc/.zshrc (fora do SuperTerminal nada muda)
set -e
WINHOME=$(cd /mnt/c && wslpath "$(/mnt/c/Windows/System32/cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')")
CFG="$WINHOME/.config/wsl"
BIN="$HOME/.local/bin"; mkdir -p "$BIN"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
echo "WINHOME=$WINHOME"

asset() {  # repo regex -> url do asset do ultimo release
    curl -fsSL "https://api.github.com/repos/$1/releases/latest" | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4 | grep -E "$2" | head -1
}
get() {  # repo regex nome-do-binario
    # ja instalado e a funcionar? (um ficheiro errado, ex. script de completacao, falha o --version)
    head -c4 "$BIN/$3" 2>/dev/null | grep -q ELF && "$BIN/$3" --version >/dev/null 2>&1 && { echo "$3 ja existe"; return; }
    curl -fsSL "$(asset "$1" "$2")" -o "$TMP/a.tgz"
    mkdir -p "$TMP/x" && tar -xzf "$TMP/a.tgz" -C "$TMP/x"
    # o arquivo pode trazer outros ficheiros com o mesmo nome (completacoes): preferir o de */bin/
    local f; f=$(find "$TMP/x" -type f -path "*/bin/$3" | head -1)
    [ -n "$f" ] || f=$(find "$TMP/x" -type f -name "$3" -exec sh -c 'head -c4 "$1" | grep -q ELF' _ {} \; -print | head -1)
    install -m755 "$f" "$BIN/$3"
    rm -rf "$TMP/x" "$TMP/a.tgz"; echo "$3 ok"
}
get fastfetch-cli/fastfetch 'fastfetch-linux-amd64\.tar\.gz$' fastfetch
get ajeetdsouza/zoxide 'x86_64-unknown-linux-musl\.tar\.gz$' zoxide
get eza-community/eza 'eza_x86_64-unknown-linux-musl\.tar\.gz$' eza
get sharkdp/bat 'x86_64-unknown-linux-musl\.tar\.gz$' bat

# config do fastfetch = a do Windows desta maquina, com as linhas do Tailscale a lerem a cache do Windows via cat
mkdir -p "$HOME/.config/fastfetch"
sed -E 's#"shell": "cmd.exe", "param": "/c", "text": "type %LOCALAPPDATA%\\\\pwsh-init-cache\\\\(ts[0-9])\.txt"#"text": "sh '"$CFG"'/ts-line.sh '"$WINHOME"'/AppData/Local/pwsh-init-cache/\1.txt"#' \
    "$WINHOME/.config/fastfetch/config.jsonc" | sed '/comandos/,/teclas/d' > "$HOME/.config/fastfetch/config.jsonc"   # a seccao comandos e do PowerShell
echo "fastfetch config ok"

# zsh (pede a palavra-passe do sudo uma vez) + ferramentas que o kvn.zshrc usa
need=; for p in zsh git fzf ripgrep; do dpkg -s $p >/dev/null 2>&1 || need="$need $p"; done
[ -n "$need" ] && { echo "a instalar:$need (o sudo pede a tua palavra-passe do Linux)"; sudo apt-get update -qq && sudo apt-get install -y -qq $need; }

# bash e zsh: so mudam dentro do SuperTerminal ($SUPERTERMINAL); fora dele o WSL fica como estava
grep -q 'SUPERTERMINAL.*exec zsh' "$HOME/.bashrc" 2>/dev/null || printf '\n# SuperTerminal (so dentro dele)\n[ -t 1 ] && [ -n "$SUPERTERMINAL" ] && command -v zsh >/dev/null && exec zsh\n[ -n "$SUPERTERMINAL" ] && [ -f %s/kvn.bashrc ] && . %s/kvn.bashrc\n' "$CFG" "$CFG" >> "$HOME/.bashrc"
mkdir -p "$HOME/.zsh"
[ -d "$HOME/.zsh/zsh-autosuggestions" ] || git clone -q --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$HOME/.zsh/zsh-autosuggestions"
[ -d "$HOME/.zsh/zsh-syntax-highlighting" ] || git clone -q --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting "$HOME/.zsh/zsh-syntax-highlighting"
grep -q 'kvn.zshrc' "$HOME/.zshrc" 2>/dev/null || printf '\n# SuperTerminal (so dentro dele)\nexport WINHOME=%q\n[[ -n $SUPERTERMINAL ]] && source "$WINHOME/.config/wsl/kvn.zshrc"\n' "$WINHOME" >> "$HOME/.zshrc"
grep -q skip_global_compinit "$HOME/.zshenv" 2>/dev/null || echo 'skip_global_compinit=1   # o kvn.zshrc faz compinit -C (rapido)' >> "$HOME/.zshenv"
echo "setup ok"
