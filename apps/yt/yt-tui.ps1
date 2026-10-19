# yt-tui: YouTube no terminal — grelha de thumbnails reais (sixel via chafa), vídeo por cima do terminal (mpv)
#   yt                 -> login (se preciso) e a página inicial; separadores início / subscrições / ver mais tarde / histórico
#   yt <pesquisa>      -> pesquisa        yt -c <canal> -> canal        yt -a <pesquisa> -> só áudio        ? -> atalhos
# Rapidez: as listas dos separadores carregam em paralelo (processos do yt-dlp) logo ao abrir, e as thumbnails
# e imagens sixel são preparadas em segundo plano (thread jobs).
param([Parameter(ValueFromRemainingArguments = $true)] [string[]]$Rest)

$e = [char]27
# ecra de arranque, logo a abrir (o resto demora ~1 s: DLL, lista, primeira grelha): logotipo e cartoes-esqueleto no
# sitio da grelha, como o YouTube faz enquanto carrega
& {
    $W = [Console]::WindowWidth; $H = [Console]::WindowHeight; $o = "$e[?1049h$e[?25l$e[2J"   # (ja no ecra alternativo: ao sair nao fica nada no ecra normal)
    if ($W -ge 70 -and $H -ge 22) {
        $cols = [Math]::Max(1, [Math]::Min(6, [Math]::Floor(($W - 6 + 3) / 43))); $cw = [Math]::Floor(($W - 6 - ($cols - 1) * 3) / $cols)
        $th = [Math]::Max(4, [int]($cw * 9 / 16 * 0.4)); $left = [Math]::Max(3, [Math]::Floor(($W - ($cols * ($cw + 3) - 3)) / 2) + 1)
        $sk = "$e[48;2;44;49;58m"; $bar = "$e[48;2;52;58;68m"
        $o += "$e[2;${left}H$e[1;31m$([char]0xf16a) $e[1;97mYouTube$e[0m"
        for ($r = 0; $r -lt 2 -and 7 + ($r + 1) * ($th + 6) -le $H; $r++) {
            for ($c = 0; $c -lt $cols; $c++) {
                $x = $left + $c * ($cw + 3); $y = 7 + $r * ($th + 6)
                for ($q = 0; $q -lt $th; $q++) { $o += "$e[$($y + $q);${x}H$sk" + (' ' * $cw) + "$e[0m" }
                $o += "$e[$($y + $th + 1);${x}H$bar" + (' ' * [Math]::Floor($cw * 0.8)) + "$e[0m$e[$($y + $th + 3);${x}H$sk" + (' ' * [Math]::Floor($cw * 0.45)) + "$e[0m"
            }
        }
    }
    [Console]::Write($o)
}
# tempos (so com YT_TRACE=1): %TEMP%\yt-trace.log, "ms desde o arranque <tab> o que aconteceu"
$TraceSw = [Diagnostics.Stopwatch]::StartNew()
function Trace([string]$m) { if ($env:YT_TRACE) { [IO.File]::AppendAllText("$env:TEMP\yt-trace.log", "$($TraceSw.ElapsedMilliseconds)`t$m`n") } }
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # (aberto sem o perfil, ex.: separador do pin ou do WSL, os icones e molduras viravam "?")
$MpvDir = Split-Path (@((Get-Command mpv -ErrorAction SilentlyContinue).Source, 'C:\Program Files\MPV Player\mpv.exe', "$HOME\.local\mpv\mpv.exe") | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1)
$MpvWin = Join-Path $MpvDir 'mpv.exe'   # janela
# yt-dlp "onedir" (yt-dlp_win.zip, em %LOCALAPPDATA%\Programs\yt-dlp-dir): arranca em ~0,45 s em vez de ~1,45 s do
# executável único do winget (que se descomprime todo em cada processo) — conta em cada lista, prefetch e no mpv
$YtDlp = @("$env:LOCALAPPDATA\Programs\yt-dlp-dir\yt-dlp.exe", (Get-Command yt-dlp -ErrorAction SilentlyContinue).Source) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
$Chafa = (Get-Command chafa).Source
$Dir = "$env:TEMP\yt"; $SixDir = "$Dir\six"
# celula do terminal: sem poder perguntar ao terminal, o chafa gera o sixel para celulas de 10x20 px. No WezTerm a celula e
# outra (espacamento de linha 1.25): pede-se o tamanho equivalente, e as imagens ficam numa pasta por tamanho de celula
$ChafaFx = 1.0; $ChafaFy = 1.0; $CellRatio = 0.45   # largura / altura da celula (Windows Terminal: ~0,45)
if ($env:WEZTERM_PANE -and $env:WEZTERM_EXECUTABLE) {
    try {
        $me = (& (Join-Path (Split-Path $env:WEZTERM_EXECUTABLE) 'wezterm.exe') cli list --format json 2>$null | ConvertFrom-Json) | Where-Object pane_id -eq ([int]$env:WEZTERM_PANE)
        $cw = $me.size.pixel_width / $me.size.cols; $ch = $me.size.pixel_height / $me.size.rows
        if ($cw -gt 0 -and $ch -gt 0) {
            $ChafaFx = $cw / 10; $ChafaFy = $ch / 20; $CellRatio = $cw / $ch; $SixDir = "$Dir\six-$([int]$cw)x$([int]$ch)"; $env:YT_ITERM = '1'
            $env:YT_CW = $cw.ToString([cultureinfo]::InvariantCulture); $env:YT_CH = $ch.ToString([cultureinfo]::InvariantCulture); $CellW = $cw; $CellH = $ch
            if ($env:YT_NOITERM) { Remove-Item Env:YT_ITERM }   # (testes: forcar sixel)
        }
    } catch {}
}
New-Item -ItemType Directory $SixDir -Force | Out-Null
# (para os thread jobs; invariante: "0,92" com a cultura pt-PT nao se lia de volta)
$env:YT_SIXDIR = $SixDir; $env:YT_FX = $ChafaFx.ToString([cultureinfo]::InvariantCulture); $env:YT_FY = $ChafaFy.ToString([cultureinfo]::InvariantCulture)
function Get-ChafaSize([int]$w, [int]$h) { "$([Math]::Max(1, [Math]::Round($w * $ChafaFx)))x$([Math]::Max(1, [Math]::Round($h * $ChafaFy)))" }
# cache das thumbnails (~15 KB) e das imagens sixel já geradas (~100 KB): apaga o que tiver mais de 7 dias
Get-ChildItem $Dir -File -Recurse | Where-Object LastWriteTime -lt (Get-Date).AddDays(-7) | ForEach-Object { [IO.File]::Delete($_.FullName) }
# sessão: o original fica intocado em ~\.config; o yt-dlp usa uma cópia de trabalho (ele grava sempre os cookies de volta
# no ficheiro, e uma resposta do YouTube a "terminar a sessão" apagava os cookies de login do original)
$CookieMaster = "$HOME\.config\yt-cookies.txt"; $BrowserFile = "$HOME\.config\yt-browser.txt"
# cada processo do yt-dlp leva a sua cópia ($Dir\ck-<guid>.txt, apagada quando ele termina): com um só ficheiro partilhado,
# um yt-dlp a gravar por cima de outro perdia a sessão. Get-CookieArgs devolve $CkTag, trocado pela cópia no arranque.
$CkTag = '<yt-cookies>'; $CkFiles = [Collections.Generic.List[object]]::new(); $ListFiles = [Collections.Generic.List[string]]::new()
Get-ChildItem $Dir -File | Where-Object { $_.Name -like 'ck-*.txt' -or $_.Name -like 'list-*' -or $_.Name -eq 'cookies.txt' } | Where-Object LastWriteTime -lt (Get-Date).AddDays(-1) | ForEach-Object { try { [IO.File]::Delete($_.FullName) } catch {} }
if (Test-Path "$Dir\cookies.txt") { try { [IO.File]::Delete("$Dir\cookies.txt") } catch {} }   # cópia partilhada das versões antigas
function New-Ck { $f = "$Dir\ck-$([guid]::NewGuid().ToString('N')).txt"; try { [IO.File]::Copy($CookieMaster, $f, $true) } catch {}; $f }
function Clear-Ck([switch]$All) {
    # apaga as cópias dos processos que já terminaram (-All: todas, à saída)
    foreach ($x in @($CkFiles)) { if ($All -or ($x.p -and $x.p.HasExited)) { try { [IO.File]::Delete($x.f) } catch {}; [void]$CkFiles.Remove($x) } }
}
function Start-Yt([string[]]$a, [string]$out) {
    # yt-dlp escondido; $CkTag nos argumentos -> cópia própria dos cookies; -out: stdout para o ficheiro (e stderr para .err)
    $f = $null; $a = @($a | ForEach-Object { if ($_ -eq $CkTag) { if (-not $f) { $f = New-Ck }; $f } else { $_ } })
    $o = @{ FilePath = $YtDlp; ArgumentList = (Quote-Args $a); WindowStyle = 'Hidden'; PassThru = $true }
    if ($out) { $o.RedirectStandardOutput = $out; $o.RedirectStandardError = "$out.err" }
    $p = try { Start-Process @o -ErrorAction Stop } catch { $null }
    if ($f) { $CkFiles.Add(@{ f = $f; p = $p }); if (-not $p) { try { [IO.File]::Delete($f) } catch {} } }
    $p
}
$WatchedFile = "$HOME\.config\yt-watched.txt"
# servidor de PO tokens (plugin bgutil do yt-dlp, ~\bgutil-ytdlp-pot-provider): sem ele o YouTube só dá até 1080p
# (os formatos DASH 1440p/2160p exigem PO token); fica a correr escondido entre sessões, na porta 4416
# mpv das miniaturas (thumbfast) que ficaram órfãos de sessões antigas (o mpv principal fechado à força): fecham-se
$null = Start-ThreadJob -Name yt {
    $alive = @{}; foreach ($p in Get-CimInstance Win32_Process -Property ProcessId) { $alive[[int]$p.ProcessId] = 1 }
    Get-CimInstance Win32_Process -Filter "Name='mpv.exe' and CommandLine like '%--load-scripts=no%--ytdl=no%'" |
        Where-Object { $_.CommandLine -like '*--idle*' -and -not $alive[[int]$_.ParentProcessId] } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA 0 }
}
$PotDir = "$HOME\bgutil-ytdlp-pot-provider\server\node_modules"
if ((Test-Path $PotDir) -and -not ([Net.Sockets.TcpClient]::new().ConnectAsync('127.0.0.1', 4416).Wait(100))) {
    Start-Process deno -WorkingDirectory $PotDir -WindowStyle Hidden -ArgumentList 'run', '--allow-env', '--allow-net', '--allow-ffi=.', '--allow-read=.', '../src/main.ts'
}
$Sixel = [hashtable]::Synchronized(@{})   # cache "id-WxH" -> sixel (partilhada com os thread jobs)
$Jobs = @{}                               # chave -> @{ p = processo do yt-dlp; f = ficheiro de saída }
$SearchNext = @{}                         # pesquisa -> ficheiro .next com o token da pagina seguinte (yt-search.ps1)
$Watched = [Collections.Generic.HashSet[string]]::new()
if (Test-Path $WatchedFile) { foreach ($id in [IO.File]::ReadAllLines($WatchedFile)) { [void]$Watched.Add($id) } }
$HistMerged = $false
$Sep = '|~|'
$Fmt = "%(id)s$Sep%(title)s$Sep%(channel,uploader)s$Sep%(duration_string)s$Sep%(view_count)s$Sep%(channel_id)s$Sep%(timestamp)s"   # timestamp: aproximado ("há 2 dias"), com youtubetab:approximate_date
$ChanFmt = "P$Sep%(channel)s$Sep%(uploader_id)s$Sep%(channel_follower_count)s$Sep%(description)j$Sep%(thumbnails)j$Sep%(channel_id)s"
# opções do mpv: config própria (ver ~\.config\mpv-setup.ps1)
$MpvOpts = @("--config-dir=$HOME\.config\mpv", "--script-opts-append=ytdl_hook-ytdl_path=$YtDlp", '--window-dragging=no')   # interface uosc + miniaturas thumbfast + volume guardado (~\.config\mpv)
$MpvN = 0   # contador de arranques do mpv: cada um tem o seu canal IPC (ytmpv-<pid>-<n>)
function New-MpvLog {
    # log por arranque ($Dir\mpv-<data>.log); ficam só os 5 mais recentes
    Get-ChildItem $Dir -Filter 'mpv-2*.log' -File -EA 0 | Sort-Object Name -Descending | Select-Object -Skip 4 | ForEach-Object { try { [IO.File]::Delete($_.FullName) } catch {} }
    $script:MpvLog = "$Dir\mpv-$(Get-Date -Format 'yyyyMMdd-HHmmss-fff').log"; "--log-file=$script:MpvLog"
}
function Quote-Args($a) { $a | ForEach-Object { if ("$_" -match '[\s"]') { "`"$("$_" -replace '"', '\"')`"" } else { "$_" } } }   # aspas dentro de um argumento: \"
$Tabs = @(
    @{ m = 'home';    n = 'home';          src = ':ytrec' }
    @{ m = 'feed';    n = 'subscriptions'; src = ':ytsubs' }
    @{ m = 'later';   n = 'watch later';   src = ':ytwatchlater' }
    @{ m = 'history'; n = 'history';       src = ':ythis' }
)
$ChanTabs = @(@{ m = 'videos'; n = 'videos' }, @{ m = 'shorts'; n = 'shorts' }, @{ m = 'streams'; n = 'live' })

# funções do Windows (consola, janelas): compiladas uma vez para uma DLL em disco e depois só carregadas
# (compilar C# em cada arranque custava ~0,4 s; o nome da DLL leva um hash do código -> recompila se ele mudar)
$WinApi = @'
using System; using System.Runtime.InteropServices;
namespace Yt {
public static class Con {
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
[StructLayout(LayoutKind.Explicit, Size = 20)] public struct IR { [FieldOffset(0)] public ushort Type; [FieldOffset(4)] public int Down; [FieldOffset(10)] public ushort VK;
    [FieldOffset(4)] public short MX; [FieldOffset(6)] public short MY; [FieldOffset(8)] public int Btn; [FieldOffset(16)] public int Flags; }   // Down: bKeyDown / bSetFocus; M*: MOUSE_EVENT
// rato: tira da frente da fila os eventos do rato (o .NET deita-os fora) e devolve o ultimo clique ou roda:
// 0 = nada, 1 = clique esquerdo, 2 = roda (Wheel = +1 para cima, -1 para baixo); posicao em MouseX / MouseY (a contar de 0)
public static int MouseX, MouseY, Wheel;
public static int Mouse(IntPtr h) {
    // (a roda soma todos os eventos seguidos da fila: um gesto do touchpad manda dezenas -> um so passo de N filas)
    int r = 0; Wheel = 0; var b = new IR[32]; uint n, got;
    while (r != 1 && GetNumberOfConsoleInputEvents(h, out n) && n > 0 && PeekConsoleInputW(h, b, Math.Min(n, 32u), out got) && got > 0) {
        uint k = 0; bool stop = false;
        while (k < got && b[k].Type == 2) {
            int fl = b[k].Flags;
            if (fl == 4) { r = 2; Wheel += (short)(b[k].Btn >> 16) > 0 ? 1 : -1; MouseX = b[k].MX; MouseY = b[k].MY; }
            else if ((fl == 0 || fl == 2) && (b[k].Btn & 1) != 0) { if (r == 2) { stop = true; break; } r = 1; MouseX = b[k].MX; MouseY = b[k].MY; k++; stop = true; break; }
            else if (fl == 1 && (r == 0 || r == 3)) { r = 3; MouseX = b[k].MX; MouseY = b[k].MY; }   // so mexeu (hover): fica a ultima posicao
            k++;
        }
        if (k == 0) break;
        ReadConsoleInputW(h, b, k, out got);
        if (stop || k < got) break;
    }
    if (r == 2 && Wheel == 0) r = 0;   // (para cima e para baixo no mesmo gesto: anula-se)
    return r;
}
[DllImport("kernel32.dll")] static extern bool GetNumberOfConsoleInputEvents(IntPtr h, out uint n);
[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool PeekConsoleInputW(IntPtr h, [Out] IR[] b, uint n, out uint r);
[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool ReadConsoleInputW(IntPtr h, [Out] IR[] b, uint n, out uint r);
// foco do painel: o ConPTY converte o ESC[I / ESC[O do terminal em FOCUS_EVENT (o ReadKey ignora-os).
// Tira da frente da fila os eventos que não são teclas premidas (o .NET também os deita fora, mas perdia-se o foco)
// e devolve o último foco visto: 1 = ganhou, 0 = perdeu, -1 = nada. (Tecla largada com Alt fica: Alt+números do teclado numérico)
public static int Focus(IntPtr h) {
    int r = -1; var b = new IR[32]; uint n, got;
    while (GetNumberOfConsoleInputEvents(h, out n) && n > 0 && PeekConsoleInputW(h, b, Math.Min(n, 32u), out got) && got > 0) {
        uint k = 0; while (k < got && b[k].Type != 2 && (b[k].Type != 1 || (b[k].Down == 0 && b[k].VK != 0x12))) { if (b[k].Type == 0x10) r = b[k].Down != 0 ? 1 : 0; k++; }
        if (k == 0) break;
        ReadConsoleInputW(h, b, k, out got);   // as teclas ficam na fila para o ReadKey
        if (k < got) break;
    }
    return r;
}
}
public static class Win {
[StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Rt, B; }
[StructLayout(LayoutKind.Sequential)] public struct P { public int X, Y; }
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
[DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out R r);
[DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref P p);
[DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr p);
[DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
public delegate bool EnumProc(IntPtr h, IntPtr l);
[DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", EntryPoint = "GetWindowThreadProcessId")] static extern uint GetWindowPid(IntPtr h, out uint pid);
// janela do WezTerm (classe org.wezfurlong.wezterm) do processo pid
public static IntPtr FindWez(uint pid) {
    IntPtr found = IntPtr.Zero; var sb = new System.Text.StringBuilder(64);
    EnumWindows((h, l) => { uint p; GetWindowPid(h, out p); if (p != pid) return true; sb.Length = 0; GetClassName(h, sb, 64);
        if (sb.ToString() == "org.wezfurlong.wezterm") { found = h; return false; } return true; }, IntPtr.Zero);
    return found;
}
[DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
[DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
[DllImport("user32.dll")] public static extern IntPtr SetWindowLongPtr(IntPtr h, int i, IntPtr v);
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
}
public static class Vd {
[DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
}
// "job" do Windows com KILL_ON_JOB_CLOSE: quando este processo morre (separador fechado, crash), o Windows fecha
// também tudo o que lá estiver (o mpv e os processos dele, como o mpv das miniaturas)
public static class Job {
[StructLayout(LayoutKind.Sequential)] struct Basic { public long a, b; public uint Flags; public UIntPtr c, d; public uint e; public UIntPtr f; public uint g, h; }
[StructLayout(LayoutKind.Sequential)] struct Io { public ulong a, b, c, d, e, f; }
[StructLayout(LayoutKind.Sequential)] struct Ext { public Basic B; public Io I; public UIntPtr a, b, c, d; }
[DllImport("kernel32.dll")] static extern IntPtr CreateJobObject(IntPtr a, string n);
[DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr j, int c, ref Ext i, int l);
[DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr j, IntPtr p);
static IntPtr job;
public static bool Add(IntPtr process) {
    if (job == IntPtr.Zero) {
        job = CreateJobObject(IntPtr.Zero, null);
        var x = new Ext(); x.B.Flags = 0x2000;   // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        SetInformationJobObject(job, 9, ref x, Marshal.SizeOf(typeof(Ext)));
    }
    return AssignProcessToJobObject(job, process);
}
}
}
'@
if (-not ('Yt.Con' -as [type])) {
    $hash = [BitConverter]::ToString([Security.Cryptography.SHA1]::HashData([Text.Encoding]::UTF8.GetBytes($WinApi))).Replace('-', '').Substring(0, 12)
    $dll = "$env:LOCALAPPDATA\yt-tui\winapi-$hash.dll"
    if (-not (Test-Path $dll)) { New-Item -ItemType Directory (Split-Path $dll) -Force | Out-Null; Add-Type -TypeDefinition $WinApi -OutputAssembly $dll }
    Add-Type -Path $dll
}
# modo do teclado da consola: guardado no arranque e reposto antes de cada tecla
# (programas externos podem ligar a entrada em modo VT, e as setas passariam a chegar como texto)
Trace 'add-type feito'
$InH = [Yt.Con]::GetStdHandle(-10); $InMode = 0; [void][Yt.Con]::GetConsoleMode($InH, [ref]$InMode)
# descarta teclas acumuladas (Enter repetido enquanto algo carregava não abre vídeo atrás de vídeo)
function Clear-Keys { while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) } }
# modo da entrada: sem VT (o foco chega como evento), com rato (0x10 + extended 0x80, sem quick edit 0x40)
$InModeYt = (($InMode -band (-bnot 0x200)) -band (-bnot 0x40)) -bor 0x10 -bor 0x80
function Read-Key { [void][Yt.Con]::SetConsoleMode($InH, $InModeYt); [Console]::ReadKey($true) }

# ---------- conta ----------
function Get-CookieArgs {
    if (Test-Path $CookieMaster) { return @('--cookies', $CkTag) }   # $CkTag: Start-Yt troca-o por uma cópia própria
    if (Test-Path $BrowserFile) { return @('--cookies-from-browser', (Get-Content $BrowserFile -Raw).Trim()) }
    $null
}
function Test-Login([string[]]$c) {
    $f = $null; $c = @($c | ForEach-Object { if ($_ -eq $CkTag) { if (-not $f) { $f = New-Ck }; $f } else { $_ } })
    try { [bool](& $YtDlp ':ytsubs' @c --flat-playlist --playlist-end 1 --no-warnings --print id 2>$null) } finally { if ($f) { try { [IO.File]::Delete($f) } catch {} } }
}
$LoginUrl = 'https://accounts.google.com/ServiceLogin?service=youtube&continue=https://www.youtube.com/'
$ExtId = 'cclelndahbckbenkjhflpdbgdldlbecc'   # extensão "Get cookies.txt LOCALLY"
function Get-Browser {
    # browser predefinido do utilizador: executável, pasta de dados (Chromium) e flag de janela privada
    $id = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice' -ErrorAction SilentlyContinue).ProgId
    $cmd = if ($id) { (Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\$id\shell\open\command" -ErrorAction SilentlyContinue).'(default)' }
    $exe = [regex]::Match("$cmd", '^"([^"]+)"').Groups[1].Value
    if (-not $exe -or -not (Test-Path $exe)) { return $null }
    switch ((Split-Path $exe -Leaf).ToLower()) {
        'brave.exe'   { @{ exe = $exe; name = 'Brave'; priv = '--incognito'; data = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"; ext = "https://chromewebstore.google.com/detail/$ExtId"; extPage = 'brave://extensions' } }
        'chrome.exe'  { @{ exe = $exe; name = 'Chrome'; priv = '--incognito'; data = "$env:LOCALAPPDATA\Google\Chrome\User Data"; ext = "https://chromewebstore.google.com/detail/$ExtId"; extPage = 'chrome://extensions' } }
        'msedge.exe'  { @{ exe = $exe; name = 'Edge'; priv = '--inprivate'; data = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"; ext = "https://chromewebstore.google.com/detail/$ExtId"; extPage = 'edge://extensions' } }
        'firefox.exe' { @{ exe = $exe; name = 'Firefox'; priv = '-private-window'; data = $null; ext = 'https://addons.mozilla.org/firefox/addon/get-cookies-txt-locally/'; extPage = 'about:addons' } }
        default       { @{ exe = $exe; name = (Split-Path $exe -LeafBase); priv = '--incognito'; data = $null; ext = "https://chromewebstore.google.com/detail/$ExtId"; extPage = 'the extensions page' } }
    }
}
function Get-ExtState($b) {
    # extensão instalada? e com "permitir em privado"? (só dá para ver nos browsers Chromium conhecidos)
    if (-not $b.data) { return @{ known = $false } }
    $prof = "$($b.data)\Default"
    $inst = Test-Path "$prof\Extensions\$ExtId"
    $priv = $false
    foreach ($pf in "$prof\Secure Preferences", "$prof\Preferences") {
        try { $j = Get-Content $pf -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable; if ($j.extensions.settings[$ExtId].incognito) { $priv = $true } } catch {}
    }
    @{ known = $true; installed = $inst; private = $priv }
}
function Invoke-Login([switch]$Required) {
    # Os browsers Chromium cifram a sessão: exporta-se uma vez um ficheiro de cookies com uma extensão, numa janela
    # privada (numa janela normal o browser continua a usar a sessão e o YouTube invalida a cópia ao fim de umas horas)
    $dl = (New-Object -ComObject Shell.Application).Namespace('shell:Downloads').Self.Path
    $b = Get-Browser; $st = if ($b) { Get-ExtState $b } else { @{ known = $false } }
    $since = Get-Date
    $open = {
        if (-not $b) { return }
        if (-not ($st.known -and $st.installed)) { Start-Process $b.exe -ArgumentList $b.ext }   # janela normal: instalar a extensão
        Start-Process $b.exe -ArgumentList $b.priv, $LoginUrl                                       # janela privada: entrar na conta
    }
    & $open
    while ($true) {
        $st = if ($b) { Get-ExtState $b } else { @{ known = $false } }
        $steps = @()
        if (-not ($st.known -and $st.installed)) { $steps += "install the $e[36mGet cookies.txt LOCALLY$e[37m extension on the page that opened $e[90m(Add)$e[0m" }
        if (-not ($st.known -and $st.private)) { $steps += "in $e[36m$($b.extPage)$e[37m open the extension's $e[1;97mDetails$e[0;37m and turn on $e[1;97mAllow in incognito/private$e[0m" }
        $steps += "in the $e[1;97mprivate window$e[0;37m that opened, sign in to your Google account$e[0m"
        $steps += "click the extension icon $e[90m->$e[37m $e[1;97mExport$e[0;37m $e[90m(saves to Downloads)$e[0m"
        $steps += "close the private window $e[90m— yt carries on by itself once the file shows up$e[0m"
        $lines = @('', "   $e[1;31m$([char]0xf16a)  $e[1;97msign in to YouTube$e[0;90m   ($(if ($b) { $b.name } else { 'browser' }))$e[0m", '')
        for ($i = 0; $i -lt $steps.Count; $i++) { $lines += "   $e[1;97m$($i + 1)$e[0;37m  $($steps[$i])"; $lines += '' }
        $lines += "   $e[90m$([char]0x2500 * 60)$e[0m"
        $lines += "   $e[37mp$e[90m reopen the windows     $e[37mx$e[90m sign out     $e[37mesc$e[90m $(if ($Required) { 'quit yt' } else { 'back' })$e[0m"
        [Console]::Write("$e[2J$e[H" + ($lines -join "`n"))
        # espera: ficheiro novo de cookies nas Transferências (avança sozinho) ou tecla
        $new = $null; $k = $null; $t0 = [Diagnostics.Stopwatch]::StartNew()
        while (-not $new -and -not $k) {
            if ([Console]::KeyAvailable) { $k = Read-Key; break }
            $new = Get-ChildItem $dl -Filter '*cookies*.txt' -File -ErrorAction SilentlyContinue | Where-Object LastWriteTime -gt $since | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($t0.ElapsedMilliseconds -gt 5000) { break }   # de 5 em 5 s redesenha (os passos já feitos desaparecem)
            Start-Sleep -Milliseconds 400
        }
        if ($k) {
            if ($k.Key -eq 'Escape') { return $false }
            switch ($k.KeyChar) {
                'p' { $since = Get-Date; & $open }
                'x' { foreach ($p in $CookieMaster, $BrowserFile) { if (Test-Path $p) { [IO.File]::Delete($p) } }; Show-Status 'signed out'; Start-Sleep 1 }
            }
            continue
        }
        if (-not $new) { continue }
        Start-Sleep -Milliseconds 500   # deixa o browser acabar de gravar
        Copy-Item $new.FullName $CookieMaster -Force; [IO.File]::Delete($new.FullName)   # fica só em ~\.config
        Show-Status 'file received — checking the session...'
        if (Test-Login @('--cookies', $CkTag)) { if (Test-Path $BrowserFile) { [IO.File]::Delete($BrowserFile) }; return $true }
        [IO.File]::Delete($CookieMaster)
        Show-Status "$e[31mthe file has no YouTube session: export it with youtube.com open and signed in"; Start-Sleep 3
        $since = Get-Date
    }
}

# ---------- dados (em segundo plano) ----------
function Start-ListJob([string]$key, [string]$src, [int]$n, [string[]]$extra = @(), [string]$plPrint = '', [int]$from = 1) {
    # ficheiro próprio por pedido (o anterior com a mesma chave pode ainda estar a ser lido); o processo antigo é fechado
    $out = "$Dir\list-$key-$([guid]::NewGuid().ToString('N')).txt"; $ListFiles.Add($out)
    $old = $Jobs[$key]; if ($old -and $old.p) { try { if (-not $old.p.HasExited) { $old.p.Kill() } } catch {} }
    # pesquisa: pedido direto a API do YouTube (yt-search.ps1, ~1 s) em vez do yt-dlp (~4,5 s). 1.a pagina so com 20
    # (chegam para o ecra); o "mais" continua com o token que ficou em <ficheiro>.next. Sem token: yt-dlp como antes.
    # (ytrelated:<id> = os relacionados do video, a barra lateral do YouTube: o mesmo yt-search.ps1, com -Related)
    if ($src -match '^(ytsearch\d*|ytrelated):(.+)$') {
        $rel = $Matches[1] -eq 'ytrelated'; $q = $Matches[2]; $sk = "$($Matches[1]):$q"
        $tok = if ($from -gt 1 -and $SearchNext[$sk] -and (Test-Path $SearchNext[$sk])) { (Get-Content $SearchNext[$sk] -Raw).Trim() }
        if ($from -eq 1 -or $tok) {
            $sa = @('-NoProfile', '-File', "$HOME\.config\yt-search.ps1", $(if ($rel) { '-Related' } else { '-Query' }), $q, '-Out', $out, '-Sep', $Sep, '-Count', $(if ($tok) { 40 } else { 20 })) + $(if ($tok) { '-Token', $tok })
            $p = try { Start-Process pwsh -WindowStyle Hidden -PassThru -ArgumentList (Quote-Args $sa) -ErrorAction Stop } catch { $null }
            $SearchNext[$sk] = "$out.next"
            $Jobs[$key] = @{ p = $p; f = $out; t = [datetime]::Now }
            return
        }
    }
    $a = @($src, '--flat-playlist', '--playlist-items', "$from-$($from + $n - 1)", '--no-warnings', '--encoding', 'utf-8', '--extractor-args', 'youtubetab:approximate_date', '--print', $Fmt) + $(if ($plPrint) { '--print', "playlist:$plPrint" }) + $extra
    $p = Start-Yt $a $out
    $Jobs[$key] = @{ p = $p; f = $out; t = [datetime]::Now }
}
# trabalho dos threads de imagens: descarrega as thumbnails que faltam (em paralelo) e gera as primeiras $n imagens sixel,
# guardadas em memória e no disco ($Dir\six) para a próxima vez abrir sem gerar nada.
# (vai como texto: um scriptblock passado a um thread job correria no runspace principal)
$SixelWork = @'
param($ids, $n, $dir, $chafa, $tw, $th, $cache, $busy)
# thumbnails: --fail (um erro HTTP não fica gravado como imagem), para .part e só depois o nome final;
# $busy = ids a descarregar noutro thread/processo (não se pedem duas vezes)
# grelha: miniatura grande (hq720, 1280x720, como o YouTube no browser) em $id-hq.jpg; sem hq720, a mqdefault (320x180)
$got = @()
foreach ($id in $ids) { if (-not (Test-Path "$dir\$id-hq.jpg")) { try { $busy.Add($id, 1); $got += $id } catch {} } }
foreach ($q in 'hq720', 'mqdefault') {
    $want = @($got | Where-Object { -not (Test-Path "$dir\$_-hq.jpg") }); if (-not $want) { break }
    $a = @('--parallel', '-sL', '--fail', '--remove-on-error'); foreach ($id in $want) { $a += "https://i.ytimg.com/vi/$id/$q.jpg", '-o', "$dir\$id-hq.jpg.part" }
    & curl.exe @a 2>$null
    foreach ($id in $want) { $f = "$dir\$id-hq.jpg"; try { if ((Test-Path "$f.part") -and (Get-Item "$f.part").Length) { [IO.File]::Move("$f.part", $f, $true) } else { [IO.File]::Delete("$f.part") } } catch {} }
}
foreach ($id in $got) { $busy.Remove($id) }
foreach ($id in ($ids | Select-Object -First $n)) {
    $k = "$id-$tw-$th-s"; $sf = "$env:YT_SIXDIR\$k.six"
    # a descarregar noutro thread (ex.: o prefetch): espera (ate 5 s); antes, no WezTerm saltava-a e ficava em branco
    if (-not $cache.ContainsKey($k)) { for ($w8 = 0; $w8 -lt 100 -and $busy.ContainsKey($id); $w8++) { Start-Sleep -Milliseconds 50 } }
    # WezTerm: o proprio JPEG vai para o terminal (protocolo de imagens do iTerm2) e e ele que o descodifica: cores
    # originais, sem a conversao do chafa (sixel = paleta de 256 cores, ~2x mais lento)
    if ($env:YT_ITERM) {
        if ($cache.ContainsKey($k) -or -not (Test-Path "$dir\$id-hq.jpg")) { continue }
        # ja no tamanho exato em que aparece (pixels do cartao): ~25 KB em vez dos ~250 KB do hq720 -> cada pagina
        # desenha-se ~10x mais depressa (o terminal nao tem de descodificar e encolher imagens grandes a cada pagina)
        $sj = "$env:YT_SIXDIR\$k.jpg"
        if (-not (Test-Path $sj)) {
            try {
                Add-Type -AssemblyName System.Drawing
                $pw = [int]($tw * [double]::Parse($env:YT_CW, [cultureinfo]::InvariantCulture)); $ph = [int]($th * [double]::Parse($env:YT_CH, [cultureinfo]::InvariantCulture))
                $src = [Drawing.Image]::FromFile("$dir\$id-hq.jpg"); $bmp = [Drawing.Bitmap]::new($pw, $ph); $gr = [Drawing.Graphics]::FromImage($bmp)
                $gr.InterpolationMode = 'HighQualityBicubic'; $gr.PixelOffsetMode = 'HighQuality'; $gr.DrawImage($src, 0, 0, $pw, $ph)
                $jc = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg'
                $ep = [Drawing.Imaging.EncoderParameters]::new(1); $ep.Param[0] = [Drawing.Imaging.EncoderParameter]::new([Drawing.Imaging.Encoder]::Quality, [long]90)
                $tmp = "$sj.$([guid]::NewGuid().ToString('N')).tmp"; $bmp.Save($tmp, $jc, $ep); $gr.Dispose(); $bmp.Dispose(); $src.Dispose(); [IO.File]::Move($tmp, $sj, $true)
            } catch { $sj = "$dir\$id-hq.jpg" }
        }
        $cache[$k] = "$([char]27)]1337;File=inline=1;width=$tw;height=$th;preserveAspectRatio=0:" + [Convert]::ToBase64String([IO.File]::ReadAllBytes($sj)) + [char]7
        continue
    }
    $sz = "$([Math]::Max(1, [Math]::Round($tw * [double]::Parse($env:YT_FX, [cultureinfo]::InvariantCulture))))x$([Math]::Max(1, [Math]::Round($th * [double]::Parse($env:YT_FY, [cultureinfo]::InvariantCulture))))"
    if ($cache.ContainsKey($k)) { continue }
    # (tudo antes do ESC P sai: dentro do WezTerm o chafa poe ?80l / ?8452l antes da imagem, e o WezTerm deixa de a mostrar)
    if (Test-Path $sf) { try { $cache[$k] = [IO.File]::ReadAllText($sf) -replace '^(?s).*?(?=\x1bP)', ''; continue } catch {} }
    if (-not (Test-Path "$dir\$id-hq.jpg")) { continue }
    $x = ((& $chafa -f sixels --probe off --dither none --stretch --size $sz "$dir\$id-hq.jpg" 2>$null) -join '') -replace "$([char]27)\[\?25[hl]", '' -replace '^(?s).*?(?=\x1bP)', ''
    $tmp = "$sf.$([guid]::NewGuid().ToString('N')).tmp"
    if ($x) { try { [IO.File]::WriteAllText($tmp, $x); [IO.File]::Move($tmp, $sf, $true) } catch {}; $cache[$k] = $x }   # gravar e só depois mudar o nome: nunca se lê a meio
}
'@
function Start-Prefetch([string]$key, $L) {
    # thread em segundo plano: espera pela lista, descarrega as thumbnails e gera as imagens da 1.ª página
    $j = $Jobs[$key]
    $null = Start-ThreadJob -Name yt -ThrottleLimit 24 -ArgumentList $j.p, $j.f, $Sep, $SixelWork, $Dir, $Chafa, $L.TW, $L.TH, $L.per, $Sixel, $ThumbBusy -ScriptBlock {
        param($p, $f, $sep, $work, $dir, $chafa, $tw, $th, $per, $cache, $busy)
        if (-not $p) { return }
        $p.WaitForExit()
        $ids = @(Get-Content $f -Encoding utf8 -ErrorAction SilentlyContinue | ForEach-Object { ($_ -split [regex]::Escape($sep))[0] } | Where-Object { $_.Length -eq 11 })
        & ([scriptblock]::Create($work)) $ids $per $dir $chafa $tw $th $cache $busy
    }
}
function Start-SixelJob($ids, $L) {
    $null = Start-ThreadJob -Name yt -ThrottleLimit 24 -ArgumentList $SixelWork, @($ids), $Dir, $Chafa, $L.TW, $L.TH, $Sixel, $ThumbBusy -ScriptBlock {
        param($work, $ids, $dir, $chafa, $tw, $th, $cache, $busy)
        & ([scriptblock]::Create($work)) $ids $ids.Count $dir $chafa $tw $th $cache $busy
    }
}
$ThumbBusy = [hashtable]::Synchronized(@{})   # ids de thumbnails a descarregar neste momento
function Start-Thumbs($ids) {
    # descarrega em segundo plano as thumbnails que faltam (para .part); Complete-Thumbs dá-lhes o nome final quando o curl acabar
    $a = @('--parallel', '-sL', '--fail', '--remove-on-error'); $got = @()
    foreach ($id in $ids) { if (-not (Test-Path "$Dir\$id.jpg")) { try { $ThumbBusy.Add($id, 1); $got += $id; $a += "https://i.ytimg.com/vi/$id/mqdefault.jpg", '-o', "$Dir\$id.jpg.part" } catch {} } }
    if (-not $got) { return $null }
    $p = try { Start-Process curl.exe -ArgumentList $a -WindowStyle Hidden -PassThru -ErrorAction Stop } catch { $null }
    @{ p = $p; ids = $got }
}
function Complete-Thumbs($t, [switch]$Discard) {
    # -Discard: curl interrompido -> os .part podem estar a meio, apagam-se
    foreach ($id in $t.ids) { $f = "$Dir\$id.jpg"; try { if (-not $Discard -and (Test-Path "$f.part") -and (Get-Item "$f.part").Length) { [IO.File]::Move("$f.part", $f, $true) } else { [IO.File]::Delete("$f.part") } } catch {}; $ThumbBusy.Remove($id) }
}
function Test-Six([string]$id, $L) {
    $k = "$id-$($L.TW)-$($L.TH)-s"
    # (iTerm: pronta quando o JPEG reduzido existe; sem ele, o thread de imagens fa-lo e o Update-Pending desenha)
    $Sixel.ContainsKey($k) -or $(if ($env:YT_ITERM) { [IO.File]::Exists("$SixDir\$k.jpg") } else { [IO.File]::Exists("$SixDir\$k.six") })
}
function Wait-Busy([scriptblock]$done, [string]$msg, [int]$maxMs = 600000, [switch]$Cancelable, [int]$Row = 0) {
    # indicador animado ao centro do ecrã enquanto se espera (em vez de texto no rodapé)
    # -Cancelable: esc cancela; 1-4, /, s, ctrl+f e q cancelam e ficam para o ciclo principal ($PendingKey)
    $script:Canceled = $false
    if (& $done) { return }
    $hint = if ($Cancelable) { 'esc cancels' } else { '' }
    $frames = [char[]]'⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'; $i = 0; $sw = [Diagnostics.Stopwatch]::StartNew()
    $W = [Console]::WindowWidth; $r = if ($Row) { $Row } else { [Math]::Floor([Console]::WindowHeight / 2) }
    $bw = [Math]::Max(28, $msg.Length + $hint.Length + 10); $c = [Math]::Max(1, [Math]::Floor(($W - $bw) / 2) + 1)
    $bg = "$e[48;2;44;49;58m"; $tw = $bw - 4
    while (-not (& $done) -and $sw.ElapsedMilliseconds -lt $maxMs) {
        if ($Cancelable -and [Console]::KeyAvailable) {
            $k = Read-Key
            if ($k.Key -eq 'Escape') { $script:Canceled = $true; break }
            if ("$($k.KeyChar)" -in '1', '2', '3', '4', '/', 's', 'q' -or $k.KeyChar -eq [char]6) { $script:Canceled = $true; $script:PendingKey = $k; break }
        }
        # linha 1: spinner + texto (+ "esc cancels" a direita); linha 2: trilho cinzento com um segmento vermelho a ir e vir
        $sp = $frames[$i % $frames.Count]; $pad = $bw - 6 - $msg.Length - $hint.Length
        $seg = 8; $pos = [int](($tw - $seg) * (1 - [Math]::Cos($i * 0.12)) / 2); $i++
        $bar = "$e[38;2;62;68;81m" + ([string][char]0x2501 * $pos) + "$e[38;2;255;0;0m" + ([string][char]0x2501 * $seg) + "$e[38;2;62;68;81m" + ([string][char]0x2501 * ($tw - $pos - $seg))
        [Console]::Write("$e[?2026h$e[$($r - 1);${c}H$bg" + (' ' * $bw) + "$e[$r;${c}H$bg  $e[1;31m$sp  $e[0;97m$bg$msg" + (' ' * [Math]::Max(1, $pad)) + "$e[90m$hint  " +
            "$e[$($r + 1);${c}H$bg  $bar$bg  $e[$($r + 2);${c}H$bg" + (' ' * $bw) + "$e[0m$e[?2026l")
        Start-Sleep -Milliseconds 40
    }
    $o = ''; for ($q = -1; $q -le 2; $q++) { $o += "$e[$($r + $q);${c}H" + (' ' * $bw) }; [Console]::Write($o)
}
function Read-ListFile([string]$f) {
    @(Get-Content $f -Encoding utf8 -ErrorAction SilentlyContinue | ForEach-Object {
            $x = $_ -split [regex]::Escape($Sep)
            if ($x.Count -ge 5 -and $x[0].Length -eq 11) { [pscustomobject]@{ id = $x[0]; t = $x[1]; ch = $x[2]; dur = $(if ($x[3] -eq 'NA') { 'live' } else { $x[3] }); v = $x[4]; chid = $(if ($x.Count -ge 6) { $x[5] }); ts = $(if ($x.Count -ge 7) { $x[6] }) } }
        })
}
function Wait-List([string]$key, [string]$msg = 'loading') {
    $j = $Jobs[$key]; if (-not $j) { return @() }
    Wait-Busy { -not $j.p -or $j.p.HasExited } $msg -Cancelable
    if ($script:Canceled) { return @() }
    Read-ListFile $j.f
}
function Update-Watched {
    # junta o histórico da conta (carregado em segundo plano) aos vídeos vistos
    if ($script:HistMerged -or -not $Jobs['history'] -or -not $Jobs['history'].p.HasExited) { return }
    foreach ($x in Read-ListFile $Jobs['history'].f) { [void]$Watched.Add($x.id) }
    $script:HistMerged = $true
}
# JPEG reduzido ao tamanho em que aparece (iTerm2 no WezTerm): o terminal descodifica imagens pequenas, nao as grandes
function Resize-Jpg([string]$src, [string]$dst, [int]$pw, [int]$ph) {
    try {
        Add-Type -AssemblyName System.Drawing
        $im = [Drawing.Image]::FromFile($src); $bmp = [Drawing.Bitmap]::new($pw, $ph); $gr = [Drawing.Graphics]::FromImage($bmp)
        $gr.InterpolationMode = 'HighQualityBicubic'; $gr.PixelOffsetMode = 'HighQuality'; $gr.DrawImage($im, 0, 0, $pw, $ph)
        $jc = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg'
        $ep = [Drawing.Imaging.EncoderParameters]::new(1); $ep.Param[0] = [Drawing.Imaging.EncoderParameter]::new([Drawing.Imaging.Encoder]::Quality, [long]90)
        $tmp = "$dst.$([guid]::NewGuid().ToString('N')).tmp"; $bmp.Save($tmp, $jc, $ep); $gr.Dispose(); $bmp.Dispose(); $im.Dispose(); [IO.File]::Move($tmp, $dst, $true)
        $true
    } catch { $false }
}
function Get-Img([string]$file, [int]$w, [int]$h, [switch]$Stretch, [string]$Key) {
    # sixel de qualquer imagem: memória -> disco -> chafa (e guarda nos dois)
    # --dither none: sixel ~40% mais pequeno (o terminal desenha mais depressa), sem diferença visível em thumbnails
    $k = if ($Key) { $Key } else { "$([IO.Path]::GetFileNameWithoutExtension($file))-$w-$h$(if ($Stretch) { '-s' })" }
    if ($Sixel.ContainsKey($k)) { return $Sixel[$k] }
    # WezTerm: o JPEG tal como e (protocolo do iTerm2); o terminal descodifica-o com as cores todas
    if ($env:YT_ITERM) {
        $small = "$SixDir\$k.jpg"
        if (-not [IO.File]::Exists($small)) {
            if (-not [IO.File]::Exists($file)) { return $null }
            if (-not (Resize-Jpg $file $small ([int]($w * $CellW)) ([int]($h * $CellH)))) { $small = $file }
        }
        $s = "$e]1337;File=inline=1;width=$w;height=$h;preserveAspectRatio=$(if ($Stretch) { 0 } else { 1 }):" + [Convert]::ToBase64String([IO.File]::ReadAllBytes($small)) + [char]7
        $Sixel[$k] = $s; return $s
    }
    $sf = "$SixDir\$k.six"
    $s = if ([IO.File]::Exists($sf) -and ($rd = try { [IO.File]::ReadAllText($sf) -replace '^(?s).*?(?=\x1bP)', '' } catch { $null })) { $rd } elseif ([IO.File]::Exists($file)) {
        $st = @(if ($Stretch) { '--stretch' })   # (lista: um texto solto com @ passava mal ao chafa)
        # (o chafa esconde/mostra o cursor à volta da imagem: tira-se, senão o cursor fica a piscar na grelha)
        $x = ((& $Chafa -f sixels --probe off --dither none @st --size (Get-ChafaSize $w $h) $file 2>$null) -join '') -replace "$e\[\?25[hl]", '' -replace '^(?s).*?(?=\x1bP)', ''
        if ($x) { try { $tmp = "$sf.$([guid]::NewGuid().ToString('N')).tmp"; [IO.File]::WriteAllText($tmp, $x); [IO.File]::Move($tmp, $sf, $true) } catch {} }; $x
    }
    if ($s) { $Sixel[$k] = $s }
    $s
}
function Get-Sixel([string]$id, $L) { Get-Img "$Dir\$id-hq.jpg" $L.TW $L.TH -Stretch -Key "$id-$($L.TW)-$($L.TH)-s" }
function Format-Num($v) {
    if ("$v" -notmatch '^\d+$') { return '' }
    $n = [double]$v
    if ($n -ge 1e6) { '{0:0.#}M' -f ($n / 1e6) } elseif ($n -ge 1e4) { '{0:0}K' -f ($n / 1e3) } elseif ($n -ge 1e3) { '{0:0.#}K' -f ($n / 1e3) } else { "$n" }
}

# ---------- canal ----------
function Get-ChannelBase($arg) {
    if ($arg -is [hashtable] -and $arg.id -and $arg.id -ne 'NA') { return "https://www.youtube.com/channel/$($arg.id)" }
    $s = if ($arg -is [hashtable]) { $arg.name } else { "$arg" }
    if ($s -match '^UC[\w-]{22}$') { "https://www.youtube.com/channel/$s" } elseif ($s -like '@*') { "https://www.youtube.com/$s" } else { 'https://www.youtube.com/@' + ($s -replace '\s', '') }
}
function Get-ChannelInfo([string]$f) {
    $line = Get-Content $f -Encoding utf8 -ErrorAction SilentlyContinue | Where-Object { $_.StartsWith("P$Sep") } | Select-Object -First 1
    if (-not $line) { return $null }
    $x = $line -split [regex]::Escape($Sep)
    $desc = try { ($x[4] | ConvertFrom-Json) -replace '\s+', ' ' } catch { '' }
    $th = try { @($x[5] | ConvertFrom-Json) } catch { @() }
    $avatar = ($th | Where-Object { $_.width -and $_.width -eq $_.height } | Sort-Object width -Descending | Select-Object -First 1).url
    $banner = ($th | Where-Object { $_.width -and $_.height -and ($_.width / $_.height) -gt 3 } | Sort-Object width -Descending | Select-Object -First 1).url
    $info = @{ name = $x[1]; handle = $x[2]; subs = $x[3]; desc = $desc; id = $x[6]; avatar = ''; banner = '' }
    # avatar e banner: descarregados uma vez por canal; o banner é cortado à faixa que cabe no ecrã
    $a = @('-sL', '--fail', '--remove-on-error'); $af = "$Dir\ch-$($info.id)-a.jpg"
    if ($avatar -and -not (Test-Path $af)) { $a += $avatar, '-o', "$af.part" }
    if ($a.Count -gt 3) {
        $p = try { Start-Process curl.exe -ArgumentList (@('--parallel') + $a) -WindowStyle Hidden -PassThru -ErrorAction Stop } catch { $null }
        Wait-Busy { -not $p -or $p.HasExited } 'opening channel'
        try { if ($p -and $p.HasExited -and (Test-Path "$af.part") -and (Get-Item "$af.part").Length) { [IO.File]::Move("$af.part", $af, $true) } else { [IO.File]::Delete("$af.part") } } catch {}
    }
    if (Test-Path "$Dir\ch-$($info.id)-a.jpg") { $info.avatar = "$Dir\ch-$($info.id)-a.jpg" }
    if (Test-Path "$Dir\ch-$($info.id)-b.jpg") { $info.banner = "$Dir\ch-$($info.id)-b.jpg" }
    $info
}
function Get-BannerCrop([string]$src, [int]$cols, [int]$rows) {
    # faixa central do banner com a proporção da área no ecrã (célula ~ 1:2,3)
    $dst = $src -replace '\.jpg$', "-$cols-$rows.jpg"
    if (Test-Path $dst) { return $dst }
    try {
        Add-Type -AssemblyName System.Drawing
        $img = [Drawing.Image]::FromFile($src)
        $ratio = $cols / ($rows * 2.3)
        $h = [int][Math]::Min($img.Height, $img.Width / $ratio); $w = [int][Math]::Min($img.Width, $h * $ratio)
        $bmp = [Drawing.Bitmap]::new($w, $h); $g = [Drawing.Graphics]::FromImage($bmp)
        $g.DrawImage($img, [Drawing.Rectangle]::new(0, 0, $w, $h), [Drawing.Rectangle]::new([int](($img.Width - $w) / 2), [int](($img.Height - $h) / 2), $w, $h), [Drawing.GraphicsUnit]::Pixel)
        $bmp.Save($dst, [Drawing.Imaging.ImageFormat]::Jpeg); $g.Dispose(); $bmp.Dispose(); $img.Dispose()
        $dst
    } catch { $src }
}

# ---------- desenho ----------
# linhas 1-3: logótipo | barra de pesquisa | conta;  linha 5: separadores;  grelha a partir de $L.top
# canal: banner (linhas 5-9), avatar + nome + info (11-15), separadores do canal (17), grelha (19)
function Fit([string]$s, [int]$w) { if ($w -le 1) { return '' }; if ($s.Length -le $w) { $s.PadRight($w) } else { $s.Substring(0, $w - 1) + [char]0x2026 } }
function Wrap2([string]$s, [int]$w) {
    # texto em 2 linhas, partido por palavras; reticências se não couber
    $l1 = ''
    foreach ($word in $s -split ' ') { if (($l1 + ' ' + $word).Trim().Length -le $w) { $l1 = ($l1 + ' ' + $word).Trim() } else { break } }
    if (-not $l1) { $l1 = $s.Substring(0, [Math]::Min($w, $s.Length)) }
    @($l1.PadRight($w), (Fit $s.Substring([Math]::Min($s.Length, $l1.Length)).Trim() $w))
}
function Show-Status([string]$msg) { [Console]::Write("$e[$([Console]::WindowHeight);4H$e[2K$e[90m$msg$e[0m") }
function Get-Layout($s) {
    $W = [Console]::WindowWidth; $H = [Console]::WindowHeight
    $chan = $s -and $s.mode -eq 'channel'
    $top = if ($chan) { 11 } else { 7 }
    # como o YouTube: cartoes largos (~44+ colunas: 4 numa janela inteira), miniatura em 16:9 a serio (pela proporcao real
    # da celula), e por baixo barra + titulo em 2 linhas + canal + visualizacoes/data (cada cartao: TH + 6 linhas)
    $gap = 3; $mar = 3
    $cols = [Math]::Max(1, [Math]::Min(6, [Math]::Floor(($W - 2 * $mar + $gap) / (40 + $gap))))
    $room = $H - $top - 1   # (ultima linha: rodape)
    # mais colunas (cartoes mais pequenos) ate caberem 2 filas, como no YouTube (com 1 fila sobrava meio ecra)
    while ($true) {
        $TW = [Math]::Floor(($W - 2 * $mar - ($cols - 1) * $gap) / $cols)
        $TH = [Math]::Max(4, [int][Math]::Round($TW * 9 / 16 * $CellRatio))
        if ($cols -ge 6 -or 2 * ($TH + 6) -le $room) { break }
        $cols++
    }
    # nao cabe nem uma fila: miniaturas mais baixas (e mais estreitas, para manter os 16:9)
    if ($TH + 6 -gt $room) { $TH = [Math]::Max(4, $room - 6); $TW = [Math]::Min($TW, [int][Math]::Round($TH * 16 / 9 / $CellRatio)) }
    $rows = [Math]::Max(1, [Math]::Floor($room / ($TH + 6)))
    $bw = [Math]::Max(30, [Math]::Min(72, $W - 64))
    $gw = $cols * ($TW + $gap) - $gap
    $left = [Math]::Max($mar, [Math]::Floor(($W - $gw) / 2) + 1)   # grelha centrada
    @{ W = $W; H = $H; TW = $TW; TH = $TH; cols = $cols; rows = $rows; per = $cols * $rows; bw = $bw; bc = [Math]::Floor(($W - $bw) / 2); left = $left; gw = $gw; top = $top; gap = $gap }
}
# 1.o video a mostrar: a grelha anda por filas (como o scroll do YouTube), nao por paginas inteiras. $s.top = 1.a fila
# visivel; muda so quando a selecao sai do que se ve (setas) ou com a roda (Move-Rows)
function Get-Start($s, $L) {
    if ($null -eq $s.top) { $s.top = 0 }
    $row = [Math]::Floor($s.sel / $L.cols)
    if ($row -lt $s.top) { $s.top = $row } elseif ($row -ge $s.top + $L.rows) { $s.top = $row - $L.rows + 1 }
    $s.top * $L.cols
}
# roda: n filas para baixo (ou para cima, se negativo); a selecao vem junto para ficar a vista
function Move-Rows($s, $L, [int]$n) {
    $last = [Math]::Max(0, [Math]::Ceiling($s.vids.Count / $L.cols) - $L.rows)
    $null = Get-Start $s $L; $s.top = [Math]::Max(0, [Math]::Min($last, $s.top + $n))
    $row = [Math]::Floor($s.sel / $L.cols); $col = $s.sel % $L.cols
    $row = [Math]::Max($s.top, [Math]::Min($s.top + $L.rows - 1, $row))
    $s.sel = [Math]::Min($s.vids.Count - 1, $row * $L.cols + $col)
}
function Get-TilePos([int]$slot, $L) { @{ r = $L.top + [Math]::Floor($slot / $L.cols) * ($L.TH + 6); c = $L.left + ($slot % $L.cols) * ($L.TW + $L.gap) } }
function Draw-Header($L, [string]$q, [bool]$focus) {
    $h = [string][char]0x2500; $bc = if ($focus -or $script:HoverSearch) { '0;37' } else { '0;90' }; $in = $L.bw - 7   # (rato por cima: acende)   # "│ " + ícone + "  " + texto + " │" = bw
    $text = if ($focus) { ''.PadRight($in) } elseif ($q) { "$e[37m" + (Fit $q $in) } else { "$e[90m" + 'search'.PadRight($in) }
    $acct = if (Get-CookieArgs) { '' } else { "$e[90m$([char]0xf007)  sign in $e[37ml" }   # com sessão iniciada não mostra nada
    [Console]::Write(
        "$e[2;$($L.left)H$e[1;31m$([char]0xf16a) $e[1;97mYouTube$e[0m" +
        "$e[1;$($L.bc)H$e[${bc}m$([char]0x256D)" + ($h * ($L.bw - 2)) + "$([char]0x256E)" +
        "$e[2;$($L.bc)H$([char]0x2502) $e[90m$([char]0xf002)  $text$e[${bc}m $([char]0x2502)" +
        "$e[3;$($L.bc)H$([char]0x2570)" + ($h * ($L.bw - 2)) + "$([char]0x256F)$e[0m" +
        "$e[2;$($L.W - $L.left - 11)H$acct$e[0m")
}
function Chips($items, [string]$active) {
    ($items | ForEach-Object { if ($_.m -eq $active) { "$e[48;2;171;178;191;30m $($_.n) $e[0m  " } else { "$e[48;2;62;68;81;37m $($_.n) $e[0m  " } }) -join ''
}
function Get-Count($s) {
    # "video selecionado / total" (+ = ainda ha mais para carregar); com largura fixa para nao deixar restos ao encolher
    if ($s.vids.Count -lt 2) { return '' }
    "$($s.sel + 1) / $($s.vids.Count)$(if (-not $s.done -and $s.src) { '+' } else { ' ' })".PadLeft(11)
}
function Draw-Count($s, $L) {
    $c = Get-Count $s; if (-not $c) { return }
    [Console]::Write("$e[$(if ($s.mode -eq 'channel') { 9 } else { 5 });$($L.W - $L.left - $c.Length + 1)H$e[90m$c$e[0m")
}
function Draw-Tabs($s, $L, [string]$pageInfo) {
    $out = "$e[5;1H$e[2K$e[5;$($L.left)H" + (Chips $Tabs $s.mode)
    if ($s.mode -eq 'search') { $out += "$e[90m$([char]0x203A)  $e[48;2;171;178;191;30m $($s.label) $e[0m" }
    if ($pageInfo) { $out += "$e[5;$($L.W - $L.left - $pageInfo.Length + 1)H$e[90m$pageInfo$e[0m" }
    [Console]::Write($out)
}
function Draw-Channel($s, $L, [string]$pageInfo) {
    # cabeçalho compacto do canal: avatar pequeno, nome, @handle · subscritores, e os separadores do canal
    $i = $s.info; $out = ''; $tx = $L.left
    if ($i.avatar) { $out += "$e[5;$($L.left)H" + (Get-Img $i.avatar 7 3); $tx = $L.left + 10 }
    $subs = Format-Num $i.subs
    $meta = @($i.handle, $(if ($subs) { "$subs subscribers" })) | Where-Object { $_ -and $_ -ne 'NA' }
    $out += "$e[5;${tx}H$e[1;97m$($i.name)$e[0m" + "$e[6;${tx}H$e[90m" + ($meta -join "  $([char]0x00B7)  ") + "$e[0m"
    $out += "$e[9;$($L.left)H" + (Chips $ChanTabs $s.ctab)
    if ($pageInfo) { $out += "$e[9;$($L.W - $L.left - $pageInfo.Length + 1)H$e[90m$pageInfo$e[0m" }
    [Console]::Write($out)
}function Draw-TileText($v, [int]$slot, $L, [bool]$sel) {
    $p = Get-TilePos $slot $L; $TW = $L.TW; $TH = $L.TH
    $t = Wrap2 $v.t $TW
    $seen = $Watched.Contains($v.id)
    $dot = " $([char]0x00B7) "
    $ch = if ($v.ch -and $v.ch -ne 'NA') { $v.ch } else { '' }
    # como o YouTube: o canal numa linha, "visualizacoes · ha quanto tempo" na seguinte (abreviado so se nao couber)
    $views = Format-Num $v.v
    $stats = (@($(if ($views) { "$views views" }), (Format-Ago $v.ts)) | Where-Object { $_ }) -join $dot
    if ($stats.Length -gt $TW) { $stats = (@($views, (Format-Ago $v.ts -Short)) | Where-Object { $_ }) -join $dot }
    $tc = if ($sel) { '1;97' } elseif ($seen) { '0;90' } else { '1;37' }; $mc = if ($sel) { '0;37' } else { '0;90' }
    # barra por baixo da thumbnail: vermelha = selecionado; vermelho escuro = já visto (como a barra de progresso do YouTube)
    $bar = if ($sel) { "$e[31m" + ([string][char]0x2501 * $TW) } elseif ($seen) { "$e[38;2;190;80;70m" + ([string][char]0x2501 * $TW) } else { ' ' * $TW }
    [Console]::Write(
        (Get-DurBadge $v $p $L) +
        "$e[$($p.r + $TH);$($p.c)H$bar" +
        "$e[$($p.r + $TH + 1);$($p.c)H$e[${tc}m$($t[0])$e[$($p.r + $TH + 2);$($p.c)H$($t[1])" +
        "$e[$($p.r + $TH + 3);$($p.c)H$e[${mc}m$(Fit $ch $TW)" +
        "$e[$($p.r + $TH + 4);$($p.c)H$e[90m$(Fit $stats $TW)$e[0m")
}
# duracao por cima da miniatura, no canto de baixo (fundo escuro, como no YouTube; "live" a vermelho). Escrever texto
# por cima tira a imagem dessas celulas: e desenhada outra vez depois da imagem (Update-Pending)
function Get-DurBadge($v, $p, $L) {
    if (-not $v.dur) { return '' }
    $d = " $($v.dur) "; $c = if ($v.dur -eq 'live') { "$e[48;2;204;0;0;1;97m" } else { "$e[48;2;15;15;15;1;97m" }
    "$e[$($p.r + $L.TH - 1);$($p.c + $L.TW - $d.Length - 1)H$c$d$e[0m"
}
function Draw-Page($s) {
    $dsw = [Diagnostics.Stopwatch]::StartNew(); Trace 'draw-page'
    $script:L = Get-Layout $s; $L = $script:L
    Get-Job -Name yt -ErrorAction SilentlyContinue | Where-Object State -eq 'Completed' | Remove-Job -ErrorAction SilentlyContinue; Clear-Ck
    if ($L.W -lt 70 -or $L.H -lt 22) {
        # painel demasiado pequeno (ex.: split estreito): aviso ao centro; volta sozinho quando se aumenta
        $m1 = 'window too small'; $m2 = "enlarge the pane (min 70×22; now $($L.W)×$($L.H))"
        [Console]::Write("$e[2J$e[$([Math]::Floor($L.H / 2));$([Math]::Max(1, [Math]::Floor(($L.W - $m1.Length) / 2)))H$e[1;97m$m1$e[$([Math]::Floor($L.H / 2) + 1);$([Math]::Max(1, [Math]::Floor(($L.W - $m2.Length) / 2)))H$e[0;90m$m2$e[0m")
        return
    }
    Update-Watched
    $vids = $s.vids; $start = Get-Start $s $L; $page = [Math]::Floor($start / $L.per)
    $pages = [Math]::Max(1, [Math]::Ceiling($vids.Count / $L.per))
    $pi = Get-Count $s
    # tamanho das imagens, para o prefetch em segundo plano (perfil) as gerar já neste tamanho
    if ($script:SavedLayout -ne "$($L.TW) $($L.TH) $($L.per)") { $script:SavedLayout = "$($L.TW) $($L.TH) $($L.per)"; [IO.File]::WriteAllText("$Dir\layout.txt", $script:SavedLayout) }
    # imagens em falta: geradas em paralelo (3 por thread) e desenhadas à medida que ficam prontas (Update-Pending)
    $pageIds = @($vids | Select-Object -Skip $start -First $L.per | ForEach-Object id)
    $missing = @($pageIds | Where-Object { -not (Test-Six $_ $L) })
    for ($i = 0; $i -lt $missing.Count; $i += 3) { Start-SixelJob $missing[$i..([Math]::Min($i + 2, $missing.Count - 1))] $L }
    $script:Pending = [Collections.Generic.List[object]]::new()
    # tudo num só bloco, com "synchronized output" (o terminal mostra o ecrã já completo: sem piscar)
    [Console]::Write("$e[?2026h$e[2J")
    Draw-Header $L $s.q $false
    if ($s.mode -eq 'channel') { Draw-Channel $s $L $pi } else { Draw-Tabs $s $L $pi }
    $sb = [Text.StringBuilder]::new()
    $ph = "$e[48;2;44;49;58m" + (' ' * $L.TW) + "$e[0m"
    for ($i = 0; $i -lt $pageIds.Count; $i++) {
        $p = Get-TilePos $i $L
        if (Test-Six $pageIds[$i] $L) { [void]$sb.Append("$e[$($p.r);$($p.c)H").Append((Get-Sixel $pageIds[$i] $L)) }
        else { for ($q = 0; $q -lt $L.TH; $q++) { [void]$sb.Append("$e[$($p.r + $q);$($p.c)H$ph") }; $script:Pending.Add(@{ i = $i; id = $pageIds[$i]; v = $vids[$start + $i] }) }
    }
    [Console]::Write($sb.ToString())
    for ($i = 0; $i -lt $pageIds.Count; $i++) { Draw-TileText $vids[$start + $i] $i $L ($start + $i -eq $s.sel) }
    Draw-Footer $L; [Console]::Write("$e[?2026l"); Trace "draw-page fim $($dsw.ElapsedMilliseconds) ms ($($script:Pending.Count) imagens por chegar)"
    # prepara as imagens das páginas vizinhas
    $ids = @($vids | Select-Object -Skip ($start + $L.per) -First $L.per | ForEach-Object id) + @($vids | Select-Object -Skip ([Math]::Max(0, $start - $L.per)) -First ([Math]::Min($start, $L.per)) | ForEach-Object id)
    $ids = @($ids | Where-Object { -not (Test-Six $_ $L) })
    if ($ids) { Start-SixelJob $ids $L }
    # perto do fim da lista: pede já os vídeos seguintes, para o "scroll infinito" não ter de esperar
    if (-not $s.done -and $s.src -and $start + 2 * $L.per -ge $vids.Count -and $s.aheadFrom -ne $vids.Count + 1) {
        $s.aheadFrom = $vids.Count + 1; Start-ListJob "more-$($s.mode)" $s.src 45 @(Get-CookieArgs) '' $s.aheadFrom; $s.ahead = $Jobs["more-$($s.mode)"]
    }
}
# a grelha andou exatamente uma fila: o terminal desliza o que ja la esta (regiao de scroll) e so se desenha a fila
# nova (metade das imagens, sem limpar o ecra). Devolve $false se nao der (e entao redesenha-se tudo)
function Scroll-Grid($s, $L, [int]$dir) {
    if ($env:YT_NOSCROLL) { return $false }
    $h = $L.TH + 6; $top = $L.top; $bot = $L.top + $L.rows * $h - 1
    $start = Get-Start $s $L
    $o = "$e[?2026h$e[$top;${bot}r$e[$top;1H" + $(if ($dir -gt 0) { "$e[$($h)S" } else { "$e[$($h)T" }) + "$e[r"
    $row = if ($dir -gt 0) { $L.rows - 1 } else { 0 }
    $script:Pending = [Collections.Generic.List[object]]::new()
    $ph = "$e[48;2;44;49;58m" + (' ' * $L.TW) + "$e[0m"
    for ($c = 0; $c -lt $L.cols; $c++) {
        $slot = $row * $L.cols + $c; $i = $start + $slot; $p = Get-TilePos $slot $L
        if ($i -ge $s.vids.Count) { continue }
        $id = $s.vids[$i].id
        if (Test-Six $id $L) { $o += "$e[$($p.r);$($p.c)H" + (Get-Sixel $id $L) }
        else { for ($q = 0; $q -lt $L.TH; $q++) { $o += "$e[$($p.r + $q);$($p.c)H$ph" }; $script:Pending.Add(@{ i = $slot; id = $id; v = $s.vids[$i] }) }
    }
    [Console]::Write($o)
    for ($c = 0; $c -lt $L.cols; $c++) { $slot = $row * $L.cols + $c; if ($start + $slot -lt $s.vids.Count) { Draw-TileText $s.vids[$start + $slot] $slot $L ($start + $slot -eq $s.sel) } }
    [Console]::Write("$e[?2026l")
    $true
}
function Update-Pending {
    # desenha as imagens da página que entretanto ficaram prontas
    if (-not $script:Pending -or -not $script:Pending.Count) { return }
    $o = ''; $now = [Environment]::TickCount64
    foreach ($x in @($script:Pending)) {
        $k = "$($x.id)-$($L.TW)-$($L.TH)-s"
        if (-not $x.t) { $x.t = $now; $x.n = 0 }
        # a imagem ja foi descarregada mas o thread nao a chegou a preparar (ex.: esperou 5 s por outro e desistiu):
        # prepara-a aqui; sem imagem ao fim de 3 s e sem ninguem a descarrega-la, pede-a outra vez (ate 3 vezes)
        if (-not $Sixel.ContainsKey($k) -and $now - $x.t -gt 1500) {
            if ([IO.File]::Exists("$Dir\$($x.id)-hq.jpg")) { [void](Get-Sixel $x.id $L) }
            elseif ($now - $x.t -gt 3000 -and $x.n -lt 3 -and -not $ThumbBusy.ContainsKey($x.id)) { Start-SixelJob @($x.id) $L; $x.t = $now; $x.n++ }
        }
        if ($Sixel.ContainsKey($k)) { $p = Get-TilePos $x.i $L; $o += "$e[$($p.r);$($p.c)H" + $Sixel[$k] + (Get-DurBadge $x.v $p $L); [void]$script:Pending.Remove($x) }
    }
    if ($o) { [Console]::Write($o) }
}
# tecla desenhada como "chip" (o mesmo estilo da caixa de comandos do terminal)
function Key-Chip([string]$k) { "$e[48;2;62;68;81;97m $k $e[0m" }
# rodape: os atalhos principais, sempre visiveis
function New-Key($ch, $key, [switch]$Shift) { [ConsoleKeyInfo]::new([char]$ch, [ConsoleKey]$key, [bool]$Shift, $false, $false) }
# rodape (tecla, texto, tecla equivalente para o clique)
$FooterItems = @(
    @('enter', 'watch', (New-Key "`r" 'Enter')), @('a', 'audio', (New-Key 'a' 'A')), @('/', 'search', (New-Key '/' 'Oem2')),
    @('c', 'channel', (New-Key 'c' 'C')), @('tab', 'tabs', (New-Key "`t" 'Tab')), @('?', 'all shortcuts', (New-Key '?' 'Oem2' -Shift))
)
# WezTerm: os atalhos vao para a barra de baixo do proprio terminal (user var "hints" = "tecla|texto;..."), em vez
# de um rodape aqui; vazio = a barra volta as teclas do shell (ao sair do yt)
function Set-Hints([string]$s) { if ($env:WEZTERM_PANE) { [Console]::Write("$e]1337;SetUserVar=hints=$([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s)))$([char]7)") } }
$WatchHints = "space|pause;$([char]0x2190)$([char]0x2192)|seek;f|full screen;$([char]0x2191)$([char]0x2193)|up next;enter|play;?|shortcuts;esc|back"
function Draw-Footer($L) {
    if ($env:WEZTERM_PANE) { Set-Hints (($FooterItems | ForEach-Object { "$($_[0])|$($_[1])" }) -join ';'); return }
    $out = "$e[$($L.H);1H$e[2K$e[$($L.H);$($L.left)H"
    foreach ($x in $FooterItems) { $out += (Key-Chip $x[0]) + " $e[90m$($x[1])$e[0m   " }
    [Console]::Write($out)
}
function Convert-Mouse([int]$m, $cur, $L) {
    # clique / roda do rato -> a tecla equivalente (o resto do ciclo trata dela como se viesse do teclado)
    # roda: F23 / F22 = descer / subir $script:WheelRows filas (cada evento da roda = 1 fila, como o scroll do YouTube)
    if ($m -eq 2) { $script:WheelRows = [Math]::Abs([Yt.Con]::Wheel); if ([Yt.Con]::Wheel -lt 0) { return New-Key 0 'F23' } else { return New-Key 0 'F22' } }
    $x = [Yt.Con]::MouseX + 1; $y = [Yt.Con]::MouseY + 1
    $onSearch = $y -le 3 -and $x -ge $L.bc -and $x -lt $L.bc + $L.bw
    if ($m -eq 3) {
        # hover: a barra de pesquisa acende; um video fica selecionado (como com as setas: barra vermelha, titulo branco)
        if ($onSearch -ne [bool]$script:HoverSearch) { $script:HoverSearch = $onSearch; Draw-Header $L $cur.q $false }
        $start = Get-Start $cur $L
        for ($i = 0; $i -lt $L.per -and $start + $i -lt $cur.vids.Count; $i++) {
            $p = Get-TilePos $i $L
            if ($x -ge $p.c -and $x -lt $p.c + $L.TW -and $y -ge $p.r -and $y -le $p.r + $L.TH + 4) {
                if ($start + $i -ne $cur.sel) { $script:HoverSel = $start + $i; return New-Key 0 'F21' }
                break
            }
        }
        return $null
    }
    if ($onSearch) { return New-Key '/' 'Oem2' }   # barra de pesquisa
    if ($y -eq 5 -and $cur.mode -ne 'channel') {
        # separadores: " nome " + 2 espacos cada (como em Chips); 1-4 = a tecla de cada um
        $c = $L.left
        for ($i = 0; $i -lt $Tabs.Count; $i++) { $w = $Tabs[$i].n.Length + 2; if ($x -ge $c -and $x -lt $c + $w) { return New-Key "$($i + 1)" "D$($i + 1)" }; $c += $w + 2 }
        return $null
    }
    if ($y -eq $L.H) {
        $c = $L.left
        foreach ($f in $FooterItems) { $w = $f[0].Length + 2 + 1 + $f[1].Length + 3; if ($x -ge $c -and $x -lt $c + $w) { return $f[2] }; $c += $w }
        return $null
    }
    # um video (miniatura ou textos): abre, como no YouTube
    $start = Get-Start $cur $L
    for ($i = 0; $i -lt $L.per -and $start + $i -lt $cur.vids.Count; $i++) {
        $p = Get-TilePos $i $L
        if ($x -ge $p.c -and $x -lt $p.c + $L.TW -and $y -ge $p.r -and $y -le $p.r + $L.TH + 4) { $cur.sel = $start + $i; return New-Key "`r" 'Enter' }
    }
    $null
}
function Show-Help($L) {
    # painel com fundo proprio (antes o texto ficava por cima da grelha, misturado com os titulos)
    $groups = @(
        @('browse', @(@('arrows', 'move'), @('tab  1-4', 'home / subscriptions / watch later / history'), @('/  s  ctrl+f', 'search'), @('c', 'channel of the selected video'), @('esc', 'go back'))),
        @('watch', @(@('enter', 'video page (plays here)'), @('o', 'open in its own window'), @('a', 'audio only (music)'))),
        @('in a channel', @(, @('tab  1-3', 'videos / shorts / live'))),   # (", @(...)": uma so linha nao se desfaz)
        @('app', @(@('r', 'reload'), @('l', 'account (sign in)'), @('q', 'quit')))
    )
    $kw = 16; $w = 70
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($g in $groups) {
        $lines.Add("$e[1;31m$($g[0])$e[0m")
        foreach ($x in $g[1]) { $lines.Add((($x[0] -split '  ' | ForEach-Object { Key-Chip $_ }) -join ' ') + '|' + $x[1]) }
        $lines.Add('')
    }
    $lines.RemoveAt($lines.Count - 1)
    $hgt = $lines.Count + 4; $top = [Math]::Max(2, [Math]::Floor(($L.H - $hgt) / 2)); $lc = [Math]::Floor(($L.W - $w) / 2)
    $bg = "$e[48;2;33;37;43m"; $bd = "$e[38;2;92;99;112m"; $h = [string][char]0x2500
    $out = "$e[$top;${lc}H$bg$bd$([char]0x256D)$h $e[1;97mshortcuts $bd" + ($h * ($w - 14)) + "$([char]0x256E)$e[0m"
    $r = $top + 1
    $blank = "$bg$bd$([char]0x2502)$e[0m$bg" + (' ' * ($w - 2)) + "$bd$([char]0x2502)$e[0m"
    $out += "$e[$r;${lc}H$blank"; $r++
    foreach ($ln in $lines) {
        $out += "$e[$r;${lc}H$blank$e[$r;$($lc + 3)H$bg"
        if ($ln -match '\|') { $k, $d = $ln -split '\|', 2; $out += "$k$bg$e[$r;$($lc + 3 + $kw + 2)H$e[37m$d$e[0m" } else { $out += "$ln" }
        $r++
    }
    $out += "$e[$r;${lc}H$blank"; $r++
    $out += "$e[$r;${lc}H$bg$bd$([char]0x2570)" + ($h * ($w - 2)) + "$([char]0x256F)$e[0m"
    [Console]::Write($out); [void](Read-Key)
}
$SearchFile = "$HOME\.config\yt-searches.txt"
function Get-SearchHistory { if (Test-Path $SearchFile) { @(Get-Content $SearchFile -Encoding utf8 | Where-Object { $_ }) } else { @() } }
function Add-SearchHistory([string]$q) {
    # mais recente primeiro, sem repetidos, até 100
    $h = @($q) + @(Get-SearchHistory | Where-Object { $_ -ne $q }) | Select-Object -First 100
    Set-Content $SearchFile $h -Encoding utf8
}
$SuggHttp = [Net.Http.HttpClient]::new(); $SuggHttp.Timeout = [TimeSpan]::FromSeconds(3); $SuggCache = @{}
function Read-Search($L, [string]$q, [scriptblock]$Under) {
    # editor próprio dentro da barra do topo; por baixo, como no YouTube: as últimas pesquisas (relógio) e as
    # sugestões do próprio YouTube (lupa), pedidas em segundo plano enquanto se escreve (nunca atrasam as teclas)
    #   escrever filtra | ↑ ↓ escolher | tab completar | enter pesquisar | del apagar do histórico | esc cancelar
    Draw-Header $L '' $true
    $in = $L.bw - 7; $buf = ''; $sel = -1; $hist = Get-SearchHistory; $shown = 0; $task = $null; $taskQ = $null
    $bg = "$e[49m"   # (fundo do terminal: o mesmo da barra)
    while ($true) {
        # pedido ao YouTube para o texto atual (uma vez por texto; respostas guardadas)
        $qk = $buf.Trim()
        if ($qk -and -not $SuggCache.ContainsKey($qk) -and $taskQ -ne $qk) {
            $taskQ = $qk; $task = $SuggHttp.GetStringAsync("https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&hl=$((Get-Culture).TwoLetterISOLanguageName)&q=$([uri]::EscapeDataString($qk))")
        }
        $mine = @(@(if ($buf) { $hist | Where-Object { $_.IndexOf($buf, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and $_ -ne $buf } | Select-Object -First 3 } else { $hist | Select-Object -First 8 }))
        $yt = @(if ($qk -and $SuggCache.ContainsKey($qk)) { $SuggCache[$qk] | Where-Object { $_ -notin $mine } })
        $sugg = @(@($mine) + @($yt) | Select-Object -First 10)   # @(): com 1 sugestão continua a ser lista (senão o Tab apanhava só a 1.ª letra)
        if ($sel -ge $sugg.Count) { $sel = $sugg.Count - 1 }
        $vis = if ($buf.Length -gt $in - 1) { $buf.Substring($buf.Length - $in + 1) } else { $buf }
        $o = "$e[?2026h$e[2;$($L.bc + 5)H$e[0;97m$vis$e[7m $e[0m" + (' ' * [Math]::Max(0, $in - $vis.Length - 1))
        # painel por baixo da barra, so com as sugestoes que houver (nenhuma = nada, como no YouTube); a encolher,
        # $Under redesenha o que estava por baixo (a grelha) e a barra ativa
        # (a lista continua a caixa da barra: o fundo dela passa a ├──┤ e a caixa fecha por baixo das sugestoes)
        $r = 4; $rows = $sugg.Count; $need = $rows + [int][bool]$rows; $hz = [string][char]0x2500; $sd = "$e[0;37m$([char]0x2502)"
        if ($need -lt $shown -and $Under) { & $Under; Draw-Header $L '' $true }
        $o += "$e[3;$($L.bc)H$e[0;37m" + $(if ($rows) { "$([char]0x251C)" + ($hz * ($L.bw - 2)) + "$([char]0x2524)" } else { "$([char]0x2570)" + ($hz * ($L.bw - 2)) + "$([char]0x256F)" }) + "$e[0m"
        if ($rows) { $o += "$e[$($r + $rows);$($L.bc)H$e[0;37m$([char]0x2570)" + ($hz * ($L.bw - 2)) + "$([char]0x256F)$e[0m" }
        for ($i = 0; $i -lt $rows; $i++) {
            if ($i -lt $sugg.Count) {
                $m = $sugg[$i]; $ic = if ($i -lt $mine.Count) { [char]0xf017 } else { [char]0xf002 }
                # (a parte ja escrita a normal, o resto a negrito: como o YouTube)
                $txt = Fit $m ($L.bw - 8)
                $hl = if ($buf -and $txt.StartsWith($buf, [StringComparison]::OrdinalIgnoreCase)) { $txt.Substring(0, $buf.Length) + "$e[1m" + $txt.Substring($buf.Length) } else { $txt }
                $rowBg = if ($i -eq $sel) { "$e[48;2;62;68;81m" } else { $bg }
                $o += "$e[$($r + $i);$($L.bc)H$sd$rowBg$e[90m $ic  $e[22;97m$hl$e[22m$rowBg" + (' ' * [Math]::Max(0, $L.bw - 6 - $txt.Length)) + "$e[0m$sd$e[0m"
            } else { $o += "$e[$($r + $i);$($L.bc)H$bg" + (' ' * $L.bw) + "$e[0m" }
        }
        $shown = $rows + [int][bool]$rows
        [Console]::Write("$o$e[?2026l")
        # espera por tecla; entretanto, chegou a resposta do YouTube -> redesenha
        $k = $null
        while (-not [Console]::KeyAvailable) {
            if ($task -and $task.IsCompleted) {
                if ($task.Status -eq 'RanToCompletion') { try { $SuggCache[$taskQ] = @((ConvertFrom-Json $task.Result)[1]) } catch { $SuggCache[$taskQ] = @() } } else { $SuggCache[$taskQ] = @() }
                $done = $taskQ; $task = $null; $taskQ = $null
                if ($done -eq $buf.Trim()) { break }
            }
            Start-Sleep -Milliseconds 20
        }
        if (-not [Console]::KeyAvailable) { continue }
        $k = Read-Key
        switch ($k.Key) {
            'Enter'     { $res = if ($sel -ge 0) { $sugg[$sel] } else { $buf.Trim() }; if ($res) { Add-SearchHistory $res }; return $res }
            'Escape'    { return '' }
            'DownArrow' { if ($sel -lt $sugg.Count - 1) { $sel++ }; continue }
            'UpArrow'   { if ($sel -ge 0) { $sel-- }; continue }
            'Tab'       { if ($sel -ge 0) { $buf = $sugg[$sel]; $sel = -1 } elseif ($sugg.Count) { $buf = $sugg[0] }; continue }
            'Delete'    { if ($sel -ge 0 -and $sel -lt $mine.Count) { $hist = @($hist | Where-Object { $_ -ne $sugg[$sel] }); Set-Content $SearchFile $hist -Encoding utf8 }; continue }
            'Backspace' { if ($buf.Length) { $buf = $buf.Substring(0, $buf.Length - 1) }; $sel = -1; continue }
        }
        if ([int]$k.KeyChar -ge 32) { $buf += $k.KeyChar; $sel = -1 }
    }
}
# ---------- reprodução ----------
function Invoke-Play($v) {
    # janela normal do mpv (tecla o, ou painel pequeno / split / SSH). Uma só por yt: se já houver uma aberta,
    # o vídeo novo abre nela (Enter repetido ou teclas acumuladas já não abrem dezenas de janelas)
    $url = "https://youtu.be/$($v.id)"
    # marcar como visto: aqui e na conta do YouTube (pedido à parte, em segundo plano)
    if ($Watched.Add($v.id)) { Add-Content $WatchedFile $v.id }
    $ck = Get-CookieArgs
    if ($ck) { $null = Start-Yt (@($url, '--mark-watched', '--simulate', '--no-warnings', '--quiet', '--ignore-no-formats-error', '--extractor-args', 'youtube:player_client=web_safari;fetch_pot=never') + $ck) }
    if ($script:WinMp -and -not $script:WinMp.HasExited) {
        Send-Mpv 'change-list', 'script-opts', 'append', "yt-url=$url" -Pipe $script:WinPipe   # menu de qualidade: o vídeo novo
        Send-Mpv 'loadfile', $url -Pipe $script:WinPipe; return
    }
    $script:WinPipe = "ytmpv-$PID-w$((++$script:MpvN))"
    $script:WinMp = Start-Process $MpvWin -PassThru -ArgumentList (Quote-Args (@("--input-ipc-server=\\.\pipe\$script:WinPipe", "--script-opts-append=yt-url=$url", (New-MpvLog)) + $MpvOpts + (Get-PlayOpts) + $url))
}

# ---------- página do vídeo (como no YouTube) ----------
# vídeo à esquerda (mpv sem bordas encaixado nessa área), título/canal/descrição/comentários por baixo, "a seguir" à direita.
# O teclado fica no terminal e comanda o mpv pelo canal IPC (\\.\pipe\ytmpv-<pid>).
$MpvPipe = "ytmpv-$PID"   # muda a cada arranque do mpv (ytmpv-<pid>-<n>): um mpv antigo ainda a fechar não apanha comandos do novo
$IsWT = $null
function Get-WezGeom {
    # WezTerm: janela do processo wezterm-gui dono deste painel; celula e tamanho do painel pela CLI dele (pixels reais).
    # O yt corre com o painel ampliado (Invoke-Zoomed): o painel comeca no canto da area de conteudo, depois do padding
    # (16, 12 na config, escalado pelo DPI) e da barra de separadores (so com 2+ separadores)
    $wz = Join-Path (Split-Path $env:WEZTERM_EXECUTABLE) 'wezterm.exe'
    $all = @(& $wz cli list --format json 2>$null | ConvertFrom-Json); $me = $all | Where-Object pane_id -eq ([int]$env:WEZTERM_PANE)
    if (-not $me -or -not $me.size.pixel_width) { return $null }
    $gp = Get-Process -Id $PID; while ($gp -and $gp.ProcessName -ne 'wezterm-gui') { $gp = $gp.Parent }
    if (-not $gp) { return $null }
    $h = [Yt.Win]::FindWez([uint32]$gp.Id); if ($h -eq [IntPtr]::Zero) { return $null }
    $o = New-Object Yt.Win+P; [void][Yt.Win]::ClientToScreen($h, [ref]$o)
    $scale = [Yt.Win]::GetDpiForWindow($h) / 96
    $cw = $me.size.pixel_width / $me.size.cols; $ch = $me.size.pixel_height / $me.size.rows
    $tabs = @($all | Where-Object window_id -eq $me.window_id | ForEach-Object tab_id | Select-Object -Unique).Count
    @{ x = $o.X + 16 * $scale; y = $o.Y + 12 * $scale;   # (a barra de separadores esta em baixo: nao empurra o painel)
    cw = $cw; ch = $ch; wt = $h }
}
function Get-WinGeom {
    [void][Yt.Win]::SetProcessDpiAwarenessContext([IntPtr]-4)
    if ($env:WEZTERM_PANE -and $env:WEZTERM_EXECUTABLE -and -not $env:SSH_CONNECTION) { return Get-WezGeom }
    if ($null -eq $script:IsWT) { $script:IsWT = (Get-Process -Id $PID).Parent.ProcessName -eq 'WindowsTerminal' -and -not $env:SSH_CONNECTION }
    if (-not $script:IsWT) { return $null }
    [void][Yt.Win]::SetProcessDpiAwarenessContext([IntPtr]-4)   # coordenadas em pixels reais (ecrãs com escala)
    # janela do Windows Terminal deste separador: dona da janela da pseudo-consola (GA_ROOTOWNER); com várias janelas
    # do WT o MainWindowHandle do processo podia ser outra
    $h = [Yt.Win]::GetAncestor([Yt.Win]::GetConsoleWindow(), 3)
    if ($h -eq [IntPtr]::Zero) { return $null }
    $r = New-Object Yt.Win+R; [void][Yt.Win]::GetClientRect($h, [ref]$r)
    $o = New-Object Yt.Win+P; [void][Yt.Win]::ClientToScreen($h, [ref]$o)
    $scale = [Yt.Win]::GetDpiForWindow($h) / 96
    $px = 16 * $scale; $py = 12 * $scale            # padding do perfil do Windows Terminal ("16, 12")
    $cw = ($r.Rt - 2 * $px) / [Console]::WindowWidth; $ch = ($r.B - 2 * $py) / [Console]::WindowHeight
    # split: o painel não ocupa a janela toda (células 'demasiado largas/altas') -> não dá para encaixar o vídeo
    # (numa janela inteira a célula tem ~0,4-0,5 de largura/altura; num split vertical o dobro, num horizontal metade)
    $ratio = $cw / $ch
    if ($ratio -lt 0.3 -or $ratio -gt 0.62) { return $null }
    @{ x = $o.X + $px; y = $o.Y + $py; cw = $cw; ch = $ch; wt = $h }
}
$MpvHwnd = [hashtable]::Synchronized(@{ h = [IntPtr]::Zero })   # (sem janela ainda = Zero; vazio partia o SetWindowPos)
# SetWindowPos na janela do mpv: sempre assíncrono (SWP_ASYNCWINDOWPOS), sem ativar nem mexer na ordem — o yt nunca fica
# à espera do ciclo de mensagens do mpv ou do WT
$SwpMove = 0x4214; $SwpHide = 0x4297; $SwpShow = 0x4257   # ASYNC|NOOWNERZORDER|NOACTIVATE|NOZORDER (+ NOMOVE|NOSIZE e HIDE/SHOWWINDOW)
function Set-NoFocus($p, $wtH) {
    # a janela do mpv fica "não ativável" e o foco volta ao terminal (o teclado continua no yt)
    $MpvHwnd.h = [IntPtr]::Zero
    $null = Start-ThreadJob -Name yt -ThrottleLimit 24 -ArgumentList $p, $wtH, $MpvHwnd -ScriptBlock {
        param($p, $wt, $out)
        $sw = [Diagnostics.Stopwatch]::StartNew()   # a janela só aparece quando o vídeo já toca: espera até 60 s
        while (-not $p.HasExited -and $sw.Elapsed.TotalSeconds -lt 60) {
            $p.Refresh(); $h = $p.MainWindowHandle
            if ($h -ne [IntPtr]::Zero) {
                $out.h = $h   # com dono, o .NET deixa de a ver como janela principal -> guardar já
                [void][Yt.Win]::SetWindowLong($h, -20, ([Yt.Win]::GetWindowLong($h, -20) -bor 0x08000000))   # WS_EX_NOACTIVATE
                # dono = janela do terminal: fica por cima dele (não das outras apps), no mesmo ambiente de trabalho,
                # e esconde-se/minimiza com ele
                [void][Yt.Win]::SetWindowLongPtr($h, -8, $wt)
                $fg = [Yt.Win]::GetForegroundWindow()
                if ($fg -ne $wt) {
                    $a = [Yt.Win]::GetCurrentThreadId(); $b = [Yt.Win]::GetWindowThreadProcessId($fg, [IntPtr]::Zero)
                    [void][Yt.Win]::AttachThreadInput($a, $b, $true); [void][Yt.Win]::SetForegroundWindow($wt); [void][Yt.Win]::AttachThreadInput($a, $b, $false)
                }
                return
            }
            Start-Sleep -Milliseconds 60
        }
    }
}
function Get-PlayOpts([switch]$Audio) {
    # o YouTube pode exigir sessão ("confirm you're not a bot"); com sessão, o cliente web_safari dá HLS que o mpv abre
    # (os outros clientes com sessão dão endereços com erro 403 no mpv)
    # com o servidor de PO tokens, o web_creator dá DASH até 2160p (menu de qualidade do uosc); VP9 SDR antes de AV1/HDR
    # (a GPU do portátil não descodifica AV1 por hardware). O arranque normal usa o HLS já resolvido (Start-StreamPrefetch).
    if (-not (Test-Path $CookieMaster)) { return @() }
    # cópia dos cookies só para o mpv (refeita se o original mudar, ex.: nova sessão)
    if (-not $script:MpvCk -or -not (Test-Path $script:MpvCk) -or [IO.File]::GetLastWriteTime($CookieMaster) -gt $script:MpvCkT) {
        $script:MpvCk = New-Ck; $script:MpvCkT = [datetime]::Now; $CkFiles.Add(@{ f = $script:MpvCk; p = $null })
    }
    $ckf = $script:MpvCk
    if ($Audio -or -not (Test-Path $PotDir)) {
        return @("--ytdl-raw-options=cookies=$ckf,extractor-args=youtube:player_client=web_safari;fetch_pot=never",
          $(if ($Audio) { '--ytdl-format=bestaudio/best[protocol^=m3u8][height<=480]/best' } else { '--ytdl-format=best[protocol^=m3u8][height<=1080]/best' }))
    }
    @("--ytdl-raw-options=cookies=$ckf,extractor-args=youtube:player_client=web_creator,format-sort=[res,hdr:sdr,vcodec:vp9]",
      '--ytdl-format=bestvideo[height<=?1080]+bestaudio/best[height<=?1080]')
}
$StreamCache = [hashtable]::Synchronized(@{})   # id -> endereços diretos (vídeo + áudio) já resolvidos
function Start-StreamPrefetch([string]$id) {
    # resolve em segundo plano os endereços diretos do vídeo, para o Enter abrir sem esperar pelo yt-dlp
    # entradas válidas: a resolver ou falhada há menos de 2 min, resolvida há menos de 4 h (depois tenta-se outra vez)
    # Desligado por omissao (Kev): cada um e um yt-dlp completo (~1-2 s de CPU, ~150 MB). YT_PREFETCH=1 volta a ligar
    if (-not $id -or -not $env:YT_PREFETCH) { return }
    $c = $StreamCache[$id]
    if (($c -and $c.t -and ([datetime]::Now - $c.t).TotalMinutes -lt $(if ($c.v) { 240 } else { 2 }))) { return }
    $StreamCache[$id] = @{ busy = $true; t = [datetime]::Now }
    $null = Start-ThreadJob -Name yt -ThrottleLimit 24 -ArgumentList $YtDlp, $id, $StreamCache, $CookieMaster, $Dir -ScriptBlock {
        param($yt, $id, $cache, $master, $dir)
        $ck = $null
        if (Test-Path $master) { $ck = "$dir\ck-$([guid]::NewGuid().ToString('N')).txt"; try { [IO.File]::Copy($master, $ck, $true) } catch {} }   # cópia própria
        $auth = if ($ck) { @('--cookies', $ck, '--extractor-args', 'youtube:player_client=web_safari;fetch_pot=never') } else { @() }   # o HLS não precisa de PO token (mais rápido)
        try { $u = @(& $yt "https://youtu.be/$id" -g --no-warnings @auth -f 'best[protocol^=m3u8][height<=1080]/best' 2>$null) }
        finally { if ($ck) { try { [IO.File]::Delete($ck) } catch {} } }
        $cache[$id] = if ($u.Count -ge 1 -and $u[0] -like 'http*') { @{ v = $u[0]; a = $(if ($u.Count -ge 2) { $u[1] }); t = [datetime]::Now } } else { @{ fail = $true; t = [datetime]::Now } }
    }
}
function Get-Stream($v) {
    # endereços diretos (se já resolvidos e com menos de 4 h) ou $null -> o mpv usa o yt-dlp
    $c = $StreamCache[$v.id]
    if ($c -and $c.v -and ([datetime]::Now - $c.t).TotalHours -lt 4) { $c } else { $null }
}
function Send-Mpv([string[]]$cmd, [string]$Pipe = $MpvPipe) {
    try {
        $c = [IO.Pipes.NamedPipeClientStream]::new('.', $Pipe, [IO.Pipes.PipeDirection]::Out); $c.Connect(100)
        $w = [IO.StreamWriter]::new($c); $w.WriteLine((@{ command = $cmd } | ConvertTo-Json -Compress)); $w.Flush(); $c.Dispose()
    } catch {}
}
function Stop-Mpv($mp, [switch]$Hide, [string]$Pipe = $MpvPipe) {
    # sair sem esperar: esconde já a janela do vídeo, pede ao mpv para fechar (os scripts dele terminam bem, sem deixar
    # o mpv das miniaturas órfão) e só o mata em segundo plano se ao fim de 3 s ainda estiver aberto
    if ($Hide -and $MpvHwnd.h -ne [IntPtr]::Zero) { [void][Yt.Vd]::SetWindowPos($MpvHwnd.h, [IntPtr]::Zero, 0, 0, 0, 0, $SwpHide) }
    Send-Mpv 'quit' -Pipe $Pipe
    if ($mp -and -not $mp.HasExited) { $null = Start-ThreadJob -Name yt -ArgumentList $mp -ScriptBlock { param($p) if (-not $p.WaitForExit(3000)) { try { $p.Kill($true) } catch {} } } }
}
function Set-MpvFocus([bool]$on, $wtH) {
    # ecrã inteiro: a janela do mpv passa a ativável e recebe o foco (sem foco, o Windows não volta a mostrar o rato
    # depois de o mpv o esconder); ao sair do ecrã inteiro volta a "não ativável" e o foco regressa ao terminal
    $h = $MpvHwnd.h; if ($h -eq [IntPtr]::Zero) { return }
    $ex = [Yt.Win]::GetWindowLong($h, -20)
    [void][Yt.Win]::SetWindowLong($h, -20, $(if ($on) { $ex -band (-bnot 0x08000000) } else { $ex -bor 0x08000000 }))
    $to = if ($on) { $h } else { $wtH }
    $a = [Yt.Win]::GetCurrentThreadId(); $b = [Yt.Win]::GetWindowThreadProcessId([Yt.Win]::GetForegroundWindow(), [IntPtr]::Zero)
    [void][Yt.Win]::AttachThreadInput($a, $b, $true); [void][Yt.Win]::SetForegroundWindow($to); [void][Yt.Win]::AttachThreadInput($a, $b, $false)
}
function Format-Ago($ts, [switch]$Short) {
    # -Short: unidades curtas para caber nas fichas da grelha ("há 3 sem", "há 2 d", "há 5 h")
    if (-not $ts -or "$ts" -eq 'NA') { return '' }
    $d = [DateTimeOffset]::UtcNow - [DateTimeOffset]::FromUnixTimeSeconds([long]$ts)
    $n, $one, $many = if ($d.TotalDays -ge 365) { ($d.TotalDays / 365), 'year', 'years' } elseif ($d.TotalDays -ge 30) { ($d.TotalDays / 30), 'month', 'months' }
    elseif ($d.TotalDays -ge 7) { ($d.TotalDays / 7), 'week', 'weeks' } elseif ($d.TotalDays -ge 1) { $d.TotalDays, 'day', 'days' }
    elseif ($d.TotalHours -ge 1) { $d.TotalHours, 'hour', 'hours' } else { [Math]::Max(1, $d.TotalMinutes), 'minute', 'minutes' }
    $ab = @{ week = 'w'; day = 'd'; hour = 'h'; minute = 'min' }[$one]   # mês/ano ficam por extenso
    $n = [int][Math]::Floor($n)
    if ($Short -and $ab) { return "$n$ab ago" }   # curto: "3w ago", "2d ago", "5h ago", "10min ago"
    "$n $(if ($n -eq 1) { $one } else { $many }) ago"
}
function Wrap-Lines([string]$s, [int]$w, [int]$max) {
    # parte texto em até $max linhas de largura $w (por palavras); reticências se sobrar
    $out = [Collections.Generic.List[string]]::new(); $line = ''
    foreach ($word in ($s -replace '\s+', ' ').Trim() -split ' ') {
        if (($line + ' ' + $word).Trim().Length -le $w) { $line = ($line + ' ' + $word).Trim() }
        else { $out.Add($line); $line = if ($word.Length -gt $w) { $word.Substring(0, $w) } else { $word }; if ($out.Count -ge $max) { break } }
    }
    if ($out.Count -lt $max -and $line) { $out.Add($line) }
    elseif ($out.Count -ge $max) { $last = $out[$max - 1]; $out[$max - 1] = (Fit $last ($w)).TrimEnd(); if ($line) { $out[$max - 1] = (Fit ($last + ' ' + $line) $w).TrimEnd() } }
    @($out | Select-Object -First $max)
}
function Show-WatchHelp($row, $col, $w) {
    $rows = @(@('space', 'pause'), @('← →', 'back / forward 5 s'), @('↑ ↓', 'pick in "up next"'), @('enter', 'open the selected one'),
        @('f', 'fullscreen'), @('m', 'mute'), @('9  0', 'volume'), @('pgup pgdn', 'comments'), @('D', 'debug info to a file'), @('esc', 'back'))
    $h = [string][char]0x2500
    $out = "$e[$row;${col}H$e[90m$([char]0x256D)$h $e[1;97mshortcuts $e[0;90m" + ($h * ($w - 14)) + [char]0x256E
    $r = $row + 1
    foreach ($x in $rows) { $out += "$e[$r;${col}H$e[90m$([char]0x2502)$e[0m  $e[1;97m" + $x[0].PadRight(11) + "$e[0;37m" + $x[1].PadRight($w - 15) + "$e[90m$([char]0x2502)"; $r++ }
    $out += "$e[$r;${col}H$([char]0x2570)" + ($h * ($w - 2)) + "$([char]0x256F)$e[0m"
    [Console]::Write($out); [void](Read-Key)
    [Console]::Write((($row..$r) | ForEach-Object { "$e[$_;${col}H" + (' ' * $w) }) -join '')
}
function Show-Watch($s) {
    $watchSw = [Diagnostics.Stopwatch]::StartNew()
    $g = Get-WinGeom
    # por SSH, num split ou num painel pequeno: janela normal do mpv
    if (-not $g -or [Console]::WindowWidth -lt 110 -or [Console]::WindowHeight -lt 28) { Invoke-Play $s.vids[$s.sel]; return }
    $v = $s.vids[$s.sel]; $mp = $null; Clear-Keys
    if ($script:WinMp -and -not $script:WinMp.HasExited) { Stop-Mpv $script:WinMp -Pipe $script:WinPipe }   # um só mpv de cada vez
    $away = $false; $hideN = 0; $thumbPs = [Collections.Generic.List[object]]::new()   # thumbPs: curls das thumbnails do "a seguir"; $away: outro separador/painel do WT à frente (o vídeo esconde-se)
    [void][Yt.Con]::SetConsoleMode($InH, $InModeYt)   # sem modo VT na entrada: o foco chega como evento, não como texto
    [void][Yt.Con]::Focus($InH)
    try {
    while ($true) {
        $url = "https://youtu.be/$($v.id)"
        $W = [Console]::WindowWidth; $H = [Console]::WindowHeight
        $lm = 3; $vw = $W - [Math]::Max(44, [Math]::Floor($W * 0.27)) - $lm - 6
        $vh = [int][Math]::Round($vw * $g.cw * 9 / 16 / $g.ch)
        if ($vh -gt [Math]::Floor($H * 0.6)) { $vh = [Math]::Floor($H * 0.6); $vw = [int][Math]::Round($vh * $g.ch * 16 / 9 / $g.cw) }
        # a coluna "a seguir" encosta ao vídeo e fica com o resto da largura
        $lw = $vw; $rc = $lm + $vw + 4; $rw = $W - $rc - 2; $nh = 5; $nw = [Math]::Max(12, [int][Math]::Round($nh * 16 / 9 / $CellRatio)); $tw2 = $rw - $nw - 3;   # "a seguir": miniatura 16:9 de $nh linhas (como na barra lateral do YouTube)
        $vr = 2

        # marcar como visto (aqui e na conta) e pedir detalhes + comentários em segundo plano
        if ($Watched.Add($v.id)) { Add-Content $WatchedFile $v.id }
        # (um só yt-dlp para detalhes + comentários + marcar como visto: precisa da sessão, senão o YouTube responde
        # "not a bot"; web_safari sem PO token chega para os metadados e poupa CPU enquanto o vídeo arranca)
        $ck = Get-CookieArgs
        $wf = "$Dir\watch-$($v.id).json"
        if ((Test-Path $wf) -and (Get-Item $wf).Length -eq 0) { [IO.File]::Delete($wf) }   # pedido anterior falhou: tenta outra vez
        $meta = @('--no-warnings', '--extractor-args', 'youtube:player_client=web_safari;fetch_pot=never;max_comments=40,40,0,0;comment_sort=top') + $ck
        $wj = if (Test-Path $wf) {
            if ($ck) { $null = Start-Yt (@($url, '--mark-watched', '--simulate', '--quiet', '--ignore-no-formats-error') + $meta) }
            $null
        } else {
            Start-Yt (@($url, '--write-comments', '--ignore-no-formats-error', '--print', '%(.{title,like_count,view_count,timestamp,channel,channel_follower_count,description,comments})j') +
                    $(if ($ck) { '--mark-watched' }) + $meta) $wf
        }

        # a seguir: os relacionados deste video (a barra lateral do YouTube; a playlist "mix" de antes enchia-se do
        # mesmo canal), 20 de cada vez
        $relSrc = "ytrelated:$($v.id)"
        Start-ListJob 'rel' $relSrc 20 @($ck)   # (fecha o pedido anterior, se ainda estiver a correr)
        $next = [Collections.Generic.List[object]]::new(); $seen = [Collections.Generic.HashSet[string]]::new(); [void]$seen.Add($v.id)
        $relFrom = 1; $relDone = $false; $relBusy = $true; $skelDone = $false
        $nShow = [Math]::Max(1, [Math]::Floor(($H - $vr) / ($nh + 1))); $ns = 0; $nOff = 0

        # vídeo: mpv encaixado na área da esquerda (o primeiro abre; os seguintes carregam no mesmo)
        # endereços diretos já resolvidos em segundo plano -> arranque imediato; senão o mpv resolve sozinho
        # (chamado com "." para mudar $mp aqui; volta a ser usado se a abertura falhar)
        $open = {
            param($st)
            $src = if ($st) { @($st.v) + $(if ($st.a) { "--audio-file=$($st.a)" }) } else { @($url) }
            if (-not $mp -or $mp.HasExited) {
                $script:PrevPath = $null   # (mpv novo: o que comecar a tocar e este video)
                $geo = '--geometry={0}x{1}+{2}+{3}' -f [int]($vw * $g.cw), [int]($vh * $g.ch), [int]($g.x + ($lm - 1) * $g.cw), [int]($g.y + ($vr - 1) * $g.ch)
                # sem --force-window: a janela só aparece quando o vídeo já está a tocar (nada de caixa preta)
                # yt-url: para o menu de qualidade reabrir pelo YouTube (scripts\yt-quality.lua)
                # log de cada arranque em $Dir\mpv-<data>.log (para perceber falhas; ficam os últimos 5)
                $script:MpvPipe = "ytmpv-$PID-$((++$script:MpvN))"
                $mp = Start-Process $MpvWin -PassThru -ArgumentList (Quote-Args (@($geo, '--no-border', "--input-ipc-server=\\.\pipe\$script:MpvPipe", "--script-opts-append=yt-url=$url", (New-MpvLog)) + $MpvOpts + (Get-PlayOpts) + $src))
                Set-NoFocus $mp $g.wt
                # se o terminal fechar sem passar pelo esc (fechar o separador, crash), o mpv não fica órfão
                [void][Yt.Job]::Add($mp.Handle)
            }
            else {
                # o mesmo mpv: esconde a janela (senao ficava por cima do painel de carregamento com a imagem do anterior) e
                # guarda o ficheiro que tinha, para so dar o novo como "a tocar" quando ele mudar
                $script:PrevPath = Get-MpvProp 'path'
                if ($MpvHwnd.h -and $MpvHwnd.h -ne [IntPtr]::Zero) { [void][Yt.Vd]::SetWindowPos($MpvHwnd.h, [IntPtr]::Zero, 0, 0, 0, 0, $SwpHide) }
                Send-Mpv 'change-list', 'script-opts', 'append', "yt-url=$url"
                if ($st) { Send-Mpv 'loadfile', $st.v, 'replace', '-1', $(if ($st.a) { "audio-file=$($st.a)" } else { '' }) } else { Send-Mpv 'loadfile', $url }
            }
        }
        $st = Get-Stream $v
        . $open $st
        # se não começar a tocar (endereço pré-resolvido que já não serve, mpv fechou com erro, YouTube lento):
        # tenta uma vez pelo endereço do YouTube; se mesmo assim falhar, diz que falhou em vez de ficar a carregar
        $loadSw = [Diagnostics.Stopwatch]::StartNew(); $retried = -not $st; $failed = $false
        $fs = $null; $playing = $false; $spin = 0; $tick = 0; $frames = [char[]]'⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        $ended = $false; $autoplay = $false; $endSw = $null; $endN = 0; $endCard = $null   # ecra de fim (ver mais abaixo)

        $sb = [Text.StringBuilder]::new(); [void]$sb.Append("$e[2J")
        # enquanto abre: painel escuro liso no lugar do video (a thumbnail nao aparece; o indicador vai ao centro)
        $panelBg = "$e[48;2;33;37;43m"
        for ($q = 0; $q -lt $vh; $q++) { [void]$sb.Append("$e[$($vr + $q);${lm}H$panelBg" + (' ' * $vw) + "$e[0m") }
        # escreve uma linha centrada no painel (por posicao: o texto nunca desalinha)
        $center = { param($row, $text, $len) "$e[$row;$($lm + [Math]::Max(0, [Math]::Floor(($vw - $len) / 2)))H$panelBg$text$e[0m" }
        $tl = @(Wrap-Lines $v.t $lw 2); $r = $vr + $vh + 1
        foreach ($l in $tl) { [void]$sb.Append("$e[$r;${lm}H$e[1;97m$l$e[0m"); $r++ }
        # canal com icone e, a cinzento, views / ha quanto tempo / duracao (o que houver)
        $meta = @($(if ($v.v -and $v.v -ne 'NA') { "$(Format-Num $v.v) views" }), (Format-Ago $v.ts), $(if ($v.dur -and $v.dur -notin 'NA', 'live') { $v.dur })) | Where-Object { $_ }
        [void]$sb.Append("$e[$($r);${lm}H$e[31m$([char]0xf16a)  $e[1;37m$($v.ch)$e[0;90m" + $(if ($meta) { "   $([char]0x00B7)   " + ($meta -join "   $([char]0x00B7)   ") }) + "$e[0m")
        $infoRow = $r; $descRow = $r + 2
        if ($env:WEZTERM_PANE) { Set-Hints $WatchHints } else { [void]$sb.Append("$e[$H;${lm}H$e[48;2;62;68;81;97m ? $e[0;90m shortcuts$e[0m") }
        [Console]::Write($sb.ToString())
        $drawHead = { }   # (sem titulo "up next": a lista comeca alinhada com o topo do video, como no YouTube)
        $drawNext = {
            $o = ''
            for ($k = 0; $k -lt $nShow; $k++) {
                $rr = $vr + $k * ($nh + 1); $j = $nOff + $k; $tx = $rc + $nw + 2
                if ($j -ge $next.Count) {
                    # ainda a carregar: cartoes-esqueleto (bloco da thumbnail + barras), senao vazio
                    for ($q = 0; $q -lt $nh; $q++) {
                        $o += "$e[$($rr + $q);${rc}H" + $(if ($relBusy -and -not $next.Count) {
                                "$e[48;2;44;49;58m" + (' ' * $nw) + "$e[0m  " + $(switch ($q) { 0 { "$e[48;2;62;68;81m" + (' ' * [Math]::Min(28, $tw2)) + "$e[0m" } 1 { "$e[48;2;62;68;81m" + (' ' * [Math]::Min(18, $tw2)) + "$e[0m" } 2 { "$e[48;2;44;49;58m" + (' ' * [Math]::Min(12, $tw2)) + "$e[0m" } default { '' } }) + (' ' * [Math]::Max(0, $rw - $nw - 32))
                            } else { ' ' * $rw })
                    }
                    continue
                }
                # como a barra lateral do YouTube: miniatura 16:9 (a grande, se ja veio da grelha) com a duracao no canto;
                # titulo em 2 linhas, canal, visualizacoes · data; o selecionado com a barra vermelha por baixo do titulo
                $x = $next[$j]; $sel = $j -eq $ns
                $img = if (Test-Path "$Dir\$($x.id)-hq.jpg") { "$Dir\$($x.id)-hq.jpg" } else { "$Dir\$($x.id).jpg" }
                $o += if (Test-Path $img) { "$e[$rr;${rc}H" + (Get-Img $img $nw $nh -Stretch) } else { (0..($nh - 1) | ForEach-Object { "$e[$($rr + $_);${rc}H$e[48;2;44;49;58m" + (' ' * $nw) + "$e[0m" }) -join '' }
                if ($x.dur) { $d = " $($x.dur) "; $o += "$e[$($rr + $nh - 1);$($rc + $nw - $d.Length)H$(if ($x.dur -eq 'live') { "$e[48;2;204;0;0;1;97m" } else { "$e[48;2;15;15;15;1;97m" })$d$e[0m" }
                $t2 = @(Wrap-Lines $x.t $tw2 2)
                $o += "$e[$rr;${tx}H$e[$(if ($sel) { '1;97' } else { '1;37' })m$(Fit $t2[0] $tw2)" + "$e[$($rr + 1);${tx}H$(Fit $(if ($t2.Count -gt 1) { $t2[1] } else { '' }) $tw2)"
                $o += "$e[$($rr + 2);${tx}H$e[0;90m$(Fit $(if ($x.ch -and $x.ch -ne 'NA') { $x.ch } else { '' }) $tw2)"
                $vv = Format-Num $x.v
                $o += "$e[$($rr + 3);${tx}H$(Fit ((@($(if ($vv) { "$vv views" }), (Format-Ago $x.ts)) | Where-Object { $_ }) -join " $([char]0x00B7) ") $tw2)"
                $o += "$e[$($rr + 4);${tx}H" + $(if ($sel) { "$e[31m" + ([string][char]0x2501 * $tw2) } else { ' ' * $tw2 }) + "$e[0m"
            }
            [Console]::Write($o); & $drawHead
        }

        $info = $null; $cOff = 0; $comRow = 0
        $drawComments = {
            # comentários a partir de $cOff, até ao fundo do ecrã
            $o = ''; $rr = $comRow
            for ($rr2 = $comRow; $rr2 -lt $H - 1; $rr2++) { $o += "$e[$rr2;${lm}H" + (' ' * $lw) }
            # como no YouTube: nome (branco; o do canal num chip) e ha quanto tempo; o texto ate 4 linhas; gostos por baixo
            $all = @($info.comments | Where-Object { $_ }); $shown = 0
            foreach ($cm in @($all | Select-Object -Skip $cOff)) {
                $room = [Math]::Min(4, $H - 2 - $rr)   # (linhas de texto que ainda cabem ate a penultima; a ultima e a do "more")
                if ($room -lt 1) { break }
                $txt = @(Wrap-Lines $cm.text ($lw - 2) $room)
                $likes = Format-Num $cm.like_count
                $ago = Format-Ago $cm.timestamp
                $name = if ($cm.author_is_uploader) { "$e[48;2;62;68;81;1;97m $($cm.author) $e[0m" } else { "$e[1;97m$($cm.author)$e[0m" }
                $o += "$e[$rr;${lm}H$(if ($cm.is_pinned) { "$e[90m$([char]0xf08d) pinned  " })$name$e[0;90m  $ago$e[0m"; $rr++
                foreach ($l in $txt) { $o += "$e[$rr;${lm}H$e[37m$l$e[0m"; $rr++ }
                if ($likes -and $rr -lt $H - 2) { $o += "$e[$rr;${lm}H$e[90m$([char]0xf164)  $likes$e[0m"; $rr++ }
                $rr++; $shown++
            }
            # mais por baixo: a roda (ou pgdn) desce
            $left = $all.Count - $cOff - $shown
            $o += "$e[$($H - 1);${lm}H" + (' ' * $lw) + "$e[$($H - 1);${lm}H" + $(if ($left -gt 0) { "$e[90m$([char]0x2193)  $left more  $([char]0x00B7)  scroll$e[0m" } elseif ($cOff -gt 0) { "$e[90m$([char]0x2191)  scroll up$e[0m" } else { '' })
            [Console]::Write($o)
        }
        $goto = $null
        while ($true) {
            # recomendações: lista pronta -> mostrar e descarregar as thumbnails (redesenha quando chegarem)
            if ($relBusy -and (-not $Jobs['rel'].p -or $Jobs['rel'].p.HasExited)) {
                $relBusy = $false
                $new = @(Read-ListFile $Jobs['rel'].f | Where-Object { $seen.Add($_.id) })
                if (-not $new -and -not $next.Count) { $new = @($s.vids | Where-Object { $seen.Add($_.id) }); $relDone = $true }   # falhou: usa a lista de onde vieste
                if (-not $new) { $relDone = $true }
                $first = -not $next.Count
                foreach ($x in $new) { $next.Add($x) }
                if ($t = Start-Thumbs @($new | ForEach-Object id)) { $thumbPs.Add($t) }
                if ($first) { foreach ($x in ($next | Select-Object -First 3)) { Start-StreamPrefetch $x.id } }
                & $drawNext
            }
            foreach ($t in @($thumbPs)) { if (-not $t.p -or $t.p.HasExited) { Complete-Thumbs $t; [void]$thumbPs.Remove($t); & $drawNext } }   # só desenha depois de o curl acabar
            if ($relBusy -and -not $next.Count) { if (-not $skelDone) { $skelDone = $true; & $drawNext } else { & $drawHead } }   # esqueleto uma vez, depois so o spinner

            if (-not $info -and (-not $wj -or $wj.HasExited) -and (Test-Path $wf)) {
                $info = try { (Get-Content $wf -Encoding utf8 | Select-Object -Last 1) | ConvertFrom-Json } catch { @{} }
                $subs = Format-Num $info.channel_follower_count; $likes = Format-Num $info.like_count; $views = Format-Num $info.view_count
                # (limpa a linha da coluna do video primeiro: a linha provisoria era mais comprida e sobravam letras
                # "...subscriberss ago"; ESC[K nao serve, apagaria tambem o "a seguir" a direita)
                $o = "$e[$infoRow;${lm}H" + (' ' * $lw) + "$e[$infoRow;${lm}H$e[31m$([char]0xf16a)  $e[1;37m$($v.ch)$e[0;90m" + $(if ($subs) { "   $([char]0x00B7)   $subs subscribers" })
                $meta = @($(if ($likes) { "$([char]0x2665) $likes" }), $(if ($views) { "$views views" }), (Format-Ago $info.timestamp)) | Where-Object { $_ }
                $ms = ($meta | ForEach-Object { " $_ " }) -join "  "   # chips
                $o += "$e[$infoRow;$($lm + $lw - $ms.Length)H" + (($meta | ForEach-Object { "$e[48;2;62;68;81;97m $_ $e[0m" }) -join "  ")
                # descrição: mantém os parágrafos, até 4 linhas, links a azul, dentro de um cartão
                $d = [Collections.Generic.List[string]]::new()
                # (encolhe para deixar sempre ~8 linhas aos comentarios: num ecra mais baixo nao sobrava nenhuma)
                $dMax = [Math]::Max(1, [Math]::Min(4, $H - 1 - ($descRow + 2 + 3) - 8))
                foreach ($par in ("$($info.description)" -split "`n")) { if ($par.Trim()) { foreach ($l in @(Wrap-Lines $par ($lw - 4) $dMax)) { $d.Add($l) } }; if ($d.Count -ge $dMax) { break } }
                $rr = $descRow
                if ($d.Count) {
                    foreach ($l in @('') + @($d | Select-Object -First $dMax) + @('')) { $o += "$e[$rr;${lm}H$e[48;2;44;49;58;37m  " + ($l.PadRight($lw - 4) -replace '(https?://\S+)', "$e[34m`$1$e[37m") + "  $e[0m"; $rr++ }
                }
                $comRow = $rr + 1
                $o += "$e[$comRow;${lm}H$e[1;97mComments$e[0;90m  $(@($info.comments | Where-Object { $_ }).Count)"; $comRow += 2
                [Console]::Write($o); & $drawComments
            }
            if (-not $playing -and -not $failed) {
                # até o vídeo começar: painel de carregamento no lugar do vídeo (a janela do mpv só aparece quando já toca)
                # (no mesmo mpv: o tempo e o do video anterior ate o novo abrir; so conta quando o ficheiro ja mudou)
                if ($spin % 4 -eq 0 -and $null -ne (Get-MpvProp 'time-pos') -and (-not $script:PrevPath -or (Get-MpvProp 'path') -ne $script:PrevPath)) {
                    $playing = $true; $script:PrevPath = $null; Trace "a tocar $([int]$watchSw.ElapsedMilliseconds) ms depois do Enter"
                    if ($MpvHwnd.h -and $MpvHwnd.h -ne [IntPtr]::Zero -and -not $away) { [void][Yt.Vd]::SetWindowPos($MpvHwnd.h, [IntPtr]::Zero, 0, 0, 0, 0, $SwpShow) }
                }
                elseif ($mp.HasExited -or $loadSw.Elapsed.TotalSeconds -gt $(if ($retried) { 30 } else { 10 })) {
                    if (-not $retried) { $retried = $true; $StreamCache.Remove($v.id); . $open $null; $loadSw.Restart() }
                    else {
                        $failed = $true
                        # sessão do YouTube expirada ("not a bot" no log do mpv) -> dizer o que fazer
                        $msg = if (Select-String -Path $script:MpvLog -Pattern 'not a bot|Sign in to confirm' -Quiet -EA 0) { "your YouTube session expired  $([char]0x00B7)  esc, then l to sign in again" }
                        else { "couldn't open the video  $([char]0x00B7)  esc goes back  $([char]0x00B7)  enter tries another" }
                        # no painel: icone a vermelho, a mensagem e o que fazer por baixo
                        $c = $vr + [Math]::Floor($vh / 2); $blank = { param($row) "$e[$row;${lm}H$panelBg" + (' ' * $vw) }
                        $hint, $what = if ($msg -like 'your YouTube session expired*') { 'your YouTube session expired', 'esc, then l to sign in again' } else { "couldn't open the video", 'esc goes back   ·   enter tries another' }
                        $o = (& $blank ($c - 3)) + (& $blank ($c - 1)) + (& $blank ($c + 1)) + (& $blank ($c + 2))
                        $o += & $center ($c - 3) "$e[31m$([char]0xf071)" 1
                        $o += & $center ($c - 1) "$e[1;97m$hint" $hint.Length
                        $o += & $center ($c + 1) "$e[22;90m$what" $what.Length
                        [Console]::Write($o)
                    }
                }
                else {
                    # painel de carregamento: icone do YouTube, "loading video" com spinner, barra que corre e o tempo
                    $c = $vr + [Math]::Floor($vh / 2); $bwid = [Math]::Min(36, $vw - 8)
                    $pos = $spin % ($bwid + 6) - 6   # segmento de 6 que entra pela esquerda e sai pela direita
                    $bar = -join (0..($bwid - 1) | ForEach-Object { if ($_ -ge $pos -and $_ -lt $pos + 6) { "$e[38;2;224;108;117m$([char]0x2501)" } else { "$e[38;2;75;82;99m$([char]0x2501)" } })
                    $secs = '{0:0.0} s' -f $loadSw.Elapsed.TotalSeconds
                    $o = "$e[$($c + 2);${lm}H$panelBg" + (' ' * $vw)   # (o tempo muda de largura)
                    $o += & $center ($c - 3) "$e[31m$([char]0xf16a)" 1
                    $o += & $center ($c - 1) "$e[31m$($frames[$spin % 10])  $e[1;97mloading video" 16
                    $o += & $center ($c + 1) $bar $bwid
                    $o += & $center ($c + 2) "$e[22;90m$secs" $secs.Length
                    [Console]::Write($o)
                }
                $spin++
            }
            # fim do video: o mpv fecha sozinho no fim (keep-open=no). Ecra de fim no lugar do video: o seguinte do
            # "up next" com autoplay de 10 s (barra a esvaziar), r = ver de novo, c = sem autoplay, enter = ja, esc = sair
            if ($playing -and -not $ended -and $mp.HasExited) { $ended = $true; $autoplay = [bool]$next.Count; $endSw = [Diagnostics.Stopwatch]::StartNew(); $endN = 0 }
            if ($ended) {
                if ($autoplay -and $next.Count -and $endSw.Elapsed.TotalSeconds -ge 10) { $v = $next[$ns]; break }
                $chips = { param($list) ($list | ForEach-Object { "$e[48;2;62;68;81;97m $($_[0]) $panelBg$e[0;90m$panelBg $($_[1])" }) -join "$panelBg     " }
                $chipLen = { param($list) ($list | ForEach-Object { $_[0].Length + $_[1].Length + 3 } | Measure-Object -Sum).Sum + 5 * ($list.Count - 1) }
                if ($next.Count -and $endN++ % 3 -eq 0) {
                    # como o cartao de autoplay do YouTube: miniatura do seguinte, titulo, canal, views / ha quanto tempo,
                    # a contagem e as teclas. O cartao desenha-se uma vez (por video escolhido); depois so a barra muda
                    $nx = $next[$ns]
                    $th = [Math]::Max(4, [Math]::Min(9, $vh - 9)); $tw = [int][Math]::Round($th * 16 / 9 / $CellRatio)
                    $cw = [Math]::Min($vw - 6, $tw + 3 + 56); $tx = $tw + 3; $iw = $cw - $tx   # (largura do texto ao lado da miniatura)
                    $cx = $lm + [Math]::Floor(($vw - $cw) / 2); $cy = $vr + [Math]::Max(1, [Math]::Floor(($vh - ($th + 7)) / 2))
                    $sig = "$($nx.id)|$autoplay"
                    if ($endCard -ne $sig) {
                        $endCard = $sig; $o = ''
                        for ($q = 0; $q -lt $vh; $q++) { $o += "$e[$($vr + $q);${lm}H$panelBg" + (' ' * $vw) }
                        $o += "$e[$cy;${cx}H$panelBg$e[0;90mUp next$e[0m"
                        $jp = "$Dir\$($nx.id).jpg"; if (-not [IO.File]::Exists($jp)) { $jp = "$Dir\$($nx.id)-hq.jpg" }
                        $img = if ([IO.File]::Exists($jp)) { Get-Img $jp $tw $th -Stretch } else { $null }
                        if ($img) { $o += "$e[$($cy + 2);${cx}H$img" } else { for ($q = 0; $q -lt $th; $q++) { $o += "$e[$($cy + 2 + $q);${cx}H$e[48;2;44;49;58m" + (' ' * $tw) + "$e[0m" } }
                        if ($nx.dur -and $nx.dur -notin 'NA', 'live') { $o += "$e[$($cy + 1 + $th);$($cx + $tw - $nx.dur.Length - 2)H$e[48;2;20;20;20;97m $($nx.dur) $e[0m" }
                        $r = $cy + 2
                        foreach ($l in @(Wrap-Lines $nx.t $iw 2)) { $o += "$e[$r;$($cx + $tx)H$panelBg$e[1;97m$l$e[0m"; $r++ }
                        $o += "$e[$($r + 1);$($cx + $tx)H$panelBg$e[0;37m$(Fit $nx.ch $iw)$e[0m".TrimEnd()
                        $nm = @($(if ($nx.v -and $nx.v -ne 'NA') { "$(Format-Num $nx.v) views" }), (Format-Ago $nx.ts)) | Where-Object { $_ }
                        if ($nm) { $o += "$e[$($r + 2);$($cx + $tx)H$panelBg$e[0;90m$($nm -join "  $([char]0x00B7)  ")$e[0m" }
                        $ks = [Collections.Generic.List[object]]::new(); $ks.Add(@('enter', 'play now')); $ks.Add(@('r', 'watch again'))
                        if ($autoplay) { $ks.Add(@('c', 'cancel')) }; $ks.Add(@('esc', 'back'))   # (List: o "+" de arrays desfazia os pares)
                        $o += & $center ($cy + $th + 6) (& $chips $ks) (& $chipLen $ks)
                        [Console]::Write($o + "$e[0m")
                    }
                    # contagem: barra a esvaziar por baixo do cartao e "playing in N s" a direita do "Up next"
                    $o = ''
                    if ($autoplay) {
                        $left = [Math]::Max(0, 10 - $endSw.Elapsed.TotalSeconds); $fill = [int]($cw * $left / 10)
                        $o += "$e[$($cy + $th + 3);${cx}H$panelBg$e[38;2;224;108;117m" + ([string][char]0x2501 * $fill) + "$e[38;2;75;82;99m" + ([string][char]0x2501 * ($cw - $fill))
                        $pl = "playing in $([Math]::Ceiling($left)) s"; $o += "$e[$cy;$($cx + $cw - $pl.Length)H$panelBg$e[0;37m$pl"
                    } else { $o += "$e[$($cy + $th + 3);${cx}H$panelBg" + (' ' * $cw) + "$e[$cy;$($cx + $cw - 16)H$panelBg" + (' ' * 16) }
                    [Console]::Write($o + "$e[0m")
                }
                elseif (-not $next.Count -and $endN++ % 6 -eq 0) {
                    $c = $vr + [Math]::Floor($vh / 2); $o = ''
                    for ($q = 0; $q -lt $vh; $q++) { $o += "$e[$($vr + $q);${lm}H$panelBg" + (' ' * $vw) }
                    $o += & $center ($c - 2) "$e[31m$([char]0xf01e)" 1
                    $o += & $center ($c) "$e[1;97mthat's the end" 14
                    $ks = @(@('r', 'watch again'), @('esc', 'back'))
                    $o += & $center ($c + 4) (& $chips $ks) (& $chipLen $ks)
                    [Console]::Write($o + "$e[0m")
                }
            }
            # foco do painel (o ConPTY passa o ESC[I / ESC[O do WT como evento): perdê-lo com o WT ainda à frente = outro
            # separador ou painel (ctrl+t, mudar de separador) -> esconder o vídeo; ao voltar, mostrá-lo
            # (perder o foco porque se mudou de app não esconde: a janela do vídeo é "dona" do WT e fica com ele)
            # rato (lido antes do Focus / KeyAvailable): clicar num video do "a seguir" abre-o; roda sobre a lista = mexer
            # nela, sobre o resto = comentarios; o rodape = atalhos. No video, o proprio mpv trata dos cliques (pausa, barra)
            $mk = $null
            if ($mm = [Yt.Con]::Mouse($InH)) {
                $mx = [Yt.Con]::MouseX + 1; $my = [Yt.Con]::MouseY + 1; $up = [Yt.Con]::Wheel -gt 0
                if ($mm -eq 2) { $mk = if ($mx -ge $rc) { New-Key 0 $(if ($up) { 'UpArrow' } else { 'DownArrow' }) } elseif ($info) { $cOff = [Math]::Max(0, [Math]::Min(@($info.comments).Count - 1, $cOff - [Yt.Con]::Wheel)); & $drawComments } }   # (roda sobre os comentarios: 1 comentario por passo)
                elseif ($mx -ge $rc -and $my -ge $vr) {
                    # (3 = so mexeu: destaca o video; 1 = clique: abre-o)
                    $kk = [Math]::Floor(($my - $vr) / ($nh + 1))
                    if ($kk -lt $nShow -and $nOff + $kk -lt $next.Count) {
                        if ($mm -eq 1) { $ns = $nOff + $kk; $mk = New-Key "`r" 'Enter' }
                        elseif ($ns -ne $nOff + $kk) { $ns = $nOff + $kk; & $drawNext }
                    }
                }
                elseif ($mm -eq 1 -and $my -eq $H -and $mx -lt $rc) { $mk = New-Key '?' 'Oem2' -Shift }
            }
            $fe = [Yt.Con]::Focus($InH)
            if ($fe -ge 0) { $away = $fe -eq 0 -and [Yt.Win]::GetForegroundWindow() -eq $g.wt; $tick = 0 }
            if ($tick++ % 16 -eq 0 -and $MpvHwnd.h -and $MpvHwnd.h -ne [IntPtr]::Zero -and $null -eq $fs -and -not [Yt.Win]::IsIconic($g.wt)) {
                # ~1 vez por segundo: posição (janela do WT movida/redimensionada, ou noutro ecrã) e visibilidade do vídeo.
                # Tudo com SetWindowPos assíncrono: o yt nunca espera pelo mpv nem pelo WT
                $hv = $MpvHwnd.h
                $g2 = Get-WinGeom
                if ($g2 -and ($g2.x -ne $g.x -or $g2.y -ne $g.y -or $g2.cw -ne $g.cw -or $g2.ch -ne $g.ch)) {
                    $g = $g2
                    [void][Yt.Vd]::SetWindowPos($hv, [IntPtr]::Zero, [int]($g.x + ($lm - 1) * $g.cw), [int]($g.y + ($vr - 1) * $g.ch), [int]($vw * $g.cw), [int]($vh * $g.ch), $SwpMove)
                }
                $vis = [Yt.Vd]::IsWindowVisible($hv)
                if ($away) { if ($vis) { [void][Yt.Vd]::SetWindowPos($hv, [IntPtr]::Zero, 0, 0, 0, 0, $SwpHide) } }
                elseif ([Yt.Win]::GetForegroundWindow() -eq $g.wt) {
                    # ao mudar de ambiente de trabalho e voltar, o Windows pode deixar a janela do vídeo escondida ("cloaked")
                    # -> esconder e mostrar outra vez (no máximo 3 vezes seguidas, para não ficar em ciclo)
                    $cl = 0; [void][Yt.Vd]::DwmGetWindowAttribute($hv, 14, [ref]$cl, 4)
                    if (-not $vis -and $playing -and -not $ended) { [void][Yt.Vd]::SetWindowPos($hv, [IntPtr]::Zero, 0, 0, 0, 0, $SwpShow) }   # (a carregar o seguinte: fica escondida)
                    elseif ($cl -ne 0 -and $hideN -lt 3) { $hideN++; [void][Yt.Vd]::SetWindowPos($hv, [IntPtr]::Zero, 0, 0, 0, 0, $SwpHide); [void][Yt.Vd]::SetWindowPos($hv, [IntPtr]::Zero, 0, 0, 0, 0, $SwpShow) }
                    elseif ($cl -eq 0) { $hideN = 0 }
                }
            }
            # ecrã inteiro (foco no mpv): quando sair dele, o foco volta ao terminal
            if ($null -ne $fs -and $fs++ % 4 -eq 3 -and (Get-MpvProp 'fullscreen') -ne $true) { $fs = $null; Set-MpvFocus $false $g.wt }
            if (-not $mk -and -not [Console]::KeyAvailable) { Start-Sleep -Milliseconds 60; continue }
            $k = if ($mk) { $mk } else { Read-Key }
            switch ($k.Key) {
                'Escape'     { return }
                'Spacebar'   { Send-Mpv 'cycle', 'pause' }
                'LeftArrow'  { Send-Mpv 'seek', '-5', 'relative+exact' }
                'RightArrow' { Send-Mpv 'seek', '5', 'relative+exact' }
                'UpArrow'    { if ($ns -gt 0) { $ns--; if ($ns -lt $nOff) { $nOff-- }; & $drawNext; Start-StreamPrefetch $next[$ns].id } }
                'DownArrow'  {
                    if ($ns -lt $next.Count - 1) { $ns++; if ($ns -ge $nOff + $nShow) { $nOff++ }; & $drawNext; Start-StreamPrefetch $next[$ns].id }
                    # perto do fim: carrega mais 20 recomendações
                    if ($ns -ge $next.Count - 4 -and -not $relDone -and -not $relBusy) { $relFrom += 20; Start-ListJob 'rel' $relSrc 20 @($ck) '' $relFrom; $relBusy = $true }
                }
                'Enter'      { if ($next.Count) { $goto = $next[$ns] } }
                'PageDown'   { if ($info) { $cOff = [Math]::Min(@($info.comments).Count - 1, $cOff + 3); & $drawComments } }
                'PageUp'     { if ($info) { $cOff = [Math]::Max(0, $cOff - 3); & $drawComments } }
            }
            switch -CaseSensitive ($k.KeyChar) {
                'q' { return }
                '?' { Show-WatchHelp 3 $rc ([Math]::Min($rw, 48)); & $drawNext }
                'f' { Send-Mpv 'set', 'fullscreen', 'yes'; Set-MpvFocus $true $g.wt; $fs = 0 }   # o teclado passa ao mpv (mesmas teclas; esc/f saem)
                'm' { Send-Mpv 'cycle', 'mute' }
                # ecra de fim: r = ver de novo (volta ao painel de carregamento e reabre), c = sem autoplay
                'r' {
                    if ($ended) {
                        $o = ''; for ($q = 0; $q -lt $vh; $q++) { $o += "$e[$($vr + $q);${lm}H$panelBg" + (' ' * $vw) }; [Console]::Write($o + "$e[0m")   # painel limpo
                        $ended = $false; $playing = $false; $failed = $false; $spin = 0; $st = Get-Stream $v; . $open $st; $loadSw.Restart(); $retried = -not $st
                    }
                }
                'c' { if ($ended) { $autoplay = $false; $endN = 0 } }
                '9' { Send-Mpv 'add', 'volume', '-5' }
                '0' { Send-Mpv 'add', 'volume', '5' }
                'D' {
                    # diagnóstico (vídeo a encravar com o som a continuar, etc.): estado do mpv para $Dir\mpv-debug.txt
                    $dbg = @("# $(Get-Date -Format s)  $url  log: $script:MpvLog") + (@('path', 'hwdec-current', 'avsync', 'frame-drop-count', 'decoder-frame-drop-count', 'vo-delayed-frame-count', 'paused-for-cache', 'demuxer-cache-state') |
                            ForEach-Object { "$_ = $(ConvertTo-Json -InputObject (Get-MpvProp $_) -Compress -Depth 6)" }) + ''
                    Add-Content "$Dir\mpv-debug.txt" $dbg -Encoding utf8
                    [Console]::Write("$e[$H;${lm}H$e[2K$e[90mdebug info saved to $Dir\mpv-debug.txt$e[0m")
                }
            }
            if ($null -ne $goto) { $v = $goto; break }
        }
    }
    }
    finally { Stop-Mpv $mp -Hide; foreach ($t in $thumbPs) { $kill = $t.p -and -not $t.p.HasExited; if ($kill) { try { $t.p.Kill(); [void]$t.p.WaitForExit(500) } catch {} }; Complete-Thumbs $t -Discard:$kill } }
}

function Get-MpvProp([string]$name) {
    # lê uma propriedade do mpv pelo canal IPC (ex.: time-pos, duration, pause, volume)
    try {
        $c = [IO.Pipes.NamedPipeClientStream]::new('.', $MpvPipe, [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::Asynchronous); $c.Connect(150)
        $w = [IO.StreamWriter]::new($c); $rd = [IO.StreamReader]::new($c)
        $w.WriteLine((@{ command = @('get_property', $name); request_id = 7 } | ConvertTo-Json -Compress)); $w.Flush()
        for ($i = 0; $i -lt 6; $i++) {
            $t = $rd.ReadLineAsync(); if (-not $t.Wait(300)) { break }   # mpv ocupado: não bloqueia o yt
            $line = $t.Result; if (-not $line) { break }
            $j = $line | ConvertFrom-Json
            if ($j.request_id -eq 7) { $c.Dispose(); return $j.data }
        }
        $c.Dispose()
    } catch {}
    $null
}
function Format-Time($sec) { if ($null -eq $sec) { return '--:--' }; $t = [TimeSpan]::FromSeconds([double]$sec); if ($t.TotalHours -ge 1) { '{0}:{1:mm\:ss}' -f [int][Math]::Floor($t.TotalHours), $t } else { '{0:m\:ss}' -f $t } }
function Show-Audio($s) {
    # ecrã "a tocar": capa grande, título, canal, barra de progresso ao vivo; o mpv toca escondido (sem vídeo)
    $idx = $s.sel; $mp = $null
    try {
        while ($true) {
            $v = $s.vids[$idx]; $url = "https://youtu.be/$($v.id)"
            if ($Watched.Add($v.id)) { Add-Content $WatchedFile $v.id }
            if (-not $mp -or $mp.HasExited) {
                $script:MpvPipe = "ytmpv-$PID-$((++$script:MpvN))"
                $mp = Start-Process $MpvWin -WindowStyle Hidden -PassThru -ArgumentList (Quote-Args (@('--no-video', '--force-window=no', "--input-ipc-server=\\.\pipe\$script:MpvPipe", (New-MpvLog)) + $MpvOpts + (Get-PlayOpts -Audio) + $url))
                [void][Yt.Job]::Add($mp.Handle)   # não fica a tocar escondido se o terminal fechar
            } else { Send-Mpv 'loadfile', $url }

            $W = [Console]::WindowWidth; $H = [Console]::WindowHeight
            $th = [Math]::Max(8, [Math]::Min(18, $H - 16)); $tw = [int][Math]::Round($th * 1.78 * 2.1)   # capa 16:9
            $blockW = $tw + 4 + [Math]::Min(70, $W - $tw - 12)
            $cx = [Math]::Max(3, [Math]::Floor(($W - $blockW) / 2)); $cy = [Math]::Max(2, [Math]::Floor(($H - $th) / 2) - 1)
            $tx = $cx + $tw + 4; $twid = [Math]::Min(70, $W - $tx - 3)
            $views = Format-Num $v.v
            $o = "$e[2J$e[$cy;${cx}H" + (Get-Img "$Dir\$($v.id).jpg" $tw $th -Stretch)
            $r = $cy + 1
            $o += "$e[$r;${tx}H$e[1;31m$([char]0xf001)  now playing$e[0m"; $r += 2
            foreach ($l in @(Wrap-Lines $v.t $twid 3)) { $o += "$e[$r;${tx}H$e[1;97m$l$e[0m"; $r++ }
            $r++
            $o += "$e[$r;${tx}H$e[36m$($v.ch)$e[0m" + $(if ($views) { "$e[90m   $views views$e[0m" })
            $barRow = $cy + $th - 2; $stateRow = $barRow + 2
            $nx = if ($s.vids.Count -gt 1) { $s.vids[($idx + 1) % $s.vids.Count] } else { $null }
            if ($nx) { $o += "$e[$($cy + $th + 2);${cx}H$e[90mup next  $e[37m$(Fit $nx.t ($blockW - 12))$e[0m" }
            $o += "$e[$H;${cx}H$e[90mspace pause   ← → 10 s   9 0 volume   m mute   n next   esc back$e[0m"
            [Console]::Write($o)

            $goto = $null; $tick = 0; $lastPos = $null; $lastDur = $null; $dead = $false
            while ($true) {
                if (-not $dead -and $tick-- -le 0) {
                    # barra de progresso e estado (de meio em meio segundo)
                    $pos = Get-MpvProp 'time-pos'; $dur = Get-MpvProp 'duration'; $pause = Get-MpvProp 'pause'; $vol = Get-MpvProp 'volume'; $mute = Get-MpvProp 'mute'
                    if ($null -ne $pos) { $lastPos = $pos; $lastDur = $dur }
                    $bw = $twid - 16
                    $frac = if ($pos -and $dur) { [Math]::Min(1, $pos / $dur) } else { 0 }
                    $fill = [int]($bw * $frac)
                    $bar = "$e[37m$(Format-Time $pos)  $e[31m" + ([string][char]0x2501 * $fill) + "$e[1;97m$([char]0x25CF)$e[0;90m" + ([string][char]0x2500 * [Math]::Max(0, $bw - $fill)) + "  $e[37m$(Format-Time $dur)$e[0m"
                    $state = if ($null -eq $pos) { "$e[90mloading..." } elseif ($pause) { "$e[33m$([char]0xf04c)  paused" } else { "$e[32m$([char]0xf04b)  playing" }
                    $vs = if ($mute) { "$([char]0xf6a9)  muted" } elseif ($null -ne $vol) { "$([char]0xf028)  $([int]$vol)%" } else { '' }
                    [Console]::Write("$e[$barRow;${tx}H$e[2K$e[$barRow;${tx}H$bar$e[$stateRow;${tx}H$e[2K$e[$stateRow;${tx}H$state$e[0;90m      $vs$e[0m")
                    $tick = 8
                    if ($mp.HasExited) {
                        # acabou (a última posição estava perto do fim): passa ao seguinte; senão falhou -> diz e para (sem relançar em ciclo)
                        if ($lastDur -and $lastPos -ge $lastDur - 3) { if ($nx) { $goto = ($idx + 1) % $s.vids.Count; break } }
                        else { $dead = $true; [Console]::Write("$e[$stateRow;${tx}H$e[2K$e[$stateRow;${tx}H$e[31mcouldn't play this one  $e[90m$([char]0x00B7)  n next  $([char]0x00B7)  esc back$e[0m") }
                    }
                }
                if (-not [Console]::KeyAvailable) { Start-Sleep -Milliseconds 60; continue }
                $k = Read-Key; $tick = 0
                switch ($k.Key) {
                    'Escape'     { return }
                    'Spacebar'   { Send-Mpv 'cycle', 'pause' }
                    'LeftArrow'  { Send-Mpv 'seek', '-10', 'relative+exact' }
                    'RightArrow' { Send-Mpv 'seek', '10', 'relative+exact' }
                }
                switch -CaseSensitive ($k.KeyChar) {
                    'q' { return }
                    'm' { Send-Mpv 'cycle', 'mute' }
                    '9' { Send-Mpv 'add', 'volume', '-5' }
                    '0' { Send-Mpv 'add', 'volume', '5' }
                    'n' { if ($nx) { $goto = ($idx + 1) % $s.vids.Count } }
                }
                if ($null -ne $goto) { break }
            }
            $idx = $goto; $s.sel = $idx
        }
    }
    finally { Stop-Mpv $mp }
}

# ---------- loop principal ----------
function Add-More($s) {
    # "scroll infinito": ao chegar ao fim da lista, carrega os 45 vídeos seguintes
    if ($s.done -or -not $s.src) { return $false }
    # normalmente já foi pedido pelo Draw-Page ao chegar perto do fim
    if (-not $s.ahead -or $s.aheadFrom -ne $s.vids.Count + 1) { $s.aheadFrom = $s.vids.Count + 1; Start-ListJob "more-$($s.mode)" $s.src 45 @(Get-CookieArgs) '' $s.aheadFrom; $s.ahead = $Jobs["more-$($s.mode)"] }
    $j = $s.ahead; Wait-Busy { -not $j.p -or $j.p.HasExited } 'loading more videos' -Cancelable -Row ([Console]::WindowHeight - 3)
    if ($script:Canceled) { Draw-Page $s; return $false }
    $have = [Collections.Generic.HashSet[string]]::new([string[]]@($s.vids | ForEach-Object id))
    $v = @(Read-ListFile $j.f | Where-Object { $have.Add($_.id) })
    if (-not $v) { $s.done = $true; return $false }
    $s.vids = @($s.vids) + $v
    $true
}
function Start-Tabs {
    # as listas de todos os separadores carregam em paralelo, logo ao abrir
    $c = Get-CookieArgs; if (-not $c) { return }
    $L0 = Get-Layout @{ mode = 'home' }
    foreach ($t in $Tabs) { if (-not $Jobs[$t.m]) { Start-ListJob $t.m $t.src 45 $c; Start-Prefetch $t.m $L0 } }
}
function Get-ChanKey([string]$src) { 'ch-' + ($src -replace '[^\w-]', '_') }   # chave/ficheiro da lista de um separador de canal
function Load([string]$mode, $arg, [string]$ctab = 'videos', [switch]$Fresh) {
    $q = ''; $info = $null; $key = $mode
    $L0 = Get-Layout @{ mode = $mode }
    switch ($mode) {
        'search' { $msg = "searching «$arg»"; $label = $arg; $q = $arg; $src = "ytsearch500:$arg"; Start-ListJob 'search' $src 45 @(Get-CookieArgs) }
        'channel' {
            $base = Get-ChannelBase $arg
            $label = if ($arg -is [hashtable]) { $arg.name } else { "$arg" }
            $msg = "opening channel $label"
            # cada separador do canal tem a sua lista, guardada 10 min: voltar ao canal ou mudar de separador é imediato
            # (abrir um separador pede logo os outros dois em segundo plano)
            $src = "$base/$ctab"; $key = Get-ChanKey $src
            $j = $Jobs[$key]
            $stale = -not $j -or $Fresh -or ([datetime]::Now - $j.t).TotalMinutes -gt 10 -or ($j.p.HasExited -and -not (Read-ListFile $j.f).Count)
            if ($stale) { Start-ListJob $key $src 45 @(Get-CookieArgs) $ChanFmt }
            foreach ($t in $ChanTabs.m) {
                $k2 = Get-ChanKey "$base/$t"
                if ($t -ne $ctab -and (-not $Jobs[$k2] -or ([datetime]::Now - $Jobs[$k2].t).TotalMinutes -gt 10)) { Start-ListJob $k2 "$base/$t" 45 @(Get-CookieArgs) $ChanFmt }
            }
        }
        default {
            if (-not (Get-CookieArgs)) { if (-not (Invoke-Login -Required)) { return $null } }
            Start-Tabs
            $label = ($Tabs | Where-Object m -eq $mode).n; $src = ($Tabs | Where-Object m -eq $mode).src
            $msg = if ($mode -eq 'home') { 'loading home' } else { "loading $label" }
        }
    }
    # ecrã limpo (topo + separador ativo) com o indicador ao centro enquanto carrega
    if (-not $Jobs[$key].p.HasExited) { [Console]::Write("$e[2J"); Draw-Header $L0 $q $false; if ($mode -ne 'channel') { Draw-Tabs @{ mode = $mode; label = $label } $L0 '' } }
    $v = Wait-List $key $msg
    if ($script:Canceled) { if ($key -eq 'search') { try { if (-not $Jobs[$key].p.HasExited) { $Jobs[$key].p.Kill() } } catch {} }; return $null }   # cancelado: fica onde estava
    if ($mode -eq 'channel') { $info = Get-ChannelInfo $Jobs[$key].f; if ($info -and $info.name -and $info.name -ne 'NA') { $label = $info.name }; foreach ($x in $v) { if ($x.ch -eq 'NA') { $x.ch = $label } } }
    if (-not $v -or $v.Count -eq 0) {
        $W = [Console]::WindowWidth; $m = if ($mode -eq 'later') { 'your watch later list is empty' } elseif ($mode -eq 'channel') { "this channel has no $(($ChanTabs | Where-Object m -eq $ctab).n)" } else { 'no results' }
        # o yt-dlp falhou (rede, sessão, YouTube)? mostra a última linha do erro em vez de só "sem resultados"
        $er = if ($Jobs[$key]) { Get-Content "$($Jobs[$key].f).err" -Encoding utf8 -EA 0 | Where-Object { $_.Trim() } | Select-Object -Last 1 }
        if (-not $Jobs[$key].p) { $er = "couldn't start yt-dlp" }
        if ($er) { $m = Fit ($er.Trim() -replace '^ERROR:\s*', '') ($W - 8); $m = $m.TrimEnd() }
        [Console]::Write("$e[$([Math]::Floor([Console]::WindowHeight / 2) + 1);$([Math]::Max(1, [Math]::Floor(($W - $m.Length) / 2)))H$(if ($er) { "$e[31m" } else { "$e[90m" })$m$e[0m"); Start-Sleep $(if ($er) { 3 } else { 1 }); return $null
    }
    @{ vids = $v; sel = 0; label = $label; q = $q; mode = $mode; arg = $arg; ctab = $ctab; info = $info; src = $src; done = $false }
}

[Console]::Write("$e[?1049h$e[?25l")   # ecrã alternativo, sem cursor
try {
    $L = Get-Layout @{ mode = 'home' }
    $hist = [Collections.Generic.Stack[object]]::new()   # vistas anteriores (Esc volta)
    $tabCache = @{}
    $cur = $null
    # yt login: so o ecra de entrar na conta (o "setup" usa-o); sai com 0 = sessao feita
    if ($Rest -and $Rest[0] -eq 'login') { $ok = Invoke-Login; $global:LASTEXITCODE = [int](-not $ok); return }
    if (-not (Get-CookieArgs)) { if (-not (Invoke-Login -Required)) { return } }   # (também para 'yt <pesquisa>' e 'yt -c')
    $audio = $Rest -and $Rest[0] -eq '-a'   # yt -a <pesquisa>: pesquisa e abre já o ecrã só áudio (sem pesquisa: pergunta-a)
    if ($audio) { $Rest = @($Rest | Select-Object -Skip 1) }
    if ($Rest -and $Rest[0] -eq '-c') { $cur = Load 'channel' (($Rest | Select-Object -Skip 1) -join ' '); Start-Tabs }
    elseif ($audio) { if ($Rest) { $cur = Load 'search' ($Rest -join ' '); Start-Tabs } }
    elseif ($Rest -and $Rest[0] -notin 'feed', 'home') { $cur = Load 'search' ($Rest -join ' '); Start-Tabs }
    else {
        if (-not (Get-CookieArgs)) { if (-not (Invoke-Login -Required)) { return } }   # sem sessão não se entra
        $hc = "$Dir\home-cache.txt"
        if ((Get-CookieArgs) -and -not $Rest -and (Test-Path $hc) -and ((Get-Date) - (Get-Item $hc).LastWriteTime).TotalMinutes -lt 30 -and (($hv = Read-ListFile $hc).Count)) {
            # página inicial já preparada em segundo plano (perfil do terminal): abre logo
            $cur = @{ vids = $hv; sel = 0; label = 'home'; q = ''; mode = 'home'; arg = ''; src = ':ytrec'; done = $false }
            $tabCache['home'] = $cur; Start-Tabs
        }
        elseif (Get-CookieArgs) { $cur = Load $(if ($Rest -and $Rest[0] -eq 'feed') { 'feed' } else { 'home' }) ''; if ($cur) { $tabCache[$cur.mode] = $cur } }
    }
    while (-not $cur) {
        [Console]::Write("$e[2J"); Draw-Header $L '' $false
        [Console]::Write("$e[6;$($L.left)H$e[90mtype what you want to watch (esc = quit)$e[0m")
        $q = Read-Search $L ''
        if (-not $q) { return }
        $cur = Load 'search' $q
    }
    if ($audio) { Show-Audio $cur; Clear-Keys }
    Trace 'lista pronta'; Draw-Page $cur; Trace 'grelha desenhada'
    while ($true) {
        # à espera de tecla: vai desenhando as imagens que ficam prontas e, parado 0,5 s num vídeo, resolve-o (o Enter abre logo)
        $sw = [Diagnostics.Stopwatch]::StartNew(); $pf = $false; $rz = 0
        [void][Yt.Con]::SetConsoleMode($InH, $InModeYt)   # (rato ligado)
        while (-not $script:PendingKey) {
            # rato: lido antes do KeyAvailable (que deita fora os eventos que nao sao teclas)
            if (($m = [Yt.Con]::Mouse($InH)) -and ($mk = Convert-Mouse $m $cur $L)) { $script:PendingKey = $mk; break }
            if ([Console]::KeyAvailable) { break }
            # janela redimensionada sem tecla nenhuma: redesenha já (de ~150 em ~150 ms)
            if ($rz++ % 5 -eq 0 -and ([Console]::WindowWidth -ne $L.W -or [Console]::WindowHeight -ne $L.H)) { Draw-Page $cur }
            Update-Pending
            # (1 s: com 0,5 s o yt-dlp arrancava a meio de uma sequencia de setas e roubava CPU ao desenho)
            if (-not $pf -and $sw.ElapsedMilliseconds -ge 1000) { Start-StreamPrefetch $cur.vids[$cur.sel].id; $pf = $true }
            Start-Sleep -Milliseconds 30
        }
        $k = if ($script:PendingKey) { $script:PendingKey; $script:PendingKey = $null } else { Read-Key }
        $ksw = [Diagnostics.Stopwatch]::StartNew()
        $old = $cur.sel; $oldStart = Get-Start $cur $L
        if ([Console]::WindowWidth -ne $L.W -or [Console]::WindowHeight -ne $L.H) { Draw-Page $cur; continue }
        if ($L.W -lt 70 -or $L.H -lt 22) { if ($k.Key -eq 'Escape' -or $k.KeyChar -eq 'q') { return }; continue }   # painel pequeno: só sair
        $n = $cur.vids.Count
        $tabTo = $null
        # passar do fim da lista (direita / baixo / PgDn) carrega mais vídeos
        $step = switch ($k.Key) { 'RightArrow' { 1 } 'DownArrow' { $L.cols } 'PageDown' { $L.per } 'F23' { $L.cols * $script:WheelRows } default { 0 } }
        if ($step -and $cur.sel + $step -gt $n - 1 -and (Add-More $cur)) { $n = $cur.vids.Count; $cur.sel = [Math]::Min($n - 1, $cur.sel + $step); Draw-Page $cur; continue }
        # seta segura (repeticao do teclado): junta as setas que ja estao na fila num so passo, para o desenho nao ficar
        # atrasado em relacao ao teclado
        $rep = 1
        if ($k.Key -in 'RightArrow', 'LeftArrow', 'DownArrow', 'UpArrow') {
            while ([Console]::KeyAvailable) { $k2 = Read-Key; if ($k2.Key -eq $k.Key) { $rep++ } else { $script:PendingKey = $k2; break } }
        }
        switch ($k.Key) {
            'RightArrow' { $cur.sel = [Math]::Min($n - 1, $cur.sel + $rep) }
            'LeftArrow'  { $cur.sel = [Math]::Max(0, $cur.sel - $rep) }
            'DownArrow'  { $cur.sel = [Math]::Min($n - 1, $cur.sel + $L.cols * $rep) }
            'UpArrow'    { $cur.sel = [Math]::Max(0, $cur.sel - $L.cols * $rep) }
            'PageDown'   { $cur.sel = [Math]::Min($n - 1, $cur.sel + $L.per) }
            'PageUp'     { $cur.sel = [Math]::Max(0, $cur.sel - $L.per) }
            'F23'        { Move-Rows $cur $L $script:WheelRows }   # roda para baixo (Convert-Mouse)
            'F21'        { $cur.sel = $script:HoverSel }           # rato por cima de outro video
            'F22'        { Move-Rows $cur $L (-$script:WheelRows) }
            'Tab' {
                $d = if ($k.Modifiers -band [ConsoleModifiers]::Shift) { -1 } else { 1 }
                if ($cur.mode -eq 'channel') {
                    # no canal, o Tab muda entre vídeos / shorts / diretos
                    $i = [array]::IndexOf(@($ChanTabs | ForEach-Object { $_.m }), $cur.ctab)
                    $ct = $ChanTabs[(($i + $d) % $ChanTabs.Count + $ChanTabs.Count) % $ChanTabs.Count].m
                    $v = Load 'channel' $cur.arg $ct
                    if ($v) { $cur = $v }
                    Draw-Page $cur; continue
                }
                $i = [array]::IndexOf(@($Tabs | ForEach-Object { $_.m }), $cur.mode)
                if ($i -lt 0) { $i = if ($d -gt 0) { -1 } else { 0 } }
                $tabTo = $Tabs[(($i + $d) % $Tabs.Count + $Tabs.Count) % $Tabs.Count].m
            }
            'Enter'      { Show-Watch $cur; Clear-Keys; Draw-Page $cur; continue }   # página do vídeo
            'Escape'     { if ($hist.Count -eq 0) { return }; $cur = $hist.Pop(); Draw-Page $cur; continue }
        }
        if ($cur.mode -eq 'channel' -and $k.KeyChar -in '1', '2', '3') {
            # no canal, 1-3 = vídeos / shorts / diretos
            $ct = $ChanTabs[[int]"$($k.KeyChar)" - 1].m
            if ($ct -ne $cur.ctab) { $v = Load 'channel' $cur.arg $ct; if ($v) { $cur = $v }; Draw-Page $cur }
            continue
        }
        if ($k.KeyChar -in '1', '2', '3', '4') { $tabTo = $Tabs[[int]"$($k.KeyChar)" - 1].m }
        if ($tabTo) {
            # muda já o separador ativo (resposta imediata) e depois mostra a lista (normalmente já carregada)
            if ($cur.mode -ne 'channel') { Draw-Tabs @{ mode = $tabTo } $L '' }
            $hist.Clear()
            $v = if ($tabCache.ContainsKey($tabTo)) { $tabCache[$tabTo] } else { Load $tabTo '' }
            if ($v) { $tabCache[$tabTo] = $v; $cur = $v }
            Draw-Page $cur; continue
        }
        $new = $null; $redraw = $false
        switch -CaseSensitive ($k.KeyChar) {
            'q' { return }
            '?' { Show-Help $L; $redraw = $true }
            'o' { Invoke-Play $cur.vids[$cur.sel]; Clear-Keys; $redraw = $true }
            'a' { Show-Audio $cur; Clear-Keys; $redraw = $true }   # ecrã só áudio
            { $_ -eq '/' -or $_ -eq 's' -or $_ -eq [char]6 } { $q = Read-Search $L $cur.q { Draw-Page $cur }; if ($q) { $new = Load 'search' $q }; $redraw = $true }   # / ou s ou Ctrl+F
            'c' {
                # canal do vídeo selecionado
                $x = $cur.vids[$cur.sel]
                if ($cur.mode -ne 'channel') { $new = Load 'channel' @{ id = $x.chid; name = $x.ch } }
            }
            'r' {
                if ($cur.mode -eq 'search') { $fresh = Load 'search' $cur.arg }
                elseif ($cur.mode -eq 'channel') { $fresh = Load 'channel' $cur.arg $cur.ctab -Fresh }
                else { Start-ListJob $cur.mode ($Tabs | Where-Object m -eq $cur.mode).src 45 (Get-CookieArgs); $fresh = Load $cur.mode '' }
                if ($fresh) { $cur = $fresh; if ($cur.mode -in @($Tabs | ForEach-Object { $_.m })) { $tabCache[$cur.mode] = $cur } }
                $redraw = $true
            }
            'l' { [void](Invoke-Login); $tabCache.Clear(); foreach ($j in $Jobs.Values) { try { if (-not $j.p.HasExited) { $j.p.Kill() } } catch {} }; $Jobs.Clear(); $HistMerged = $false; Start-Tabs; $redraw = $true }
        }
        if ($new) { $hist.Push($cur); $cur = $new }
        if ($new -or $redraw) { Draw-Page $cur; continue }
        if ($cur.sel -ne $old) {
            $ns2 = Get-Start $cur $L
            if ($ns2 -ne $oldStart) {
                # (a grelha andou: uma fila so -> desliza e desenha a fila nova; mais -> redesenha tudo)
                $dr = ($ns2 - $oldStart) / $L.cols
                if ([Math]::Abs($dr) -eq 1 -and (Scroll-Grid $cur $L ([int]$dr))) {
                    $base = $ns2; $os = $old - $base
                    if ($os -ge 0 -and $os -lt $L.per) { Draw-TileText $cur.vids[$old] $os $L $false }
                    Draw-TileText $cur.vids[$cur.sel] ($cur.sel - $base) $L $true
                } else { Draw-Page $cur }
            }
            else {
                $base = Get-Start $cur $L
                Draw-TileText $cur.vids[$old] ($old - $base) $L $false
                Draw-TileText $cur.vids[$cur.sel] ($cur.sel - $base) $L $true
            }
            Draw-Count $cur $L; Trace "tecla $($k.Key) $($ksw.ElapsedMilliseconds) ms"
        }
    }
}
finally {
    Set-Hints ''; [Console]::Write("$e[0m$e[?25h$e[?1049l")   # volta ao ecrã normal
    foreach ($j in $Jobs.Values) { try { if (-not $j.p.HasExited) { $j.p.Kill() } } catch {} }
    Clear-Ck -All; foreach ($f in $ListFiles) { foreach ($x in $f, "$f.err") { try { [IO.File]::Delete($x) } catch {} } }
    Get-Job -Name yt -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
}
