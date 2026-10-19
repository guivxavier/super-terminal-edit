# Prepara a configuração do mpv usada pelo 'yt' em ~\.config\mpv: interface moderna (uosc) + miniaturas na barra (thumbfast)
$ErrorActionPreference = 'Stop'; [Net.ServicePointManager]::SecurityProtocol = 'Tls12'; $ProgressPreference = 'SilentlyContinue'
$cfg = "$HOME\.config\mpv"
New-Item -ItemType Directory "$cfg\scripts", "$cfg\script-opts", "$cfg\fonts" -Force | Out-Null
$tmp = Join-Path $env:TEMP "uosc-$(Get-Random)"; New-Item -ItemType Directory $tmp | Out-Null
Invoke-WebRequest 'https://github.com/tomasklaen/uosc/releases/latest/download/uosc.zip' -OutFile "$tmp\uosc.zip" -UseBasicParsing
Expand-Archive "$tmp\uosc.zip" $tmp -Force
Copy-Item "$tmp\scripts\*" "$cfg\scripts" -Recurse -Force
Copy-Item "$tmp\fonts\*" "$cfg\fonts" -Recurse -Force
Invoke-WebRequest 'https://raw.githubusercontent.com/po5/thumbfast/master/thumbfast.lua' -OutFile "$cfg\scripts\thumbfast.lua" -UseBasicParsing
Copy-Item "$HOME\.config\mpv-keep-volume.lua" "$cfg\scripts\keep-volume.lua" -Force
[IO.Directory]::Delete($tmp, $true)

# mpv.conf: sem a interface antiga, sem bordas; a uosc trata dos controlos
@'
osc=no
osd-bar=no
border=no
keep-open=no
background=color
background-color='#282C34'
osd-font=CaskaydiaMono Nerd Font
title=${media-title}
ytdl-format=bestvideo[height<=1080][vcodec^=avc1]+bestaudio/bestvideo[height<=1080]+bestaudio/best
hwdec=auto-safe
'@ | Set-Content "$cfg\mpv.conf" -Encoding utf8

# uosc: só o essencial — barra, volume, qualidade do vídeo e ecrã inteiro (o título aparece no terminal)
@'
timeline_style=line
timeline_line_width=3
timeline_size=40
progress=windowed
progress_size=2
top_bar=never
controls=space,stream-quality,fullscreen
stream_quality_options=1080,720,480,360
volume=right
color=foreground=E06C75,foreground_text=282C34,background=21252B,background_text=ABB2BF
font_scale=1.1
autohide=yes
'@ | Set-Content "$cfg\script-opts\uosc.conf" -Encoding utf8

# thumbfast: miniaturas também em streams (YouTube)
"network=yes" | Set-Content "$cfg\script-opts\thumbfast.conf" -Encoding utf8

Get-ChildItem $cfg -Recurse -Depth 1 | ForEach-Object { $_.FullName.Replace($cfg, '') }
