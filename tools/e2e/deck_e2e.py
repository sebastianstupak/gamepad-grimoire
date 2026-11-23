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
        self.x(":1", f"mousemove {xy[0]} {xy[1]} click 1")

    def chat(self, line):
        """Types a chat line in WoW (only when no loading screen is up)."""
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


def scenario(deck):
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
    for cid in ("steamdeck", "xbox", "dualsense", "switchpro"):
        deck.chat("/gg controller " + cid)
        deck.chat("/gg show")
        time.sleep(1)
        shots.append((cid, deck.screenshot("10-card-" + cid)))
        deck.chat("/gg show")
    # peek: hold Shift (= LT on the default GamePadEmulateShift) like holding the trigger
    deck.chat("/gg controller steamdeck")
    deck.x(":1", "keydown shift")
    time.sleep(1.2)
    peek = deck.screenshot("20-peek-lt")
    deck.x(":1", "keyup shift")
    setup = setup_scenario(deck)
    deck.chat("/gg controller auto")
    deck.chat("/gg diag")
    return shots, peek, setup


def setup_scenario(deck):
    """Controller setup, driven with arrow keys / Enter / Tab / Escape - the same
    navigator inputs as D-pad / A / Y / B on a controller."""
    deck.chat("/gg profile copy E2E Setup")
    deck.chat("/gg profile use E2E Setup")
    deck.chat("/gg setup")
    time.sleep(0.8)

    def key(name):
        deck.x(":1", "key " + name)
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
    key("Escape")  # close setup
    deck.chat("/gg profile use E2E")
    return {"rows": rows, "picker": picker, "menu": menu}


def logout(deck):
    print("== logout")
    deck.chat("/logout")
    time.sleep(25)
    deck.x(":1", "key alt+F4")
    for _ in range(20):
        time.sleep(2)
        if not deck.wow_running():
            print("  WoW closed")
            return
    print("  ! WoW still running")


def saved_variables(deck):
    data = deck.get(ACCOUNT + "/SavedVariables/" + ADDON + ".lua")
    return data.decode("utf-8", errors="replace") if data else ""


def check(sv):
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
    images = [("cheatsheet-" + c, c, p) for c, p in shots] + [("cheatsheet-peek-lt", "steamdeck", peek)]
    images += [("setup-" + k, "steamdeck", v) for k, v in (setup or {}).items()]
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


SETUP_SHOTS = {"rows": "30-setup-rows", "picker": "31-setup-picker", "menu": "32-setup-menu"}
SHOT_NAMES = [(cid, "10-card-" + cid) for cid in ("steamdeck", "xbox", "dualsense", "switchpro")]


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
    shots, peek, setup = scenario(deck)
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
    ok = check(sv)
    if a.readme:
        readme_images(shots, peek, sv, setup)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
