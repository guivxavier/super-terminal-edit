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

# ---- HTTP(S) minimo (so GET; TcpListener: nao precisa de urlacl nem de admin) ----
# Com certificado (hub cert: Let's Encrypt pelo DNS, ~\.config\superterminal\hub-cert\*.pem) serve https na 443 e a
# porta 80 so redireciona; sem ele, http na 80.
$CertDir = "$HOME\.config\superterminal\hub-cert"
$script:Cert = $null; $script:CertT = $null
function Get-Cert {
    $f = "$CertDir\fullchain.pem"; $k = "$CertDir\privkey.pem"
    if (-not (Test-Path $f) -or -not (Test-Path $k)) { return $null }
    $t = (Get-Item $f).LastWriteTime
    if ($t -ne $script:CertT) {   # (renovado: carrega o novo)
        try {
            $c = [Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPemFile($f, $k)
            # (no Windows o SslStream precisa da chave num formato persistido: passa por PFX)
            $script:Cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new($c.Export('Pfx')); $script:CertT = $t
            L "certificate loaded: $($script:Cert.Subject), until $($script:Cert.NotAfter)"
        } catch { L "certificate: $_" }
    }
    $script:Cert
}

# cada ligacao e tratada num thread a parte (um browser abre ligacoes de antemao que nao mandam nada: nao podem
# bloquear as outras); o ciclo principal so aceita e mantem $Sh (pagina, estado em JSON, certificado) atualizado
$Sh = [hashtable]::Synchronized(@{ page = $Page; state = [byte[]]@(); cert = $null; ip = '' })
$Serve = {
    param($c, [bool]$tls, $Sh, [string]$Log)
    function Send($st, [int]$code, [string]$type, [byte[]]$body, [string]$extra = '') {
        $txt = @{ 200 = 'OK'; 301 = 'Moved Permanently'; 404 = 'Not Found' }[$code]
        $sec = if ($Sh.cert) { "Strict-Transport-Security: max-age=31536000`r`n" } else { '' }
        $h = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 $code $txt`r`nContent-Type: $type`r`nContent-Length: $($body.Length)`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`n$sec$extra" + "Connection: close`r`n`r`n")
        $st.Write($h, 0, $h.Length); $st.Write($body, 0, $body.Length); $st.Flush()
    }
    try {
        $c.ReceiveTimeout = 10000; $c.SendTimeout = 10000; $st = $c.GetStream()
        if ($tls) { $ssl = [Net.Security.SslStream]::new($st, $false); $ssl.AuthenticateAsServer($Sh.cert); $st = $ssl }
        $buf = [byte[]]::new(8192); $n = $st.Read($buf, 0, $buf.Length); if ($n -le 0) { return }
        $req = [Text.Encoding]::ASCII.GetString($buf, 0, $n); $path = ($req -split ' ')[1]
        if (-not $tls -and $Sh.cert) {
            # http -> https (com o nome que o browser usou)
            $hostName = [regex]::Match($req, '(?im)^Host:\s*([^\s:]+)').Groups[1].Value; if (-not $hostName) { $hostName = $Sh.ip }
            Send $st 301 'text/plain' ([byte[]]@()) "Location: https://$hostName$path`r`n"; return
        }
        switch -Regex ($path) {
            '^/(\?.*)?$' { Send $st 200 'text/html; charset=utf-8' $Sh.page }
            '^/api/state' { Send $st 200 'application/json; charset=utf-8' $Sh.state }
            default { Send $st 404 'text/plain' ([Text.Encoding]::ASCII.GetBytes('not found')) }
        }
    } catch {
        # (ligacoes abertas de antemao e fechadas sem pedido: normal, nao fica no log)
        $x = $_.Exception; while ($x.InnerException) { $x = $x.InnerException }
        if ($x.Message -notmatch 'EOF or 0 bytes|did not properly respond|forcibly closed|aborted') { try { [IO.File]::AppendAllText($Log, "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') request: $($x.Message)`n") } catch {} }
    } finally { $c.Close() }
}

try {
    # so no IP Tailscale (espera que o Tailscale arranque, ex. no inicio da sessao)
    $ip = $null
    while (-not $ip) { $ip = "$(& $Ts ip -4 2>$null)".Trim(); if (-not $ip) { Start-Sleep 5 } }
    $Sh.ip = $ip; $addr = [Net.IPAddress]::Parse($ip)
    $Sh.cert = Get-Cert
    $ls = @(@{ l = [Net.Sockets.TcpListener]::new($addr, $Port); tls = $false })
    if ($Sh.cert) { $ls += @{ l = [Net.Sockets.TcpListener]::new($addr, 443); tls = $true } }
    foreach ($x in $ls) { $x.l.Start(); $x.acc = $x.l.AcceptTcpClientAsync() }
    $msg = if ($Sh.cert) { "hub on https://${ip} (http redirects)" } else { "hub on http://${ip}:$Port" }
    L $msg; Write-Host $msg
    $tick = [Diagnostics.Stopwatch]::StartNew(); $st1 = [Diagnostics.Stopwatch]::StartNew(); $Sh.state = [Text.Encoding]::UTF8.GetBytes((Get-State))
    while ($true) {
        Update-Srcs
        if ($st1.ElapsedMilliseconds -ge 1000) {
            $st1.Restart(); $Sh.state = [Text.Encoding]::UTF8.GetBytes((Get-State))
            Get-Job -Name hub-req -ErrorAction Ignore | Where-Object State -ne 'Running' | Remove-Job -Force
        }
        # (de hora a hora: certificado renovado? carrega-o; um certificado onde nao havia -> sai, e o ciclo de quem o
        # arrancou (hub on) volta a abri-lo ja com a 443)
        if ($tick.Elapsed.TotalMinutes -ge 60) { $tick.Restart(); $had = [bool]$Sh.cert; $Sh.cert = Get-Cert; if (-not $had -and $Sh.cert) { L 'certificate appeared: restart'; break } }
        $any = $false
        foreach ($x in $ls) {
            if ($x.acc.IsCompleted) {
                $any = $true
                if ($x.acc.IsFaulted) { L "accept: $($x.acc.Exception.InnerException.Message)" } else { $null = Start-ThreadJob -Name hub-req -ThrottleLimit 32 -ScriptBlock $Serve -ArgumentList $x.acc.Result, $x.tls, $Sh, $Log }
                $x.acc = $x.l.AcceptTcpClientAsync()
            }
        }
        if (-not $any) { Start-Sleep -Milliseconds 50 }
    }
} catch { L "fatal: $($_.Exception.Message) @ L$($_.InvocationInfo.ScriptLineNumber)"; throw }
finally { foreach ($x in $ls) { try { $x.l.Stop() } catch {} }; foreach ($s in $Srcs.Values) { if ($s.p -and -not $s.p.HasExited) { try { $s.p.Kill() } catch {} } } }
