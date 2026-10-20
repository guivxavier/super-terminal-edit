# paleta do tema (comando theme -> ~\.config\superterminal\theme.json) como "r;g;b" para as cores 24-bit dos TUIs:
#   "$e[48;2;$($StTheme.sel)m". Sem ficheiro: One Dark.
$StTheme = @{ bg = '40;44;52'; dark = '33;37;43'; surf = '44;49;58'; surf2 = '52;58;68'; sel = '62;68;81'; line = '75;82;99'; comment = '92;99;112'
    fg = '171;178;191'; red = '224;108;117'; green = '152;195;121'; yellow = '229;192;123'; blue = '97;175;239'; magenta = '198;120;221'; cyan = '86;182;194'; white = '255;255;255' }
try {
    (Get-Content "$HOME\.config\superterminal\theme.json" -Raw -ErrorAction Stop | ConvertFrom-Json).PSObject.Properties |
        Where-Object { "$($_.Value)" -match '^#[0-9a-fA-F]{6}$' } |
        ForEach-Object { $c = [Convert]::FromHexString($_.Value.Substring(1)); $StTheme[$_.Name] = "$($c[0]);$($c[1]);$($c[2])" }
} catch {}
