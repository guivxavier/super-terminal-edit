# teste interativo real em passos: abre pwsh (perfil completo) escondido; $env:HSTEPS = "t:cd |cs|snap|tab|snap|t:lo|snap|esc|snap"
#   t:<texto> escreve; cs = Ctrl+Espaco; tab; enter; esc; bs = backspace; snap = grava o ecra (secao no log)
$log = Join-Path $env:TEMP 'vt\keys-steps.txt'
trap { "ERRO: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" | Add-Content $log; exit }
Add-Type -Namespace T3 -Name C -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern bool FreeConsole();
[DllImport("kernel32.dll")] public static extern bool AttachConsole(int pid);
[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr CreateFileW(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr tmpl);
[StructLayout(LayoutKind.Explicit, CharSet = CharSet.Unicode)] public struct REC { [FieldOffset(0)] public ushort Type; [FieldOffset(4)] public int Down; [FieldOffset(8)] public ushort Repeat; [FieldOffset(10)] public ushort Vk; [FieldOffset(12)] public ushort Scan; [FieldOffset(14)] public char Ch; [FieldOffset(16)] public uint Ctrl; }
[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern bool WriteConsoleInputW(IntPtr h, REC[] r, uint n, out uint w);
[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern bool ReadConsoleOutputCharacterW(IntPtr h, System.Text.StringBuilder b, uint len, uint coord, out uint read);
public static void Key(IntPtr h, ushort vk, char ch, uint ctrl) { var r = new REC[2]; for (int i = 0; i < 2; i++) { r[i].Type = 1; r[i].Down = i == 0 ? 1 : 0; r[i].Repeat = 1; r[i].Vk = vk; r[i].Ch = ch; r[i].Ctrl = ctrl; } uint w; WriteConsoleInputW(h, r, 2, out w); }
'@
$env:KVN_CMD = $env:HKVN
$p = Start-Process pwsh -WindowStyle Hidden -PassThru -WorkingDirectory $HOME -ArgumentList '-NoLogo'
Start-Sleep 6
[void][T3.C]::FreeConsole(); if (-not [T3.C]::AttachConsole($p.Id)) { throw 'AttachConsole falhou' }
$in = [T3.C]::CreateFileW('CONIN$', [uint32]3221225472, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
$out = [T3.C]::CreateFileW('CONOUT$', [uint32]3221225472, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
Set-Content $log '' -Encoding utf8
foreach ($s in $env:HSTEPS -split '\|') {
    switch -Regex ($s) {
        '^t:(.*)$' { foreach ($c in $Matches[1].ToCharArray()) { $vk = if ([char]::IsLetterOrDigit($c) -or $c -eq ' ') { [uint16][char]::ToUpper($c) } else { 0 }; [T3.C]::Key($in, $vk, $c, 0) } }
        '^cs$'    { [T3.C]::Key($in, 0x20, ' ', 0x8) }
        '^tab$'   { [T3.C]::Key($in, 0x09, [char]9, 0) }
        '^right$' { [T3.C]::Key($in, 0x27, [char]0, 0) }
        '^enter$' { [T3.C]::Key($in, 0x0D, [char]13, 0) }
        '^esc$'   { [T3.C]::Key($in, 0x1B, [char]27, 0) }
        '^bs$'    { [T3.C]::Key($in, 0x08, [char]8, 0) }
        '^cbs$'   { [T3.C]::Key($in, 0x08, [char]127, 0x8) }
        '^cc$'    { [T3.C]::Key($in, 0x43, [char]3, 0x8) }
        '^f1$'    { [T3.C]::Key($in, 0x70, [char]0, 0) }
        '^snap$'  {
            Start-Sleep 1.5
            $sb = [Text.StringBuilder]::new(120 * 30); $r = 0
            [void][T3.C]::ReadConsoleOutputCharacterW($out, $sb, 120 * 30, 0, [ref]$r)
            $t = $sb.ToString(); $ls = for ($i = 0; $i -lt 30 -and ($i + 1) * 120 -le $t.Length; $i++) { $t.Substring($i * 120, 120).TrimEnd() }
            "=== snap" | Add-Content $log -Encoding utf8; ($ls | Where-Object { $_ }) | Add-Content $log -Encoding utf8
        }
    }
    Start-Sleep -Milliseconds 300
}
Stop-Process -Id $p.Id -Force
"=== fim" | Add-Content $log -Encoding utf8
