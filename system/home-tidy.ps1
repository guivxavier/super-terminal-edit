# Home limpa como no Linux: esconde (atributo "oculto", nada e apagado nem movido) o que comeca por ponto,
# as pastas do Windows que nao se usam e as pastas de programas que tem de ficar na home.
# Corre ao iniciar sessao (chamado pelo wt-keepalive.ps1). Para ver tudo: la  (ou ls -Force)
# Compativel com o PowerShell 5.1.
$winHide = 'Contacts', 'Favorites', 'Links', 'Searches', 'Saved Games', '3D Objects'
$toolHide = 'scoop', 'curseforge', 'vscode-remote-wsl', 'bgutil-ytdlp-pot-provider', 'ansel', 'OpenplanetNext', 'PaceKeyChain', 'OneDrive'
$n = 0
foreach ($i in Get-ChildItem $HOME -Force -ErrorAction SilentlyContinue) {
    if ($i.Attributes -band [IO.FileAttributes]::Hidden) { continue }
    if ($i.Name -like '.*' -or $i.Name -in $winHide -or $i.Name -in $toolHide) {
        try { $i.Attributes = $i.Attributes -bor [IO.FileAttributes]::Hidden; $n++ } catch {}
    }
}
if ($args -contains '-v') { "escondidos agora: $n" }
