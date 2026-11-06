#!/bin/bash
# First-boot setup for tmux.peat.org. up.sh fills in the __PLACEHOLDERS__.
# Log: /var/log/plug-setup.log
set -euxo pipefail
exec > >(tee -a /var/log/plug-setup.log) 2>&1
export DEBIAN_FRONTEND=noninteractive

hostnamectl set-hostname tmux
echo "127.0.1.1 tmux" >>/etc/hosts
timedatectl set-timezone America/Los_Angeles   # status-bar clock in the room's time zone

# Safety net: power off (= terminate, see up.sh) after __MAX_HOURS__ hours. No wall spam.
systemd-run --unit=plug-self-destruct --on-active=__MAX_HOURS__h /bin/systemctl poweroff

apt-get update
apt-get install -y build-essential bison pkg-config libevent-dev libncurses-dev \
  curl git rsync nftables figlet toilet ed htop jq asciinema ncurses-term neovim

# Ghostty's terminfo isn't in Ubuntu 24.04; up.sh embeds it. (kitty/alacritty/etc. come from ncurses-term.)
cat >/tmp/ghostty.ti <<'TI'
__GHOSTTY_TERMINFO__
TI
tic -x /tmp/ghostty.ti || echo "ghostty terminfo failed"

# --- tmux __TMUX_VERSION__ from source (Ubuntu 24.04 ships 3.4) ---------------
V=__TMUX_VERSION__
if curl -fsSL -o /tmp/tmux.tgz "https://github.com/tmux/tmux/releases/download/$V/tmux-$V.tar.gz" &&
   tar -C /tmp -xzf /tmp/tmux.tgz &&
   (cd "/tmp/tmux-$V" && ./configure --prefix=/usr/local && make -j"$(nproc)" && make install); then
  echo "built tmux $V"
else
  echo "tmux $V build failed; using Ubuntu's tmux"
  apt-get install -y tmux
  ln -sf /usr/bin/tmux /usr/local/bin/tmux
fi
/usr/local/bin/tmux -V

# --- presentation: Peat only, by SSH key -------------------------------------
useradd -m -s /bin/bash -G sudo presentation
passwd -l presentation
echo 'presentation ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/90-presentation
chmod 440 /etc/sudoers.d/90-presentation
install -d -m 700 -o presentation -g presentation /home/presentation/.ssh
cat >/home/presentation/.ssh/authorized_keys <<'KEYS'
__PRESENTER_KEYS__
KEYS
chown presentation:presentation /home/presentation/.ssh/authorized_keys
chmod 600 /home/presentation/.ssh/authorized_keys
chmod 750 /home/presentation
touch /home/presentation/.hushlogin
sudo -u presentation -H bash -c 'curl -fsSL https://claude.ai/install.sh | bash' || echo "Claude Code install failed"

# --- demo: anyone, by password, straight into the shared fight session -------
useradd -m -u 2000 -s /bin/bash demo
echo 'demo:__DEMO_PASSWORD__' | chpasswd
touch /home/demo/.hushlogin

# --- watch: anyone, by password, a read-only view of the deck --------------
# The deck's server lives on a socket in /srv/plug (group plug). 'deck' grants watch
# read-only access with tmux's server-access; the server enforces it, not the client.
useradd -m -u 2001 -s /bin/bash watch
echo 'watch:__DEMO_PASSWORD__' | chpasswd
touch /home/watch/.hushlogin
groupadd -f plug
usermod -aG plug presentation
usermod -aG plug watch
install -d -m 2770 -o presentation -g plug /srv/plug
cat >/usr/local/bin/watch-talk <<'SH'
#!/bin/bash
# ForceCommand for 'watch': attach read-only; our terminal size never resizes the slides.
# Any terminal: no terminfo, or one tmux can't use (dumb can't clear), gets xterm-256color.
tput -T "${TERM:-dumb}" clear >/dev/null 2>&1 || export TERM=xterm-256color
# -u: draw UTF-8 even if the client's locale doesn't say so (the slides are full of █ ─ •).
/usr/local/bin/tmux -u -S /srv/plug/talk attach -f read-only,ignore-size -t talk 2>/dev/null && exit 0
figlet -w 80 'Soon!' 2>/dev/null
echo "The talk isn't running yet. Try again in a minute!"
sleep 5
SH
chmod 755 /usr/local/bin/watch-talk

cat >/etc/tmux-fight.conf <<'CONF'
# Shared type-fight server (tmux -L fight). Everyone types into one pane.
set -g prefix None                 # no prefix key: every keystroke goes to the pane
unbind -a -T prefix
unbind -a -T root
set -g mouse off
set -g window-size manual          # nobody's tiny terminal shrinks it for everyone
set -g default-size 100x30
set -g remain-on-exit on           # someone types 'exit'? respawn the shell
set-hook -g pane-died 'run-shell -d 1 "tmux -L fight respawn-pane -k -t #{pane_id}"'
set -g default-command 'bash --rcfile /etc/fight.bashrc'
set -g status-style 'bg=colour202,fg=black,bold'
set -g status-left ' TYPE FIGHT '
set -g status-left-length 20
set -g window-status-format ''
set -g window-status-current-format ''
set -g status-right ' #{session_attached} fighters | ssh demo@tmux.peat.org '
set -g status-right-length 60
CONF

cat >/etc/fight.bashrc <<'RC'
[ -f /etc/bash.bashrc ] && . /etc/bash.bashrc
export HISTFILE=/dev/null
cd /home/demo
figlet -w 100 'tmux @ PLUG'
echo "Everyone in the room is typing into this one pane. Be nice-ish."
echo "There is no internet from here. 'exit' just gets you a fresh shell."
PS1='\[\e[1;33m\]fight\[\e[0m\]:\w\$ '
RC

cat >/usr/local/bin/fight <<'SH'
#!/bin/bash
# ForceCommand for 'demo': attach to the shared session (create it if it's gone).
tput -T "${TERM:-dumb}" clear >/dev/null 2>&1 || export TERM=xterm-256color   # odd terminal? don't crash
exec /usr/local/bin/tmux -u -L fight -f /etc/tmux-fight.conf new-session -A -s fight
SH
chmod 755 /usr/local/bin/fight

# The fight server lives in a systemd service: restarted if someone kills it,
# and capped so a fork bomb hurts only the fight.
cat >/etc/systemd/system/fight.service <<'UNIT'
[Unit]
Description=Shared tmux type-fight session
After=network.target
[Service]
Type=forking
User=demo
WorkingDirectory=/home/demo
Environment=TERM=xterm-256color
ExecStart=/usr/local/bin/tmux -L fight -f /etc/tmux-fight.conf new-session -d -s fight
Restart=always
RestartSec=2
TasksMax=300
MemoryMax=2G
CPUQuota=150%
[Install]
WantedBy=multi-user.target
UNIT
for uid in 2000 2001; do
  mkdir -p /etc/systemd/system/user-$uid.slice.d
  printf '[Slice]\nTasksMax=200\nMemoryMax=1G\nCPUQuota=100%%\n' >/etc/systemd/system/user-$uid.slice.d/limits.conf
done
systemctl daemon-reload
systemctl enable --now fight.service

# No outbound network for demo (2000) or watch (2001), except loopback. Covers IMDS too.
cat >/etc/nftables.conf <<'NFT'
#!/usr/sbin/nft -f
flush ruleset
table inet plug {
  chain output {
    type filter hook output priority 0; policy accept;
    meta skuid { 2000, 2001 } oifname "lo" accept
    meta skuid { 2000, 2001 } ct state established,related accept
    meta skuid { 2000, 2001 } counter reject
  }
}
NFT
systemctl enable nftables
systemctl restart nftables

# --- sshd: ports 22 + 443, a whole room behind one NAT, demo is fenced in ----
cat >/etc/ssh/sshd_config.d/10-plug.conf <<'SSHD'
Port 22
Port 443
MaxStartups 100:30:200
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
AllowUsers presentation demo watch
Match User demo
    PasswordAuthentication yes
    PubkeyAuthentication no            # many agent keys would burn MaxAuthTries before the password prompt
    AuthenticationMethods password
    ForceCommand /usr/local/bin/fight
    AllowTcpForwarding no
    AllowAgentForwarding no
    AllowStreamLocalForwarding no
    X11Forwarding no
    PermitTunnel no
Match User watch
    PasswordAuthentication yes
    PubkeyAuthentication no            # many agent keys would burn MaxAuthTries before the password prompt
    AuthenticationMethods password
    ForceCommand /usr/local/bin/watch-talk
    AllowTcpForwarding no
    AllowAgentForwarding no
    AllowStreamLocalForwarding no
    X11Forwarding no
    PermitTunnel no
SSHD
sshd -t
# Ubuntu 24.04 uses socket activation, which ignores Port lines. Switch to a plain service.
# Stop the boot-time sshd *before* reloading units. Ubuntu's ssh.service uses KillMode=process,
# and after the daemon-reload systemd loses track of it. A plain restart then leaves it holding
# port 22 with the old config (no password for demo).
systemctl stop ssh.service ssh.socket || true
systemctl disable ssh.socket || true
rm -f /etc/systemd/system/ssh.service.d/00-socket.conf /etc/systemd/system/ssh.socket.d/addresses.conf
systemctl daemon-reload
systemctl enable --now ssh.service
# Belt and braces: exactly one sshd should own both ports.
sleep 1
MAIN=$(systemctl show -p MainPID --value ssh.service)
for pid in $(ss -ltnpH '( sport = :22 or sport = :443 )' | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u); do
  [ "$pid" = "$MAIN" ] || { echo "killing stale sshd listener $pid"; kill "$pid"; }
done
sleep 1
systemctl restart ssh.service
ss -ltnp | grep -E ':(22|443) '
echo "plug setup done"
