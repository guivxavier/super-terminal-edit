# VM de teste "PC limpo" (VirtualBox, no desktop): Windows 11 novo, para experimentar o install.cmd + setup como o colega.
#   pwsh -File create-vm.ps1 [-Iso <imagem.iso>]
# Pede o nome e a password do utilizador da VM (escreves tu). Sem chave do Windows: corre sem estar ativado (chega
# para testar). No fim da instalacao, tira um snapshot "limpo" para voltar ao zero:  VBoxManage snapshot SuperTerminal-Test take limpo
param([string]$Iso, [string]$Name = 'SuperTerminal-Test', [string]$Dir = 'D:\VMs', [int]$RamMB = 6144, [int]$Cpus = 4, [int]$DiskGB = 64)
$ErrorActionPreference = 'Stop'
$vbm = "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe"
if (-not (Test-Path $vbm)) { throw 'VirtualBox nao esta instalado (Downloads\VirtualBox-*-Win.exe)' }
function VBox { & $vbm @args; if ($LASTEXITCODE) { throw "VBoxManage $($args[0]) falhou ($LASTEXITCODE)" } }

if (-not $Iso) { $Iso = (Get-ChildItem "$HOME\Downloads", 'D:\', $Dir -Filter 'Win11*.iso' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName }
if (-not $Iso -or -not (Test-Path $Iso)) { throw 'nao encontrei a imagem do Windows 11 (Win11*.iso nas Transferencias): passa -Iso <caminho>' }
"imagem: $Iso"
if ((& $vbm list vms) -match "`"$Name`"") { throw "ja existe uma VM '$Name' (apaga-a no VirtualBox ou usa -Name outro)" }

# edicao: Pro se houver, senao a 1.a (o "detect" lista as imagens da ISO)
$det = (& $vbm unattended detect --iso=$Iso 2>&1) -join "`n"
$idx = ([regex]::Matches($det, "Image #(\d+)\s*=\s*([^\r\n]+)") | Where-Object { $_.Groups[2].Value -match 'Pro\b' -and $_.Groups[2].Value -notmatch 'N\b|Education|Workstation' } | Select-Object -First 1).Groups[1].Value
if (-not $idx) { $idx = 1 }
"edicao: imagem #$idx"

$user = Read-Host 'utilizador da VM (ex.: teste)'
$pw = Read-Host 'password desse utilizador' -AsSecureString
$plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw))

New-Item -ItemType Directory $Dir -Force | Out-Null
VBox createvm --name $Name --ostype Windows11_64 --basefolder $Dir --register
VBox modifyvm $Name --memory $RamMB --cpus $Cpus --firmware efi --tpm-type 2.0 --graphicscontroller vboxsvga --vram 128 --nic1 nat --clipboard-mode bidirectional --draganddrop hosttoguest
$vdi = Join-Path $Dir "$Name\$Name.vdi"
VBox createmedium disk --filename $vdi --size ($DiskGB * 1024) --format VDI
VBox storagectl $Name --name SATA --add sata --controller IntelAhci
VBox storageattach $Name --storagectl SATA --port 0 --device 0 --type hdd --medium $vdi
# o repo dentro da VM, so de leitura: \\vboxsvr\SuperTerminal (o install.cmd corre dali)
VBox sharedfolder add $Name --name SuperTerminal --hostpath 'D:\PROJECTS\SuperTerminal' --readonly --automount
try {
    VBox unattended install $Name "--iso=$Iso" "--user=$user" "--password=$plain" "--full-user-name=$user" --image-index=$idx --locale=pt_PT --country=PT --time-zone=Europe/Lisbon --install-additions --start-vm=gui
} finally { $plain = $null }
''
'a instalar (uns 15-30 min; a VM reinicia sozinha algumas vezes).'
'quando estiveres no ambiente de trabalho da VM:'
"  1. snapshot limpo:  & '$vbm' snapshot $Name take limpo"
'  2. na VM: Explorador > Rede > \\vboxsvr\SuperTerminal > install.cmd'
"  para voltar ao zero:  & '$vbm' snapshot $Name restore limpo   (com a VM desligada)"
