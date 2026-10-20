# monitor: CPU, GPU, RAM, temperatura e processos deste PC e dos teus outros PCs, lado a lado.
# Cada PC corre o st-monitor-sample.ps1 (os outros por ssh, ver setup > Tailscale) e manda uma linha JSON a cada 2 s.
$e = [char]27
. "$HOME\.config\st-theme.ps1"
$Pcs = @(if (Test-Path "$HOME\.config\superterminal\pcs.json") { try { Get-Content "$HOME\.config\superterminal\pcs.json" -Raw | ConvertFrom-Json } catch {} })
$me = $env:COMPUTERNAME.ToLower()
$meName = @($Pcs | Where-Object { "$($_.host)".ToLower() -eq $me } | ForEach-Object name)[0]; if (-not $meName) { $meName = $me }
$Ssh = "$env:WINDIR\System32\OpenSSH\ssh.exe"

function Start-Src([string]$name, [string]$exe, [string[]]$argv, [bool]$self) {
    $si = [Diagnostics.ProcessStartInfo]::new($exe); foreach ($a in $argv) { $si.ArgumentList.Add($a) }
    $si.UseShellExecute = $false; $si.RedirectStandardOutput = $si.RedirectStandardError = $si.RedirectStandardInput = $true; $si.CreateNoWindow = $true
    $s = @{ name = $name; self = $self; d = $null; hist = [Collections.Generic.List[double]]::new(); ghist = [Collections.Generic.List[double]]::new(); err = $null; t0 = Get-Date }
    try { $s.p = [Diagnostics.Process]::Start($si); $s.out = $s.p.StandardOutput.ReadLineAsync(); $s.eout = $s.p.StandardError.ReadToEndAsync() } catch { $s.err = "$_" }
    $s
}
$Srcs = [Collections.Generic.List[object]]::new()
$Srcs.Add((Start-Src $meName "$PSHOME\pwsh.exe" @('-NoProfile', '-File', "$HOME\.config\st-monitor-sample.ps1") $true))
foreach ($p in $Pcs) {
    if ("$($p.host)".ToLower() -eq $me -or $p.name -eq $meName) { continue }
    $Srcs.Add((Start-Src $p.name $Ssh @('-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5', $p.name, 'pwsh -NoProfile -File .config/st-monitor-sample.ps1') $false))
}

function Fmt-Bytes([double]$b) { if ($b -ge 1GB) { '{0:0.0} GB' -f ($b / 1GB) } else { '{0:0} MB' -f ($b / 1MB) } }
function Level([double]$v) { if ($v -ge 85) { '31' } elseif ($v -ge 60) { '33' } else { '32' } }
function Bar([double]$v, [int]$w) {
    # barra com oitavos (mais precisa); a parte vazia num tom do tema
    $v = [Math]::Max(0, [Math]::Min(100, $v)); $full = [Math]::Floor($v / 100 * $w); $rest = [int][Math]::Floor(($v / 100 * $w - $full) * 8)
    $s = "$e[$(Level $v)m" + ([string][char]0x2588) * $full
    if ($full -lt $w) { $s += $(if ($rest) { [string][char](0x2590 - $rest) } else { '' }) }
    $used = $full + $(if ($rest -and $full -lt $w) { 1 } else { 0 })
    "$s$e[38;2;$($StTheme.sel)m$(([string][char]0x2588) * ($w - $used))$e[0m"
}
function Spark($h, [int]$w) {
    $bl = ' ▁▂▃▄▅▆▇█'; $vals = @($h | Select-Object -Last $w)
    "$e[38;2;$($StTheme.comment)m" + (' ' * ($w - $vals.Count)) + (-join ($vals | ForEach-Object { $bl[[int][Math]::Round([Math]::Min(100, $_) / 100 * 8)] })) + "$e[0m"
}
function Fit([string]$s, [int]$w) { if ($s.Length -gt $w) { $s.Substring(0, [Math]::Max(0, $w - 1)) + '…' } else { $s.PadRight($w) } }

function Draw-Col($s, [int]$w) {
    $L = [Collections.Generic.List[string]]::new()
    $icon = if ($s.name -match 'lap|book|note') { [char]0xf109 } else { [char]0xf108 }
    $d = $s.d
    $tag = if ($s.self) { "$e[90m · this PC" } else { '' }
    $up = if ($d) { "$e[90mup $(if ($d.up -ge 48) { "$([int]($d.up / 24))d" } else { "$($d.up)h" })" } else { '' }
    $L.Add("$e[1;$Accent`m$icon  $e[1;97m$($s.name)$e[0m$tag$e[0m"); $L.Add($up)
    if (-not $d) {
        $L.Add('')
        if ($s.err) { $L.Add("$e[33m$([char]0xf071)  $(Fit $s.err ($w - 4))$e[0m") }
        else { $L.Add("$e[90m$([char]0x2026) connecting ($([int]((Get-Date) - $s.t0).TotalSeconds) s)$e[0m") }
        return $L
    }
    $bw = [Math]::Max(8, [Math]::Min(40, $w - 22))
    $L.Add("$e[90m$(Fit "$($d.cpuName)" $w)$e[0m")
    $L.Add('')
    $L.Add("$e[37mCPU   $(Bar $d.cpu $bw) $e[1;97m$(("{0,3}%" -f [int]$d.cpu))$e[0m")
    $L.Add("      $(Spark $s.hist $bw)")
    if ($null -ne $d.gpu) {
        $L.Add("$e[37mGPU   $(Bar $d.gpu $bw) $e[1;97m$(("{0,3}%" -f [int]$d.gpu))$e[0m")
        $L.Add("      $(Spark $s.ghist $bw)")
    }
    $rp = if ($d.ramTotal) { 100 * $d.ramUsed / $d.ramTotal } else { 0 }
    $L.Add("$e[37mRAM   $(Bar $rp $bw) $e[1;97m$(("{0,3}%" -f [int]$rp))$e[0m")
    $L.Add("      $e[90m$(Fmt-Bytes $d.ramUsed) of $(Fmt-Bytes $d.ramTotal)$e[0m")
    if ($null -ne $d.temp) { $tc = if ($d.temp -ge 85) { '31' } elseif ($d.temp -ge 70) { '33' } else { '32' }; $L.Add("$e[37mTEMP  $e[1;${tc}m$([int]$d.temp)°C$e[0m") }
    if ($d.gpuName) { $L.Add("$e[90m$(Fit "GPU  $($d.gpuName)" $w)$e[0m") }
    $L.Add('')
    $nw = [Math]::Max(8, $w - 20)
    $L.Add("$e[90m$(Fit 'process' $nw)   cpu      mem$e[0m")
    foreach ($p in @($d.procs)) { $L.Add("$e[37m$(Fit $p.n $nw)$e[0m $e[$(Level ($p.c * 2))m$(("{0,5:0.0}%" -f $p.c))$e[0m $e[90m$(("{0,8}" -f (Fmt-Bytes $p.m)))$e[0m") }
    $L
}

$Accent = "38;2;$($StTheme.blue)"
[Console]::Write("$e[?1049h$e[?25l")
try {
    $dirty = $true; $lastW = 0; $lastH = 0; $tick = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        foreach ($s in $Srcs) {
            if (-not $s.p) { continue }
            while ($s.out -and $s.out.IsCompleted) {
                $line = $s.out.Result
                if ($null -eq $line) { $s.out = $null; break }   # o processo acabou
                try {
                    $s.d = $line | ConvertFrom-Json; $s.err = $null
                    $s.hist.Add([double]$s.d.cpu); if ($null -ne $s.d.gpu) { $s.ghist.Add([double]$s.d.gpu) }
                    if ($s.hist.Count -gt 200) { $s.hist.RemoveAt(0) }; if ($s.ghist.Count -gt 200) { $s.ghist.RemoveAt(0) }
                } catch {}
                $dirty = $true; $s.out = $s.p.StandardOutput.ReadLineAsync()
            }
            if (-not $s.out -and -not $s.err -and $s.p.HasExited) {
                $m = "$($s.eout.Result)".Trim()
                $s.err = if ($m -match 'not recognized|cannot find|does not exist|No such file') { 'not updated there yet: run super sync' }
                elseif ($m -match 'timed out|Could not resolve|unreachable|refused') { 'offline (wake it with: wake ' + $s.name + ')' }
                elseif ($m -match 'Permission denied') { 'ssh asks for a password: setup > Tailscale > copy my key' }
                elseif ($m) { @($m -split "`n")[-1].Trim() } else { 'stopped' }
                $s.d = $null; $dirty = $true
            }
        }
        $W = [Console]::WindowWidth; $H = [Console]::WindowHeight
        if ($W -ne $lastW -or $H -ne $lastH) { $dirty = $true; $lastW = $W; $lastH = $H }
        if ($tick.ElapsedMilliseconds -ge 1000) { $tick.Restart(); if (@($Srcs | Where-Object { -not $_.d -and -not $_.err })) { $dirty = $true } }
        if ($dirty) {
            $dirty = $false
            $n = $Srcs.Count; $gap = 4; $cw = [Math]::Max(30, [Math]::Floor(($W - 4 - $gap * ($n - 1)) / $n))
            $cols = @($Srcs | ForEach-Object { , @(Draw-Col $_ $cw) })
            $o = "$e[?2026h$e[2J$e[H`n"
            $rows = ($cols | ForEach-Object { $_.Count } | Measure-Object -Maximum).Maximum
            for ($r = 0; $r -lt [Math]::Min($rows, $H - 3); $r++) {
                for ($c = 0; $c -lt $n; $c++) {
                    $x = 3 + $c * ($cw + $gap)
                    if ($r -lt $cols[$c].Count) { $o += "$e[$($r + 2);${x}H$($cols[$c][$r])$e[0m" }
                }
            }
            $o += "$e[$H;3H$e[48;2;$($StTheme.sel);97m q $e[0m $e[37mquit$e[0m   $e[90mevery 2 s$e[0m$e[?2026l"
            [Console]::Write($o)
        }
        if ([Console]::KeyAvailable) { $k = [Console]::ReadKey($true); if ($k.Key -eq 'Escape' -or $k.KeyChar -eq 'q') { break } }
        Start-Sleep -Milliseconds 100
    }
} finally {
    foreach ($s in $Srcs) { if ($s.p -and -not $s.p.HasExited) { try { $s.p.Kill() } catch {} } }
    [Console]::Write("$e[0m$e[?25h$e[?1049l")
}
