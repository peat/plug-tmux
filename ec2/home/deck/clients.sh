#!/usr/bin/env bash
# Live head count: who's in the type fight, who's watching the slides, and what terminals they brought.
SOCK=${DECK_SOCKET:-/srv/plug/talk}; [[ -S $SOCK ]] || SOCK=/tmp/deck-$UID
B=$'\e[1m' Y=$'\e[1;33m' C=$'\e[1;36m' D=$'\e[2m' R=$'\e[0m'
fight() {   # minus the deck's own fight window, which is a client too (behind sudo's pty, so match by process)
  local mine pid term p
  mine=$(tmux -S "$SOCK" display -p -t 'talk:=fight' '#{pane_pid}' 2>/dev/null)
  sudo -n -u demo /usr/local/bin/tmux -L fight list-clients -F '#{client_pid} #{client_termname}' 2>/dev/null |
    while read -r pid term; do
      p=$pid; while [[ -n $mine && $p -gt 1 && $p != "$mine" ]]; do p=$(ps -o ppid= -p "$p" 2>/dev/null || echo 1); p=${p// /}; p=${p:-1}; done
      [[ -n $mine && $p == "$mine" ]] || echo "$term"
    done
}
watchers() { tmux -S "$SOCK" list-clients -F '#{?client_readonly,#{client_termname},}' 2>/dev/null | grep .; }
terms() {  # top 8, as one block centered in width $1 (left-aligned inside it, so the counts line up)
  sort | uniq -c | sort -rn | head -8 |
    awk -v d="$D" -v r="$R" -v W="$1" '{n[NR]=$1; t[NR]=$2; if (length($2) > m) m = length($2)}
      END {pad = int((W - (m + 5)) / 2); if (pad < 0) pad = 0
           for (i = 1; i <= NR; i++) printf "%*s%s%3d%s  %s\n", pad, "", d, n[i], r, t[i]}'
}
center() { local pad=$(( ($1 - ${#2}) / 2 )); (( pad < 0 )) && pad=0; printf '%*s%s\n' "$pad" '' "$3$2$R"; }
printf '\e[?25l'; trap 'printf "\e[?25h"' EXIT
while :; do
  f=$(fight) w=$(watchers)
  nf=$(grep -c . <<<"$f") nw=$(grep -c . <<<"$w")
  W=$(tput cols 2>/dev/null || echo 100)
  out=$(
    echo
    printf '%s' "$Y"; figlet -c -w "$W" "$nf fighting" 2>/dev/null || echo "$nf fighting"; printf '%s' "$R"
    printf '%s' "$C"; figlet -c -w "$W" "$nw watching" 2>/dev/null || echo "$nw watching"; printf '%s' "$R"
    echo; center "$W" "What everyone brought:" "$B"
    { [[ -n $f ]] && echo "$f"; [[ -n $w ]] && echo "$w"; } | terms "$W"
  )
  printf '\e[H%s\e[J' "${out//$'\n'/$'\e[K\n'}"
  sleep 1
done
