# view <ficheiro>: mostra bem no terminal
#   .md       -> glow (cores, tabelas, codigo) + diagramas mermaid desenhados como imagem (mmdc + chafa/sixel)
#   .pdf      -> paginas como imagem, navegaveis (setas / pgup pgdn / home end / q)
#   imagens   -> chafa
#   o resto   -> bat
param([Parameter(Mandatory)][string]$Path)
$e = [char]27
$f = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
if (-not $f) { Write-Host "  '$Path' doesn't exist" -ForegroundColor Yellow; return }
$f = $f.ProviderPath
$Cache = "$env:TEMP\view"; New-Item -ItemType Directory $Cache -Force | Out-Null
try { $W = [Console]::WindowWidth; $H = [Console]::WindowHeight } catch { $W = if ($env:COLUMNS) { [int]$env:COLUMNS } else { 120 }; $H = if ($env:LINES) { [int]$env:LINES } else { 40 } }   # (sem consola: vindo do WSL)
$W = [Math]::Max($W, 60); $H = [Math]::Max($H, 20)

function Show-Image([string]$img, [int]$cols, [int]$rows) {
    # sixel (o Windows Terminal desenha) com o tamanho em celulas; a imagem fica a esquerda com margem de 2
    $six = & chafa -f sixel --size "${cols}x${rows}" --animate off $img 2>$null | Out-String
    [Console]::Write("  " + $six.TrimEnd() + "`n")
}

function Show-Markdown([string]$file) {
    $md = [IO.File]::ReadAllText($file)
    $ww = [Math]::Min(110, $W - 4)
    # o glow so pinta quando escreve num terminal; daqui a saida passa por um pipe, por isso forca as cores
    $env:CLICOLOR_FORCE = '1'; $env:COLORTERM = 'truecolor'
    $pp = "$env:TEMP\view\mermaid-pp.json"   # o mmdc usa o Edge do Windows (sem descarregar o Chromium)
    if (-not (Test-Path $pp)) { '{"executablePath":"C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe","args":["--no-sandbox"]}' | Set-Content $pp }
    $parts = [regex]::Split($md, '(?ms)^```mermaid[ \t]*\r?\n(.*?)^```[ \t]*$')
    # Split com um grupo: [texto, mermaid, texto, mermaid, ...]
    for ($i = 0; $i -lt $parts.Count; $i++) {
        if ($i % 2 -eq 0) {
            if ($parts[$i].Trim()) { $parts[$i] | glow - -s dark -w $ww | Out-String | ForEach-Object { [Console]::Write($_) } }
            continue
        }
        $code = $parts[$i]
        $hash = [BitConverter]::ToString([Security.Cryptography.SHA1]::HashData([Text.Encoding]::UTF8.GetBytes($code))).Replace('-', '').Substring(0, 16)
        $png = "$Cache\$hash.png"
        if (-not (Test-Path $png)) {
            [Console]::Write("  $e[90mrendering diagram...$e[0m`r")
            $src = "$Cache\$hash.mmd"; [IO.File]::WriteAllText($src, $code)
            $mmdc = if (Get-Command mmdc -ErrorAction SilentlyContinue) { 'mmdc' } else { "$env:APPDATA\npm\mmdc.cmd" }   # (o npm global nem sempre esta no PATH)
            $err = & $mmdc -i $src -o $png -t dark -b transparent -s 2 -p $pp -q 2>&1 | Out-String
            Remove-Item $src -ErrorAction SilentlyContinue
            [Console]::Write("$e[2K")
        }
        if (Test-Path $png) {
            # altura proporcional a imagem, no maximo meio ecra
            Add-Type -AssemblyName System.Drawing
            $im = [Drawing.Image]::FromFile($png); $ratio = $im.Height / $im.Width; $im.Dispose()
            $cols = [Math]::Min($ww, 100); $rows = [Math]::Max(4, [Math]::Min([int]($H / 2), [int]($cols * $ratio / 2.1)))
            Show-Image $png $cols $rows
        } else {
            $msg = "$($err -split "`n" | Where-Object { $_ -match 'Error|not recognized' } | Select-Object -First 1)".Trim()
            Write-Host "  couldn't draw this diagram$(if ($msg) { ": $msg" })" -ForegroundColor Red
            ('```' + "`n" + $code + '```') | glow - -s dark -w $ww | Out-String | ForEach-Object { [Console]::Write($_) }
        }
    }
    Remove-Item Env:CLICOLOR_FORCE
}

function Show-Pdf([string]$file) {
    $n = [int]("$(& pdfinfo $file 2>$null | Where-Object { $_ -match '^Pages:' } | Select-Object -First 1)" -replace '\D', '')
    if (-not $n) { Write-Host "  couldn't read this pdf" -ForegroundColor Yellow; return }
    $name = Split-Path $file -Leaf; $p = 1; $shown = 0
    [Console]::Write("$e[?1049h$e[?25l")
    try {
        while ($true) {
            if ($p -ne $shown -or [Console]::WindowWidth -ne $W -or [Console]::WindowHeight -ne $H) {
                $W = [Console]::WindowWidth; $H = [Console]::WindowHeight; $shown = $p
                $png = "$Cache\pdf-$((Get-Item $file).LastWriteTime.Ticks)-$p"
                if (-not (Test-Path "$png.png")) { & pdftoppm -f $p -l $p -r 110 -png -singlefile $file $png 2>$null }
                [Console]::Write("$e[2J$e[1;1H")
                if (Test-Path "$png.png") { Show-Image "$png.png" ($W - 4) ($H - 3) }
                [Console]::Write("$e[$H;3H$e[2K$e[1;97m$name$e[0;90m   page $e[37m$p$e[90m / $n   ·   ← → pages   home end   q quit$e[0m")
            }
            if (-not [Console]::KeyAvailable) { Start-Sleep -Milliseconds 50; continue }
            $k = [Console]::ReadKey($true)
            switch ($k.Key) {
                { $_ -in 'RightArrow', 'DownArrow', 'PageDown', 'Spacebar' } { if ($p -lt $n) { $p++ } }
                { $_ -in 'LeftArrow', 'UpArrow', 'PageUp', 'Backspace' } { if ($p -gt 1) { $p-- } }
                'Home' { $p = 1 }
                'End' { $p = $n }
                { $_ -eq 'Escape' -or $k.KeyChar -eq 'q' } { return }
            }
        }
    } finally { [Console]::Write("$e[0m$e[?25h$e[?1049l") }
}

# (corre a partir da home: numa pasta de rede, o mmdc.cmd/cmd e outros partiam; o caminho do ficheiro ja esta resolvido)
Push-Location $HOME
try {
switch -Regex ([IO.Path]::GetExtension($f).ToLower()) {
    '^\.(md|markdown)$' { Show-Markdown $f }
    '^\.pdf$' { Show-Pdf $f }
    '^\.(png|jpe?g|gif|webp|bmp)$' { Add-Type -AssemblyName System.Drawing; Show-Image $f ([Math]::Min(100, $W - 4)) ($H - 4) }
    default { & bat --paging=never --style=numbers,header $f }
}
} finally { Pop-Location }
