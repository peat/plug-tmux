# tmux @ PLUG

*The use (and abuse) of a terminal multiplexer*: a talk at the Portland Linux/Unix Group, November 5, 2026, by Peat Bakke.

The slides aren't a slide deck. They're a tmux session: one window per slide, driven with `C-b n` and `C-b p`. On the night it ran on a throwaway EC2 box. The audience could watch read-only and join a shared "type fight" session. Claude Code was building a Game of Life in the background, computed entirely by tmux.

## Watch the slides on your own machine

You need tmux, python3 and figlet.

```sh
git clone https://github.com/peat/plug-tmux && cd plug-tmux
ec2/home/deck/deck            # builds the deck on a private socket and attaches
```

`C-b n` / `C-b p` move between slides, and `C-b d` detaches. The slide text is all in `ec2/home/deck/talk.txt`, and `render.py` draws it. Some windows only work on the original box, so locally they fail in their own window and drop you to a shell: the type fight, the head count and Claude.

## What's here

- **`ec2/home/deck/`**: the deck.
  - `talk.txt`: every slide, plus the speaker notes.
  - `render.py`: draws a slide in a tmux pane and redraws it live when `talk.txt` changes.
  - `deck`: builds, rebuilds and attaches.
  - `deck.conf`: the status bar and demo mode.
  - Live demos: `onecell.sh` (one Game of Life step, with tmux doing the math), `clients.sh` (live head count) and `tds.bash`.
- **`ec2/home/plug/CLAUDE.md`**: the brief Claude Code got for building a tmux-powered Game of Life, unattended, during the talk.
- **`life/`**: the hand-built fallback Life. `gen.sh` writes `step.conf`, and tmux does the rest: state in options, the rules as format strings, the loop via `run -b -C -d`, the display in the status bar.
- **`ec2/`**: rebuild the whole box. `up.sh` creates a VPC, an instance and DNS on AWS, `user-data.sh` sets up the box, `down.sh` tears it all down, and `sync.sh` pushes the deck. Settings, including the domain, are in `config.sh`, so you'll want your own. The box powers itself off after `MAX_HOURS`.

The audience accounts used the password `plug`, shown on a slide. That box is gone.
