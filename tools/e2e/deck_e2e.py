"""End-to-end test on a real Steam Deck running WoW, driven over SSH.

  python tools/e2e/deck_e2e.py [--host deck@192.168.1.104] [--key ~/.ssh/steamdeck]
                               [--no-launch] [--keep-running] [--readme]

What it does (WoW must be closed and Battle.net signed in on the Deck):
  1. packages the addon (as the release would: toc + src without specs + media)
     and installs it on the Deck, backing up the previous copy;
  2. starts WoW from Battle.net in Gaming Mode and enters the world;
  3. types /gg commands in chat: diag, capture, profile use, show, peek (holds
     Shift = LT), every controller picture - taking a screenshot each time;
  4. logs out, closes WoW, reads GamepadGrimoireDB back from SavedVariables and
     checks the diagnostics report;
  5. with --readme, crops the cheat-sheet screenshots into docs/images/.

Dev rig only: coordinates below match Battle.net/WoW at 1280x800 in Gaming Mode.
"""

import argparse
import io
import os
import re
import shlex
import subprocess
import sys
import tarfile
import time

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ADDON = "GamepadGrimoire"
FOREVER = (
    "/home/deck/.local/share/Steam/steamapps/compatdata/2153225858/pfx/drive_c/"
    "Program Files (x86)/World of Warcraft/_forever_"
)
ACCOUNT = FOREVER + "/WTF/Account/1194444039#1"
GAME_ID = "9248034641045094400"
# Battle.net / WoW UI positions on DISPLAY=:1 (1280x800)
WOWF_ICON, PLAY, ENTER_WORLD = (163, 115), (155, 691), (640, 721)
OUT = os.path.join(ROOT, "tools", "e2e", "out")


class Deck:
    def __init__(self, host, key):
        self.host, self.key = host, os.path.expanduser(key)

    def sh(self, cmd, check=True, timeout=300):
        r = subprocess.run(
            ["ssh", "-i", self.key, "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", self.host, cmd],
            capture_output=True,
            timeout=timeout,
        )
        out = r.stdout.decode(errors="replace")
        if check and r.returncode != 0:
            err = r.stderr.decode(errors="replace")
            raise SystemExit(f"deck command failed ({r.returncode}): {cmd[:120]}\n{err}")
        return out

    def put(self, data, remote):
        r = subprocess.run(
            ["ssh", "-i", self.key, "-o", "BatchMode=yes", self.host, f"cat > {shlex.quote(remote)}"],
            input=data,
            capture_output=True,
        )
        if r.returncode:
            raise SystemExit("upload failed: " + r.stderr.decode(errors="replace"))

    def get(self, remote):
        r = subprocess.run(
            ["ssh", "-i", self.key, "-o", "BatchMode=yes", self.host, f"cat {shlex.quote(remote)}"],
            capture_output=True,
        )
        return r.stdout if r.returncode == 0 else None

    def x(self, display, args):
        env = f"export DISPLAY={display} XAUTHORITY=$(ls /run/user/1000/xauth_* 2>/dev/null | head -1);"
        return self.sh(env + " xdotool " + args, check=False)

    def click(self, xy):
        # Battle.net's web UI ignores a click that arrives without a hover first
        x, y = xy
        self.x(":1", f"mousemove {x - 3} {y - 3} sleep 0.4 mousemove {x} {y} sleep 0.4 mousedown 1 sleep 0.1 mouseup 1")

    def focused(self):
        """(window name, its size, screen size) of the focused window on the game display."""
        out = self.sh(
            "export DISPLAY=:1; w=$(xdotool getactivewindow); xdotool getwindowname $w;"
            " xdotool getwindowgeometry $w | sed -n 's/.*Geometry: //p'; xdotool getdisplaygeometry",
            check=False,
        ).splitlines()
        out += ["", "", ""]
        return out[0].strip(), out[1].strip(), out[2].strip().replace(" ", "x")

    def require_wow(self):
        """Stops the run unless the full-screen WoW window has focus. Battle.net
        windows (friends chat!) can take focus; typing must never reach them."""
        name, size, screen = self.focused()
        if name != "World of Warcraft" or size != screen:
            raise SystemExit(f"stopped: '{name}' ({size}) has focus, not the WoW window - nothing typed")

    def key(self, name):
        """Presses a key in WoW (refuses when another window has focus)."""
        self.require_wow()
        self.x(":1", "key " + name)

    def chat(self, line):
        """Types a chat line in WoW (only when no loading screen is up; refuses when
        another window has focus)."""
        self.require_wow()
        self.x(":1", "key Return")
        time.sleep(0.5)
        self.x(":1", f"type --delay 35 {shlex.quote(line)}")
        time.sleep(0.3)
        self.x(":1", "key Return")
        time.sleep(1.0)

    def screenshot(self, name):
        self.sh(
            "XDG_RUNTIME_DIR=/run/user/1000 gamescopectl screenshot /tmp/gg-e2e.png >/dev/null 2>&1; sleep 1",
            check=False,
        )
        data = self.get("/tmp/gg-e2e.png")
        if not data:
            print("  ! screenshot failed:", name)
            return None
        os.makedirs(OUT, exist_ok=True)
        path = os.path.join(OUT, name + ".png")
        with open(path, "wb") as f:
            f.write(data)
        print("  screenshot", os.path.relpath(path, ROOT))
        return path

    def bnet_running(self):
        # anchored: must not match this ssh command's own command line
        pattern = r"^C:.Program Files .x86..Battle\.net.Battle\.net\.exe --from-launcher"
        return self.sh(f"pgrep -f '{pattern}' >/dev/null && echo yes || echo no", check=False).strip() == "yes"

    def wow_running(self):
        return self.sh("pgrep -x Wow.exe >/dev/null && echo yes || echo no", check=False).strip() == "yes"


def package():
    """The files a release contains (mirrors .pkgmeta): toc, src without specs, media, LICENSE."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:

        def add(rel):
            tar.add(os.path.join(ROOT, rel), arcname=ADDON + "/" + rel.replace(os.sep, "/"))

        add(ADDON + ".toc")
        add("LICENSE")
        for base in ("src", "media"):
            for dirpath, _, files in os.walk(os.path.join(ROOT, base)):
                for f in sorted(files):
                    if not f.endswith("_spec.lua"):
                        add(os.path.relpath(os.path.join(dirpath, f), ROOT))
    return buf.getvalue()


def install(deck):
    print("== install")
    if deck.wow_running():
        raise SystemExit("WoW is running on the Deck - close it first")
    deck.put(package(), "/tmp/gg-addon.tgz")
    addons = shlex.quote(FOREVER + "/Interface/AddOns")
    deck.sh(
        f"cd {addons} && if [ -d {ADDON} ]; then mkdir -p ~/wow-backups/addons"
        f" && mv {ADDON} ~/wow-backups/addons/{ADDON}-$(date +%Y%m%d-%H%M%S); fi"
        f" && tar -xzf /tmp/gg-addon.tgz && rm /tmp/gg-addon.tgz && ls {ADDON} | head"
    )
    print("  installed", ADDON)


CONFLICTING = ("DeckSetup",)  # addons that also answer LT+R3 / draw a card


def disable_conflicting(deck):
    """Disables CONFLICTING addons in every character's AddOns.txt (WoW closed),
    keeping a backup that restore_addons() puts back."""
    per_addon = "".join(
        rf"""grep -q '^{a}:' "$f" || echo '{a}: disabled' >> "$f"; sed -i 's/^{a}: enabled/{a}: disabled/' "$f"; """
        for a in CONFLICTING
    )
    out = deck.sh(
        f"cd {shlex.quote(ACCOUNT)} && "
        r'for f in */*/AddOns.txt; do [ -f "$f" ] || continue; cp "$f" "$f.gg-e2e-bak"; '
        + per_addon
        + r'echo "$f"; done',
        check=False,
    )
    print("  disabled", ", ".join(CONFLICTING), "in", len(out.split()), "AddOns.txt")


def restore_addons(deck):
    out = deck.sh(
        f'cd {shlex.quote(ACCOUNT)} && for b in */*/AddOns.txt.gg-e2e-bak; do [ -f "$b" ] || continue;'
        f' mv -f "$b" "${{b%.gg-e2e-bak}}"; echo "$b"; done',
        check=False,
    )
    print("  restored", len(out.split()), "AddOns.txt")


VPAD = "/home/deck/.local/share/gamepad-grimoire-e2e/vpad.py"
VPAD_FIFO = "/tmp/gg-vpad.fifo"
BNET_HIDDEN = "/tmp/gg-bnet-hidden"


class VirtualPad:
    """A virtual Xbox Elite pad on the Deck (tools/e2e/vpad.py), run as a user
    service; steps are written to a FIFO so presses can overlap screenshots."""

    def __init__(self, deck):
        self.deck = deck
        # Battle.net reads controllers too and acts on them (opens friends chat, file
        # browsers...): hide its windows while the virtual pad exists
        deck.sh(
            f"export DISPLAY=:1; xdotool search --name '^Battle.net' > {BNET_HIDDEN} 2>/dev/null;"
            f" for w in $(cat {BNET_HIDDEN}); do xdotool windowunmap $w; done",
            check=False,
        )
        with open(os.path.join(ROOT, "tools", "e2e", "vpad.py"), "rb") as f:
            deck.sh(f"mkdir -p {os.path.dirname(VPAD)}")
            deck.put(f.read(), VPAD)
        deck.sh(
            f"systemctl --user stop gg-vpad 2>/dev/null; rm -f {VPAD_FIFO}; mkfifo {VPAD_FIFO};"
            f" systemd-run --user --unit=gg-vpad python3 {VPAD} serve {VPAD_FIFO} >/dev/null 2>&1",
            check=False,
        )
        time.sleep(3)  # the game picks up the new controller
        if deck.sh("systemctl --user is-active gg-vpad", check=False).strip() != "active":
            log = deck.sh("journalctl --user -u gg-vpad -n 20 --no-pager", check=False)
            raise SystemExit("virtual gamepad did not start:\n" + log)

    def send(self, *steps, wait=True):
        """Queues steps; with wait, sleeps about as long as they take."""
        body = "\n".join(steps)
        self.deck.sh(f"printf '%s\\n' {shlex.quote(body)} > {VPAD_FIFO}", check=False)
        if wait:
            took = 0.0
            for st in steps:
                parts = st.split()
                took += float(parts[1]) if parts[0] == "wait" else (float(parts[2]) if len(parts) > 2 else 0.15) + 0.25
            time.sleep(took + 0.4)

    def press(self, *buttons):
        self.send(*("press " + b for b in buttons))

    def close(self):
        self.send("quit", wait=False)
        time.sleep(1)
        self.deck.sh("systemctl --user stop gg-vpad 2>/dev/null; rm -f " + VPAD_FIFO, check=False)
        self.deck.sh(
            f"export DISPLAY=:1; for w in $(cat {BNET_HIDDEN} 2>/dev/null); do xdotool windowmap $w; done;"
            f" rm -f {BNET_HIDDEN}",
            check=False,
        )


def keep_awake(deck, on=True):
    """Blocks sleep / idle / lid suspend for the whole run. A user service, so it
    survives the SSH session that starts it (a nohup'ed child does not)."""
    if on:
        out = deck.sh(
            "systemctl --user is-active -q gg-e2e-awake || systemd-run --user --unit=gg-e2e-awake"
            " systemd-inhibit --what=idle:sleep:handle-lid-switch --who=gamepad-grimoire --why=e2e-test sleep 3600"
            " >/dev/null 2>&1; systemctl --user is-active gg-e2e-awake",
            check=False,
        ).strip()
        if out != "active":
            raise SystemExit("could not stop the Deck from sleeping")
        print("  Deck kept awake for the run")
    else:
        deck.sh("systemctl --user stop gg-e2e-awake", check=False)


def ensure_gaming_mode(deck):
    """The click positions are for Gaming Mode (gamescope); switch if in Desktop Mode."""

    def active():
        return deck.sh("systemctl --user is-active gamescope-session", check=False).strip() == "active"

    if active():
        return
    print("  switching the Deck to Gaming Mode")
    deck.sh("(steamos-session-select gamescope >/dev/null 2>&1 &)", check=False)
    for _ in range(30):
        time.sleep(3)
        if active():
            time.sleep(20)  # Steam UI
            return
    raise SystemExit("could not switch the Deck to Gaming Mode")


def launch(deck):
    print("== launch")
    ensure_gaming_mode(deck)
    deck.x(":0", "mousemove_relative 5 5")  # wake Steam's screensaver
    deck.sh(
        "export DISPLAY=:0 XAUTHORITY=$(ls /run/user/1000/xauth_* 2>/dev/null | head -1); "
        f"steam -ifrunning steam://rungameid/{GAME_ID} >/dev/null 2>&1 &",
        check=False,
    )
    if not deck.bnet_running():
        print("  starting Battle.net")
        for _ in range(60):
            time.sleep(3)
            if deck.bnet_running():
                break
        else:
            raise SystemExit("Battle.net did not start")
        time.sleep(45)  # UI + automatic sign-in
    else:
        time.sleep(8)
    deck.screenshot("00-battlenet")
    deck.click(WOWF_ICON)
    time.sleep(3)
    deck.click(PLAY)
    for _ in range(40):
        time.sleep(3)
        if deck.wow_running():
            break
    else:
        raise SystemExit("WoW did not start")
    args = deck.sh(r"tr '\0' ' ' < /proc/$(pgrep -x Wow.exe | head -1)/cmdline", check=False)
    if "-launcherlogin" not in args:
        print("  ! WoW started without a Battle.net login (wow-guard restarts Battle.net) - retrying once")
        time.sleep(60)
        deck.click(WOWF_ICON)
        time.sleep(3)
        deck.click(PLAY)
        time.sleep(20)
    print("  WoW started, waiting for character select")
    time.sleep(45)
    deck.screenshot("01-character-select")
    deck.click(ENTER_WORLD)
    print("  entering world")
    time.sleep(50)


def scenario(deck, pad=True):
    print("== scenario")
    deck.chat("/gg diag")
    deck.chat("/gg profile use Default")
    deck.chat("/gg profile delete E2E")  # leftovers of an earlier run
    deck.chat("/gg profile delete E2E Setup")
    deck.chat("/gg capture E2E")
    deck.chat("/gg profile use E2E")
    time.sleep(1)
    deck.screenshot("01-chat-diag")
    shots = []
    for cid in controller_ids():
        deck.chat("/gg controller " + cid)
        shots.append((cid, shot_with_card(deck, "10-card-" + cid)))
        deck.chat("/gg flip")  # the back of the controller
        time.sleep(1)
        shots.append((cid + "_back", deck.screenshot("11-back-" + cid)))
        deck.chat("/gg flip")
        deck.chat("/gg hide")
    # peek: hold Shift (= LT on the default GamePadEmulateShift) like holding the trigger
    deck.chat("/gg controller steamdeck")
    deck.require_wow()
    deck.x(":1", "keydown shift")
    time.sleep(1.2)
    peek = deck.screenshot("20-peek-lt")
    deck.x(":1", "keyup shift")
    setup = setup_scenario(deck)
    if pad:
        setup.update(gamepad_scenario(deck))
    setup.update(chat_scenario(deck))
    deck.chat("/gg controller auto")
    deck.chat("/gg diag")
    return shots, peek, setup


def card_visible(path):
    """True when the card (a dark panel across the upper screen) is in the screenshot."""
    im = Image.open(path).convert("RGB")
    w, h = im.size
    band = im.crop((int(w * 0.06), int(h * 0.12), int(w * 0.94), int(h * 0.5))).resize((112, 30))
    dark = sum(1 for r, g, b in band.getdata() if r < 40 and g < 40 and b < 50)
    return dark / (112 * 30) > 0.25


def shot_with_card(deck, name, command="/gg show base"):
    """Pins the card and screenshots it. Typed chat can get lost while the game is
    busy, so the commands are idempotent and a missing card is retried once."""
    for attempt in range(2):
        deck.chat(command)
        time.sleep(1)
        path = deck.screenshot(name)
        if card_visible(path):
            return path
        print("  ! no card on", name, "- retrying" if attempt == 0 else "- giving up")
    return path


def gamepad_scenario(deck):
    """Everything through a (virtual) controller on the Steam Deck picture: setup
    navigation, binding a back grip on the back of the Deck, the on-screen keyboard
    and held buttons. A screenshot after every step, for reviewing the UI as well as
    the result. The virtual pad's back buttons are not pressed: through Proton they
    arrive in WoW as face buttons (P1 = B closes the setup), so the back grips are
    reached with the D-pad, as a player would on a Deck whose grips go to Steam Input."""
    print("== gamepad")
    deck.chat("/gg profile delete Padx")  # leftover of an earlier run
    deck.chat("/gg profile use E2E Setup")
    deck.chat("/gg controller steamdeck")
    pad = VirtualPad(deck)
    shots = {}

    def step(key, name, *buttons):
        pad.press(*buttons)
        time.sleep(0.4)
        deck.require_wow()  # the pad must not have driven another window
        shots[key] = deck.screenshot(name)

    try:
        pad.press("DOWN")  # first input makes the virtual pad the active controller
        # before the setup opens: while it is open it takes Enter, so typing in chat would act on it
        deck.chat("/gg diag")  # records the buttons the game sees (incl. paddles or not)
        deck.chat("/gg setup")
        time.sleep(0.8)
        shots["open"] = deck.screenshot("39-setup-open")
        step("back", "40-setup-back", "VIEW")  # View: back of the Deck
        # back rows: left L2 L1 L4 L5, right R2 R1 R4 R5
        step("paddle", "41-setup-paddle", "RIGHT", "DOWN", "DOWN")  # R4
        step("paddle-picker", "41b-setup-paddle-picker", "A")  # spell list for R4
        step("paddle-bound", "41c-setup-paddle-bound", "DOWN", "A")  # second spell on R4
        step("front", "41d-setup-front", "VIEW")
        # menu from the bottom: Close, Capture, Card size, Controller, spec, Delete, Rename, Copy, New
        step("menu-pad", "41e-setup-menu", "Y", *["DOWN"] * 25)
        pad.press(*["UP"] * 8, "A")  # New empty profile...
        # "Pad": P (row 2, col 6), a (row 1, col 1), d (row 1, col 4)
        pad.press("DOWN", *["RIGHT"] * 5, "A", "UP", *["LEFT"] * 5, "A", *["RIGHT"] * 3, "A")
        shots["keys"] = deck.screenshot("42-setup-keyboard")
        pad.press("Y")  # done: profile "Pad" created and used
        pad.press("Y", *["DOWN"] * 25, *["UP"] * 6, "A")  # Rename Pad...
        step("rename", "42b-setup-rename", "DOWN", "DOWN", *["RIGHT"] * 3, "A")  # append "x"
        step("renamed", "42c-setup-renamed", "Y")  # "Padx"
        pad.press("B")  # close setup
        time.sleep(0.5)
        shots["closed"] = deck.screenshot("42d-setup-closed")
        shot_with_card(deck, "43-pinned")  # pin the card (not in setup: presses reach the game)
        pad.send("hold RB 2.5", wait=False)
        time.sleep(1.2)
        shots["held"] = deck.screenshot("43-held-rb")
        time.sleep(1.8)
        deck.chat("/gg hide")
        pad.send("hold LT 2", wait=False)  # peek with the real trigger
        time.sleep(1.2)
        shots["peek-pad"] = deck.screenshot("45-peek-pad")
        time.sleep(1.2)
    finally:
        pad.close()
    deck.chat("/gg profile use E2E")
    return shots


# profiles the chat scenario makes; check() looks for what is left of them
CHAT_PROFILES = ("Chat A", "Chat B", "Chat C", "Chat Gone", "Chat Keys")


def chat_scenario(deck):
    """Every slash command once, typed in chat. What they change is checked in the
    saved data after logout (check()); what they show is screenshotted."""
    print("== chat commands")
    deck.chat("/gg profile use E2E")
    for name in CHAT_PROFILES:  # leftovers of an earlier run
        deck.chat("/gg profile delete " + name)
    shots = {}
    deck.chat("/gg help")
    deck.chat("/gg profile")
    time.sleep(0.5)
    shots["chat-help"] = deck.screenshot("50-chat-help")
    deck.chat("/gg profile new Chat A")
    deck.chat("/gg profile use Chat A")
    deck.chat("/gg profile copy Chat B")
    deck.chat("/gg profile rename Chat B = Chat C")
    deck.chat("/gg profile new Chat Gone")
    deck.chat("/gg profile delete Chat Gone")
    deck.chat("/gg capture Chat Keys")
    deck.chat("/gg profile use Chat C")
    deck.chat("/gg controller dualsense")  # stored in Chat C
    deck.chat("/gg scale 1.3")
    shots["chat-show-lt"] = shot_with_card(deck, "51-chat-show-lt", "/gg show lt")
    deck.chat("/gg hide")
    deck.chat("/gg scale auto")
    deck.chat("/gg export")
    time.sleep(0.8)
    shots["chat-export"] = deck.screenshot("52-chat-export")
    deck.key("Escape")
    deck.chat("/gg import")
    time.sleep(0.8)
    shots["chat-import"] = deck.screenshot("53-chat-import")
    deck.key("Escape")
    deck.chat("/gg setup")
    time.sleep(0.8)
    shots["chat-setup"] = deck.screenshot("54-chat-setup")
    deck.chat("/gg setup")
    deck.chat("/gg reload")
    deck.chat("/grimoire profile use E2E")  # the long alias
    return shots


def _block(sv, key):
    """Text of the table saved under ["key"] = { ... } (balanced braces), or None."""
    start = sv.find(f'["{key}"] = {{')
    if start < 0:
        return None
    i = sv.index("{", start)
    depth = 0
    for j in range(i, len(sv)):
        depth += {"{": 1, "}": -1}.get(sv[j], 0)
        if depth == 0:
            return sv[i : j + 1]
    return None


def setup_scenario(deck):
    """Controller setup, driven with arrow keys / Enter / Tab / Escape - the same
    navigator inputs as D-pad / A / Y / B on a controller."""
    deck.chat("/gg profile copy E2E Setup")
    deck.chat("/gg profile use E2E Setup")
    deck.chat("/gg setup")
    time.sleep(0.8)

    def key(name):
        deck.key(name)
        time.sleep(0.5)

    key("Down")  # L1 row
    rows = deck.screenshot("30-setup-rows")
    key("Return")  # spell picker
    key("Down")
    time.sleep(0.5)
    picker = deck.screenshot("31-setup-picker")
    key("Return")  # bind the second spell to L1
    key("Tab")  # menu: profiles, controller, size...
    time.sleep(0.5)
    menu = deck.screenshot("32-setup-menu")
    key("Escape")  # back to the rows
    # the back of the Deck (V = View): rows left L2 L1 L4 L5, right R2 R1 R4 R5
    key("v")
    key("Right")
    key("Down")
    key("Down")  # R4
    key("Return")
    key("Down")
    key("Return")  # second spell on R4
    time.sleep(0.5)
    back = deck.screenshot("33-setup-back-bound")
    key("v")  # front again
    # on-screen keyboard: menu from the bottom (Close, Capture, Card size,
    # Controller, spec, Delete, Rename, Copy, New), New empty profile...
    key("Tab")
    for _ in range(25):
        key("Down")
    for _ in range(8):
        key("Up")
    key("Return")
    for ch in "deck":
        key(ch)  # a real keyboard types into the on-screen keyboard
    time.sleep(0.5)
    keys = deck.screenshot("34-setup-keyboard")
    key("Escape")  # cancel the name: back to the menu
    key("Escape")  # rows
    key("Escape")  # close setup
    deck.chat("/gg profile use E2E")
    return {"rows": rows, "picker": picker, "menu": menu, "back": back, "keys": keys}


def logout(deck):
    print("== logout")
    deck.chat("/logout")
    time.sleep(25)
    deck.key("alt+F4")
    for _ in range(20):
        time.sleep(2)
        if not deck.wow_running():
            print("  WoW closed")
            return
    print("  ! WoW still running")


def saved_variables(deck):
    data = deck.get(ACCOUNT + "/SavedVariables/" + ADDON + ".lua")
    return data.decode("utf-8", errors="replace") if data else ""


def check(sv, pad=True):
    print("== checks")
    results = []

    def expect(name, ok):
        results.append((name, bool(ok)))
        print("  {} {}".format("PASS" if ok else "FAIL", name))

    expect("saved data written", "GamepadGrimoireDB" in sv)
    expect("diagnostics report saved", '["diag"]' in sv)
    expect("share string round trip", re.search(r'\["share"\] = \{[^}]*\["ok"\] = true', sv, re.S))
    expect("E2E profile captured", '["E2E"]' in sv)
    expect("captured binds applied", re.search(r'\["applied"\] = [1-9]', sv))
    diag_buttons = re.search(r'\["buttons"\] = \{([^}]*)\}', sv, re.S)
    seen = re.findall(r'"(PAD\w+)"', diag_buttons.group(1)) if diag_buttons else []
    if pad:
        expect("the game sees the virtual gamepad", "PAD1" in seen)
    print("    buttons the game sees:", " ".join(seen) or "-")
    # listed is not the same as pressed: the virtual Elite's paddles arrive as face buttons
    print("    back-button slots listed by the game:", "yes" if "PADPADDLE1" in seen else "no")
    if pad:
        expect("profile named with the on-screen keyboard (gamepad only)", '["Padx"]' in sv)
    chat_c = _block(sv, "Chat C") or ""
    expect("chat: profile new / copy / rename kept Chat A and Chat C", '["Chat A"]' in sv and chat_c)
    expect("chat: renamed and deleted profiles are gone", '["Chat B"]' not in sv and '["Chat Gone"]' not in sv)
    expect("chat: controller choice saved in the profile", '"dualsense"' in chat_c)
    expect("chat: capture made a profile", '["Chat Keys"]' in sv)
    expect("chat: scale back to automatic", '["scale"]' not in (_block(sv, "settings") or ""))
    expect(
        "back grip R4 bound on the back of the Deck",
        re.search(r'\["E2E Setup"\] = \{.*?\["BASE"\] = \{.*?\["PADPADDLE1"\] = \{[^}]*"spell"', sv, re.S),
    )
    expect(
        "controller setup bound a spell to L1",
        re.search(r'\["E2E Setup"\] = \{.*?\["BASE"\] = \{.*?\["PADLSHOULDER"\] = \{[^}]*"spell"', sv, re.S),
    )
    return all(ok for _, ok in results)


def card_rect(sv, cid):
    m = re.search(rf'\["{cid}"\] = \{{([^{{}}]*?\["left"\][^{{}}]*?)\}}', sv, re.S)
    if not m:
        return None
    vals = dict(re.findall(r'\["(left|right|top|bottom)"\] = ([\d.e-]+)', m.group(1)))
    return {k: float(v) for k, v in vals.items()} if len(vals) == 4 else None


def readme_images(shots, peek, sv, setup=None):
    """README images: the whole screen width from the top down to a bit below the card,
    so the card is shown as the overlay it is, over the game."""
    out = os.path.join(ROOT, "docs", "images")
    os.makedirs(out, exist_ok=True)
    images = [("cheatsheet-" + c.replace("_back", "-back"), c, p) for c, p in shots]
    images += [("cheatsheet-peek-lt", "steamdeck", peek)]
    # setup / gamepad shots: crop with the card that was on screen
    card_of = {"back": "steamdeck_back"}
    images += [("setup-" + k, card_of.get(k, "steamdeck"), v) for k, v in (setup or {}).items() if k in SETUP_SHOTS]
    for name, cid, path in images:
        rect = card_rect(sv, cid)
        if not (path and rect):
            print("  ! no screenshot or card position for", name)
            continue
        im = Image.open(path).convert("RGB")
        W, H = im.size
        bottom = min(H, int((rect["bottom"] + 0.2) * H))
        im.crop((0, 0, W, bottom)).save(os.path.join(out, name + ".png"), optimize=True)
        print(f"  docs/images/{name}.png")


SETUP_SHOTS = {
    "rows": "30-setup-rows",
    "picker": "31-setup-picker",
    "menu": "32-setup-menu",
    "back": "33-setup-back-bound",
    "keys": "34-setup-keyboard",
    "held": "43-held-rb",
}


def controller_ids():
    """Front-view controller ids, in registration order, from the generated definitions."""
    with open(os.path.join(ROOT, "src", "Features", "Controllers", "Definitions.lua"), encoding="utf-8") as f:
        ids = re.findall(r'id = "(\w+)"', f.read())
    return [i for i in ids if not i.endswith("_back")]


SHOT_NAMES = [(cid, "10-card-" + cid) for cid in controller_ids()]
SHOT_NAMES += [(cid + "_back", "11-back-" + cid) for cid in controller_ids()]


def readme_from_last_run():
    """Re-crops docs/images from tools/e2e/out (no Deck needed)."""
    with open(os.path.join(OUT, "SavedVariables.lua"), encoding="utf-8") as f:
        sv = f.read()
    shots = [(cid, os.path.join(OUT, n + ".png")) for cid, n in SHOT_NAMES]
    setup = {k: os.path.join(OUT, n + ".png") for k, n in SETUP_SHOTS.items()}
    readme_images(shots, os.path.join(OUT, "20-peek-lt.png"), sv, setup)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", default="deck@192.168.1.104")
    ap.add_argument("--key", default="~/.ssh/steamdeck")
    ap.add_argument("--no-launch", action="store_true", help="WoW is already in the world")
    ap.add_argument("--keep-running", action="store_true", help="do not log out at the end")
    ap.add_argument("--readme", action="store_true", help="update docs/images from the screenshots")
    ap.add_argument("--no-pad", action="store_true", help="skip the virtual gamepad scenario")
    ap.add_argument("--readme-only", action="store_true", help="only re-crop docs/images from the last run")
    a = ap.parse_args()
    if a.readme_only:
        readme_from_last_run()
        return
    deck = Deck(a.host, a.key)
    keep_awake(deck)
    if not deck.wow_running():
        restore_addons(deck)  # leftovers of an interrupted run (WoW rewrites AddOns.txt on exit)
    if not a.no_launch:
        install(deck)
        disable_conflicting(deck)
        launch(deck)
    shots, peek, setup = scenario(deck, pad=not a.no_pad)
    if a.keep_running:
        return
    logout(deck)
    if not deck.wow_running():
        restore_addons(deck)
    keep_awake(deck, False)
    sv = saved_variables(deck)
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "SavedVariables.lua"), "w", encoding="utf-8") as f:
        f.write(sv)
    ok = check(sv, pad=not a.no_pad)
    if a.readme:
        readme_images(shots, peek, sv, setup)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
