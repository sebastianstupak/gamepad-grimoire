import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import vpad


def test_uinput_structs_have_the_kernel_layout():
    assert len(vpad.setup_struct()) == 80 + 4 * 2 + 4 + 4 * 64 * 4  # uinput_user_dev
    assert len(vpad.event(vpad.EV_KEY, vpad.KEYS["A"], 1)) == 24  # input_event, 64-bit


def test_every_button_the_e2e_presses_is_known():
    for b in ("A", "B", "X", "Y", "LB", "RB", "VIEW", "MENU", "L3", "R3", "PADDLE1", "PADDLE4"):
        assert b in vpad.KEYS
    assert set(vpad.TRIGGERS) == {"LT", "RT"}
    assert set(vpad.HAT) == {"UP", "DOWN", "LEFT", "RIGHT"}
