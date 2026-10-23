# Verificacoes rapidas de todo o repo (o CI corre isto; a mao: pwsh -File tests\run.ps1). Falha (exit 1) se alguma falhar.
#   1. todos os .ps1 sem erros de sintaxe nem "else" soltos (o que o chk.ps1 ve num ficheiro)
#   2. install.ps1 e get.ps1 so em ASCII: correm no Windows PowerShell 5.1 de um PC novo, que le acentos mal
#   3. PSScriptAnalyzer, so os erros (se estiver instalado: Install-Module PSScriptAnalyzer)
$ErrorActionPreference = 'Stop'
$Repo = Split-Path $PSScriptRoot -Parent
$fail = 0
function Fail([string]$m) { Write-Host "  x $m" -ForegroundColor Red; $script:fail++ }

$files = @(Get-ChildItem $Repo -Recurse -Filter *.ps1 -File | Where-Object { $_.FullName -notmatch '\\(\.git|\.claude-flow|node_modules)\\' })
foreach ($f in $files) {
    $tk = $null; $er = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tk, [ref]$er)
    $rel = $f.FullName.Substring($Repo.Length + 1)
    foreach ($x in $er) { Fail "${rel}:$($x.Extent.StartLineNumber) $($x.Message)" }
    foreach ($x in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in 'else', 'elseif' }, $true)) { Fail "${rel}:$($x.Extent.StartLineNumber) else / elseif solto (a chaveta de antes fecha o if)" }
}
Write-Host "  syntax: $($files.Count) files"

foreach ($n in 'install.ps1', 'get.ps1') {
    $b = [IO.File]::ReadAllBytes((Join-Path $Repo $n)); $i = [Array]::FindIndex($b, [Predicate[byte]] { param($c) $c -gt 127 })
    if ($i -ge 0) { Fail "$n is not ASCII (line $(([Text.Encoding]::UTF8.GetString($b, 0, $i) -split "`n").Count))" }
}
Write-Host '  ascii: install.ps1, get.ps1'

if (Get-Module -ListAvailable PSScriptAnalyzer) {
    $r = @($files | ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Severity Error })
    foreach ($x in $r) { Fail "$($x.ScriptName):$($x.Line) $($x.RuleName): $($x.Message)" }
    Write-Host "  PSScriptAnalyzer: $($r.Count) errors"
} else { Write-Host '  PSScriptAnalyzer: not installed, skipped' -ForegroundColor DarkGray }

if ($fail) { Write-Host "  $fail problems" -ForegroundColor Red; exit 1 }
Write-Host '  all good' -ForegroundColor Green
