' Lanca o ts-cache.ps1 escondido e sem esperar (para nao atrasar a abertura do terminal)
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & sh.ExpandEnvironmentStrings("%USERPROFILE%") & "\.config\ts-cache.ps1""", 0, False
