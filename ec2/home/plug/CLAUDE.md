# You're live at PLUG

This is a live demo at a Portland Linux/Unix Group talk about tmux. Peat (the presenter) is running you
in a window of his tmux session on tmux.peat.org, projected in front of a room. When he asks for a
**tmux powered Game of Life**, he'll walk away to keep talking and come back in about 10 minutes.

**Work completely unattended.** Don't ask questions or wait for confirmation. Make reasonable choices and
keep going. A simple version that works beats an ambitious one that doesn't. Aim to finish in under 10 minutes.

## What to build

Conway's Game of Life (B3/S23) where **tmux itself does the computing**. That's the whole joke.

- **State:** one global user option per cell on a private tmux server, `@c_ROW_COL` = `0`/`1`.
  Grid is **10 rows × 32 columns**, toroidal (edges wrap).
- **Logic:** tmux format expressions only, applied with `set -gF`.
  - Phase 1: sum the 8 neighbours into `@n_ROW_COL` with nested `#{e|+:a,b}`.
  - Phase 2: apply the rule with `#{?…}`, `#{==:…}` and `#{&&:…}`.
  - Both phases are written into a generated `step.conf`. Phase 2 is safe in place because each
    cell reads only its own `@n` and `@c`.
- **Shell:** a bash script may *generate* the repetitive config (wraparound indices are worked out
  at generation time). It must not compute Life. All the Life logic lives in tmux.
- **Loop:** driven by tmux. The last line of `step.conf` reschedules the next step when `@running`
  is `1`. Keep `@gen` as a generation counter and `@delay` (default 0.25).
- **Rendering:** the status bar of a dedicated session.
  - `status 5` (the maximum), with `status-format[0]` through `status-format[4]`.
  - Each line shows two grid rows using half blocks: `▀` top only, `▄` bottom only, `█` both,
    space neither.
  - Put the generation counter on one of the lines.
- **Seed:** two gliders, a blinker and a lightweight spaceship, spaced apart.

## Traps that will eat your time

1. **Inside `source-file`, `run -d` needs `-b`.** Without it, the delay is ignored and every step
   nests inside the last until "too many nested files". Use `run -b -d …`.
2. **`-d` does not expand formats.** `run -d #{@delay}` fails. Wrap it: `run -C "run -b -d #{@delay} -C '#{@tick}'"`,
   with `@tick` holding `source-file /abs/path/step.conf`. Use `{ }` braces to tame quoting.
3. **`refresh-client` fails with no client attached.** You don't need it: option changes redraw
   attached clients by themselves.
4. **Status bar is 5 lines max.** That's why there are two rows per line.
5. **Use bash for scripts**, use absolute paths in generated config, and quote `'status-format[0]'`
   in shells.

## Where and how

- Work in `~/plug/life/`. Do not look in `~/.fallback`, and don't fetch anything from the web.
  Building it is the point.
- **Use a private tmux server for everything: `tmux -L life …`.** Never kill, reconfigure, or set
  options on Peat's server (the one in `$TMUX`, socket `/srv/plug/talk`). That server *is* his slide
  deck, with the audience attached read-only.
  The only thing you may do on it is the launch step below. If a `-L life` server is left over from
  an earlier attempt, kill it and start fresh.
- **Test before you launch,** on a scratch server (`tmux -L lifetest`).
  - Use `show -gv` and `display -p` to check that a blinker flips between horizontal and vertical.
  - Check that a glider moves one cell diagonally every 4 generations.
  - `display -p "$(tmux -L lifetest show -gv 'status-format[0]')"` renders a status line without
    a client.
  - **Kill `lifetest` when you're done** (`tmux -L lifetest kill-server`). Last rehearsal left it running.

## Launch

1. On `-L life`, create a session named `life`, seed the grid, set `@running 1`, and start the loop.
   Also:
   - Key bindings: plain letters in the `life` server's **root** table (`bind -n`), no prefix and no
     function keys. Peat's laptop has no handy F-keys. Keys only reach the `life` server while its
     window is active, so plain letters don't collide with anything:
     - `s`: stop (`@running 0`)
     - `g`: go. Start the loop only if it isn't already running, or you get two loops.
     - `r`: reset to the original seed and generation 0, staying running or stopped as it was.
       Keep the seed in its own `seed.conf` so `r` can just source it.
   - Show these keys on the status bar and in the README.
   - Make the session's only pane show a short, friendly README of how it works. Cover where the
     state lives, how neighbours are counted, the rule as a format string, and what the loop is.
     Run it as a script that prints the README and then `exec sleep infinity`, so it stays on screen.
2. On Peat's server, find his session with `tmux display -p -t "$TMUX_PANE" '#S'`. Add a window
   named `life` **without switching to it** (`-d`, because he may be on a slide):
   Put it right after the `check-in` slide, so it's the next window when he gets there:
   `tmux new-window -d -a -t "$S:=check-in" -n life "env -u TMUX tmux -L life attach -t life"`
   If his session already has a window named `life` from an earlier run, kill that window first
   (`kill-window -t "$S:life"`) so there's only one.
3. Announce it on his server:
   `tmux display-message -d 5000 -t "$S" '🧬 Game of Life is running in window: life'`
4. Check it's alive: `@gen` should be climbing on `-L life`.
5. Finish with a short, cheerful summary in chat: what you built, and how many lines of tmux config
   vs shell. The summary will be read out loud, so keep it short.
