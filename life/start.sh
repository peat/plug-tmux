#!/bin/bash
# Usage: ./start.sh [tmux socket args...]   e.g. ./start.sh -L golprobe
# Creates session "life", loads the board, seeds a glider + blinker, starts the tmux-driven loop.
cd "$(dirname "$0")"; T=(/usr/bin/tmux "$@")
[ -f life.conf ] || ./gen.sh
"${T[@]}" has -t life 2>/dev/null || "${T[@]}" new -d -s life -n life
"${T[@]}" source-file "$PWD/life.conf"
for rc in 0_1 1_2 2_0 2_1 2_2  6_6 6_7 6_8; do "${T[@]}" set -g @c_$rc 1; done
"${T[@]}" set -g @delay 0.3
"${T[@]}" bind -T root F5 'set -g @running 0'
"${T[@]}" bind -T root F6 'set -g @running 1 ; run -C "#{@tick}"'
"${T[@]}" set -g @running 1
"${T[@]}" source-file "$PWD/step.conf"
