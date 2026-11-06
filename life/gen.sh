#!/bin/sh
# Generates life.conf: Conway's Life where state, rules and loop all live in tmux.
# Shell is only used here to write the (repetitive) tmux config.
W=${W:-10}; H=${H:-10}   # H must be even (2 rows per status line via half blocks)
DIR=$(cd "$(dirname "$0")" && pwd)
OUT="$DIR/life.conf"; STEP="$DIR/step.conf"
c() { echo "#{@c_$(( ($1+H)%H ))_$(( ($2+W)%W ))}"; }
{
  echo "# --- step: one generation, pure tmux formats ---"
  # phase 1: neighbour count per cell into @n_r_c
  r=0; while [ $r -lt $H ]; do col=0; while [ $col -lt $W ]; do
    s=$(c $((r-1)) $((col-1)))
    for d in "-1 0" "-1 1" "0 -1" "0 1" "1 -1" "1 0" "1 1"; do
      set -- $d; s="#{e|+:$s,$(c $((r+$1)) $((col+$2)))}"
    done
    echo "set -gF @n_${r}_${col} \"$s\""
  col=$((col+1)); done; r=$((r+1)); done
  # phase 2: apply B3/S23 in place (only reads own @n and @c)
  r=0; while [ $r -lt $H ]; do col=0; while [ $col -lt $W ]; do
    n="#{@n_${r}_${col}}"; me="#{@c_${r}_${col}}"
    echo "set -gF @c_${r}_${col} \"#{?#{==:$n,3},1,#{?#{&&:#{==:$n,2},$me},1,0}}\""
  col=$((col+1)); done; r=$((r+1)); done
  echo 'set -gF @gen "#{e|+:#{@gen},1}"'
  echo "if -F '#{client_name}' 'refresh-client -S'"
  echo "if -F '#{@running}' { run -C \"run -b -d #{@delay} -C '#{@tick}'\" }"
} > "$STEP"
{
  echo "# --- life.conf: setup + renderer ---"
  echo "set -g @delay 0.5"
  echo "set -g @gen 0"
  r=0; while [ $r -lt $H ]; do col=0; while [ $col -lt $W ]; do
    echo "set -g @c_${r}_${col} 0"; col=$((col+1)); done; r=$((r+1)); done
  # renderer: each status line = 2 grid rows using half blocks
  L=$((H/2)); echo "set -t life status $L"
  i=0; while [ $i -lt $L ]; do
    a=$((2*i)); b=$((2*i+1)); f=""
    col=0; while [ $col -lt $W ]; do
      f="$f#{?#{@c_${a}_${col}},#{?#{@c_${b}_${col}},█,▀},#{?#{@c_${b}_${col}},▄, }}"
      col=$((col+1)); done
    pre=""; [ $i -eq 0 ] && pre="#[align=left]gen #{@gen}"
    echo "set -t life status-format[$i] '$pre#[align=centre,fg=green,bg=black]$f#[default]'"
    i=$((i+1)); done
  echo "set -g @tick 'source-file $STEP'"
} > "$OUT"
