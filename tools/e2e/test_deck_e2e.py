import io
import os
import sys
import tarfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import deck_e2e

SV = """
GamepadGrimoireDB = {
["diag"] = {
["share"] = {
["ok"] = true,
["length"] = 120,
},
["applied"] = 42,
["buttons"] = {
"PAD1",
"PAD2",
},
},
["profiles"] = {
["E2E"] = {
},
["Padx"] = {
},
["E2E Setup"] = {
["layers"] = {
["BASE"] = {
["PADLSHOULDER"] = {
["id"] = 348,
["type"] = "spell",
},
},
},
},
},
["debug"] = {
["cards"] = {
["xbox"] = {
["bottom"] = 0.61,
["left"] = 0.12,
["right"] = 0.88,
["top"] = 0.11,
},
},
},
}
"""


def test_package_contains_the_release_files_only():
    with tarfile.open(fileobj=io.BytesIO(deck_e2e.package())) as tar:
        names = tar.getnames()
    assert "GamepadGrimoire/GamepadGrimoire.toc" in names
    assert "GamepadGrimoire/src/Features/CheatSheet/View.lua" in names
    assert "GamepadGrimoire/media/controllers/xbox.tga" in names
    assert not [n for n in names if n.endswith("_spec.lua") or "/spec/" in n or "/tools/" in n]


def test_check_passes_on_a_good_report_and_fails_on_an_empty_one(capsys):
    assert deck_e2e.check(SV) is True
    assert deck_e2e.check("") is False
    assert "FAIL saved data written" in capsys.readouterr().out


def test_card_rect_is_read_per_controller():
    assert deck_e2e.card_rect(SV, "xbox") == {"bottom": 0.61, "left": 0.12, "right": 0.88, "top": 0.11}
    assert deck_e2e.card_rect(SV, "dualsense") is None


class FakeDeck:
    def __init__(self):
        self.cmds = []

    def sh(self, cmd, check=True):
        self.cmds.append(cmd)
        return ""


def test_conflicting_addons_are_disabled_with_a_backup_and_restored():
    deck = FakeDeck()
    deck_e2e.disable_conflicting(deck)
    deck_e2e.restore_addons(deck)
    disable, restore = deck.cmds
    assert 'cp "$f" "$f.gg-e2e-bak"' in disable
    assert "echo 'DeckSetup: disabled' >> \"$f\"" in disable
    assert "s/^DeckSetup: enabled/DeckSetup: disabled/" in disable
    assert "\n" not in disable
    assert 'mv -f "$b" "${b%.gg-e2e-bak}"' in restore
