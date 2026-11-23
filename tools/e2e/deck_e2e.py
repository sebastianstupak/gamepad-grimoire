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


def launch(deck):
    print("== launch")
    deck.sh(
        "pgrep -f 'systemd-inhibit.*gg-e2e' >/dev/null"
        " || (nohup systemd-inhibit --what=idle:sleep --why=gg-e2e sleep 3600 >/dev/null 2>&1 &)",
        check=False,
    )
    deck.x(":0", "mousemove_relative 5 5")
    deck.sh(
        "export DISPLAY=:0 XAUTHORITY=$(ls /run/user/1000/xauth_* 2>/dev/null | head -1); "
        f"steam -ifrunning steam://rungameid/{GAME_ID} >/dev/null 2>&1 &",
        check=False,
    )
    time.sleep(8)
    deck.click(WOWF_ICON)
    time.sleep(3)
    deck.click(PLAY)
    for _ in range(40):
        time.sleep(3)
        if deck.wow_running():
            break
    else:
        raise SystemExit("WoW did not start")
    print("  WoW started, waiting for character select")
    time.sleep(45)
    deck.screenshot("00-character-select")
    deck.click(ENTER_WORLD)
    print("  entering world")
    time.sleep(50)


def scenario(deck):
    print("== scenario")
    deck.chat("/gg diag")
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
    deck.chat("/gg controller auto")
    deck.chat("/gg diag")
    return shots, peek


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
    return all(ok for _, ok in results)


def card_rect(sv, cid):
    m = re.search(rf'\["{cid}"\] = \{{([^{{}}]*?\["left"\][^{{}}]*?)\}}', sv, re.S)
    if not m:
        return None
    vals = dict(re.findall(r'\["(left|right|top|bottom)"\] = ([\d.e-]+)', m.group(1)))
    return {k: float(v) for k, v in vals.items()} if len(vals) == 4 else None


def readme_images(shots, peek, sv):
    out = os.path.join(ROOT, "docs", "images")
    os.makedirs(out, exist_ok=True)
    pad = 0.012
    for name, cid, path in [("cheatsheet-" + c, c, p) for c, p in shots] + [("cheatsheet-peek-lt", "steamdeck", peek)]:
        rect = card_rect(sv, cid)
        if not (path and rect):
            print("  ! no screenshot or card position for", name)
            continue
        im = Image.open(path).convert("RGB")
        W, H = im.size
        box = (
            max(0, int((rect["left"] - pad) * W)),
            max(0, int((rect["top"] - pad) * H)),
            min(W, int((rect["right"] + pad) * W)),
            min(H, int((rect["bottom"] + pad) * H)),
        )
        im.crop(box).save(os.path.join(out, name + ".png"), optimize=True)
        print(f"  docs/images/{name}.png")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", default="deck@192.168.1.104")
    ap.add_argument("--key", default="~/.ssh/steamdeck")
    ap.add_argument("--no-launch", action="store_true", help="WoW is already in the world")
    ap.add_argument("--keep-running", action="store_true", help="do not log out at the end")
    ap.add_argument("--readme", action="store_true", help="update docs/images from the screenshots")
    a = ap.parse_args()
    deck = Deck(a.host, a.key)
    if not a.no_launch:
        install(deck)
        launch(deck)
    shots, peek = scenario(deck)
    if a.keep_running:
        return
    logout(deck)
    sv = saved_variables(deck)
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "SavedVariables.lua"), "w", encoding="utf-8") as f:
        f.write(sv)
    ok = check(sv)
    if a.readme:
        readme_images(shots, peek, sv)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
