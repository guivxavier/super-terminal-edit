@echo off
rem SuperTerminal: double click to install (runs install.ps1 next to this file)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
pause
