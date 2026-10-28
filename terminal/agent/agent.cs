// SuperTerminal agent: Ctrl+Alt+T mostra / esconde o WezTerm de qualquer lado (abre-o se nao estiver aberto).
// Arranca com o Windows, elevado, pela tarefa TerminalKeepAlive (system/wt-keepalive.ps1), com --prelaunch: abre o
// WezTerm logo e esconde-o, para o 1.o Ctrl+Alt+T ser instantaneo. Compila com o csc do .NET Framework, que vem com o Windows:
//   csc /nologo /target:winexe /out:agent.exe agent.cs
// Uso: agent.exe [--prelaunch] [--key T] [--hide] [--wezterm <wezterm-gui.exe>]
//   --hide: so esconde a janela e sai (o Ctrl+W no ultimo painel usa isto)
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

static class Agent {
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mod, uint vk);
    [DllImport("user32.dll")] static extern int GetMessage(out MSG m, IntPtr h, uint a, uint b);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] static extern IntPtr GetShellWindow();
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int idx);
    [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int val, int size);
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int l, t, r, b; }
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [StructLayout(LayoutKind.Sequential)] struct MSG { public IntPtr hwnd; public uint message; public IntPtr w, l; public uint time; public int x, y; }

    const uint MOD_ALT = 1, MOD_CONTROL = 2, MOD_NOREPEAT = 0x4000;
    const int SW_HIDE = 0, SW_SHOW = 5, SW_RESTORE = 9;
    static string Gui = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @".local\wezterm\wezterm-gui.exe");

    // janela do WezTerm (visivel ou escondida): classe "org.wezfurlong.wezterm". (A janela escondida que o WezTerm usa
    // para testar o OpenGL tem a mesma classe: se ela viesse 1.o, o atalho mostrava-a a ela e nao escondia o terminal)
    static IntPtr Find() {
        IntPtr found = IntPtr.Zero; var sb = new StringBuilder(64); var t = new StringBuilder(64);
        EnumWindows((h, l) => {
            sb.Length = 0; GetClassName(h, sb, sb.Capacity);
            if (sb.ToString() != "org.wezfurlong.wezterm") return true;
            t.Length = 0; GetWindowText(h, t, t.Capacity);
            if (t.ToString().StartsWith("wezterm wgl")) return true;
            found = h; return false;
        }, IntPtr.Zero);
        return found;
    }

    // ha alguma janela normal por cima dela? (sem isto o atalho so escondia com o terminal com o foco: com o foco na
    // barra de tarefas, num widget ou no ambiente de trabalho, mostrava-o outra vez - ja estava a vista: nada mudava)
    static bool Covered(IntPtr h) {
        RECT r; GetWindowRect(h, out r);
        for (IntPtr w = GetWindow(h, 3); w != IntPtr.Zero; w = GetWindow(w, 3)) {   // GW_HWNDPREV: as de cima
            if (!IsWindowVisible(w) || IsIconic(w) || GetWindowTextLength(w) == 0 || (GetWindowLong(w, -20) & 0x80) != 0) continue;
            int cloaked = 0; DwmGetWindowAttribute(w, 14, out cloaked, 4); if (cloaked != 0) continue;   // DWMWA_CLOAKED (apps UWP escondidas)
            RECT o; GetWindowRect(w, out o);
            if (o.l < r.r && o.r > r.l && o.t < r.b && o.b > r.t) return true;
        }
        return false;
    }

    // sem a animacao (fade) do Windows ao mostrar / esconder: o atalho fica instantaneo
    static void NoAnim(IntPtr h) { int on = 1; DwmSetWindowAttribute(h, 3, ref on, 4); }   // DWMWA_TRANSITIONS_FORCEDISABLED

    // a janela que estava a frente antes de o terminal aparecer: recebe o foco quando ele se esconde
    static IntPtr Prev = IntPtr.Zero;

    static void Focus(IntPtr t) {
        // (o Windows so deixa dar o foco a quem o tem: junta-se a fila de entrada da janela da frente)
        uint fg = GetWindowThreadProcessId(GetForegroundWindow(), IntPtr.Zero), me = GetCurrentThreadId();
        AttachThreadInput(me, fg, true); SetForegroundWindow(t); AttachThreadInput(me, fg, false);
    }

    // a proxima janela "normal" visivel por baixo (com titulo, sem ser janela de ferramentas)
    static IntPtr Below(IntPtr h) {
        for (IntPtr w = GetWindow(h, 2); w != IntPtr.Zero; w = GetWindow(w, 2))   // GW_HWNDNEXT
            if (IsWindowVisible(w) && !IsIconic(w) && GetWindowTextLength(w) > 0 && (GetWindowLong(w, -20) & 0x80) == 0) return w;   // GWL_EXSTYLE / WS_EX_TOOLWINDOW
        return IntPtr.Zero;
    }

    // escondido: o cabecalho (terminal/wezterm/header.ps1) para de correr o fastfetch a cada 2 s enquanto ninguem o ve
    static string HiddenFlag = Path.Combine(Path.GetTempPath(), "superterminal-hidden");
    static void Hidden(bool on) { try { if (on) File.WriteAllText(HiddenFlag, ""); else File.Delete(HiddenFlag); } catch { } }

    // esconde e entrega o foco: sem isto o Windows fica sem janela ativa e, nalguns PCs, o ecra so se redesenha
    // (e deixa de mostrar o terminal) depois de um clique
    static void Hide(IntPtr h) {
        IntPtr next = Below(h);
        NoAnim(h); ShowWindow(h, SW_HIDE); Hidden(true);
        IntPtr t =(Prev != IntPtr.Zero && Prev != h && IsWindow(Prev) && IsWindowVisible(Prev) && !IsIconic(Prev)) ? Prev : next;
        if (t == IntPtr.Zero) t = GetShellWindow();   // (nada aberto: o ambiente de trabalho)
        if (t != IntPtr.Zero) Focus(t);
    }

    static void Front(IntPtr h) {
        IntPtr f = GetForegroundWindow(); if (f != h && f != IntPtr.Zero) Prev = f;
        NoAnim(h); Hidden(false);
        ShowWindow(h, SW_SHOW);
        if (IsIconic(h)) ShowWindow(h, SW_RESTORE);
        Focus(h);
    }

    static IntPtr Launch() {
        if (!File.Exists(Gui)) return IntPtr.Zero;
        // pelo explorer.exe: o WezTerm abre sempre como utilizador normal, mesmo com o agente elevado (o agente corre
        // elevado para conseguir mostrar / esconder qualquer janela; um programa normal nao mexe numa janela de admin)
        Process.Start(new ProcessStartInfo("explorer.exe", "\"" + Gui + "\"") { UseShellExecute = false });
        // mal a janela aparece, esconde-a ate o WezTerm acabar de arrancar (ecra inteiro, cabecalho, shell): assim
        // aparece ja pronta, sem os saltos e redesenhos do arranque
        for (int i = 0; i < 200; i++) {
            var h = Find();
            if (h != IntPtr.Zero && IsWindowVisible(h)) { NoAnim(h); ShowWindow(h, SW_HIDE); Hidden(true); Thread.Sleep(1200); return h; }
            Thread.Sleep(25);
        }
        return IntPtr.Zero;
    }

    static void Toggle() {
        var h = Find();
        if (h == IntPtr.Zero) { h = Launch(); if (h != IntPtr.Zero) Front(h); return; }
        if (IsWindowVisible(h) && !IsIconic(h) && (GetForegroundWindow() == h || !Covered(h))) Hide(h);
        else Front(h);
    }

    [STAThread]
    static int Main(string[] args) {
        uint vk = 'T'; bool prelaunch = false;
        for (int i = 0; i < args.Length; i++) {
            if (args[i] == "--hide") { var h = Find(); if (h != IntPtr.Zero) Hide(h); return 0; }
            if (args[i] == "--prelaunch") prelaunch = true;
            if (args[i] == "--key" && i + 1 < args.Length) vk = char.ToUpperInvariant(args[++i][0]);
            if (args[i] == "--wezterm" && i + 1 < args.Length) Gui = args[++i];
        }
        bool first; var mutex = new Mutex(true, "SuperTerminalAgent", out first);
        if (!first) return 0;   // ja ha um a correr
        if (!RegisterHotKey(IntPtr.Zero, 1, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, vk)) {
            // outro programa tem o atalho (ex.: o globalSummon do Windows Terminal)
            File.WriteAllText(Path.Combine(Path.GetTempPath(), "superterminal-agent.err"), "Ctrl+Alt+" + (char)vk + " is taken by another program");
            return 1;
        }
        if (prelaunch && Find() == IntPtr.Zero) Launch();   // (o Launch ja a deixa escondida)
        MSG m;
        while (GetMessage(out m, IntPtr.Zero, 0, 0) > 0) if (m.message == 0x0312) Toggle();   // WM_HOTKEY
        GC.KeepAlive(mutex);
        return 0;
    }
}
