# Liga o servidor SSH neste PC e autoriza a chave do outro PC (para "ssh laptop" a partir do desktop).
# Corre num terminal de administrador:   & "$HOME\.config\setup-sshd.ps1"
# Mexe em definicoes de seguranca do Windows (servico, firewall, chaves autorizadas): por isso es tu que o corres.
$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'abre o terminal como administrador' }

# 1) servidor OpenSSH (componente do Windows)
# (dism.exe direto: o Add-WindowsCapability no PowerShell 7 fica em ciclo com o erro 0x80040154)
if (-not (Test-Path "$env:WINDIR\System32\OpenSSH\sshd.exe")) {
    'a instalar o OpenSSH Server (descarrega do Windows Update; pode demorar uns minutos)...'
    dism.exe /Online /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0 /NoRestart
    if ($LASTEXITCODE -notin 0, 3010) { throw "o dism falhou (codigo $LASTEXITCODE)" }
    'OpenSSH Server instalado'
}
Set-Service sshd -StartupType Automatic; Start-Service sshd; "sshd: $((Get-Service sshd).Status)"

# 2) firewall: so a porta 22 (a regra que o Windows cria; se faltar, cria-se)
if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) { New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null }
# (so para a rede do Tailscale e a rede local: o wake usa o IP local; da internet nao)
Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -RemoteAddress '100.64.0.0/10', 'fd7a:115c:a1e0::/48', 'LocalSubnet'
'firewall: porta 22 aberta (Tailscale e rede local)'

# 3) chave do outro PC: contas de administrador usam C:\ProgramData\ssh\administrators_authorized_keys
$pub = (Get-Content "$HOME\.config\desktop-key.pub" -Raw).Trim()
$ak = "$env:ProgramData\ssh\administrators_authorized_keys"
$cur = if (Test-Path $ak) { Get-Content $ak -Raw } else { '' }
if ($cur -notmatch [regex]::Escape($pub)) { Add-Content $ak $pub -Encoding ascii; 'chave do desktop autorizada' } else { 'chave do desktop ja estava autorizada' }
icacls $ak /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F' | Out-Null   # Administradores + SYSTEM (SIDs: servem em qualquer lingua); o sshd recusa o ficheiro se outros o puderem ler
'pronto: no desktop, "ssh laptop"'
