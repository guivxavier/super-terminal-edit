# Pesquisa do yt sem o yt-dlp: pede os resultados diretamente a API interna do YouTube (youtubei/v1/search, a mesma
# do site). ~1 s em vez de ~4,5 s (o yt-dlp gasta o resto a arrancar o Python e a carregar extratores).
# Escreve no formato do yt-dlp com o $Fmt do yt-tui (id|titulo|canal|duracao|views|canal_id|timestamp) e guarda o
# token da pagina seguinte em <Out>.next (o "carregar mais" continua dai com -Token).
# ponytail: depende da estrutura JSON do YouTube; se mudar, o yt-tui volta ao yt-dlp (ficheiro vazio -> erro em .err)
param([Parameter(Mandatory)][string]$Query, [Parameter(Mandatory)][string]$Out, [string]$Sep = '|~|', [int]$Count = 40, [string]$Token)
$ErrorActionPreference = 'Stop'
$ctx = @{ client = @{ clientName = 'WEB'; clientVersion = '2.20250101.00.00'; hl = 'en'; gl = 'PT' } }
$tmp = "$Out.req"
function Invoke-Yt($body) {
    [IO.File]::WriteAllText($tmp, ($body | ConvertTo-Json -Depth 6 -Compress))
    $r = curl.exe -s --fail --compressed --max-time 12 -H 'Content-Type: application/json' --data-binary "@$tmp" 'https://www.youtube.com/youtubei/v1/search?prettyPrint=false'
    if ($LASTEXITCODE) { throw "YouTube search request failed (curl $LASTEXITCODE)" }
    ($r -join "`n") | ConvertFrom-Json -Depth 64
}
function Get-Ago([string]$t) {
    # "3 weeks ago" / "Streamed 2 days ago" -> unix timestamp aproximado (como o approximate_date do yt-dlp)
    if ($t -notmatch '(\d+)\s+(second|minute|hour|day|week|month|year)') { return 'NA' }
    $n = [int]$Matches[1]; $d = Get-Date
    $d = switch ($Matches[2]) { 'second' { $d.AddSeconds(-$n) } 'minute' { $d.AddMinutes(-$n) } 'hour' { $d.AddHours(-$n) } 'day' { $d.AddDays(-$n) } 'week' { $d.AddDays(-7 * $n) } 'month' { $d.AddMonths(-$n) } 'year' { $d.AddYears(-$n) } }
    [string][DateTimeOffset]::new($d).ToUnixTimeSeconds()
}
$lines = [Collections.Generic.List[string]]::new(); $next = $Token
try {
    while ($lines.Count -lt $Count) {
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
