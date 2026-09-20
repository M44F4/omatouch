#!/usr/bin/env python3
"""Three-finger double-tap gesture daemon for OmaTouch.

Watches the touchscreen directly via the raw Linux evdev protocol -- no
python-evdev, no new package, just the standard library reading
/dev/input/eventN the same way every input driver already does. On two
quick, clean three-finger taps in a row, toggles the OmaTouch keyboard via
its own IPC.

The touchscreen is selected by its multitouch capabilities rather than its
reported name.
"""
import fcntl
import glob
import json
import os
import re
import struct
import subprocess
import sys
import threading
import time

EVENT_FMT = "qqHHi"
EVENT_SIZE = struct.calcsize(EVENT_FMT)

EV_SYN = 0x00
EV_ABS = 0x03
SYN_REPORT = 0
ABS_MT_SLOT = 0x2F
ABS_MT_TRACKING_ID = 0x39
ABS_MT_POSITION_X = 0x35
ABS_MT_POSITION_Y = 0x36

TOUCH_COUNT = 3
FALLBACK_MAX_MOVEMENT = 300
TAP_MAX_HOLD_MS = 700       # how long 3 fingers can stay down and still count as "a tap"
DOUBLE_TAP_WINDOW_MS = 700  # max gap between the two taps

STATE_DIR = os.path.expanduser("~/.local/state/omarchy/omatouch")
ENABLED_FLAG = os.path.join(STATE_DIR, "gesture-enabled")
HEARTBEAT_PATH = os.path.join(STATE_DIR, "gesture-heartbeat.json")
HEARTBEAT_INTERVAL_S = 30


INPUT_PROP_DIRECT = 0x01  # linux/input.h -- "direct input", i.e. a touchscreen


def _device_name(n):
    try:
        return open(f"/sys/class/input/event{n}/device/name").read().strip()
    except OSError:
        return ""


def find_touchscreens():
    candidates = []
    for path in glob.glob("/sys/class/input/event*/device/capabilities/abs"):
        m = re.search(r"event(\d+)", path)
        if not m:
            continue
        n = int(m.group(1))
        try:
            val = int(open(path).read().strip(), 16)
        except (OSError, ValueError):
            continue
        needed = (ABS_MT_SLOT, ABS_MT_TRACKING_ID, ABS_MT_POSITION_X, ABS_MT_POSITION_Y)
        if not all((val >> bit) & 1 for bit in needed):
            continue
        try:
            props = int(open(f"/sys/class/input/event{n}/device/properties").read().strip(), 16)
        except (OSError, ValueError):
            props = 0
        if not (props >> INPUT_PROP_DIRECT) & 1:
            continue
        candidates.append((n, _device_name(n)))
    candidates.sort(key=lambda c: (("unknown" in c[1].lower()), c[0]))
    return candidates


def find_touchscreen():
    candidates = find_touchscreens()
    return f"/dev/input/event{candidates[0][0]}" if candidates else None


def now_ms():
    return time.monotonic() * 1000


def _ioc(direction, type_char, nr, size):
    return (direction << 30) | (size << 16) | (ord(type_char) << 8) | nr


def _eviocgabs(abs_code):
    return _ioc(2, "E", 0x40 + abs_code, 24)  # _IOR('E', 0x40+abs, struct input_absinfo)


def abs_range(fd, abs_code):
    buf = bytearray(24)
    fcntl.ioctl(fd, _eviocgabs(abs_code), buf)
    _value, minimum, maximum, _fuzz, _flat, _resolution = struct.unpack("iiiiii", buf)
    return minimum, maximum


def movement_threshold_for(fd):
    try:
        mn, mx = abs_range(fd, ABS_MT_POSITION_X)
        span = mx - mn
        if span > 0:
            return max(30, int(span * 0.08))
    except OSError:
        pass
    return FALLBACK_MAX_MOVEMENT


def is_enabled():
    try:
        return open(ENABLED_FLAG).read().strip() != "0"
    except OSError:
        return True


def write_heartbeat(device_name):
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        tmp_path = HEARTBEAT_PATH + ".tmp"
        with open(tmp_path, "w") as f:
            json.dump({"ts": time.time(), "device": device_name}, f)
        os.replace(tmp_path, HEARTBEAT_PATH)
    except OSError:
        pass  # best-effort -- a failed heartbeat write shouldn't kill the daemon


def start_heartbeat_thread(device_name):
    def loop():
        while True:
            time.sleep(HEARTBEAT_INTERVAL_S)
            write_heartbeat(device_name)
    t = threading.Thread(target=loop, daemon=True)
    t.start()


def discover_wayland_env():
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    display = os.environ.get("WAYLAND_DISPLAY")
    if not display:
        try:
            candidates = sorted(
                f for f in os.listdir(runtime_dir)
                if f.startswith("wayland-") and not f.endswith(".lock")
            )
            display = candidates[0] if candidates else None
        except OSError:
            display = None
    return runtime_dir, display or "wayland-1"


def toggle_keyboard():
    if not is_enabled():
        return
    runtime_dir, display = discover_wayland_env()
    env = dict(os.environ)
    env["XDG_RUNTIME_DIR"] = runtime_dir
    env["WAYLAND_DISPLAY"] = display
    subprocess.Popen(
        ["quickshell", "-p", "/usr/share/omarchy/shell", "ipc", "call", "m44f4.omatouch", "toggle"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env,
    )


def main():
    if len(sys.argv) > 1:
        dev_path, dev_name = sys.argv[1], "(explicit)"
    else:
        candidates = find_touchscreens()
        if candidates:
            print("Multitouch+direct candidates: " + ", ".join(
                f"event{n} ({name or 'unnamed'})" for n, name in candidates), flush=True)
        dev_path = f"/dev/input/event{candidates[0][0]}" if candidates else None
        dev_name = candidates[0][1] if candidates else ""
    if not dev_path:
        sys.exit(
            "No multitouch touchscreen found (looked for a device reporting "
            "ABS_MT_SLOT + ABS_MT_TRACKING_ID + ABS_MT_POSITION_X/Y and "
            "INPUT_PROP_DIRECT under /sys/class/input/*/device)."
        )

    fd = os.open(dev_path, os.O_RDONLY)
    max_movement = movement_threshold_for(fd)
    print(f"Watching {dev_path} ({dev_name or 'unnamed'}) for a three-finger double-tap "
          f"(movement allowance: {max_movement} units).", flush=True)

    write_heartbeat(dev_name or dev_path)
    start_heartbeat_thread(dev_name or dev_path)
    last_frame_heartbeat_ms = now_ms()

    slots = {}            # slot id -> {"x0": int|None, "y0": int|None}
    cur_slot = 0
    frame_dirty = False

    gesture_active = False
    gesture_start_ms = 0.0
    gesture_broke = False
    max_count_seen = 0
    last_tap_ms = -1e9

    while True:
        buf = os.read(fd, EVENT_SIZE)
        if len(buf) < EVENT_SIZE:
            continue
        _, _, ev_type, ev_code, ev_value = struct.unpack(EVENT_FMT, buf)

        if ev_type == EV_ABS:
            frame_dirty = True
            if ev_code == ABS_MT_SLOT:
                cur_slot = ev_value
            elif ev_code == ABS_MT_TRACKING_ID:
                if ev_value == -1:
                    slots.pop(cur_slot, None)
                else:
                    slots[cur_slot] = {"x0": None, "y0": None}
            elif ev_code in (ABS_MT_POSITION_X, ABS_MT_POSITION_Y):
                s = slots.get(cur_slot)
                if s is not None:
                    key0 = "x0" if ev_code == ABS_MT_POSITION_X else "y0"
                    if s[key0] is None:
                        s[key0] = ev_value
                    elif abs(ev_value - s[key0]) > max_movement:
                        gesture_broke = True
            continue

        if ev_type != EV_SYN or ev_code != SYN_REPORT or not frame_dirty:
            continue
        frame_dirty = False

        t = now_ms()
        if t - last_frame_heartbeat_ms > 5000:
            write_heartbeat(dev_name or dev_path)
            last_frame_heartbeat_ms = t
        count = len(slots)

        if not gesture_active:
            if count > 0:
                gesture_active = True
                gesture_start_ms = t
                gesture_broke = False
                max_count_seen = count
        else:
            if count > max_count_seen:
                max_count_seen = count
            if count > TOUCH_COUNT:
                gesture_broke = True

            if count == 0:
                held_ms = t - gesture_start_ms
                clean_tap = (not gesture_broke) and max_count_seen == TOUCH_COUNT and held_ms <= TAP_MAX_HOLD_MS
                gesture_active = False
                if clean_tap:
                    gap_ms = t - last_tap_ms
                    if gap_ms <= DOUBLE_TAP_WINDOW_MS:
                        print(f"[gesture] second clean tap ({gap_ms:.0f}ms gap) -- toggling keyboard", flush=True)
                        last_tap_ms = -1e9
                        toggle_keyboard()
                    else:
                        print(f"[gesture] clean tap (held {held_ms:.0f}ms) -- waiting for a second one", flush=True)
                        last_tap_ms = t
                else:
                    print(f"[gesture] tap discarded (peak fingers={max_count_seen}, moved_too_far={gesture_broke}, held={held_ms:.0f}ms)", flush=True)


if __name__ == "__main__":
    main()
