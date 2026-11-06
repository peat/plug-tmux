# tds for bash: a tmux session per directory (the zsh original lives in Oh My Zsh's tmux plugin)
tds() {
  local dir=${PWD##*/}
  dir=${dir//[.:]/_}            # . and : are separators in tmux target syntax
  dir=${dir/#[\$@%=]/_}         # leading $ @ % are ids, leading = means exact match
  local md5=$(printf '%s' "$PWD" | md5sum | cut -d ' ' -f 1)
  command tmux new -As "${dir}-${md5:0:6}"
}
