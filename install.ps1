# SuperTerminal installer: from this repo folder to a working terminal, on a clean Windows 10 / 11 PC.
#   install.cmd (double click)  or  powershell -ExecutionPolicy Bypass -File install.ps1
# What it does, and only this:
#   1. installs the programs with winget (PowerShell 7, Git, fastfetch, fzf, mpv, yt-dlp, editors...); ones already there are kept
#   2. downloads WezTerm (the terminal itself) to ~\.local\wezterm
#   3. puts the config files in place (~\.config, the PowerShell profile...); anything that was there is backed up first
#   4. builds the Ctrl+Alt+T agent and adds "SuperTerminal" to the Start menu
# Nothing outside SuperTerminal changes: the profile and the rest only load inside its window.
# Runs on Windows PowerShell 5.1 (what a new PC has), so this file is ASCII only and uses no PowerShell 7 syntax.
#   -SkipApps  no winget (what "sync" uses to apply a new version: only the files)
#   -Quiet     only the summary line
#   -Previous  the commit applied before (super upgrade passes it): files that changed on this PC since then are kept
param([switch]$SkipApps, [switch]$Quiet, [string]$Previous)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Repo = $PSScriptRoot
$Cfg = Join-Path $HOME '.config'
$Local = Join-Path $HOME '.local'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Backup = Join-Path $HOME ".superterminal-backup\$Stamp"

function Step([string]$t) { if (-not $Quiet) { Write-Host ''; Write-Host "== $t" -ForegroundColor Cyan } }
function Info([string]$t) { if (-not $Quiet) { Write-Host "   $t" -ForegroundColor DarkGray } }
function Good([string]$t) { if (-not $Quiet) { Write-Host "   ok  $t" -ForegroundColor Green } }
function Warn([string]$t) { Write-Host "   !   $t" -ForegroundColor Yellow }

if (-not $Quiet) {
    Write-Host ''
    Write-Host '  SuperTerminal installer' -ForegroundColor White
    Write-Host "  from $Repo" -ForegroundColor DarkGray
}

# ---------- 0. checks ----------
if ([Environment]::OSVersion.Version.Major -lt 10) { throw 'SuperTerminal needs Windows 10 or 11' }
if (-not (Test-Path (Join-Path $Repo 'shell\profile.ps1'))) { throw "run this from the SuperTerminal folder (shell\profile.ps1 not found in $Repo)" }
# espaco: os programas + o WezTerm + as caches precisam de ~3 GB; sem eles cada download falha a meio
$free = (Get-PSDrive ($env:SystemDrive.TrimEnd(':'))).Free
if (-not $SkipApps -and $free -lt 4GB) {
    Warn ("only {0:0.0} GB free on {1}: SuperTerminal needs about 4 GB. Free some space and run this again" -f ($free / 1GB), $env:SystemDrive)
    exit 1
}
$winget = Get-Command winget -ErrorAction SilentlyContinue
if (-not $winget -and -not $SkipApps) {
    # num Windows acabado de instalar o winget (App Installer) ja la esta mas so fica registado quando a Store o
    # atualiza, minutos depois do 1.o login: regista-o ja
    Info 'winget is not registered yet on this new Windows: registering it...'
    try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop } catch { }
    $env:PATH += ";$env:LOCALAPPDATA\Microsoft\WindowsApps"
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) { Good 'winget ready' }
}
if (-not $winget -and -not $SkipApps) {
    Warn 'winget is missing: install "App Installer" from the Microsoft Store, then run this again'
    Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1'
    exit 1
}

# ---------- 1. programs ----------
# (id, what it is for). PowerShell 7 as the MSI build: the Store one fails over ssh
$Apps = @(
    @('Microsoft.PowerShell', 'PowerShell 7'), @('Git.Git', 'git (and grep / sed / awk)'), @('Fastfetch-cli.Fastfetch', 'the header'),
    @('junegunn.fzf', 'menus and search'), @('ajeetdsouza.zoxide', 'z: jump to folders'), @('sharkdp.bat', 'cat with colours'),
    @('BurntSushi.ripgrep.MSVC', 'search in files'), @('sharkdp.fd', 'find files'), @('eza-community.eza', 'ls with icons'),
    @('uutils.coreutils', 'the Linux commands'), @('zyedidia.micro', 'simple editor'), @('Helix.Helix', 'code editor'),
    @('JesseDuffield.lazygit', 'git with a UI'), @('dandavison.delta', 'git diffs'), @('sxyazi.yazi', 'file manager'),
    # (o ffmpeg vem com o yt-dlp: o winget instala o yt-dlp.FFmpeg como dependencia; um 2.o, o Gyan.FFmpeg, chocava
    # com o comando "ffmpeg" que ja existia e era reinstalado a cada vez)
    @('charmbracelet.glow', 'markdown'), @('yt-dlp.yt-dlp', 'yt (and ffmpeg)'), @('shinchiro.mpv', 'the video player'),
    @('hpjansson.Chafa', 'images in the terminal'), @('oschwartz10612.Poppler', 'view: pdf pages'), @('jqlang.jq', 'JSON'), @('bootandy.dust', 'disk usage'), @('tldr-pages.tlrc', 'tldr'),
    # extras: super upgrade --all, spotify, cloud, pcping, speedtest, trip, share / receive, xh, pastel, gh, hyperfine
    @('topgrade-rs.topgrade', 'update every program'), @('aome510.spotify-player', 'spotify'), @('Rclone.Rclone', 'cloud: Google Drive, OneDrive...'),
    @('orf.gping', 'pcping: ping with a graph'), @('Ookla.Speedtest.CLI', 'speedtest'), @('FujiApple.Trippy', 'trip: traceroute'),
    @('schollz.croc', 'share / receive files with anyone'), @('ducaale.xh', 'HTTP requests'), @('sharkdp.pastel', 'colours'),
    @('GitHub.cli', 'gh: GitHub'), @('sharkdp.hyperfine', 'time commands')
)
# (sem pacote no winget: a versao oficial do GitHub, para ~\.local\bin, que o perfil poe no PATH)
#   (repo, ficheiro da versao Windows, exe, para que serve)
$GhApps = @(
    @('sharkdp/numbat', 'x86_64-pc-windows-msvc\.zip$', 'numbat.exe', 'calc: calculator with units'),
    @('ouch-org/ouch', 'ouch-x86_64-pc-windows-msvc\.zip$', 'ouch.exe', 'ouch: any archive format')
)
# winget: "Failed to extract the contents of the archive" (-1978335140) acontece em alguns Windows com o metodo de
# extracao por omissao (o do Explorador); a solucao documentada e o "tar". So durante a instalacao: no fim volta tudo
$WgSettings = "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json"
$WgSaved = $null; $WgTar = $false
function Use-WingetTar {
    if ($script:WgTar) { return }
    $script:WgTar = $true
    if (Test-Path $WgSettings) { $script:WgSaved = [IO.File]::ReadAllText($WgSettings) } else { $script:WgSaved = '' }
    $j = $null
    try { $j = (($script:WgSaved -split "`n" | Where-Object { $_ -notmatch '^\s*//' }) -join "`n") | ConvertFrom-Json } catch { }
    if (-not $j) { $j = New-Object PSObject }
    if (-not $j.installBehavior) { $j | Add-Member -NotePropertyName installBehavior -NotePropertyValue (New-Object PSObject) -Force }
    $j.installBehavior | Add-Member -NotePropertyName archiveExtractionMethod -NotePropertyValue 'tar' -Force
    New-Item -ItemType Directory (Split-Path $WgSettings) -Force | Out-Null
    [IO.File]::WriteAllText($WgSettings, ($j | ConvertTo-Json -Depth 10))
}
function Restore-WingetSettings {
    if (-not $script:WgTar) { return }
    if ($script:WgSaved) { [IO.File]::WriteAllText($WgSettings, $script:WgSaved) } else { Remove-Item $WgSettings -ErrorAction SilentlyContinue }
}
function Install-UutilsDirect {
    # o pacote do uutils no winget (0.12.0) espera um ficheiro que o zip ja nao traz (-1978335141): vai direto a
    # versao oficial no GitHub do uutils, para ~\.local\coreutils (o perfil procura-o la tambem)
    $rel = Invoke-RestMethod 'https://api.github.com/repos/uutils/coreutils/releases/latest' -UseBasicParsing -Headers @{ 'User-Agent' = 'SuperTerminal' }
    $asset = $rel.assets | Where-Object { $_.name -match 'x86_64-pc-windows-msvc\.zip$' } | Select-Object -First 1
    if (-not $asset) { throw 'no Windows build in the latest uutils release' }
    $zip = Join-Path $env:TEMP $asset.name
    Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing
    $dst = Join-Path $Local 'coreutils'; New-Item -ItemType Directory $dst -Force | Out-Null
    Expand-Archive $zip $dst -Force; Remove-Item $zip -ErrorAction SilentlyContinue
}
if (-not $SkipApps) {
    Step 'Programs (winget)'
    Info 'Windows may ask for admin for some of them'
    foreach ($a in $Apps) {
        # (um a um: o "winget list" sem --id corta os nomes compridos com "...")
        & winget list -e --id $a[0] --accept-source-agreements --disable-interactivity *> $null
        if ($LASTEXITCODE -eq 0) { Good "$($a[0])  (already installed)"; continue }
        if ($a[0] -eq 'uutils.coreutils' -and (Get-ChildItem "$Local\coreutils" -Filter 'coreutils-*' -Directory -ErrorAction SilentlyContinue)) { Good 'uutils.coreutils  (already installed)'; continue }
        Info "installing $($a[0])  - $($a[1])"
        $extra = @(); if ($a[0] -eq 'Microsoft.PowerShell') { $extra = @('--installer-type', 'wix') }
        $wg = { & winget install -e --id $a[0] --silent --accept-package-agreements --accept-source-agreements --disable-interactivity @extra }
        & $wg
        if ($LASTEXITCODE -eq -1978335140) { Info 'the archive did not extract: trying again with tar'; Use-WingetTar; & $wg }
        if ($LASTEXITCODE -ne 0 -and $a[0] -eq 'uutils.coreutils') {
            Info 'the winget package is broken: getting it from the uutils releases on GitHub'
            try { Install-UutilsDirect; $global:LASTEXITCODE = 0 } catch { Warn "uutils: $($_.Exception.Message)" }
        }
        if ($LASTEXITCODE -eq 0) { Good $a[0] } else { Warn "$($a[0]) did not install (code $LASTEXITCODE): the rest goes on; run this again later" }
    }
    Restore-WingetSettings
    $bin = Join-Path $Local 'bin'
    foreach ($g in $GhApps) {
        if (Test-Path (Join-Path $bin $g[2])) { Good "$($g[2])  (already installed)"; continue }
        Info "installing $($g[2])  - $($g[3])  (from github.com/$($g[0]))"
        $zip = $null; $tmp = $null
        try {
            $rel = Invoke-RestMethod "https://api.github.com/repos/$($g[0])/releases/latest" -UseBasicParsing -Headers @{ 'User-Agent' = 'SuperTerminal' }
            $asset = $rel.assets | Where-Object { $_.name -match $g[1] } | Select-Object -First 1
            if (-not $asset) { throw "no Windows build in the latest release" }
            $zip = Join-Path $env:TEMP "$Stamp-$($asset.name)"; $tmp = "$zip.d"
            Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing
            Expand-Archive $zip $tmp -Force
            $exe = Get-ChildItem $tmp -Recurse -Filter $g[2] | Select-Object -First 1
            if (-not $exe) { throw "$($g[2]) is not in $($asset.name)" }
            New-Item -ItemType Directory $bin -Force | Out-Null
            Copy-Item $exe.FullName $bin -Force
            Good $g[2]
        } catch { Warn "$($g[2]): $($_.Exception.Message)" }
        finally { if ($zip) { Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue } }
    }
    # (o que o winget instalou so entra no PATH dos processos novos: este continua com o antigo)
    $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH', 'User')
}
$Pwsh = 'C:\Program Files\PowerShell\7\pwsh.exe'
if (-not (Test-Path $Pwsh)) { Warn "PowerShell 7 is not at ${Pwsh}: SuperTerminal needs it (winget install Microsoft.PowerShell --installer-type wix)" }

# ---------- 2. WezTerm ----------
Step 'WezTerm (the terminal)'
$wz = Join-Path $Local 'wezterm'
if (Test-Path (Join-Path $wz 'wezterm-gui.exe')) { Good "already in $wz" }
else {
    $zip = Join-Path $env:TEMP "wezterm-$Stamp.zip"; $tmp = Join-Path $env:TEMP "wezterm-$Stamp"
    Info 'downloading WezTerm (~45 MB)...'
    Invoke-WebRequest 'https://github.com/wezterm/wezterm/releases/download/nightly/WezTerm-windows-nightly.zip' -OutFile $zip -UseBasicParsing
    Expand-Archive $zip $tmp -Force
    $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
    New-Item -ItemType Directory $Local -Force | Out-Null
    Move-Item $inner.FullName $wz
    Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Good "installed in $wz"
}

# ---------- 3. config files ----------
Step 'Config files'
$ProfilePath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Microsoft.PowerShell_profile.ps1'
$Map = @(
    @('shell\profile.ps1', $ProfilePath),
    @('shell\help.ps1', "$Cfg\kvn-help.ps1"), @('shell\theme.ps1', "$Cfg\st-theme.ps1"),
    @('apps\monitor\monitor.ps1', "$Cfg\st-monitor.ps1"), @('apps\monitor\sample.ps1', "$Cfg\st-monitor-sample.ps1"),
    @('apps\yt\yt-tui.ps1', "$Cfg\yt-tui.ps1"), @('apps\yt\yt-search.ps1', "$Cfg\yt-search.ps1"), @('apps\yt\yt-prefetch.ps1', "$Cfg\yt-prefetch.ps1"),
    @('apps\st\st-tui.ps1', "$Cfg\st-tui.ps1"), @('apps\view\view.ps1', "$Cfg\view.ps1"),
    @('config\fastfetch\config.jsonc', "$Cfg\fastfetch\config.jsonc"), @('config\fastfetch\config-hw.jsonc', "$Cfg\fastfetch\config-hw.jsonc"), @('config\fastfetch\config-live.jsonc', "$Cfg\fastfetch\config-live.jsonc"),
    @('config\helix\config.toml', "$Cfg\helix\config.toml"), @('config\helix\languages.toml', "$Cfg\helix\languages.toml"),
    @('config\micro\settings.json', "$Cfg\micro\settings.json"), @('config\micro\bindings.json', "$Cfg\micro\bindings.json"),
    @('config\lazygit\config.yml', "$env:LOCALAPPDATA\lazygit\config.yml"),
    @('config\mpv\mpv.conf', "$Cfg\mpv\mpv.conf"), @('config\mpv\input.conf', "$Cfg\mpv\input.conf"), @('config\mpv\st-input.conf', "$Cfg\mpv\st-input.conf"),
    @('config\mpv\script-opts\uosc.conf', "$Cfg\mpv\script-opts\uosc.conf"), @('config\mpv\script-opts\thumbfast.conf', "$Cfg\mpv\script-opts\thumbfast.conf"),
    @('config\mpv\mpv-setup.ps1', "$Cfg\mpv-setup.ps1"), @('config\mpv\mpv-keep-volume.lua', "$Cfg\mpv-keep-volume.lua"),
    @('system\ts-cache.ps1', "$Cfg\ts-cache.ps1"), @('system\ts-cache.vbs', "$Cfg\ts-cache.vbs"), @('system\setup-sshd.ps1', "$Cfg\setup-sshd.ps1"),
    @('terminal\wezterm\wezterm.lua', "$Cfg\wezterm\wezterm.lua"), @('terminal\wezterm\header.ps1', "$Cfg\wezterm\header.ps1"),
    @('terminal\setup\setup.ps1', "$Cfg\superterminal-setup.ps1"),
    @('wsl\zshrc', "$Cfg\wsl\kvn.zshrc"), @('wsl\bashrc', "$Cfg\wsl\kvn.bashrc"), @('wsl\setup-wsl.sh', "$Cfg\wsl\setup-wsl.sh"), @('wsl\ts-line.sh', "$Cfg\wsl\ts-line.sh")
)
# (pessoais: so se ainda nao existirem - o logo e as colunas do cabecalho de cada PC ficam)
$KeepIfThere = @('config\fastfetch\config.jsonc', 'config\fastfetch\config-hw.jsonc', 'config\fastfetch\config-live.jsonc')
# numa atualizacao (o "super upgrade" passa -Previous = a versao que aplicou da ultima vez): um ficheiro que ja nao e
# igual a essa versao foi mudado neste PC -> fica, e a nova vai para <ficheiro>.new. Sem versao anterior conhecida
# (1.o upgrade depois de instalar pelo zip) nao ha com que comparar: atualiza (com copia de seguranca)
$Prev = $null
if ($Previous -and (Get-Command git -ErrorAction SilentlyContinue)) { $Prev = "$(& git -C $Repo rev-parse -q --verify "$Previous^{commit}" 2>$null)".Trim() }
$backedUp = 0; $changed = 0; $kept = @()
# linhas que o comando theme muda (o tema escolhido): nao contam como mudanca local, e ficam ao atualizar o ficheiro
$ThemeLine = @{ 'config\helix\config.toml' = '(?m)^theme *= *"[^"]*"'; 'config\micro\settings.json' = '"colorscheme": *"[^"]*"' }
$norm = { param($t) "$t".Replace("`r`n", "`n").TrimEnd() }
foreach ($m in $Map) {
    $src = Join-Path $Repo $m[0]; $dst = $m[1]
    if (-not (Test-Path $src)) { Warn "missing in the repo: $($m[0])"; continue }
    if (($KeepIfThere -contains $m[0]) -and (Test-Path $dst)) { continue }
    if ((Test-Path $dst) -and ((Get-FileHash $dst).Hash -eq (Get-FileHash $src).Hash)) { continue }
    $tl = $ThemeLine[$m[0]]; $mine = $null
    if ($tl -and (Test-Path $dst)) {
        # (compara como se a linha do tema fosse a do repo; igual -> nada a fazer; senao atualiza e volta a por o tema)
        $live = [IO.File]::ReadAllText($dst); $new = [IO.File]::ReadAllText($src)
        $mine = [regex]::Match($live, $tl).Value; $repoLine = [regex]::Match($new, $tl).Value
        if ($mine -and $repoLine) {
            $liveN = & $norm ([regex]::new($tl).Replace($live, $repoLine.Replace('$', '$$'), 1))
            if ($liveN -eq (& $norm $new)) { continue }
            if ($Prev) {
                $oldT = (& git -C $Repo show "${Prev}:$($m[0].Replace('\', '/'))" 2>$null) -join "`n"
                if ($oldT -and $liveN -ne (& $norm ([regex]::new($tl).Replace($oldT, $repoLine.Replace('$', '$$'), 1)))) { Copy-Item $src "$dst.new" -Force; $kept += $dst; continue }
            }
        } else { $tl = $null }
    }
    if ($Prev -and (Test-Path $dst) -and -not $tl) {
        # (pelo id do git: o do ficheiro daqui, com as mesmas regras de fim de linha, contra o da versao anterior)
        $rel = $m[0].Replace('\', '/')
        $old = "$(& git -C $Repo rev-parse -q --verify "${Prev}:$rel" 2>$null)".Trim()
        $now = "$(& git -C $Repo hash-object "--path=$rel" $dst 2>$null)".Trim()
        if ($old -and $now -and $old -ne $now) { Copy-Item $src "$dst.new" -Force; $kept += $dst; continue }
    }
    $changed++
    New-Item -ItemType Directory (Split-Path $dst) -Force | Out-Null
    if ((Test-Path $dst) -and ((Get-FileHash $dst).Hash -ne (Get-FileHash $src).Hash)) {
        # (o que ja la estava fica guardado, com o mesmo caminho relativo a home)
        $rel = $dst; if ($rel.StartsWith($HOME)) { $rel = $rel.Substring($HOME.Length).TrimStart('\') } else { $rel = $rel -replace ':', '' }
        $b = Join-Path $Backup $rel; New-Item -ItemType Directory (Split-Path $b) -Force | Out-Null
        Copy-Item $dst $b -Force; $backedUp++
    }
    Copy-Item $src $dst -Force
    if ($tl -and $mine) { $t = [IO.File]::ReadAllText($dst); [IO.File]::WriteAllText($dst, [regex]::new($tl).Replace($t, $mine.Replace('$', '$$'), 1)) }   # (o tema que estava)
}
foreach ($d in "$Cfg\cmds", "$Cfg\superterminal", "$Local\superterminal") { New-Item -ItemType Directory $d -Force | Out-Null }
# placa grafica: sem uma a serio (VM, "Basic Display Adapter", PC sem drivers) nao ha OpenGL e o WezTerm nao abre;
# ai desenha por software (o wezterm.lua le este ficheiro). Com placa, o ficheiro sai e fica o OpenGL
$gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name)" })
$realGpu = @($gpus | Where-Object { $_ -match 'NVIDIA|AMD|Radeon|Intel|Qualcomm|Adreno|Arc' }).Count -gt 0
$feFile = "$Cfg\superterminal\front_end.txt"
if ($realGpu) { Remove-Item $feFile -ErrorAction SilentlyContinue }
else { Set-Content $feFile 'EGL'; Info "no graphics card with OpenGL ($($gpus -join ', ')): the terminal draws through DirectX (ANGLE)" }
# a fonte do terminal (letras + os icones do prompt, do cabecalho e das apps): CaskaydiaMono Nerd Font, so para este
# utilizador, se ainda nao houver (o setup deixa trocar por outra)
$fontReg = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
$haveFont = @((Get-ItemProperty $fontReg -ErrorAction SilentlyContinue).PSObject.Properties.Name + (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts' -ErrorAction SilentlyContinue).PSObject.Properties.Name | Where-Object { $_ -like 'CaskaydiaMono*' }).Count -gt 0
if ($haveFont) { Good 'font: CaskaydiaMono Nerd Font' }
else {
    Info 'font: downloading CaskaydiaMono Nerd Font (~40 MB)...'
    $fz = Join-Path $env:TEMP "CascadiaMono-$Stamp.zip"; $fx = Join-Path $env:TEMP "CascadiaMono-$Stamp"
    try {
        Invoke-WebRequest 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaMono.zip' -OutFile $fz -UseBasicParsing
        Expand-Archive $fz $fx -Force
        $fd = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"; New-Item -ItemType Directory $fd -Force | Out-Null
        foreach ($t in Get-ChildItem $fx -Filter 'CaskaydiaMonoNerdFont-*.ttf') {
            Copy-Item $t.FullName $fd -Force
            New-ItemProperty $fontReg -Name "CaskaydiaMono NF $($t.BaseName -replace '^CaskaydiaMonoNerdFont-') (TrueType)" -Value (Join-Path $fd $t.Name) -Force | Out-Null
        }
        Good 'font: CaskaydiaMono Nerd Font installed'
    } catch { Warn "font: could not install it ($($_.Exception.Message)); setup > Font does it later" }
    finally { Remove-Item $fz, $fx -Recurse -Force -ErrorAction SilentlyContinue }
}
Good "$changed of $($Map.Count) files updated"
if ($backedUp) { Info "$backedUp files that were there are saved in $Backup" }
# helix le a config de %APPDATA%\helix: uma juncao para ~\.config\helix (so se ainda nao existir)
$hx = Join-Path $env:APPDATA 'helix'
if (-not (Test-Path $hx)) { New-Item -ItemType Junction $hx -Target "$Cfg\helix" | Out-Null; Good 'helix config linked' }
# mpv: a interface (uosc) e as miniaturas (thumbfast), descarregadas pelo mpv-setup.ps1
if ((Test-Path $Pwsh) -and -not (Test-Path "$Cfg\mpv\scripts\uosc")) {
    Info 'mpv interface (uosc + thumbfast)...'
    try { & $Pwsh -NoProfile -ExecutionPolicy Bypass -File "$Cfg\mpv-setup.ps1" | Out-Null; Good 'mpv ready' } catch { Warn "mpv-setup failed: $($_.Exception.Message)" }
}

# ---------- 4. agent + Start menu ----------
Step 'Ctrl+Alt+T and the Start menu'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$agent = Join-Path $Local 'superterminal\agent.exe'
# (so recompila quando o agent.cs muda: o hash do que foi compilado fica ao lado)
$agentSrc = Join-Path $Repo 'terminal\agent\agent.cs'; $agentHash = (Get-FileHash $agentSrc).Hash
$built = ''; if (Test-Path "$agent.src") { $built = (Get-Content "$agent.src" -Raw).Trim() }
if ((Test-Path $agent) -and $built -eq $agentHash) { Good 'agent up to date' }
elseif (Test-Path $csc) {
    $out = & $csc /nologo /target:winexe "/out:$agent.new" (Join-Path $Repo 'terminal\agent\agent.cs') 2>&1
    if ($LASTEXITCODE -eq 0) {
        $running = @(Get-Process agent -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $agent })
        $kaTask = Get-ScheduledTask -TaskName TerminalKeepAlive -ErrorAction SilentlyContinue
        # (a correr e sem a tarefa do Kev, que troca o .new ao entrar: fecha-o, troca e volta a arrancar)
        if ($running -and -not $kaTask) { try { $running | Stop-Process -Force -ErrorAction Stop; Start-Sleep -Milliseconds 300; $running = @() } catch {} }
        # (com a tarefa do Kev o agente corre elevado: nem se ve o caminho dele; a tarefa troca o .new ao entrar)
        if ($running -or $kaTask) { Info 'the agent is running: the new one takes over at the next sign-in' }
        else {
            try { Move-Item "$agent.new" $agent -Force -ErrorAction Stop } catch { Info 'the agent is in use: the new one takes over at the next sign-in' }
            if (Get-Process wezterm-gui -ErrorAction SilentlyContinue) { Start-Process $agent } else { Start-Process $agent -ArgumentList '--prelaunch' }
        }
        Set-Content "$agent.src" $agentHash
        Good 'agent built'
    } else { Warn "could not build the agent: $out" }
} else { Warn '.NET Framework compiler not found: no Ctrl+Alt+T (the Start menu entry still works)' }
$sh = New-Object -ComObject WScript.Shell
$programs = [Environment]::GetFolderPath('Programs'); $startup = [Environment]::GetFolderPath('Startup')
$l = $sh.CreateShortcut("$programs\SuperTerminal.lnk")
$l.TargetPath = "$wz\wezterm-gui.exe"; $l.WorkingDirectory = $HOME; $l.IconLocation = "$wz\wezterm-gui.exe,0"; $l.Description = 'SuperTerminal'; $l.Save()
Good 'Start menu: SuperTerminal'
$keepAlive = Get-ScheduledTask -TaskName TerminalKeepAlive -ErrorAction SilentlyContinue   # (nos PCs do Kev o agente ja arranca elevado por esta tarefa)
if ((Test-Path $agent) -and -not $keepAlive) {
    # o agente arranca com o Windows (prelaunch: o 1.o Ctrl+Alt+T abre logo)
    $l = $sh.CreateShortcut("$startup\SuperTerminal agent.lnk")
    $l.TargetPath = $agent; $l.Arguments = '--prelaunch'; $l.WorkingDirectory = $HOME; $l.Save()
    if (-not (Get-Process agent -ErrorAction SilentlyContinue)) { Start-Process $agent -ArgumentList '--prelaunch' }
    Good 'Ctrl+Alt+T opens SuperTerminal (also after a restart)'
}

foreach ($k in $kept) { Warn "kept your local change: $k (the new version is next to it: $(Split-Path $k -Leaf).new)" }
if ($Quiet) { Write-Host "applied: $changed files updated$(if ($kept) { ", $($kept.Count) kept (changed on this PC)" })" }
else {
    Write-Host ''
    Write-Host '  Done. Open SuperTerminal (Start menu, or Ctrl+Alt+T).' -ForegroundColor Green
    Write-Host '  The first time, the setup opens by itself: font, Tailscale, YouTube, Stremio, logo, sudo.' -ForegroundColor DarkGray
    Write-Host ''
}
