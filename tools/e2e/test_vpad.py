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


class Recorder(vpad.Pad):
    """A Pad that records events instead of writing to /dev/uinput."""

    def __init__(self):
        self.sent = []

    def send(self, etype, code, value):
        self.sent.append((etype, code, value))


def test_press_holds_a_button_then_releases_it(monkeypatch):
    slept = []
    monkeypatch.setattr(vpad.time, "sleep", slept.append)
    pad = Recorder()
    vpad.step(pad, "press A")
    vpad.step(pad, "hold PADDLE3 1.5")
    assert pad.sent == [
        (vpad.EV_KEY, vpad.KEYS["A"], 1),
        (vpad.EV_KEY, vpad.KEYS["A"], 0),
        (vpad.EV_KEY, vpad.KEYS["PADDLE3"], 1),
        (vpad.EV_KEY, vpad.KEYS["PADDLE3"], 0),
    ]
    assert slept == [0.15, 0.25, 1.5, 0.25]


def test_triggers_and_dpad_are_axes(monkeypatch):
    monkeypatch.setattr(vpad.time, "sleep", lambda _: None)
    pad = Recorder()
    vpad.step(pad, "press LT")
    vpad.step(pad, "press UP")
    axis, value = vpad.HAT["UP"]
    assert pad.sent == [
        (vpad.EV_ABS, vpad.TRIGGERS["LT"], 1023),
        (vpad.EV_ABS, vpad.TRIGGERS["LT"], 0),
        (vpad.EV_ABS, axis, value),
        (vpad.EV_ABS, axis, 0),
    ]


def test_wait_blank_and_bad_steps(monkeypatch):
    slept = []
    monkeypatch.setattr(vpad.time, "sleep", slept.append)
    pad = Recorder()
    vpad.step(pad, "")
    vpad.step(pad, "wait 2")
    assert slept == [2.0] and pad.sent == []
    import pytest

    with pytest.raises(ValueError):
        vpad.step(pad, "dance")
    with pytest.raises(SystemExit):
        vpad.step(pad, "press TURBO")


def test_paddles_are_distinct_keys_the_game_maps_to_padpaddle1_to_4():
    codes = [vpad.KEYS[f"PADDLE{i}"] for i in range(1, 5)]
    assert len(set(codes)) == 4
    assert not set(codes) & {vpad.KEYS[b] for b in ("A", "B", "X", "Y", "LB", "RB")}
