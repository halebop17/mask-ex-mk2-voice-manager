#!/usr/bin/env python3
"""
One-shot fixture extractor.

Reads the MIDI Monitor `.mmon` capture and the `.m1b` sample bank from the
project, and writes plain `.bin` fixtures next to this script for use in
Swift unit tests. Re-run only if the source data changes.

MIDI Monitor's plist format strips the F0 / F7 framing bytes but keeps the
3-byte manufacturer ID (`00 00 02` etc.) in the stored payload. We re-add
F0/F7 so fixtures are full on-wire frames — that is what `MIDIManager` will
hand to the codec at runtime.

Outputs:
- factory-request-000.bin     (  7 bytes — full on-wire request)
- factory-response-000.bin    (132 bytes — full on-wire response)
- factory-response-last.bin   (132 bytes)
- user-write-slot-000.bin     (135 bytes — captured write, slot 0)
- user-write-slot-005.bin     (135 bytes — captured write, slot 5; was the moved voice)
- user-write-slot-199.bin     (135 bytes — captured write, last slot)
- user-bank-commit.bin        (  7 bytes — F0 00 00 05 7F 7F F7 trailer)
- user-read-request-384.bin   (  7 bytes — first user-bank read request)
- user-read-response-000.bin  (132 bytes — first user-bank read response)
- avi-bank.m1b                (copy of the sample bank — 271 voices)
"""
from __future__ import annotations
import plistlib
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
FIXTURES = Path(__file__).resolve().parent
MMON_FACTORY    = ROOT / "sysex-data" / "factory-dump.mmon"
MMON_USER_READ  = ROOT / "sysex-data" / "user-bank-read.mmon"
MMON_USER_WRITE = ROOT / "sysex-data" / "user-bank-write.mmon"
M1B = ROOT / "sound-bank" / "Avi Fine Mask1 bank Interactive.m1b"


def extract_messages(mmon_path: Path) -> tuple[list[bytes], list[bytes]]:
    with mmon_path.open("rb") as f:
        outer = plistlib.load(f)
    inner = plistlib.loads(bytes(outer["messageData"]))
    objects = inner["$objects"]

    to_msgs: list[bytes] = []
    from_msgs: list[bytes] = []
    i = 0
    while i < len(objects):
        obj = objects[i]
        if isinstance(obj, str) and obj in ("To Mask1EX MK2", "From Mask1EX MK2"):
            direction = obj
            for j in range(i + 1, min(i + 4, len(objects))):
                if isinstance(objects[j], bytes):
                    (to_msgs if direction == "To Mask1EX MK2" else from_msgs).append(objects[j])
                    break
        i += 1
    return to_msgs, from_msgs


def wrap(payload: bytes) -> bytes:
    return b"\xF0" + payload + b"\xF7"


def write_fixture(name: str, blob: bytes) -> None:
    (FIXTURES / name).write_bytes(blob)
    print(f"  wrote {name} ({len(blob)} bytes)  hex[0:16]={blob[:16].hex()}")


def main() -> None:
    # ── factory dump ────────────────────────────────────────────────
    print(f"reading {MMON_FACTORY}")
    to_, from_ = extract_messages(MMON_FACTORY)
    print(f"  to={len(to_)} from={len(from_)}")
    factory_requests  = [m for m in to_   if len(m) == 5   and m[2] == 0x02]
    factory_responses = [m for m in from_ if len(m) == 130]
    if factory_requests and factory_responses:
        write_fixture("factory-request-000.bin",   wrap(factory_requests[0]))
        write_fixture("factory-response-000.bin",  wrap(factory_responses[0]))
        write_fixture("factory-response-last.bin", wrap(factory_responses[-1]))

    # ── user-bank read ──────────────────────────────────────────────
    if MMON_USER_READ.exists():
        print(f"reading {MMON_USER_READ}")
        to_, from_ = extract_messages(MMON_USER_READ)
        print(f"  to={len(to_)} from={len(from_)}")
        # First read request: opcode 0x02 with index 384 → LSB=00 MSB=03
        first_req = next((m for m in to_ if len(m) == 5 and m[2] == 0x02 and m[3] == 0x00 and m[4] == 0x03), None)
        if first_req:
            write_fixture("user-read-request-384.bin", wrap(first_req))
        if from_:
            user_responses = [m for m in from_ if len(m) == 130]
            if user_responses:
                write_fixture("user-read-response-000.bin", wrap(user_responses[0]))

    # ── user-bank write ─────────────────────────────────────────────
    if MMON_USER_WRITE.exists():
        print(f"reading {MMON_USER_WRITE}")
        to_, _ = extract_messages(MMON_USER_WRITE)
        print(f"  to={len(to_)}")
        writes_by_slot = {}
        for m in to_:
            if len(m) == 133 and m[2] == 0x01:
                slot = m[3] | (m[4] << 7)
                writes_by_slot.setdefault(slot, m)
        for slot, label in [(0, "user-write-slot-000.bin"),
                            (5, "user-write-slot-005.bin"),
                            (199, "user-write-slot-199.bin")]:
            if slot in writes_by_slot:
                write_fixture(label, wrap(writes_by_slot[slot]))
        # Bank-commit trailer
        commit = next((m for m in to_ if len(m) == 5 and m[2] == 0x05), None)
        if commit:
            write_fixture("user-bank-commit.bin", wrap(commit))

    # ── .m1b sample bank ────────────────────────────────────────────
    if M1B.exists():
        dest = FIXTURES / "avi-bank.m1b"
        shutil.copy2(M1B, dest)
        print(f"  copied {M1B.name} → avi-bank.m1b ({dest.stat().st_size} bytes)")
    else:
        print(f"WARN: {M1B} not found; skipping .m1b fixture")


if __name__ == "__main__":
    main()
