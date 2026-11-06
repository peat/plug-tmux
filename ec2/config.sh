# Settings for up.sh / down.sh / sync.sh. Override any of these from the environment.
export AWS_PROFILE=${AWS_PROFILE:-personal}
REGION=${REGION:-us-west-2}                 # Oregon: closest to PSU
INSTANCE_TYPE=${INSTANCE_TYPE:-t3.large}    # 2 vCPU / 8 GB: Claude Code + a roomful of demo shells
DISK_GB=${DISK_GB:-20}
ZONE=${ZONE:-peat.org}
HOST=${HOST:-tmux.peat.org}
NAME=${NAME:-plug-tmux}                     # tag on everything we create
TMUX_VERSION=${TMUX_VERSION:-3.8}           # built from source; falls back to Ubuntu's tmux
DEMO_PASSWORD=${DEMO_PASSWORD:-plug}        # shown on a slide; no quotes or backslashes
MAX_HOURS=${MAX_HOURS:-48}                  # box powers off (= terminates) after this, as a safety net
PRESENTER_KEYS=${PRESENTER_KEYS:-$HOME/.ssh/authorized_keys}  # pubkeys allowed into 'presentation'
