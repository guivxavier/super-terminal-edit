# Cabecalho do SuperTerminal no WezTerm (o painel de cima de cada separador). Corre com o perfil carregado (KVN_CMD=1):
# desenha o fastfetch + comandos (ff -Bar), diz ao WezTerm quantas linhas precisa (user var "rows") e redesenha
# ao mudar de tamanho e a cada 2 s (ao vivo). E so para ver: as teclas sao ignoradas (o WezTerm tira-lhe o foco).
$e = [char]27
# corre com -NoProfile (vale tambem lancado pelo "pin" via wezterm cli): carrega o perfil em modo so-comandos
if (-not (Get-Command ff -ErrorAction Ignore)) { $env:KVN_CMD = '1'; $env:KVN_COMPACT = ''; . $PROFILE.CurrentUserCurrentHost }
function Set-UserVar($n, $v) { [Console]::Write("$e]1337;SetUserVar=$n=$([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$v")))$([char]7)") }
Set-UserVar role header
[Console]::Write("$e]2;superterminal-header$([char]7)")   # (titulo: o "pin" encontra este painel pelo wezterm cli list)
[Console]::TreatControlCAsInput = $true
$n = 0; $W = 0; $H = 0; $tick = [Diagnostics.Stopwatch]::StartNew()
# (SUPERTERMINAL_HDRLOG=1: registo de cada redesenho e erro em %TEMP%\superterminal-header.log)
function HLog($m) { if ($env:SUPERTERMINAL_HDRLOG) { [IO.File]::AppendAllText("$env:TEMP\superterminal-header.log", "$(Get-Date -Format HH:mm:ss.fff) $PID $m`n") } }
trap { HLog "ERRO: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)"; continue }
$profT = (Get-Item $PROFILE.CurrentUserCurrentHost).LastWriteTime
while ($true) {
    # perfil mudou (sync, edicao): volta a carregar as funcoes e redesenha (senao o cabecalho ficava com o codigo antigo
    # ate se fechar o separador)
    if ($tick.ElapsedMilliseconds -ge 2000 -and ($pt = (Get-Item $PROFILE.CurrentUserCurrentHost -ErrorAction Ignore).LastWriteTime) -and $pt -ne $profT) {
        $profT = $pt; HLog 'perfil mudou: recarregar'; . $PROFILE.CurrentUserCurrentHost; $FfLines = $null; $W = 0
    }
    # pedido de redesenho (um programa ampliado acabou: Invoke-Zoomed no perfil)
    if ([IO.File]::Exists("$env:TEMP\superterminal-header-redraw")) { try { [IO.File]::Delete("$env:TEMP\superterminal-header-redraw") } catch {}; $W = 0; $FfLines = $null }   # (o setup tambem: widgets mudaram a altura)
    if ([Console]::WindowWidth -ne $W -or [Console]::WindowHeight -ne $H) {
        if ($W) { Start-Sleep -Milliseconds 150 }   # (espera que o tamanho estabilize)
        $W = [Console]::WindowWidth; $H = [Console]::WindowHeight
        HLog "redesenho ${W}x$H"
        if (Get-Command Update-Widgets -ErrorAction Ignore) { Update-Widgets }
        ff -Bar; [Console]::Write("$e[?25l")
        HLog "desenhado, cursor na linha $([Console]::CursorTop)"
        # altura pelo conteudo (o fastfetch tem $FfLines linhas, a coluna dos comandos $CheatRows): com o painel mais
        # baixo que o conteudo, o cursor fica preso no fundo e nao serve para medir
        if (-not $FfLines) { Push-Location $HOME; try { $FfLines = @(fastfetch --pipe false 2>$null).Count } finally { Pop-Location } }
        $rows = if ([Console]::WindowWidth -ge 90) { [Math]::Max($FfLines, [int]$global:CheatRows) + 1 } else { 1 }
        $n++; Set-UserVar rows "$($rows):$n"
        $tick.Restart()
    }
    elseif ($tick.ElapsedMilliseconds -ge 2000 -and -not (Test-Path "$env:TEMP\superterminal-header-static")) {   # (ffw desliga)
        # ao vivo: o fastfetch volta a correr e escreve por cima (sem limpar -> nao pisca); ESC[K apaga restos
        Update-TsCache 5; if (Get-Command Update-Widgets -ErrorAction Ignore) { Update-Widgets }
        $enc = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); Push-Location $HOME
        try { $ffo = @(fastfetch --pipe false 2>$null) } finally { Pop-Location; [Console]::OutputEncoding = $enc }
        [Console]::Write("$e[?2026h$e[H" + (($ffo | ForEach-Object { "$_$e[K" }) -join "`n")); Show-Cheats; [Console]::Write("$e[?2026l")
        $tick.Restart()
    }
    while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }
    Start-Sleep -Milliseconds 200
}
