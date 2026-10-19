# Atalhos do SuperTerminal: "SuperTerminal" no menu Iniciar abre o WezTerm.
# Tem de correr fora de processos empacotados (MSIX), senao os atalhos ficam numa copia virtual do AppData.
$sh = New-Object -ComObject WScript.Shell
$base = "$HOME\.local"
$programs = [Environment]::GetFolderPath('Programs'); $startup = [Environment]::GetFolderPath('Startup')

# (o agente ja nao arranca pela pasta Startup, onde correria sem admin: arranca elevado pela tarefa TerminalKeepAlive)
Remove-Item "$startup\SuperTerminal agent.lnk" -ErrorAction Ignore

$l = $sh.CreateShortcut("$programs\SuperTerminal.lnk")
$l.TargetPath = "$base\wezterm\wezterm-gui.exe"; $l.WorkingDirectory = $HOME; $l.IconLocation = "$base\wezterm\wezterm-gui.exe,0"
$l.Description = 'SuperTerminal (WezTerm)'; $l.Save()

Get-Item "$programs\SuperTerminal.lnk" | ForEach-Object FullName
