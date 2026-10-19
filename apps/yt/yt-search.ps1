# Pesquisa do yt sem o yt-dlp: pede os resultados diretamente a API interna do YouTube (youtubei/v1/search, a mesma
# do site). ~1 s em vez de ~4,5 s (o yt-dlp gasta o resto a arrancar o Python e a carregar extratores).
# Escreve no formato do yt-dlp com o $Fmt do yt-tui (id|titulo|canal|duracao|views|canal_id|timestamp) e guarda o
# token da pagina seguinte em <Out>.next (o "carregar mais" continua dai com -Token).
# ponytail: depende da estrutura JSON do YouTube; se mudar, o yt-tui volta ao yt-dlp (ficheiro vazio -> erro em .err)
# -Related <id>: os videos relacionados desse video (youtubei/v1/next, a barra lateral do site), em vez de uma pesquisa
param([string]$Query, [Parameter(Mandatory)][string]$Out, [string]$Sep = '|~|', [int]$Count = 40, [string]$Token, [string]$Related)
$ErrorActionPreference = 'Stop'
$ctx = @{ client = @{ clientName = 'WEB'; clientVersion = '2.20250101.00.00'; hl = 'en'; gl = 'PT' } }
$tmp = "$Out.req"
function Invoke-Yt($body, [string]$api = 'search') {
    [IO.File]::WriteAllText($tmp, ($body | ConvertTo-Json -Depth 6 -Compress))
    $r = curl.exe -s --fail --compressed --max-time 12 -H 'Content-Type: application/json' --data-binary "@$tmp" "https://www.youtube.com/youtubei/v1/${api}?prettyPrint=false"
    if ($LASTEXITCODE) { throw "YouTube $api request failed (curl $LASTEXITCODE)" }
    ($r -join "`n") | ConvertFrom-Json -Depth 64
}
function Get-Num([string]$t) {
    # "1,234 views" / "207M" / "2.5B" -> numero (como o view_count do yt-dlp)
    if ($t -match '([\d.,]+)\s*([KMB])\b') { $m = @{ K = 1e3; M = 1e6; B = 1e9 }[$Matches[2].ToUpper()]; return [string][long]([double]($Matches[1] -replace ',', '') * $m) }
    if ($t -match '\d') { return $t -replace '\D', '' }
    'NA'
}
function Get-Ago([string]$t) {
    # "3 weeks ago" / "Streamed 2 days ago" / "16y ago" / "2mo ago" -> unix timestamp aproximado (como o approximate_date do yt-dlp)
    if ($t -match '(\d+)\s*(mo|y|w|d|h|min|m|s)\b(?!\w)') { $t = "$($Matches[1]) " + @{ mo = 'month'; y = 'year'; w = 'week'; d = 'day'; h = 'hour'; min = 'minute'; m = 'minute'; s = 'second' }[$Matches[2]] }
    if ($t -notmatch '(\d+)\s+(second|minute|hour|day|week|month|year)') { return 'NA' }
    $n = [int]$Matches[1]; $d = Get-Date
    $d = switch ($Matches[2]) { 'second' { $d.AddSeconds(-$n) } 'minute' { $d.AddMinutes(-$n) } 'hour' { $d.AddHours(-$n) } 'day' { $d.AddDays(-$n) } 'week' { $d.AddDays(-7 * $n) } 'month' { $d.AddMonths(-$n) } 'year' { $d.AddYears(-$n) } }
    [string][DateTimeOffset]::new($d).ToUnixTimeSeconds()
}
$lines = [Collections.Generic.List[string]]::new(); $next = $Token
try {
    while ($Related -and $lines.Count -lt $Count) {
        # relacionados: cartoes "lockupViewModel" (so os de video; playlists / mixes ficam de fora)
        $j = if ($next) { Invoke-Yt @{ context = $ctx; continuation = $next } 'next' } else { Invoke-Yt @{ context = $ctx; videoId = $Related } 'next' }
        $items = if ($next) { @($j.onResponseReceivedEndpoints | ForEach-Object { $_.appendContinuationItemsAction.continuationItems }) } else { $j.contents.twoColumnWatchNextResults.secondaryResults.secondaryResults.results }
        $next = $null
        foreach ($it in $items) {
            if ($it.continuationItemRenderer) { $next = $it.continuationItemRenderer.continuationEndpoint.continuationCommand.token; continue }
            $lv = $it.lockupViewModel
            if (-not $lv -or $lv.contentType -ne 'LOCKUP_CONTENT_TYPE_VIDEO' -or -not $lv.contentId) { continue }
            $md = $lv.metadata.lockupMetadataViewModel
            $rows = @($md.metadata.contentMetadataViewModel.metadataRows | ForEach-Object { , @($_.metadataParts | ForEach-Object { "$($_.text.content)" }) })
            $title = "$($md.title.content)" -replace [regex]::Escape($Sep), ' '
            $chan = if ($rows.Count) { $rows[0][0] } else { '' }
            $vw = if ($rows.Count -gt 1) { $rows[1][0] } else { '' }; $age = if ($rows.Count -gt 1) { $rows[1][-1] } else { '' }
            $ov = $lv.contentImage.thumbnailViewModel.overlays | ConvertTo-Json -Depth 20 -Compress
            $dur = [regex]::Match("$ov", '"text":"(\d+(?::\d+)+)"').Groups[1].Value; if (-not $dur) { $dur = 'NA' }
            $cid = [regex]::Match(($md | ConvertTo-Json -Depth 30 -Compress), '"browseId":"(UC[\w-]{22})"').Groups[1].Value
            $lines.Add(($lv.contentId, $title, $chan, $dur, (Get-Num $vw), $cid, (Get-Ago $age)) -join $Sep)
        }
        if (-not $next) { break }
    }
    while (-not $Related -and $lines.Count -lt $Count) {
        $j = if ($next) { Invoke-Yt @{ context = $ctx; continuation = $next } } else { Invoke-Yt @{ context = $ctx; query = $Query; params = 'EgIQAQ==' } }   # EgIQAQ== = so videos
        $items = if ($next) { $j.onResponseReceivedCommands.appendContinuationItemsAction.continuationItems } else { $j.contents.twoColumnSearchResultsRenderer.primaryContents.sectionListRenderer.contents }
        $next = $null
        foreach ($it in $items) {
            if ($it.continuationItemRenderer) { $next = $it.continuationItemRenderer.continuationEndpoint.continuationCommand.token; continue }
            foreach ($v in $it.itemSectionRenderer.contents.videoRenderer) {
                if (-not $v.videoId) { continue }
                $title = ($v.title.runs.text -join '') -replace [regex]::Escape($Sep), ' '
                $own = $v.ownerText.runs | Select-Object -First 1
                $dur = if ($v.lengthText.simpleText) { $v.lengthText.simpleText } else { 'NA' }   # sem duracao = direto
                $vt = if ($v.viewCountText.simpleText) { $v.viewCountText.simpleText } else { $v.viewCountText.runs.text -join '' }
                $views = if ($vt -match '\d') { $vt -replace '\D', '' } else { 'NA' }
                $lines.Add(($v.videoId, $title, $own.text, $dur, $views, $own.navigationEndpoint.browseEndpoint.browseId, (Get-Ago $v.publishedTimeText.simpleText)) -join $Sep)
            }
        }
        if (-not $next) { break }
    }
    [IO.File]::WriteAllLines($Out, $lines, [Text.UTF8Encoding]::new($false))
    if ($next) { [IO.File]::WriteAllText("$Out.next", $next) }
} catch {
    [IO.File]::WriteAllText("$Out.err", "ERROR: $($_.Exception.Message)")
    if (-not (Test-Path $Out)) { [IO.File]::WriteAllText($Out, '') }
} finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
