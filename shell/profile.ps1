# Sessoes so-de-comando (pwsh -c / -File, ex.: ssh host 'cmd') nao precisam do perfil
# (KVN_CMD=1: modo so-comandos, usado pelo zsh do WSL para correr yt/st/get/send/rls/ssh/wake... deste perfil)
if (-not $env:KVN_CMD -and [Environment]::GetCommandLineArgs() -match '^-(c|command|ec|encodedcommand|f|file)$') { return }
# So dentro do SuperTerminal: o WezTerm marca as sessoes dele com SUPERTERMINAL=1 (passa tambem para o WSL e para o
# ssh de um PC para o outro). Fora dele (VS Code, Windows Terminal, pwsh solto) o PowerShell fica como de origem
if (-not $env:SUPERTERMINAL -and -not $env:KVN_CMD) { return }
# git com o delta (diffs com cores e numeros de linha) so aqui: pelo ambiente, nao no ~\.gitconfig (que o VS Code e os
# outros terminais tambem leem)
$env:GIT_CONFIG_COUNT = '6'
$env:GIT_CONFIG_KEY_0 = 'core.pager'; $env:GIT_CONFIG_VALUE_0 = 'delta'
$env:GIT_CONFIG_KEY_1 = 'interactive.diffFilter'; $env:GIT_CONFIG_VALUE_1 = 'delta --color-only'
$env:GIT_CONFIG_KEY_2 = 'delta.navigate'; $env:GIT_CONFIG_VALUE_2 = 'true'
$env:GIT_CONFIG_KEY_3 = 'delta.line-numbers'; $env:GIT_CONFIG_VALUE_3 = 'true'
$env:GIT_CONFIG_KEY_4 = 'delta.syntax-theme'; $env:GIT_CONFIG_VALUE_4 = 'OneHalfDark'
$env:GIT_CONFIG_KEY_5 = 'merge.conflictStyle'; $env:GIT_CONFIG_VALUE_5 = 'zdiff3'

[Console]::OutputEncoding = [Text.Encoding]::UTF8   # simbolos/caixas corretos (ex.: via SSH)
# SSH_AUTH_SOCK para um agent do WezTerm que ja nao existe: sem ela, o ssh usa o ssh-agent do Windows (onde esta a chave)
if ($env:SSH_AUTH_SOCK -like '*wezterm*' -and -not (Test-Path $env:SSH_AUTH_SOCK)) { Remove-Item Env:SSH_AUTH_SOCK }

if (Test-Path "$HOME\.bun\bin\bun.exe") { function claude-mem { & "$HOME\.bun\bin\bun.exe" "$HOME\.claude\plugins\marketplaces\thedotmack\plugin\scripts\worker-service.cjs" $args } }   # (so no laptop; o perfil e igual nos dois PCs)

# Prompt nativo (substitui o Starship: sem .exe externo -> paineis/abas abrem ~200 ms mais rapido)
#   [ssh] [admin] kvn@host [servidor de rede] pasta [branch git] [duracao]
$PromptHost = [Environment]::MachineName.ToLower()
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# os teus PCs (setup > Tailscale): ~\.config\superterminal\pcs.json = [{ name, host, user, shell, ip, mac }]
#   name = o do ssh (ssh desktop), host = o nome no Tailscale, shell = o do ssh de la (pwsh / cmd), ip = o do Tailscale
#   (o prompt mostra o PC nas pastas de rede \\<ip>\...), mac = para o wake. Nada disto fica no codigo
$PcsFile = "$HOME\.config\superterminal\pcs.json"
$Pcs = @(if (Test-Path $PcsFile) { try { Get-Content $PcsFile -Raw | ConvertFrom-Json } catch {} })
$NetHostNames = @{}; foreach ($pc in $Pcs) { if ($pc.ip) { $NetHostNames[$pc.ip] = $pc.host } }
$PwshExe = 'C:\Program Files\PowerShell\7\pwsh.exe'   # (pwsh 7 MSI nos dois PCs; usado para lancar processos escondidos)
# tema One Dark em todo o lado (o mesmo do Windows Terminal): fzf (Ctrl+R, F1, k, fetch, app...) e bat (cat, view, fetch)
$env:FZF_DEFAULT_OPTS = '--color=fg:#abb2bf,bg:-1,hl:#61afef,fg+:#ffffff,bg+:#3e4451,hl+:#61afef,info:#98c379,prompt:#56b6c2,pointer:#e06c75,marker:#e5c07b,spinner:#c678dd,header:#5c6370,border:#4b5263,gutter:-1,query:#abb2bf'
$env:BAT_THEME = 'OneHalfDark'
# editor: micro (teclas normais: Ctrl+S guarda, Ctrl+W sai); o git e o lazygit tambem o usam. nano -> micro
$env:EDITOR = $env:VISUAL = 'micro'; $env:MICRO_TRUECOLOR = '1'
function nano { micro @args }
# sudo: o do Windows 11 (Definicoes > Para programadores); no Windows 10 o gsudo faz o mesmo
# (pela versao: procurar o sudo no PATH custava ~15 ms em cada separador; o Windows 10 e build < 22000)
if ([Environment]::OSVersion.Version.Build -lt 22000 -and (Test-Path "$env:ProgramFiles\gsudo\Current\gsudo.exe")) { Set-Alias sudo "$env:ProgramFiles\gsudo\Current\gsudo.exe" }
# language servers do helix (hx): ao FIM do PATH, para o python.exe do venv do pylsp nao passar a frente do Python normal
$env:PATH += ";$HOME\.local\pylsp\Scripts;$HOME\.local\clangd\bin"
$script:LastHistId = 0
function prompt {
    # resultado do ultimo comando: $? tem de ser lido na 1.a linha (por isso o zoxide ja nao envolve este prompt: a rotina
    # dele e chamada no fim). Codigo de saida reposto a 0 para nao ficar "preso" ao comando seguinte.
    $ok = $?; $code = $global:LASTEXITCODE; $global:LASTEXITCODE = 0
    $e = [char]27
    $s = ''
    # WezTerm: diz-lhe a pasta atual (OSC 7: splits e separadores novos abrem aqui; user var cwd: reabrir a sessao)
    if ($env:WEZTERM_PANE -and -not $env:SSH_CONNECTION) {
        $here = $PWD.ProviderPath
        # (escrito a parte, fora do texto do prompt: o PSReadLine contaria estes caracteres na largura do prompt)
        if ($here -notlike '\\*') { [Console]::Write("$e]7;file://$env:COMPUTERNAME/$($here -replace '\\', '/')$e\") }
        [Console]::Write("$e]1337;SetUserVar=cwd=$([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($here)))$([char]7)")
    }
    if ($env:SSH_CONNECTION) { $s += "$e[1;32m`u{f489} ssh " }
    $s += "$e[0;35m$env:USERNAME$e[90m@$e[34m$PromptHost "
    # pasta de rede (drive mapeada ou \\servidor\...)
    $unc = if ($PWD.Drive.DisplayRoot) { $PWD.Drive.DisplayRoot } elseif ($PWD.ProviderPath -like '\\*') { $PWD.ProviderPath }
    if ($unc) { $srv = ($unc -split '\\')[2]; $s += "$e[1;33m`u{f233} $(if ($NetHostNames[$srv]) { $NetHostNames[$srv] } else { $srv }) " }
    $p = $PWD.ProviderPath
    # \\<ip do PC>\d\x -> D:\x (o PC ja aparece antes; partilha de uma letra = disco)
    if ($p -match '^\\\\[^\\]+\\([^\\]+)(.*)$') { $p = $(if ($Matches[1].Length -eq 1) { "$($Matches[1].ToUpper()):" } else { $Matches[1] }) + $(if ($Matches[2]) { $Matches[2] } else { '\' }) }
    # pastas acabam em "\" (C:\x\y\, ~\Documents\); a home fica so "~"
    $shown = if ($p -eq $HOME) { '~' } elseif ($p.StartsWith("$HOME\")) { '~' + $p.Substring($HOME.Length) } else { $p }
    if ($shown -ne '~' -and -not $shown.EndsWith('\')) { $shown += '\' }
    $s += "$e[0;36m$shown "
    # git: branch, * = alteracoes por gravar, ↑n/↓n = commits por enviar/receber (so dentro de um repositorio)
    for ($d = $p; $d; $d = Split-Path $d) {
        if (Test-Path -LiteralPath "$d\.git") {
            $st = @(git -C $d status --porcelain=v2 --branch 2>$null)
            $br = ($st | Where-Object { $_ -like '# branch.head *' }) -replace '^# branch.head ', ''
            if ($br -eq '(detached)') { $br = (($st | Where-Object { $_ -like '# branch.oid *' }) -replace '^# branch.oid ', '').Substring(0, 7) }
            $dirty = [bool]($st | Where-Object { $_ -notlike '#*' } | Select-Object -First 1)
            $ab = ($st | Where-Object { $_ -like '# branch.ab *' }) -replace '^# branch.ab ', ''
            $up = if ($ab -match '\+(\d+) -(\d+)') { "$(if ([int]$Matches[1]) { " $([char]0x2191)$($Matches[1])" })$(if ([int]$Matches[2]) { " $([char]0x2193)$($Matches[2])" })" }
            if ($br) { $s += "$e[90m$br$(if ($dirty) { "$e[33m*" })$e[36m$up " }
            break
        }
    }
    if (Test-Path $SyncFlag) { $s += "$e[33m$([char]0x26A0) sync " }   # o ultimo sync nao conseguiu juntar (ver sync)
    # ultimo comando: falhou (✘ + codigo) e quanto demorou (se >= 2 s); so uma vez, logo a seguir a ele
    $last = Get-History -Count 1
    if ($last -and $last.Id -ne $script:LastHistId) {
        $script:LastHistId = $last.Id
        $failed = -not $ok -or $code -or $last.ExecutionStatus -ne 'Completed'
        $t = $last.EndExecutionTime - $last.StartExecutionTime
        if ($failed) { $s += "$e[31m$([char]0xf00d)$(if ($code) { " $code" }) " }
        if ($t.TotalSeconds -ge 2) { $s += "$e[33m$(if ($t.TotalMinutes -ge 1) { '{0}m{1}s' -f [int][math]::Floor($t.TotalMinutes), $t.Seconds } else { '{0}s' -f [int]$t.TotalSeconds }) " }
        # comando demorado (>= 30 s) acabou com a janela do terminal noutro plano: notificacao do Windows
        if ($t.TotalSeconds -ge 30) { Send-DoneToast $last.CommandLine $t (-not $failed) }
    }
    if (Test-Path Function:__zoxide_hook) { $null = __zoxide_hook }   # (o z aprende a pasta, ver zoxide abaixo)
    $global:LASTEXITCODE = 0   # (o git status deste prompt nao pode contar como o resultado do proximo comando)
    # pasta deste separador, para o reabrir depois de reiniciar (ver "separadores" abaixo); so quando muda
    if ($global:TabFile -and $global:TabSaved -ne $PWD.ProviderPath -and $PWD.Provider.Name -eq 'FileSystem') {
        $global:TabSaved = $PWD.ProviderPath; Set-Content $global:TabFile "$global:TabWt|$($PWD.ProviderPath)" -ErrorAction SilentlyContinue
    }
    "$s$e[0m"
}
function Send-DoneToast([string]$cmd, [TimeSpan]$t, [bool]$ok) {
    # so se o terminal nao estiver a frente (se estas a olhar para ele, nao faz falta)
    if (-not ('Kvn.Fg' -as [type])) {
        Add-Type -Namespace Kvn -Name Fg -MemberDefinition '[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);'
    }
    if ([Kvn.Fg]::GetForegroundWindow() -eq [Kvn.Fg]::GetAncestor([Kvn.Fg]::GetConsoleWindow(), 3)) { return }
    $dur = if ($t.TotalMinutes -ge 1) { '{0}m{1}s' -f [int][math]::Floor($t.TotalMinutes), $t.Seconds } else { '{0}s' -f [int]$t.TotalSeconds }
    $title = if ($ok) { "$([char]0x2713) finished  ·  $dur" } else { "$([char]0x2718) failed  ·  $dur" }
    $body = if ($cmd.Length -gt 90) { $cmd.Substring(0, 89) + [char]0x2026 } else { $cmd }
    $x = { param($s) [Security.SecurityElement]::Escape($s) }
    # notificacao pelo WinRT do Windows PowerShell 5.1 (o pwsh 7 nao o tem), num processo escondido
    $ps = @"
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
`$d = New-Object Windows.Data.Xml.Dom.XmlDocument
`$d.LoadXml('<toast><visual><binding template="ToastGeneric"><text>$(& $x $title)</text><text>$(& $x $body)</text></binding></visual></toast>')
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe').Show([Windows.UI.Notifications.ToastNotification]::new(`$d))
"@
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile', '-EncodedCommand', ([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ps)))
}

# zoxide (init em cache; regenera quando o zoxide e atualizado)
# (procurar o zoxide no PATH custava ~80 ms em cada separador: com a cache feita ha menos de 1 dia, usa-a logo)
$zc = "$env:LOCALAPPDATA\pwsh-init-cache\zoxide.ps1"
$zok = $false
if ((Test-Path $zc) -and ((Get-Date) - (Get-Item $zc).LastWriteTime).TotalDays -lt 1) { try { . $zc; $zok = $true } catch { Remove-Item $zc -ErrorAction SilentlyContinue } }   # (estragada: refaz ja)
if (-not $zok -and ($zx = (Get-Command zoxide -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source)) {
    New-Item -ItemType Directory (Split-Path $zc) -Force | Out-Null
    # (para um temporario e so depois o nome final: com varios shells a abrir ao mesmo tempo, um lia o ficheiro a meio
    # da escrita de outro e o perfil dava "Missing closing '}'")
    $zi = zoxide init powershell | Out-String
    $zt = "$zc.$PID.tmp"; [IO.File]::WriteAllText($zt, $zi, [Text.UTF8Encoding]::new($false)); try { [IO.File]::Move($zt, $zc, $true) } catch { Remove-Item $zt -ErrorAction SilentlyContinue }
    . ([scriptblock]::Create($zi))
}
# o zoxide envolve o prompt (e com isso perde-se o $? do ultimo comando): repoe o nosso; ele chama o __zoxide_hook no fim
if ($global:__zoxide_prompt_old) { $function:global:prompt = $global:__zoxide_prompt_old }
# Ctrl+R: historico no fzf (mais recentes primeiro, sem repetidos); Enter poe o comando na linha para editar/correr
# (sem verificar se o fzf existe: custava ~150 ms a procurar no PATH; esta nos dois PCs)
if (-not [Console]::IsOutputRedirected) {
    Set-PSReadLineKeyHandler -Chord Ctrl+r -ScriptBlock {
        $h = (Get-PSReadLineOption).HistorySavePath
        $line = $null; [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$null)
        $seen = @{}; $items = [Collections.Generic.List[string]]::new()
        $all = [IO.File]::ReadAllLines($h); for ($i = $all.Count - 1; $i -ge 0; $i--) { $c = $all[$i].Trim(); if ($c -and -not $seen[$c]) { $seen[$c] = 1; $items.Add($c) } }
        $pick = $items | fzf --height 40% --reverse --no-sort --prompt 'history> ' --query "$line"
        [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
        if ($pick) { [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine(); [Microsoft.PowerShell.PSConsoleReadLine]::Insert($pick) }
    }
}
# yazi: precisa do file.exe do Git para saber o tipo dos ficheiros; "y" abre e, ao sair, fica na pasta onde estavas no yazi
$env:YAZI_FILE_ONE = 'C:\Program Files\Git\usr\bin\file.exe'
# view <ficheiro>: md (com diagramas mermaid), pdf (paginas navegaveis), imagens, codigo
function view { Clear-FfRegion; & "$HOME\.config\view.ps1" @args }

# ---- ficheiros: unzip / zip / fetch / ex / k ----
# (tar.exe do Windows = bsdtar: le zip, 7z, rar, tar.gz/xz/zst e cria zip; nada para instalar)
$TarExe = "$env:SystemRoot\System32\tar.exe"
function unzip {
    # unzip <arquivo> [pasta]   -> extrai para uma pasta com o nome do arquivo (ao lado dele), ou para [pasta]
    param([Parameter(Mandatory)][string]$Path, [string]$Dest)
    $f = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $f) { Write-Warn "'$Path' doesn't exist"; return }
    $f = $f.ProviderPath
    if (-not $Dest) {
        # se o arquivo ja traz tudo dentro de uma pasta, extrai ao lado dele (sem ficar "x\x\...")
        $tops = @(& $TarExe -tf $f 2>$null | ForEach-Object { ($_ -replace '\\', '/').Split('/')[0] } | Where-Object { $_ } | Select-Object -Unique)
        $Dest = if ($tops.Count -eq 1 -and (& $TarExe -tf $f 2>$null | Select-Object -First 2).Count -gt 1) { Split-Path $f }
                else { Join-Path (Split-Path $f) ([IO.Path]::GetFileName($f) -replace '\.(zip|7z|rar|tar|tgz|gz|xz|bz2|zst)$', '' -replace '\.tar$', '') }
    }
    New-Item -ItemType Directory $Dest -Force | Out-Null
    Write-Host "  `e[33m$([char]0xf1c6)`e[0m  extracting `e[1;97m$(Split-Path $f -Leaf)`e[0m"
    & $TarExe -xf $f -C $Dest 2>&1 | Select-Object -First 3 | ForEach-Object { Write-Host "  `e[31m$_`e[0m" }
    $got = if ($tops.Count -eq 1 -and $Dest -eq (Split-Path $f)) { Join-Path $Dest $tops[0] } else { $Dest }   # (so o que foi extraido)
    $n = @(Get-ChildItem -LiteralPath $got -Recurse -File -Force -ErrorAction SilentlyContinue)
    Write-Host "  `e[32m$([char]0x2713)`e[0m $($n.Count) files  `e[90m$(Format-Size ($n | Measure-Object Length -Sum).Sum)  ->  $got`e[0m"
}
function zip {
    # zip <pasta|ficheiros...> [-o nome.zip]   -> cria um .zip (por omissao com o nome do primeiro, ao lado dele)
    param([Parameter(Mandatory, Position = 0, ValueFromRemainingArguments)][string[]]$Path, [Alias('o')][string]$Out)
    $items = @($Path | ForEach-Object { (Resolve-Path -LiteralPath $_ -ErrorAction SilentlyContinue).ProviderPath } | Where-Object { $_ })
    if (-not $items) { Write-Warn "nothing to zip ('$($Path -join "', '")' doesn't exist)"; return }
    $base = Split-Path $items[0]
    if (-not $Out) { $Out = Join-Path $base ((Split-Path $items[0] -Leaf) + '.zip') } elseif (-not [IO.Path]::IsPathRooted($Out)) { $Out = Join-Path $PWD.ProviderPath $Out }
    if (Test-Path -LiteralPath $Out) { Write-Warn "'$Out' already exists"; return }
    Write-Host "  `e[33m$([char]0xf1c6)`e[0m  zipping $($items.Count) item$(if ($items.Count -ne 1) { 's' })"
    & $TarExe -a -cf $Out -C $base @($items | ForEach-Object { Split-Path $_ -Leaf }) 2>&1 | Select-Object -First 3 | ForEach-Object { Write-Host "  `e[31m$_`e[0m" }
    if (Test-Path -LiteralPath $Out) { Write-Host "  `e[32m$([char]0x2713)`e[0m $(Split-Path $Out -Leaf)  `e[90m$(Format-Size (Get-Item -LiteralPath $Out).Length)  ->  $(Split-Path $Out)`e[0m" }
}
function fetch {
    # fetch <texto> [pasta]   -> procura o texto dentro dos ficheiros (rg); lista com pre-visualizacao (bat) no fzf;
    # Enter abre o ficheiro no VS Code na linha certa. Maiusculas so contam se o texto as tiver (smart case).
    param([Parameter(Mandatory)][string]$Text, [string]$Path = '.')
    $hits = rg --line-number --column --no-heading --color=always --smart-case -- $Text $Path 2>$null
    if (-not $hits) { Write-Warn "'$Text' not found in $((Resolve-Path $Path).ProviderPath)"; return }
    $pick = $hits | fzf --ansi --height 70% --reverse --delimiter ':' --prompt "fetch $Text> " `
        --preview 'bat --color=always --style=numbers --highlight-line {2} {1}' --preview-window 'right,60%,+{2}-8' `
        --header "$(@($hits).Count) matches  ·  enter opens in VS Code" 2>$null
    if (-not $pick) { return }
    $file, $ln, $col = ($pick -replace "`e\[[0-9;]*m", '') -split ':', 4
    code -g "${file}:${ln}:${col}"
}
function ex {
    # ex [pasta|ficheiro]   -> pasta: abre no Explorador; ficheiro: abre com a app do Windows para esse tipo
    param([string]$Path = '.')
    $p = (Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue).ProviderPath
    if (-not $p) { Write-Warn "'$Path' doesn't exist"; return }
    if (Test-Path -LiteralPath $p -PathType Container) { explorer.exe $p } else { Invoke-Item -LiteralPath $p }
}
function k {
    # k [nome]   -> processos (mais memoria primeiro) no fzf; Enter pede confirmacao e termina o escolhido
    param([string]$Name)
    $rows = Get-Process | Where-Object { $_.Id -ne $PID -and $_.Id -gt 4 } | Sort-Object WorkingSet64 -Descending | ForEach-Object {
        '{0,7}  {1,-28} {2,10}  {3}' -f $_.Id, ($_.ProcessName.Substring(0, [Math]::Min(28, $_.ProcessName.Length))), (Format-Size $_.WorkingSet64), $(if ($_.MainWindowTitle) { "`e[90m$($_.MainWindowTitle)`e[0m" })
    }
    $pick = $rows | fzf --ansi --height 60% --reverse --prompt 'kill> ' --query "$Name" --header '    pid  name                               memory  window' 2>$null
    if (-not $pick) { return }
    $procId = [int]($pick.Trim() -split '\s+')[0]; $pr = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if (-not $pr) { Write-Warn "process $procId already ended"; return }
    $ans = Read-Host "  end $($pr.ProcessName) ($procId)? [y/N]"
    if ($ans -match '^(y|s)') { try { Stop-Process -Id $procId -ErrorAction Stop; Write-Host "  `e[32m$([char]0x2713)`e[0m $($pr.ProcessName) ended" } catch { Write-Warn "couldn't end it: $($_.Exception.Message)" } }
}
function y {
    $tmp = (New-TemporaryFile).FullName
    Clear-FfRegion; yazi @args --cwd-file="$tmp"
    $cwd = Get-Content -Path $tmp -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($cwd -and $cwd -ne $PWD.Path -and (Test-Path -LiteralPath $cwd -PathType Container)) { Set-Location -LiteralPath $cwd }
    Remove-Item -Path $tmp -ErrorAction SilentlyContinue
}

# Sugestoes a partir do historico (seta direita aceita)
if (-not [Console]::IsOutputRedirected) {
    # sem sugestoes cinzentas do historico (Kev achou-as frustrantes: propunham sempre o ultimo comando parecido);
    # o historico fica no Ctrl+R e na seta para cima
    Set-PSReadLineOption -PredictionSource None -HistoryNoDuplicates
    # Tab como no VS Code: 1.o Tab escreve a 1.a opcao; 2.o Tab seguido abre a lista com todas (volta ao que estava
    # escrito); no menu, cada Tab passa a seguinte e ja a escreve na linha. Shift+Tab = anterior. Ctrl+Espaco = lista logo.
    $global:KvnTab = $null
    Set-PSReadLineKeyHandler -Key Tab -ScriptBlock {
        $line = $null; $cur = 0; [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cur)
        $t = $global:KvnTab; $global:KvnTab = $null
        # (o MenuComplete logo a seguir ao TabCompleteNext continua as mesmas opcoes: abre a lista toda)
        if ($t -and $t.after -eq $line -and $t.cur -eq $cur) { [Microsoft.PowerShell.PSConsoleReadLine]::MenuComplete(); return }
        [Microsoft.PowerShell.PSConsoleReadLine]::TabCompleteNext()
        $after = $null; $c2 = 0; [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$after, [ref]$c2)
        if ($after -ne $line) { $global:KvnTab = @{ before = $line; bcur = $cur; after = $after; cur = $c2 } }
    }
    Set-PSReadLineKeyHandler -Key Shift+Tab -Function TabCompletePrevious
    # Ctrl+Espaco: abre sempre a lista de opcoes
    # Em cd/ls/y: grelha propria com as cores do ls (a do PSReadLine nao tem cores e o Tab dela muda de selecao,
    # fixo no codigo). Setas mudam, Tab/Enter escrevem a selecionada, Esc fecha, outra tecla fecha e escreve-se.
    # Ctrl+Backspace em cd/ls/y: tira a ultima pasta do caminho (cd AppData\Local\ -> cd AppData\); $true se tratou a linha
    function Remove-PathSegment {
        $line = $null; $c = $null; [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$c)
        if ($line -notmatch '^(\s*(cd|ls|ll|la|y)\s+)(.+)$') { return $false }
        $pre = $Matches[1]; $t = $Matches[3].Trim().Trim('''', '"').TrimEnd('\', '/')
        $i = $t.LastIndexOfAny([char[]]'\/'); $new = if ($i -ge 0) { $t.Substring(0, $i + 1) } else { '' }
        if ($new -match '[\s''`$&(){}]') { $new = "'$($new.Replace("'", "''"))'" }
        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine(); [Microsoft.PowerShell.PSConsoleReadLine]::Insert($pre + $new)
        $true
    }
    Set-PSReadLineKeyHandler -Chord Ctrl+Backspace -ScriptBlock {
        param($key, $arg)
        if (-not (Remove-PathSegment)) { [Microsoft.PowerShell.PSConsoleReadLine]::BackwardKillWord($key, $arg) }
    }
    function Show-DirMenu {
        # lista de pastas no estilo do ls (uma por linha: icone, nome, data a direita) numa caixa por baixo do prompt.
        # Fica aberta enquanto se escreve o caminho: Tab entra na pasta, escrever filtra, Backspace apaga,
        # Ctrl+Backspace sobe uma pasta, Enter escreve e corre; fecha sem mais pastas, com Ctrl+Espaco ou Esc.
        # Molduras e colunas vao por posicao absoluta (ESC[<col>G): a largura dos icones varia com a fonte e
        # contar caracteres desalinhava a caixa.
        $e = [char]27; $sel = 0; $off = 0; $lastLine = $null; $bc = "$e[38;2;92;99;112m"   # cor da moldura
        $hz = [string][char]0x2500; $vt = [string][char]0x2502; $dot = [char]0x00B7
        $chip = { param($k, $t) "$e[48;2;62;68;81;97m $k $e[0;90m $t" }
        # no terminal real o Ctrl+C chega como sinal (nao como tecla) e era engolido: enquanto a lista esta aberta, como tecla
        $tcc = [Console]::TreatControlCAsInput; [Console]::TreatControlCAsInput = $true
        try {
            while ($true) {
                $line = $null; $cur = 0; [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cur)
                if ($line -ne $lastLine) {
                    $r = TabExpansion2 -inputScript $line -cursorColumn $cur
                    # so pastas: sem nenhuma, o PowerShell completava com ficheiros (desktop.ini, atalhos...)
                    $items = @($r.CompletionMatches | Where-Object ResultType -eq 'ProviderContainer'); $sel = 0; $off = 0; $lastLine = $line
                    if (-not $items.Count) { return }   # sem mais pastas
                    # pasta que se esta a ver (para o cabecalho)
                    $w = $line.Substring($r.ReplacementIndex, $r.ReplacementLength).Trim('''', '"'); $i = $w.LastIndexOfAny([char[]]'\/')
                    $dir = if ($i -ge 0) { (Resolve-Path -LiteralPath $w.Substring(0, $i + 1) -ErrorAction SilentlyContinue).ProviderPath } else { $PWD.ProviderPath }
                    if (-not $dir) { $dir = 'frequent folders' }
                    # nome / data (ou "frequent") de cada uma, a partir do texto da lista e da dica do completador
                    $rowsData = @(foreach ($it in $items) {   # @(): com 1 so, ficava um objeto e [0] dava vazio
                        $t = $it.ListItemText; $freq = $t.StartsWith([string][char]0xf017)
                        $nm = if ($freq) { $it.ToolTip -replace "\s+$dot\s+frequent$", '' } else { $t.Substring(1).Trim() }
                        if ($freq -and $nm.StartsWith($HOME, 'OrdinalIgnoreCase')) { $nm = '~' + $nm.Substring($HOME.Length) }
                        @{ ic = $t.Substring(0, 1); nm = $nm; freq = $freq; right = $(if ($freq) { 'frequent' } else { $it.ToolTip -replace '^.*modified\s+', '' }) }
                    })
                    $nLocal = @($rowsData | Where-Object { -not $_.freq }).Count
                }
                $W = [Console]::WindowWidth; $H = [Console]::WindowHeight
                $x0 = 3                                                    # coluna da moldura esquerda
                $nameW = [Math]::Min(60, ($rowsData | ForEach-Object { $_.nm.Length } | Measure-Object -Maximum).Maximum)
                $host1 = $env:COMPUTERNAME.ToLower(); $pc = Get-PcIcon (Get-PcName)
                $cnt = if ($nLocal -eq $items.Count) { "$($items.Count) folder$(if ($items.Count -ne 1) { 's' })" } else { "$nLocal here $dot $($items.Count - $nLocal) frequent" }
                $bw = [Math]::Min($W - 4, [Math]::Max([Math]::Max(58, $nameW + 26), $host1.Length + $dir.Length + $cnt.Length + 18))   # largura da caixa toda (cresce com o caminho)
                $x1 = $x0 + $bw - 1                                       # coluna da moldura direita
                $vis = [Math]::Min($items.Count, [Math]::Max(3, [Math]::Min(12, $H - 8)))
                if ($sel -lt $off) { $off = $sel } elseif ($sel -ge $off + $vis) { $off = $sel - $vis + 1 }
                # espaco por baixo do prompt: se nao houver, o ecra sobe (e o prompt com ele)
                $need = $vis + 3
                if ($H - 1 - ([Console]::CursorTop - [Console]::WindowTop) -lt $need) { [Console]::Write("`n" * $need + "$e[$($need)A") }
                $hline = $bc + ($hz * ($bw - 2))
                # cabecalho:  ╭─  <pc>  C:\...\pasta\   3 folders ─────╮
                $path = $dir; $room = $bw - 16 - $host1.Length - $cnt.Length; if ($path.Length -gt $room) { $path = [char]0x2026 + $path.Substring($path.Length - $room + 1) }
                $o = "$e[?25l${e}7`n`r$e[J"
                $o += "$e[${x0}G$bc$([char]0x256D)$hline$([char]0x256E)$e[$($x0 + 2)G $e[1;97m$pc  $host1$e[0;37m  $path$e[90m   $cnt $e[0m"
                for ($k = 0; $k -lt $vis; $k++) {
                    $j = $off + $k; $d = $rowsData[$j]; $isSel = $j -eq $sel
                    $nm = $d.nm; if ($nm.Length -gt $bw - 24) { $nm = $nm.Substring(0, $bw - 25) + [char]0x2026 }
                    $o += "`n`r$e[${x0}G$bc$vt$e[0m"
                    if ($isSel) { $o += "$e[$($x0 + 1)G$e[48;2;62;68;81m" + (' ' * ($bw - 2)) }   # linha toda realcada
                    $nc = if ($isSel) { '1;97' } elseif ($d.freq) { '0;37' } else { '1;34' }
                    $icc = if ($d.freq) { '90' } else { '34' }
                    $o += "$e[$($x0 + 2)G$e[$($icc)m$($d.ic)$e[$($x0 + 5)G$e[$($nc)m$nm"
                    $o += "$e[$($x1 - 1 - $d.right.Length)G$e[0;90m$(if ($isSel) { "$e[48;2;62;68;81m" })$($d.right)$e[0m$e[${x1}G$bc$vt$e[0m"
                }
                # rodape:  ╰─ 2/31 ──────────── tab open  enter go  esc close ─╯
                $pos = if ($items.Count -gt $vis) { "$($sel + 1)/$($items.Count)" } else { '' }
                $keys = (& $chip 'tab' 'open') + '   ' + (& $chip 'enter' 'go') + '   ' + (& $chip 'esc' 'close')
                $kw = ' tab  open    enter  go    esc  close'.Length
                $o += "`n`r$e[${x0}G$bc$([char]0x2570)$hline$([char]0x256F)$e[0m"
                if ($pos) { $o += "$e[$($x0 + 2)G$e[90m $pos $e[0m" }
                $o += "$e[$($x1 - 2 - $kw)G $keys $e[0m"
                [Console]::Write($o + "${e}8$e[?25h")
                $k = [Console]::ReadKey($true)
                $ctrlSpace = $k.Key -eq 'Spacebar' -and ($k.Modifiers -band [ConsoleModifiers]::Control)
                if ($ctrlSpace -or $k.Key -eq 'Escape') { return }
                # Ctrl+C: fecha a lista e cancela a linha, como fora dela (^C e prompt novo)
                if ($k.KeyChar -eq [char]3 -or ($k.Key -eq 'C' -and ($k.Modifiers -band [ConsoleModifiers]::Control))) {
                    [Console]::Write("${e}7`n`r$e[J${e}8"); [Microsoft.PowerShell.PSConsoleReadLine]::CancelLine(); return
                }
                if ($k.Key -eq 'Backspace' -and ($k.Modifiers -band [ConsoleModifiers]::Control)) { [void](Remove-PathSegment); continue }
                switch ($k.Key) {
                    'DownArrow'  { if ($sel + 1 -lt $items.Count) { $sel++ } }
                    'UpArrow'    { if ($sel -gt 0) { $sel-- } }
                    'PageDown'   { $sel = [Math]::Min($items.Count - 1, $sel + $vis) }
                    'PageUp'     { $sel = [Math]::Max(0, $sel - $vis) }
                    'Tab'        { [Microsoft.PowerShell.PSConsoleReadLine]::Replace($r.ReplacementIndex, $r.ReplacementLength, $items[$sel].CompletionText) }
                    'Enter'      {
                        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($r.ReplacementIndex, $r.ReplacementLength, $items[$sel].CompletionText)
                        [Console]::Write("${e}7`n`r$e[J${e}8"); [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine(); return
                    }
                    'Backspace'  { [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar() }
                    default      { if ($k.KeyChar -and [int]$k.KeyChar -ge 32) { [Microsoft.PowerShell.PSConsoleReadLine]::Insert([string]$k.KeyChar) } }
                }
            }
        } finally { [Console]::TreatControlCAsInput = $tcc; [Console]::Write("${e}7`n`r$e[J${e}8$e[?25h") }   # apaga a lista
    }
    Set-PSReadLineKeyHandler -Chord Ctrl+Spacebar -ScriptBlock {
        param($key, $arg)
        $line = $null; $c = $null; [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$c)
        if ($line -match '^\s*(cd|ls|ll|la|y)(\s|$)') { Show-DirMenu } else { [Microsoft.PowerShell.PSConsoleReadLine]::MenuComplete($key, $arg) }
    }
}

# Comandos Linux verdadeiros (iguais aos do WSL): uutils coreutils (rm, cp, mv, mkdir, touch, head, tail, wc, sort...)
# + grep/sed/awk/find/less/diff/xargs do Git. Os cmdlets do PowerShell continuam pelo nome completo (Remove-Item...).
# Os nossos (ls, cat, cd, fetch...) sao funcoes e ganham sempre aos .exe.
# (GetDirectories em vez do Resolve-Path com * : ~20 ms -> ~1 ms em cada separador)
$UuDir = try { $uuPk = @([IO.Directory]::GetDirectories("$env:LOCALAPPDATA\Microsoft\WinGet\Packages", 'uutils.coreutils_*')); if ($uuPk) { @([IO.Directory]::GetDirectories($uuPk[-1], 'coreutils-*'))[-1] } } catch { $null }
# (sem o pacote do winget: a versao que o instalador foi buscar ao GitHub do uutils)
if (-not $UuDir) { $UuDir = try { @([IO.Directory]::GetDirectories("$HOME\.local\coreutils", 'coreutils-*'))[-1] } catch { $null } }
if ($UuDir) {
    $env:PATH = "$UuDir;$env:PATH"   # a frente do System32 (sort, find, hostname...)
    Remove-Item Alias:rm, Alias:rmdir, Alias:cp, Alias:mv, Alias:sort, Alias:tee, Alias:sleep, Alias:del, Alias:copy, Alias:move -Force -ErrorAction SilentlyContinue
    Remove-Item Function:mkdir -Force -ErrorAction SilentlyContinue
}
function rm {
    # o rm do uutils nao apaga ficheiros read-only no Windows (no Linux o -f apaga; ex. .git\objects\pack na partilha D:):
    # com -f tira o atributo aos alvos antes de chamar o rm verdadeiro. O resto e o rm.exe tal e qual.
    if ($args -cmatch '^(-[a-zA-Z]*f[a-zA-Z]*|--force)$') {
        foreach ($p in @($args -notmatch '^-')) {
            Get-Item -Path $p -Force -ErrorAction Ignore | ForEach-Object {
                if ($_.PSIsContainer) { Get-ChildItem -LiteralPath $_.FullName -Recurse -Force -File -ErrorAction Ignore } else { $_ }
            } | Where-Object IsReadOnly | ForEach-Object { $_.IsReadOnly = $false }
        }
    }
    rm.exe @args
}
Remove-Item Alias:diff -Force -ErrorAction SilentlyContinue
foreach ($t in 'grep', 'sed', 'awk', 'find', 'less', 'diff', 'xargs', 'file') {
    if (Test-Path "$env:ProgramFiles\Git\usr\bin\$t.exe") { Set-Alias $t "$env:ProgramFiles\Git\usr\bin\$t.exe" }
}

# Ferramentas modernas
Remove-Item Alias:ls, Alias:cat -Force -ErrorAction SilentlyContinue
function ll { eza -la --icons --group-directories-first --git @args }
function la { eza -a --icons --group-directories-first @args }   # tudo, incluindo o que o home-tidy esconde
function lt { eza --tree --level=2 --icons @args }
function cat { bat --paging=never @args }
function lg { if (Open-InTab 'lazygit' (@('lazygit') + $args)) { return }; Clear-FfRegion; $a = $args; Invoke-Zoomed { lazygit @a } }
function repo {
    # repo [pasta] -> o estado todo de um repositorio, so para ver (o lg e para mexer):
    # branch e remoto, alteracoes, branches, historico, autores, linguagens. So le, nunca muda nada (nem faz fetch).
    param([string]$Path = '.')
    $e = [char]27
    $root = "$(git -C $Path rev-parse --show-toplevel 2>&1)"
    if ($LASTEXITCODE) {
        if ($root -match 'dubious ownership') { Write-Warn 'git does not trust this folder (network drive)' 'needs the safe.directory exception (git config --global --add safe.directory ...), run it yourself'; return }
        Write-Warn "'$Path' is not inside a git repository"; return
    }
    $g = { git -C $root @args 2>$null }
    $W = 100; try { $W = [Math]::Max(60, [Math]::Min([Console]::WindowWidth - 4, 120)) } catch { }
    $cut = { param($s, $n) if ($s.Length -gt $n) { $s.Substring(0, $n - 1) + [char]0x2026 } else { $s } }
    $sec = { param($i, $t, $c, $x) Write-Host ''; Write-Host "  $e[${c}m$([char]$i)  $t$e[0m  $e[90m$x$e[0m"; Write-Host "  $e[90m$([string][char]0x2500 * $W)$e[0m" }

    # ---- cabecalho: nome, pasta, branch, upstream, remoto ----
    $st = @(& $g status --porcelain=v2 --branch)
    $head = ($st -match '^# branch.head ' -replace '^# branch.head ') | Select-Object -First 1
    $up = ($st -match '^# branch.upstream ' -replace '^# branch.upstream ') | Select-Object -First 1
    $ab = ($st -match '^# branch.ab ') | Select-Object -First 1
    $ahead = $behind = 0; if ($ab -match '\+(\d+) -(\d+)') { $ahead = [int]$Matches[1]; $behind = [int]$Matches[2] }
    $url = "$(& $g remote get-url origin)"
    $web = $url -replace '^git@([^:]+):', 'https://$1/' -replace '\.git$', ''
    $sync = if (-not $up) { "$e[90mno upstream" } elseif (-not $ahead -and -not $behind) { "$e[32m$([char]0x2713) up to date with $up" } else { "$e[33m$(if ($ahead) { "$([char]0x2191)$ahead to push " })$(if ($behind) { "$([char]0x2193)$behind to pull " })$e[90m($up)" }
    $show = $root -replace '/', '\'
    $show = $show -replace '^\\\\[^\\]+\\([a-zA-Z])(?=\\|$)', { "$($_.Groups[1].Value.ToUpper()):" }   # partilha do outro PC -> D:\..., como o prompt
    Write-Host ''
    Write-Host "  $e[1;97m$([char]0xf1d3)  $(Split-Path $root -Leaf)$e[0m  $e[37m$show$e[0m"
    Write-Host "  $e[35m$([char]0xe725) $(if ($head -eq '(detached)') { "detached at $(& $g rev-parse --short HEAD)" } else { $head })$e[0m   $sync$e[0m"
    if ($url) { Write-Host "  $e[90m$([char]0xf0ac)  $e[36m$web$e[0m" } else { Write-Host "  $e[90m$([char]0xf0ac)  no remote (local only)$e[0m" }
    $fetched = Get-Item "$root\.git\FETCH_HEAD" -ErrorAction Ignore
    if ($fetched -and $up) {
        $t = (Get-Date) - $fetched.LastWriteTime
        $ago = if ($t.TotalHours -lt 1) { "$([int]$t.TotalMinutes) min" } elseif ($t.TotalDays -lt 1) { "$([int]$t.TotalHours) h" } else { "$([int]$t.TotalDays) days" }
        Write-Host "  $e[90m   last fetch $ago ago  (push / pull numbers are from then)$e[0m"
    }

    # ---- alteracoes ----
    $files = foreach ($l in $st) {
        switch -Regex ($l) {
            '^1 (.)(.) (?:\S+ ){6}(.+)$' { @{ x = $Matches[1]; y = $Matches[2]; p = $Matches[3] } }
            '^2 (.)(.) (?:\S+ ){7}(.+)\t(.+)$' { @{ x = $Matches[1]; y = $Matches[2]; p = "$($Matches[4]) $([char]0x2192) $($Matches[3])" } }
            '^u (?:\S+ ){9}(.+)$' { @{ x = 'U'; y = 'U'; p = $Matches[1] } }
            '^\? (.+)$' { @{ x = '?'; y = '?'; p = $Matches[1] } }
        }
    }
    $nS = @($files | Where-Object { $_.x -notin '.', '?', 'U' }).Count; $nM = @($files | Where-Object { $_.y -notin '.', '?', 'U' }).Count
    $nU = @($files | Where-Object { $_.x -eq '?' }).Count; $nC = @($files | Where-Object { $_.x -eq 'U' }).Count
    $sum = @($(if ($nC) { "$e[31m$nC conflicts" }), $(if ($nS) { "$e[32m$nS staged" }), $(if ($nM) { "$e[33m$nM modified" }), $(if ($nU) { "$e[90m$nU untracked" })) -ne $null -join "$e[90m  ·  "
    & $sec 0xf044 'changes' '33' $(if (-not $files) { 'nothing to commit' })
    if (-not $files) { Write-Host "  $e[32m$([char]0x2713)$e[0m $e[90mworking tree clean$e[0m" }
    else {
        Write-Host "  $sum$e[0m"
        $verb = @{ M = 'modified'; A = 'new'; D = 'deleted'; R = 'renamed'; C = 'copied'; T = 'type'; U = 'conflict'; '?' = 'untracked' }
        foreach ($f in @($files | Sort-Object { if ($_.x -eq 'U') { 0 } elseif ($_.x -notin '.', '?') { 1 } elseif ($_.x -eq '?') { 3 } else { 2 } }) | Select-Object -First 14) {
            $c = if ($f.x -eq 'U') { '31' } elseif ($f.x -notin '.', '?') { '32' } elseif ($f.x -eq '?') { '90' } else { '33' }
            $k = if ($f.x -notin '.', '?', 'U') { $f.x } else { $f.y }
            $tag = if ($f.x -notin '.', '?', 'U') { 'staged' } else { $verb["$k"] }
            Write-Host ("  $e[${c}m  {0}  {1,-10}$e[0m {2}" -f $k, $tag, (& $cut $f.p ($W - 18)))
        }
        if ($files.Count -gt 14) { Write-Host "  $e[90m  + $($files.Count - 14) more$e[0m" }
    }
    $stash = @(& $g stash list).Count
    if ($stash) { Write-Host "  $e[35m  $stash in stash$e[0m  $e[90m(put aside with git stash)$e[0m" }

    # ---- branches (mais recentes primeiro) ----
    $br = @(& $g for-each-ref --sort=-committerdate refs/heads --format='%(HEAD)%09%(refname:short)%09%(upstream:track,nobracket)%09%(committerdate:relative)%09%(subject)')
    $rem = @(& $g for-each-ref refs/remotes --format='%(refname:short)' | Where-Object { $_ -notmatch '/HEAD$' }).Count
    & $sec 0xe725 'branches' '35' "$($br.Count) local  ·  $rem remote"
    foreach ($b in $br | Select-Object -First 8) {
        $p = $b -split "`t"; $cur = $p[0] -eq '*'
        $tr = $p[2] -replace 'ahead (\d+)', "$([char]0x2191)`$1" -replace 'behind (\d+)', "$([char]0x2193)`$1" -replace ', ', ' ' -replace '^gone$', 'remote gone'
        $line = "  {0} {1,-30} {2,-8} {3,-15} " -f $(if ($cur) { "$e[32m$([char]0x25CF)" } else { "$e[90m " }), (& $cut $p[1] 30), $tr, $p[3]
        Write-Host "$(if ($cur) { "$e[1;97m" } else { "$e[37m" })$line$e[90m$(& $cut $p[4] ([Math]::Max(10, $W - 60)))$e[0m"
    }
    if ($br.Count -gt 8) { Write-Host "  $e[90m  + $($br.Count - 8) more$e[0m" }

    # ---- historico (grafo) ----
    $n = @(& $g rev-list --count HEAD)[0]
    & $sec 0xf1da 'history' '34' $(if ($n) { "$n commit$(if ($n -ne 1) { s })" } else { 'no commits yet' })
    if ($n) {
        # (decoracao so com este branch, tags e remotos: os branches locais estao na seccao de cima; assunto cortado a largura)
        $refs = @('--decorate-refs=refs/tags', '--decorate-refs=refs/remotes') + $(if ($head -ne '(detached)') { "--decorate-refs=refs/heads/$head" })
        & $g log --graph --color=always -n 12 @refs --format="%C(yellow)%h%C(reset) %<($([Math]::Max(20, $W - 50)),trunc)%s%C(auto)%d%C(reset) %C(8)%an, %ar%C(reset)" |
            ForEach-Object { "  $_" } | Write-Host
    }

    # ---- resumo: autores, tags, ficheiros, linguagens ----
    if ($n) {
        $first = "$(& $g log --reverse --format='%ad' --date=format:'%d/%m/%y' | Select-Object -First 1)"
        $tag = "$(& $g describe --tags --abbrev=0)"
        $tracked = @(& $g ls-files)
        & $sec 0xf080 'about' '36' "since $first$(if ($tag) { "  ·  latest tag $tag" })  ·  $($tracked.Count) files"
        $who = @(& $g shortlog -sn --no-merges HEAD | Select-Object -First 4)
        Write-Host "  $e[90mpeople   $e[0m$(($who | ForEach-Object { if ($_ -match '^\s*(\d+)\s+(.+)$') { "$e[97m$($Matches[2])$e[90m $($Matches[1])" } }) -join "$e[90m  ·  ")$e[0m"
        $langs = $tracked | ForEach-Object { [IO.Path]::GetExtension($_).TrimStart('.').ToLower() } | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | Select-Object -First 6
        $tot = ($langs | Measure-Object Count -Sum).Sum
        if ($tot) { Write-Host "  $e[90mfiles    $e[0m$(($langs | ForEach-Object { "$e[36m.$($_.Name)$e[90m $([Math]::Round(100 * $_.Count / $tot))%" }) -join "$e[90m  ·  ")$e[0m" }
    }
    Write-Host ''
}

# cd D / cd c -> raiz da drive (se nao existir pasta com esse nome)
Remove-Item Alias:cd -Force -ErrorAction SilentlyContinue
function cd {
    # (Path declarado para o Tab usar o completador de pastas abaixo; sem argumento vai para a home, como no Linux)
    param([Parameter(Position = 0)][string]$Path)
    if (-not $Path) { Set-Location $HOME; return }
    # 'cd D', 'cd D:' ou 'cd "D:"': raiz da drive; se a drive nao existir, diz-o em vez do erro do PS
    if ($Path -match '^([a-zA-Z]):?$' -and -not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        $l = $Matches[1].ToUpper()
        $rp = (Get-ItemProperty "HKCU:\Network\$l" -ErrorAction SilentlyContinue).RemotePath
        # numa sessao ssh (entrada com chave) o Windows nao tem a password guardada da partilha: nao da para a abrir
        if ($rp -and $env:SSH_CONNECTION) {
            Write-Warn "drive ${l}: is the network share $rp - not reachable inside an ssh session" 'ssh logins have no saved passwords on Windows; use it on that PC directly (exit this ssh)'
            return
        }
        if (Test-Path "${l}:\" -ErrorAction SilentlyContinue) { Set-Location "${l}:\"; return }
        # unidade de rede (ex.: D: = \\desktop\d): o Windows so a liga a sessao normal; num terminal admin liga-se aqui
        if ($rp) {
            try { New-PSDrive -Name $l -PSProvider FileSystem -Root $rp -Scope Global -ErrorAction Stop | Out-Null; Set-Location "${l}:\" -ErrorAction Stop; return }
            catch {
                Remove-PSDrive $l -Force -ErrorAction SilentlyContinue
                if ("$_" -match 'denied|negado') { Write-Warn "drive ${l}: access denied to $rp" "save the share's password first: cmdkey /add:$((($rp -split '\\')[2])) /user:<pc>\<user> /pass" }
                else { Write-Warn "drive ${l}: is the share $rp and it didn't respond" 'is the other PC on? (wake <pc> wakes it, if it has a MAC in pcs.json)' }
                return
            }
        }
        $have = (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' } | ForEach-Object Name) -join ', '
        Write-Warn "drive ${l}: doesn't exist on this PC" "drives: $have"
        return
    }
    Set-Location $Path
}
# Tab no cd: so pastas. Primeiro as que comecam pelo que se escreveu, depois as que o contem ("proj" -> "My Projeto");
# pastas com ponto so se o texto comecar por ponto. Sem nenhuma aqui: as pastas frequentes do zoxide.
# Na grelha: icone de pasta + nome (frequentes do zoxide com icone de relogio); por baixo, a data da selecionada.
Register-ArgumentCompleter -CommandName cd, ls, Set-Location -ParameterName Path -ScriptBlock {   # (Set-Location: o Ctrl+Espaco num prompt interativo resolve o "cd" para ele)
    param($c, $p, $word)
    $w = "$word".Trim('''', '"')
    $i = $w.LastIndexOfAny([char[]]'\/')
    $parent = if ($i -ge 0) { $w.Substring(0, $i + 1) } else { '' }; $leaf = $w.Substring($i + 1)
    $base = if ($parent) { $parent } else { '.' }
    # sem as escondidas (Application Data, Cookies, o que o home-tidy esconde), como o ls; com ".x" mostra-as
    $hid = $leaf.StartsWith('.')
    $dirs = @(Get-ChildItem -LiteralPath $base -Directory -Force:$hid -ErrorAction SilentlyContinue | Where-Object { $hid -or -not $_.Name.StartsWith('.') })
    $hit = @($dirs | Where-Object { $_.Name.StartsWith($leaf, [StringComparison]::OrdinalIgnoreCase) }) + @($dirs | Where-Object { -not $_.Name.StartsWith($leaf, [StringComparison]::OrdinalIgnoreCase) -and $_.Name.IndexOf($leaf, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
    $out = @($hit | ForEach-Object { @{ d = "$parent$($_.Name)\"; n = "$([char]0xf07b) $($_.Name)"; tip = "$($_.Name)   ·   modified $($_.LastWriteTime.ToString('dd/MM/yy HH:mm'))" } })
    if (-not $out -and -not $parent -and $leaf -and (Get-Command zoxide -ErrorAction SilentlyContinue)) {
        $out = @(zoxide query -l -- $leaf 2>$null | Select-Object -First 8 | ForEach-Object { @{ d = "$_\"; n = "$([char]0xf017) $(Split-Path $_ -Leaf)"; tip = "$_   ·   frequent" } })
    }
    foreach ($x in $out) {
        $d = $x.d; $text = if ($d -match '[\s''`$&(){}]') { "'$($d.Replace("'", "''"))'" } else { $d }
        [Management.Automation.CompletionResult]::new($text, $x.n, 'ProviderContainer', $x.tip)
    }
}

# F1 / help: comandos por grupo com a documentacao de cada um ao lado (~\.config\kvn-help.ps1, so carrega no F1)
# ha um cabecalho noutro painel (pin do Windows Terminal, ou o painel de cima do WezTerm, que poe KVN_COMPACT nos shells):
# este shell nao desenha o seu, e um ssh daqui pede ao outro PC para tambem nao desenhar
function Test-HeaderPane { [bool](($env:KVN_COMPACT -and $env:WEZTERM_PANE) -or ($global:FfBarPid -and (Get-Process -Id $global:FfBarPid -ErrorAction SilentlyContinue))) }
function Invoke-Zoomed([scriptblock]$sb) {
    # com o pin ligado, o painel de baixo e so parte do separador: zoom do painel (ctrl+shift+z = togglePaneZoom no WT)
    # enquanto $sb corre (F1, editores), para ocupar o ecra todo
    # no WezTerm (prototipo do SuperTerminal) ha sempre cabecalho em cima: zoom pela CLI dele, sem teclas falsas
    if ($env:WEZTERM_PANE -and $env:WEZTERM_EXECUTABLE) {
        $wz = Join-Path (Split-Path $env:WEZTERM_EXECUTABLE) 'wezterm.exe'
        & $wz cli zoom-pane --zoom 2>$null; Start-Sleep -Milliseconds 100
        # (ao sair do zoom o cabecalho e redesenhado ja: as vezes o WezTerm nao o repintava e ficava em branco)
        try { & $sb } finally { & $wz cli zoom-pane --unzoom 2>$null; New-Item "$env:TEMP\superterminal-header-redraw" -Force | Out-Null }
        return
    }
    $zoom = $global:FfBarPid -and (Get-Process -Id $global:FfBarPid -ErrorAction SilentlyContinue)
    if ($zoom) { Send-WtKeys; Start-Sleep -Milliseconds 250 }
    try { & $sb } finally { if ($zoom) { Send-WtKeys } }
}
function Select-Cheat { Invoke-Zoomed { . "$HOME\.config\kvn-help.ps1"; Show-KvnHelp } }
# editores em ecra inteiro mesmo com o pin
function hx { $edArgs = $args; Clear-FfRegion; Invoke-Zoomed { hx.exe @edArgs } }
function micro { $edArgs = $args; Clear-FfRegion; Invoke-Zoomed { micro.exe @edArgs } }
function Send-WtKeys {
    # carrega em ctrl+shift+z na janela do Windows Terminal (que esta a frente: o F1 foi carregado nela)
    if (-not ('Kvn.Kb' -as [type])) { Add-Type -Namespace Kvn -Name Kb -MemberDefinition '[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);' }
    foreach ($vk in 0x11, 0x10, 0x5A) { [Kvn.Kb]::keybd_event($vk, 0, 0, [UIntPtr]::Zero) }
    foreach ($vk in 0x5A, 0x10, 0x11) { [Kvn.Kb]::keybd_event($vk, 0, 2, [UIntPtr]::Zero) }
}
function help-kvn { $i = Select-Cheat; if ($i) { "type: $i" } }
# ---- caixa "comandos" (e o tailscale por cima) a direita do fastfetch ----
function Get-CheatRows {
    # so as teclas principais (a lista dos comandos saiu do cabecalho: esta toda no F1). No WezTerm as teclas estao
    # na barra de baixo do proprio terminal: aqui nada
    if ($env:WEZTERM_PANE) { return }
    $e = [char]27
    $chip = { param($k, $t) "$e[48;2;62;68;81;97m $k $e[0;90m $t  " }
    @("  $e[37m$([char]0xf11c)  keys   " + (& $chip '^T' 'tab') + (& $chip '^D' 'split') + (& $chip '^R' 'history') + (& $chip 'F1' 'help') + "$e[0m")
}
function Get-TsRows {
    # seccao "tailscale" (por cima dos comandos, na coluna da direita): saiu do fastfetch para o cabecalho ficar mais
    # baixo. Usa a cache do ts-cache.ps1 (ts1 = resumo, ts2..ts6 = dispositivos; o ESC[11D era para o fastfetch)
    $e = [char]27; $d = "$env:LOCALAPPDATA\pwsh-init-cache"
    $r = @("$e[1;34m$([char]0xf233)  tailscale $e[0;90m" + ([string][char]0x2500 * 44) + "$e[0m")
    $s = Get-Content "$d\ts1.txt" -Raw -ErrorAction SilentlyContinue
    if ($s) { $r += "  $e[90m" + '  status'.PadRight(14) + "$e[0m$s$e[0m" }
    foreach ($i in 2..6) { $l = Get-Content "$d\ts$i.txt" -Raw -ErrorAction SilentlyContinue; if ($l) { $r += '  ' + $l.Replace("$e[11D", '') + "$e[0m" } }
    $r
}
function Get-FfLogoWidth {
    # largura do logotipo do fastfetch (colunas); lida do config.jsonc so quando o ficheiro muda
    $f = "$HOME\.config\fastfetch\config.jsonc"; $wt = try { [IO.File]::GetLastWriteTimeUtc($f) } catch { return 27 }
    if ($global:FfLogoT -ne $wt) {
        $m = [regex]::Match([IO.File]::ReadAllText($f), '"logo"\s*:\s*\{[^}]*?"source"\s*:\s*"((?:[^"\\]|\\.)*)"')
        $global:FfLogoW = if ($m.Success) { (@(($m.Groups[1].Value -replace '\$\d', '') -split '\\n' | ForEach-Object { $_.TrimEnd().Length }) | Measure-Object -Maximum).Maximum } else { 27 }
        $global:FfLogoT = $wt
    }
    $global:FfLogoW
}
function Show-Cheats {
    # colunas a direita do fastfetch (que so tem logotipo + system + network): hardware (outro fastfetch, so essa
    # seccao: ~\.config\fastfetch\config-hw.jsonc) e tailscale + teclas. Lado a lado o cabecalho fica com ~8 linhas em
    # vez de ~16; o que nao couber ao lado vai para baixo do hardware
    $e = [char]27; $W = [Console]::WindowWidth; $out = "${e}7"; $global:CheatRows = 0
    # (a coluna do hardware segue a largura do logotipo: um logo mais largo, desenhado no setup, nao fica por baixo dela)
    $hwCol = [Math]::Max(82, (Get-FfLogoWidth) + 55); $hwW = 48; $tsW = 56; $tsCol = $hwCol + $hwW + 2
    $hwFile = "$HOME\.config\fastfetch\config-hw.jsonc"; $hwRows = 0
    if ($W -ge $hwCol + $hwW -and (Test-Path $hwFile)) {
        $enc = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); Push-Location $HOME
        try { $hw = @(fastfetch -c $hwFile --pipe false 2>$null) } finally { Pop-Location; [Console]::OutputEncoding = $enc }
        # (o fastfetch alinha os valores com ESC[<n>G = coluna n do ecra: passa a ser relativa a esta coluna, senao os
        # valores saltavam para a esquerda, por cima do logotipo)
        $r = 1; foreach ($l in $hw) { $l = [regex]::Replace($l, "$e\[(\d+)G", { param($m) "$e[$($hwCol - 1 + [int]$m.Groups[1].Value)G" }); $out += "$e[$r;${hwCol}H$l"; $r++ }; $hwRows = $r - 1
    }

    $rows = @(Get-TsRows); $cr = @(Get-CheatRows); if ($cr) { $rows += @('') + $cr }
    if ($W -ge $tsCol + $tsW) { $c = $tsCol; $r = 1 } elseif ($W -ge $hwCol + $tsW) { $c = $hwCol; $r = $hwRows + 2 } else { $c = 0 }
    if ($c) { foreach ($row in $rows) { $out += "$e[$r;${c}H$row"; $r++ } }
    $global:CheatRows = [Math]::Max($hwRows, $(if ($c) { $r - 1 } else { 0 }))   # (o ff garante que o cursor fica abaixo disto)
    [Console]::Write($out + "${e}8")
}

# Clear-FfRegion: desfaz uma regiao de scroll (DECSTBM) deixada por algum programa; antes de apps de ecra inteiro.
# (o antigo cabecalho fixo por DECSTBM saiu: no Windows Terminal, o que sai por cima da regiao perde-se do historico)
$global:FfTop = $null
function Clear-FfRegion { [Console]::Write("`e7`e[r`e8") }
# pin: este painel fica so com o cabecalho (fastfetch + comandos, igual ao normal) e abre-se o shell num painel por
# baixo, com scroll normal. "pin" no shell de baixo (ou fechar um dos paineis) volta a um so painel.
# Ligacao entre os dois: o painel novo nao herda variaveis do WT, por isso vai por ficheiros em %TEMP%
#   ff-bar-pending = PID do cabecalho (o shell novo le-o ao arrancar), ff-bar-<pid>.shell / .stop
$global:FfBarPid = $null
function pin {
    # WezTerm (SuperTerminal): o cabecalho e um painel do proprio WezTerm (titulo "superterminal-header"); pin liga / desliga-o
    if ($env:WEZTERM_PANE -and $env:WEZTERM_EXECUTABLE) {
        $wz = Join-Path (Split-Path $env:WEZTERM_EXECUTABLE) 'wezterm.exe'
        $all = @(& $wz cli list --format json | ConvertFrom-Json)
        $me = $all | Where-Object pane_id -eq ([int]$env:WEZTERM_PANE)
        $hdr = $all | Where-Object { $_.tab_id -eq $me.tab_id -and $_.title -eq 'superterminal-header' } | Select-Object -First 1
        # sem cabecalho este shell volta a desenhar o seu (KVN_COMPACT so neste shell); com cabecalho, so limpa
        if ($hdr) { & $wz cli kill-pane --pane-id $hdr.pane_id; $env:KVN_COMPACT = ''; Start-Sleep -Milliseconds 300; ff; return }
        $env:KVN_COMPACT = '1'; Clear-Host
        $null = & $wz cli split-pane --pane-id $env:WEZTERM_PANE --top --top-level --percent 45 -- $PwshExe -NoLogo -NoProfile -File "$HOME\.config\wezterm\header.ps1"
        & $wz cli activate-pane --pane-id $env:WEZTERM_PANE; return
    }
    # o cabecalho ja foi fechado (painel fechado a mao): este pin volta a ligar
    if ($global:FfBarPid -and -not (Get-Process -Id $global:FfBarPid -ErrorAction SilentlyContinue)) { $global:FfBarPid = $null }
    if ($global:FfBarPid) {
        # desligar: pede ao painel de cima para fechar, espera que feche e que este painel cresca, e desenha o fastfetch
        New-Item "$env:TEMP\ff-bar-$($global:FfBarPid).stop" -Force | Out-Null
        $h0 = [Console]::WindowHeight; $bar = Get-Process -Id $global:FfBarPid -ErrorAction SilentlyContinue; $global:FfBarPid = $null
        if ($bar) { [void]$bar.WaitForExit(3000) }
        for ($i = 0; $i -lt 20 -and [Console]::WindowHeight -eq $h0; $i++) { Start-Sleep -Milliseconds 50 }
        Start-Sleep -Milliseconds 150; ff; return
    }
    if ($env:SSH_CONNECTION -or -not $env:WT_SESSION) { Write-Warn 'pin needs a local Windows Terminal'; return }
    $wt = @("$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe", "$HOME\.local\terminal\wt.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $wt) { Write-Warn 'wt.exe not found'; return }
    ff -Bar
    $rows = [Console]::CursorTop + 1; $h = [Console]::WindowHeight   # altura do fastfetch (+1 linha onde fica o cursor)
    if (-not $global:FfTop -or $h -lt $rows + 10) { ff; Write-Warn "terminal too short for pin ($h rows)"; return }
    $stop = "$env:TEMP\ff-bar-$PID.stop"; $shellFile = "$env:TEMP\ff-bar-$PID.shell"; $cmdFile = "$env:TEMP\ff-bar-$PID.cmd"; $live = $true; $tick = $null   # ao vivo por omissao (ffw no shell de baixo desliga/liga)
    Remove-Item $stop, $shellFile, $cmdFile -ErrorAction SilentlyContinue
    if ($global:TabFile) { Remove-Item $global:TabFile -ErrorAction SilentlyContinue; $global:TabFile = $null }   # o cabecalho nao e um separador a reabrir
    Set-Content "$env:TEMP\ff-bar-pending" $PID
    # -H: o painel novo (shell) fica em baixo com o resto da altura; -s = fracao do painel novo
    Start-Process $wt -ArgumentList '-w', '0', 'sp', '-H', '-s', ('{0:0.00}' -f (1 - ($rows + 1) / $h)).Replace(',', '.'), '-d', "`"$($PWD.ProviderPath)`""
    [Console]::Write("`e[?25l"); $W = 0; $H = 0
    # o painel de cima e so para ver: Ctrl+C nao o interrompe e qualquer tecla devolve o foco ao shell de baixo
    # (desliga-se com "pin" no shell de baixo, ou fechando o painel)
    [Console]::TreatControlCAsInput = $true
    # foco: o ConPTY converte o "ganhou foco" do terminal num FOCUS_EVENT na fila da consola (com a entrada VT desligada);
    # Drain le a fila toda e diz se o painel ganhou o foco ou recebeu uma tecla -> devolve-se o foco ao shell de baixo
    if (-not ('Pin.In' -as [type])) {
        Add-Type -Namespace Pin -Name In -MemberDefinition @'
[StructLayout(LayoutKind.Explicit, Size = 20)] public struct IR { [FieldOffset(0)] public ushort Type; [FieldOffset(4)] public int Down; }
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
[DllImport("kernel32.dll")] static extern bool GetNumberOfConsoleInputEvents(IntPtr h, out uint n);
[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool ReadConsoleInputW(IntPtr h, [Out] IR[] b, uint n, out uint r);
public static bool Drain(IntPtr h) {
    bool hit = false; var b = new IR[32]; uint n, got;
    while (GetNumberOfConsoleInputEvents(h, out n) && n > 0 && ReadConsoleInputW(h, b, 32, out got) && got > 0)
        for (int i = 0; i < got; i++) if ((b[i].Type == 1 || b[i].Type == 0x10) && b[i].Down != 0) hit = true;   // tecla premida / ganhou foco
    return hit;
}
'@
    }
    $inH = [Pin.In]::GetStdHandle(-10); $mode = 0; [void][Pin.In]::GetConsoleMode($inH, [ref]$mode)
    [void][Pin.In]::SetConsoleMode($inH, ($mode -band (-bnot 0x200)))   # sem entrada VT: o foco chega como evento
    try {
        while ($true) {
            if (Test-Path $stop) { break }
            # fecha quando ja nao ha nenhum shell em baixo (o do pin e os splits do Ctrl+D)
            if (Test-Path $shellFile) { if (-not (Get-Process -Id ([int[]]@(Get-Content $shellFile)) -ErrorAction SilentlyContinue)) { break } }
            if ([Pin.In]::Drain($inH)) { Start-Process $wt -ArgumentList '-w', '0', 'move-focus', 'down' }
            # pedidos do shell de baixo (ff-bar-<pid>.cmd): "ff" = redesenhar, "ffw" = liga/desliga o modo ao vivo
            if (Test-Path $cmdFile) {
                $cmd = "$(Get-Content $cmdFile -ErrorAction SilentlyContinue)".Trim(); Remove-Item $cmdFile -ErrorAction SilentlyContinue
                if ($cmd -eq 'ffw') { $live = -not $live }
                $W = 0   # (forca o redesenho abaixo)
            }
            # o painel encolheu (split) ou mudou de tamanho: espera que estabilize e redesenha
            if ([Console]::WindowWidth -ne $W -or [Console]::WindowHeight -ne $H) {
                if ($W) { Start-Sleep -Milliseconds 250 }; $W = [Console]::WindowWidth; $H = [Console]::WindowHeight
                ff -Bar; [Console]::Write("`e[?25l"); $tick = [Diagnostics.Stopwatch]::StartNew()
            }
            elseif ($live -and $tick.ElapsedMilliseconds -ge 2000) {
                # ao vivo: o fastfetch volta a correr e escreve por cima (sem limpar o ecra -> nao pisca); ESC[K apaga restos
                Update-TsCache 5
                # (captura em UTF-8: com a codificacao da consola os blocos do logo viravam "?")
                $enc = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); Push-Location $HOME
                try { $ffo = @(fastfetch --pipe false 2>$null) } finally { Pop-Location; [Console]::OutputEncoding = $enc }
                [Console]::Write("`e[?2026h`e[H" + (($ffo | ForEach-Object { "$_`e[K" }) -join "`n")); Show-Cheats; [Console]::Write("`e[?2026l")
                $tick.Restart()
            }
            Start-Sleep -Milliseconds 200
        }
    } finally { Remove-Item $stop, $shellFile, $cmdFile -ErrorAction SilentlyContinue; [Console]::Write("`e[?25h") }
    # fecha o processo (e o painel): um "exit" aqui so sairia do perfil quando o pin corre no arranque (pin por omissao)
    [Environment]::Exit(0)
}
function ff {
    # -Bar: painel do pin (sem minimo de altura: o painel tem a altura do fastfetch; sem linha separadora nem
    # quebra de linha no fim, que faria o painel subir uma linha e cortar o topo)
    param([switch]$Bar, [Parameter(ValueFromRemainingArguments)]$Rest)
    # ssh vindo de um painel com pin (o cabecalho ja esta la em cima): so limpa (o prompt ja diz "ssh")
    if (-not $Bar -and $env:KVN_COMPACT) { Clear-Host; $global:FfClean = $false; return }
    # shell de baixo do pin (cabecalho ja esta no painel de cima): clear / Ctrl+L / ff so limpam
    # (e pede ao painel de cima para redesenhar o fastfetch)
    if (-not $Bar -and $global:FfBarPid -and (Get-Process -Id $global:FfBarPid -ErrorAction SilentlyContinue)) {
        Set-Content "$env:TEMP\ff-bar-$($global:FfBarPid).cmd" 'ff'; Clear-Host; $global:FfClean = $false; return
    }
    Clear-FfRegion; $global:FfTop = $null
    Update-TsCache; Clear-Host
    # so em paineis com espaco (o 1.o split lado a lado ainda tem; do 3.o painel em diante fica so o prompt)
    if ([Console]::WindowWidth -ge 90 -and ($Bar -or [Console]::WindowHeight -ge 24)) {
        Push-Location $HOME; try { fastfetch @Rest } finally { Pop-Location }   # (numa pasta de rede, o cmd dos modulos queixa-se do caminho UNC)
        Show-Cheats
        # a coluna da direita pode ser mais alta que o fastfetch. (Nunca para la do fundo do painel: num painel mais baixo
        # que a coluna o cursor nunca chegava la e o ciclo nao acabava - o cabecalho do WezTerm ficava em branco)
        while ([Console]::CursorTop -lt $global:CheatRows -and [Console]::CursorTop -lt [Console]::WindowHeight - 1) { [Console]::WriteLine() }
        if (-not $Bar) { [Console]::WriteLine("`e[90m" + ([string][char]0x2500 * [Console]::WindowWidth) + "`e[0m") }   # linha a separar do prompt
        $global:FfTop = [Console]::CursorTop + 1   # 1.a linha da regiao de scroll (a do prompt)
    }
    $global:FfSize = "$([Console]::WindowWidth)x$([Console]::WindowHeight)"   # tamanho com que se desenhou (ver OnIdle)
    $global:FfClean = $true
}
# cache do Tailscale para o fastfetch: atualiza em segundo plano se tiver > 60 s (o 'tailscale status' demora ~1 s)
function Update-TsCache([int]$MaxAge = 30) {
    $tsc = "$env:LOCALAPPDATA\pwsh-init-cache\ts1.txt"
    if (-not (Test-Path $tsc) -or ([datetime]::Now - [IO.File]::GetLastWriteTime($tsc)).TotalSeconds -gt $MaxAge) {
        [Diagnostics.Process]::Start('wscript.exe', "`"$HOME\.config\ts-cache.vbs`"") | Out-Null
    }
}
# (no WezTerm o cabecalho ja a mantem a cada 5 s: lancar o processo aqui custava ~70 ms a cada separador novo)
if (-not $env:WEZTERM_PANE) { Update-TsCache }
# página inicial do 'yt' preparada em segundo plano (para abrir logo); só com sessão iniciada e se tiver > 15 min
$ytc = "$env:TEMP\yt\home-cache.txt"
if ((Test-Path "$HOME\.config\yt-cookies.txt") -and (-not (Test-Path $ytc) -or ([datetime]::Now - [IO.File]::GetLastWriteTime($ytc)).TotalMinutes -gt 15)) {
    Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$HOME\.config\yt-prefetch.ps1" -WindowStyle Hidden
}
# ---- separadores: ao reabrir o Windows Terminal (reiniciar o PC, crash) volta as pastas onde estavas ----
# cada painel guarda "<pid do WT>|<pasta>" em %LOCALAPPDATA%\kvn-tabs\<WT_SESSION>.txt (o prompt atualiza-o quando
# se muda de pasta; sai ao fazer exit). O 1.o painel de um WT novo ve os ficheiros de um WT que ja nao existe:
# fica ele com a 1.a pasta e abre as outras em separadores novos. (O WT fica vivo escondido: so conta apos reiniciar.)
$TabsDir = "$env:LOCALAPPDATA\kvn-tabs"; $global:TabFile = $null
if ($env:WT_SESSION -and -not $env:SSH_CONNECTION -and -not $env:KVN_CMD -and -not [Console]::IsOutputRedirected) {
    $wtp = (Get-Process -Id $PID).Parent
    if ($wtp.ProcessName -eq 'WindowsTerminal') {
        New-Item -ItemType Directory $TabsDir -Force | Out-Null
        $global:TabFile = "$TabsDir\$($env:WT_SESSION).txt"; $global:TabWt = $wtp.Id
        $dead = @(Get-ChildItem $TabsDir -Filter *.txt | ForEach-Object {
                $w, $d = "$(Get-Content $_.FullName -Raw)".Trim() -split '\|', 2
                $alive = Get-Process -Id ([int]$w) -ErrorAction SilentlyContinue
                if ([int]$w -ne $wtp.Id -and -not ($alive -and $alive.ProcessName -eq 'WindowsTerminal')) { [pscustomobject]@{ f = $_; dir = $d; recent = $_.LastWriteTime -gt (Get-Date).AddDays(-2) } }
            })
        $dirs = @($dead | Where-Object { $_.recent -and $_.dir -and (Test-Path -LiteralPath $_.dir) } | Sort-Object { $_.f.LastWriteTime } | ForEach-Object dir | Select-Object -Unique | Select-Object -First 8)
        $dead | ForEach-Object { Remove-Item $_.f.FullName -ErrorAction SilentlyContinue }
        if ($dirs) {
            Set-Location -LiteralPath $dirs[0]
            $wtExe = @("$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe", "$HOME\.local\terminal\wt.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
            foreach ($d in ($dirs | Select-Object -Skip 1)) { Start-Process $wtExe -ArgumentList '-w', '0', 'nt', '-d', "`"$d`"" }
        }
        $null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { if ($global:TabFile) { Remove-Item $global:TabFile -ErrorAction SilentlyContinue } }
    }
}
$pend = "$env:TEMP\ff-bar-pending"
if ((Test-Path $pend) -and ((Get-Date) - (Get-Item $pend).LastWriteTime).TotalSeconds -lt 15) {
    # painel de baixo de um "pin": o cabecalho ja esta em cima; regista-se para o cabecalho fechar quando este fechar
    $global:FfBarPid = [int](Get-Content $pend); Remove-Item $pend; $global:FfBarLive = $true
    Add-Content "$env:TEMP\ff-bar-$($global:FfBarPid).shell" $PID; Clear-Host   # (um PID por linha: o Ctrl+D junta mais shells em baixo)
}
elseif (-not [Console]::IsOutputRedirected -and -not $env:KVN_CMD) {
    # pin por omissao: separador novo com altura para o cabecalho + shell (os splits pequenos do Ctrl+D ficam normais).
    # O pin corre no fim do perfil (precisa das funcoes definidas mais abaixo); aqui so se decide.
    $global:AutoPin = $env:WT_SESSION -and -not $env:SSH_CONNECTION -and [Console]::WindowHeight -ge 30 -and [Console]::WindowWidth -ge 160
    # (WezTerm: o fastfetch esta no cabecalho e o painel nasce vazio: nem o Clear-Host, ~90 ms a cada separador novo)
    if ($env:WEZTERM_PANE -and $env:KVN_COMPACT) { $global:FfClean = $false } elseif (-not $global:AutoPin) { ff }   # Clear-Host tambem apaga o banner do pwsh
}
# clear / cls / Ctrl+L limpam mas voltam a mostrar o fastfetch
Remove-Item Alias:clear, Alias:cls -Force -ErrorAction SilentlyContinue
function clear { ff }
# reset como no Linux (o reset.exe do Windows e outra coisa: "reset session" do Ambiente de Trabalho Remoto): repoe o
# terminal - cores, cursor, rato, ecra alternativo, regiao de scroll deixados por uma app que rebentou - e limpa
function reset { [Console]::Write("$([char]27)c$([char]27)[?1049l$([char]27)[?1000l$([char]27)[?1003l$([char]27)[?1006l$([char]27)[r$([char]27)[0m$([char]27)[?25h"); ff }
# ao sair de uma sessao SSH interativa (ssh <host>), limpa logo o ecra
# ---- ssh desktop / ssh laptop: abre o pwsh do outro PC ('pwsh -NoLogo': sem o banner), com avisos claros ----
# (mesmo PC, sessao que ja vem de la, nome que nao resolve, desligado, sshd parado, chave recusada)
$SshHosts = @{}; foreach ($pc in $Pcs) { $SshHosts[$pc.name] = $pc.host }   # (nome do ssh -> nome no Tailscale)
# sempre o OpenSSH do Windows (o ssh do Git, se vier primeiro no PATH, nao tem as chaves)
$SshExe = "$env:WINDIR\System32\OpenSSH\ssh.exe"; $ScpExe = "$env:WINDIR\System32\OpenSSH\scp.exe"
function Write-Warn($m, $hint) { $e = [char]27; Write-Host "$e[33m! $e[97m$m$e[0m"; if ($hint) { Write-Host "  $e[90m$hint$e[0m" } }
function Get-OtherPc { $SshHosts.Keys | Where-Object { $SshHosts[$_] -ne $env:COMPUTERNAME } | Select-Object -First 1 }
function Test-SshPeer([string]$name, [switch]$NotOrigin) {
    # o outro PC esta pronto para SSH? senao diz porque (e devolve $false)
    $hn = $SshHosts[$name]
    if (-not $hn) { Write-Warn "unknown PC '$name'" "PCs: $($SshHosts.Keys -join ', ')"; return $false }
    if ($hn -eq $env:COMPUTERNAME) { Write-Warn "you're already on $name" $(if ($env:SSH_CONNECTION) { 'ctrl+w (or exit) goes back to the PC you came from' }); return $false }
    $ips = try { @([Net.Dns]::GetHostAddresses($hn) | ForEach-Object IPAddressToString) } catch { @() }
    if (-not $ips) { Write-Warn "can't find $name on the network" 'is Tailscale running on both PCs? (tailscale status)'; return $false }
    if ($NotOrigin -and $env:SSH_CONNECTION -and (($env:SSH_CONNECTION -split ' ')[0] -in $ips)) { Write-Warn "this session already comes from $name" 'ctrl+w (or exit) goes back there'; return $false }
    # porta 22 (1,5 s); se falhar, o Tailscale diz se o PC esta ligado (o ping costuma estar bloqueado no Windows)
    $tcp = [Net.Sockets.TcpClient]::new()
    $ok = try { $tcp.ConnectAsync($hn, 22).Wait(1500) -and $tcp.Connected } catch { $false } finally { $tcp.Dispose() }
    if (-not $ok) {
        $peer = try { (tailscale status --json | ConvertFrom-Json).Peer.PSObject.Properties.Value | Where-Object { $_.HostName -eq $hn } | Select-Object -First 1 } catch { $null }
        if ($peer -and $peer.Online) { Write-Warn "$name is on but not accepting SSH" "its SSH server is off or not installed: on $name, setup > Tailscale > the SSH server step" }
        else { Write-Warn "$name is off, asleep or offline" $(if ($WakeMacs[$name]) { "to wake it: wake $name" }) }
        return $false
    }
    $true
}
function ssh {
    # (o nome do PC no Tailscale tambem serve: ssh <nome no tailscale> = ssh <nome>)
    $name = "$($args[0])"
    if ($args.Count -eq 1 -and -not $SshHosts.ContainsKey($name)) { $hit = @($SshHosts.Keys | Where-Object { $SshHosts[$_] -eq ($name -replace '\..*$') }); if ($hit) { $name = $hit[0] } }
    if ($args.Count -ne 1 -or -not $SshHosts.ContainsKey($name)) { & $SshExe @args; return }
    if (-not (Test-SshPeer $name -NotOrigin)) { return }
    # com o pin ligado ja ha um cabecalho no painel de cima: o outro PC mostra so uma linha (KVN_COMPACT), nao o fastfetch
    $pinned = Test-HeaderPane
    # (SUPERTERMINAL=1: o perfil do outro PC so carrega dentro do SuperTerminal; o ssh nao leva o ambiente, vai no comando)
    $remote = if ($SshShell[$name] -eq 'cmd') { "set SUPERTERMINAL=1&& $(if ($pinned) { 'set KVN_COMPACT=1&& ' })pwsh -NoLogo" } else { "`$env:SUPERTERMINAL = '1'; $(if ($pinned) { "`$env:KVN_COMPACT = '1'; " })pwsh -NoLogo" }
    Clear-FfRegion; & $SshExe -t $name $remote
    if ($LASTEXITCODE -eq 255) { Write-Warn "connection to $name failed" "key rejected? here: setup > Tailscale > copy my key (or on $name, its SSH server step)" }
    ff
}

# ---- get / send / rls: ficheiros entre os dois PCs (scp pela mesma ligacao do ssh, com os mesmos avisos) ----
#   get <caminho no outro PC> [pasta aqui]     traz (ficheiro, pasta ou *) -> por omissao as Transferencias deste PC
#   send <caminho aqui> [pasta no outro PC]    manda -> por omissao as Transferencias do outro PC
#   rls [pasta no outro PC]                    lista (para saber o caminho a pedir)
# Caminhos no outro PC: relativos a home dele (Downloads\x.zip), absolutos (D:\musica\y.wav) ou com ~ ; aceita * (get Downloads\*.pdf)
# Opcoes: -From/-To/-On desktop|laptop (por omissao: o outro PC)   get -Open abre a pasta no fim   rls -All mostra os escondidos
function Get-DownloadsDir { (New-Object -ComObject Shell.Application).Namespace('shell:Downloads').Self.Path }
function ConvertTo-ScpPath([string]$p) { $p.Trim().Trim('"').Replace('\', '/') }   # (o scp do Windows usa SFTP: sem aspas, / em vez de \)
$PcIcon = @{ desktop = [char]0xf108; laptop = [char]0xf109 }
# nome e icone de um PC para os titulos (ls, rls, get / send); sem ele no pcs.json (PC novo, ainda sem setup) = o deste
function Get-PcLabel([string]$pc) { if ($pc -and $SshHosts[$pc]) { "$($SshHosts[$pc])".ToLower() } else { $env:COMPUTERNAME.ToLower() } }
function Get-PcIcon([string]$pc) { if ($pc -and $PcIcon[$pc]) { $PcIcon[$pc] } elseif ($pc -match 'lap|book|note') { [char]0xf109 } else { [char]0xf108 } }
function Get-FileIcon([string]$name, [bool]$dir) {
    if ($dir) { return "`e[34m$([char]0xf07b)" }
    switch -Regex ([IO.Path]::GetExtension($name).ToLower()) {
        '^\.(jpe?g|png|gif|webp|avif|heic|bmp|svg|ico)$' { return "`e[35m$([char]0xf1c5)" }
        '^\.(mp4|mkv|avi|mov|webm|m4v|wmv)$' { return "`e[31m$([char]0xf1c8)" }
        '^\.(mp3|wav|flac|m4a|ogg|aac|flp|mid)$' { return "`e[36m$([char]0xf1c7)" }
        '^\.(zip|rar|7z|tar|gz|xz|iso)$' { return "`e[33m$([char]0xf1c6)" }
        '^\.pdf$' { return "`e[31m$([char]0xf1c1)" }
        '^\.(exe|msi|bat|cmd|lnk)$' { return "`e[32m$([char]0xf013)" }
        '^\.(ps1|py|js|ts|json|cs|cpp|c|h|lua|sh|html|css|xml|yml|yaml)$' { return "`e[33m$([char]0xf1c9)" }
        '^\.(txt|md|docx?|odt|rtf|log|csv|xlsx?)$' { return "`e[37m$([char]0xf15c)" }
    }
    "`e[37m$([char]0xf15b)"
}
function Format-Size([double]$b) { if ($b -ge 1GB) { '{0:0.0} GB' -f ($b / 1GB) } elseif ($b -ge 1MB) { '{0:0.0} MB' -f ($b / 1MB) } elseif ($b -ge 1KB) { '{0:0} KB' -f ($b / 1KB) } else { "$([int]$b) B" } }
function Format-Link([string]$path) { "`e]8;;file:///$($path.Replace('\', '/'))`e\$path`e]8;;`e\" }   # ctrl+clique no Windows Terminal abre
# shell do ssh de cada PC (o DefaultShell do OpenSSH de la; sem saber, cmd - que funciona com os dois)
$SshShell = @{}; foreach ($pc in $Pcs) { $SshShell[$pc.name] = $(if ($pc.shell) { $pc.shell } else { 'cmd' }) }
function Invoke-Remote([string]$pc, [string]$ps) {
    # corre PowerShell no outro PC, codificado (sem problemas de aspas). Se o shell do SSH de la ja e o pwsh, corre
    # direto nele (~0,4 s mais rapido); se e o cmd (laptop), arranca um pwsh
    $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ps))
    $cmd = if ($SshShell[$pc] -eq 'pwsh') { "& ([scriptblock]::Create([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$b64'))))" } else { "pwsh -NoProfile -NonInteractive -EncodedCommand $b64" }
    @(& $SshExe -n $pc $cmd 2>$null)
}
function Get-RemoteInfo([string]$pc, [string]$path) {
    # tamanho total, n. de ficheiros, se e uma pasta e o caminho completo (aceita *); $null se nao existir
    $ps = "Set-Location `$HOME; `$p = '$($path.Replace("'", "''"))'; `$it = @(Get-Item -Path `$p -Force -ErrorAction SilentlyContinue); if (-not `$it) { exit 1 }; " +
    "`$f = @(`$it | ForEach-Object { if (`$_.PSIsContainer) { Get-ChildItem -LiteralPath `$_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue } else { `$_ } }); " +
    "'{0}|{1}|{2}|{3}' -f [double](`$f | Measure-Object Length -Sum).Sum, `$f.Count, [int](`$it.Count -eq 1 -and `$it[0].PSIsContainer), `$(if (`$it.Count -eq 1) { `$it[0].FullName } else { Join-Path (Split-Path `$it[0].FullName) (Split-Path `$p -Leaf) })"
    $o = Invoke-Remote $pc $ps | Select-Object -Last 1
    if ("$o" -notmatch '\|') { return $null }
    $s, $n, $d, $full = "$o" -split '\|', 4
    @{ size = [double]$s; count = [int]$n; dir = $d -eq '1'; full = $full }
}
function Show-XferHead($from, $to, [string]$what, [bool]$dir, $info) {
    $n = if ($dir -or $info.count -gt 1) { "$($info.count) files  `e[90m$([char]0x00B7)`e[0m  " } else { '' }
    Write-Host ''
    Write-Host "  `e[90m$(Get-PcIcon $from)  $(Get-PcLabel $from)`e[0m  `e[90m$([char]0x2192)`e[0m  `e[1;97m$(Get-PcIcon $to)  $(Get-PcLabel $to)`e[0m"
    Write-Host "  $(Get-FileIcon $what $dir)`e[0m  `e[97m$what`e[0m   `e[90m$n$(Format-Size $info.size)`e[0m"
}
function Invoke-Xfer([string[]]$scpArgs, [double]$total, [scriptblock]$measure, [int]$everyMs = 250) {
    # scp em segundo plano e uma barra de progresso propria (o $measure diz quanto ja chegou)
    $err = [IO.Path]::GetTempFileName()
    $q = $scpArgs | ForEach-Object { if ("$_" -match '\s') { "`"$_`"" } else { "$_" } }
    $p = Start-Process $ScpExe -ArgumentList (@('-q', '-r', '-o', 'BatchMode=yes') + $q) -NoNewWindow -PassThru -RedirectStandardError $err
    $sw = [Diagnostics.Stopwatch]::StartNew(); $w = 28; $cur = 0; $last = -10000
    [Console]::Write("`e[?25l")
    while (-not $p.HasExited) {
        if ($sw.ElapsedMilliseconds - $last -ge $everyMs) { $last = $sw.ElapsedMilliseconds; $cur = [double](& $measure) }
        $f = if ($total -gt 0) { [Math]::Min(1, $cur / $total) } else { 0 }; $k = [int]($w * $f)
        $spd = if ($sw.Elapsed.TotalSeconds -gt 0.5) { $cur / $sw.Elapsed.TotalSeconds } else { 0 }
        $eta = if ($spd -gt 0 -and $total -gt $cur) { [TimeSpan]::FromSeconds(($total - $cur) / $spd).ToString('m\:ss') } else { '' }
        [Console]::Write("`r  `e[34m" + ([string][char]0x2501 * $k) + "`e[90m" + ([string][char]0x2500 * ($w - $k)) + ("`e[0m  {0,3}%  `e[90m{1} / {2}   {3}/s   {4}`e[0m`e[K" -f [int]($f * 100), (Format-Size $cur), (Format-Size $total), (Format-Size $spd), $eta))
        Start-Sleep -Milliseconds 100
    }
    [void]$p.WaitForExit(3000)   # (com limite: sem ele espera que o ssh filho do scp feche o stderr redirecionado, e pode ficar preso)
    $t = $sw.Elapsed.TotalSeconds; $code = $p.ExitCode
    $msg = (Get-Content $err -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch 'quantum|store now|server may' }) -join ' '; Remove-Item $err -ErrorAction SilentlyContinue
    [Console]::Write("`r`e[K`e[?25h")
    if ($code) { return @{ ok = $false; msg = $msg } }
    $spd = if ($t -gt 0) { $total / $t } else { 0 }
    Write-Host ("  `e[32m$([char]0x2713)`e[0m `e[97m{0}`e[0m in {1}   `e[90m({2}/s)`e[0m" -f (Format-Size $total), $(if ($t -lt 60) { '{0:0.0} s' -f $t } else { [TimeSpan]::FromSeconds($t).ToString('m\:ss') }), (Format-Size $spd))
    @{ ok = $true }
}
function Show-XferHelp([string]$cmd) {
    $o = Get-OtherPc; $h = [string][char]0x2500
    $rows = switch ($cmd) {
        'get' { @("copy from $o to here (Downloads)", '', "`e[97mget `e[36m<path on $o> `e[90m[folder here] [-Open]", '', "`e[90mget `e[37mDownloads\foto.jpg", "`e[90mget `e[37mD:\projects\game `e[36mC:\work", "`e[90mget `e[37mDownloads\*.pdf `e[36m-Open", '', "`e[90mdon't know the path?  `e[37mrls `e[90mor `e[37mrls Downloads") }
        'send' { @("copy from here to $o (its Downloads)", '', "`e[97msend `e[36m<path here> `e[90m[folder on $o]", '', "`e[90msend `e[37m.\video.mp4", "`e[90msend `e[37mC:\photos\trip `e[36mD:\backup", "`e[90msend `e[37m*.wav `e[36mDocuments\audio") }
    }
    Write-Host ''
    Write-Host "  `e[90m$([char]0x256D)$h `e[1;97m$cmd`e[0;90m $($h * 46)$([char]0x256E)`e[0m"
    foreach ($r in $rows) { $plain = $r -replace "`e\[[\d;]*m", ''; Write-Host ("  `e[90m$([char]0x2502)`e[0m  `e[37m$r`e[0m" + (' ' * [Math]::Max(1, 50 - $plain.Length)) + "`e[90m$([char]0x2502)`e[0m") }
    Write-Host "  `e[90m$([char]0x2570)$($h * 53)$([char]0x256F)`e[0m"
}
function get {
    param([string]$Path, [string]$Dest, [string]$From, [switch]$Open)
    if (-not $Path) { Show-XferHelp 'get'; return }
    if (-not $From) { $From = Get-OtherPc }
    if (-not (Test-SshPeer $From)) { return }
    $info = Get-RemoteInfo $From $Path
    if (-not $info) { Write-Warn "'$Path' doesn't exist on $From" "see what's there: rls $(Split-Path $Path -Parent)"; return }
    if (-not $Dest) { $Dest = Get-DownloadsDir }
    $Dest = [IO.Path]::GetFullPath($Dest, $PWD.Path)
    if (-not (Test-Path $Dest)) { New-Item -ItemType Directory $Dest -Force | Out-Null }
    $leaf = Split-Path ($Path.TrimEnd('\', '/')) -Leaf; $target = Join-Path $Dest $leaf
    Show-XferHead $From (Get-PcName) $leaf $info.dir $info
    $r = Invoke-Xfer @("${From}:$(ConvertTo-ScpPath $Path)", $Dest) $info.size { [double](Get-ChildItem -Path $target -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }
    if (-not $r.ok) { Write-Warn "couldn't copy '$Path' from $From" $r.msg; return }
    $shown = if ($leaf -match '[*?]') { $Dest } else { $target }
    Write-Host "  `e[90m$([char]0x2192)`e[0m $(Format-Link $shown)"
    if ($Open) { if (Test-Path -LiteralPath $target) { explorer.exe /select, "$target" } else { explorer.exe "$Dest" } }
}
function send {
    param([string]$Path, [string]$Dest = 'Downloads', [string]$To)
    if (-not $Path) { Show-XferHelp 'send'; return }
    $items = @(Resolve-Path $Path -ErrorAction SilentlyContinue | ForEach-Object { Get-Item -LiteralPath $_.ProviderPath -Force })
    if (-not $items) { Write-Warn "'$Path' not found on this PC"; return }
    if (-not $To) { $To = Get-OtherPc }
    if (-not (Test-SshPeer $To)) { return }
    $files = @($items | ForEach-Object { if ($_.PSIsContainer) { Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Force } else { $_ } })
    $info = @{ size = [double]($files | Measure-Object Length -Sum).Sum; count = $files.Count }
    $rd = ConvertTo-ScpPath $Dest
    $null = Invoke-Remote $To "New-Item -ItemType Directory -Force -Path (Join-Path `$HOME '$($Dest.Replace("'", "''"))') -ErrorAction SilentlyContinue | Out-Null; Set-Location `$HOME; New-Item -ItemType Directory -Force -Path '$($Dest.Replace("'", "''"))' -ErrorAction SilentlyContinue | Out-Null"
    $what = if ($items.Count -eq 1) { $items[0].Name } else { Split-Path $Path -Leaf }
    Show-XferHead (Get-PcName) $To $what ($items.Count -eq 1 -and $items[0].PSIsContainer) $info
    # progresso: o que ja esta do lado de la (perguntado de ~1 em 1 s)
    $names = ($items | ForEach-Object { "'" + $_.Name.Replace("'", "''") + "'" }) -join ','
    $probe = "Set-Location `$HOME; `$d = '$($Dest.Replace("'", "''"))'; [double](@($names) | ForEach-Object { Get-ChildItem -LiteralPath (Join-Path `$d `$_) -Recurse -File -Force -ErrorAction SilentlyContinue } | Measure-Object Length -Sum).Sum"
    $r = Invoke-Xfer (@($items.FullName) + "${To}:$rd/") $info.size { [double]"0$(Invoke-Remote $To $probe | Select-Object -Last 1)" } 1000
    if (-not $r.ok) { Write-Warn "couldn't copy to $To" $r.msg; return }
    Write-Host "  `e[90m$([char]0x2192) on $To in`e[0m $Dest"
}
function Get-PcName { $SshHosts.Keys | Where-Object { $SshHosts[$_] -eq $env:COMPUTERNAME } | Select-Object -First 1 }
function rls {
    param([string]$Path = '.', [string]$On, [switch]$All)
    if (-not $On) { $On = Get-OtherPc }
    if (-not (Test-SshPeer $On)) { return }
    $f = if ($All) { '-Force' } else { '' }
    $ps = "Set-Location `$HOME; `$p = '$($Path.Replace("'", "''"))'; if (-not (Test-Path -LiteralPath `$p)) { exit 1 }; (Resolve-Path -LiteralPath `$p).Path; " +
    "Get-ChildItem -LiteralPath `$p $f | Sort-Object { -not `$_.PSIsContainer }, Name | ForEach-Object { '{0}|{1}|{2}' -f `$(if (`$_.PSIsContainer) { 'd' } else { `$_.Length }), `$_.LastWriteTime.ToString('dd/MM/yy HH:mm'), `$_.Name }"
    $out = Invoke-Remote $On $ps
    if (-not $out) { Write-Warn "'$Path' doesn't exist on $On" 'try: rls  (home)  or  rls Downloads'; return }
    $rows = @($out | Select-Object -Skip 1 | ForEach-Object { $s, $d, $n = $_ -split '\|', 3; @{ dir = $s -eq 'd'; size = $(if ($s -ne 'd') { [double]$s } else { 0 }); date = $d; name = $n } } | Where-Object { $All -or -not $_.name.StartsWith('.') })
    Show-Listing $On $out[0] $rows
}
function Show-Listing([string]$pc, [string]$full, $rows) {
    # listagem do ls e do rls: PC + caminho + total, depois icone, nome, tamanho, data
    $tot = ($rows | Where-Object { -not $_.dir } | Measure-Object { $_.size } -Sum).Sum
    $cw = try { [Console]::WindowWidth } catch { if ($env:COLUMNS) { [int]$env:COLUMNS } else { 120 } }   # (vindo do WSL nao ha consola: o zsh passa COLUMNS)
    $nw = [Math]::Max(20, [Math]::Min(56, $cw - 40))
    Write-Host ''
    Write-Host "  `e[1;97m$(Get-PcIcon $pc)  $(Get-PcLabel $pc)`e[0m  `e[37m$full`e[0m   `e[90m$($rows.Count) items$(if ($tot) { "  $([char]0x00B7)  $(Format-Size $tot)" })`e[0m"
    Write-Host "  `e[90m$([string][char]0x2500 * ($nw + 30))`e[0m"
    foreach ($x in $rows) {
        $nm = if ($x.name.Length -gt $nw) { $x.name.Substring(0, $nw - 1) + [char]0x2026 } else { $x.name }
        $sz = if ($x.dir) { '' } else { Format-Size $x.size }
        $nc = if ($x.dir) { '1;34' } else { '0;97' }
        Write-Host ("  {0}`e[0m  `e[{1}m{2}`e[0m  `e[36m{3,9}`e[0m  `e[90m{4}`e[0m" -f (Get-FileIcon $x.name $x.dir), $nc, $nm.PadRight($nw), $sz, $x.date)
    }
    if (-not $rows) { Write-Host "  `e[90m(empty)`e[0m" }
    Write-Host ''
}
function ls {
    # igual ao rls, mas deste PC:  ls [pasta] [-a]   (ll / lt continuam no eza)
    param([string]$Path = '.', [Alias('a')][switch]$All)
    # flags Linux (ls -la, ls -lh...) -> o ls verdadeiro do uutils
    if ($args -and $UuDir) { & "$UuDir\ls.exe" @args $(if ($PSBoundParameters.ContainsKey('Path')) { $Path }); return }
    $p = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $p) { Write-Warn "'$Path' doesn't exist"; return }
    # dotfiles escondidos como no Linux (.claude.json/.gitconfig sao regravados e perdem o atributo "oculto"); -a mostra tudo
    $items = Get-ChildItem -LiteralPath $p.ProviderPath -Force:$All -ErrorAction SilentlyContinue | Where-Object { $All -or -not $_.Name.StartsWith('.') } | Sort-Object { -not $_.PSIsContainer }, Name
    $rows = @($items | ForEach-Object { @{ dir = $_.PSIsContainer; size = $(if ($_.PSIsContainer) { 0 } else { [double]$_.Length }); date = $_.LastWriteTime.ToString('dd/MM/yy HH:mm'); name = $_.Name } })
    # partilha de rede (\\<ip do PC>\d\x): mostra o PC dono e "D:\x", como o prompt
    $pc = Get-PcName; $show = $p.ProviderPath
    $unc = if ($p.Drive.DisplayRoot) { $p.Drive.DisplayRoot + $p.ProviderPath.Substring(2) } elseif ($show -like '\\*') { $show }
    if ($unc -match '^\\\\([^\\]+)\\([^\\]+)(.*)$') {
        $owner = $SshHosts.Keys | Where-Object { $SshHosts[$_].ToLower() -eq $NetHostNames[$Matches[1]] } | Select-Object -First 1
        if ($owner) { $pc = $owner }
        $show = $(if ($Matches[2].Length -eq 1) { "$($Matches[2].ToUpper()):" } else { $Matches[2] }) + $(if ($Matches[3]) { $Matches[3] } else { '\' })
    }
    Show-Listing $pc $show $rows
}
# Tab no rls / get completa com as pastas e ficheiros do outro PC (cada pasta fica em cache 30 s)
$RemoteDirCache = @{}
Register-ArgumentCompleter -CommandName rls, get -ParameterName Path -ScriptBlock {
    param($cmd, $param, $word, $ast, $bound)
    $pc = if ($bound.From) { $bound.From } elseif ($bound.On) { $bound.On } else { Get-OtherPc }
    $w = "$word".Trim("'", '"').Replace('/', '\')
    $dir = if ($w.EndsWith('\')) { $w.TrimEnd('\') } elseif ($w.Contains('\')) { Split-Path $w } else { '' }
    $pre = if ($w.EndsWith('\')) { '' } else { Split-Path $w -Leaf }
    $key = "$pc|$dir"
    $c = $RemoteDirCache[$key]
    if (-not $c -or ([datetime]::Now - $c.t).TotalSeconds -gt 30) {
        $ps = "Set-Location `$HOME; `$p = '$(if ($dir) { $dir.Replace("'", "''") } else { '.' })'; Get-ChildItem -LiteralPath `$p -ErrorAction SilentlyContinue | ForEach-Object { `$(if (`$_.PSIsContainer) { 'd|' } else { 'f|' }) + `$_.Name }"
        $c = @{ t = [datetime]::Now; items = @(Invoke-Remote $pc $ps) }; $RemoteDirCache[$key] = $c
    }
    foreach ($i in $c.items) {
        $k, $n = "$i" -split '\|', 2
        if ($n -notlike "$pre*") { continue }
        $full = if ($dir) { "$dir\$n" } else { $n }; if ($k -eq 'd') { $full += '\' }
        $txt = if ($full -match '\s') { "'$full'" } else { $full }
        [Management.Automation.CompletionResult]::new($txt, $n + $(if ($k -eq 'd') { '\' }), 'ParameterValue', $full)
    }
}

# cpwd: copia a pasta atual (ou o caminho completo de um ficheiro) para a area de transferencia
# (dentro de um ssh, vai para o PC onde estas, pelo proprio terminal: OSC 52)
# ---- completar (Tab / Ctrl+Espaco) nos programas que nao o trazem: git, gh, winget ----
# git: subcomandos; branches (switch, checkout, merge, rebase, branch, cherry-pick, reset, diff, log, show, worktree);
# remoto e branch (push, pull, fetch); ficheiros alterados (add, restore, rm, diff, commit). Sem nada a sugerir:
# o PowerShell completa com ficheiros.
$GitSubs = [ordered]@{
    add = 'stage changes'; branch = 'list / create / delete branches'; checkout = 'switch branch or restore files'; 'cherry-pick' = 'apply a commit here'
    clone = 'copy a repository'; commit = 'save staged changes'; diff = 'show changes'; fetch = 'download from a remote'; init = 'new repository'
    log = 'history'; merge = 'join a branch into this one'; pull = 'fetch + merge'; push = 'upload commits'; rebase = 'replay commits on another base'
    remote = 'manage remotes'; reset = 'move HEAD / unstage'; restore = 'discard / unstage file changes'; revert = 'undo a commit with a new one'
    show = 'show a commit'; stash = 'put changes aside'; status = 'what changed'; switch = 'change branch'; tag = 'tags'; worktree = 'extra working trees'
    blame = 'who changed each line'; clean = 'delete untracked files'; config = 'settings'; grep = 'search tracked files'; mv = 'move / rename'; rm = 'remove files'
}
Register-ArgumentCompleter -Native -CommandName git -ScriptBlock {
    param($word, $ast, $cursor)
    $els = @($ast.CommandElements | Where-Object { $_.Extent.EndOffset -le $cursor -or $_.Extent.Text -eq $word } | ForEach-Object { $_.Extent.Text })
    $idx = if ($word) { $els.Count - 1 } else { $els.Count }   # posicao da palavra a completar (0 = "git")
    $mk = { param($t, $tip, $type = 'ParameterValue') [Management.Automation.CompletionResult]::new($(if ($t -match '\s') { "'$t'" } else { $t }), $t, $type, $tip) }
    # subcomandos ja com o espaco a seguir (git sw + Tab -> "git switch ", pronto para o branch)
    if ($idx -le 1) { foreach ($k in $GitSubs.Keys) { if ($k -like "$word*") { [Management.Automation.CompletionResult]::new("$k ", $k, 'ParameterValue', $GitSubs[$k]) } }; return }
    $sub = $els[1]
    $branches = { git for-each-ref --format='%(refname:short)' refs/heads 2>$null }
    $remoteBr = { git for-each-ref --format='%(refname:short)' refs/remotes 2>$null | Where-Object { $_ -notlike '*/HEAD' } }
    $out = switch -Regex ($sub) {
        '^(switch|checkout)$' {
            # locais e, dos remotos, os que ainda nao existem aqui (sem o "origin/": o switch cria-os)
            $loc = @(& $branches); $loc
            & $remoteBr | ForEach-Object { $_ -replace '^[^/]+/', '' } | Where-Object { $_ -notin $loc } | Select-Object -Unique
        }
        '^(merge|rebase|cherry-pick|reset|log|show|diff|worktree|branch)$' { & $branches; & $remoteBr }
        '^(push|pull|fetch)$' { if ($idx -eq 2) { git remote 2>$null } else { & $branches } }
        '^(add|restore|rm|commit)$' { git status --porcelain 2>$null | ForEach-Object { $_.Substring(3).Trim('"') -replace '^.* -> ', '' } }
        '^remote$' { if ($idx -eq 2) { 'add', 'remove', 'rename', 'set-url', 'get-url', '-v' } else { git remote 2>$null } }
        '^stash$' { if ($idx -eq 2) { 'push', 'pop', 'apply', 'list', 'show', 'drop', 'clear' } }
    }
    foreach ($o in @($out | Where-Object { $_ -and $_ -like "$word*" } | Select-Object -Unique)) { & $mk $o $o }
}
# gh (GitHub CLI) e winget: completacao oficial deles (a do gh em cache, como a do zoxide)
if (Test-Path "$env:ProgramFiles\GitHub CLI\gh.exe") {
    $ghc = "$env:LOCALAPPDATA\pwsh-init-cache\gh.ps1"
    # (2>$null no pedido: o gh.exe escreve "Completion ended with directive..." no stderr, que aparecia no ecra)
    if (-not (Test-Path $ghc) -or ((Get-Date) - (Get-Item $ghc).LastWriteTime).TotalDays -gt 7) {
        (& "$env:ProgramFiles\GitHub CLI\gh.exe" completion -s powershell | Out-String).Replace('$RequestComp="$Program __complete $Arguments"', '$RequestComp="$Program __complete $Arguments 2>`$null"') | Set-Content $ghc -Encoding utf8
    }
    try { . $ghc } catch { Remove-Item $ghc -ErrorAction SilentlyContinue }   # (cache estragada - dois shells a escreve-la ao mesmo tempo: refeita no proximo)
}
Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
    param($word, $ast, $cursor)
    [Console]::InputEncoding = [Console]::OutputEncoding = $OutputEncoding = [Text.UTF8Encoding]::new()
    winget complete --word="$word" --commandline "$ast" --position $cursor | ForEach-Object { [Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

function cpwd([string]$Path) {
    $p = if ($Path) { (Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue).ProviderPath } else { $PWD.ProviderPath }
    if (-not $p) { Write-Warn "'$Path' not found"; return }
    if ($env:SSH_CONNECTION) { [Console]::Write("`e]52;c;$([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($p)))`a") } else { Set-Clipboard $p }
    Write-Host "  `e[32m$([char]0x2713)`e[0m copied  `e[90m$p`e[0m"
}
function cls { ff }

# ---- Desktop: acordar (Wake-on-LAN, so na mesma rede) / suspender (S3) ----
# O desktop esta em Wi-Fi (Intel 8260): o magic packet so o acorda de suspensao (S3), nao desligado; e o router pode
# nao entregar broadcasts a um cliente Wi-Fi a dormir -> manda-se tambem direto ao IP local (guardado no suspend).
# ---- sync: o SuperTerminal na versao mais recente, em todos os PCs ----
# 1) vai buscar a versao mais recente ao GitHub (copia limpa do repo em ~\.local\superterminal\repo) e aplica-a
#    (install.ps1 -SkipApps: so os ficheiros; os pessoais - cookies, contas, pcs.json, o logo - ficam)
# 2) com Tailscale e outros PCs com nome (setup > Tailscale): manda-lhes essa versao por ssh (ramo sync-incoming na
#    copia deles; assim nao precisam de acesso ao GitHub) e cada um aplica-a. Sem outros PCs: so este.
# So a mao (sem modo automatico). "sync --status" so compara. "dot" = o git antigo do ~\.dotfiles
$DotGit = "$HOME\.dotfiles"; $SyncFlag = "$HOME\.config\sync-problem.txt"
function dot { git -C $HOME --git-dir=$DotGit --work-tree=$HOME @args }   # (-C: os caminhos sao sempre relativos a home, seja qual for a pasta atual)
$StRepo = "$HOME\.local\superterminal\repo"
$StRepoUrl = 'https://github.com/kevgoncalves/SuperTerminal.git'   # ponytail: o repo do Kev; com a config por pessoa (fase 1) passa a vir de la
function Update-SuperTerminal {
    # -Incoming: a versao que outro PC acabou de mandar (em vez do GitHub). Devolve $true se este PC ficou na versao certa
    param([switch]$Quiet, [switch]$Incoming)
    $say = { param($m) if (-not $Quiet) { Write-Host $m } }
    Remove-Item $SyncFlag -ErrorAction SilentlyContinue   # (o aviso do sync antigo)
    if (-not (Test-Path "$StRepo\.git")) {
        if ($Incoming) { git init -q $StRepo 2>&1 | Out-Null }
        else {
            & $say "  `e[90mgetting SuperTerminal from GitHub...`e[0m"
            git clone -q $StRepoUrl $StRepo 2>&1 | Out-Null
            if ($LASTEXITCODE) { & $say "  `e[31m$([char]0x2717)`e[0m couldn't get SuperTerminal from GitHub (network, or no access to the repo)"; return $false }
        }
    }
    # (a copia ainda nao foi aplicada neste PC: o ultimo commit aplicado fica em applied.txt)
    $before = "$(Get-StApplied)"
    $target = 'sync-incoming'
    if (-not $Incoming) {
        git -C $StRepo fetch -q origin 2>&1 | Out-Null
        if ($LASTEXITCODE) { & $say "  `e[90m$([char]0x25CB) no connection to GitHub: this PC stays on the version it has`e[0m"; return [bool]$before }
        $target = 'origin/main'
    }
    # (a copia e so do sync: fica igual a versao nova, sem merges)
    git -C $StRepo reset -q --hard $target 2>&1 | Out-Null
    if ($LASTEXITCODE) { & $say "  `e[31m$([char]0x2717)`e[0m couldn't switch to the new version"; return $false }
    $after = "$(git -C $StRepo rev-parse HEAD)"; $short = $after.Substring(0, 7)
    if ($before -eq $after) { & $say "  `e[32m$([char]0x2713)`e[0m already on the latest version `e[90m($short)`e[0m"; return $true }
    $n = if ($before) { "$(git -C $StRepo rev-list --count "$before..$after") new changes" } else { 'first version' }
    $ia = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$StRepo\install.ps1", '-SkipApps', '-Quiet') + $(if ($before) { '-Previous', $before } else { @() })
    $r = "$(& $PwshExe @ia 2>&1 | Select-Object -Last 1)".Trim()
    if ($r -match '^applied:') { Set-Content "$StRepo\..\applied.txt" $after }
    & $say "  `e[32m$([char]0x2193)`e[0m updated to $short `e[90m($n; $r)`e[0m$(if ($r -notmatch '^applied: 0 ') { "`n  `e[90mopen a new tab to use it`e[0m" })"
    $true
}
function Get-StApplied { if (Test-Path "$StRepo\..\applied.txt") { "$(Get-Content "$StRepo\..\applied.txt" -TotalCount 1)".Trim() } }
function Show-SyncStatus {
    # versao aplicada aqui (e nos outros PCs ligados) comparada com a mais recente do GitHub; nao muda nada
    if (-not (Test-Path "$StRepo\.git")) { Write-Host "  `e[33m$([char]0x25CB)`e[0m not synced yet on this PC: run sync"; return }
    git -C $StRepo fetch -q origin 2>&1 | Out-Null
    if ($LASTEXITCODE) { Write-Host "  `e[90m$([char]0x25CB) no connection to GitHub: can't compare`e[0m"; return }
    $latest = "$(git -C $StRepo rev-parse origin/main)"
    $line = {
        param($who, $have)
        if (-not $have) { return "  $who  `e[33mnever synced`e[0m" }
        if ($have -eq $latest) { return "  $who  `e[32m$([char]0x2713) up to date`e[0m `e[90m($($have.Substring(0, 7)))`e[0m" }
        $n = "$(git -C $StRepo rev-list --count "$have..$latest" 2>$null)"
        "  $who  `e[33m$([char]0x2191) $(if ($n) { "$n behind" } else { 'not on the latest' })`e[0m `e[90m($($have.Substring(0, 7)) $([char]0x2192) $($latest.Substring(0, 7)))`e[0m"
    }
    Write-Host "  `e[90mGitHub: $($latest.Substring(0, 7))  $(git -C $StRepo log -1 --format='%s  (%cr)' origin/main)`e[0m"
    $me = Get-StApplied
    Write-Host (& $line ("this PC".PadRight(10)) $me)
    # o que falta aqui (os titulos das mudancas novas, ate 5)
    if ($me -and $me -ne $latest) { git -C $StRepo log --format="      `e[90m$([char]0x00B7) %s`e[0m" -5 "$me..$latest" 2>$null | ForEach-Object { Write-Host $_ } }
    foreach ($pc in @($SshHosts.Keys | Where-Object { $SshHosts[$_] -ne $env:COMPUTERNAME } | Sort-Object)) {
        if (-not (Test-Port22 $SshHosts[$pc] 1500)) { Write-Host "  $($pc.PadRight(10))  `e[90moff or offline`e[0m"; continue }
        $h = "$(Invoke-Remote $pc 'if (Test-Path "$HOME\.local\superterminal\applied.txt") { (Get-Content "$HOME\.local\superterminal\applied.txt" -TotalCount 1).Trim() }' | Select-Object -Last 1)".Trim()
        Write-Host (& $line $pc.PadRight(10) $h)
    }
}
function Sync-Pcs {
    # a versao deste PC (a da copia do repo, aplicada aqui) para os outros PCs com nome; cada um aplica-a
    param([switch]$Quiet)
    $say = { param($m) if (-not $Quiet) { Write-Host $m } }
    if (-not (Get-StApplied)) { & $say "  `e[33m$([char]0x25CB)`e[0m this PC has no SuperTerminal version yet: super upgrade first"; return }
    $peers = @($SshHosts.Keys | Where-Object { $SshHosts[$_] -ne $env:COMPUTERNAME } | Sort-Object)
    if (-not $peers -or -not (Get-Command tailscale -ErrorAction SilentlyContinue)) { & $say "  `e[90m$([char]0x25CB) no other PCs (setup > Tailscale names them): only this one`e[0m"; return }
    $gitSsh = "$($SshExe.Replace('\', '/')) -o BatchMode=yes -o ConnectTimeout=5"
    foreach ($pc in $peers) {
        if (-not (Test-Port22 $SshHosts[$pc] 1500)) { & $say "  `e[90m$([char]0x25CB) ${pc}: off or offline, skipped`e[0m"; continue }
        $rh = "$(Invoke-Remote $pc 'if (-not (Test-Path "$HOME\.local\superterminal\repo\.git")) { git init -q "$HOME\.local\superterminal\repo" | Out-Null }; $HOME' | Select-Object -Last 1)".Trim()
        if (-not $rh) { & $say "  `e[31m$([char]0x2717)`e[0m ${pc}: no answer over ssh"; continue }
        git -C $StRepo -c "core.sshCommand=$gitSsh" push -q -f "${pc}:$($rh.Replace('\', '/'))/.local/superterminal/repo" HEAD:refs/heads/sync-incoming 2>&1 | Out-Null
        if ($LASTEXITCODE) { & $say "  `e[31m$([char]0x2717)`e[0m ${pc}: couldn't send it the new version"; continue }
        $r = @(Invoke-Remote $pc "`$env:KVN_CMD = '1'; `$env:SUPERTERMINAL = '1'; . `$PROFILE.CurrentUserCurrentHost; Update-SuperTerminal -Incoming" | Where-Object { "$_".Trim() })
        & $say "  `e[1m${pc}:`e[0m $(if ($r) { "$($r[0])".Trim() } else { "`e[31mno answer" })`e[0m"
    }
}
function super {
    # super upgrade -> a versao mais recente do GitHub, aplicada neste PC
    # super sync    -> a versao deste PC para os outros PCs (setup > Tailscale da-lhes nome)
    # super status  -> este PC e os outros comparados com o GitHub (nao muda nada)
    param([Parameter(Position = 0)][string]$Cmd)
    switch ($Cmd) {
        'upgrade' { [void](Update-SuperTerminal) }
        'sync' { Sync-Pcs }
        'status' { Show-SyncStatus }
        default {
            $c = { param($k, $t) "  `e[48;2;62;68;81;97m super $k `e[0m  `e[37m$t`e[0m" }
            Write-Host (& $c 'upgrade' 'the latest version from GitHub, on this PC')
            Write-Host (& $c 'sync   ' 'this PC''s version to your other PCs')
            Write-Host (& $c 'status ' 'this PC and the others compared with GitHub')
        }
    }
}
Register-ArgumentCompleter -CommandName super -ParameterName Cmd -ScriptBlock { param($c, $p, $w) 'upgrade', 'sync', 'status' | Where-Object { $_ -like "$w*" } | ForEach-Object { [Management.Automation.CompletionResult]::new($_) } }
function sync { Write-Host "  `e[90msync is now: super upgrade (this PC from GitHub) / super sync (to your other PCs) / super status`e[0m" }

$WakeMacs = @{}; foreach ($pc in $Pcs) { if ($pc.mac) { $WakeMacs[$pc.name] = $pc.mac } }
$LanFile = "$HOME\.config\pcs-lan.json"   # ultimo IP local conhecido de cada PC
function Get-LanIp([string]$name) { if (Test-Path $LanFile) { (Get-Content $LanFile -Raw | ConvertFrom-Json).$name } }
function Save-LanIp([string]$name, [string]$ip) { $j = if (Test-Path $LanFile) { Get-Content $LanFile -Raw | ConvertFrom-Json -AsHashtable } else { @{} }; $j[$name] = $ip; $j | ConvertTo-Json | Set-Content $LanFile -Encoding utf8 }
function Test-Port22([string]$h, [int]$ms = 800) { $t = [Net.Sockets.TcpClient]::new(); try { $t.ConnectAsync($h, 22).Wait($ms) -and $t.Connected } catch { $false } finally { $t.Dispose() } }
function Wait-Until([scriptblock]$cond, [string]$msg, [int]$secs, [scriptblock]$every) {
    # animacao "msg  12s" ate $cond ser verdade (ou acabar o tempo); $every corre de 15 em 15 s; devolve os segundos ou -1
    $fr = [char[]]'⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'; $sw = [Diagnostics.Stopwatch]::StartNew(); $i = 0; $next = 15
    [Console]::Write("`e[?25l")
    try {
        while ($sw.Elapsed.TotalSeconds -lt $secs) {
            [Console]::Write("`r  `e[35m$($fr[$i++ % 10])`e[0m  $msg  `e[90m$([int]$sw.Elapsed.TotalSeconds)s`e[0m`e[K")
            if (& $cond) { [Console]::Write("`r`e[K"); return [int]$sw.Elapsed.TotalSeconds }
            if ($every -and $sw.Elapsed.TotalSeconds -ge $next) { & $every; $next += 15 }
            Start-Sleep -Milliseconds 400
        }
    } finally { [Console]::Write("`e[?25h") }
    [Console]::Write("`r`e[K"); -1
}
function wake([string]$name) {
    # (sem nome: o 1.o PC com MAC no pcs.json)
    if (-not $name) { $name = @($WakeMacs.Keys | Sort-Object)[0] }
    if (-not $name) { Write-Warn 'no PC to wake yet' 'Wake-on-LAN needs the PC''s MAC: "mac" for it in ~\.config\superterminal\pcs.json (setup > Tailscale names the PCs)'; return }
    if (-not $WakeMacs[$name]) { Write-Warn "no MAC address for '$name'" "known: $($WakeMacs.Keys -join ', ')"; return }
    $hn = $SshHosts[$name]; $ip = Get-LanIp $name
    Write-Host ''
    if ((Test-Port22 $hn) -or ($ip -and (Test-Port22 $ip))) { Write-Host "  `e[32m$([char]0x2713)`e[0m `e[97m$hn`e[0m is already awake"; return }
    $myLan = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.PrefixOrigin -eq 'Dhcp' -or $_.IPAddress -like '192.168.*' } | ForEach-Object IPAddress)
    $sameNet = -not $ip -or @($myLan | Where-Object { ($_ -split '\.')[0..2] -join '.' -eq ($ip -split '\.')[0..2] -join '.' }).Count
    $mac = [byte[]]($WakeMacs[$name] -split '-' | ForEach-Object { [Convert]::ToByte($_, 16) }); $pkt = [byte[]](@(0xFF) * 6 + $mac * 16)
    $send = {
        $u = [Net.Sockets.UdpClient]::new(); $u.EnableBroadcast = $true
        $dsts = @('255.255.255.255') + $(if ($ip) { (($ip -split '\.')[0..2] -join '.') + '.255'; $ip })
        foreach ($d in $dsts) { foreach ($port in 7, 9) { try { [void]$u.Send($pkt, $pkt.Length, $d, $port) } catch {} } }
        $u.Close()
    }
    & $send
    Write-Host "  `e[35m$([char]0x2192)`e[0m magic packet to `e[97m$hn`e[0m  `e[90m$($WakeMacs[$name])$(if ($ip) { "  (broadcast + $ip)" })`e[0m"
    if (-not $sameNet) { Write-Warn "you don't seem to be on the same network as $name ($ip)" 'Wake-on-LAN only works inside the home network' }
    $s = Wait-Until { (Test-Port22 $hn 600) -or ($ip -and (Test-Port22 $ip 600)) } "waiting for $hn to wake up" 90 $send
    if ($s -ge 0) { Write-Host "  `e[32m$([char]0x2713)`e[0m `e[97m$hn`e[0m is awake  `e[90m($s s)`e[0m" }
    else {
        Write-Host "  `e[31m$([char]0x2717)`e[0m no answer from `e[97m$hn`e[0m after 90 s"
        Write-Host "  `e[90mWi-Fi wake only works from sleep (suspend), not after a shutdown, and the PC must be plugged in.`e[0m"
        Write-Host "  `e[90mIf it was shut down, press its power button.`e[0m"
    }
}
function suspend([string]$name) {
    # (sem nome: o outro PC; "suspend <este>" suspende este)
    if (-not $name) { $name = Get-OtherPc }
    if (-not $name) { Write-Warn 'no other PC yet' 'setup > Tailscale names your PCs (or: suspend <this PC''s name>)'; return }
    $hn = $SshHosts[$name]
    if ($hn -eq $env:COMPUTERNAME) { Write-Host "  `e[35m$([char]0x263E)`e[0m this PC is going to sleep"; Add-Type -AssemblyName System.Windows.Forms; [void][Windows.Forms.Application]::SetSuspendState('Suspend', $false, $false); return }
    if (-not (Test-SshPeer $name)) { return }
    # guarda o IP local (para o wake o encontrar a dormir) e suspende com a chamada do Windows (nunca hiberna)
    $lan = Invoke-Remote $name "(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { `$_.PrefixOrigin -eq 'Dhcp' } | Select-Object -First 1).IPAddress" | Select-Object -Last 1
    if ($lan -match '^\d+\.\d+\.\d+\.\d+$') { Save-LanIp $name $lan }
    Write-Host ''
    Write-Host "  `e[35m$([char]0x263E)`e[0m sending `e[97m$hn`e[0m to sleep  `e[90m$(if ($lan) { "(lan $lan)" })`e[0m"
    $null = Invoke-Remote $name "Start-Job { Start-Sleep 1; Add-Type -AssemblyName System.Windows.Forms; [Windows.Forms.Application]::SetSuspendState('Suspend', `$false, `$false) } | Out-Null; Start-Sleep 2"
    $s = Wait-Until { -not (Test-Port22 $hn 600) } "waiting for $hn to go to sleep" 45 $null
    if ($s -ge 0) { Write-Host "  `e[32m$([char]0x2713)`e[0m `e[97m$hn`e[0m is asleep  `e[90m(wake it with: wake $name)`e[0m" }
    else { Write-Warn "$hn is still answering after 45 s" 'something may be keeping it awake (a download, a game, a program blocking sleep)' }
}

# ---- yt: YouTube no terminal (grelha de thumbnails + video no terminal) -> ~\.config\yt-tui.ps1 ----
# apps de ecra inteiro com o pin ligado: abrem num separador novo (o painel de baixo e so parte do ecra); o separador
# fecha-se ao sair da app. Sem pin, correm aqui como sempre. $true se abriu no separador.
function Open-InTab([string]$title, [string[]]$cmd, [string]$dir = $PWD.ProviderPath) {
    if (-not ($global:FfBarPid -and (Get-Process -Id $global:FfBarPid -ErrorAction SilentlyContinue))) { return $false }
    $wt = @("$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe", "$HOME\.local\terminal\wt.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $wt) { return $false }
    $q = $cmd | ForEach-Object { if ("$_" -match '[\s"]') { "`"$("$_".Replace('"', '\"'))`"" } else { "$_" } }
    Start-Process $wt -ArgumentList (@('-w', '0', 'nt', '--title', $title, '-d', "`"$dir`"") + $q)
    $true
}
# (yt/st correm sempre a partir da home: numa pasta de rede, o D: do desktop, o curl/cmd/mpv que eles chamam partiam)
# (no WezTerm correm no proprio painel, ampliado para o ecra todo enquanto estao abertos: Invoke-Zoomed)
function yt { if (Open-InTab 'yt' (@($PwshExe, '-NoLogo', '-File', "$HOME\.config\yt-tui.ps1") + $args) $HOME) { return }; Clear-FfRegion; $a = $args; Invoke-Zoomed { Push-Location $HOME; try { & "$HOME\.config\yt-tui.ps1" @a } finally { Pop-Location } } }
# ---- st: Stremio no terminal (catalogos + streams dos addons da conta: Torrentio, Comet...) -> ~\.config\st-tui.ps1 ----
function st { if (Open-InTab 'st' (@($PwshExe, '-NoLogo', '-File', "$HOME\.config\st-tui.ps1") + $args) $HOME) { return }; Clear-FfRegion; $a = $args; Invoke-Zoomed { Push-Location $HOME; try { & "$HOME\.config\st-tui.ps1" @a } finally { Pop-Location } } }

# ---- setup: contas e escolhas (fonte, Tailscale, YouTube, Stremio, logo, sudo) -> ~\.config\superterminal-setup.ps1 ----
function setup { Clear-FfRegion; $a = $args; Invoke-Zoomed { & $PwshExe -NoLogo -NoProfile -File "$HOME\.config\superterminal-setup.ps1" @a } }
Register-ArgumentCompleter -CommandName setup -ScriptBlock { param($c, $p, $w) 'font', 'tailscale', 'youtube', 'stremio', 'logo', 'sudo' | Where-Object { $_ -like "$w*" } }
# ---- app: lancador de apps ----
#   app            -> escolher com fzf        app <nome>      -> abrir
#   app add        -> escolher .exe na janela app add <nome> [path]
#   app list | app rm <nome> | app ren <nome> <novo>
$AppsFile = "$HOME\.config\apps.json"
function Get-Apps { if (Test-Path $AppsFile) { Get-Content $AppsFile -Raw | ConvertFrom-Json -AsHashtable } else { [ordered]@{} } }
function app([string]$Name, [string]$A1, [string]$A2) {
    $apps = Get-Apps
    $save = { $apps | ConvertTo-Json | Set-Content $AppsFile -Encoding utf8 }
    switch ($Name) {
        'add' {
            $n = $A1; $path = $A2
            if ($n -and -not $path -and (Test-Path -LiteralPath $n)) { $path = $n; $n = $null }
            if (-not $path) {
                Add-Type -AssemblyName System.Windows.Forms
                $d = [System.Windows.Forms.OpenFileDialog]@{ Title = 'Pick the app'; Filter = 'Programs (*.exe;*.lnk;*.bat;*.cmd)|*.exe;*.lnk;*.bat;*.cmd|All|*.*' }
                if ($d.ShowDialog() -ne 'OK') { return }
                $path = $d.FileName
            }
            # nome automatico: minusculas, sem numero de versao ("Blender 5.2" -> blender)
            if (-not $n) { $n = ([IO.Path]::GetFileNameWithoutExtension($path).ToLower() -replace '[\s_-]*v?\d+(\.\d+)*$', '' -replace '\s+', '-') }
            # shell:AppsFolder\<AppID> = apps MSIX (Claude, Store...): o explorer abre-as, mas nao sao ficheiros
            $apps[$n] = if ($path -like 'shell:*') { $path } else { (Resolve-Path -LiteralPath $path).Path }; & $save
            "+ $n -> $($apps[$n])"
        }
        { $_ -in 'rm', 'remove' } { $apps.Remove($A1); & $save; "- $A1" }
        { $_ -in 'ren', 'rename', 'mv' } {
            if (-not $apps.Contains($A1)) { "app '$A1' doesn't exist"; return }
            if (-not $A2) { 'usage: app ren <name> <new-name>'; return }
            $apps[$A2] = $apps[$A1]; $apps.Remove($A1); & $save; "$A1 -> $A2"
        }
        { $_ -in 'list', 'ls' } { $apps.GetEnumerator() | Sort-Object Key | ForEach-Object { '{0,-16} {1}' -f $_.Key, $_.Value } }
        default {
            if (-not $Name) { $Name = $apps.Keys | Sort-Object | fzf --height 40% --reverse --prompt 'app> '; if (-not $Name) { return } }
            if (-not $apps.Contains($Name)) { "app '$Name' doesn't exist - add it with: app add $Name"; return }
            # via explorer: abre sem admin mesmo a partir do terminal elevado
            [Diagnostics.Process]::Start('explorer.exe', "`"$($apps[$Name])`"") | Out-Null
        }
    }
}
Register-ArgumentCompleter -CommandName app -ParameterName Name -ScriptBlock {
    param($c, $p, $word) @('add', 'rm', 'ren', 'list') + @((Get-Apps).Keys) | Where-Object { $_ -like "$word*" }
}

# ---- comandos teus: mkcmd ----
# cada comando e um ficheiro em ~\.config\cmds\<nome>.ps1 (uma funcao normal do PowerShell; as flags sao o param()).
# Sincronizado entre os PCs e mostrado no F1 (grupo "mine", le o param() de cada ficheiro).
$CmdDir = "$HOME\.config\cmds"
Get-ChildItem "$CmdDir\*.ps1" -ErrorAction Ignore | ForEach-Object { . $_.FullName }
function mkcmd {
    # mkcmd <nome>  cria (pergunta o que faz e as flags)  ·  mkcmd -e <nome> edita  ·  mkcmd -rm <nome> apaga  ·  mkcmd -l lista
    param([Parameter(Position = 0)][string]$Name, [Alias('e')][switch]$Edit, [Alias('rm')][switch]$Remove, [Alias('l')][switch]$List)
    $e = [char]27; $f = "$CmdDir\$Name.ps1"
    $ask = { param($q) Write-Host "  $e[36m?$e[0m $q " -NoNewline; (Read-Host).Trim() }
    $load = {
        $err = $null; $null = [Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$err)
        if ($err) { Write-Warn "$Name has an error, not loaded: $($err[0].Message)" "line $($err[0].Extent.StartLineNumber)  ·  fix it with: mkcmd -e $Name"; return }
        . $f; Write-Host "  $e[32m$([char]0x2713)$e[0m $e[97m$Name$e[0m ready  $e[90m(F1 shows it under ""mine"")$e[0m"
    }
    if ($List -or -not $Name) {
        $all = @(Get-ChildItem "$CmdDir\*.ps1" -ErrorAction Ignore)
        if (-not $all) { Write-Host "  $e[90mno commands of yours yet  ·  mkcmd <name> creates one$e[0m"; return }
        foreach ($c in $all) { Write-Host ("  $e[97m{0,-14}$e[90m{1}$e[0m" -f $c.BaseName, ((Get-Content $c -TotalCount 1) -replace '^#\s*')) }
        return
    }
    if ($Edit -or $Remove) {
        if (-not (Test-Path $f)) { Write-Warn "'$Name' is not one of your commands" 'mkcmd -l lists them'; return }
        if ($Edit) { micro $f; & $load; return }
        if ((& $ask "delete $e[97m$Name$e[0m? (y/N)") -notmatch '^y') { return }
        Remove-Item "Function:\$Name" -ErrorAction Ignore; Remove-Item -LiteralPath $f; Write-Host "  $e[32m$([char]0x2713)$e[0m $Name deleted"; return
    }
    if ($Name -cnotmatch '^[a-z][a-z0-9-]*$') { Write-Warn "'$Name': use lowercase letters, numbers and -" 'e.g. mkcmd backup  ·  mkcmd git-clean'; return }
    if (Test-Path $f) { Write-Warn "'$Name' is already yours" "mkcmd -e $Name to change it"; return }
    # ja existe com esse nome? (comando nosso do perfil, cmdlet, alias ou programa no PATH)
    $old = Get-Command $Name -ErrorAction Ignore | Select-Object -First 1
    if ($old) {
        $what = switch ($old.CommandType) { 'Application' { "program  $($old.Source)" } 'Alias' { "alias of $($old.Definition)" } 'Function' { 'a command from the profile' } default { "PowerShell $($old.CommandType.ToString().ToLower())" } }
        Write-Warn "'$Name' already exists: $what" 'yours would hide it in this shell'
        if ((& $ask 'create it anyway? (y/N)') -notmatch '^y') { return }
    }
    $desc = & $ask 'what does it do? (short)'
    $arg = & $ask 'main argument name (e.g. file; empty = none)'
    if ($arg -notmatch '^([a-zA-Z][a-zA-Z0-9]*)?$') { Write-Warn "'$arg' can't be a name, no main argument"; $arg = '' }
    if ($arg) { $arg = $arg.Substring(0, 1).ToUpper() + $arg.Substring(1) }
    $common = [Management.Automation.PSCmdlet]::CommonParameters + [Management.Automation.PSCmdlet]::OptionalCommonParameters
    $flags = [Collections.Generic.List[object]]::new(); $taken = @('e', 'l') + $(if ($arg) { $arg })
    Write-Host "  $e[90mflags: -name (or a short letter). empty name = done$e[0m"
    while ($true) {
        $n = & $ask 'flag name (e.g. force)'
        if (-not $n) { break }
        if ($n -notmatch '^[a-zA-Z][a-zA-Z0-9]*$' -or $n -in $common -or $n -in $taken) { Write-Warn "'$n' can't be used" 'letters and numbers, not repeated, not a PowerShell one (Verbose, Debug...)'; continue }
        $s = & $ask "short letter for -$n (empty = none)"
        if ($s -and ($s -notmatch '^[a-zA-Z]$' -or $s -in $taken)) { Write-Warn "'-$s' is taken or not a letter, no short form"; $s = '' }
        $val = (& $ask "does -$n take a value? (y/N)") -match '^y'
        $flags.Add(@{ n = $n.Substring(0, 1).ToUpper() + $n.Substring(1); s = $s; v = $val; d = (& $ask "-$n does what?") })
        $taken += $n, $s
    }
    $vars = @(@(if ($arg) { "`$$arg" }) + @($flags | ForEach-Object { "`$$($_.n)" })) -join ' '
    $body = & $ask "command to run (use $(if ($vars) { $vars } else { 'nothing' }); empty = write the code in micro)"
    $p = @($(if ($arg) { "        [Parameter(Position = 0)][string]`$$arg,   # main argument" }))
    $p += foreach ($x in $flags) { "        $(if ($x.s) { "[Alias('$($x.s)')]" })[$(if ($x.v) { 'string' } else { 'switch' })]`$$($x.n),   # $($x.d)" }
    if ($p) { $p[-1] = $p[-1] -replace ',(\s+#)', '$1' }
    $code = @("# $desc", "# (made with mkcmd  ·  change it: mkcmd -e $Name)", "function global:$Name {", '    param(') + $p + @('    )')
    $code += if ($body) { "    $body" } else { "    # your code here. Flags are variables: `$Force is `$true when you type -Force (or its letter); values: -Out x -> `$Out = 'x'", "    Write-Host '$Name`: not done yet'" }
    $code += '}'
    New-Item -ItemType Directory $CmdDir -Force | Out-Null
    [IO.File]::WriteAllLines($f, [string[]]$code, [Text.UTF8Encoding]::new($false))
    dot add -- ".config/cmds/$Name.ps1" 2>$null
    if (-not $body) { micro $f }
    & $load
}
Register-ArgumentCompleter -CommandName mkcmd -ParameterName Name -ScriptBlock {
    param($c, $p, $word) Get-ChildItem "$CmdDir\$word*.ps1" -ErrorAction Ignore | ForEach-Object BaseName
}
# Tab nas funcoes sem param() (usam $args): ssh <pc>, yt -a, sudo <comando>. Sem sugestao propria, o Tab volta aos ficheiros.
Register-ArgumentCompleter -Native -CommandName ssh -ScriptBlock {
    param($word, $ast, $cursor)
    if ($ast.CommandElements.Count -gt 2 -or ($ast.CommandElements.Count -eq 2 -and -not $word)) { return }
    $SshHosts.Keys | Sort-Object | Where-Object { $_ -like "$word*" } | ForEach-Object { [Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "ssh to $($SshHosts[$_])") }
}
Register-ArgumentCompleter -Native -CommandName yt -ScriptBlock {
    param($word) if ("$word" -like '-*') { [Management.Automation.CompletionResult]::new('-a', '-a', 'ParameterName', 'audio only (music)') }
}
Register-ArgumentCompleter -Native -CommandName sudo, gsudo -ScriptBlock {
    param($word, $ast, $cursor)
    # 1.a palavra a seguir ao sudo: um comando; depois disso, o Tab do proprio comando (sudo winget ins -> install)
    if ($ast.CommandElements.Count -gt 2 -or ($ast.CommandElements.Count -eq 2 -and -not $word)) {
        $text = $ast.Extent.Text; $skip = $ast.CommandElements[1].Extent.StartOffset - $ast.Extent.StartOffset
        (TabExpansion2 -inputScript $text.Substring($skip) -cursorColumn ($cursor - $ast.Extent.StartOffset - $skip)).CompletionMatches
        return
    }
    Get-Command "$word*" -CommandType Application, Function, Alias, Cmdlet -ErrorAction Ignore | ForEach-Object { $_.Name -replace '\.exe$' } |
        Select-Object -Unique -First 40 | ForEach-Object { [Management.Automation.CompletionResult]::new($_, $_, 'Command', $_) }
}
if (-not [Console]::IsOutputRedirected) {
    # atalhos correm comandos via AcceptLine (desenhar dentro do handler deixa o prompt por cima do fastfetch)
    function Invoke-LineCommand($cmd) {
        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($cmd)
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    }
    # painel mudou de tamanho (fechar splits, maximizar...) com o prompt parado e vazio: redesenha sozinho
    $null = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -SupportEvent -Action {
        $s = "$([Console]::WindowWidth)x$([Console]::WindowHeight)"
        if ($global:FfClean -and $global:FfSize -and $s -ne $global:FfSize) {   # (nao apaga o resultado de comandos)
            $line = $null; $c = $null; [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$c)
            if (-not $line) { $global:FfSize = $s; Invoke-LineCommand 'ff' }
        }
    }
    # FfClean: ecra so com o fastfetch (ff/exit/pin nao vao para o historico)
    Set-PSReadLineOption -AddToHistoryHandler {
        param($line)
        if ($line -notin 'ff', 'exit', 'pin', 'Hide-Terminal; ff') { $global:FfClean = $false; return $true }
        $false
    }
    # esconde o Windows Terminal pelo proprio atalho global (Ctrl+Alt+T); minimizar a forca apaga o ecra
    function Hide-Terminal { (New-Object -ComObject WScript.Shell).SendKeys('^%t') }
    # Ctrl+L (e o Ctrl+D, que o manda ao painel antigo): espera que o painel acabe de mudar de tamanho antes de
    # redesenhar; senao desenha com a largura antiga e o terminal parte o desenho ao encolher (max. 0,5 s)
    Set-PSReadLineKeyHandler -Chord Ctrl+l -ScriptBlock {
        $w = [Console]::WindowWidth; $h = [Console]::WindowHeight
        for ($i = 0; $i -lt 7; $i++) {
            Start-Sleep -Milliseconds 70
            if ([Console]::WindowWidth -eq $w -and [Console]::WindowHeight -eq $h) { break }
            $w = [Console]::WindowWidth; $h = [Console]::WindowHeight
        }
        Invoke-LineCommand 'ff'
    }
    # Ctrl+D = dividir o painel, so no prompt (com yt/st/etc. abertos o shell nao le teclas -> nao divide).
    # O atalho saiu do Windows Terminal, que dividia sempre. Dentro de um ssh nao faz nada (o wt.exe de la nao e este).
    Set-PSReadLineKeyHandler -Chord Ctrl+d -ScriptBlock {
        if ($env:SSH_CONNECTION) { return }
        $wt = @("$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe", "$HOME\.local\terminal\wt.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $wt) { return }
        # com o pin ligado, o pin fica: divide-se so o shell de baixo e o painel novo junta-se ao mesmo cabecalho
        # (sem fastfetch proprio; o cabecalho so fecha quando fecharem todos os shells de baixo)
        $pinned = $global:FfBarPid -and (Get-Process -Id $global:FfBarPid -ErrorAction SilentlyContinue)
        if ($pinned) { Set-Content "$env:TEMP\ff-bar-pending" $global:FfBarPid }
        Start-Process $wt -ArgumentList '-w', '0', 'sp', '-d', "`"$($PWD.ProviderPath)`""
        if ($pinned) { return }   # (sem fastfetch neste painel: nada a redesenhar, e o que estava no ecra fica)
        # este painel encolhe: espera que o tamanho estabilize e redesenha (como o Ctrl+L)
        Start-Sleep -Milliseconds 150
        $w = [Console]::WindowWidth; $h = [Console]::WindowHeight
        for ($i = 0; $i -lt 7; $i++) {
            Start-Sleep -Milliseconds 70
            if ([Console]::WindowWidth -eq $w -and [Console]::WindowHeight -eq $h) { break }
            $w = [Console]::WindowWidth; $h = [Console]::WindowHeight
        }
        Invoke-LineCommand 'ff'
    }
    Set-PSReadLineKeyHandler -Chord F1 -ScriptBlock {
        $i = Select-Cheat
        [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
        # (ctrl+o no F1 = "!run:<comando>": escreve e corre logo)
        if ($i -like '!run:*') { Invoke-LineCommand $i.Substring(5).Trim() }
        elseif ($i) { [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine(); [Microsoft.PowerShell.PSConsoleReadLine]::Insert($i) }
    }
    # Ctrl+W: em SSH sai so da sessao remota; localmente fecha a aba,
    # mas na ULTIMA aba esconde a janela (sem fechar -> sem relancar/flicker)
    Set-PSReadLineKeyHandler -Chord Ctrl+w -ScriptBlock {
        if (-not $env:SSH_CONNECTION) {
            $wt = (Get-Process -Id $PID).Parent   # pwsh e filho direto do WindowsTerminal (1 OpenConsole por aba/painel)
            # (com o pin, o separador tem 2 paineis: o do cabecalho nao conta)
            $max = 1 + [int][bool]($global:FfBarPid -and (Get-Process -Id $global:FfBarPid -ErrorAction SilentlyContinue))
            if ($wt.ProcessName -eq 'WindowsTerminal' -and @(Get-Process OpenConsole -ErrorAction SilentlyContinue | Where-Object { $_.Parent.Id -eq $wt.Id }).Count -le $max) {
                Invoke-LineCommand 'Hide-Terminal; ff'   # esconde logo e desenha com a janela escondida
                return
            }
        }
        Invoke-LineCommand 'exit'
    }
}
# ao vivo (+ uso de GPU); Ctrl+C para sair. Enquanto corre, atualiza o Tailscale a cada 5 s em segundo plano
function ffw {
    # WezTerm: o cabecalho atualiza-se sozinho; ffw liga / desliga isso (ficheiro lido pelo header.ps1, vale para todos)
    if ($env:WEZTERM_PANE -and $env:KVN_COMPACT) {
        $off = "$env:TEMP\superterminal-header-static"
        if (Test-Path $off) { Remove-Item $off; $live = $true } else { New-Item $off -Force | Out-Null; $live = $false }
        Write-Host "  header $(if ($live) { 'live (updates every 2 s)' } else { 'static' })" -ForegroundColor DarkGray; return
    }
    # com o pin: o painel de cima passa a atualizar sozinho (ffw outra vez desliga)
    if ($global:FfBarPid -and (Get-Process -Id $global:FfBarPid -ErrorAction SilentlyContinue)) {
        Set-Content "$env:TEMP\ff-bar-$($global:FfBarPid).cmd" 'ffw'; $global:FfBarLive = -not $global:FfBarLive
        Write-Host "  header $(if ($global:FfBarLive) { 'live (updates every 2 s)' } else { 'static' })" -ForegroundColor DarkGray; return
    }
    Clear-FfRegion; Clear-Host
    $r = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', "while (1) { & '$HOME\.config\ts-cache.ps1'; Start-Sleep 5 }"
    Push-Location $HOME; try { fastfetch -c "$HOME\.config\fastfetch\config-live.jsonc" --watch @args }
    finally { Pop-Location; Stop-Process -Id $r.Id -Force -ErrorAction SilentlyContinue }
}
# wsl: ao sair (exit / Ctrl+W) volta limpo com o fastfetch, como no ssh
function wsl {
    # numa pasta de rede (\\pc\d) o wsl nao consegue traduzir o caminho: abre na home do Linux
    $cd = if ($PWD.ProviderPath -like '\\*' -and $args -notcontains '--cd') { '--cd', '~' } else { @() }
    Clear-FfRegion; wsl.exe @cd @args
    # so depois de sessoes interativas (nao depois de 'wsl -e cmd', 'wsl -l', 'wsl --shutdown', ...)
    $nonInteractive = '-e', '--exec', '--', '-l', '--list', '-v', '--version', '--status', '--shutdown', '-t', '--terminate', '--update', '--install', '-s', '--set-default', '--unregister', '--export', '--import', '--mount', '--unmount', '--help'
    if (-not ($args | Where-Object { $_ -in $nonInteractive })) { ff }
}

# 1.a vez que o terminal abre (num PC novo): o setup aparece sozinho (ele grava ~\.config\superterminal\setup-seen)
if (-not $env:KVN_CMD -and -not $env:SSH_CONNECTION -and -not [Console]::IsOutputRedirected -and -not (Test-Path "$HOME\.config\superterminal\setup-seen")) { setup }
# pin por omissao (decidido no arranque, ver $global:AutoPin): este painel fica com o cabecalho e o shell abre por baixo
if ($global:AutoPin) { $global:AutoPin = $false; pin }
