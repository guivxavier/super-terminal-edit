# divide a config do fastfetch deste PC: hardware para config-hw.jsonc (coluna ao lado, desenhada pelo Show-Cheats);
# na principal ficam o logotipo, system e network. Copia de seguranca em config.jsonc.bak-colunas.
$f = "$HOME\.config\fastfetch\config.jsonc"; $hwf = "$HOME\.config\fastfetch\config-hw.jsonc"
$t = [IO.File]::ReadAllText($f)
if (Test-Path $hwf) { 'ja dividido'; return }
Copy-Item $f "$f.bak-colunas" -Force
$lines = $t -split "`r?`n"
$hs = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '"custom".*hardware') { $hs = $i; break } }
if ($hs -lt 0) { 'sem seccao hardware'; return }
$he = -1; for ($i = $hs; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*"break",?\s*$') { $he = $i; break } }
$hw = @($lines[$hs..($he - 1)]); $hw[-1] = $hw[-1] -replace ',\s*$', ''
$main = @($lines[0..($hs - 1)]) + @($lines[($he + 1)..($lines.Count - 1)])
$mainT = ($main -join "`n") -replace '"top":\s*6', '"top": 1'
$hwT = @'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "logo": { "type": "none" },
    "display": { "separator": "  ", "key": { "width": 12 }, "color": { "keys": "90" } },
    "modules": [
'@ + "`n" + ($hw -join "`n") + "`n    ]`n}`n"
$enc = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($f, $mainT, $enc); [IO.File]::WriteAllText($hwf, $hwT, $enc)
"dividido: $($hw.Count) linhas de hardware"
Push-Location $HOME; fastfetch -c $hwf --pipe false | Select-Object -First 3; Pop-Location
