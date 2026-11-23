#!/usr/bin/env python3
"""Virtual gamepad for the end-to-end test. Runs ON the test machine (Linux),
standard library only, through /dev/uinput (logged-in users may open it on
SteamOS).

  python3 vpad.py "wait 3" "press A" "hold LT 1.5" "press PADDLE1" ...
  python3 vpad.py serve /tmp/gg-vpad.fifo     # then: echo "press A" > /tmp/gg-vpad.fifo

It shows up as an Xbox Elite Series 2 (with paddles), so the game sees a real
controller: button presses, triggers and the D-pad go through the same path as
a player's. Steps:
  wait <s>             sleep
  press <button> [s]   press and release (default 0.15 s)
  hold <button> <s>    keep held for <s> seconds
Buttons: A B X Y LB RB LT RT L3 R3 VIEW MENU GUIDE UP DOWN LEFT RIGHT PADDLE1..4
"""

import os
import struct
import sys
import time

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
SYN_REPORT = 0
UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_ABSBIT = 0x40045564, 0x40045565, 0x40045567
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
BUS_USB = 0x03
VENDOR, PRODUCT = 0x045E, 0x0B00  # Xbox Elite Series 2

ABS_X, ABS_Y, ABS_Z, ABS_RX, ABS_RY, ABS_RZ, ABS_HAT0X, ABS_HAT0Y = 0, 1, 2, 3, 4, 5, 0x10, 0x11
KEYS = {
    "A": 0x130,
    "B": 0x131,
    "X": 0x133,
    "Y": 0x134,
    "LB": 0x136,
    "RB": 0x137,
    "VIEW": 0x13A,
    "MENU": 0x13B,
    "GUIDE": 0x13C,
    "L3": 0x13D,
    "R3": 0x13E,
    # xpad reports the Elite paddles as BTN_TRIGGER_HAPPY5..8
    "PADDLE1": 0x2C4,
    "PADDLE2": 0x2C5,
    "PADDLE3": 0x2C6,
    "PADDLE4": 0x2C7,
}
TRIGGERS = {"LT": ABS_Z, "RT": ABS_RZ}
HAT = {"UP": (ABS_HAT0Y, -1), "DOWN": (ABS_HAT0Y, 1), "LEFT": (ABS_HAT0X, -1), "RIGHT": (ABS_HAT0X, 1)}
AXES = {
    ABS_X: (-32768, 32767),
    ABS_Y: (-32768, 32767),
    ABS_RX: (-32768, 32767),
    ABS_RY: (-32768, 32767),
    ABS_Z: (0, 1023),
    ABS_RZ: (0, 1023),
    ABS_HAT0X: (-1, 1),
    ABS_HAT0Y: (-1, 1),
}


def setup_struct():
    """struct uinput_user_dev: name[80], input_id, ff_effects_max, abs max/min/fuzz/flat[64]."""
    name = b"Gamepad Grimoire test pad".ljust(80, b"\0")
    absmax, absmin = [0] * 64, [0] * 64
    for code, (lo, hi) in AXES.items():
        absmin[code], absmax[code] = lo, hi
    return (
        name
        + struct.pack("<HHHHI", BUS_USB, VENDOR, PRODUCT, 1, 0)
        + struct.pack("<64i", *absmax)
        + struct.pack("<64i", *absmin)
        + struct.pack("<64i", *([0] * 64))
        + struct.pack("<64i", *([0] * 64))
    )


def event(etype, code, value):
    """struct input_event on 64-bit Linux: timeval (2 x long), u16 type, u16 code, s32 value."""
    t = time.time()
    return struct.pack("<qqHHi", int(t), int((t % 1) * 1e6), etype, code, value)


class Pad:
    def __init__(self):
        import fcntl  # Linux only; imported here so the module loads anywhere (tests)

        self.ioctl = fcntl.ioctl
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        for ev in (EV_KEY, EV_ABS, EV_SYN):
            self.ioctl(self.fd, UI_SET_EVBIT, ev)
        for code in KEYS.values():
            self.ioctl(self.fd, UI_SET_KEYBIT, code)
        for code in AXES:
            self.ioctl(self.fd, UI_SET_ABSBIT, code)
        os.write(self.fd, setup_struct())
        self.ioctl(self.fd, UI_DEV_CREATE)

    def send(self, etype, code, value):
        os.write(self.fd, event(etype, code, value) + event(EV_SYN, SYN_REPORT, 0))

    def set(self, button, down):
        if button in KEYS:
            self.send(EV_KEY, KEYS[button], 1 if down else 0)
        elif button in TRIGGERS:
            self.send(EV_ABS, TRIGGERS[button], 1023 if down else 0)
        elif button in HAT:
            axis, value = HAT[button]
            self.send(EV_ABS, axis, value if down else 0)
        else:
            raise SystemExit(f"unknown button {button}")

    def close(self):
        self.ioctl(self.fd, UI_DEV_DESTROY)
        os.close(self.fd)


def step(pad, line):
    parts = line.split()
    if not parts:
        return
    if parts[0] == "wait":
        time.sleep(float(parts[1]))
    elif parts[0] in ("press", "hold"):
        held = float(parts[2]) if len(parts) > 2 else 0.15
        pad.set(parts[1], True)
        time.sleep(held)
        pad.set(parts[1], False)
        time.sleep(0.25)
    else:
        raise ValueError(f"unknown step {line}")


def serve(fifo):
    """Keeps the pad connected and runs steps written to `fifo`, one per line,
    until "quit" (the e2e test sends steps while it takes screenshots)."""
    if not os.path.exists(fifo):
        os.mkfifo(fifo)
    pad = Pad()
    try:
        while True:
            with open(fifo, encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line == "quit":
                        return
                    try:
                        step(pad, line)
                        print("ok", line, flush=True)
                    except (ValueError, SystemExit) as e:
                        print("error", e, flush=True)
    finally:
        pad.close()


def run(steps):
    pad = Pad()
    try:
        time.sleep(2)  # let the game notice the new controller
        for line in steps:
            step(pad, line)
            print("ok", line, flush=True)
    finally:
        pad.close()


if __name__ == "__main__":
    if sys.argv[1:2] == ["serve"]:
        serve(sys.argv[2])
    else:
        run(sys.argv[1:])
