-- Guarda o volume do mpv entre vídeos e sessões (usado pelo yt): ~/.config/mpv-volume.txt
local file = (os.getenv('USERPROFILE') or os.getenv('HOME')) .. '/.config/mpv-volume.txt'

local f = io.open(file, 'r')
if f then
    local v = tonumber(f:read('*a'))
    f:close()
    if v then mp.set_property_number('volume', v) end
end

mp.observe_property('volume', 'number', function(_, v)
    if v then
        local o = io.open(file, 'w')
        if o then o:write(string.format('%.0f', v)); o:close() end
    end
end)
