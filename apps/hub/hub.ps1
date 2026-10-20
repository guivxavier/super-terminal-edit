# Hub do SuperTerminal: pagina web com os teus PCs (estado, CPU, GPU, RAM, temperatura, processos) e a tailnet.
# Ouve SO no IP Tailscale deste PC (fora da tailnet nao existe). Os dados vem do st-monitor-sample.ps1 de cada PC
# (este PC direto, os outros por ssh), os mesmos do comando monitor.
#   pwsh -File st-hub.ps1 [-Port 80]
param([int]$Port = 80)
$ErrorActionPreference = 'Continue'
$Ts = @((Get-Command tailscale -ErrorAction Ignore).Source, "$env:ProgramFiles\Tailscale\tailscale.exe" | Where-Object { $_ -and (Test-Path $_) })[0]
$Ssh = "$env:WINDIR\System32\OpenSSH\ssh.exe"
$Page = [IO.File]::ReadAllBytes("$PSScriptRoot\st-hub.html")
$Log = "$env:LOCALAPPDATA\superterminal-hub.log"
function L($m) { try { [IO.File]::AppendAllText($Log, "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m`n") } catch {} }

# ---- fontes: um amostrador por PC (linha JSON a cada 2 s); reiniciadas se morrerem ----
function Start-Src($s) {
    $si = [Diagnostics.ProcessStartInfo]::new($s.exe); foreach ($a in $s.argv) { $si.ArgumentList.Add($a) }
    $si.UseShellExecute = $false; $si.RedirectStandardOutput = $si.RedirectStandardError = $si.RedirectStandardInput = $true; $si.CreateNoWindow = $true
    try { $s.p = [Diagnostics.Process]::Start($si); $s.out = $s.p.StandardOutput.ReadLineAsync(); $s.eout = $s.p.StandardError.ReadToEndAsync(); $s.started = Get-Date } catch { $s.err = "$_"; $s.p = $null }
}
function Get-Pcs { $f = "$HOME\.config\superterminal\pcs.json"; @(if (Test-Path $f) { try { Get-Content $f -Raw | ConvertFrom-Json } catch {} }) }
$me = $env:COMPUTERNAME.ToLower()
$Srcs = [ordered]@{}
foreach ($p in Get-Pcs) {
    $self = "$($p.host)".ToLower() -eq $me
    $Srcs[$p.name] = @{ name = $p.name; self = $self; d = $null; err = $null; seen = $null; hist = [Collections.Generic.List[double]]::new()
        exe = $(if ($self) { "$PSHOME\pwsh.exe" } else { $Ssh })
        argv = $(if ($self) { @('-NoProfile', '-File', "$PSScriptRoot\st-monitor-sample.ps1") } else { @('-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5', '-o', 'ServerAliveInterval=10', $p.name, 'pwsh -NoProfile -File .config/st-monitor-sample.ps1') }) }
}
if (-not @($Srcs.Values | Where-Object self)) { $Srcs[$me] = @{ name = $me; self = $true; d = $null; err = $null; seen = $null; hist = [Collections.Generic.List[double]]::new(); exe = "$PSHOME\pwsh.exe"; argv = @('-NoProfile', '-File', "$PSScriptRoot\st-monitor-sample.ps1") } }
foreach ($s in $Srcs.Values) { Start-Src $s }

function Update-Srcs {
    foreach ($s in $Srcs.Values) {
        if (-not $s.p) { if (-not $s.started -or ((Get-Date) - $s.started).TotalSeconds -gt 30) { Start-Src $s }; continue }
        while ($s.out -and $s.out.IsCompleted) {
            $line = $s.out.Result; if ($null -eq $line) { $s.out = $null; break }
            try { $s.d = $line | ConvertFrom-Json; $s.err = $null; $s.seen = Get-Date; $s.hist.Add([double]$s.d.cpu); if ($s.hist.Count -gt 60) { $s.hist.RemoveAt(0) } } catch {}
            $s.out = $s.p.StandardOutput.ReadLineAsync()
        }
        if (-not $s.out -and $s.p.HasExited) {
            $m = "$($s.eout.Result)".Trim()
            $s.err = if ($m -match 'not recognized|cannot find|does not exist|No such file') { 'not updated there yet (super sync)' } elseif ($m -match 'timed out|resolve|unreachable|refused|closed') { 'offline' } elseif ($m -match 'Permission denied') { 'ssh key not copied (setup > Tailscale)' } elseif ($m) { @($m -split "`n")[-1].Trim() } else { 'stopped' }
            $s.d = $null; $s.p = $null   # (volta a tentar daqui a 30 s)
        }
    }
}
$script:Tail = $null; $script:TailT = [datetime]::MinValue
function Get-Tailnet {
    if (((Get-Date) - $script:TailT).TotalSeconds -lt 10) { return $script:Tail }
    $script:TailT = Get-Date
    $script:Tail = try {
        $j = & $Ts status --json 2>$null | ConvertFrom-Json
        $ns = @(@($j.Self) + @($j.Peer.PSObject.Properties.Value) | Where-Object { $_.HostName -and $_.TailscaleIPs })
        # nomes como no cabecalho: o do pcs.json; o WSL de um PC (mesmo nome, ou "<pc>-1" no Headscale) = "<nome>-wsl"
        $pcs = @(Get-Pcs); $hosts = @($pcs | ForEach-Object { "$($_.host)".ToLower() })
        $dup = @($ns | Group-Object { "$($_.HostName)".ToLower() -replace '-\d+$' } | Where-Object Count -gt 1 | ForEach-Object Name)
        $label = { param($n) $h = "$($n.HostName)".ToLower(); $wsl = $n.OS -eq 'linux' -and ($h -replace '-\d+$') -in $dup; if ($wsl) { $h = $h -replace '-\d+$' }
            $i = [array]::IndexOf($hosts, $h); $l = if ($i -ge 0) { $pcs[$i].name } else { $n.HostName }; if ($wsl) { "$l-wsl" } else { $l } }
        @{ name = $j.CurrentTailnet.Name; nodes = @($ns | ForEach-Object {
                    @{ host = (& $label $_); os = $_.OS; online = [bool]($_.Online -or $_.ID -eq $j.Self.ID); ip = @($_.TailscaleIPs | Where-Object { $_ -notlike '*:*' })[0]; self = $_.ID -eq $j.Self.ID; seen = "$($_.LastSeen)" } }) }
    } catch { $null }
    $script:Tail
}
function Get-State {
    $theme = try { Get-Content "$HOME\.config\superterminal\theme.json" -Raw | ConvertFrom-Json } catch { $null }
    @{ time = (Get-Date -Format s); tailnet = (Get-Tailnet); theme = $theme
        pcs = @($Srcs.Values | ForEach-Object { @{ name = $_.name; self = $_.self; err = $_.err; d = $_.d; hist = @($_.hist); stale = [bool]($_.seen -and ((Get-Date) - $_.seen).TotalSeconds -gt 10) } }) } | ConvertTo-Json -Depth 6 -Compress
}

# ---- HTTP minimo (so GET; TcpListener: nao precisa de urlacl nem de admin) ----
function Send($c, [int]$code, [string]$type, [byte[]]$body) {
    $h = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 $code $(if ($code -eq 200) { 'OK' } else { 'Not Found' })`r`nContent-Type: $type`r`nContent-Length: $($body.Length)`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nConnection: close`r`n`r`n")
    $st = $c.GetStream(); $st.Write($h, 0, $h.Length); $st.Write($body, 0, $body.Length); $st.Flush()
}
function Handle($c) {
    try {
        $c.ReceiveTimeout = 3000; $st = $c.GetStream(); $buf = [byte[]]::new(8192); $n = $st.Read($buf, 0, $buf.Length)
        $req = [Text.Encoding]::ASCII.GetString($buf, 0, $n); $path = ($req -split ' ')[1]
        switch -Regex ($path) {
            '^/(\?.*)?$' { Send $c 200 'text/html; charset=utf-8' $Page }
            '^/api/state' { Send $c 200 'application/json; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes((Get-State))) }
            default { Send $c 404 'text/plain' ([Text.Encoding]::ASCII.GetBytes('not found')) }
        }
    } catch { L "request: $_" } finally { $c.Close() }
}

# so no IP Tailscale (espera que o Tailscale arranque, ex. no inicio da sessao)
$ip = $null
while (-not $ip) { $ip = "$(& $Ts ip -4 2>$null)".Trim(); if (-not $ip) { Start-Sleep 5 } }
$lst = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse($ip), $Port)
try { $lst.Start() } catch { L "cannot listen on ${ip}:$Port ($_)"; throw }
L "hub on http://${ip}:$Port"; Write-Host "hub on http://${ip}:$Port"
$acc = $lst.AcceptTcpClientAsync()
while ($true) {
    Update-Srcs
    if ($acc.Wait(200)) { Handle $acc.Result; $acc = $lst.AcceptTcpClientAsync() }
}
