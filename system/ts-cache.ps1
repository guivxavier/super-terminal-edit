# Gera as linhas do Tailscale para o fastfetch (corre escondido em segundo plano; o 'tailscale status' demora ~1 s)
#   ts1.txt = resumo; ts2..ts6.txt = uma linha por dispositivo
# So ASCII: o fastfetch estraga caracteres nao-ASCII vindos de comandos
$dir = "$env:LOCALAPPDATA\pwsh-init-cache"
$ts = 'C:\Program Files\Tailscale\tailscale.exe'
$e = [char]27
$lines = @()
try {
    $j = & $ts status --json 2>$null | ConvertFrom-Json
    if ($j.BackendState -ne 'Running') { $lines += "$e[90mtailscale stopped ($($j.BackendState))" }
    else {
        $nodes = @($j.Self) + @($j.Peer.PSObject.Properties.Value)
        $dup = $nodes | Group-Object HostName | Where-Object Count -gt 1 | ForEach-Object Name
        $on = @($nodes | Where-Object Online).Count
        $lines += "$e[32m$on$e[0m$e[90m/$e[0m$($nodes.Count)  $e[90m$($j.CurrentTailnet.Name)"
        # os PCs com nome (setup > Tailscale: ~\.config\superterminal\pcs.json) primeiro, pela ordem de la, com esse
        # nome; os WSL deles a seguir ("<nome>-wsl"); depois os outros por nome
        $pcs = @(); $pf = "$env:USERPROFILE\.config\superterminal\pcs.json"
        # (no Windows PowerShell 5.1 o ConvertFrom-Json da a lista como um so objeto: o ForEach desfaz)
        if (Test-Path $pf) { try { $pcs = @(Get-Content $pf -Raw | ConvertFrom-Json | ForEach-Object { $_ }) } catch {} }
        $hosts = @($pcs | ForEach-Object { "$($_.host)".ToLower() })
        $order = { $i = [array]::IndexOf($hosts, "$($_.HostName)".ToLower()); if ($i -lt 0) { 99 } elseif ($_.OS -eq 'linux') { 50 + $i } else { $i } }
        foreach ($n in $nodes | Sort-Object $order, HostName) {
            # nome na coluna das etiquetas (ESC[11D recua o cursor ate ao inicio da etiqueta)
            $label = $n.HostName
            $i = [array]::IndexOf($hosts, "$($n.HostName)".ToLower()); if ($i -ge 0) { $label = $pcs[$i].name }
            if ($n.HostName -in $dup -and $n.OS -eq 'linux') { $label = "$label-wsl" }
            $ip = $n.TailscaleIPs | Where-Object { $_ -notlike '*:*' } | Select-Object -First 1
            $self = $n.ID -eq $j.Self.ID
            if ($n.Online -or $self) { $st = 'online'; $sc = '32' } else { $st = 'offline'; $sc = '90' }
            # o PC onde este terminal esta a correr: nome a ciano + "<-"
            $lcol = if ($self) { '1;36' } elseif ($n.Online) { '1;37' } else { '90' }
            $here = if ($self) { "$e[0;36m<-" } else { '' }
            # padding aplicado ao texto sem cor (senao as colunas desalinham)
            $lines += "$e[11D$e[${lcol}m" + "  $label".PadRight(14) + "$e[0;${sc}m" + $st.PadRight(9) + "$e[0;90m" + "$ip".PadRight(16) + "$here$e[0m"
        }
    }
} catch { $lines += "$e[90mtailscale not installed" }
New-Item -ItemType Directory $dir -Force | Out-Null
1..6 | ForEach-Object { Remove-Item "$dir\ts$_.txt" -ErrorAction SilentlyContinue }
for ($i = 0; $i -lt [Math]::Min($lines.Count, 6); $i++) { [IO.File]::WriteAllText("$dir\ts$($i + 1).txt", $lines[$i], [Text.Encoding]::ASCII) }
