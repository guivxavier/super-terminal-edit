param($f)
$tk=$null;$er=$null;$ast=[System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$tk,[ref]$er)
$bad=@($ast.FindAll({param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in 'else','elseif'},$true))
"$(Split-Path $f -Leaf): erros $($er.Count), else soltos $($bad.Count)"; $er | Select-Object -First 5 | ForEach-Object { "  L$($_.Extent.StartLineNumber): $($_.Message)" }
