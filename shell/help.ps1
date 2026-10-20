# Ajuda do terminal (F1): lista dos comandos por grupo no fzf, com a documentacao de cada um ao lado
# (como usar, variantes, teclas, notas). Enter escreve o comando no prompt. Carregado so quando se carrega no F1.
#   Cada entrada: g = grupo, c = comando, s = resumo, use = @(@('forma', 'o que faz'), ...), kb = teclas, notes, ins = texto a inserir
. "$HOME\.config\st-theme.ps1"   # cores do tema ($StTheme)
$KvnHelp = @(
    # ---- media ----
    @{ g = 'media'; c = 'yt'; s = 'YouTube in the terminal'; ins = 'yt '
        use = @(@('yt', 'home feed (asks you to sign in the first time)'), @('yt <search>', 'search YouTube'), @('yt -a <search>', 'audio only (music): plays the results one after another'))
        kb = @(@('arrows', 'move in the grid'), @('enter', 'play the selected video'), @('1 2 3 4', 'home / subscriptions / watch later / history'), @('/  s  ctrl+f', 'search'), @('r', 'reload'), @('l', 'sign in again'), @('?', 'all shortcuts'), @('esc  q', 'back / quit'))
        notes = @('while a video plays: space pause, arrows seek 5 s, f fullscreen, m mute, 9 0 volume, up/down pick in "up next"', 'click the video to pause; at the end: enter next, r watch again, c cancel autoplay', 'takes the whole window while it is open') }
    @{ g = 'media'; c = 'st'; s = 'movies and series (Stremio addons + Real-Debrid)'; ins = 'st '
        use = @(@('st', 'explore: trending movies'), @('st <search>', 'search movies and series'))
        kb = @(@('t', 'type: movies / series / all'), @('g', 'genre'), @('o', 'sort'), @('f', 'favorite on / off'), @('tab  1 2', 'explore / favorites'), @('enter', 'title page: episodes and streams'), @('l', 'stream language filter (on the streams list)'), @('esc  q', 'back / quit'))
        notes = @('only streams cached on Real-Debrid open instantly (yellow lightning)', 'progress is saved locally: reopening resumes where you stopped') }
    @{ g = 'media'; c = 'view'; s = 'show a file nicely: markdown, pdf, images, code'; ins = 'view '
        use = @(@('view <file.md>', 'markdown with colors; mermaid diagrams drawn as images'), @('view <file.pdf>', 'pages as images: arrows / pgup pgdn / home end, q quits'), @('view <image>', 'shows the image'), @('view <other>', 'code / text with colors and line numbers (bat)'))
        notes = @('from WSL, a pdf opens in a new tab (it needs the keyboard)') }
    # ---- pcs ----
    @{ g = 'pcs'; c = 'ssh'; s = 'open a shell on another of your PCs'; ins = 'ssh '
        use = @(@('ssh <pc>', 'the name you gave it in setup > Tailscale (its Tailscale name works too)'), @('ssh <anything else>', 'the normal ssh'))
        notes = @('checks first: same PC, PC off (wake <pc>), SSH server off, key not copied', 'ctrl+w leaves the session', 'names, SSH server and keys: setup > Tailscale') }
    @{ g = 'pcs'; c = 'get'; s = 'copy a file / folder FROM the other PC'; ins = 'get '
        use = @(@('get <path>', 'to your Downloads (path on the other PC; tab completes it)'), @('get <path> <dest>', 'to <dest>'))
        notes = @('relative paths start in the other PC''s home: get Downloads\x.zip', 'progress bar; folders go whole') }
    @{ g = 'pcs'; c = 'send'; s = 'copy a file / folder TO the other PC'; ins = 'send '
        use = @(@('send <path>', 'to the other PC''s Downloads'), @('send <path> <dest>', 'to <dest> on the other PC')) }
    @{ g = 'pcs'; c = 'rls'; s = 'list a folder of the other PC (like ls)'; ins = 'rls '
        use = @(@('rls', 'the other PC''s home'), @('rls <folder>', 'that folder (tab completes)'), @('rls -a', 'include hidden files')) }
    @{ g = 'pcs'; c = 'super'; s = 'SuperTerminal itself: upgrade, sync your PCs, status'; ins = 'super '
        use = @(@('super upgrade', 'the latest version from GitHub, on this PC'), @('super sync', 'this PC''s version to your other PCs (they apply it)'), @('super status', 'this PC and the others compared with GitHub; changes nothing'))
        notes = @('only when you run it: nothing updates by itself', 'the other PCs: the ones named in setup > Tailscale and online; they get the version over ssh (no GitHub needed there)', 'yours stays: cookies, accounts, PC names, the header logo, and any file you changed on this PC (the new one is saved next to it as .new)') }
    @{ g = 'pcs'; c = 'wake'; s = 'wake another PC (Wake-on-LAN)'; ins = 'wake'
        use = @(@('wake', 'wakes your other PC and waits until it answers'), @('wake <pc>', 'that one'))
        notes = @('only on the same network as that PC', 'needs its MAC: "mac" for it in ~\.config\superterminal\pcs.json') }
    @{ g = 'pcs'; c = 'suspend'; s = 'put another PC (or this one) to sleep'; ins = 'suspend'
        use = @(@('suspend', 'suspends your other PC'), @('suspend <pc>', 'that one; this PC''s own name suspends this PC')) }
    # ---- files ----
    @{ g = 'files'; c = 'ls'; s = 'list a folder (icons, sizes, dates)'; ins = 'ls '
        use = @(@('ls', 'this folder'), @('ls <folder>', 'another folder'), @('ls -a', 'include hidden files'), @('la', 'everything with eza'), @('ll', 'details with eza (+ git status)'), @('lt', 'tree, 2 levels')) }
    @{ g = 'files'; c = 'cd'; s = 'change folder'; ins = 'cd '
        use = @(@('cd <folder>', 'go to the folder'), @('cd', 'home'), @('cd ..', 'up one'), @('cd -', 'back to the previous folder'), @('cd C:\full\path', 'any path'))
        kb = @(@('tab', 'complete the folder name (again = next one)'), @('ctrl+space', 'folder menu: tab goes in, typing filters, enter goes'), @('ctrl+backspace', 'remove the last folder of the path')) }
    @{ g = 'files'; c = 'z'; s = 'jump to a folder you have used before'; ins = 'z '
        use = @(@('z <part of name>', 'best match: z uni -> Trabalhos Uni'), @('z <a> <b>', 'several words: z kiln src'), @('zi <name>', 'choose from a list')) }
    @{ g = 'files'; c = 'fetch'; s = 'search text inside files'; ins = 'fetch '
        use = @(@('fetch <text>', 'in this folder and below'), @('fetch <text> <folder>', 'in another folder'))
        kb = @(@('type', 'filter the results'), @('enter', 'opens the file in VS Code at that line'))
        notes = @('capitals only matter if the text has capitals') }
    @{ g = 'files'; c = 'unzip'; s = 'extract an archive (zip, 7z, rar, tar.gz...)'; ins = 'unzip '
        use = @(@('unzip <file>', 'into a folder with the archive''s name, next to it'), @('unzip <file> <folder>', 'into <folder>'))
        notes = @('if the archive already has one folder inside, it does not nest another one') }
    @{ g = 'files'; c = 'zip'; s = 'make a .zip'; ins = 'zip '
        use = @(@('zip <folder>', '<folder>.zip next to it'), @('zip <a> <b> <c>', 'several files / folders in one zip'), @('zip <x> -o <name>.zip', 'choose the name')) }
    @{ g = 'files'; c = 'ex'; s = 'open in Windows'; ins = 'ex'
        use = @(@('ex', 'this folder in Explorer'), @('ex <folder>', 'that folder'), @('ex <file>', 'opens the file with its usual app')) }
    @{ g = 'files'; c = 'linux'; s = 'real Linux commands, same as in WSL'; ins = 'rm '
        use = @(@('rm -rf <folder>', 'delete (also read-only files, e.g. a git repo)'), @('cp -r <a> <b>  /  mv <a> <b>', 'copy / move'), @('mkdir -p a/b/c  /  touch <file>', 'folders / empty file'), @('head  tail  wc  sort  uniq  cut  tr  du  df', 'text and disk'), @('grep  sed  awk  find  less  diff  xargs', 'from Git'), @('ls -la', 'with flags: the real ls (no flags: our ls)'))
        notes = @('uutils coreutils (winget uutils.coreutils) + Git usr\bin', 'PowerShell cmdlets keep their full names: Remove-Item, Copy-Item, Sort-Object...') }
    @{ g = 'files'; c = 'y'; s = 'file manager (yazi)'; ins = 'y'
        use = @(@('y', 'opens here; when you leave, the terminal stays in the folder you were in'), @('y <folder>', 'opens there')) }
    @{ g = 'files'; c = 'cpwd'; s = 'copy the current folder''s path'; ins = 'cpwd'
        use = @(@('cpwd', 'copies the path to the clipboard (also over ssh)')) }
    @{ g = 'files'; c = 'dust'; s = 'what takes space on the disk'; ins = 'dust '
        use = @(@('dust', 'this folder'), @('dust <folder>', 'another one'), @('dust -d 1', 'only one level')) }
    # ---- apps ----
    @{ g = 'apps'; c = 'app'; s = 'open your apps by name'; ins = 'app '
        use = @(@('app', 'pick from a list'), @('app <name>', 'open it (tab completes)'), @('app add', 'pick a program in a window'), @('app add <name> <path>', 'add with a path or shell:AppsFolder\<id>'), @('app ren <a> <b>', 'rename'), @('app rm <name>', 'remove'), @('app list', 'list all'))
        notes = @('Store / MSIX apps: app add <name> shell:AppsFolder\<AppID> (Get-StartApps <name> shows the id)') }
    # ---- shell ----
    @{ g = 'shell'; c = 'mkcmd'; s = 'make your own command, with flags'; ins = 'mkcmd '
        use = @(@('mkcmd <name>', 'asks what it does, its flags and the command to run (empty = write the code in micro)'), @('mkcmd -e <name>', 'edit it in micro'), @('mkcmd -rm <name>', 'delete it'), @('mkcmd -l', 'list yours'))
        notes = @('checks first if the name already exists (profile command, PowerShell, alias or program)', 'flags: -force, a short letter (-f), or with a value (-out x)', 'saved in ~\.config\cmds, synced to the other PC, shown here under "mine"') }
    @{ g = 'files'; c = 'micro'; s = 'text editor (nano opens it too)'; ins = 'micro '
        use = @(@('micro <file>', 'open / create'), @('micro a b', 'several files in tabs'))
        kb = @(@('ctrl+s', 'save'), @('ctrl+w', 'quit (ctrl+q switches tabs in the terminal)'), @('ctrl+c  ctrl+x  ctrl+v', 'copy / cut / paste'), @('ctrl+z  ctrl+y', 'undo / redo'), @('ctrl+f  ctrl+n', 'find / next'), @('ctrl+g', 'all shortcuts'), @('ctrl+p', 'command bar (e.g. "replace a b")'), @('alt+/', 'comment the line'), @('ctrl+d', 'extra cursor on the next match'), @('mouse', 'click, select, scroll'))
        notes = @('also the editor for git and lazygit (EDITOR=micro)', 'same editor and settings in WSL') }
    @{ g = 'files'; c = 'hx'; s = 'code editor with IntelliSense (helix)'; ins = 'hx '
        use = @(@('hx <file>', 'open / create'), @('hx .', 'file picker of this folder'), @('hx --health python', 'what is set up for a language'))
        kb = @(@('i  a', 'start typing (insert) before / after'), @('esc', 'back to normal mode (moving, commands)'), @('ctrl+s  :w', 'save'), @(':q  :q!', 'quit / quit without saving'), @('ctrl+space', 'suggestions (they also appear on their own)'), @('space k', 'docs / type of what is under the cursor'), @('g d', 'go to definition (ctrl+o back)'), @('space a', 'quick fixes'), @('space r', 'rename everywhere'), @('space f', 'open file'), @('space ?', 'search every command'), @('u  U', 'undo / redo'), @('/', 'find'))
        notes = @('modal like vim: keys move and edit in normal mode, type in insert mode', 'IntelliSense: Python (pylsp) and C/C++ (clangd); also in WSL', 'config: ~\.config\helix (onedark, mouse on)') }
    @{ g = 'shell'; c = 'setup'; s = 'set up accounts and choices: font, Tailscale, YouTube, Stremio, logo, sudo'; ins = 'setup'
        use = @(@('setup', 'all the steps and how each one stands'), @('setup <step>', 'straight to one: font, tailscale, youtube, stremio, logo, sudo'))
        kb = @(@('up / down  1-6', 'choose a step'), @('enter', 'set it up (or again)'), @('q  esc', 'done'))
        notes = @('opens by itself the first time the terminal starts', 'stremio: sign in, AIOMetadata, and streams with or without Real-Debrid', 'logo: block letters from text, or draw / paste your own in the editor') }
    @{ g = 'shell'; c = 'ff'; s = 'clear the shell / redraw the header'; ins = 'ff'
        use = @(@('ff', 'clear the shell (clear and ctrl+l do the same)'), @('reset', 'like on Linux: fixes a terminal left broken by an app (colours, cursor, mouse) and clears'), @('ffw', 'header live (every 2 s) on / off'))
        notes = @('the header lives in the top pane and redraws itself (live is the default)') }
    @{ g = 'pcs'; c = 'monitor'; s = 'CPU, GPU, RAM, temperature and processes of your PCs, side by side'; ins = 'monitor'
        use = @(@('monitor', 'this PC and every PC named in setup > Tailscale (over ssh), every 2 s'))
        notes = @('a PC that says "not updated there yet" needs super sync first', 'temperature: only where Windows exposes it (not every PC does)') }
    @{ g = 'shell'; c = 'theme'; s = 'change the colours of everything at once'; ins = 'theme'
        use = @(@('theme', 'pick one (with a preview of the colours)'), @('theme one-dark', 'One Dark (the default)'), @('theme catppuccin', 'Catppuccin Mocha'), @('theme tokyo-night', 'Tokyo Night'))
        notes = @('terminal, header, fzf, bat, micro and helix change now; yt / st / setup on their next start') }
    @{ g = 'shell'; c = 'pin'; s = 'header pane on top, on / off'; ins = 'pin'
        use = @(@('pin', 'on / off (on by default in new tabs)'))
        notes = @('the top pane is view-only; pin stays on: ctrl+d splits the shell below, the header closes only when every shell below is closed', 'yt / st / lg / hx / micro / F1 take the whole window while open') }
    @{ g = 'shell'; c = 'k'; s = 'end a program'; ins = 'k'
        use = @(@('k', 'programs by memory use; type to filter, enter asks before ending'), @('k <name>', 'starts filtered')) }
    @{ g = 'shell'; c = 'repo'; s = 'everything about a git repo, just to look'; ins = 'repo'
        use = @(@('repo', 'the repo of this folder'), @('repo <folder>', 'another one'))
        notes = @('branch and remote (to push / pull), changes, branches, history graph, people, file types', 'only reads: changes nothing and does not fetch (lg is for acting)') }
    @{ g = 'shell'; c = 'lg'; s = 'lazygit (git with a UI)'; ins = 'lg'
        use = @(@('lg', 'in the current repository')) }
    @{ g = 'shell'; c = 'jq'; s = 'read and filter JSON'; ins = 'jq '
        use = @(@('jq . <file.json>', 'pretty-print with colors'), @('jq .key <file.json>', 'one field'), @('<command> | jq .', 'JSON from another command'))
        notes = @('e.g. Get-Content $HOME\.config\apps.json | jq .') }
    @{ g = 'shell'; c = 'tldr'; s = 'short examples of a command'; ins = 'tldr '
        use = @(@('tldr <command>', 'e.g. tldr tar, tldr git-rebase')) }
    @{ g = 'shell'; c = 'wsl'; s = 'Linux (zsh)'; ins = 'wsl'
        use = @(@('wsl', 'opens zsh in this folder'), @('exit', 'back to Windows'))
        notes = @('inside: ~ws ~desk ~dl ~win go to Windows folders; cd ''C:\...'' works; get / send / rls / yt / st / view too') }
    # ---- keys ----
    @{ g = 'keys'; c = 'keys'; s = 'keyboard shortcuts'; ins = ''
        use = @(@('ctrl+alt+t', 'show / hide the terminal from anywhere'), @('ctrl+p', 'command palette: commands, apps, recent folders, PCs, setup'), @('ctrl+t', 'new tab'), @('ctrl+q  ctrl+e', 'previous / next tab'), @('ctrl+1..9', 'go to that tab'), @('ctrl+d', 'split (side by side)'), @('ctrl+arrows', 'move between panes'), @('ctrl+shift+z', 'zoom the pane (whole window)'), @('ctrl+w', 'close the pane (the last one just hides; inside ssh: leave the other PC)'), @('f11  ctrl+b', 'full screen / window'), @('ctrl+c', 'copy the selection (no selection: stop the command)'), @('ctrl+v', 'paste'), @('ctrl+shift+f', 'search the scrollback'), @('ctrl+l', 'clear'), @('ctrl+r', 'search history'), @('tab', 'complete with the 1st option; tab again: list of all, then each tab picks the next'), @('shift+tab', 'previous option'), @('ctrl+space', 'list of options (folder menu on cd / ls / y)'), @('ctrl+backspace', 'delete a word (on cd: a folder)'), @('f1', 'this help'), @('setup keys', 'change these shortcuts')) }
    @{ g = 'keys'; c = 'prompt'; s = 'what the prompt shows'; ins = ''
        use = @(@('<pc> D:\', 'you are on another PC''s shared drive (its name from setup > Tailscale)'), @('main* ↑2 ↓1', 'git: branch, * unsaved changes, commits to push / pull'), @('✘ 3', 'the last command failed (exit code)'), @('12s', 'how long the last command took (if 2 s or more)'))
        notes = @('commands that take 30 s or more show a Windows notification if the terminal is not in front') }
)

function Show-KvnHelp {
    # escreve a documentacao de cada comando num ficheiro (a pre-visualizacao do fzf so faz "type") e abre a lista
    $e = [char]27; $dir = "$env:TEMP\kvn-help"; New-Item -ItemType Directory $dir -Force | Out-Null
    $gc = @{ media = '31'; pcs = '34'; files = '32'; apps = '33'; shell = '35'; keys = '37'; mine = '36' }
    $gi = @{ media = [char]0xf144; pcs = [char]0xf108; files = [char]0xf07b; apps = [char]0xf00a; shell = [char]0xf120; keys = [char]0xf11c; mine = [char]0xf007 }
    # os teus comandos (mkcmd): resumo = 1.a linha do ficheiro, flags = o param() (o comentario a frente de cada uma)
    $mine = foreach ($c in Get-ChildItem "$HOME\.config\cmds\*.ps1" -ErrorAction Ignore) {
        $src = Get-Content $c.FullName
        $fn = [Management.Automation.Language.Parser]::ParseFile($c.FullName, [ref]$null, [ref]$null).Find({ $args[0] -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)
        $use = @(foreach ($pa in @($fn.Body.ParamBlock.Parameters)) {
            $nm = $pa.Name.VariablePath.UserPath
            $al = @($pa.Attributes | Where-Object { $_.TypeName.Name -eq 'Alias' } | ForEach-Object { $_.PositionalArguments.Value })
            $pos = @($pa.Attributes | Where-Object { $_.TypeName.Name -eq 'Parameter' -and $_.NamedArguments.ArgumentName -contains 'Position' }).Count
            $note = if ($src[$pa.Extent.EndLineNumber - 1] -match '#\s*(.+)$') { $Matches[1] } else { '' }
            if ($pos) { , @("$($c.BaseName) <$($nm.ToLower())>", $note) }
            else { , @(("-$($nm.ToLower())" + $(if ($al) { "  -$($al -join '  -')" }) + $(if ($pa.StaticType -ne [switch]) { ' <value>' })), $note) }
        })
        if (-not $use) { $use = @(, @($c.BaseName, 'run it')) }
        @{ g = 'mine'; c = $c.BaseName; s = (($src | Select-Object -First 1) -replace '^#\s*'); ins = "$($c.BaseName) "; use = $use
            notes = @("file: ~\.config\cmds\$($c.Name)", "change it: mkcmd -e $($c.BaseName)  ·  delete: mkcmd -rm $($c.BaseName)") }
    }
    $all = @($mine) + @($KvnHelp)
    # teclas como na barra de baixo do WezTerm: cada uma num "chip" ("ctrl+t", "1 2 3 4" -> um chip por tecla)
    $chips = { param($k) ($k -split '  ' | Where-Object { $_ } | ForEach-Object { "$e[48;2;$($StTheme.sel);97m $_ $e[0m" }) -join ' ' }
    $lines = foreach ($d in $all) {
        $id = $d.c; $col = $gc[$d.g]
        # pre-visualizacao: titulo grande com o icone do grupo, resumo, e as seccoes; os exemplos de uso num cartao
        $o = @('', " $e[${col}m$($gi[$d.g])  $e[1;97m$($d.c)$e[0m", " $e[37m$($d.s)$e[0m", " $e[90m" + ([string][char]0x2500 * 60) + "$e[0m")
        if ($d.use) {
            $use = if ($d.use[0] -is [string]) { , $d.use } else { $d.use }   # (uma so linha: @(@(a, b)) desfaz-se em a, b)
            $w = [Math]::Min(28, (($use | ForEach-Object { "$(if ($_ -is [string]) { $_ } else { $_[0] })".Length }) | Measure-Object -Maximum).Maximum + 2)
            $o += '', " $e[1;${col}mUSAGE$e[0m"
            $bg = "$e[48;2;$($StTheme.dark)m"
            $o += " $bg" + (' ' * 62) + "$e[0m"
            foreach ($u in $use) { if ($u -is [string]) { $u = $u, '' }; $o += " $bg  $e[36m$("$($u[0])".PadRight($w))$e[37m$("$($u[1])".PadRight([Math]::Max(0, 60 - $w)))$e[0m" }
            $o += " $bg" + (' ' * 62) + "$e[0m"
        }
        if ($d.kb) {
            $kb = if ($d.kb[0] -is [string]) { , $d.kb } else { $d.kb }
            $o += '', " $e[1;${col}mKEYS$e[0m"
            foreach ($u in $kb) { $o += "   $(& $chips $u[0])  $e[37m$($u[1])$e[0m" }
        }
        if ($d.notes) { $o += '', " $e[1;${col}mNOTES$e[0m"; foreach ($n in $d.notes) { $o += "   $e[90m$([char]0x2022)$e[0m $n" } }
        if ($d.ins) { $o += '', " $e[90menter: put on the prompt   ctrl+o: run now   ctrl+y: copy$e[0m" }
        [IO.File]::WriteAllLines("$dir\$id.txt", [string[]]$o, [Text.UTF8Encoding]::new($false))
        # (4.o campo, escondido: o texto todo da ajuda, para a pesquisa encontrar "pdf" no view, "musica" no yt -a...)
        $find = (@($d.s) + @($d.use | ForEach-Object { $_ }) + @($d.kb | ForEach-Object { $_ }) + @($d.notes)) -join ' '
        "$e[${col}m$($gi[$d.g])  $($d.g.PadRight(6))$e[0m $e[1;97m$($d.c.PadRight(9))$e[0;90m$($d.s)$e[0m`t$id`t$dir\$id.txt`t$find"
    }
    $pick = @($lines | fzf --ansi --layout reverse --delimiter "`t" --with-nth 1 --nth '1,4' --no-sort --prompt "  $([char]0xf002)  " `
        --border rounded --border-label " $([char]0xf120)  SuperTerminal $([char]0x00B7) help " --border-label-pos 3 `
        --info inline-right --pointer ([char]0x258C) `
        --expect 'ctrl-o,ctrl-y' --with-shell 'cmd.exe /v:on /s /c' --preview "set f={3}& type !f:'=!" `
        --preview-window 'right,60%,wrap,border-rounded' --preview-label ' details ' 2>$null)   # (cores: FZF_DEFAULT_OPTS do perfil, One Dark)
    if ($pick.Count -lt 2 -or -not $pick[1]) { return $null }
    $id = ($pick[1] -split "`t")[1]
    $ins = ($all | Where-Object c -eq $id | Select-Object -First 1).ins
    # --expect: 1.a linha = a tecla (vazia = enter). ctrl+o corre ja, ctrl+y copia (o F1 trata do prefixo)
    if ($ins -and $pick[0] -eq 'ctrl-o') { "!run:$ins" } elseif ($ins -and $pick[0] -eq 'ctrl-y') { Set-Clipboard $ins.Trim(); $null } else { $ins }
}
