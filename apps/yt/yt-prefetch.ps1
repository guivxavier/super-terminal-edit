# Prepara em segundo plano a página inicial do YouTube para o 'yt' abrir logo (lista + thumbnails).
# Chamado escondido pelo perfil do PowerShell quando a cache tem mais de 15 minutos. Só corre com sessão iniciada.
$ck = "$HOME\.config\yt-cookies.txt"
if (-not (Test-Path $ck)) { exit }
$dir = "$env:TEMP\yt"; New-Item -ItemType Directory $dir -Force | Out-Null
Copy-Item $ck "$dir\cookies-prefetch.txt" -Force; $ck = "$dir\cookies-prefetch.txt"   # cópia: o yt-dlp reescreve o ficheiro de cookies
$lock = "$dir\home-cache.lock"
if ((Test-Path $lock) -and ((Get-Date) - (Get-Item $lock).LastWriteTime).TotalMinutes -lt 3) { exit }   # já a correr
Set-Content $lock ''
try {
    $sep = '|~|'
    $fmt = "%(id)s$sep%(title)s$sep%(channel,uploader)s$sep%(duration_string)s$sep%(view_count)s$sep%(channel_id)s$sep%(timestamp)s"
    $yt = @("$env:LOCALAPPDATA\Programs\yt-dlp-dir\yt-dlp.exe", (Get-Command yt-dlp).Source) | Where-Object { Test-Path $_ } | Select-Object -First 1   # onedir: arranca mais depressa
    # saída direta para ficheiro (preserva o UTF-8 dos títulos)
    $p = Start-Process $yt -ArgumentList ':ytrec', '--cookies', $ck, '--flat-playlist', '--playlist-items', '1-45', '--no-warnings', '--encoding', 'utf-8', '--extractor-args', 'youtubetab:approximate_date', '--print', $fmt `
        -RedirectStandardOutput "$dir\home-cache.tmp" -RedirectStandardError "$dir\home-cache.err" -WindowStyle Hidden -PassThru -Wait
    if ($p.ExitCode -ne 0 -or (Get-Item "$dir\home-cache.tmp").Length -eq 0) { exit }
    Move-Item "$dir\home-cache.tmp" "$dir\home-cache.txt" -Force
    $a = @('--parallel', '-sL')
    foreach ($l in Get-Content "$dir\home-cache.txt" -Encoding UTF8) {
        $id = ($l -split [regex]::Escape($sep))[0]
        if ($id.Length -eq 11 -and -not (Test-Path "$dir\$id.jpg")) { $a += "https://i.ytimg.com/vi/$id/mqdefault.jpg", '-o', "$dir\$id.jpg" }
    }
    if ($a.Count -gt 2) { & curl.exe @a 2>$null }
    # imagens sixel da 1.ª página, no tamanho da última vez que o yt abriu (ficam no disco; o yt lê-as logo)
    if (Test-Path "$dir\layout.txt") {
        $tw, $th, $per = (Get-Content "$dir\layout.txt") -split ' '
        $chafa = (Get-Command chafa).Source; New-Item -ItemType Directory "$dir\six" -Force | Out-Null
        foreach ($l in Get-Content "$dir\home-cache.txt" -Encoding UTF8 | Select-Object -First ([int]$per)) {
            $id = ($l -split [regex]::Escape($sep))[0]; $sf = "$dir\six\$id-$tw-$th-s.six"
            if ($id.Length -eq 11 -and -not (Test-Path $sf) -and (Test-Path "$dir\$id.jpg")) {
                $x = ((& $chafa -f sixels --probe off --dither none --stretch --size "${tw}x$th" "$dir\$id.jpg" 2>$null) -join '') -replace "$([char]27)\[\?25[hl]", ''
                if ($x) { [IO.File]::WriteAllText("$sf.$PID.tmp", $x); try { [IO.File]::Move("$sf.$PID.tmp", $sf) } catch { [IO.File]::Delete("$sf.$PID.tmp") } }   # (PowerShell 5.1: Move sem substituir)
            }
        }
    }
}
finally { [IO.File]::Delete($lock) }
