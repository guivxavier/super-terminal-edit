# SuperTerminal in one line, on a clean Windows (nothing needed beforehand, not even git):
#   irm https://raw.githubusercontent.com/guivxavier/super-terminal-edit/main/get.ps1 | iex
# Downloads this repo as a zip, unpacks it in %TEMP% and runs install.ps1 from there (which installs git and the rest;
# "super upgrade" later keeps its own copy of the repo). ASCII only: it runs on Windows PowerShell 5.1.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$tmp = Join-Path $env:TEMP "superterminal-get-$(Get-Random)"
New-Item -ItemType Directory $tmp | Out-Null
try {
    Write-Host '  downloading SuperTerminal...' -ForegroundColor DarkGray
    Invoke-WebRequest 'https://github.com/guivxavier/super-terminal-edit/archive/refs/heads/main.zip' -OutFile "$tmp\st.zip" -UseBasicParsing
    Expand-Archive "$tmp\st.zip" $tmp -Force
    $repo = Get-ChildItem $tmp -Directory | Select-Object -First 1
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo.FullName 'install.ps1')
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
