#!/usr/bin/env python3
"""render.py: parse talk.txt and draw one slide in a tmux pane.

talk.txt format:
  @act NAME             sets the act for the slides that follow (shown in the status bar)
  === name              starts a slide; 'name' becomes the tmux window name
  === !name: command    a live window that runs 'command' instead of drawing a slide
  # Title               big figlet title
  ## Heading            bold heading
  - item                bullet
  $ command             shell command, highlighted
  > text                dim aside
  ```                   toggles a preformatted block (no wrapping)
  `code` **bold** *italic*   inline, anywhere
  %ruler N              an N-column calibration line: size the terminal until it spans the screen
  %indent N             indent the text lines after it (not ``` blocks) by N, e.g. to center text under a wide diagram
  --- notes             everything after this, up to the next ===, is speaker notes (never drawn)
  // comment            ignored

Usage:
  render.py --list  talk.txt        tab-separated: index, name, act, command
  render.py --show N talk.txt       draw slide N; redraw on resize or when talk.txt changes
  render.py --notes talk.txt        every slide with its notes, for rehearsal
  render.py --follow SOCK talk.txt  presenter view: live notes for whatever slide the deck is on
"""
import os, re, select, shutil, signal, subprocess, sys, termios, textwrap

RESET, BOLD, DIM, ITAL = "\033[0m", "\033[1m", "\033[2m", "\033[3m"
FG = lambda n: f"\033[38;5;{n}m"
TITLE, HEAD, BULLET, CMD, CODE, ASIDE = FG(81), FG(221), FG(81), FG(114), FG(180), FG(245)
ANSI = re.compile(r"\033\[[0-9;]*m")


def parse(path):
    slides, act, cur = [], "", None
    for raw in open(path, encoding="utf-8"):
        line = raw.rstrip("\n")
        if line.startswith("@act "):
            act = line[5:].strip()
        elif line.startswith("=== "):
            spec, cmd = line[4:].strip(), ""
            if spec.startswith("!"):
                spec, _, cmd = spec[1:].partition(":")
            cur = {"name": spec.strip(), "act": act, "cmd": cmd.strip(), "body": [], "notes": [], "in_notes": False}
            slides.append(cur)
        elif cur is None or line.startswith("//"):
            continue
        elif line.strip() == "--- notes":
            cur["in_notes"] = True
        else:
            cur["notes" if cur["in_notes"] else "body"].append(line)
    for s in slides:  # trim blank lines at both ends
        while s["body"] and not s["body"][0].strip(): s["body"].pop(0)
        while s["body"] and not s["body"][-1].strip(): s["body"].pop()
    return slides


def vlen(s):
    return len(ANSI.sub("", s))


def inline(s, base=""):
    s = re.sub(r"`([^`]+)`", lambda m: f"{CODE}{m.group(1)}{RESET}{base}", s)
    s = re.sub(r"\*\*([^*]+)\*\*", lambda m: f"{BOLD}{m.group(1)}{RESET}{base}", s)
    return re.sub(r"(?<![\w*])\*([^*\s][^*]*)\*(?!\w)", lambda m: f"{ITAL}{m.group(1)}{RESET}{base}", s)


def wrap(text, width):
    """textwrap.wrap, but never split inside a `code` span (that breaks the highlighting)."""
    held = re.sub(r"`[^`]+`", lambda m: m.group(0).replace(" ", "\0"), text)
    return [p.replace("\0", " ") for p in textwrap.wrap(held, width, break_on_hyphens=False)]


def figlet(text, width, gap=4):
    """Render each word on its own and join them with a real gap: figlet's own
    smushing runs words together at projector distance."""
    words = text.split()
    for font in ("standard", "small"):
        blocks = []
        try:
            for w in words:
                out = subprocess.run(["figlet", "-f", font, "-w", "1000", w], capture_output=True, text=True).stdout
                lines = out.rstrip("\n").split("\n")
                while lines and not lines[-1].strip(): lines.pop()
                blocks.append(lines)
        except FileNotFoundError:
            return None
        if not blocks or not all(blocks):
            continue
        h = max(len(b) for b in blocks)
        blocks = [b + [""] * (h - len(b)) for b in blocks]
        widths = [max(len(l) for l in b) for b in blocks]
        lines = [(" " * gap).join(b[i].ljust(wd) for b, wd in zip(blocks, widths)).rstrip() for i in range(h)]
        full = max(len(l) for l in lines)
        if full <= width - 2:
            return [l.ljust(full) for l in lines]      # same width, so centring keeps them aligned
    return None


def layout(body, W):
    """Return a list of (kind, text) where kind is 'center' or 'block'."""
    out, pre, width, ind = [], False, max(20, min(W - 6, 84)), ""
    for line in body:
        if line.strip().startswith("```"):
            pre = not pre
            continue
        if not pre and line.startswith("%indent "):
            ind = " " * int(line.split()[1])
            continue
        start = len(out)
        if pre:
            out.append(("block", f"{CODE}{line}{RESET}"))
        elif line.startswith("# "):
            big = figlet(line[2:].strip(), W)
            if big:
                out += [("center", f"{BOLD}{TITLE}{l}{RESET}") for l in big]
            else:
                out.append(("center", f"{BOLD}{TITLE}{line[2:].strip().upper()}{RESET}"))
        elif line.startswith("## "):
            out.append(("block", f"{BOLD}{HEAD}{inline(line[3:], BOLD + HEAD)}{RESET}"))
        elif line.startswith("- ") or line.startswith("  - "):
            indent = "    " if line.startswith("  ") else ""
            text = line.strip()[2:]
            for i, part in enumerate(wrap(text, width - len(indent) - 2) or [""]):
                lead = f"{BULLET}•{RESET} " if i == 0 else "  "
                out.append(("block", f"{indent}{lead}{inline(part)}"))
        elif line.startswith("%ruler "):
            n = int(line.split()[1])
            out.append(("ruler", f"{ASIDE}├{'─' * max(0, n - 2)}┤{RESET}"))
        elif line.startswith("$ "):
            out.append(("block", f"{CMD}${RESET} {BOLD}{line[2:]}{RESET}"))
        elif line.startswith("> "):
            for part in wrap(line[2:], width) or [""]:
                out.append(("block", f"{ASIDE}{ITAL}{inline(part, ASIDE + ITAL)}{RESET}"))
        elif not line.strip():
            out.append(("block", ""))
        else:
            for part in wrap(line, width) or [""]:
                out.append(("block", inline(part)))
        if ind and not pre:
            out[start:] = [(k, ind + t if k == "block" and t else t) for k, t in out[start:]]
    return out


def draw(slide):
    W, H = shutil.get_terminal_size((100, 30))
    rows = layout(slide["body"], W)
    block_w = max([vlen(t) for k, t in rows if k == "block"] + [0])
    left = max(1, (W - block_w) // 2)
    top = max(0, (H - len(rows)) // 2)
    buf = ["\033[H\033[2J", "\n" * top]
    for kind, text in rows[: max(0, H - top)]:
        if kind == "ruler" and vlen(text) > W:  # too narrow: clip, so the missing ┤ shows it
            text = ANSI.sub("", text)[:W]
        pad = max(0, (W - vlen(text)) // 2) if kind in ("center", "ruler") else left
        buf.append(" " * pad + text + "\n")
    sys.stdout.write("".join(buf).rstrip("\n"))
    sys.stdout.flush()


def show(n, path):
    fd = sys.stdin.fileno()
    try:  # no echo, no line buffering: stray keys vanish instead of messing up the slide
        old = termios.tcgetattr(fd)
        new = termios.tcgetattr(fd)
        new[3] &= ~(termios.ECHO | termios.ICANON)
        termios.tcsetattr(fd, termios.TCSANOW, new)
    except termios.error:
        old = None
    sys.stdout.write("\033[?25l")  # hide cursor
    dirty = [True]
    signal.signal(signal.SIGWINCH, lambda *_: dirty.__setitem__(0, True))
    mtime = None
    try:
        while True:
            m = os.stat(path).st_mtime
            if m != mtime:
                mtime, dirty[0] = m, True
            if dirty[0]:
                dirty[0] = False
                slides = parse(path)
                draw(slides[n - 1] if 0 < n <= len(slides) else {"body": [f"(no slide {n}: run 'deck rebuild')"]})
            try:
                r, _, _ = select.select([fd], [], [], 1.0)
                if r: os.read(fd, 1024)
            except InterruptedError:
                pass
    finally:
        if old: termios.tcsetattr(fd, termios.TCSANOW, old)


def current(sock):
    """(index, name) of the deck's active window, or None."""
    try:
        out = subprocess.run(["tmux", "-S", sock, "list-windows", "-t", "=talk", "-F", "#{?window_active,#I\t#W,}"],
                             capture_output=True, text=True, timeout=2).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    for l in out.splitlines():
        if l.strip():
            i, _, n = l.partition("\t")
            return int(i), n
    return None


def follow(sock, path):
    """Presenter view: the current slide's notes and what's next, following the deck live.
    Run it on a second screen (phone, tablet) so the mirrored projector never shows it."""
    import time
    start, last = time.time(), None
    sys.stdout.write("\033[?25l")
    try:
        while True:
            W = shutil.get_terminal_size((80, 24)).columns
            cur, slides = current(sock), parse(path)
            key = (cur, os.stat(path).st_mtime, W, int(time.time() - start) // 60)
            if key != last:
                last = key
                byname = {s["name"]: (i, s) for i, s in enumerate(slides, 1)}
                out = ["\033[H\033[2J"]
                mins = int(time.time() - start) // 60
                if cur is None:
                    out.append(f"{DIM}no deck running on {sock}{RESET}\n")
                elif cur[1] not in byname:
                    out.append(f"{BOLD}{HEAD}window {cur[0]}: {cur[1]}{RESET}  {DIM}(not a slide){RESET}   {DIM}{mins}m{RESET}\n")
                else:
                    i, s = byname[cur[1]]
                    out.append(f"{BOLD}{HEAD}[{i}/{len(slides)}] {s['act']} / {s['name']}{RESET}"
                               + (f"  {CMD}(live){RESET}" if s["cmd"] else "") + f"   {DIM}{mins}m{RESET}\n\n")
                    notes = [l for l in s["notes"] if l.strip()] or [f"{DIM}(no notes){RESET}"]
                    for l in notes:
                        lead = len(l) - len(l.lstrip())
                        for j, part in enumerate(textwrap.wrap(l.strip(), max(20, W - 2 - lead)) or [""]):
                            out.append(" " * (lead + (2 if j else 0)) + part + "\n")
                    if i < len(slides):
                        n = slides[i]
                        head = next((l[3:] if l.startswith("## ") else l[2:] for l in n["body"] if l.startswith(("# ", "## "))), "")
                        out.append(f"\n{DIM}next: {n['name']}{'  (live)' if n['cmd'] else ''}{'  · ' + ANSI.sub('', inline(head)) if head else ''}{RESET}\n")
                sys.stdout.write("".join(out)); sys.stdout.flush()
            time.sleep(0.5)
    except KeyboardInterrupt:
        pass
    finally:
        sys.stdout.write("\033[?25h\n")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    mode, path = sys.argv[1], sys.argv[-1]
    slides = parse(path)
    if mode == "--list":
        for i, s in enumerate(slides, 1):
            print(f"{i}\t{s['name']}\t{s['act']}\t{s['cmd']}")
    elif mode == "--show":
        show(int(sys.argv[2]), path)
    elif mode == "--follow":
        follow(sys.argv[2], path)
    elif mode == "--notes":
        for i, s in enumerate(slides, 1):
            print(f"{BOLD}{HEAD}[{i}] {s['act']} / {s['name']}{RESET}" + (f"  {CMD}(live: {s['cmd']}){RESET}" if s["cmd"] else ""))
            for l in s["notes"]:
                if l.strip(): print("    " + l)
            print()


if __name__ == "__main__":
    main()
