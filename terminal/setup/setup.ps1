# SuperTerminal setup: o que precisa de uma conta ou de uma escolha antes de o terminal ficar 100%.
#   setup          -> ecra com os passos e o estado de cada um (enter faz / refaz o passo)
#   setup <passo>  -> vai direto a um passo: font, tailscale, youtube, stremio, logo, sudo
# Cada passo e uma pagina guiada: os passos numerados, o atual com as teclas de atalho (abrir o browser, escolher um
# ficheiro...), e cada um fica feito sozinho quando o setup o deteta. Credenciais (Stremio, Real-Debrid, Google) sao
# escritas pela pessoa, aqui ou no browser; nada fica fora de ~\.config.
param([string]$Step)

$e = [char]27
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$Cfg = "$HOME\.config"; $Pwsh = 'C:\Program Files\PowerShell\7\pwsh.exe'
$StCfg = "$Cfg\superterminal"; New-Item -ItemType Directory $StCfg -Force | Out-Null
$StremioApi = 'https://api.strem.io/api'; $StremioAuth = "$Cfg\stremio-auth.txt"
$FfConfig = "$Cfg\fastfetch\config.jsonc"
$Accent = '38;2;97;175;239'
$Chip = "$e[48;2;62;68;81;97m"

# ---------- ecra ----------
function Clear-Screen { [Console]::Write("$e[2J$e[3J$e[H") }
function Title([string]$icon, [string]$t) { Clear-Screen; [Console]::Write("`n  $e[1;${Accent}m$icon  $e[1;97m$t$e[0m`n`n") }
function Say([string]$t, [string]$c = '37') { [Console]::Write("  $e[${c}m$t$e[0m`n") }
# campo de texto: enter = pronto, esc = desistir (devolve $null); -Secret mostra pontos (o Read-Host nao deixava sair)
function Ask([string]$q, [switch]$Secret) {
    $row = [Console]::CursorTop + 1; $buf = [Text.StringBuilder]::new()
    while ($true) {
        $shown = if ($Secret) { [string][char]0x2022 * $buf.Length } else { "$buf" }
        [Console]::Write("$e[$row;1H$e[2K  $e[97m$q$e[0m $shown  $e[90m(esc: back)$e[0m$e[$row;$(4 + $q.Length + $shown.Length)H$e[?25h")
        $k = [Console]::ReadKey($true)
        switch ($k.Key) {
            'Escape' { [Console]::Write("$e[?25l`n"); return $null }
            'Enter' { [Console]::Write("$e[$row;1H$e[2K  $e[97m$q$e[0m $shown$e[?25l`n"); return "$buf" }
            'Backspace' { if ($buf.Length) { [void]$buf.Remove($buf.Length - 1, 1) }; continue }
        }
        if ([int]$k.KeyChar -ge 32) { [void]$buf.Append($k.KeyChar) }
    }
}
function Ask-Secret([string]$q) { Ask $q -Secret }
function Pause-Key { [Console]::Write("`n  $e[90many key to go on$e[0m"); [void][Console]::ReadKey($true) }
function Open-Url([string]$u) { Start-Process $u }
function Chips($list) { ($list | ForEach-Object { "$Chip $($_[0]) $e[0m $e[37m$($_[1])$e[0m" }) -join '   ' }
# escolha grande (ecras de "com ou sem"): cartoes numerados; devolve o numero ou 0 (esc)
function Pick-Card([string]$icon, [string]$title, [string]$q, $cards) {
    $sel = 0
    while ($true) {
        Title $icon $title; Say $q '97'; Say ''
        for ($i = 0; $i -lt $cards.Count; $i++) {
            $c = $cards[$i]; $on = $i -eq $sel
            $bar = if ($on) { "$e[${Accent}m$([char]0x258C)" } else { ' ' }
            [Console]::Write("  $bar $(if ($on) { "$e[1;97m" } else { "$e[37m" })$($i + 1)  $($c[0])$e[0m`n")
            foreach ($l in $c[1..($c.Count - 1)]) { [Console]::Write("  $bar    $e[90m$l$e[0m`n") }
            [Console]::Write("`n")
        }
        [Console]::Write("  $(Chips @(@('↑↓', 'choose'), @('enter', 'continue'), @('esc', 'back')))")
        $k = [Console]::ReadKey($true)
        switch ($k.Key) { 'UpArrow' { $sel = [Math]::Max(0, $sel - 1) } 'DownArrow' { $sel = [Math]::Min($cards.Count - 1, $sel + 1) } 'Enter' { return $sel + 1 } 'Escape' { return 0 } }
        if ("$($k.KeyChar)" -match '^[1-9]$' -and [int]"$($k.KeyChar)" -le $cards.Count) { return [int]"$($k.KeyChar)" }
    }
}

# ---------- motor das paginas guiadas ----------
# $G = @{ icon; title; intro = @(linhas); steps = @(passo...); end = 'texto no fim'; acts = @(@(tecla, texto, {acao})) }
# passo = @{ t = titulo; d = @(como fazer); done = {feito?} (sem done: carrega-se enter quando estiver feito);
#            note = {texto curto quando feito}; info = {linhas extra no passo atual}; acts = @(@(tecla, texto, {acao}));
#            every = segundos entre verificacoes (2) }
# $script:Msg = mensagem que uma acao deixa (verde / vermelha) por baixo dos passos
function Show-Guide($G) {
    $n = $G.steps.Count; $ok = @($false) * $n; $last = @([datetime]::MinValue) * $n; $script:Msg = $null
    $check = {
        param([switch]$Force)
        for ($i = 0; $i -lt $n; $i++) {
            $s = $G.steps[$i]; if (-not $s.done) { continue }
            $ev = if ($s.every) { $s.every } else { 2 }
            if ($Force -or ([datetime]::Now - $last[$i]).TotalSeconds -ge $ev) { $ok[$i] = [bool]$(try { & $s.done } catch { $false }); $last[$i] = [datetime]::Now }
        }
    }
    & $check -Force
    while ($true) {
        $cur = -1; for ($i = 0; $i -lt $n; $i++) { if (-not $ok[$i]) { $cur = $i; break } }
        $o = "$e[?2026h$e[2J$e[H`n  $e[1;${Accent}m$($G.icon)  $e[1;97m$($G.title)$e[0m`n`n"
        foreach ($l in @($G.intro)) { if ($l) { $o += "  $e[90m$l$e[0m`n" } }
        $o += "`n"
        for ($i = 0; $i -lt $n; $i++) {
            $s = $G.steps[$i]
            if ($ok[$i]) {
                $nt = if ($s.note) { try { "$(& $s.note)" } catch { '' } }
                $o += "  $e[32m$([char]0xf00c)  $e[90m$($i + 1)  $($s.t)$(if ($nt) { "   $e[32m$nt" })$e[0m`n"
            } elseif ($i -eq $cur) {
                $o += "`n  $e[${Accent}m$([char]0x258C) $e[1;97m$($i + 1)  $($s.t)$e[0m`n"
                foreach ($l in @($s.d)) { if ($null -ne $l) { $o += "  $e[${Accent}m$([char]0x258C)$e[0m    $e[37m$l$e[0m`n" } }
                if ($s.info) { foreach ($l in @(try { & $s.info } catch {})) { $o += "  $e[${Accent}m$([char]0x258C)$e[0m    $l$e[0m`n" } }
                $ks = @($s.acts | Where-Object { $_ } | ForEach-Object { , @($_[0], $_[1]) })
                if (-not $s.done) { $ks += , @('enter', 'done, next step') }
                if ($ks) { $o += "  $e[${Accent}m$([char]0x258C)$e[0m`n  $e[${Accent}m$([char]0x258C)$e[0m    $(Chips $ks)`n" }
                $o += "`n"
            } else { $o += "  $e[90m$([char]0xf10c)  $($i + 1)  $($s.t)$e[0m`n" }
        }
        if ($cur -lt 0) { $o += "`n  $e[1;32m$([char]0xf00c)  $(if ($G.end) { $G.end } else { 'all done' })$e[0m`n" }
        if ($script:Msg) { $o += "`n  $($script:Msg)$e[0m`n" }
        $gk = @($G.acts | Where-Object { $_ } | ForEach-Object { , @($_[0], $_[1]) }) + , @('esc', $(if ($cur -lt 0) { 'back' } else { 'back (it carries on next time)' }))
        $o += "`n  $(Chips $gk)$e[?2026l"
        [Console]::Write($o)
        # espera por tecla; entretanto volta a verificar (o passo fica feito sozinho e a pagina avanca)
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while (-not [Console]::KeyAvailable -and $sw.ElapsedMilliseconds -lt 1500) { Start-Sleep -Milliseconds 50 }
        if (-not [Console]::KeyAvailable) { & $check; continue }
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq 'Escape') { return }
        if ($k.Key -eq 'Enter') {
            if ($cur -lt 0) { return }
            if (-not $G.steps[$cur].done) { $ok[$cur] = $true; $script:Msg = $null }
            continue
        }
        $ch = "$($k.KeyChar)"
        $act = $null
        if ($cur -ge 0) { $act = @($G.steps[$cur].acts | Where-Object { $_ -and $_[0] -eq $ch } | Select-Object -First 1) }
        if (-not $act) { $act = @($G.acts | Where-Object { $_ -and $_[0] -eq $ch } | Select-Object -First 1) }
        if ($act) { $script:Msg = $null; [Console]::Write("$e[2J$e[H`n"); & $act[0][2]; & $check -Force }
    }
}

# ---------- 1. fonte ----------
$FontFile = "$StCfg\font.txt"
function Get-UserFonts { $p = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts' -ErrorAction Ignore; $q = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts' -ErrorAction Ignore; @($p, $q | Where-Object { $_ } | ForEach-Object { $_.PSObject.Properties.Name }) }
function Get-ChosenFont { if (Test-Path $FontFile) { "$(Get-Content $FontFile -TotalCount 1)".Trim() } }
function Test-FontInstalled([string]$fam) { $k = $fam -replace ' Nerd Font', ' NF'; [bool](Get-UserFonts | Where-Object { $_ -like "$fam*" -or $_ -like "$k*" }) }
function Select-FontFile {
    # janela do Windows para escolher o ficheiro (precisa de um thread STA); a frente do terminal
    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.Open()
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript({
            Add-Type -AssemblyName System.Windows.Forms
            $d = [Windows.Forms.OpenFileDialog]::new(); $d.Title = 'Choose a font (.zip, .ttf or .otf)'
            $d.Filter = 'Fonts (*.zip;*.ttf;*.otf)|*.zip;*.ttf;*.otf'; $d.InitialDirectory = (New-Object -ComObject Shell.Application).Namespace('shell:Downloads').Self.Path
            $owner = [Windows.Forms.Form]@{ TopMost = $true; ShowInTaskbar = $false; Width = 0; Height = 0; StartPosition = 'CenterScreen' }
            $owner.Show(); $owner.Activate()
            $r = if ($d.ShowDialog($owner) -eq 'OK') { $d.FileName }; $owner.Close(); $r
        })
    try { "$($ps.Invoke())" } finally { $ps.Dispose(); $rs.Close() }
}
function Install-Font([string]$path) {
    # .zip (todas as .ttf / .otf la dentro) ou um ficheiro; so para este utilizador. Devolve as familias
    $path = $path.Trim('"', ' ')
    if (-not (Test-Path $path)) { $script:Msg = "$e[31m$([char]0xf00d)  file not found: $path"; return @() }
    $tmp = Join-Path $env:TEMP "superterminal-font-$([guid]::NewGuid().ToString('N'))"; New-Item -ItemType Directory $tmp | Out-Null
    try {
        $files = if ($path -like '*.zip') { Expand-Archive $path $tmp; @(Get-ChildItem $tmp -Recurse -Include *.ttf, *.otf) } else { @(Get-Item $path) }
        if (-not $files) { $script:Msg = "$e[31m$([char]0xf00d)  no .ttf / .otf in that file"; return @() }
        Add-Type -AssemblyName System.Drawing
        $dst = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"; New-Item -ItemType Directory $dst -Force | Out-Null
        $reg = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'; $fams = @{}
        foreach ($f in $files) {
            $pfc = [Drawing.Text.PrivateFontCollection]::new(); try { $pfc.AddFontFile($f.FullName); $fam = $pfc.Families[0].Name } catch { continue } finally { $pfc.Dispose() }
            $to = Join-Path $dst $f.Name
            try { Copy-Item $f.FullName $to -Force -ErrorAction Stop } catch { }   # (ja instalada e em uso: fica a que la esta)
            New-ItemProperty $reg -Name "$fam $($f.BaseName -replace '^.*-') ($(if ($f.Extension -eq '.otf') { 'OpenType' } else { 'TrueType' }))" -Value $to -Force | Out-Null
            $fams[$fam] = 1 + [int]$fams[$fam]
        }
        @($fams.Keys | Sort-Object { -$fams[$_] })
    } finally { Remove-Item $tmp -Recurse -Force -ErrorAction Ignore }
}
function Use-Font([string]$fam) {
    Set-Content $FontFile $fam -Encoding utf8
    # o WezTerm recarrega o config (a 1.a vez ainda nao vigia o font.txt: tocar no wezterm.lua faz recarregar)
    $wl = "$Cfg\wezterm\wezterm.lua"; if (Test-Path $wl) { (Get-Item $wl).LastWriteTime = Get-Date }
    $script:Msg = "$e[32m$([char]0xf00c)  the terminal now uses $fam"
}
function Install-AndUse([string]$path) {
    $fams = @(Install-Font $path); if (-not $fams) { return }
    # (um .zip pode trazer variantes: Mono / Propo / normal -> prefere a Mono, que e a que alinha no terminal)
    $fam = @(@($fams | Where-Object { $_ -match 'Mono' -and $_ -notmatch 'Propo' }) + $fams)[0]
    if ($fams.Count -gt 1) {
        Title ([char]0xf031) 'Which one?'
        for ($i = 0; $i -lt [Math]::Min(9, $fams.Count); $i++) { Say "$Chip $($i + 1) $e[0m  $($fams[$i])$(if ($fams[$i] -eq $fam) { "   $e[90m(recommended)" })" }
        Say ''; Say 'enter = the recommended one' '90'
        $k = [Console]::ReadKey($true); if ("$($k.KeyChar)" -match '^[1-9]$' -and [int]"$($k.KeyChar)" -le $fams.Count) { $fam = $fams[[int]"$($k.KeyChar)" - 1] }
    }
    Use-Font $fam
}
$FontPage = @{
    icon = [char]0xf031; title = 'Font'
    intro = @('The terminal needs a Nerd Font: normal letters plus the icons of the prompt, the header and the apps.',
        'Keep the default one or use your own (any Nerd Font from nerdfonts.com).')
    steps = @(
        @{ t = 'Choose the font'
            d = @('o  pick a .zip / .ttf you downloaded (a window opens)', 'd  download and use the default, CaskaydiaMono Nerd Font', 'w  browse Nerd Fonts on nerdfonts.com (download a .zip, then press o)')
            # (sem escolha feita, a predefinida instalada tambem conta)
            done = { if ($f = Get-ChosenFont) { Test-FontInstalled $f } else { Test-FontInstalled 'CaskaydiaMono' } }
            note = { if ($f = Get-ChosenFont) { $f } else { 'CaskaydiaMono Nerd Font (the default)' } }
            acts = @(
                @('o', 'pick a file', { Say 'a window opened to choose the file (it may be behind this one)' '90'; $p = Select-FontFile; if ($p) { Say 'installing...' '90'; Install-AndUse $p } }),
                @('p', 'paste a path', { $p = Ask 'path of the .zip / .ttf:'; if ($p) { Install-AndUse $p } }),
                @('d', 'default font', {
                        Say 'downloading CaskaydiaMono Nerd Font (~40 MB)...' '90'
                        $z = Join-Path $env:TEMP "CascadiaMono-$([guid]::NewGuid().ToString('N')).zip"
                        & curl.exe -sL --fail -o $z 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaMono.zip'
                        if ($LASTEXITCODE) { $script:Msg = "$e[31m$([char]0xf00d)  the download failed" } else { Install-AndUse $z }
                        Remove-Item $z -ErrorAction Ignore
                    }),
                @('w', 'nerdfonts.com', { Open-Url 'https://www.nerdfonts.com/font-downloads' }))
        },
        @{ t = 'Check the icons'
            d = @('these should be little pictures, not empty boxes or question marks:')
            info = { "$e[36m   $([char]0xf07b)  $([char]0xf1d3)  $([char]0xf16a)  $([char]0xf0c2)  $([char]0xf120)  $([char]0xf00c)  $([char]0xe0b0)  $([char]0xf489)$e[0m" }
            acts = @(, @('o', 'try another font', { $p = Select-FontFile; if ($p) { Install-AndUse $p } }))
        }
    )
    end = 'font ready'
}

# ---------- 2. Tailscale ----------
function Get-TsExe { $c = Get-Command tailscale -ErrorAction Ignore; if ($c) { $c.Source } elseif (Test-Path "$env:ProgramFiles\Tailscale\tailscale.exe") { "$env:ProgramFiles\Tailscale\tailscale.exe" } }
function Get-Ts { $x = Get-TsExe; if (-not $x) { return $null }; try { & $x status --json 2>$null | ConvertFrom-Json } catch { $null } }

# PCs com nome para o ssh: ~\.config\superterminal\pcs.json (lido pelo perfil) + um "Host <nome>" no ~\.ssh\config
$PcsFile = "$StCfg\pcs.json"; $SshCfg = "$HOME\.ssh\config"; $SshExe = "$env:WINDIR\System32\OpenSSH\ssh.exe"
function Get-Pcs {
    # sem pcs.json ainda: os nomes que ja existiam no ~\.ssh\config (Host <nome> / HostName <pc no tailscale>) contam
    $l = if (Test-Path $PcsFile) { try { @(Get-Content $PcsFile -Raw | ConvertFrom-Json) } catch { @() } } else { @(Get-SshCfgHosts) }
    @($l | Where-Object { $_ } | ForEach-Object { $_ | Add-Member -NotePropertyName self -NotePropertyValue ($_.host -eq $env:COMPUTERNAME) -Force -PassThru })
}
function Get-SshCfgHosts {
    if (-not (Test-Path $SshCfg)) { return }
    $cur = $null
    foreach ($ln in Get-Content $SshCfg) {
        if ($ln -match '^\s*Host\s+(\S+)\s*$' -and $Matches[1] -notmatch '[*?]') { if ($cur -and $cur.host) { $cur }; $cur = [pscustomobject]@{ name = $Matches[1].ToLower(); host = $null; user = $null; shell = 'cmd' } }
        elseif ($cur -and $ln -match '^\s*HostName\s+(\S+)') { $cur.host = $Matches[1] }
        elseif ($cur -and $ln -match '^\s*User\s+(\S+)') { $cur.user = $Matches[1] }
    }
    if ($cur -and $cur.host) { $cur }
}
function Update-PcShell([string]$name) {
    # o shell do ssh de la (pwsh ou cmd): com o pwsh, o get / send corre direto nele (mais rapido)
    $out = "$(& $SshExe -n -o BatchMode=yes -o ConnectTimeout=3 $name 'echo %OS%' 2>$null)"
    $sh = if ($LASTEXITCODE) { return } elseif ($out -match 'Windows_NT') { 'cmd' } else { 'pwsh' }
    $pcs = @(Get-Pcs); foreach ($p in $pcs) { if ($p.name -eq $name) { $p.shell = $sh } }; Save-Pcs $pcs
}
function Save-Pcs($list) { ConvertTo-Json @($list | Select-Object name, host, user, shell, ip, mac) -Depth 3 | Set-Content $PcsFile -Encoding utf8 }
function Set-SshHost([string]$name, [string]$hn, [string]$user) {
    # troca (ou junta) o bloco "Host <nome>" do ~\.ssh\config; o IdentityFile que la estava fica. Copia antes
    New-Item -ItemType Directory (Split-Path $SshCfg) -Force | Out-Null
    $lines = if (Test-Path $SshCfg) { Copy-Item $SshCfg "$SshCfg.bak-setup" -Force; @(Get-Content $SshCfg) } else { @() }
    $out = [Collections.Generic.List[string]]::new(); $skip = $false; $key = $null
    foreach ($l in $lines) {
        if ($l -match '^\s*Host\s+(.+)$') { $skip = @($Matches[1].Trim() -split '\s+') -contains $name }
        if ($skip) { if ($l -match '^\s*IdentityFile\s+(.+)$') { $key = $Matches[1].Trim() } } else { $out.Add($l) }
    }
    if (-not $hn) { Set-Content $SshCfg $out -Encoding ascii; return }   # (sem host: so apaga)
    if (-not $key -and (Test-Path "$HOME\.ssh\id_ed25519")) { $key = '~/.ssh/id_ed25519' }
    while ($out.Count -and -not $out[$out.Count - 1].Trim()) { $out.RemoveAt($out.Count - 1) }
    if ($out.Count) { $out.Add('') }
    $out.Add("Host $name"); $out.Add("    HostName $hn"); if ($user) { $out.Add("    User $user") }; if ($key) { $out.Add("    IdentityFile $key") }; $out.Add('    ConnectTimeout 5')
    Set-Content $SshCfg $out -Encoding ascii
}
function Set-PcName {
    $s = Get-Ts; if (-not $s) { $script:Msg = "$e[31m$([char]0xf00d)  Tailscale is not running"; return }
    $devs = @(@($s.Self) + @($s.Peer.PSObject.Properties.Value | Sort-Object { -not $_.Online }, HostName) | Where-Object { $_.HostName })
    $pcs = @(Get-Pcs)
    Title ([char]0xf0c2) 'Name a PC'
    for ($i = 0; $i -lt [Math]::Min(9, $devs.Count); $i++) {
        $d = $devs[$i]; $has = $pcs | Where-Object { $_.host -eq $d.HostName } | Select-Object -First 1
        Say ("$Chip $($i + 1) $e[0m  {0,-20} $e[90m{1,-10} {2}$e[0m{3}" -f $d.HostName.ToLower(), $d.OS, $(if ($i -eq 0) { 'this PC' } elseif ($d.Online) { "$e[32monline" } else { 'offline' }), $(if ($has) { "   $e[36m= $($has.name)" }))
    }
    Say ''; Say 'which one? (esc: back)' '90'
    $k = [Console]::ReadKey($true); if ("$($k.KeyChar)" -notmatch '^[1-9]$' -or [int]"$($k.KeyChar)" -gt $devs.Count) { return }
    $d = $devs[[int]"$($k.KeyChar)" - 1]; $hn = $d.HostName
    $def = ($hn.ToLower() -replace '-[^-]+$') ; if (-not $def) { $def = $hn.ToLower() }
    $name = Ask "name for $($hn.ToLower()) (enter = $def):"; if ($null -eq $name) { return }
    $name = $name.Trim().ToLower(); if (-not $name) { $name = $def }
    if ($name -notmatch '^[a-z0-9][a-z0-9_-]*$') { $script:Msg = "$e[31m$([char]0xf00d)  use letters, numbers, - and _ only"; return }
    $self = $hn -eq $env:COMPUTERNAME
    $user = if ($self) { $env:USERNAME } else { $u = Ask "your user name on $name (enter = $env:USERNAME):"; if ($null -eq $u) { return }; $u = $u.Trim(); if ($u) { $u }else { $env:USERNAME } }
    # (um nome e um PC: tira o nome antigo deste PC e outro PC que ja tivesse este nome)
    $old = @($pcs | Where-Object { $_.host -eq $hn -or $_.name -eq $name })
    foreach ($o in $old) { if (-not $o.self) { Set-SshHost $o.name $null $null } }
    # (ip do Tailscale: o prompt mostra este PC nas pastas de rede dele; o mac, se ja havia, fica - e o do wake)
    $mac = @($old | Where-Object { $_.host -eq $hn } | ForEach-Object mac | Where-Object { $_ })[0]
    $sh = @($old | Where-Object { $_.host -eq $hn } | ForEach-Object shell | Where-Object { $_ })[0]; if (-not $sh) { $sh = 'cmd' }
    $pcs = @($pcs | Where-Object { $_ -notin $old }) + [pscustomobject]@{ name = $name; host = $hn; user = $user; shell = $sh; ip = @($d.TailscaleIPs | Where-Object { $_ -notlike '*:*' })[0]; mac = $mac }
    Save-Pcs $pcs
    if (-not $self) { Set-SshHost $name $hn $user; if (Test-SshKey $name) { Update-PcShell $name } }
    $script:Msg = "$e[32m$([char]0xf00c)  $(if ($self) { "this PC is $name" } else { "ssh $name now opens $($hn.ToLower())" })"
}
function Remove-PcName {
    $pcs = @(Get-Pcs); if (-not $pcs) { return }
    Title ([char]0xf0c2) 'Remove a name'
    for ($i = 0; $i -lt [Math]::Min(9, $pcs.Count); $i++) { Say "$Chip $($i + 1) $e[0m  $($pcs[$i].name)  $e[90m$($pcs[$i].host)$e[0m" }
    $k = [Console]::ReadKey($true); if ("$($k.KeyChar)" -notmatch '^[1-9]$' -or [int]"$($k.KeyChar)" -gt $pcs.Count) { return }
    $p = $pcs[[int]"$($k.KeyChar)" - 1]
    Save-Pcs @($pcs | Where-Object { $_.name -ne $p.name }); if (-not $p.self) { Set-SshHost $p.name $null $null }
    $script:Msg = "$e[90mremoved $($p.name)"
}
$KeyOk = @{}   # PC -> entra sem password? (guardado: o teste demora ~1 s)
function Test-SshKey([string]$name) {
    if ($KeyOk[$name] -and ([datetime]::Now - $KeyOk[$name].t).TotalSeconds -lt 30) { return $KeyOk[$name].ok }
    # (2 tentativas: o Windows do outro PC as vezes recusa uma sessao quando chegam varias juntas)
    $ok = $false; foreach ($try in 1, 2) { try { & $SshExe -n -o BatchMode=yes -o ConnectTimeout=3 $name exit 2>$null; $ok = $LASTEXITCODE -eq 0 } catch {}; if ($ok) { break }; Start-Sleep -Milliseconds 800 }
    $KeyOk[$name] = @{ ok = $ok; t = [datetime]::Now }; $ok
}
function Copy-SshKey {
    $o = @(Get-Pcs | Where-Object { -not $_.self }); if (-not $o) { $script:Msg = "$e[33mname a PC first (n)"; return }
    Title ([char]0xf0c2) 'Copy my key'
    for ($i = 0; $i -lt [Math]::Min(9, $o.Count); $i++) { Say "$Chip $($i + 1) $e[0m  $($o[$i].name)  $e[90m$($o[$i].host)$e[0m" }
    $k = [Console]::ReadKey($true); if ("$($k.KeyChar)" -notmatch '^[1-9]$' -or [int]"$($k.KeyChar)" -gt $o.Count) { return }
    $p = $o[[int]"$($k.KeyChar)" - 1]
    $KeyOk.Remove($p.name); if (Test-SshKey $p.name) { $script:Msg = "$e[32m$([char]0xf00c)  ssh $($p.name) already goes in without a password"; return }
    # o servidor de la aceita password? (pede-lhe so a lista de metodos, sem entrar) - se so aceitar chaves, a chave
    # tem de ser posta la a partir desse PC
    $meth = "$(& $SshExe -n -o BatchMode=yes -o PreferredAuthentications=none -o ConnectTimeout=5 "$($p.user)@$($p.host)" exit 2>&1)"
    if ($meth -match 'Permission denied \(([^)]*)\)' -and $Matches[1] -notmatch 'password|keyboard') {
        $script:Msg = "$e[33m$([char]0xf071)  $($p.name) only accepts keys, not passwords: on $($p.name), open setup > Tailscale > k and copy its key here, or add this PC's key there by hand"; return
    }
    if ($meth -match 'Connection (refused|timed out)|Could not resolve') { $script:Msg = "$e[31m$([char]0xf00d)  can't reach the SSH server on $($p.name) (step 4, on that PC)"; return }
    # chave deste PC (cria uma, sem frase-passe, se ainda nao houver)
    $kf = "$HOME\.ssh\id_ed25519"
    if (-not (Test-Path "$kf.pub")) { New-Item -ItemType Directory "$HOME\.ssh" -Force | Out-Null; & "$env:WINDIR\System32\OpenSSH\ssh-keygen.exe" -q -t ed25519 -N '' -f $kf; Set-SshHost $p.name $p.host $p.user }
    $pub = (Get-Content "$kf.pub" -Raw).Trim()
    # no outro PC: contas de administrador usam C:\ProgramData\ssh\administrators_authorized_keys (so Administradores
    # e SYSTEM podem ler, senao o sshd ignora-o); as outras, ~\.ssh\authorized_keys
    $remote = @"
`$k = '$pub'
`$adm = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (`$adm) { `$f = "`$env:ProgramData\ssh\administrators_authorized_keys" } else { New-Item -ItemType Directory "`$HOME\.ssh" -Force | Out-Null; `$f = "`$HOME\.ssh\authorized_keys" }
if (-not ((Test-Path `$f) -and (Select-String -Path `$f -SimpleMatch `$k -Quiet))) { Add-Content `$f `$k -Encoding ascii }
if (`$adm) { icacls `$f /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F' | Out-Null }
'key added'
"@
    $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($remote))
    Say "connecting to $($p.name): type your Windows password for $($p.user) on it when asked" '90'; Say ''
    & $SshExe -o PubkeyAuthentication=no -o ConnectTimeout=5 "$($p.user)@$($p.host)" "powershell -NoProfile -EncodedCommand $b64"
    $KeyOk.Remove($p.name)
    if (Test-SshKey $p.name) { Update-PcShell $p.name; $script:Msg = "$e[32m$([char]0xf00c)  ssh $($p.name) now goes in without a password" } else { $script:Msg = "$e[31m$([char]0xf00d)  it still asks for a password on $($p.name) (is the SSH server on there? step 4, on that PC)" }
}
function Enable-Sshd {
    # como administrador (o Windows pede): servidor OpenSSH (dism: o Add-WindowsCapability no pwsh 7 entra em ciclo),
    # servico automatico e a porta 22 na firewall
    $ps = @'
$ErrorActionPreference = 'Continue'
if (-not (Test-Path "$env:WINDIR\System32\OpenSSH\sshd.exe")) { 'installing OpenSSH Server (from Windows Update, can take a few minutes)...'; dism.exe /Online /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0 /NoRestart }
Set-Service sshd -StartupType Automatic; Start-Service sshd
if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) { New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null }
"sshd: $((Get-Service sshd).Status)"; Start-Sleep 2
'@
    $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ps))
    Say 'Windows asks for admin; the SSH server installs in that window' '90'
    try { Start-Process $Pwsh -Verb RunAs -Wait -ArgumentList '-NoProfile', '-EncodedCommand', $b64 } catch { $script:Msg = "$e[33mcancelled" }
}
$TsPage = @{
    icon = [char]0xf0c2; title = 'Tailscale'
    intro = @('Tailscale puts your PCs in one private network (free for personal use): ssh between them, get / send',
        'files and the PCs in the header. Do this on every PC, with the same account.')
    steps = @(
        @{ t = 'Install Tailscale'
            d = @('i  installs it with winget (Windows asks for admin), or download it from tailscale.com')
            done = { [bool](Get-TsExe) }
            acts = @(@('i', 'install', { winget install -e --id Tailscale.Tailscale; Pause-Key }), @('o', 'open tailscale.com/download', { Open-Url 'https://tailscale.com/download/windows' }))
        },
        @{ t = 'Sign in'
            d = @('s  opens the sign-in page in the browser: Google, Microsoft, GitHub... (any, but the same on every PC)',
                'or: the Tailscale icon next to the clock > Log in')
            done = { (Get-Ts).BackendState -eq 'Running' }
            note = { $s = Get-Ts; "$($s.Self.HostName.ToLower())  $($s.Self.TailscaleIPs[0])" }
            acts = @(, @('s', 'sign in', {
                        # "tailscale up" escreve o link de entrar: abre-o no browser
                        $f = "$env:TEMP\superterminal-ts-up.txt"; Remove-Item $f, "$f.out" -ErrorAction Ignore
                        $null = Start-Process (Get-TsExe) -ArgumentList 'up' -WindowStyle Hidden -RedirectStandardError $f -RedirectStandardOutput "$f.out" -PassThru
                        $u = $null
                        for ($i = 0; $i -lt 40; $i++) {
                            Start-Sleep -Milliseconds 250
                            $u = [regex]::Match("$(Get-Content $f, "$f.out" -Raw -ErrorAction Ignore)", 'https://login\.tailscale\.com/\S+').Value
                            if ($u) { Open-Url $u; break }
                            if ((Get-Ts).BackendState -eq 'Running') { break }
                        }
                        if (-not $u -and (Get-Ts).BackendState -ne 'Running') { $script:Msg = "$e[33m$([char]0xf071)  no sign-in link yet: use the Tailscale icon next to the clock > Log in" }
                    }))
        },
        @{ t = 'Add your other PCs'
            d = @('install Tailscale on each other PC and sign in with the same account: they show up here by themselves')
            done = { @((Get-Ts).Peer.PSObject.Properties.Value).Count -ge 1 }
            note = { $p = @((Get-Ts).Peer.PSObject.Properties.Value); "$($p.Count) other device$(if ($p.Count -ne 1) { 's' })" }
            acts = @(, @('o', 'open the admin page', { Open-Url 'https://login.tailscale.com/admin/machines' }))
        },
        @{ t = 'Let the other PCs ssh into this one'
            d = @('i  turns on the Windows SSH server on this PC (Windows asks for admin: it installs OpenSSH Server,',
                'starts it and opens port 22 in the firewall). Do it on every PC you want to reach.')
            done = { (Get-Service sshd -ErrorAction Ignore).Status -eq 'Running' }
            acts = @(, @('i', 'turn on the SSH server', { Enable-Sshd }))
        },
        @{ t = 'Name your PCs for ssh'
            d = @('n  pick a PC from your Tailscale network and give it a short name: then "ssh <name>" opens it',
                '(its Tailscale name works too). Name this PC as well, so the others know it.')
            info = { foreach ($p in Get-Pcs) { "$e[36m$($p.name)$e[90m  $([char]0x2192)  $($p.host)  $(if ($p.user) { "· $($p.user)" })$(if ($p.self) { '  (this PC)' })" } }
            done = { @(Get-Pcs | Where-Object { -not $_.self }).Count -ge 1 }
            note = { (@(Get-Pcs | ForEach-Object name) -join ', ') }
            acts = @(@('n', 'name a PC', { Set-PcName }), @('r', 'remove a name', { Remove-PcName }))
        },
        @{ t = 'Sign in to them without a password'
            d = @('k  copies this PC''s key to one of your PCs: its Windows password is asked once (type it there),',
                'after that ssh goes straight in. Do it for each PC.')
            info = { foreach ($p in @(Get-Pcs | Where-Object { -not $_.self })) { $ok = Test-SshKey $p.name; "$(if ($ok) { "$e[32m$([char]0xf00c)" } else { "$e[33m$([char]0xf10c)" })  $e[37m$($p.name)$e[90m  $(if ($ok) { 'no password' } else { 'asks for a password' })" } }
            done = { $o = @(Get-Pcs | Where-Object { -not $_.self }); $o -and -not @($o | Where-Object { -not (Test-SshKey $_.name) }) }; every = 15
            acts = @(, @('k', 'copy my key', { Copy-SshKey }))
        }
    )
    end = 'Tailscale ready: ssh <name> opens your other PCs'
    acts = @(, @('l', 'list devices', {
                $s = Get-Ts; Title ([char]0xf0c2) 'Devices'
                if ($s) { foreach ($p in @($s.Self) + @($s.Peer.PSObject.Properties.Value)) { Say ("{0,-20} {1,-16} {2}" -f $p.HostName.ToLower(), $p.TailscaleIPs[0], $(if ($p.Online) { "$e[32monline" } else { "$e[90moffline" })) } }
                Pause-Key
            }))
}

# ---------- 3. YouTube ----------
$ExtId = 'cclelndahbckbenkjhflpdbgdldlbecc'   # extensao "Get cookies.txt LOCALLY"
$YtCookies = "$Cfg\yt-cookies.txt"
function Get-Browser {
    # browser predefinido: executavel, pasta de dados (Chromium) e a opcao de janela privada (o mesmo do yt)
    $id = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice' -ErrorAction SilentlyContinue).ProgId
    $cmd = if ($id) { (Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\$id\shell\open\command" -ErrorAction SilentlyContinue).'(default)' }
    $exe = [regex]::Match("$cmd", '^"([^"]+)"').Groups[1].Value
    if (-not $exe -or -not (Test-Path $exe)) { return $null }
    $store = "https://chromewebstore.google.com/detail/$ExtId"
    switch ((Split-Path $exe -Leaf).ToLower()) {
        'brave.exe' { @{ exe = $exe; name = 'Brave'; priv = '--incognito'; data = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"; ext = $store; extPage = 'brave://extensions'; pw = 'private window' } }
        'chrome.exe' { @{ exe = $exe; name = 'Chrome'; priv = '--incognito'; data = "$env:LOCALAPPDATA\Google\Chrome\User Data"; ext = $store; extPage = 'chrome://extensions'; pw = 'incognito window' } }
        'msedge.exe' { @{ exe = $exe; name = 'Edge'; priv = '--inprivate'; data = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"; ext = $store; extPage = 'edge://extensions'; pw = 'InPrivate window' } }
        'firefox.exe' { @{ exe = $exe; name = 'Firefox'; priv = '-private-window'; data = $null; ext = 'https://addons.mozilla.org/firefox/addon/get-cookies-txt-locally/'; extPage = 'about:addons'; pw = 'private window' } }
        default { @{ exe = $exe; name = (Split-Path $exe -LeafBase); priv = '--incognito'; data = $null; ext = $store; extPage = 'the extensions page'; pw = 'private window' } }
    }
}
function Get-ExtState($b) {
    if (-not $b.data) { return @{ known = $false } }
    $prof = "$($b.data)\Default"; $priv = $false
    foreach ($pf in "$prof\Secure Preferences", "$prof\Preferences") { try { $j = Get-Content $pf -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable; if ($j.extensions.settings[$ExtId].incognito) { $priv = $true } } catch {} }
    @{ known = $true; installed = (Test-Path "$prof\Extensions\$ExtId"); private = $priv }
}
function Test-YtCookies([string]$f) {
    # o ficheiro tem uma sessao do YouTube? (yt-dlp sobre uma copia: ele reescreve o ficheiro de cookies)
    $yd = (Get-Command yt-dlp -ErrorAction Ignore).Source; if (-not $yd) { return $true }
    $c = "$env:TEMP\superterminal-ck-$([guid]::NewGuid().ToString('N')).txt"; Copy-Item $f $c
    try { [bool](& $yd ':ytsubs' --cookies $c --flat-playlist --playlist-end 1 --no-warnings --print id 2>$null) } finally { Remove-Item $c -ErrorAction Ignore }
}
function New-YtPage {
    $b = $script:YtB = Get-Browser; $bn = if ($b) { $b.name } else { 'the browser' }; $pw = if ($b) { $b.pw } else { 'private window' }
    $script:YtDl = (New-Object -ComObject Shell.Application).Namespace('shell:Downloads').Self.Path
    $script:YtSince = Get-Date; $script:YtGot = Test-Path $YtCookies
    $known = $b -and (Get-ExtState $b).known
    @{
        icon = [char]0xf16a; title = 'YouTube (yt)'
        intro = @("yt uses your YouTube account through a cookies file that $bn exports from a $pw.",
            '(from a normal window, YouTube signs the file out after a few hours; a private one keeps it valid)')
        steps = @(
            @{ t = 'Install the "Get cookies.txt LOCALLY" extension'
                d = @("e  opens its page in ${bn}: click Add / Add to $bn")
                done = $(if ($known) { { $script:YtGot -or (Get-ExtState $script:YtB).installed } } else { { $script:YtGot } })
                acts = @(, @('e', 'open the extension page', { if ($script:YtB) { Start-Process $script:YtB.exe -ArgumentList $script:YtB.ext } else { Open-Url "https://chromewebstore.google.com/detail/$ExtId" } }))
            },
            @{ t = "Allow it in the $pw"
                d = @("x  opens $(if ($b) { $b.extPage } else { 'the extensions page' }): Get cookies.txt LOCALLY > Details >",
                    $(if ($bn -eq 'Firefox') { 'Manage > Run in Private Windows > Allow' } else { "turn on `"Allow in $(if ($bn -eq 'Edge') { 'InPrivate' } else { 'Incognito' })`"" }))
                done = $(if ($known) { { $script:YtGot -or (Get-ExtState $script:YtB).private } } else { $null })
                acts = @(, @('x', 'open the extensions page', { if ($script:YtB) { Start-Process $script:YtB.exe -ArgumentList $script:YtB.extPage } }))
            },
            @{ t = "Sign in to YouTube in a $pw"
                d = @("p  opens a $pw on the Google sign-in page: sign in, and wait for youtube.com to load")
                done = { $script:YtGot }
                acts = @(, @('p', "open a $pw", { if ($script:YtB) { Start-Process $script:YtB.exe -ArgumentList $script:YtB.priv, 'https://accounts.google.com/ServiceLogin?service=youtube&continue=https://www.youtube.com/' } }))
            },
            @{ t = 'Export the cookies'
                d = @('on youtube.com, click the extension icon (puzzle piece > Get cookies.txt LOCALLY) > Export.',
                    "It saves to Downloads and the setup picks it up by itself. Then close the $pw.")
                done = {
                    if ($script:YtGot) { return $true }
                    $new = Get-ChildItem $script:YtDl -Filter '*cookies*.txt' -File -ErrorAction Ignore | Where-Object LastWriteTime -gt $script:YtSince | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    if (-not $new) { return $false }
                    Start-Sleep -Milliseconds 500; $script:YtSince = Get-Date
                    [Console]::Write("$e[2J$e[H`n  $e[90mfile received: checking the YouTube session...$e[0m")
                    if (Test-YtCookies $new.FullName) {
                        Copy-Item $new.FullName $YtCookies -Force; Remove-Item $new.FullName -ErrorAction Ignore; Remove-Item "$Cfg\yt-browser.txt" -ErrorAction Ignore
                        $script:YtGot = $true; $true
                    } else {
                        Remove-Item $new.FullName -ErrorAction Ignore
                        $script:Msg = "$e[31m$([char]0xf00d)  that file has no YouTube session: export it with youtube.com open and signed in"; $false
                    }
                }
                note = { 'signed in' }
            }
        )
        end = 'yt is signed in: run yt'
        acts = @(, @('r', 'sign out / start over', { Remove-Item $YtCookies, "$Cfg\yt-browser.txt" -ErrorAction Ignore; $script:YtGot = $false; $script:YtSince = Get-Date; $script:Msg = "$e[90msigned out of yt" }))
    }
}

# ---------- 4. Stremio ----------
function Invoke-Stremio([string]$method, $body) {
    $body.authKey = (Get-Content $StremioAuth -Raw).Trim()
    (Invoke-RestMethod -Method Post "$StremioApi/$method" -Body ($body | ConvertTo-Json -Depth 20) -ContentType 'application/json' -TimeoutSec 15).result
}
function Get-Res($a) { @($a.manifest.resources | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } }) }
function Get-StremioState {
    # o que a conta tem (pedido a API do Stremio; guardado 5 s para as verificacoes dos passos nao repetirem)
    if ($script:StState -and ([datetime]::Now - $script:StState.t).TotalSeconds -lt 5) { return $script:StState }
    $s = @{ t = [datetime]::Now; auth = $false; aio = $false; rd = 0; direct = 0 }
    if (Test-Path $StremioAuth) {
        try {
            $ad = @((Invoke-Stremio 'addonCollectionGet' @{ update = $true }).addons); $s.auth = $true
            $s.aio = [bool]@($ad | Where-Object { $_.manifest.name -match 'AIO ?Metadata' })
            $str = @($ad | Where-Object { (Get-Res $_) -contains 'stream' -and $_.transportUrl -notlike 'http://127.0.0.1*' })
            $s.rd = @($str | Where-Object { $_.manifest.name -match '\bRD\b|debrid' -or $_.transportUrl -match 'realdebrid' }).Count
            $s.direct = $str.Count - $s.rd
        } catch {}
    }
    $script:StState = $s; $s
}
$StLogin = {
    Title ([char]0xf26c) 'Sign in to Stremio'
    $mail = Ask 'email:'; if (-not $mail) { return }
    $pw = Ask-Secret 'password:'
    try {
        $r = Invoke-RestMethod -Method Post "$StremioApi/login" -Body (@{ email = $mail; password = $pw; type = 'Login' } | ConvertTo-Json) -ContentType 'application/json' -TimeoutSec 20
        if (-not $r.result.authKey) { throw 'no session' }
        Set-Content $StremioAuth $r.result.authKey -NoNewline; $script:StState = $null
    } catch { $script:Msg = "$e[31m$([char]0xf00d)  could not sign in (wrong email or password?)" } finally { $pw = $null }
}
function New-StremioPage([bool]$rd) {
    $acct = @{ t = 'Stremio account'
        d = @('s  sign in here with your Stremio account', 'c  no account yet? create one on stremio.com (free), then press s')
        done = { (Get-StremioState).auth }; every = 5
        note = { 'signed in' }
        acts = @(@('s', 'sign in', $StLogin), @('c', 'create an account', { Open-Url 'https://www.stremio.com/register' }))
    }
    $boot = @{ t = 'Set up the account with Stremio Account Bootstrapper'
        d = @('b  opens the bootstrapper: sign in there with the same Stremio account,',
            "pick the preset $(if ($rd) { '"standard"' } else { '"http-only" (no debrid)' }) and your language$(if ($rd) { ', Real-Debrid as the debrid service, and paste your key (k shows it)' }),",
            'then Install. It replaces the addons the account had (Backup there first if you want them back).')
        done = $(if ($rd) { { (Get-StremioState).rd -gt 0 } } else { { (Get-StremioState).direct -gt 0 } }); every = 5
        note = $(if ($rd) { { "$((Get-StremioState).rd) Real-Debrid addons" } } else { { "$((Get-StremioState).direct) addons with direct links" } })
        acts = $(if ($rd) { @(@('b', 'open the bootstrapper', { Open-Url 'https://bootstrapper.stremx.net' }), @('k', 'my Real-Debrid key', { Open-Url 'https://real-debrid.com/apitoken' })) } else { , @(, @('b', 'open the bootstrapper', { Open-Url 'https://bootstrapper.stremx.net' })) })
    }
    $aio = @{ t = 'AIOMetadata (catalogs and search in st)'
        d = @('a  opens AIOMetadata: configure it (the defaults are fine), then Install to your Stremio account')
        done = { (Get-StremioState).aio }; every = 5
        acts = @(, @('a', 'open AIOMetadata', { Open-Url 'https://aiometadata.elfhosted.com/configure' }))
    }
    $steps = @($acct)
    if ($rd) {
        $steps += @{ t = 'Real-Debrid premium'
            d = @('r  opens real-debrid.com: create an account and get premium (from ~3 € / month)', 'enter when the account is premium')
            done = { (Get-StremioState).rd -gt 0 }; every = 5
            acts = @(, @('r', 'open real-debrid.com', { Open-Url 'https://real-debrid.com/premium' }))
        }
    }
    $steps += $boot, $aio
    @{
        icon = [char]0xf26c; title = "Stremio (st) · $(if ($rd) { 'with Real-Debrid' } else { 'without debrid' })"
        intro = @('st shows the catalogs and streams of the addons on your Stremio account.')
        steps = $steps
        end = 'st is ready: run st'
        acts = @(, @('x', 'sign out of Stremio', { Remove-Item $StremioAuth -ErrorAction Ignore; $script:StState = $null }))
    }
}
function Show-StremioSetup {
    $c = Pick-Card ([char]0xf26c) 'Stremio (st)' 'How do you want to watch?' @(
        @('With Real-Debrid   (recommended)', 'fast streams for almost everything, in the best quality; Real-Debrid is paid (~3 € / month)'),
        @('Without debrid   (free)', 'only addons with direct links: a smaller choice, and some titles have nothing'))
    if ($c) { Set-Content "$StCfg\stremio-mode.txt" $(if ($c -eq 1) { 'rd' } else { 'free' }); Show-Guide (New-StremioPage ($c -eq 1)) }
}

# ---------- 5. logo do cabecalho ----------
# letras 5x5 ('#' = bloco "██")
$Glyphs = @{
    A = ' ### |#   #|#####|#   #|#   #'; B = '#### |#   #|#### |#   #|#### '; C = ' ####|#    |#    |#    | ####'; D = '#### |#   #|#   #|#   #|#### '
    E = '#####|#    |#### |#    |#####'; F = '#####|#    |#### |#    |#    '; G = ' ####|#    |#  ##|#   #| ####'; H = '#   #|#   #|#####|#   #|#   #'
    I = '#####|  #  |  #  |  #  |#####'; J = '#####|   # |   # |#  # | ##  '; K = '#   #|#  # |###  |#  # |#   #'; L = '#    |#    |#    |#    |#####'
    M = '#   #|## ##|# # #|#   #|#   #'; N = '#   #|##  #|# # #|#  ##|#   #'; O = ' ### |#   #|#   #|#   #| ### '; P = '#### |#   #|#### |#    |#    '
    Q = ' ### |#   #|# # #|#  # | ## #'; R = '#### |#   #|#### |#  # |#   #'; S = ' ####|#    | ### |    #|#### '; T = '#####|  #  |  #  |  #  |  #  '
    U = '#   #|#   #|#   #|#   #| ### '; V = '#   #|#   #|#   #| # # |  #  '; W = '#   #|#   #|# # #|## ##|#   #'; X = '#   #| # # |  #  | # # |#   #'
    Y = '#   #| # # |  #  |  #  |  #  '; Z = '#####|   # |  #  | #   |#####'
    '0' = ' ### |#  ##|# # #|##  #| ### '; '1' = '  #  | ##  |  #  |  #  | ### '; '2' = ' ### |#   #|  ## | #   |#####'; '3' = '#### |    #| ### |    #|#### '
    '4' = '#   #|#   #|#####|    #|    #'; '5' = '#####|#    |#### |    #|#### '; '6' = ' ### |#    |#### |#   #| ### '; '7' = '#####|    #|   # |  #  |  #  '
    '8' = ' ### |#   #| ### |#   #| ### '; '9' = ' ### |#   #| ####|    #| ### '; '-' = '     |     | ### |     |     '; ' ' = '   |   |   |   |   '
}
function ConvertTo-BlockArt([string]$text) {
    $rows = @('', '', '', '', '')
    foreach ($ch in $text.ToUpper().ToCharArray()) {
        $g = $Glyphs["$ch"]; if (-not $g) { continue }
        $p = $g -split '\|'
        for ($i = 0; $i -lt 5; $i++) { $rows[$i] += ($p[$i] -replace '#', ([string][char]0x2588 * 2) -replace ' ', '  ') + ' ' }
    }
    @($rows | ForEach-Object { $_.TrimEnd() })
}
$Palettes = @(@('one dark', 'blue', 'cyan', 'magenta'), @('sunset', 'red', 'yellow', 'magenta'), @('forest', 'green', 'cyan', 'blue'), @('mono', 'white', 'white', 'white'))
$AnsiOf = @{ blue = '34'; cyan = '36'; magenta = '35'; red = '31'; yellow = '33'; green = '32'; white = '97' }
function Get-Logo {
    $t = [IO.File]::ReadAllText($FfConfig)
    $m = [regex]::Match($t, '"logo"\s*:\s*\{[^}]*?"source"\s*:\s*"((?:[^"\\]|\\.)*)"')
    $lines = if ($m.Success) { @(($m.Groups[1].Value -replace '\\n', "`n" -replace '\$\d', '' -replace '\\"', '"' -replace '\\\\', '\') -split "`n") } else { @() }
    $cm = [regex]::Match($t, '"color"\s*:\s*\{\s*"1"\s*:\s*"(\w+)"\s*,\s*"2"\s*:\s*"(\w+)"\s*,\s*"3"\s*:\s*"(\w+)"')
    @{ lines = $lines; colors = $(if ($cm.Success) { @($cm.Groups[1].Value, $cm.Groups[2].Value, $cm.Groups[3].Value) } else { @('blue', 'cyan', 'magenta') }) }
}
function Get-RowColor([int]$i, [int]$n) { if ($i -lt [Math]::Ceiling($n * 0.4)) { 1 } elseif ($i -lt [Math]::Ceiling($n * 0.6)) { 2 } else { 3 } }
function Save-Logo($lines, $colors) {
    # so o "source" e as cores do logo mudam no config.jsonc (o resto, com os comentarios, fica igual); copia antes
    Copy-Item $FfConfig "$FfConfig.bak-setup" -Force
    $src = (@(for ($i = 0; $i -lt $lines.Count; $i++) { "`$$(Get-RowColor $i $lines.Count)" + ($lines[$i] -replace '\\', '\\' -replace '"', '\"') }) -join '\n')
    $t = [IO.File]::ReadAllText($FfConfig)
    $t = [regex]::Replace($t, '("logo"\s*:\s*\{[^}]*?"source"\s*:\s*)"(?:[^"\\]|\\.)*"', { param($m) $m.Groups[1].Value + '"' + $src + '"' })
    # (so o "color" do logo, o que tem a chave "1"; o do "display" fica)
    $t = [regex]::new('"color"\s*:\s*\{\s*"1"[^}]*\}').Replace($t, "`"color`": { `"1`": `"$($colors[0])`", `"2`": `"$($colors[1])`", `"3`": `"$($colors[2])`" }", 1)
    [IO.File]::WriteAllText($FfConfig, $t, [Text.UTF8Encoding]::new($false))
    New-Item "$env:TEMP\superterminal-header-redraw" -Force | Out-Null   # o cabecalho redesenha-se ja
}

# editor: tela de $CW x $CH celulas; rato (arrastar pinta, botao direito apaga) e teclado
Add-Type -Namespace Su -Name Con -MemberDefinition @'
[StructLayout(LayoutKind.Explicit)] public struct IR {
    [FieldOffset(0)] public ushort Type; [FieldOffset(4)] public int KeyDown; [FieldOffset(10)] public ushort VK; [FieldOffset(14)] public char Ch;
    [FieldOffset(4)] public short MX; [FieldOffset(6)] public short MY; [FieldOffset(8)] public uint Btn; [FieldOffset(16)] public uint Flags; }
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
[DllImport("kernel32.dll")] public static extern bool GetNumberOfConsoleInputEvents(IntPtr h, out uint n);
[DllImport("kernel32.dll", EntryPoint = "ReadConsoleInputW")] public static extern bool ReadConsoleInput(IntPtr h, [Out] IR[] b, uint n, out uint got);
'@
function Edit-Logo {
    $CW = 60; $CH = 9; $l = Get-Logo; $pal = $l.colors; $brush = 2
    $cv = [char[][]]::new($CH); for ($r = 0; $r -lt $CH; $r++) { $cv[$r] = (' ' * $CW).ToCharArray() }
    $load = { param($lines) for ($r = 0; $r -lt $CH; $r++) { $cv[$r] = (' ' * $CW).ToCharArray(); if ($r -lt @($lines).Count) { $s = "$(@($lines)[$r])"; for ($c = 0; $c -lt [Math]::Min($CW, $s.Length); $c++) { $cv[$r][$c] = $s[$c] } } } }
    & $load $l.lines
    $cx = 0; $cy = 0; $top = 6; $left = 4   # (tela no ecra: linha $top, coluna $left)
    $art = {
        # linhas pintadas (sem as vazias de cima / baixo, nem o espaco a direita)
        $rows = @($cv | ForEach-Object { (-join $_).TrimEnd() })
        $a = 0; while ($a -lt $rows.Count -and -not $rows[$a]) { $a++ }
        $b = $rows.Count - 1; while ($b -ge $a -and -not $rows[$b]) { $b-- }
        if ($a -gt $b) { @() } else { @($rows[$a..$b]) }
    }
    $draw = {
        $used = @(for ($r = 0; $r -lt $CH; $r++) { if ((-join $cv[$r]).Trim()) { $r } })
        $f = if ($used) { $used[0] } else { 0 }; $n = if ($used) { $used[-1] - $f + 1 } else { 1 }
        $pn = ($Palettes | Where-Object { $_[1] -eq $pal[0] -and $_[3] -eq $pal[2] } | Select-Object -First 1)
        $o = "$e[?2026h$e[H`n  $e[1;${Accent}m$([char]0xf03e)  $e[1;97mHeader logo$e[0m`n`n  $e[90mdraw with the mouse (left paints, right erases) or the keys; the colours go top to bottom like in the header$e[0m"
        $o += "$e[$($top - 1);$($left - 1)H$e[90m$([char]0x256D)" + ([string][char]0x2500 * $CW) + "$([char]0x256E)"
        for ($r = 0; $r -lt $CH; $r++) {
            $col = $AnsiOf[$pal[(Get-RowColor ($r - $f) $n) - 1]]
            $o += "$e[$($top + $r);$($left - 1)H$e[90m$([char]0x2502)$e[48;2;33;37;43m"
            for ($c = 0; $c -lt $CW; $c++) {
                $cc = $cv[$r][$c]
                if ($r -eq $cy -and $c -ge $cx -and $c -lt $cx + $brush) { $o += "$e[48;2;97;175;239;30m$cc$e[0;48;2;33;37;43m" }
                elseif ($cc -eq ' ') { $o += "$e[38;2;55;60;70m$(if ($c % 2 -eq 0 -and $r % 2 -eq 0) { [char]0x00B7 } else { ' ' })" }
                else { $o += "$e[${col}m$cc" }
            }
            $o += "$e[0;90m$([char]0x2502)"
        }
        $o += "$e[$($top + $CH);$($left - 1)H$e[90m$([char]0x2570)" + ([string][char]0x2500 * $CW) + "$([char]0x256F)$e[0m"
        $o += "$e[$($top + $CH + 2);3H$e[2K$(Chips @(@('drag', 'paint'), @('right drag', 'erase'), @('arrows', 'move'), @('space', 'paint / erase'), @('b', "brush $brush wide")))"
        $o += "$e[$($top + $CH + 4);3H$e[2K$(Chips @(@('t', 'from text'), @('1-4', "colours: $(if ($pn) { $pn[0] } else { 'custom' })"), @('c', 'clear'), @('u', 'undo all'), @('enter', 'save'), @('esc', 'cancel')))"
        $o += "$e[$($top + $CH + 6);3H$e[2K$(if ($script:Msg) { "$($script:Msg)$e[0m" })"
        [Console]::Write("$o$e[?2026l")
    }
    $paint = { param($r, $c, [char]$v) for ($i = 0; $i -lt $brush; $i++) { if ($r -ge 0 -and $r -lt $CH -and $c + $i -ge 0 -and $c + $i -lt $CW) { $cv[$r][$c + $i] = $v } } }
    $inH = [Su.Con]::GetStdHandle(-10); $mode0 = 0; [void][Su.Con]::GetConsoleMode($inH, [ref]$mode0)
    $mouseMode = { [void][Su.Con]::SetConsoleMode($inH, ((($mode0 -bor 0x10 -bor 0x80) -band (-bnot 0x40)) -band (-bnot 0x200))) }   # rato sim, QuickEdit e VT nao
    $buf = [Su.Con+IR[]]::new(64); $script:Msg = $null
    Clear-Screen; & $mouseMode; & $draw
    try {
        while ($true) {
            $nEv = 0; [void][Su.Con]::GetNumberOfConsoleInputEvents($inH, [ref]$nEv)
            if (-not $nEv) { Start-Sleep -Milliseconds 15; continue }
            $got = 0; [void][Su.Con]::ReadConsoleInput($inH, $buf, 64, [ref]$got); $dirty = $false
            for ($i = 0; $i -lt $got; $i++) {
                $ev = $buf[$i]
                if ($ev.Type -eq 2) {
                    # rato: celula da tela por baixo do ponteiro (so cliques e movimentos; a roda nao)
                    $r = $ev.MY + 1 - $top; $c = $ev.MX + 1 - $left
                    if ($r -ge 0 -and $r -lt $CH -and $c -ge 0 -and $c -lt $CW -and ($ev.Flags -eq 0 -or $ev.Flags -eq 1)) {
                        $cx = [Math]::Max(0, [Math]::Min($c, $CW - $brush)); $cy = $r
                        if ($ev.Btn -band 1) { & $paint $r $cx ([char]0x2588) } elseif ($ev.Btn -band 2) { & $paint $r $cx ' ' }
                        $dirty = $true
                    }
                }
                elseif ($ev.Type -eq 1 -and $ev.KeyDown) {
                    $dirty = $true; $script:Msg = $null
                    switch ($ev.VK) {
                        0x25 { $cx = [Math]::Max(0, $cx - 1) } 0x27 { $cx = [Math]::Min($CW - $brush, $cx + 1) }
                        0x26 { $cy = [Math]::Max(0, $cy - 1) } 0x28 { $cy = [Math]::Min($CH - 1, $cy + 1) }
                        0x20 { & $paint $cy $cx $(if ($cv[$cy][$cx] -eq ' ') { [char]0x2588 } else { ' ' }) }
                        0x1B { if ($env:SUPERTERMINAL_SETUP_DUMP) { @($cv | ForEach-Object { "[" + (-join $_) + "]" }) | Set-Content $env:SUPERTERMINAL_SETUP_DUMP -Encoding utf8 }; return }   # (testes: a tela num ficheiro)
                        0x0D { $a = & $art; if (-not $a) { $script:Msg = "$e[33mthe logo is empty" } else { Save-Logo $a $pal; return } }
                    }
                    switch -CaseSensitive ("$($ev.Ch)") {
                        'b' { $brush = 3 - $brush; $cx = [Math]::Min($cx, $CW - $brush) }
                        'c' { & $load @() }
                        'u' { & $load $l.lines; $pal = $l.colors }
                        { $_ -in '1', '2', '3', '4' } { $pal = $Palettes[[int]$_ - 1][1..3] }
                        't' {
                            [void][Su.Con]::SetConsoleMode($inH, $mode0)
                            [Console]::Write("$e[$($top + $CH + 6);1H$e[2K"); $txt = "$(Ask 'text:')".Trim()
                            & $mouseMode
                            if ($txt) {
                                $a = ConvertTo-BlockArt $txt
                                if (($a | Measure-Object Length -Maximum).Maximum -gt $CW) { $script:Msg = "$e[33mtoo wide: fewer letters" } else { & $load (@('') + $a) }
                            }
                            Clear-Screen
                        }
                    }
                }
            }
            if ($dirty) { & $draw }
        }
    } finally { [void][Su.Con]::SetConsoleMode($inH, $mode0) }
}

# ---------- 6. sudo ----------
function Get-SudoMode { (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo' -ErrorAction Ignore).Enabled }
$SudoPage = if ([Environment]::OSVersion.Version.Build -ge 22000) {
    @{ icon = [char]0xf132; title = 'sudo'
        intro = @('sudo <command> runs one command as admin, like on Linux. Windows 11 has it built in, off by default.')
        steps = @(
            @{ t = 'Turn on sudo'
                d = @('o  opens Settings > System > For developers: turn on "Enable sudo"')
                done = { [int](Get-SudoMode) -gt 0 }
                acts = @(, @('o', 'open the settings', { Start-Process 'ms-settings:developers' }))
            },
            @{ t = 'Choose "Inline"'
                d = @('in the same place, "Configure how sudo runs applications" > Inline: it runs in the same window')
                done = { [int](Get-SudoMode) -eq 3 }
                acts = @(, @('o', 'open the settings', { Start-Process 'ms-settings:developers' }))
            })
        end = 'sudo is on' }
} else {
    @{ icon = [char]0xf132; title = 'sudo'
        intro = @('sudo <command> runs one command as admin. Windows 10 has no sudo: gsudo does the same.')
        steps = @(@{ t = 'Install gsudo'; d = @('i  installs it with winget'); done = { Test-Path "$env:ProgramFiles\gsudo\Current\gsudo.exe" }; acts = @(, @('i', 'install', { winget install -e --id gerardog.gsudo; Pause-Key })) })
        end = 'sudo is on' }
}

# ---------- ecra principal ----------
$Steps = [ordered]@{
    font = @{ icon = [char]0xf031; name = 'Font'; run = { Show-Guide $FontPage }
        check = { $f = Get-ChosenFont; if ($f -and (Test-FontInstalled $f)) { @{ ok = $true; text = $f } } elseif (Test-FontInstalled 'CaskaydiaMono') { @{ ok = $true; text = 'CaskaydiaMono Nerd Font' } } else { @{ ok = $false; text = 'no Nerd Font yet' } } } }
    tailscale = @{ icon = [char]0xf0c2; name = 'Tailscale'; run = { Show-Guide $TsPage }
        check = { $s = Get-Ts; if (-not $s) { @{ ok = $false; text = 'not installed' } } elseif ($s.BackendState -ne 'Running') { @{ ok = $false; text = 'not signed in' } } else { $p = @($s.Peer.PSObject.Properties.Value); @{ ok = $true; text = "$($s.Self.HostName.ToLower()) · $(@($p | Where-Object Online).Count + 1)/$($p.Count + 1)" } } } }
    youtube = @{ icon = [char]0xf16a; name = 'YouTube (yt)'; run = { Show-Guide (New-YtPage) }
        check = { if (Test-Path $YtCookies) { @{ ok = $true; text = 'signed in' } } else { @{ ok = $false; text = 'not signed in (yt asks for it when it opens)' } } } }
    stremio = @{ icon = [char]0xf26c; name = 'Stremio (st)'; run = { Show-StremioSetup }
        check = { if (Test-Path $StremioAuth) { $m = if (Test-Path "$StCfg\stremio-mode.txt") { if ((Get-Content "$StCfg\stremio-mode.txt") -eq 'rd') { ' · Real-Debrid' } else { ' · without debrid' } }; @{ ok = $true; text = "signed in$m" } } else { @{ ok = $false; text = 'not set up' } } } }
    logo = @{ icon = [char]0xf03e; name = 'Header logo'; run = { Edit-Logo }
        check = { $l = Get-Logo; if ($l.lines.Count) { @{ ok = $true; text = "$($l.lines.Count) lines · $($l.colors -join ' / ')" } } else { @{ ok = $false; text = 'no logo' } } } }
    sudo = @{ icon = [char]0xf132; name = 'sudo'; run = { Show-Guide $SudoPage }
        check = {
            if ([Environment]::OSVersion.Version.Build -ge 22000) { switch ([int](Get-SudoMode)) { 3 { @{ ok = $true; text = 'inline' } } 0 { @{ ok = $false; text = 'off' } } default { @{ ok = $true; text = 'on (inline is nicer)' } } } }
            elseif (Test-Path "$env:ProgramFiles\gsudo\Current\gsudo.exe") { @{ ok = $true; text = 'gsudo' } } else { @{ ok = $false; text = 'gsudo is not installed' } }
        } }
}
function Show-Menu {
    $keys = @($Steps.Keys); $sel = 0; $st = @{}
    foreach ($k in $keys) { $st[$k] = try { & $Steps[$k].check } catch { @{ ok = $false; text = "$_" } } }
    while ($true) {
        Title ([char]0xf120) 'SuperTerminal setup'
        for ($i = 0; $i -lt $keys.Count; $i++) {
            $s = $Steps[$keys[$i]]; $r = $st[$keys[$i]]
            $mark = if ($r.ok) { "$e[32m$([char]0xf00c)" } else { "$e[33m$([char]0xf111)" }
            $line = "{0}  {1}  {2,-16}" -f ($i + 1), $s.icon, $s.name
            if ($i -eq $sel) { [Console]::Write("  $e[${Accent}m$([char]0x258C)$e[48;2;62;68;81;1;97m $line $e[0m  $mark  $e[0;37m$($r.text)$e[0m`n") }
            else { [Console]::Write("   $e[37m $line $e[0m  $mark  $e[90m$($r.text)$e[0m`n") }
        }
        [Console]::Write("`n  $(Chips @(@('↑↓', 'choose'), @('enter', 'set up'), @('q', 'done')))")
        $k = [Console]::ReadKey($true)
        switch ($k.Key) {
            'UpArrow' { $sel = ($sel - 1 + $keys.Count) % $keys.Count; continue }
            'DownArrow' { $sel = ($sel + 1) % $keys.Count; continue }
            'Escape' { return }
            'Enter' { $script:Msg = $null; & $Steps[$keys[$sel]].run; $st[$keys[$sel]] = try { & $Steps[$keys[$sel]].check } catch { @{ ok = $false; text = "$_" } }; continue }
        }
        if ($k.KeyChar -eq 'q') { return }
        if ("$($k.KeyChar)" -match '^[1-9]$' -and [int]"$($k.KeyChar)" -le $keys.Count) { $sel = [int]"$($k.KeyChar)" - 1 }
    }
}

if ($env:SUPERTERMINAL_SETUP_TEST) { return }   # (testes: so as funcoes)
[Console]::Write("$e[?1049h$e[?25l")
try {
    if ($Step) { if ($Steps.Contains($Step)) { & $Steps[$Step].run } else { Say "no step '$Step' (steps: $($Steps.Keys -join ', '))" '31'; Pause-Key } }
    else { Show-Menu }
    # (so depois de sair do menu: se a janela fechou antes de ser vista - WezTerm a falhar, janela escondida - o
    # perfil volta a abrir o setup da proxima vez)
    Set-Content "$StCfg\setup-seen" (Get-Date -Format s)
}
finally { [Console]::Write("$e[0m$e[?25h$e[?1049l") }
