#!/bin/bash
# corre o zsh num tmux invisivel (120x40), manda teclas e mostra o ecra: tmux-test.sh "keys1" "keys2" ...
tmux kill-session -t kt 2>/dev/null
tmux new-session -d -s kt -x 140 -y 40 "zsh -i"
sleep 3
for k in "$@"; do
  case "$k" in
    @*) tmux send-keys -t kt "${k#@}" ;;      # tecla especial (Enter, C-Space, Tab, Escape, C-h...)
    *)  tmux send-keys -t kt -l "$k" ;;       # texto literal
  esac
  sleep 0.8
done
tmux capture-pane -t kt -p | sed '/^\s*$/d' | tail -25
tmux kill-session -t kt
