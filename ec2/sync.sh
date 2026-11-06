#!/usr/bin/env bash
# sync.sh: push ec2/home/ (CLAUDE.md, settings) and the Life fallback to the box.
# Re-run any time you edit them.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/config.sh"
source "$HERE/.state"
SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$HERE/.known_hosts"
rsync -a -e "$SSH" "$HERE/home/" "presentation@$IP:"
rsync -a --mkpath -e "$SSH" "$HERE/../life/gen.sh" "$HERE/../life/start.sh" "presentation@$IP:.fallback/life/"
[[ -e $HERE/../tmux-ops ]] && rsync -a --mkpath -e "$SSH" "$HERE/../tmux-ops" "presentation@$IP:bin/"   # optional extra, not in the repo
$SSH "presentation@$IP" 'mkdir -p ~/.local/bin && ln -sf ~/deck/deck ~/.local/bin/deck'
echo "synced to $IP"
