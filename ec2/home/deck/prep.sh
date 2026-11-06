#!/usr/bin/env bash
# prep.sh: is the box ready for the talk?
#   deck check   look at everything, change nothing
#   deck prep    clear away rehearsal leftovers, rebuild the deck, then check
# Run it from a plain ssh login, not from inside the deck. A rebuild replaces the deck's windows.
export PATH=$HOME/.local/bin:$HOME/bin:$PATH
DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
SOCK=${DECK_SOCKET:-/srv/plug/talk}
T=(tmux -S "$SOCK")
G=$'\e[1;32m' Y=$'\e[1;33m' R=$'\e[1;31m' B=$'\e[1m' D=$'\e[2m' N=$'\e[0m'
fails=0 warns=0
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; warns=$((warns + 1)); }
bad()  { printf '  %s✗%s %s\n' "$R" "$N" "$*"; fails=$((fails + 1)); }
hdr()  { printf '\n%s%s%s\n' "$B" "$*" "$N"; }
did()  { printf '  %s→ %s%s\n' "$D" "$*" "$N"; }

# Private servers the talk uses. Leftovers from rehearsal would leak into the show.
SCRATCH=(life lifetest onecell ops probe snake)
DEMO_TMPDIR=/tmp/plug-demo          # the live demo shells' tmux (demo.bashrc); plain `tmux` is the deck

prep() {
  hdr "Clearing rehearsal leftovers"
  for s in "${SCRATCH[@]}"; do
    tmux -L "$s" kill-server 2>/dev/null && did "killed tmux -L $s"
    TMUX_TMPDIR=$DEMO_TMPDIR tmux -L "$s" kill-server 2>/dev/null && did "killed demo tmux -L $s"
  done
  TMUX_TMPDIR=$DEMO_TMPDIR tmux kill-server 2>/dev/null && did "killed the demo shells' tmux server"
  local def=/tmp/tmux-$UID/default                        # a real (non-deck) default server would block the link
  if [[ -S $def && ! -L $def ]]; then
    tmux -S "$def" kill-server 2>/dev/null && did "killed a stray default tmux server"
    rm -f "$def"
  fi
  find "/tmp/tmux-$UID" "$DEMO_TMPDIR/tmux-$UID" -maxdepth 1 -type s ! -name default -delete 2>/dev/null
  if [[ -d ~/plug/life ]]; then
    mkdir -p ~/.rehearsals
    local to=~/.rehearsals/life-$(date +%Y%m%d-%H%M%S)
    mv ~/plug/life "$to" && did "moved Claude's last Life build to $to"
  fi
  rm -f ~/.tmux-ops-*.log && did "removed tmux-ops logs"
  rm -rf /tmp/example.com && did "removed the tds demo directory"
  if sudo -n -u demo tmux -L fight has-session -t fight 2>/dev/null; then
    sudo -n -u demo tmux -L fight respawn-pane -k -t fight \; clear-history -t fight && did "fresh shell and empty history in the type-fight"
  fi
  hdr "Rebuilding the deck"
  "$DIR/deck" build >/dev/null 2>&1 && did "deck rebuilt from talk.txt" || bad "deck rebuild failed"
  sleep 3                                               # let the claude window start
}

check() {
  hdr "tmux"
  local v; v=$(tmux -V 2>/dev/null)
  [[ $(printf '%s\n' "tmux 3.8" "$v" | sort -V | head -1) == "tmux 3.8" ]] && ok "$v ($(command -v tmux))" || bad "tmux is '${v:-missing}', want 3.8+"

  hdr "Deck"
  if "${T[@]}" has-session -t =talk 2>/dev/null; then
    local want have extra missing
    want=$(python3 "$DIR/render.py" --list "$DIR/talk.txt" | cut -f2)
    have=$("${T[@]}" list-windows -t =talk -F '#W')
    extra=$(comm -13 <(sort <<<"$want") <(sort <<<"$have") | paste -sd' ')
    missing=$(comm -23 <(sort <<<"$want") <(sort <<<"$have") | paste -sd' ')
    [[ $want == "$have" ]] && ok "session talk: $(wc -l <<<"$have") windows, in talk.txt order" \
      || bad "windows don't match talk.txt${extra:+ (extra: $extra)}${missing:+ (missing: $missing)}. Fix: deck prep"
    local cur; cur=$("${T[@]}" list-windows -t =talk -F '#{?window_active,#I:#W,}' | grep .)
    [[ $cur == 1:* ]] && ok "on slide $cur" || warn "the deck is on $cur, not slide 1"
    local pid; pid=$("${T[@]}" display -p -t 'talk:=claude' '#{pane_pid}' 2>/dev/null)
    [[ -n $pid ]] && pgrep -x -P "$pid" claude >/dev/null && ok "claude window is running Claude, waiting for your prompt" \
      || bad "the claude window isn't running Claude. Fix: deck prep"
    local n; n=$("${T[@]}" list-clients -t =talk 2>/dev/null | wc -l)
    ok "$n client(s) attached right now"
  else
    bad "no deck session on $SOCK. Fix: deck prep"
  fi

  hdr "Claude and the Game of Life"
  if command -v claude >/dev/null; then
    local auth; auth=$(claude auth status 2>/dev/null)
    if [[ $(jq -r .loggedIn <<<"$auth" 2>/dev/null) == true ]]; then
      ok "Claude Code $(claude --version 2>/dev/null | cut -d' ' -f1), logged in (expires $(jq -r '.loginExpiresAt[:10]' <<<"$auth"))"
    else
      bad "Claude Code isn't logged in. Fix: go to the claude window and run /login"
    fi
  else
    bad "claude isn't installed"
  fi
  [[ $(jq -r '.projects["'"$HOME"'/plug"].hasTrustDialogAccepted' ~/.claude.json 2>/dev/null) == true ]] \
    && ok "~/plug is trusted (no folder prompt on stage)" || bad "~/plug isn't trusted yet. Fix: cd ~/plug && claude, accept the prompt"
  [[ -s ~/plug/CLAUDE.md ]] && ok "~/plug/CLAUDE.md is in place" || bad "~/plug/CLAUDE.md is missing. Fix: run sync.sh on Gezora"
  [[ -e ~/plug/life ]] && bad "~/plug/life exists, so Claude would find old work. Fix: deck prep" || ok "~/plug/life is empty: Claude starts from nothing"
  local live=()
  for s in "${SCRATCH[@]}"; do
    { tmux -L "$s" has-session || TMUX_TMPDIR=$DEMO_TMPDIR tmux -L "$s" has-session; } 2>/dev/null && live+=("$s")
  done
  ((${#live[@]})) && bad "leftover private tmux servers: ${live[*]}. Fix: deck prep" || ok "no leftover private servers (${SCRATCH[*]})"
  if TMUX_TMPDIR=$DEMO_TMPDIR tmux has-session 2>/dev/null; then
    warn "the demo shells' tmux already has sessions: $(TMUX_TMPDIR=$DEMO_TMPDIR tmux ls -F '#S' | paste -sd' ')"
  else
    ok "the demo shells' tmux is empty"
  fi
  [[ $(readlink "/tmp/tmux-$UID/default") == "$SOCK" ]] && tmux has-session -t =talk 2>/dev/null \
    && ok "plain 'tmux ls' / 'tmux attach -t talk' reach the deck" || bad "plain 'tmux' doesn't reach the deck. Fix: deck prep"
  [[ $(curl -s -o /dev/null -w '%{http_code}' -m 5 https://api.anthropic.com) != 000 ]] \
    && ok "the box can reach api.anthropic.com" || bad "can't reach api.anthropic.com"

  hdr "Audience: watch and fight"
  if [[ -S $SOCK ]]; then
    [[ $(stat -c %A "$SOCK") == ?rw?rw* ]] && ok "deck socket is group-writable (group $(stat -c %G "$SOCK"))" || bad "watchers can't connect to $SOCK. Fix: deck prep"
    "${T[@]}" server-access -l 2>/dev/null | grep -q '^watch (.*R' && ok "watch is read-only on the deck" || bad "watch has no read-only access. Fix: deck prep"
  fi
  systemctl is-active -q fight && ok "fight.service is running" || bad "fight.service isn't running. Fix: sudo systemctl restart fight"
  sudo -n -u demo tmux -L fight has-session -t fight 2>/dev/null && ok "fight session is up ($(sudo -n -u demo tmux -L fight display -p -t fight '#{session_attached}') attached)" || bad "no fight session"
  local p
  for p in 22 443; do ss -ltnH "sport = :$p" | grep -q . && ok "sshd listening on $p" || bad "nothing listening on port $p"; done
  for u in demo watch; do
    sudo -n sshd -T -C "user=$u,host=x,addr=192.0.2.1" 2>/dev/null | grep -cx -e 'passwordauthentication yes' -e 'pubkeyauthentication no' | grep -qx 2 \
      && ok "$u logs in by password only (no key offers to exhaust MaxAuthTries)" || bad "$u isn't password-only. Fix: sudo systemctl restart ssh"
  done
  [[ $(sudo -n nft list ruleset 2>/dev/null | grep -c skuid) -ge 3 ]] && ok "no outbound network for demo and watch" || bad "the nftables egress rules are missing. Fix: sudo systemctl restart nftables"

  hdr "Box"
  local tok ip dns
  tok=$(curl -s -m 2 -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' http://169.254.169.254/latest/api/token)
  ip=$(curl -s -m 2 -H "X-aws-ec2-metadata-token: $tok" http://169.254.169.254/latest/meta-data/public-ipv4)
  dns=$(getent ahostsv4 tmux.peat.org | awk 'NR==1{print $1}')
  [[ -n $ip && $ip == "$dns" ]] && ok "tmux.peat.org → $ip (this box)" || bad "tmux.peat.org → ${dns:-nothing}, but this box is ${ip:-unknown}"
  local next; next=$(systemctl list-timers --all -o json plug-self-destruct.timer 2>/dev/null | jq -r '.[0].next // empty')
  if [[ -n $next ]]; then
    local mins=$(( (next / 1000000 - $(date +%s)) / 60 ))
    ((mins > 360)) && ok "self-destruct in $((mins / 60))h $((mins % 60))m ($(date -d @$((next / 1000000)) '+%a %H:%M %Z'))" \
      || warn "self-destruct in only $((mins / 60))h $((mins % 60))m"
  else
    warn "can't find the self-destruct timer"
  fi
  local cmd
  for cmd in figlet htop nvim jq python3; do command -v "$cmd" >/dev/null || bad "$cmd is missing"; done
  infocmp xterm-ghostty >/dev/null 2>&1 && ok "Ghostty terminfo is installed" || warn "no xterm-ghostty terminfo"
  ok "load $(cut -d' ' -f1-3 /proc/loadavg), $(free -h | awk '/^Mem/{print $7}') memory free, $(df -h ~ | awk 'NR==2{print $4}') disk free"

  echo
  if ((fails)); then printf '%s%d problem(s)%s, %d warning(s). Fix those before you go on.\n' "$R" "$fails" "$N" "$warns"; return 1
  elif ((warns)); then printf '%sReady%s, with %d warning(s).\n' "$G" "$N" "$warns"
  else printf '%sReady. Break a leg.%s\n' "$G" "$N"; fi
}

case ${1:-check} in
  check) check ;;
  prep)
    if [[ -n ${TMUX:-} && $TMUX == "$SOCK",* ]]; then
      echo "You're inside the deck, and rebuilding it would close this window. Detach (C-b d), then run: deck prep"; exit 1
    fi
    prep; check; echo; echo "Attach with: deck" ;;
  *) echo "usage: deck check | deck prep"; exit 1 ;;
esac
