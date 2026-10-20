# st-tui: Stremio no terminal — grelha de posters (sixel via chafa) com filtros (tipo, género, ordem), pesquisa,
# favoritos (locais), página do título com episódios,
# streams de todos os addons instalados na conta Stremio (Torrentio, Comet, MediaFusion...) e reprodução no mpv.
#   st            -> explorar (filmes em alta)      st <pesquisa> -> pesquisa      ? -> atalhos
# Os addons vêm da API do Stremio com a sessão em ~\.config\stremio-auth.txt (nada passa pela app).
param([Parameter(ValueFromRemainingArguments = $true)] [string[]]$Rest)

$e = [char]27
. "$HOME\.config\st-theme.ps1"   # cores do tema ($StTheme)
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # (aberto sem o perfil, ex.: separador do pin ou do WSL, os icones e molduras viravam "?")
$MpvDir = Split-Path (@((Get-Command mpv -ErrorAction SilentlyContinue).Source, 'C:\Program Files\MPV Player\mpv.exe', "$HOME\.local\mpv\mpv.exe") | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1)
$MpvWin = Join-Path $MpvDir 'mpv.exe'
$Chafa = (Get-Command chafa).Source
$Dir = "$env:TEMP\st"; $SixDir = "$Dir\six"; New-Item -ItemType Directory $SixDir -Force | Out-Null
Get-ChildItem $Dir -File -Recurse | Where-Object LastWriteTime -lt (Get-Date).AddDays(-14) | ForEach-Object { [IO.File]::Delete($_.FullName) }
$AuthFile = "$HOME\.config\stremio-auth.txt"
$ProgFile = "$HOME\.config\st-progress.json"     # progresso local (posição de cada filme/episódio)
$SearchFile = "$HOME\.config\st-searches.txt"
$Api = 'https://api.strem.io/api'
$Sixel = [hashtable]::Synchronized(@{})          # imagens sixel prontas (partilhado com os threads)
$Net = [hashtable]::Synchronized(@{})            # respostas dos addons (partilhado com os threads)
$Accent = '38;2;198;120;221'                             # roxo do Stremio
$MpvOpts = @("--config-dir=$HOME\.config\mpv")
function Quote-Args($a) { $a | ForEach-Object { if ("$_" -match '[\s"]') { "`"$($_ -replace '"', '\"')`"" } else { "$_" } } }

# teclado: modo da consola reposto antes de cada tecla (programas externos podem ligar a entrada VT)
Add-Type -Namespace W -Name Con -MemberDefinition @"
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
"@ -ErrorAction SilentlyContinue
$InH = [W.Con]::GetStdHandle(-10); $InMode = 0; [void][W.Con]::GetConsoleMode($InH, [ref]$InMode)
# (rato ligado: 0x10 + extended 0x80, sem quick edit 0x40 e sem entrada VT 0x200)
$InModeSt = (($InMode -band (-bnot 0x200)) -band (-bnot 0x40)) -bor 0x10 -bor 0x80
function Read-Key { [void][W.Con]::SetConsoleMode($InH, $InModeSt); [Console]::ReadKey($true) }
Add-Type -Namespace St -Name Mouse -MemberDefinition @"
[StructLayout(LayoutKind.Explicit, Size = 20)] public struct IR { [FieldOffset(0)] public ushort Type; [FieldOffset(4)] public short MX; [FieldOffset(6)] public short MY; [FieldOffset(8)] public int Btn; [FieldOffset(16)] public int Flags; }
[DllImport("kernel32.dll")] static extern bool GetNumberOfConsoleInputEvents(IntPtr h, out uint n);
[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool PeekConsoleInputW(IntPtr h, [Out] IR[] b, uint n, out uint r);
[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool ReadConsoleInputW(IntPtr h, [Out] IR[] b, uint n, out uint r);
public static int X, Y, Wheel;
// tira da fila os eventos do rato (o .NET deita-os fora): 0 nada, 1 clique, 2 roda (Wheel +/-), 3 so mexeu (como no yt)
public static int Read(IntPtr h) {
    int r = 0; Wheel = 0; var b = new IR[32]; uint n, got;
    while (r != 1 && GetNumberOfConsoleInputEvents(h, out n) && n > 0 && PeekConsoleInputW(h, b, Math.Min(n, 32u), out got) && got > 0) {
        uint k = 0; bool stop = false;
        while (k < got && b[k].Type == 2) {
            int fl = b[k].Flags;
            if (fl == 4) { r = 2; Wheel += (short)(b[k].Btn >> 16) > 0 ? 1 : -1; X = b[k].MX; Y = b[k].MY; }
            else if ((fl == 0 || fl == 2) && (b[k].Btn & 1) != 0) { if (r == 2) { stop = true; break; } r = 1; X = b[k].MX; Y = b[k].MY; k++; stop = true; break; }
            else if (fl == 1 && (r == 0 || r == 3)) { r = 3; X = b[k].MX; Y = b[k].MY; }
            k++;
        }
        if (k == 0) break;
        ReadConsoleInputW(h, b, k, out got);
        if (stop || k < got) break;
    }
    if (r == 2 && Wheel == 0) r = 0;
    return r;
}
"@ -ErrorAction SilentlyContinue
function New-Key($ch, $key) { [ConsoleKeyInfo]::new([char]$ch, [ConsoleKey]$key, $false, $false, $false) }
function Get-TileAt([int]$mx, [int]$my) {
    # o poster por baixo do rato (posicao a contar de 1) -> indice na pagina, ou -1
    $row = [Math]::Floor(($my - $L.top) / ($L.ph + 4)); $col = [Math]::Floor(($mx - $L.left) / ($L.pw + $L.gap))
    if ($my -lt $L.top -or $row -ge $L.rows -or $mx -lt $L.left -or $col -ge $L.cols -or ($mx - $L.left) % ($L.pw + $L.gap) -ge $L.pw) { return -1 }
    $row * $L.cols + $col
}

# ---------- conta e addons ----------
function Read-Field([int]$row, [string]$label, [switch]$Secret) {
    # campo de texto numa linha: enter = pronto, esc = desistir ($null); a password aparece com pontos
    $buf = [Text.StringBuilder]::new()
    while ($true) {
        $shown = if ($Secret) { [string][char]0x2022 * $buf.Length } else { "$buf" }
        [Console]::Write("$e[$row;4H$e[2K$e[37m$label $e[97m$shown$e[?25h")
        $k = Read-Key
        switch ($k.Key) {
            'Escape' { [Console]::Write("$e[?25l"); return $null }
            'Enter' { [Console]::Write("$e[?25l"); return "$buf" }
            'Backspace' { if ($buf.Length) { [void]$buf.Remove($buf.Length - 1, 1) }; continue }
        }
        if ([int]$k.KeyChar -ge 32) { [void]$buf.Append($k.KeyChar) }
    }
}
function Invoke-Login {
    # só se não houver sessão guardada: o utilizador escreve o email e a palavra-passe da conta Stremio
    # (esc sai; email ou password errados: diz e deixa tentar outra vez)
    $err = ''
    while ($true) {
        [Console]::Write("$e[2J$e[3;4H$e[1;${Accent}m$([char]0xf26c)  $e[1;97msign in to Stremio$e[0m$e[5;4H$e[90mthe session is saved in ~\.config\stremio-auth.txt   $([char]0x00B7)   no account? stremio.com (free)$e[0m" +
            "$e[12;4H$e[48;2;$($StTheme.sel);97m enter $e[0m $e[90mnext$e[0m   $e[48;2;$($StTheme.sel);97m esc $e[0m $e[90mleave st$e[0m" + $(if ($err) { "$e[10;4H$e[31m$err$e[0m" }))
        $mail = Read-Field 7 'email:'; if ($null -eq $mail) { return $false }
        if (-not $mail.Trim()) { continue }
        $plain = Read-Field 8 'password:' -Secret; if ($null -eq $plain) { return $false }
        [Console]::Write("$e[10;4H$e[2K$e[90msigning in...$e[0m")
        try {
            $r = Invoke-RestMethod -Method Post "$Api/login" -Body (@{ email = $mail.Trim(); password = $plain; type = 'Login' } | ConvertTo-Json) -ContentType 'application/json' -TimeoutSec 20
            if ($r.result.authKey) { Set-Content $AuthFile $r.result.authKey -NoNewline; return $true }
            $err = 'could not sign in: wrong email or password?'
        } catch { $err = 'could not sign in: wrong email or password, or no connection' }
        finally { $plain = $null }
    }
}
function Invoke-Api([string]$method, $body) {
    $body.authKey = (Get-Content $AuthFile -Raw).Trim()
    (Invoke-RestMethod -Method Post "$Api/$method" -Body ($body | ConvertTo-Json -Depth 5) -ContentType 'application/json' -TimeoutSec 20).result
}
function Get-Resources($a) { @($a.manifest.resources | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } }) }
function Get-Base($a) { $a.transportUrl -replace '/manifest\.json$', '' }

# ---------- imagens (sixel) ----------
# trabalho dos threads: descarrega posters em falta e gera os sixel (memória + disco)
$ImgWork = @'
param($items, $dir, $chafa, $w, $h, $cache, $busy)
# descarrega para .part e so depois muda o nome (um .jpg a meio nunca e lido nem fica na cache); com limites de tempo
$a = @('--parallel', '-sL', '--fail', '--connect-timeout', '5', '--max-time', '20')   # --fail: um poster que nao existe nao fica guardado como pagina de erro
foreach ($x in $items) { if ($x.u -and -not (Test-Path "$dir\$($x.n).jpg")) { $a += $x.u, '-o', "$dir\$($x.n).jpg.part" } }
if ($a.Count -gt 6) {
    & curl.exe @a 2>$null
    foreach ($x in $items) { $p = "$dir\$($x.n).jpg.part"; if (Test-Path $p) { try { [IO.File]::Move($p, "$dir\$($x.n).jpg", $true) } catch {} } }
}
foreach ($x in $items) {
    $k = "$($x.n)-$w-$h-s"; $sf = "$dir\six\$k.six"
    try {
        if ($cache.ContainsKey($k)) { continue }
        if ($env:ST_ITERM) {
            $src = "$dir\$($x.n).jpg"; if (-not (Test-Path $src)) { continue }
            $inv = [cultureinfo]::InvariantCulture
            $pw = [int]($w * [double]::Parse($env:ST_CW, $inv)); $ph = [int]($h * [double]::Parse($env:ST_CH, $inv))
            $sj = "$dir\six\$k-${pw}x$ph.jpg"
            if (-not (Test-Path $sj)) {
                try {
                    Add-Type -AssemblyName System.Drawing
                    $img = [Drawing.Image]::FromFile($src); $bmp = [Drawing.Bitmap]::new($pw, $ph); $gr = [Drawing.Graphics]::FromImage($bmp)
                    $gr.InterpolationMode = 'HighQualityBicubic'; $gr.PixelOffsetMode = 'HighQuality'; $gr.DrawImage($img, 0, 0, $pw, $ph)
                    $jc = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg'
                    $ep = [Drawing.Imaging.EncoderParameters]::new(1); $ep.Param[0] = [Drawing.Imaging.EncoderParameter]::new([Drawing.Imaging.Encoder]::Quality, [long]90)
                    $tmp = "$sj.$([guid]::NewGuid().ToString('N')).tmp"; $bmp.Save($tmp, $jc, $ep); $gr.Dispose(); $bmp.Dispose(); $img.Dispose(); [IO.File]::Move($tmp, $sj, $true)
                } catch { $sj = $src }
            }
            $cache[$k] = "$([char]27)]1337;File=inline=1;width=$w;height=$h;preserveAspectRatio=0:" + [Convert]::ToBase64String([IO.File]::ReadAllBytes($sj)) + [char]7
            continue
        }
        if (Test-Path $sf) { try { $cache[$k] = [IO.File]::ReadAllText($sf); continue } catch {} }
        if (-not (Test-Path "$dir\$($x.n).jpg")) { continue }
        $s = ((& $chafa -f sixels --probe off --dither none --stretch --size "${w}x$h" "$dir\$($x.n).jpg" 2>$null) -join '') -replace "$([char]27)\[\?25[hl]", ''
        $tmp = "$sf.$([guid]::NewGuid().ToString('N')).tmp"   # nome unico por thread
        if ($s) { try { [IO.File]::WriteAllText($tmp, $s); [IO.File]::Move($tmp, $sf, $true) } catch {}; $cache[$k] = $s }   # gravar e so depois mudar o nome: nunca se le a meio
    } finally { $busy.Remove($k) }
}
'@
$ImgBusy = [hashtable]::Synchronized(@{})   # imagens ja pedidas (nome-tamanho): cada uma so e pedida uma vez de cada vez
function Img-Name([string]$id) { $id -replace '[^\w-]', '_' }
function Start-ImgJob($metas, [int]$w, [int]$h) {
    $items = @($metas | Where-Object { $_.poster } | ForEach-Object { @{ n = (Img-Name $_.id); u = $_.poster } } | Where-Object {
            $k = "$($_.n)-$w-$h-s"
            if ($Sixel.ContainsKey($k) -or $ImgBusy.ContainsKey($k)) { $false } else { $ImgBusy[$k] = 1; $true } })
    if (-not $items) { return }
    $null = Start-ThreadJob -Name st -ThrottleLimit 100 -ArgumentList $ImgWork, $items, $Dir, $Chafa, $w, $h, $Sixel, $ImgBusy -ScriptBlock {
        param($work, $items, $dir, $chafa, $w, $h, $cache, $busy)
        & ([scriptblock]::Create($work)) $items $dir $chafa $w $h $cache $busy
    }
}
function Get-Six([string]$id, [int]$w, [int]$h) {
    # sixel já pronto (memória ou disco) ou $null
    $k = "$(Img-Name $id)-$w-$h-s"
    if ($Sixel.ContainsKey($k)) { return $Sixel[$k] }
    if ($env:ST_ITERM) {
        $sj = "$SixDir\$k-$(Get-ImgPx $w $h).jpg"
        if (-not [IO.File]::Exists($sj)) { return $null }
        try { $Sixel[$k] = "$e]1337;File=inline=1;width=$w;height=$h;preserveAspectRatio=0:" + [Convert]::ToBase64String([IO.File]::ReadAllBytes($sj)) + [char]7; return $Sixel[$k] } catch { return $null }
    }
    $sf = "$SixDir\$k.six"
    if ([IO.File]::Exists($sf)) { try { $Sixel[$k] = [IO.File]::ReadAllText($sf); return $Sixel[$k] } catch { return $null } }   # (outro thread ainda a gravar: fica para a próxima)
    $null
}

# ---------- pedidos aos addons (threads) ----------
function Start-Fetch([string]$key, [string]$url, [int]$timeout = 25) {
    Clear-StJobs
    $Net.Remove($key)
    $null = Start-ThreadJob -Name st -ThrottleLimit 100 -ArgumentList $key, $url, $timeout, $Net -ScriptBlock {
        param($key, $url, $t, $net)
        try { $net[$key] = @{ ok = $true; r = (Invoke-RestMethod $url -TimeoutSec $t) } } catch { $net[$key] = @{ ok = $false; err = $_.Exception.Message } }
    }
}

# ---------- progresso ----------
function Read-JsonFile([string]$f) {
    # le um JSON; se estiver estragado guarda-o como .bak-<data> (nunca e apagado nem sobrescrito por cima)
    if (-not (Test-Path $f)) { return $null }
    try { Get-Content $f -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop }
    catch { try { [IO.File]::Move($f, "$f.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')") } catch {}; $null }
}
function Write-JsonFile([string]$f, $obj) {
    # escrita atomica: ficheiro temporario + mudar o nome (um crash a meio nunca deixa o ficheiro cortado)
    $tmp = "$f.$([guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $obj -Depth 6 -Compress), [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($tmp, $f, $true)
}
$Prog = Read-JsonFile $ProgFile
if (-not $Prog -or -not $Prog.vids) { $Prog = @{ items = @{}; vids = @{} } }
function Save-Prog {
    # junta o que outra sessao do st tenha gravado entretanto (fica o mais recente de cada titulo)
    $disk = Read-JsonFile $ProgFile
    if ($disk -and $disk.vids) {
        foreach ($k in $disk.vids.Keys) { if (-not $Prog.vids.ContainsKey($k)) { $Prog.vids[$k] = $disk.vids[$k] } }
        foreach ($k in $disk.items.Keys) { if (-not $Prog.items.ContainsKey($k) -or "$($disk.items[$k].at)" -gt "$($Prog.items[$k].at)") { $Prog.items[$k] = $disk.items[$k] } }
    }
    try { Write-JsonFile $ProgFile $Prog } catch {}
}
function Clear-StJobs { Get-Job | Where-Object { $_.Name -eq 'st' -and $_.State -eq 'Completed' } | Remove-Job -ErrorAction SilentlyContinue }   # (so os threads do st)
function Get-VidProg([string]$vid) { $p = $Prog.vids[$vid]; if ($p -and $p.d -gt 0) { [Math]::Min(1, $p.t / $p.d) } else { 0 } }

# ---------- desenho (comum) ----------
function Fit([string]$s, [int]$w) { if ($w -le 1) { return '' }; if ($s.Length -le $w) { $s.PadRight($w) } else { $s.Substring(0, $w - 1) + [char]0x2026 } }
function Wrap-Lines([string]$s, [int]$w, [int]$max) {
    $out = [Collections.Generic.List[string]]::new(); $line = ''
    foreach ($word in ($s -replace '\s+', ' ').Trim() -split ' ') {
        if (($line + ' ' + $word).Trim().Length -le $w) { $line = ($line + ' ' + $word).Trim() }
        else { $out.Add($line); $line = if ($word.Length -gt $w) { $word.Substring(0, $w) } else { $word }; if ($out.Count -ge $max) { break } }
    }
    if ($out.Count -lt $max -and $line) { $out.Add($line) }
    elseif ($out.Count -ge $max) { $out[$max - 1] = (Fit ($out[$max - 1] + ' ' + $line) $w).TrimEnd() }
    @($out | Select-Object -First $max)
}
function Format-Time($sec) { if ($null -eq $sec) { return '--:--' }; $t = [TimeSpan]::FromSeconds([double]$sec); if ($t.TotalHours -ge 1) { '{0}:{1:mm\:ss}' -f [int][Math]::Floor($t.TotalHours), $t } else { '{0:m\:ss}' -f $t } }
$Frames = [char[]]'⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'; $Spin = 0
function Get-CellRatio {
    # altura/largura de uma célula do terminal em píxeis (para os posters ficarem 2:3); ~2,2 se não der para medir
    try {
        $wt = (Get-Process -Id $PID).Parent
        if ($wt.ProcessName -eq 'WindowsTerminal' -and -not $env:SSH_CONNECTION) {
            Add-Type -Namespace W -Name StRect -MemberDefinition '[StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Rt, B; } [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out R r);' -ErrorAction SilentlyContinue
            $r = New-Object W.StRect+R; [void][W.StRect]::GetClientRect($wt.MainWindowHandle, [ref]$r)
            $v = ($r.B / [Console]::WindowHeight) / ($r.Rt / [Console]::WindowWidth)
            if ($v -gt 1.6 -and $v -lt 3) { return $v }
        }
    } catch {}
    2.2
}
$CellRatio = Get-CellRatio
# WezTerm: tamanho real da celula (o espacamento de linha muda-o): posters 2:3 certos e a imagem vai como JPEG no tamanho
# exato do cartao (protocolo de imagens do iTerm2), em vez do sixel do chafa feito para celulas de 10x20
$CellW = 10.0; $CellH = 22.0
if ($env:WEZTERM_PANE -and $env:WEZTERM_EXECUTABLE) {
    try {
        $me = (& (Join-Path (Split-Path $env:WEZTERM_EXECUTABLE) 'wezterm.exe') cli list --format json 2>$null | ConvertFrom-Json) | Where-Object pane_id -eq ([int]$env:WEZTERM_PANE)
        $pxw = $me.size.pixel_width / $me.size.cols; $pxh = $me.size.pixel_height / $me.size.rows
        if ($pxw -gt 0 -and $pxh -gt 0) {
            $CellW = $pxw; $CellH = $pxh; $CellRatio = $pxh / $pxw; $env:ST_ITERM = '1'
            $env:ST_CW = $pxw.ToString([cultureinfo]::InvariantCulture); $env:ST_CH = $pxh.ToString([cultureinfo]::InvariantCulture)
        }
    } catch {}
}
function Get-ImgPx([int]$w, [int]$h) { "$([int]($w * $CellW))x$([int]($h * $CellH))" }
function Get-Layout {
    # grelha de posters 2:3 com duas filas; cada poster ocupa ph linhas + barra + nome + ano/nota + espaço
    $W = [Console]::WindowWidth; $H = [Console]::WindowHeight; $top = 9; $gap = 3
    $ph = [Math]::Max(6, [Math]::Min(18, [Math]::Floor(($H - $top - 1) / 2) - 4))
    $pw = [int][Math]::Round($ph * $CellRatio / 1.5)
    $cols = [Math]::Max(1, [Math]::Floor(($W - 8 + $gap) / ($pw + $gap)))
    $rows = [Math]::Max(1, [Math]::Floor(($H - $top - 1) / ($ph + 4)))
    $gw = $cols * ($pw + $gap) - $gap
    @{ W = $W; H = $H; pw = $pw; ph = $ph; gap = $gap; cols = $cols; rows = $rows; per = $cols * $rows; top = $top
        left = [Math]::Max(4, [Math]::Floor(($W - $gw) / 2)); bw = [Math]::Max(30, [Math]::Min(64, $W - 64)) }
}
function Draw-Header($L, [string]$q, [bool]$focus) {
    $h = [string][char]0x2500; $bc = if ($focus) { '0;37' } else { '0;90' }; $in = $L.bw - 7; $bcx = [Math]::Floor(($L.W - $L.bw) / 2)
    $text = if ($focus) { ''.PadRight($in) } elseif ($q) { "$e[37m" + (Fit $q $in) } else { "$e[90m" + 'search movies and series'.PadRight($in) }
    [Console]::Write(
        "$e[2;$($L.left)H$e[1;${Accent}m$([char]0xf26c) $e[1;97m stremio$e[0m" +
        "$e[1;${bcx}H$e[${bc}m$([char]0x256D)" + ($h * ($L.bw - 2)) + "$([char]0x256E)" +
        "$e[2;${bcx}H$([char]0x2502) $e[90m$([char]0xf002)  $text$e[${bc}m $([char]0x2502)" +
        "$e[3;${bcx}H$([char]0x2570)" + ($h * ($L.bw - 2)) + "$([char]0x256F)$e[0m")
}
$Tabs = @(@{ m = 'explore'; n = 'explore' }, @{ m = 'favs'; n = 'favorites' })
function Chips($items, [string]$active) {
    ($items | ForEach-Object { if ($_.m -eq $active) { "$e[48;2;$($StTheme.fg);30m $($_.n) $e[0m  " } else { "$e[48;2;$($StTheme.sel);37m $($_.n) $e[0m  " } }) -join ''
}
$TypeNames = @{ movie = 'movies'; series = 'series'; all = 'all' }
$OrderNames = @{ trending = 'trending'; recent = 'latest'; added = 'added'; name = 'name'; rating = 'rating' }

# ---------- favoritos (só locais: ~\.config\st-favorites.json) ----------
$FavFile = "$HOME\.config\st-favorites.json"
$Favs = [Collections.Generic.List[object]]::new()
if (Test-Path $FavFile) {
    # estragado: guarda-se como .bak-<data> em vez de comecar vazio e o apagar no proximo favorito
    try { foreach ($x in @(Get-Content $FavFile -Raw | ConvertFrom-Json -ErrorAction Stop)) { $Favs.Add($x) } }
    catch { try { [IO.File]::Move($FavFile, "$FavFile.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')") } catch {} }
}
function Test-Fav([string]$id) { [bool]@($Favs | Where-Object id -eq $id).Count }
function Switch-Fav($m) {
    $x = $Favs | Where-Object id -eq $m.id | Select-Object -First 1
    if ($x) { [void]$Favs.Remove($x) }
    else { $Favs.Insert(0, [pscustomobject]@{ id = $m.id; type = $m.type; name = $m.name; poster = $m.poster; releaseInfo = $m.releaseInfo; imdbRating = $m.imdbRating; genres = @($m.genres); added = (Get-Date).ToString('o') }) }
    try { Write-JsonFile $FavFile @($Favs) } catch {}   # (atomico)
}

# ---------- fontes (catálogos do AIOMetadata) ----------
function Get-Genres([string]$type) {
    # géneros dos catálogos "recentes" (para 'todos': os dos dois tipos)
    $t = if ($type -eq 'all') { @('movie', 'series') } else { @($type) }
    @($Aio.manifest.catalogs | Where-Object { $_.type -in $t -and $_.id -like 'tmdb.discover.*latest*' } | ForEach-Object { @(($_.extra | Where-Object name -eq 'genre').options) }) | Select-Object -Unique
}
function Get-TypeGenre([string]$g, [string]$type) {
    # o mesmo género pode ter outro nome no outro tipo (Action / Action & Adventure, Science Fiction / Sci-Fi & Fantasy)
    $opts = @(Get-Genres $type)
    if ($g -in $opts) { return $g }
    $w = if ($g -like 'Sci*') { 'Sci' } else { ($g -split '[ &]')[0] }
    $opts | Where-Object { $_ -like "$w*" } | Select-Object -First 1
}
function Get-Sources($v) {
    $b = Get-Base $Aio
    foreach ($t in $(if ($v.type -eq 'all') { 'movie', 'series' } else { $v.type })) {
        if ($v.q) { @{ base = "$b/catalog/$t/search.$t"; extra = "search=$([uri]::EscapeDataString($v.q))"; paged = $false; skip = 0; done = $false }; continue }
        $g = if ($v.genre) { Get-TypeGenre $v.genre $t } else { '' }
        if ($v.genre -and -not $g) { continue }   # este tipo não tem o género
        $latest = ($Aio.manifest.catalogs | Where-Object { $_.type -eq $t -and $_.id -like 'tmdb.discover.*latest*' } | Select-Object -First 1).id
        if (-not $g) {
            $id = if ($v.order -eq 'recent') { $latest } else { 'tmdb.trending' }
            @{ base = "$b/catalog/$t/$id"; extra = ''; paged = $true; skip = 0; done = $false }
        }
        elseif ($v.order -eq 'trending' -and ($gc = $Aio.manifest.catalogs | Where-Object { $_.type -eq $t -and $_.id -like 'tmdb.discover.*' -and $_.id -notlike '*latest*' -and $_.name -like "$g *" } | Select-Object -First 1)) {
            @{ base = "$b/catalog/$t/$($gc.id)"; extra = ''; paged = $true; skip = 0; done = $false }   # populares do género
        }
        else { @{ base = "$b/catalog/$t/$latest"; extra = "genre=$([uri]::EscapeDataString($g))"; paged = $true; skip = 0; done = $false } }
    }
}
function New-View([string]$tab) {
    $v = @{ tab = $tab; type = $(if ($tab -eq 'favs') { 'all' } else { 'movie' }); genre = ''; order = $(if ($tab -eq 'favs') { 'added' } else { 'trending' }); q = ''
        items = [Collections.Generic.List[object]]::new(); sel = 0; srcs = @(); busy = $false; done = $false }
    Reset-View $v; $v
}
function Reset-View($v) {
    # filtros mudaram: recomeça a lista
    $v.items.Clear(); $v.sel = 0; $v.busy = $false; $v.done = $false
    if ($v.tab -eq 'explore') { $v.srcs = @(Get-Sources $v); if (-not $v.srcs) { $v.done = $true }; Start-Load $v }
}
function Get-Items($v) {
    if ($v.tab -eq 'explore') { return $v.items }
    # favoritos: filtros e pesquisa aplicados aqui
    $g = $v.genre; $w = if ($g -like 'Sci*') { 'Sci' } else { ($g -split '[ &]')[0] }
    $list = @($Favs | Where-Object {
            ($v.type -eq 'all' -or $_.type -eq $v.type) -and
            (-not $g -or @($_.genres | Where-Object { $_ -eq $g -or $_ -like "$w*" }).Count) -and
            (-not $v.q -or $_.name -like "*$($v.q)*") })
    switch ($v.order) { 'name' { $list = @($list | Sort-Object name) } 'rating' { $list = @($list | Sort-Object { [double]"0$($_.imdbRating)" } -Descending) } }
    $list
}
function Start-Load($v) {
    if ($v.tab -ne 'explore' -or $v.busy -or $v.done) { return }
    foreach ($s in $v.srcs | Where-Object { -not $_.done }) {
        $s.key = [guid]::NewGuid().ToString()
        $path = if ($s.extra) { "$($s.base)/$($s.extra)$(if ($s.skip) { "&skip=$($s.skip)" })" } else { "$($s.base)$(if ($s.skip) { "/skip=$($s.skip)" })" }
        Start-Fetch $s.key "$path.json"
    }
    $v.busy = $true
}
function Update-Load($v) {
    # quando todas as fontes responderem: junta (filmes e séries intercalados), sem repetidos
    if (-not $v.busy) { return $false }
    $pending = @($v.srcs | Where-Object { -not $_.done -and $_.key })
    if (@($pending | Where-Object { -not $Net.ContainsKey($_.key) }).Count) { return $false }
    $have = @{}; foreach ($x in $v.items) { $have[$x.id] = 1 }
    $lists = [Collections.Generic.List[object]]::new()
    foreach ($s in $pending) {
        $res = $Net[$s.key]; $Net.Remove($s.key); $s.key = $null
        $m = @(if ($res.ok) { @($res.r.metas) | Where-Object { $_ -and $_.id } })
        $s.skip += $m.Count; if (-not $m.Count -or -not $s.paged) { $s.done = $true }
        $lists.Add($m)
    }
    $new = @()
    for ($i = 0; $i -lt (@($lists | ForEach-Object { $_.Count }) | Measure-Object -Maximum).Maximum; $i++) { foreach ($lst in $lists) { if ($i -lt $lst.Count -and -not $have[$lst[$i].id]) { $have[$lst[$i].id] = 1; $new += $lst[$i] } } }
    foreach ($x in $new) { $v.items.Add($x) }
    if ($new) { Start-ImgJob $new $L.pw $L.ph }
    $v.busy = $false; $v.done = -not @($v.srcs | Where-Object { -not $_.done }).Count
    $true
}

# ---------- grelha ----------
function Get-TilePos([int]$slot) { @{ y = $L.top + [Math]::Floor($slot / $L.cols) * ($L.ph + 4); x = $L.left + ($slot % $L.cols) * ($L.pw + $L.gap) } }
function Draw-TileText($m, [int]$slot, [bool]$sel) {
    $p = Get-TilePos $slot
    $year = if ($m.releaseInfo) { "$($m.releaseInfo)" } elseif ($m.year) { "$($m.year)" } else { '' }
    $info = (@($year, $(if ($m.imdbRating) { "$([char]0xf005) $($m.imdbRating)" })) | Where-Object { $_ }) -join '  '
    $heart = if (Test-Fav $m.id) { "$e[31m$([char]0x2665)" } else { ' ' }
    "$e[$($p.y + $L.ph);$($p.x)H" + $(if ($sel) { "$e[${Accent}m" + ([string][char]0x2501 * $L.pw) } else { ' ' * $L.pw }) +
    "$e[$($p.y + $L.ph + 1);$($p.x)H$e[$(if ($sel) { '1;97' } else { '0;37' })m$(Fit $m.name $L.pw)" +
    "$e[$($p.y + $L.ph + 2);$($p.x)H$e[90m$(Fit $info ($L.pw - 2)) $heart$e[0m"
}
function Draw-Filters($v, $items) {
    $chip = { param($k, $n, $val) "$e[90m$k $e[37m$n $e[48;2;$($StTheme.sel);97m $val $e[0m     " }
    $o = "$e[7;1H$e[2K$e[7;$($L.left)H" + (& $chip 't' 'type' $TypeNames[$v.type]) + (& $chip 'g' 'genre' $(if ($v.genre) { $v.genre } else { 'all' }))
    if (-not ($v.tab -eq 'explore' -and $v.q)) { $o += & $chip 'o' 'sort' $OrderNames[$v.order] }
    if ($v.q) { $o += "$e[90msearch $e[48;2;$($StTheme.fg);30m $($v.q) $e[0;90m  esc clears$e[0m" }
    $pi = if ($items.Count) { "$($v.sel + 1) / $($items.Count)$(if ($v.tab -eq 'explore' -and -not $v.done) { '+' } else { ' ' })".PadLeft(11) } else { ' ' * 11 }
    $o + "$e[7;$($L.W - $L.left - $pi.Length + 1)H$e[90m$pi$e[0m"
}
function Set-Hints([string]$s) { if ($env:WEZTERM_PANE) { [Console]::Write("$e]1337;SetUserVar=hints=$([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s)))$([char]7)") } }
$GridHints = 'enter|open;/|search;t|type;g|genre;f|favorite;tab|favorites;?|all shortcuts;esc|quit'
function Draw-Grid($v) {
    $script:L = Get-Layout; $script:Pending = [Collections.Generic.List[object]]::new()
    if ($L.W -lt 60 -or $L.H -lt 24) {
        $m1 = 'window too small'; $m2 = "enlarge the pane (minimum 60×24; now $($L.W)×$($L.H))"
        [Console]::Write("$e[2J$e[$([Math]::Floor($L.H / 2));$([Math]::Max(1, [Math]::Floor(($L.W - $m1.Length) / 2)))H$e[1;97m$m1$e[$([Math]::Floor($L.H / 2) + 1);$([Math]::Max(1, [Math]::Floor(($L.W - $m2.Length) / 2)))H$e[0;90m$m2$e[0m"); return
    }
    $items = @(Get-Items $v)
    $v.sel = [Math]::Max(0, [Math]::Min($v.sel, $items.Count - 1))   # (lista vazia: as setas não deixam a seleção negativa)
    [Console]::Write("$e[?2026h$e[2J"); Draw-Header $L $v.q $false
    $o = "$e[5;$($L.left)H" + (Chips $Tabs $v.tab) + (Draw-Filters $v $items)
    $start = [Math]::Floor($v.sel / $L.per) * $L.per
    for ($i = 0; $i -lt $L.per -and $start + $i -lt $items.Count; $i++) {
        $m = $items[$start + $i]; $p = Get-TilePos $i
        $six = Get-Six $m.id $L.pw $L.ph
        if ($six) { $o += "$e[$($p.y);$($p.x)H$six" }
        else {
            for ($q = 0; $q -lt $L.ph; $q++) { $o += "$e[$($p.y + $q);$($p.x)H$e[48;2;$($StTheme.surf)m" + (' ' * $L.pw) + "$e[0m" }
            $script:Pending.Add(@{ id = $m.id; y = $p.y; x = $p.x; m = $m })
        }
        $o += Draw-TileText $m $i ($start + $i -eq $v.sel)
    }
    # as que faltam (neste tamanho: depois de redimensionar tambem) sao pedidas aqui, em qualquer separador
    if ($script:Pending.Count) { Start-ImgJob @($script:Pending | ForEach-Object { $_.m }) $L.pw $L.ph }
    $v.drawn = [Math]::Min($L.per, $items.Count - $start)
    if (-not $items.Count) {
        $msg = if ($v.busy) { 'loading...' } elseif ($v.tab -eq 'favs' -and -not $Favs.Count) { "no favorites yet  $e[90m—  on a title, press $e[37mf$e[90m to save it here" } elseif ($v.tab -eq 'favs') { 'no favorites match these filters' } else { 'nothing found' }
        $o += "$e[$($L.top + 3);$($L.left)H$e[37m$msg$e[0m"
    }
    if ($env:WEZTERM_PANE) { Set-Hints $GridHints; $o += "$e[?2026l" } else { $o += "$e[$($L.H);$($L.W - $L.left - 11)H$e[90m? $e[37mshortcuts$e[0m$e[?2026l" }
    [Console]::Write($o)
}
function Update-Pending {
    if (-not $script:Pending -or -not $script:Pending.Count) { return }
    $o = ''
    foreach ($x in @($script:Pending)) { $six = Get-Six $x.id $L.pw $L.ph; if ($six) { $o += "$e[$($x.y);$($x.x)H$six"; [void]$script:Pending.Remove($x) } }
    if ($o) { [Console]::Write($o) }
}
function Select-Option([string]$title, $opts, [string]$cur) {
    # lista ao centro (↑↓ enter esc); devolve a opção ou $null
    $W = [Console]::WindowWidth; $H = [Console]::WindowHeight
    $bw = [Math]::Max(30, (@($opts | ForEach-Object { "$_".Length }) | Measure-Object -Maximum).Maximum + 8); $n = [Math]::Min($opts.Count, $H - 10)
    $x = [Math]::Floor(($W - $bw) / 2); $y = [Math]::Max(3, [Math]::Floor(($H - $n - 2) / 2)); $hl = [string][char]0x2500
    $sel = [Math]::Max(0, [array]::IndexOf(@($opts), $cur)); $off = 0
    while ($true) {
        if ($sel -lt $off) { $off = $sel } elseif ($sel -ge $off + $n) { $off = $sel - $n + 1 }
        $o = "$e[$y;${x}H$e[90m$([char]0x256D)$hl $e[1;97m$title $e[0;90m" + ($hl * ($bw - $title.Length - 5)) + [char]0x256E
        for ($k = 0; $k -lt $n; $k++) {
            $j = $off + $k; $t = Fit "$($opts[$j])" ($bw - 6)
            $o += "$e[$($y + 1 + $k);${x}H$e[90m$([char]0x2502)$e[0m " + $(if ($j -eq $sel) { "$e[48;2;$($StTheme.sel);1;97m $t $e[0m" } else { "$e[37m $t $e[0m" }) + " $e[90m$([char]0x2502)"
        }
        $o += "$e[$($y + 1 + $n);${x}H$([char]0x2570)" + ($hl * ($bw - 2)) + "$([char]0x256F)$e[0m"
        [Console]::Write($o)
        $k = Read-Key
        switch ($k.Key) {
            'UpArrow'   { if ($sel -gt 0) { $sel-- } }
            'DownArrow' { if ($sel -lt $opts.Count - 1) { $sel++ } }
            'PageUp'    { $sel = [Math]::Max(0, $sel - $n) }
            'PageDown'  { $sel = [Math]::Min($opts.Count - 1, $sel + $n) }
            'Enter'     { return $opts[$sel] }
            'Escape'    { return $null }
        }
    }
}
function Show-Help($rows) {
    $w = 56; $top = [Math]::Max(2, [Math]::Floor(([Console]::WindowHeight - $rows.Count - 4) / 2)); $lc = [Math]::Floor(([Console]::WindowWidth - $w) / 2)
    $h = [string][char]0x2500
    $out = "$e[$top;${lc}H$e[90m$([char]0x256D)$h $e[1;97mshortcuts $e[0;90m" + ($h * ($w - 14)) + [char]0x256E
    $r = $top + 1
    foreach ($x in $rows) { $out += "$e[$r;${lc}H$e[90m$([char]0x2502)$e[0m  $e[1;97m" + $x[0].PadRight(11) + "$e[0;37m" + $x[1].PadRight($w - 15) + "$e[90m$([char]0x2502)"; $r++ }
    $out += "$e[$r;${lc}H$([char]0x2570)" + ($h * ($w - 2)) + "$([char]0x256F)$e[0m"
    [Console]::Write($out); [void](Read-Key)
}

# ---------- pesquisa (com histórico) ----------
function Get-SearchHistory { if (Test-Path $SearchFile) { @(Get-Content $SearchFile -Encoding utf8 | Where-Object { $_ }) } else { @() } }
function Read-Search([string]$q) {
    $L0 = Get-Layout; Draw-Header $L0 '' $true
    $bcx = [Math]::Floor(($L0.W - $L0.bw) / 2); $in = $L0.bw - 7; $buf = ''; $sel = -1; $hist = Get-SearchHistory; $shown = 0
    while ($true) {
        $ms = @(@(if ($buf) { $hist | Where-Object { $_ -like "*$buf*" -and $_ -ne $buf } } else { $hist }) | Select-Object -First 8)   # @(): com 1 sugestão continua a ser lista
        if ($sel -ge $ms.Count) { $sel = $ms.Count - 1 }
        $vis = if ($buf.Length -gt $in - 1) { $buf.Substring($buf.Length - $in + 1) } else { $buf }
        $o = "$e[2;$($bcx + 5)H$e[0;97m$vis$e[7m $e[0m" + (' ' * [Math]::Max(0, $in - $vis.Length - 1))
        $r = 4
        for ($i = 0; $i -lt [Math]::Max($shown, $ms.Count + 1); $i++) { $o += "$e[$($r + $i);${bcx}H" + (' ' * $L0.bw) }
        for ($i = 0; $i -lt $ms.Count; $i++) {
            $line = " $([char]0xf017)  " + (Fit $ms[$i] ($L0.bw - 8))
            $o += "$e[$r;${bcx}H" + $(if ($i -eq $sel) { "$e[48;2;$($StTheme.sel);97m$line $e[0m" } else { "$e[48;2;$($StTheme.dark);90m$line $e[0m" }); $r++
        }
        $shown = $ms.Count + 1
        [Console]::Write($o)
        $k = Read-Key
        switch ($k.Key) {
            'Enter'     { $res = if ($sel -ge 0) { $ms[$sel] } else { $buf.Trim() }; if ($res) { Set-Content $SearchFile (@($res) + @($hist | Where-Object { $_ -ne $res }) | Select-Object -First 100) -Encoding utf8 }; return $res }
            'Escape'    { return '' }
            'DownArrow' { if ($sel -lt $ms.Count - 1) { $sel++ }; continue }
            'UpArrow'   { if ($sel -ge 0) { $sel-- }; continue }
            'Tab'       { if ($sel -ge 0) { $buf = $ms[$sel]; $sel = -1 } elseif ($ms.Count) { $buf = $ms[0] }; continue }
            'Delete'    { if ($sel -ge 0) { $hist = @($hist | Where-Object { $_ -ne $ms[$sel] }); Set-Content $SearchFile $hist -Encoding utf8 }; continue }
            'Backspace' { if ($buf.Length) { $buf = $buf.Substring(0, $buf.Length - 1) }; $sel = -1; continue }
        }
        if ([int]$k.KeyChar -ge 32) { $buf += $k.KeyChar; $sel = -1 }
    }
}

# ---------- página do título ----------
function Get-MetaUrls([string]$type, [string]$id) {
    # addons com metadados para este id (ex.: AIOMetadata); o Cinemeta fica como alternativa
    $u = @(foreach ($a in $Addons) {
            $res = $a.manifest.resources | Where-Object { ($_ -is [string] -and $_ -eq 'meta') -or $_.name -eq 'meta' }
            if (-not $res) { continue }
            $pref = if ($res -isnot [string] -and $res.idPrefixes) { $res.idPrefixes } else { $a.manifest.idPrefixes }
            if (-not $pref -or @($pref | Where-Object { $id.StartsWith($_) }).Count) { "$(Get-Base $a)/meta/$type/$id.json" }
        })
    $u + "https://v3-cinemeta.strem.io/meta/$type/$id.json"
}
function Wait-Spin([scriptblock]$done, [string]$msg, [int]$row = 0, [int]$col = 0, [int]$maxMs = 20000) {
    # indicador animado (ao centro, se não se disser onde) até $done ser verdade
    # esc cancela ($script:SpinCancel); as outras teclas carregadas durante a espera sao descartadas (nao ficam em fila)
    $sw = [Diagnostics.Stopwatch]::StartNew(); $script:SpinCancel = $false
    if (& $done) { return }
    if (-not $row) { $row = [Math]::Floor([Console]::WindowHeight / 2); $col = [Math]::Max(1, [Math]::Floor(([Console]::WindowWidth - $msg.Length) / 2)) }
    while (-not (& $done) -and $sw.ElapsedMilliseconds -lt $maxMs) {
        while ([Console]::KeyAvailable) { if ((Read-Key).Key -eq 'Escape') { $script:SpinCancel = $true } }
        if ($script:SpinCancel) { break }
        [Console]::Write("$e[$row;${col}H$e[${Accent}m$($Frames[$script:Spin++ % 10])  $e[0;37m$msg$e[0m"); Start-Sleep -Milliseconds 80
    }
    [Console]::Write("$e[$row;1H$e[2K")
}
function Get-Meta($item) {
    $key = "meta-$($item.type)-$($item.id)"
    # (so serve uma resposta com meta: um {} ou uma pagina de erro do 1.o addon nao impede tentar o seguinte)
    if ($Net.ContainsKey($key) -and $Net[$key].ok -and $Net[$key].r.meta) { return $Net[$key].r.meta }
    foreach ($u in (Get-MetaUrls $item.type $item.id)) {
        Start-Fetch $key $u 15
        Wait-Spin { $Net.ContainsKey($key) } 'opening   esc cancels'
        if ($script:SpinCancel) { return $null }
        if ($Net[$key].ok -and $Net[$key].r.meta) { return $Net[$key].r.meta }
    }
    $Net.Remove($key)
    $null
}
function Get-TitlePosterSize { $h = [Math]::Min([Console]::WindowHeight - 4, 24); @{ h = $h; w = [int][Math]::Round($h * $CellRatio / 1.5) } }
function Start-TitlePrefetch($item) {
    # parado num poster da grelha: pede já os metadados e prepara o poster grande da página do título
    $key = "meta-$($item.type)-$($item.id)"
    if (-not $Net.ContainsKey($key)) { Start-Fetch $key (Get-MetaUrls $item.type $item.id)[0] 15 }
    $ps = Get-TitlePosterSize; if (-not (Get-Six $item.id $ps.w $ps.h)) { Start-ImgJob @($item) $ps.w $ps.h }
}
$StreamReq = @{}   # vid -> pedidos de streams/legendas já feitos (reaproveitados durante 10 min)
function Start-StreamFetch([string]$type, [string]$vid) {
    $r = $StreamReq[$vid]
    # reaproveita durante 10 min, mas nao se todos os addons falharam (ex.: sem rede): pede outra vez
    if ($r -and ((Get-Date) - $r.at).TotalMinutes -lt 10 -and @($r.keys.Keys | Where-Object { -not $Net.ContainsKey($_) -or $Net[$_].ok }).Count) { return $r }
    if ($r) { foreach ($k in @($r.keys.Keys) + @($r.subs)) { $Net.Remove($k) } }   # respostas antigas saem da memoria
    $r = @{ at = Get-Date; keys = @{}; subs = @(); n = 0 }
    foreach ($a in @($Addons | Where-Object { (Get-Resources $_) -contains 'stream' -and $_.transportUrl -notlike 'http://127.0.0.1*' })) {
        $k = "st-$vid-$([guid]::NewGuid())"; $r.keys[$k] = $a.manifest.name; $r.n++; Start-Fetch $k "$(Get-Base $a)/stream/$type/$vid.json" 30
    }
    $r.subs = @(foreach ($a in $Addons | Where-Object { (Get-Resources $_) -contains 'subtitles' }) { $k = "sub-$vid-$([guid]::NewGuid())"; Start-Fetch $k "$(Get-Base $a)/subtitles/$type/$vid.json" 15; $k })
    $StreamReq[$vid] = $r; $r
}
function Show-Title($item) {
    $meta = Get-Meta $item
    if (-not $meta -and $script:SpinCancel) { return }   # esc durante o "opening"
    if ($meta -and $(if ($meta.type) { $meta.type } else { $item.type }) -ne 'series') { $null = Start-StreamFetch 'movie' $meta.id }   # o Enter já encontra os streams a chegar
    if (-not $meta) { [Console]::Write("$e[$([Math]::Floor([Console]::WindowHeight / 2));4H$e[2K$e[31mcould not open this title$e[0m"); Start-Sleep 2; return }
    if (-not $meta.type) { $meta | Add-Member type $item.type -Force }
    $isSeries = $meta.type -eq 'series' -and @($meta.videos).Count
    # temporadas (especiais no fim) e a temporada inicial: a do último episódio visto
    $eps = @($meta.videos | Sort-Object { [int]$_.season }, { [int]$_.episode })
    $seasons = @($eps | ForEach-Object { [int]$_.season } | Sort-Object -Unique | Sort-Object { if ($_ -eq 0) { 999 } else { $_ } })
    $lastVid = if ($Prog.items[$meta.id]) { $Prog.items[$meta.id].vid } elseif ($item.vid) { $item.vid } else { '' }
    $si = 0; $ei = 0
    if ($isSeries) {
        $lv = $eps | Where-Object id -eq $lastVid | Select-Object -First 1
        if ($lv) { $si = [array]::IndexOf($seasons, [int]$lv.season) }
        $cur = @($eps | Where-Object { [int]$_.season -eq $seasons[$si] })
        if ($lv) { $ei = [Math]::Max(0, [array]::IndexOf(@($cur.id), $lv.id)); if ((Get-VidProg $lv.id) -ge 0.92 -and $ei -lt $cur.Count - 1) { $ei++ } }   # visto -> o seguinte
    }
    while ($true) {
        $W = [Console]::WindowWidth; $H = [Console]::WindowHeight
        $pp2 = Get-TitlePosterSize; $ph2 = $pp2.h; $pw2 = $pp2.w
        $x0 = 4 + $pw2 + 4; $tw = $W - $x0 - 4
        $o = "$e[?2026h$e[2J"; $castPend = [Collections.Generic.List[object]]::new()   # imagens que ainda vão chegar (poster, elenco)
        $six = Get-Six $meta.id $pw2 $ph2
        if ($six) { $o += "$e[2;4H$six" }
        elseif ($meta.poster) {
            # o poster não faz esperar: a página aparece já e ele entra quando estiver pronto
            Start-ImgJob @($meta) $pw2 $ph2
            for ($q = 0; $q -lt $ph2; $q++) { $o += "$e[$(2 + $q);4H$e[48;2;$($StTheme.surf)m" + (' ' * $pw2) + "$e[0m" }
            $castPend.Add(@{ id = $meta.id; y = 2; x = 4; w = $pw2; h = $ph2 })
        }
        # título + classificação etária (a de Portugal, se houver)
        $cert = if ($meta.app_extras.certifications.PT) { $meta.app_extras.certifications.PT } else { $meta.app_extras.certification }
        $o += "$e[2;${x0}H$e[1;97m$($meta.name)$e[0m" + $(if ($cert) { "  $e[48;2;$($StTheme.sel);97m $cert $e[0m" })
        $info = @($meta.releaseInfo, $meta.runtime, $(if ($meta.imdbRating) { "$e[33m$([char]0xf005)$e[37m $($meta.imdbRating)$e[90m" }), (@($meta.genres) -join ' · ')) | Where-Object { $_ }
        $fav = if (Test-Fav $meta.id) { "     $e[31m$([char]0x2665) in favorites" } else { '' }
        $o += "$e[3;${x0}H$e[90m" + ($info -join "   ·   ") + $fav + "$e[0m"
        $r = 5
        foreach ($ln in @(Wrap-Lines "$($meta.description)" $tw $(if ($isSeries) { 3 } else { 6 }))) { $o += "$e[$r;${x0}H$e[37m$ln$e[0m"; $r++ }
        # ficha: estreia, realização, argumento, país, classificação, palavras-chave (as que existirem)
        $rel = try { ([datetime]$meta.released).ToString('dd/MM/yyyy') } catch { '' }
        $certs = @(foreach ($c in 'PT', 'BR', 'US', 'GB') { if ($meta.app_extras.certifications.$c) { "$($meta.app_extras.certifications.$c) ($c)" } }) -join '   '
        $rows = @(
            @('released', $rel), @($(if ($isSeries) { 'created by' } else { 'director' }), (@($meta.director) -join ', ')), @('writers', (@($meta.writer) | Select-Object -First 4) -join ', '),
            @('country', (@($meta.country) -join ', ')), @('status', $(if ($isSeries -and $meta.status) { $meta.status })), @('rating', $certs),
            @('keywords', $(if (-not $isSeries) { (@($meta.keywords) | Select-Object -First 8) -join ', ' }))
        ) | Where-Object { $_[1] }
        if ($rows) { $r++; foreach ($x in $rows) { $o += "$e[$r;${x0}H$e[90m$($x[0].PadRight(12))$e[37m$(Fit $x[1] ($tw - 12))$e[0m"; $r++ } }
        $r++
        $trailer = @($meta.trailers | Where-Object ytId) | Select-Object -First 1
        $keys = @($(if ($trailer) { "$e[48;2;$($StTheme.sel);97m  $([char]0xf16a)  trailer  $e[0;90m t$e[0m" }), $(if (Test-Fav $meta.id) { "$e[48;2;$($StTheme.sel);31m  $([char]0x2665)  favorite  $e[0;90m f$e[0m" } else { "$e[48;2;$($StTheme.sel);97m  $([char]0x2661)  favorite  $e[0;90m f$e[0m" })) | Where-Object { $_ }
        $epList = @(); $epTop = 0
        if (-not $isSeries) {
            $p = $Prog.vids[$meta.id]
            $resume = if ($p -and $p.t -gt 30 -and $p.t / [Math]::Max(1, $p.d) -lt 0.92) { "resume from $(Format-Time $p.t)" } else { 'play' }
            $o += "$e[$r;${x0}H$e[48;2;198;120;221;30;1m  $([char]0xf04b)  $resume  $e[0;90m enter$e[0m   " + ($keys -join '   ')
            $r += 3
            # elenco: foto, nome e personagem (as fotos chegam em segundo plano)
            $cast = @($meta.app_extras.cast | Where-Object name)
            $cw = 12; $ch = [Math]::Max(4, [int][Math]::Round($cw * 1.27 / $CellRatio)); $nc = [Math]::Min($cast.Count, [Math]::Floor(($tw + 3) / ($cw + 3)))
            if ($nc -and $r + $ch + 3 -lt $H - 1) {
                $o += "$e[$r;${x0}H$e[1;97mcast$e[0m"; $r++
                $people = @($cast | Select-Object -First $nc | ForEach-Object { [pscustomobject]@{ id = "cast-$($_.name)"; poster = $_.photo; name = $_.name; role = $_.character } })
                Start-ImgJob ($people | Where-Object poster) $cw $ch
                for ($j = 0; $j -lt $nc; $j++) {
                    $pp = $people[$j]; $cx = $x0 + $j * ($cw + 3)
                    $sx = Get-Six $pp.id $cw $ch
                    if ($sx) { $o += "$e[$r;${cx}H$sx" } else {
                        for ($q = 0; $q -lt $ch; $q++) { $o += "$e[$($r + $q);${cx}H$e[48;2;$($StTheme.surf)m" + (' ' * $cw) + "$e[0m" }
                        if ($pp.poster) { $castPend.Add(@{ id = $pp.id; y = $r; x = $cx; w = $cw; h = $ch }) }
                        else {
                            # sem foto no catalogo: as iniciais ao centro (como os avatares do YouTube), em vez de uma caixa vazia
                            $ini = (@("$($pp.name)" -split '\s+' | Where-Object { $_ } | ForEach-Object { $_.Substring(0, 1).ToUpper() }) | Select-Object -First 2) -join ''
                            $o += "$e[$($r + [Math]::Floor($ch / 2));$($cx + [Math]::Floor(($cw - $ini.Length) / 2))H$e[48;2;$($StTheme.surf);1;37m$ini$e[0m"
                        }
                    }
                    $o += "$e[$($r + $ch);${cx}H$e[37m$(Fit $pp.name $cw)$e[$($r + $ch + 1);${cx}H$e[90m$(Fit $pp.role $cw)$e[0m"
                }
            }
        }
        else {
            $o += "$e[$r;${x0}H" + ($keys -join '   '); $r += 2
            $o += "$e[$r;${x0}H" + (Chips @($seasons | ForEach-Object { @{ m = "$_"; n = $(if ($_ -eq 0) { 'specials' } else { "S$_" }) } }) "$($seasons[$si])") + "$e[90m  ← →$e[0m"
            $r += 2; $epTop = $r
            $epList = @($eps | Where-Object { [int]$_.season -eq $seasons[$si] })
        }
        if ($env:WEZTERM_PANE) { Set-Hints 'enter|play;t|trailer;f|favorite;?|all shortcuts;esc|back'; $o += "$e[?2026l" } else { $o += "$e[$H;4H$e[90m? $e[37mshortcuts$e[0m$e[?2026l" }
        [Console]::Write($o)
        # lista de episódios (desenhada à parte: muda com ↑↓ sem redesenhar a página)
        $drawEps = {
            $n = [Math]::Max(1, $H - $epTop - 2); $first = [Math]::Max(0, [Math]::Min($ei - [Math]::Floor($n / 2), $epList.Count - $n))
            $s = ''
            for ($k = 0; $k -lt $n; $k++) {
                $j = $first + $k; $yy = $epTop + $k
                if ($j -ge $epList.Count) { $s += "$e[$yy;${x0}H" + (' ' * $tw); continue }
                $ep = $epList[$j]; $sel = $j -eq $ei; $pg = Get-VidProg $ep.id
                $date = try { ([datetime]$ep.released).ToString('dd/MM/yyyy') } catch { '' }
                $future = try { ([datetime]$ep.released) -gt (Get-Date) } catch { $false }
                $mark = if ($pg -ge 0.92) { "$e[31m$([char]0xf00c)" } elseif ($pg -gt 0) { "$e[33m$([char]0x25D0)" } else { ' ' }
                $name = Fit "$($ep.episode)  $(if ($ep.name) { $ep.name } else { $ep.title })" ($tw - 16)
                $line = " $mark $e[$(if ($sel) { '1;97' } elseif ($future) { '0;90' } else { '0;37' })m$name $e[90m$($date.PadLeft(10)) "
                $s += "$e[$yy;${x0}H" + $(if ($sel) { "$e[48;2;$($StTheme.sel)m$line$e[0m" } else { "$line$e[0m" })
            }
            [Console]::Write($s)
        }
        if ($isSeries) { & $drawEps }
        $redraw = $false
        while (-not $redraw) {
            # fotos do elenco que entretanto chegaram
            while (-not [Console]::KeyAvailable) {
                foreach ($x in @($castPend)) { $sx = Get-Six $x.id $x.w $x.h; if ($sx) { [Console]::Write("$e[$($x.y);$($x.x)H$sx"); [void]$castPend.Remove($x) } }
                Start-Sleep -Milliseconds 50
            }
            $k = Read-Key
            switch ($k.Key) {
                'Escape'     { return }
                'UpArrow'    { if ($isSeries -and $ei -gt 0) { $ei--; & $drawEps } }
                'DownArrow'  { if ($isSeries -and $ei -lt $epList.Count - 1) { $ei++; & $drawEps } }
                'PageUp'     { if ($isSeries) { $ei = [Math]::Max(0, $ei - 10); & $drawEps } }
                'PageDown'   { if ($isSeries) { $ei = [Math]::Min($epList.Count - 1, $ei + 10); & $drawEps } }
                'LeftArrow'  { if ($isSeries -and $si -gt 0) { $si--; $ei = 0; $redraw = $true } }
                'RightArrow' { if ($isSeries -and $si -lt $seasons.Count - 1) { $si++; $ei = 0; $redraw = $true } }
                'Enter' {
                    if ($isSeries) { $ep = $epList[$ei]; $lbl = "S$($ep.season) E$($ep.episode)  $(if ($ep.name) { $ep.name } else { $ep.title })"; [void](Show-Streams $meta $ep.id $lbl) }
                    else { [void](Show-Streams $meta $meta.id '') }
                    # acabou um episódio: passa para o seguinte na lista
                    if ($isSeries -and (Get-VidProg $epList[$ei].id) -ge 0.92 -and $ei -lt $epList.Count - 1) { $ei++ }
                    $redraw = $true
                }
            }
            if ($k.KeyChar -eq 'q') { return }
            if ($k.KeyChar -eq 'f') { Switch-Fav $meta; $redraw = $true }
            if ($k.KeyChar -eq 't' -and $trailer) { Start-Player $meta '' 'trailer' ([pscustomobject]@{ url = "https://youtu.be/$($trailer.ytId)"; file = $trailer.name }) @() -Trailer; $redraw = $true }
            if ($k.KeyChar -eq '?') { Show-Help @(@('↑ ↓', 'episodes'), @('← →', 'seasons'), @('enter', 'pick a stream and play'), @('t', 'trailer'), @('f', 'favorite on / off'), @('esc', 'back')); $redraw = $true }
            if ([Console]::WindowWidth -ne $W -or [Console]::WindowHeight -ne $H) { $redraw = $true }
        }
    }
}

# ---------- streams ----------
$FlagLang = @{ GB = 'en'; US = 'en'; JP = 'ja'; RU = 'ru'; IT = 'it'; PT = 'pt'; BR = 'pt'; ES = 'es'; MX = 'es'; AR = 'es'; CN = 'zh'; TW = 'zh'; FR = 'fr'; DE = 'de'; PL = 'pl'; CZ = 'cs'; HU = 'hu'; TR = 'tr'; IN = 'hi'; UA = 'uk'; TH = 'th'; KR = 'ko'; NL = 'nl'; SE = 'sv'; GR = 'el'; IL = 'he'; SA = 'ar'; VN = 'vi'; ID = 'id' }
$WordLang = @{ 'multi|multi[ .-]?audio|dual[ .-]?audio' = 'multi'; 'ita|italian' = 'it'; 'french|truefrench|vff|vf2' = 'fr'; 'ger|german' = 'de'; 'spa|spanish|latino|castellano' = 'es'; 'rus|russian' = 'ru'; 'hindi|tamil|telugu' = 'hi'; 'kor|korean' = 'ko'; 'jap|jpn|japanese' = 'ja'; 'eng|english' = 'en'; 'por|portuguese|dublado' = 'pt' }
$LangPt = @{ en = 'English'; pt = 'Portuguese'; es = 'Spanish'; fr = 'French'; it = 'Italian'; de = 'German'; ru = 'Russian'; pl = 'Polish'; ja = 'Japanese'; zh = 'Chinese'; ko = 'Korean'; hi = 'Hindi'; tr = 'Turkish'; uk = 'Ukrainian'; cs = 'Czech'; hu = 'Hungarian'; th = 'Thai'; nl = 'Dutch'; sv = 'Swedish'; el = 'Greek'; he = 'Hebrew'; ar = 'Arabic'; vi = 'Vietnamese'; id = 'Indonesian'; multi = 'multiple (multi)' }
function Test-LangFilter($x, [string]$lf, [string]$orig) {
    # auto = sem língua indicada, multi, inglês ou a original; all = todas; senão, uma língua
    switch ($lf) { 'auto' { Test-Lang $x $orig } 'all' { $true } default { $x.langs -contains $lf } }
}
function Test-Lang($x, [string]$orig) {
    # mostra: sem língua indicada, multi, inglês, ou a língua original do título
    -not $x.langs.Count -or [bool]@($x.langs | Where-Object { $_ -in 'multi', 'en', $orig }).Count
}
function ConvertTo-Stream($s, [string]$addon) {
    if (-not $s.url) { return $null }   # (só links diretos: torrents sem debrid e páginas externas não abrem no mpv)
    $t = "$($s.name)`n$($s.title)`n$($s.description)`n$($s.behaviorHints.filename)"
    $q, $ql = if ($t -match '2160p|\b4k\b|uhd') { 4, '4K' } elseif ($t -match '1440p') { 3.5, '1440p' } elseif ($t -match '1080p') { 3, '1080p' } elseif ($t -match '720p') { 2, '720p' } elseif ($t -match '480p|360p|\bsd\b') { 1, 'SD' } else { 0, '?' }
    $size = 0; $sz = ''
    if ($t -match '(\d+(?:[.,]\d+)?)\s?(GB|GiB|MB|MiB)') { $size = [double]($Matches[1] -replace ',', '.') * $(if ($Matches[2] -like 'G*') { 1024 } else { 1 }); $sz = "$($Matches[1]) $($Matches[2] -replace 'i', '')" }
    $cached = ($t -match '⚡|\[RD\+\]|🌩|instant|(?<!un|not )cached') -and $t -notmatch 'download|⬇|uncached|not cached'
    $file = if ($s.behaviorHints.filename) { $s.behaviorHints.filename } else {
        $lines = @(("$($s.title)`n$($s.description)" -split "`n") | ForEach-Object { ($_ -replace '^[^\w\[\(]+', '').Trim() } | Where-Object { $_ })
        if ($lines) { $lines[0] } else { ($s.name -replace '\s+', ' ') }
    }
    $tags = @(); foreach ($tg in 'DV', 'HDR10\+|HDR10|HDR', 'REMUX', 'Atmos', 'HEVC|x265|H\.?265', 'AV1') { if ($t -match "\b($tg)\b") { $tags += ($Matches[1] -replace 'x265|H\.?265', 'HEVC') } }
    # línguas: bandeiras (🇬🇧 🇮🇹 ...) e palavras (ITA, FRENCH, LATINO...); "multi" = várias faixas de áudio
    $langs = [Collections.Generic.HashSet[string]]::new()
    foreach ($m in [regex]::Matches($t, '\uD83C([\uDDE6-\uDDFF])\uD83C([\uDDE6-\uDDFF])')) {
        $cc = [string][char](65 + [int][char]$m.Groups[1].Value - 0xDDE6) + [char](65 + [int][char]$m.Groups[2].Value - 0xDDE6)
        $lg = $FlagLang[$cc]; if ($lg) { [void]$langs.Add($lg) }
    }
    foreach ($w in $WordLang.Keys) { if ($t -match "(?i)\b($w)\b") { [void]$langs.Add($WordLang[$w]) } }
    [pscustomobject]@{ langs = @($langs); q = $q; ql = $ql; size = $size; sz = $sz; cached = $cached; file = ($file -replace '\s+', ' '); tags = ($tags | Select-Object -Unique) -join ' '; addon = ($addon -replace '\s*\|\s*RD$', ''); url = $s.url; subs = @($s.subtitles) }
}
$Resolved = [hashtable]::Synchronized(@{})   # link do addon -> link final no servidor do Real-Debrid
function Start-Resolve($st) {
    # o link do addon é um "resolve" que pede ao RD o link de download (~1,8 s): feito antes do Enter, o mpv arranca logo.
    # só para streams em cache (num que não está, isto poria o RD a descarregar o torrent)
    if (-not $st -or -not $st.cached -or $Resolved.ContainsKey($st.url)) { return }
    $Resolved[$st.url] = $null
    $null = Start-ThreadJob -Name st -ThrottleLimit 100 -ArgumentList $st.url, $Resolved -ScriptBlock {
        param($u, $res)
        $r = curl.exe -s -I -L --max-time 15 -o NUL -w '%{http_code} %{url_effective}' $u   # HEAD: só segue os redirecionamentos (~0,4 s)
        $code, $final = "$r" -split ' ', 2
        if ($code -in '200', '206' -and $final -like 'http*') { $res[$u] = $final } else { $res.Remove($u) }
    }
}
function Get-LangLabel([string]$lf, [string]$orig) {
    switch ($lf) {
        'auto' { if ($orig -eq 'en') { 'English' } else { "$(if ($LangPt[$orig]) { $LangPt[$orig] } else { $orig }) & English" } }
        'all' { 'all' }
        default { if ($LangPt[$lf]) { $LangPt[$lf] } else { $lf } }
    }
}
function Show-Streams($meta, [string]$vid, [string]$label) {
    $type = $meta.type
    $req = Start-StreamFetch $type $vid
    # língua original do título (AIOMetadata: originalLanguage); sem ela, inglês
    $orig = if (($meta | ConvertTo-Json -Depth 6 -Compress) -match '"originalLanguage":"(\w+)"') { $Matches[1] } else { 'en' }; $langF = 'auto'
    $keys = @{} + $req.keys; $srcs = $req.n
    # legendas (por língua: português primeiro)
    $subKeys = $req.subs
    $all = [Collections.Generic.List[object]]::new(); $seenS = @{}; $doneN = 0; $sel = 0; $off = 0; $filter = 0; $filters = @('all', '4K', '1080p', '720p'); $selUrl = $null; $failN = 0; $lastSig = $null
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $W = 0; $H = 0
    while ($true) {
        # junta o que chegou
        $changed = $false
        foreach ($k in @($keys.Keys)) {
            if (-not $Net.ContainsKey($k)) { continue }
            $res = $Net[$k]; $name = $keys[$k]; $keys.Remove($k); $doneN++; $changed = $true; if (-not $res.ok) { $failN++ }
            # o mesmo ficheiro chega de vários addons (ex.: 22.18 GB e 22.2 GB): fica o primeiro (o addon mais rápido)
            if ($res.ok) { foreach ($s in @($res.r.streams)) { $x = ConvertTo-Stream $s $name; if (-not $x) { continue }; $dk = "$($x.file)|$([Math]::Round($x.size / 1024, 1))"; if (-not $seenS[$dk]) { $seenS[$dk] = 1; $all.Add($x) } } }
        }
        # só refaz a lista quando chegam streams ou muda um filtro (antes: a cada 80 ms)
        $sig = "$filter|$langF|$($all.Count)"
        if ($sig -ne $lastSig) { $lastSig = $sig; $list = @($all | Where-Object { ($filter -eq 0 -or $_.ql -eq $filters[$filter]) -and (Test-LangFilter $_ $langF $orig) } | Sort-Object @{ e = 'cached'; d = $true }, @{ e = 'q'; d = $true }, @{ e = 'size'; d = $true }) }
        if ($selUrl) { $i = [array]::IndexOf(@($list.url), $selUrl); if ($i -ge 0) { $sel = $i } }
        if ($sel -ge $list.Count) { $sel = [Math]::Max(0, $list.Count - 1) }
        $full = [Console]::WindowWidth -ne $W -or [Console]::WindowHeight -ne $H
        $W = [Console]::WindowWidth; $H = [Console]::WindowHeight; $n = [Math]::Max(1, $H - 8)
        if ($sel -lt $off) { $off = $sel } elseif ($sel -ge $off + $n) { $off = $sel - $n + 1 }
        $wait = $keys.Count
        $o = "$e[?2026h" + $(if ($full) { "$e[2J" } else { '' })
        $o += "$e[2;4H$e[2K$e[1;97m$($meta.name)$e[0;90m$(if ($label) { "   $label" })$e[0m"
        $status = if ($wait) { "$e[${Accent}m$($Frames[$script:Spin++ % 10])$e[90m  searching $wait addons" } else { "$e[90m$srcs addons$(if ($failN) { "$e[31m  ($failN failed)" })" }
        $o += "$e[3;4H$e[2K$e[37m$($list.Count) streams$e[90m   ·   $status$e[90m   ·   filter $e[37m$($filters[$filter])$e[90m (f)   ·   language $e[37m$(Get-LangLabel $langF $orig)$e[90m (l)$e[0m"
        $fw = [Math]::Max(20, $W - 4 - 6 - 3 - 9 - 16 - 16 - 6)
        for ($k = 0; $k -lt $n; $k++) {
            $j = $off + $k; $yy = 5 + $k
            if ($j -ge $list.Count) { $o += "$e[$yy;1H$e[2K"; continue }
            $x = $list[$j]; $isSel = $j -eq $sel
            $qc = switch ($x.ql) { '4K' { '48;2;198;120;221;30' } '1440p' { '48;2;152;94;172;97' } '1080p' { '48;2;97;175;239;38;2;40;44;52' } default { '48;2;62;68;81;37' } }
            $ca = if ($x.cached) { "$e[33m$([char]0xf0e7)" } else { "$e[90m$([char]0xf019)" }
            $line = "$e[${qc}m $($x.ql.PadRight(5)) $e[0m$(if ($isSel) { "$e[48;2;$($StTheme.sel)m" })  $ca  $e[$(if ($isSel) { '1;97' } else { '0;37' })m$(Fit $x.file $fw)  $e[90m$((Fit $x.tags 16))$e[36m$($x.sz.PadLeft(9))  $e[90m$(Fit $x.addon 14) $e[0m"
            $o += "$e[$yy;1H$e[2K$e[$yy;4H$line"
        }
        if (-not $list.Count -and -not $wait) { $o += "$e[6;4H$e[90mno streams found$(if ($filter) { ' with this filter' })$e[0m" }
        $o += "$e[$H;4H$e[2K$e[90m$([char]0xf0e7) cached on Real-Debrid (instant)   $([char]0xf019) not cached$(if (-not $env:WEZTERM_PANE) { "   ·   ? shortcuts" })$e[0m$e[?2026l"; Set-Hints 'enter|play;l|language;?|all shortcuts;esc|back'; $o += ""
        [Console]::Write($o)
        # espera por tecla (e vai juntando os addons que respondem)
        # o primeiro da lista e o escolhido (parado ~0,4 s) ficam já resolvidos para o Enter abrir logo
        if ($list.Count) { Start-Resolve $list[0] }
        if ($selKey -ne "$sel|$($list[$sel].url)") { $selKey = "$sel|$($list[$sel].url)"; $selSw = [Diagnostics.Stopwatch]::StartNew() }
        while (-not [Console]::KeyAvailable) {
            Start-Sleep -Milliseconds 80
            if ($list.Count -and $selSw.ElapsedMilliseconds -gt 400) { Start-Resolve $list[$sel] }
            if ($keys.Count) { if (@($keys.Keys | Where-Object { $Net.ContainsKey($_) }).Count -or $sw.ElapsedMilliseconds % 400 -lt 90) { break } }
            if ([Console]::WindowWidth -ne $W -or [Console]::WindowHeight -ne $H) { break }
        }
        if (-not [Console]::KeyAvailable) { continue }
        $k = Read-Key
        switch ($k.Key) {
            'Escape'    { return }
            'UpArrow'   { if ($sel -gt 0) { $sel-- }; $selUrl = $list[$sel].url }
            'DownArrow' { if ($sel -lt $list.Count - 1) { $sel++ }; $selUrl = $list[$sel].url }
            'PageUp'    { $sel = [Math]::Max(0, $sel - $n); $selUrl = $list[$sel].url }
            'PageDown'  { $sel = [Math]::Min($list.Count - 1, $sel + $n); $selUrl = $list[$sel].url }
            'Enter' {
                if ($list.Count) {
                    $subs = @(foreach ($sk in $subKeys) { if ($Net[$sk].ok) { @($Net[$sk].r.subtitles) } }) + @($list[$sel].subs)
                    Start-Player $meta $vid $label $list[$sel] $subs
                    $W = 0
                    if ((Get-VidProg $vid) -ge 0.92) { return }   # visto até ao fim: volta à página do título
                }
            }
        }
        switch ($k.KeyChar) {
            'f' { $filter = ($filter + 1) % $filters.Count; $sel = 0; $selUrl = $null }
            'l' {
                # lista das línguas que aparecem nos streams deste título, com quantos há de cada
                $cnt = @{}; foreach ($x in $all) { foreach ($lg in $x.langs) { $cnt[$lg]++ } }
                $opts = [ordered]@{}
                $opts["$(Get-LangLabel 'auto' $orig)  ($(@($all | Where-Object { Test-Lang $_ $orig }).Count))"] = 'auto'
                $opts["all  ($($all.Count))"] = 'all'
                foreach ($lg in ($cnt.Keys | Sort-Object { $cnt[$_] } -Descending)) { $opts["$(if ($LangPt[$lg]) { $LangPt[$lg] } else { $lg })  ($($cnt[$lg]))"] = $lg }
                $cur = @($opts.Keys | Where-Object { $opts[$_] -eq $langF })[0]
                $pick = Select-Option 'language' @($opts.Keys) $cur
                if ($null -ne $pick) { $langF = $opts[$pick]; $sel = 0; $selUrl = $null }
                $W = 0
            }
            'q' { return }
            '?' { Show-Help @(@('↑ ↓', 'select'), @('enter', 'play'), @('f', 'filter quality'), @('l', 'filter language'), @('esc', 'back'), @('', ''), @('in video', ''), @('space', 'pause'), @('f', 'fullscreen'), @('q', 'quit video (saves position)')); $W = 0 }
        }
    }
}

# ---------- reprodução ----------
$MpvPipe = "stmpv-$PID"
function Get-MpvProp([string]$name) {
    try {
        $c = [IO.Pipes.NamedPipeClientStream]::new('.', $MpvPipe, [IO.Pipes.PipeDirection]::InOut); $c.Connect(150)
        $w = [IO.StreamWriter]::new($c); $rd = [IO.StreamReader]::new($c)
        $w.WriteLine((@{ command = @('get_property', $name); request_id = 7 } | ConvertTo-Json -Compress)); $w.Flush()
        # com tempo limite: um mpv preso não congela o st
        for ($i = 0; $i -lt 6; $i++) { $tk = $rd.ReadLineAsync(); if (-not $tk.Wait(300)) { break }; $line = $tk.Result; if (-not $line) { break }; $j = $line | ConvertFrom-Json; if ($j.request_id -eq 7) { $c.Dispose(); return $j.data } }
        $c.Dispose()
    } catch {}
    $null
}
function Get-WtClient {
    # área do Windows Terminal no ecrã (o vídeo cobre-a); $null por SSH ou fora do WT
    $wt = (Get-Process -Id $PID).Parent
    if ($wt.ProcessName -ne 'WindowsTerminal' -or $env:SSH_CONNECTION) { return $null }
    if (-not ('W.StWin3' -as [type])) {
        Add-Type -Namespace W -Name StWin3 -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Rt, B; }
[StructLayout(LayoutKind.Sequential)] public struct P { public int X, Y; }
[DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out R r);
[DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref P p);
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
[DllImport("user32.dll")] public static extern IntPtr SetWindowLongPtr(IntPtr h, int i, IntPtr v);
[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
[DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr p);
[DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
[DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
'@
        [void][W.StWin3]::SetProcessDpiAwarenessContext([IntPtr]-4)
    }
    # a janela do WT que tem este separador (com "useExisting" um só processo tem várias janelas)
    $h = [W.StWin3]::GetAncestor([W.StWin3]::GetConsoleWindow(), 3); if ($h -eq [IntPtr]::Zero) { $h = $wt.MainWindowHandle }
    $r = New-Object W.StWin3+R; [void][W.StWin3]::GetClientRect($h, [ref]$r)
    $p = New-Object W.StWin3+P; [void][W.StWin3]::ClientToScreen($h, [ref]$p)
    @{ x = $p.X; y = $p.Y; w = $r.Rt; h = $r.B; wt = $h }
}
function Send-Mpv([string[]]$cmd) {
    try {
        $c = [IO.Pipes.NamedPipeClientStream]::new('.', $MpvPipe, [IO.Pipes.PipeDirection]::Out); $c.Connect(300)
        $w = [IO.StreamWriter]::new($c); $w.WriteLine((@{ command = $cmd } | ConvertTo-Json -Compress)); $w.Flush(); $c.Dispose()
    } catch {}
}
$LangNames = @{ por = 'Português'; pt = 'Português'; pob = 'Português (BR)'; 'pt-br' = 'Português (BR)'; eng = 'English'; en = 'English'; spa = 'Español'; es = 'Español'; fre = 'Français'; fra = 'Français'; fr = 'Français'; ger = 'Deutsch'; deu = 'Deutsch'; ita = 'Italiano'; jpn = '日本語' }
# controlos do uosc no st: legendas, áudio, faixas e capítulos (o yt usa só qualidade)
$StControls = 'menu,gap,subtitles,<has_many_audio>audio,<has_many_video>video,<has_many_edition>editions,<has_chapter>chapters,gap,space,speed,gap,fullscreen'
function Start-Player($meta, [string]$vid, [string]$label, $st, $subs, [switch]$Trailer) {
    $title = if ($label) { "$($meta.name) — $label" } else { $meta.name }
    $p = $Prog.vids[$vid]; $start = if (-not $Trailer -and $p -and $p.t -gt 30 -and $p.t / [Math]::Max(1, $p.d) -lt 0.92) { [int]$p.t - 3 } else { 0 }
    $g = Get-WtClient
    $place = if ($g) { @('--no-border', ('--geometry={0}x{1}+{2}+{3}' -f $g.w, $g.h, $g.x, $g.y)) } else { @('--fs') }
    $a = @($place) + @("--input-ipc-server=\\.\pipe\$MpvPipe", "--force-media-title=$title", "--start=$start", '--slang=por,pt,pob', '--alang=por,pt,eng,en,jpn',
        "--script-opts-append=uosc-controls=$StControls", '--script-opts-append=uosc-top_bar=no-border',
        '--background-color=#000000', '--sub-font=Segoe UI Semibold', '--sub-font-size=44', '--sub-border-size=2.5', '--sub-shadow-offset=1', '--sub-margin-y=40', "--input-conf=$HOME\.config\mpv\st-input.conf", '--window-dragging=no') + $MpvOpts
    if ($Trailer -and (Test-Path "$HOME\.config\yt-cookies.txt")) { $a += "--ytdl-raw-options=cookies=$HOME\.config\yt-cookies.txt,extractor-args=youtube:player_client=web_safari", '--ytdl-format=best[protocol^=m3u8][height<=1080]/best' }


    # ecrã de carregamento: poster, título, o stream escolhido e o estado (fica por baixo do vídeo)
    $W = [Console]::WindowWidth; $H = [Console]::WindowHeight
    $ph = [Math]::Min(16, $H - 8); $pw = [int][Math]::Round($ph * $CellRatio / 1.5); $tw = [Math]::Min(70, $W - $pw - 16)
    $x0 = [Math]::Max(4, [Math]::Floor(($W - $pw - 6 - $tw) / 2)); $y0 = [Math]::Max(2, [Math]::Floor(($H - $ph) / 2)); $tx = $x0 + $pw + 6
    $o = "$e[?2026h$e[2J"; $six = Get-Six $meta.id $pw $ph
    if ($six) { $o += "$e[$y0;${x0}H$six" } else { Start-ImgJob @($meta) $pw $ph }
    $r = $y0 + 1
    $o += "$e[$r;${tx}H$e[1;97m$(Fit $meta.name $tw)$e[0m"; $r++
    if ($label) { $o += "$e[$r;${tx}H$e[37m$(Fit $label $tw)$e[0m"; $r++ }
    $r++
    if ($Trailer) { $o += "$e[$r;${tx}H$e[48;2;$($StTheme.sel);97m trailer $e[0m  $e[90m$(Fit $st.file ($tw - 12))$e[0m"; $r += 2 }
    else {
        $qc = switch ($st.ql) { '4K' { '48;2;198;120;221;30' } '1440p' { '48;2;152;94;172;97' } '1080p' { '48;2;97;175;239;38;2;40;44;52' } default { '48;2;62;68;81;37' } }
        $o += "$e[$r;${tx}H$e[${qc}m $($st.ql) $e[0m  " + $(if ($st.cached) { "$e[33m$([char]0xf0e7) cached  " } else { "$e[90m$([char]0xf019) preparing on Real-Debrid  " }) + "$e[36m$($st.sz)$e[90m   $($st.addon)$e[0m"; $r++
        foreach ($ln in @(Wrap-Lines $st.file $tw 2)) { $o += "$e[$r;${tx}H$e[90m$ln$e[0m"; $r++ }
        if ($st.tags) { $o += "$e[$r;${tx}H$e[90m$($st.tags)$e[0m"; $r++ }
        $r++
        $sl = @($subs | Where-Object url | ForEach-Object { $n = $LangNames["$($_.lang)".ToLower()]; if ($n) { $n } else { $_.lang } } | Select-Object -Unique)
        $o += "$e[$r;${tx}H$e[90msubtitles  $e[37m$(if ($sl) { $sl -join ', ' } else { 'embedded only' })$e[0m"; $r++
        if ($start) { $o += "$e[$r;${tx}H$e[90mresumes at  $e[37m$(Format-Time $start)$e[0m"; $r++ }
    }
    $stateRow = $r + 1; $barRow = $r + 2
    $o += "$e[$($y0 + $ph - 1);${tx}H$e[37mesc$e[90m back   $e[37mspace$e[90m pause   $e[37m← →$e[90m 10 s   $e[37m↑ ↓$e[90m volume   $e[37ms$e[90m subtitles   $e[37ma$e[90m audio   $e[37mf$e[90m fullscreen$e[0m$e[?2026l"
    [Console]::Write($o)

    # link já resolvido na lista de streams (ou ainda a resolver: espera um pouco, é o mesmo que o mpv faria)
    if ($Resolved.ContainsKey($st.url) -and -not $Resolved[$st.url]) { $w0 = [Diagnostics.Stopwatch]::StartNew(); while ($Resolved.ContainsKey($st.url) -and -not $Resolved[$st.url] -and $w0.ElapsedMilliseconds -lt 3000) { Start-Sleep -Milliseconds 40 } }
    $a += $(if ($Resolved[$st.url]) { $Resolved[$st.url] } else { $st.url })
    $mp = Start-Process $MpvWin -PassThru -ArgumentList (Quote-Args $a)
    if ($g) {
        # janela do vídeo "pertence" ao terminal: fica por cima dele, no mesmo ambiente de trabalho, e recebe o teclado
        # o vídeo fica com o foco (rato e teclas vão direto ao mpv; uma janela "não ativável" perdia o largar do rato
        # e o uosc ficava a arrastar a barra de tempo) e "pertence" ao terminal: por cima dele e no mesmo ambiente de trabalho
        $null = Start-ThreadJob -Name st -ThrottleLimit 100 -ArgumentList $mp, $g.wt -ScriptBlock {
            param($p, $wt)
            for ($i = 0; $i -lt 300 -and -not $p.HasExited; $i++) {
                $p.Refresh(); $h = $p.MainWindowHandle
                if ($h -ne [IntPtr]::Zero) { [void][W.StWin3]::SetWindowLongPtr($h, -8, $wt); return }
                Start-Sleep -Milliseconds 60
            }
        }
    }
    # enquanto abre: animação; a tocar: legendas dos addons (com nomes) e a posição guardada de 2 em 2 s
    $t = $null; $d = $null; $subsAdded = $false; $i = 0; $tick = 0; $cancelled = $false; $saveSw = [Diagnostics.Stopwatch]::StartNew()
    $keep = { if (-not $Trailer -and $null -ne $t -and $d) {
        $Prog.vids[$vid] = @{ t = $t; d = $d }
        $Prog.items[$meta.id] = @{ id = $meta.id; type = $meta.type; name = $meta.name; poster = $meta.poster; vid = $vid; t = $t; d = $d; at = (Get-Date).ToString('o') }
        Save-Prog } }
    try {
    while (-not $mp.HasExited) {
        # guarda a posição a cada 30 s (um crash ou fechar o terminal já não perde o progresso)
        if ($saveSw.Elapsed.TotalSeconds -gt 30) { $saveSw.Restart(); . $keep }
        if (-not $six -and ($six = Get-Six $meta.id $pw $ph)) { [Console]::Write("$e[$y0;${x0}H$six") }
        if ($tick-- -le 0) {
            $tp = Get-MpvProp 'time-pos'; if ($null -ne $tp) { $t = [double]$tp }
            if (-not $d) { $dd = Get-MpvProp 'duration'; if ($dd) { $d = [double]$dd } }
            $tick = if ($null -eq $t) { 5 } else { 25 }
            if ($null -ne $t -and -not $subsAdded) {
                $subsAdded = $true; $pick = $true; $n = @{}
                foreach ($s in @($subs | Where-Object url | Sort-Object { switch -Regex ($_.lang) { '^(por|pt$|pt-pt)' { 0 } '^(pob|pt-br)' { 1 } '^(eng|en)' { 2 } default { 3 } } } | Select-Object -First 10)) {
                    $ln = $LangNames["$($s.lang)".ToLower()]; if (-not $ln) { $ln = $s.lang }; $n[$ln]++
                    $isPt = "$($s.lang)" -match '^(por|pt|pob)'
                    Send-Mpv 'sub-add', $s.url, $(if ($isPt -and $pick) { 'select' } else { 'auto' }), "$ln $($n[$ln])", "$($s.lang)"
                    if ($isPt) { $pick = $false }
                }
            }
            $state = if ($null -eq $t) { "$e[${Accent}m$($Frames[$i % 10])$e[37m  opening video" } else { "$e[32m$([char]0xf04b)$e[37m  playing" }
            $bw = $tw - 18; $f = if ($t -and $d) { [int]($bw * [Math]::Min(1, $t / $d)) } else { 0 }
            $bar = if ($null -ne $t) { "$e[37m$(Format-Time $t)  $e[${Accent}m" + ([string][char]0x2501 * $f) + "$e[90m" + ([string][char]0x2500 * ($bw - $f)) + "  $e[37m$(Format-Time $d)" } else { '' }
            [Console]::Write("$e[$stateRow;${tx}H$e[0K$state$e[0m$e[$barRow;${tx}H$e[0K$bar$e[0m")
        }
        elseif ($null -eq $t -and $tick % 1 -eq 0) { [Console]::Write("$e[$stateRow;${tx}H$e[${Accent}m$($Frames[$i % 10])$e[0m") }
        # teclas do terminal -> mpv (as mesmas do st-input.conf; com um menu do uosc aberto, vão para o menu)
        while ([Console]::KeyAvailable) {
            $k = Read-Key
            $name = switch ($k.Key) { 'Escape' { 'ESC' } 'Enter' { 'ENTER' } 'Spacebar' { 'SPACE' } 'UpArrow' { 'UP' } 'DownArrow' { 'DOWN' } 'LeftArrow' { 'LEFT' } 'RightArrow' { 'RIGHT' } 'PageUp' { 'PGUP' } 'PageDown' { 'PGDWN' } 'Backspace' { 'BS' } 'Tab' { 'TAB' } default { if ([int]$k.KeyChar -gt 32) { "$($k.KeyChar)" } } }
            if ($name) { Send-Mpv 'keypress', $name }
            if ($null -eq $t -and $name -in 'ESC', 'q') { $cancelled = $true; Stop-Process -Id $mp.Id -ErrorAction SilentlyContinue }   # ainda a abrir: cancela
        }
        $i++; Start-Sleep -Milliseconds 80
    }
    } finally { if (-not $mp.HasExited) { try { $mp.Kill($true) } catch {} } }
    if ($g) {
        $fg = [W.StWin3]::GetForegroundWindow()
        if ($fg -ne $g.wt) { $ta = [W.StWin3]::GetCurrentThreadId(); $tb = [W.StWin3]::GetWindowThreadProcessId($fg, [IntPtr]::Zero); [void][W.StWin3]::AttachThreadInput($ta, $tb, $true); [void][W.StWin3]::SetForegroundWindow($g.wt); [void][W.StWin3]::AttachThreadInput($ta, $tb, $false) }
    }
    if ($Trailer) { return }
    if ($null -ne $t -and $d) { . $keep }
    elseif ($mp.ExitCode -ne 0 -and -not $cancelled) {
        $msg = if (-not $st.cached) { "this stream isn't on Real-Debrid yet (it just started downloading) — pick one with $([char]0xf0e7)" } else { 'mpv could not open this stream — try another' }
        [Console]::Write("$e[$stateRow;${tx}H$e[0K$e[31m$msg$e[0m$e[$($stateRow + 1);${tx}H$e[90mpress any key to go back$e[0m"); [void](Read-Key)
    }
}

# ---------- principal ----------
if (-not (Test-Path $AuthFile)) { if (-not (Invoke-Login)) { return } }
[Console]::Write("$e[?1049h$e[?25l$e[2J")
try {
    # addons da conta (o AIOMetadata dá os catálogos e a pesquisa; os outros, os streams e as legendas)
    $null = Start-ThreadJob -Name st -ThrottleLimit 100 -ArgumentList $Api, (Get-Content $AuthFile -Raw).Trim(), $Net -ScriptBlock {
        param($api, $k, $net)
        # sessão expirada: a API responde 200 com .error e sem .result
        try { $r = Invoke-RestMethod -Method Post "$api/addonCollectionGet" -Body (@{ authKey = $k; update = $true } | ConvertTo-Json) -ContentType 'application/json' -TimeoutSec 20
            $net['addons'] = if ($r.result) { @{ ok = $true; r = $r.result.addons } } else { @{ ok = $false; auth = $true; err = "$($r.error.message)" } } } catch { $net['addons'] = @{ ok = $false; err = "$_" } }
    }
    Wait-Spin { $Net.ContainsKey('addons') } 'connecting to your Stremio account'
    $Addons = @(if ($Net['addons'].ok) { $Net['addons'].r })
    $Aio = $Addons | Where-Object { $_.manifest.name -eq 'AIOMetadata' } | Select-Object -First 1
    if (-not $Aio) {
        if ($Net['addons'].auth) { Remove-Item $AuthFile -ErrorAction SilentlyContinue }
        $m = if ($Net['addons'].auth) { 'your Stremio session expired — run st again to sign in' } elseif ($Net['addons'].ok) { 'the AIOMetadata addon is missing from the account (it provides catalogs and search)' } else { "could not read the account's addons ($($Net['addons'].err)); if the session expired, delete ~\.config\stremio-auth.txt" }
        [Console]::Write("$e[$([Math]::Floor([Console]::WindowHeight / 2));4H$e[31m$m$e[0m"); [void](Read-Key); return
    }
    $L = Get-Layout
    $views = @{ explore = (New-View 'explore'); favs = (New-View 'favs') }
    $v = $views['explore']
    if ($Rest) { $v.q = $Rest -join ' '; $v.type = 'all'; Reset-View $v }
    Draw-Grid $v
    :main while ($true) {
        # à espera de tecla: junta os resultados que chegam e desenha os posters que ficam prontos
        $mk = $null
        [void][W.Con]::SetConsoleMode($InH, $InModeSt)
        while (-not [Console]::KeyAvailable) {
            # rato (lido antes do KeyAvailable, que deita fora os eventos que nao sao teclas)
            $mm = [St.Mouse]::Read($InH)
            if ($mm) {
                $mx = [St.Mouse]::X + 1; $my = [St.Mouse]::Y + 1; $it = @(Get-Items $v); $start = [Math]::Floor($v.sel / $L.per) * $L.per
                if ($mm -eq 2) { $mk = New-Key 0 $(if ([St.Mouse]::Wheel -gt 0) { 'UpArrow' } else { 'DownArrow' }); break }
                $slot = Get-TileAt $mx $my
                if ($slot -ge 0 -and $start + $slot -lt $it.Count) {
                    if ($mm -eq 1) { $v.sel = $start + $slot; $mk = New-Key "`r" 'Enter'; break }
                    if ($v.sel -ne $start + $slot) {
                        $old = $v.sel; $v.sel = $start + $slot
                        [Console]::Write((Draw-TileText $it[$old] ($old % $L.per) $false) + (Draw-TileText $it[$v.sel] ($v.sel % $L.per) $true) + (Draw-Filters $v $it))
                    }
                }
                elseif ($mm -eq 1 -and $my -le 3) { $mk = New-Key '/' 'Oem2'; break }   # (a caixa de pesquisa)
            }
            if (Update-Load $v) {
                $items = @(Get-Items $v)
                if ($v.drawn -lt $L.per -and $items.Count -gt [Math]::Floor($v.sel / $L.per) * $L.per + $v.drawn) { Draw-Grid $v } else { [Console]::Write((Draw-Filters $v $items)) }
            }
            Update-Pending
            # parado ~0,35 s num poster: prepara a página do título (metadados + poster grande)
            $hk = "$($v.tab)-$($v.sel)"
            if ($hk -ne $hovKey) { $hovKey = $hk; $hovSw = [Diagnostics.Stopwatch]::StartNew(); $hovDone = $false }
            if (-not $hovDone -and $hovSw.ElapsedMilliseconds -gt 350) { $hovDone = $true; $it = @(Get-Items $v); if ($v.sel -lt $it.Count) { Start-TitlePrefetch $it[$v.sel] } }
            if ([Console]::WindowWidth -ne $L.W -or [Console]::WindowHeight -ne $L.H) { Draw-Grid $v }
            Start-Sleep -Milliseconds 40
        }
        $k = if ($mk) { $mk } else { Read-Key }
        if ($L.W -lt 60 -or $L.H -lt 24) { if ($k.Key -eq 'Escape' -or $k.KeyChar -eq 'q') { return }; continue main }
        $items = @(Get-Items $v); $n = $items.Count; $old = $v.sel; $reset = $false
        switch ($k.Key) {
            'RightArrow' { $v.sel = [Math]::Max(0, [Math]::Min($n - 1, $v.sel + 1)) }
            'LeftArrow'  { $v.sel = [Math]::Max(0, $v.sel - 1) }
            'DownArrow'  { $v.sel = [Math]::Max(0, [Math]::Min($n - 1, $v.sel + $L.cols)) }
            'UpArrow'    { $v.sel = [Math]::Max(0, $v.sel - $L.cols) }
            'PageDown'   { $v.sel = [Math]::Max(0, [Math]::Min($n - 1, $v.sel + $L.per)) }
            'PageUp'     { $v.sel = [Math]::Max(0, $v.sel - $L.per) }
            'Tab'        { $v = $views[$(if ($v.tab -eq 'explore') { 'favs' } else { 'explore' })]; Draw-Grid $v; continue main }
            'Enter'      { if ($n) { Show-Title $items[$v.sel]; Draw-Grid $v }; continue main }
            'Escape'     { if ($v.q) { $v.q = ''; if ($v.tab -eq 'explore') { $v.type = 'movie' }; Reset-View $v; Draw-Grid $v; continue main } else { return } }
        }
        switch -CaseSensitive ($k.KeyChar) {
            'q' { return }
            '1' { $v = $views['explore']; Draw-Grid $v; continue main }
            '2' { $v = $views['favs']; Draw-Grid $v; continue main }
            '?' { Show-Help @(@('arrows', 'move'), @('enter', 'open (episodes and streams)'), @('/  s', 'search (or ctrl+f)'), @('t', 'type: movies / series / all'), @('g', 'genre'), @('o', 'sort'), @('f', 'favorite on / off'), @('tab  1 2', 'explore / favorites'), @('esc', 'clear search / quit')); Draw-Grid $v; continue main }
            { $_ -eq '/' -or $_ -eq 's' -or $_ -eq [char]6 } { $q = Read-Search $v.q; if ($q) { $v.q = $q; if ($v.tab -eq 'explore') { $v.type = 'all' }; $reset = $true } else { Draw-Grid $v; continue main } }
            't' { $v.type = @{ movie = 'series'; series = 'all'; all = 'movie' }[$v.type]; if ($v.genre -and -not ($v.type -eq 'all' -or (Get-TypeGenre $v.genre $v.type))) { $v.genre = '' }; $reset = $true }
            'g' { $g = Select-Option 'genre' (@('all') + @(Get-Genres $v.type)) $(if ($v.genre) { $v.genre } else { 'all' }); if ($null -ne $g) { $v.genre = if ($g -eq 'all') { '' } else { $g }; $reset = $true } else { Draw-Grid $v; continue main } }
            'o' { $os = if ($v.tab -eq 'favs') { 'added', 'name', 'rating' } else { 'trending', 'recent' }; $v.order = $os[([array]::IndexOf($os, $v.order) + 1) % $os.Count]; $reset = $true }
            'f' { if ($n) { Switch-Fav $items[$v.sel]; if ($v.tab -eq 'favs') { Draw-Grid $v } else { [Console]::Write((Draw-TileText $items[$v.sel] ($v.sel % $L.per) $true)) } }; continue main }
            'r' { $reset = $true }
        }
        if ($reset) { Reset-View $v; Draw-Grid $v; continue main }
        if ($v.sel -ne $old) {
            if ([Math]::Floor($v.sel / $L.per) -ne [Math]::Floor($old / $L.per)) { Draw-Grid $v }
            else { [Console]::Write((Draw-TileText $items[$old] ($old % $L.per) $false) + (Draw-TileText $items[$v.sel] ($v.sel % $L.per) $true)) }
        }
        # perto do fim: pede mais
        if ($v.sel -ge $n - $L.per) { Start-Load $v }
    }
}
finally {
    Set-Hints ''; [void][W.Con]::SetConsoleMode($InH, $InMode); [Console]::Write("$e[0m$e[?25h$e[?1049l")
    Get-Job | Where-Object Name -eq 'st' | Remove-Job -Force -ErrorAction SilentlyContinue   # (so os do st: corre dentro do teu shell)
}
