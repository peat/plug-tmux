# rc for the deck's live shell windows
[ -f ~/.bashrc ] && . ~/.bashrc
. ~/deck/tds.bash
unset TMUX
# Plain `tmux` on this box means the deck (see deck: link_default). Demos inside the deck get
# their own default server, so they never attach the deck to itself.
export TMUX_TMPDIR=/tmp/plug-demo; mkdir -p "$TMUX_TMPDIR"
PS1='\[\e[1;32m\]peat@tmux\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
