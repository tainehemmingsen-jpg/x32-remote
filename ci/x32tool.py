#!/usr/bin/env python3
"""Tiny OSC helper used by CI to seed and inspect the X32 emulator.

  x32tool.py seed  [host]   - load a realistic band setup into the emulator
  x32tool.py check [host]   - verify the app's self-test changes reached the desk
  x32tool.py get ADDRESS [host]
"""
import math
import socket
import struct
import sys
import time

PORT = 10023


def pad(b):
    return b + b"\0" * (4 - len(b) % 4)


def osc_string(s):
    return pad(s.encode("utf-8"))


def encode(address, *args):
    tags = ","
    data = b""
    for a in args:
        if isinstance(a, bool):
            a = int(a)
        if isinstance(a, int):
            tags += "i"
            data += struct.pack(">i", a)
        elif isinstance(a, float):
            tags += "f"
            data += struct.pack(">f", a)
        else:
            tags += "s"
            data += osc_string(str(a))
    return osc_string(address) + osc_string(tags) + data


def read_string(buf, off):
    end = buf.index(b"\0", off)
    s = buf[off:end].decode("utf-8", "replace")
    return s, (end + 4) & ~3


def decode(buf):
    address, off = read_string(buf, 0)
    if off >= len(buf):
        return address, []
    tags, off = read_string(buf, off)
    args = []
    for t in tags[1:]:
        if t == "i":
            args.append(struct.unpack(">i", buf[off:off + 4])[0])
            off += 4
        elif t == "f":
            args.append(struct.unpack(">f", buf[off:off + 4])[0])
            off += 4
        elif t == "s":
            s, off = read_string(buf, off)
            args.append(s)
        elif t == "b":
            n = struct.unpack(">i", buf[off:off + 4])[0]
            off += 4
            args.append(buf[off:off + n])
            off += (n + 3) & ~3
    return address, args


def db_to_fader(db):
    if db <= -90:
        return 0.0
    if db < -60:
        f = (db + 90) / 480
    elif db < -30:
        f = (db + 70) / 160
    elif db < -10:
        f = (db + 50) / 80
    else:
        f = (db + 30) / 40
    return max(0.0, min(1.0, f))


def q(f, steps):
    return round(f * steps) / steps


class Desk:
    def __init__(self, host):
        self.host = host
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.settimeout(0.5)

    def send(self, address, *args):
        self.sock.sendto(encode(address, *args), (self.host, PORT))
        time.sleep(0.002)

    def get(self, address):
        for _ in range(4):
            self.sock.sendto(encode(address), (self.host, PORT))
            deadline = time.time() + 0.5
            while time.time() < deadline:
                try:
                    data, _ = self.sock.recvfrom(4096)
                except socket.timeout:
                    break
                a, args = decode(data)
                if a == address:
                    return args[0] if args else None
        return None


def seed(desk):
    names = ["Kick", "Snare", "Hat", "Tom 1", "Tom 2", "OH L", "OH R", "Bass",
             "Gtr L", "Gtr R", "Keys L", "Keys R", "Lead Vox", "BV 1", "BV 2", "MC"]
    colors = [1, 1, 1, 1, 1, 1, 1, 4, 2, 2, 3, 3, 5, 5, 5, 7]
    for i, (n, c) in enumerate(zip(names, colors), start=1):
        desk.send("/ch/%02d/config/name" % i, n)
        desk.send("/ch/%02d/config/color" % i, c)
        desk.send("/ch/%02d/mix/fader" % i, q(db_to_fader(-5 - (i % 5)), 1023))
        desk.send("/ch/%02d/mix/on" % i, 1)
        desk.send("/ch/%02d/mix/pan" % i, 0.5)
        desk.send("/ch/%02d/mix/st" % i, 1)
        desk.send("/-ha/%02d/index" % (i - 1), i - 1)
        desk.send("/headamp/%03d/gain" % (i - 1), 0.45)
    for i in range(17, 33):
        desk.send("/ch/%02d/mix/on" % i, 1)
        desk.send("/ch/%02d/mix/pan" % i, 0.5)
    for b, n in enumerate(["Vox Wedge", "Gtr Wedge", "Drum Fill", "Keys IEM", "Side Fill", "Bass Wedge"], start=1):
        desk.send("/bus/%02d/config/name" % b, n)
        desk.send("/bus/%02d/config/color" % b, 3 + (b % 4))
        desk.send("/bus/%02d/mix/fader" % b, 0.75)
        desk.send("/bus/%02d/mix/on" % b, 1)
    for d, n in enumerate(["Drums", "Bass", "Guitars", "Keys", "Vocals", "FX", "MC", "Spare"], start=1):
        desk.send("/dca/%d/config/name" % d, n)
        desk.send("/dca/%d/fader" % d, 0.75)
        desk.send("/dca/%d/on" % d, 1)
    desk.send("/main/st/mix/fader", 0.75)
    desk.send("/main/st/mix/on", 1)
    desk.send("/main/st/config/name", "PA")
    desk.send("/-show/showfile/scene/000/name", "Soundcheck")
    desk.send("/-show/showfile/scene/000/hasdata", 1)
    desk.send("/-show/showfile/scene/001/name", "Show")
    desk.send("/-show/showfile/scene/001/hasdata", 1)
    print("seeded")


def check(desk):
    expected = [
        ("/ch/01/mix/fader", q(0.75, 1023)),
        ("/ch/02/mix/on", 0),
        ("/ch/03/config/name", "SelfTest"),
        ("/ch/04/mix/05/level", q(db_to_fader(-6), 160)),
        ("/ch/05/config/color", 4),
        ("/ch/06/eq/2/g", q((6 + 15) / 30, 120)),
        ("/config/mute/3", 1),
    ]
    failures = 0
    for address, want in expected:
        got = desk.get(address)
        ok = got is not None and (abs(got - want) < 0.002 if isinstance(want, float) else got == want)
        print("%-24s want %-12r got %-12r %s" % (address, want, got, "OK" if ok else "FAIL"))
        if not ok:
            failures += 1
    if failures:
        print("%d check(s) failed" % failures)
        sys.exit(1)
    print("all self-test changes reached the desk")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    cmd = sys.argv[1]
    if cmd == "get":
        host = sys.argv[3] if len(sys.argv) > 3 else "127.0.0.1"
        print(Desk(host).get(sys.argv[2]))
        return
    host = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
    desk = Desk(host)
    if cmd == "seed":
        seed(desk)
    elif cmd == "check":
        check(desk)
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main()
