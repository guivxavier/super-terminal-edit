#!/bin/sh
# Mostra uma linha da cache do Tailscale (feita no Windows) a partir do WSL.
# Se uma das linhas tiver um IP deste WSL (Tailscale proprio), o "<-" passa do Windows para essa linha.
f=$1; [ -f "$f" ] || exit 1
e=$(printf '\033')
dir=${f%/*}
mine=''
for ip in $(grep -ho '100\.[0-9]*\.[0-9]*\.[0-9]*' "$dir"/ts[2-6].txt 2>/dev/null); do
    hostname -I 2>/dev/null | grep -qw "$ip" && mine=$ip
done
if [ -z "$mine" ]; then cat "$f"; exit; fi
if grep -qF "$mine " "$f"; then   # (sem -w: o IP vem colado a um codigo de cor)
    sed -e "s/${e}\[1;37m/${e}[1;36m/" -e "s/\$/${e}[0;36m<-${e}[0m/" "$f"
else
    sed -e "s/${e}\[1;36m/${e}[1;37m/" -e "s/${e}\[0;36m<-//" "$f"
fi
