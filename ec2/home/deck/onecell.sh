#!/usr/bin/env bash
# onecell.sh: the Game of Life, one cell at a time, with tmux doing the arithmetic.
# Press Enter to advance. Runs on a private, throwaway server (tmux -L onecell).
# bash only prints and generates command text; every number comes back from tmux.
unset TMUX
T=(tmux -L onecell -f /dev/null)
N=6                                   # 6x6 board, edges wrap
B=$'\e[1m' C=$'\e[1;36m' Y=$'\e[1;33m' G=$'\e[1;32m' D=$'\e[2m' R=$'\e[0m'

wrap() { echo $(( ($1 + N) % N )); }
pause() { echo; read -rsp "${D}  (Enter)${R}" _; echo; echo; }
say() { echo "${B}$*${R}"; }
show() { printf '%s$ tmux %s%s\n' "$C" "$*" "$R"; }        # print a command (as you'd type it; -L onecell left out)...
run() {                                                    # ...and run it. Quote what a shell would need quoted.
  local a out=()
  for a in "$@"; do [[ $a =~ ^[A-Za-z0-9@_./:=-]+$ ]] && out+=("$a") || out+=("'$a'"); done
  show "${out[*]}"; "${T[@]}" "$@"
}
cell() { "${T[@]}" show -gv "@c_$1_$2"; }

board() {                                  # draw it: read straight from tmux options
  local r c focus=${1:-}
  printf '      %s' "$D"; for ((c = 0; c < N; c++)); do printf '%-2d' "$c"; done; printf ' col%s\n' "$R"
  for ((r = 0; r < N; r++)); do
    printf '%srow %d%s ' "$D" "$r" "$R"
    for ((c = 0; c < N; c++)); do
      if [[ $r,$c == "$focus" ]]; then
        [[ $(cell $r $c) == 1 ]] && printf '%s██%s' "$Y" "$R" || printf '%s[]%s' "$Y" "$R"
      else
        [[ $(cell $r $c) == 1 ]] && printf '██' || printf '%s··%s' "$D" "$R"
      fi
    done
    echo
  done
}

neighbors() {                              # the 8 neighbors, as #{@c_R_C} references
  local r=$1 c=$2 dr dc out=()
  for dr in -1 0 1; do for dc in -1 0 1; do
    (( dr == 0 && dc == 0 )) && continue
    out+=("#{@c_$(wrap $((r + dr)))_$(wrap $((c + dc)))}")
  done; done
  echo "${out[@]}"
}
sum() {                                    # a b c ... -> nested #{e|+:a,b}, pairwise
  local -a xs=("$@") next
  while (( ${#xs[@]} > 1 )); do
    next=()
    for ((i = 0; i < ${#xs[@]}; i += 2)); do
      if (( i + 1 < ${#xs[@]} )); then next+=("#{e|+:${xs[i]},${xs[i+1]}}"); else next+=("${xs[i]}"); fi
    done
    xs=("${next[@]}")
  done
  echo "${xs[0]}"
}
count_fmt() { sum $(neighbors "$1" "$2"); }
rule_fmt() { echo "#{?#{==:#{@n_$1_$2},3},1,#{?#{&&:#{@c_$1_$2},#{==:#{@n_$1_$2},2}},1,0}}"; }

step() {                                   # the whole board: phase 1 for every cell, then phase 2
  local r c
  for ((r = 0; r < N; r++)); do for ((c = 0; c < N; c++)); do
    "${T[@]}" set -gF "@n_${r}_${c}" "$(count_fmt $r $c)"
  done; done
  for ((r = 0; r < N; r++)); do for ((c = 0; c < N; c++)); do
    "${T[@]}" set -gF "@c_${r}_${c}" "$(rule_fmt $r $c)"
  done; done
}

pixel_fmt() {                              # two grid rows -> one line of half blocks
  local top=$1 bot=$2 c out=""
  for ((c = 0; c < N; c++)); do
    out+="#{?#{&&:#{@c_${top}_$c},#{@c_${bot}_$c}},█,#{?#{@c_${top}_$c},▀,#{?#{@c_${bot}_$c},▄, }}}"
  done
  echo "$out"
}

# --- title screen: build nothing until the presenter is here -----------------
clear
figlet -c -w "$(tput cols 2>/dev/null || echo 100)" 'one cell' 2>/dev/null || echo "one cell"
echo; echo "      The Game of Life, one step at a time, with tmux doing the math. Press Enter."
read -rs _

# --- setup: a blinker, standing up -------------------------------------------
"${T[@]}" kill-server 2>/dev/null
"${T[@]}" new-session -d -s math
for ((r = 0; r < N; r++)); do for ((c = 0; c < N; c++)); do "${T[@]}" set -g "@c_${r}_${c}" 0; done; done
for r in 1 2 3; do "${T[@]}" set -g "@c_${r}_2" 1; done
trap '"${T[@]}" kill-server 2>/dev/null' EXIT

clear
say "The memory: one tmux option per cell. 1 is alive, 0 is dead."
echo "Each one is named @c_ROW_COL, counting from 0."
echo
run show -g @c_1_2
run show -g @c_2_1
echo
board
pause

say "Look at @c_2_1: row 2, column 1, the empty cell left of the blinker's middle."
echo
board 2,1
echo
say "Step 1, count its neighbors. Eight lookups, added up with #{e|+:a,b}:"
echo
run set -gF @n_2_1 "$(count_fmt 2 1)"
echo
run show -gv @n_2_1
pause

say "Step 2, apply the rule. 3 neighbors: alive. Alive with 2: stays alive. Anything else: dead."
echo
echo "   ${D}#{?  #{==:#{@n},3}  ,1,  #{?  #{&&:#{@c},#{==:#{@n},2}}  ,1,0}  }${R}"
echo "   ${D}    if n == 3      then 1  elif   alive and n == 2       then 1 else 0${R}"
echo
run set -gF @c_2_1 "$(rule_fmt 2 1)"
echo
run show -gv @c_2_1
echo
say "Born. tmux did that: no shell arithmetic, no if."
pause

"${T[@]}" set -g @c_2_1 0            # put it back, and do it properly: count everything first
say "Now every cell: all $((N * N)) counts first, then all $((N * N)) rules."
echo "That way no cell reads a half-updated board."
echo "That's $((N * N * 2)) set -gF commands. In the real thing they live in step.conf."
echo
board
for i in 1 2 3 4; do
  step
  echo; echo "   generation $i"; board
done
echo
say "A blinker. tmux is computing Life."
pause

say "The screen is a format too. One status line shows two grid rows:"
echo "   ${D}top only ▀   bottom only ▄   both █   neither: space${R}"
echo
show "display -p '$(pixel_fmt 0 1 | cut -c1-100)...'"
echo
for top in 0 2 4; do
  printf '   %s[%s%s%s]%s   rows %d and %d\n' "$D" "$R" "$("${T[@]}" display -p "$(pixel_fmt $top $((top + 1)))")" "$D" "$R" $top $((top + 1))
done
echo
say "Put five of those in status-format[0..4] and the status bar is the display."
pause
say "Done. (This scratch server goes away now.)"
