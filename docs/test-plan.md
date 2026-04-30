---
name: MIDI Monitor capture plan
description: Step-by-step instructions for capturing the missing pieces of the SysEx protocol so we can finish the writer and confirm the user-bank index range.
last_updated: 2026-04-30
---

# MIDI Monitor Capture Plan

We need three captures from the Kodamo web Voice Organizer to unblock Phase 5 (writing the user bank back) and resolve the remaining open questions in [development-plan.md](development-plan.md) §6. Each capture is short, takes < 5 minutes, and produces a `.mmon` file that the Swift project will then parse and turn into test fixtures.

## Before you start

1. Connect the Mask1EX MK2 over USB-C and verify macOS sees it (Audio MIDI Setup → MIDI Studio → "Mask1EX MK2" should be listed).
2. Open **MIDI Monitor** ([snoize.com/MIDIMonitor](https://snoize.com/MIDIMonitor/), free).
   - Sources panel: tick **Mask1EX MK2** (so we capture device → host).
   - Spy on output destinations: tick **Mask1EX MK2** there too (host → device).
   - Filter: enable only **System Exclusive** to keep the log clean. Disable Note On/Off, Clock, Active Sensing.
3. Open the Kodamo web Voice Organizer at <https://kodamo.org/mask1organizer> in Chrome / Safari and grant Web MIDI permission for the Mask1EX MK2.
4. (Recommended) Have ≥ 1 user voice slot **populated** with a recognisable preset. If your user bank is empty, copy a factory voice into slot 0 of the user bank from the device front panel first — otherwise the user-bank capture will look identical to a load of an empty bank.
5. Create a folder `sysex-data/` in the project root (it already exists). Each capture below saves there.

---

## Capture 1 — User bank read (resolves: user-bank index range)

**Goal:** confirm the device-side index range used by the web app when it requests the 200 user voices.

1. In MIDI Monitor: **File → New Document** (clears the log).
2. In the web app: click **"Load user bank from MASK1"** (right pane, green button labeled in the screenshot).
3. Wait for the right pane to fully populate (≈ 5–10 seconds for 200 voices).
4. In MIDI Monitor: **File → Save As…** → `sysex-data/user-bank-read.mmon`.

**What we expect:** ~200 outgoing requests of the form `F0 00 00 02 LSB MSB F7`, each followed by an inbound 132-byte voice response. We're looking for the **first** and **last** LSB/MSB pair in the outgoing stream.

**What I'll do with it:** decode the `.mmon`, extract the request indices, and replace the placeholder `377..<577` range in [BankController.swift](../MaskOrganizer/Sources/MaskCore/Transport/BankController.swift#L83-L86) with the real range.

---

## Capture 2 — Bank write (resolves: write opcode + trigger-write SysEx)

**Goal:** capture exactly what bytes go on the wire when the web app writes the user bank back to the device. This is the highest-risk gap because the wrong opcode could corrupt the user bank.

⚠️ **Safety:** before clicking Send, make sure the **on-device user bank is backed up** (the web app's "Download bank to computer" gives you an `.m1b`). If the write goes wrong, that file restores you.

1. **Load the user bank into the web app first.** Click *"Load user bank from MASK1"* in the right (green) pane. Wait for all 200 slots to populate — without this, the right pane is empty and there's nothing for "Send" to send. (You'll *also* be making Capture 1 by accident here; either redo Capture 1 separately first, or save this stage as `user-bank-read.mmon` and clear the log before continuing.)
2. In MIDI Monitor: **File → New Document** to clear the log so the upcoming write isn't tangled with the read.
3. **In the right pane (user bank), make a small recognisable change** so the captured write has a delta we can verify against the bytes:
   - **Easiest:** click on the voice in slot 1 (the first one), then press the `↓` arrow key a few times to move it down to slot 5 or 6. The web app supports up/down arrow reorder.
   - **Alternative:** drag-and-drop slot 1 onto slot 5.
   - **Alternative:** click a voice in the **left (temporary) pane**, then click *"Copy selection >"*. This inserts that voice into the user bank — slightly larger delta but also fine.
   - Don't change anything in the left pane; the temporary/factory side isn't written.
4. **Click "Send to MASK1"** at the bottom of the right pane.
5. Wait for the device's "writing" indicator (or for the web app to settle — typically 5–15 seconds).
6. In MIDI Monitor: **File → Save As…** → `sysex-data/user-bank-write.mmon`.

**What we expect to see** (each is informative, capture all of them):
- A series of outgoing 135-byte SysEx frames per voice — should look like `F0 00 00 [opcode] LSB MSB [128 nibble bytes] F7`. The `[opcode]` is the unknown we want; we currently *assume* `0x03`.
- Possibly a trailing "trigger write to EEPROM" SysEx after the last voice (manual p.35 mentions this exists, format unknown).
- Possibly inbound `F0 00 00 [ack-opcode] F7` ACK frames after each write — useful to know about so the controller can wait for them rather than fire-and-forget.

**What I'll do with it:**
1. Confirm or correct `MaskProtocol.encodeVoiceWrite` ([here](../MaskOrganizer/Sources/MaskCore/Protocol/MaskProtocol.swift)).
2. Add (if needed) a `MaskProtocol.encodeTriggerWrite()` for the EEPROM commit.
3. Add ACK handling in `BankController.sendUserBank` if the device sends them.
4. Flip `controller.allowDeviceWrites = true` as a safe default.

---

## Capture 3 — Single-voice send / current voice reload (optional, helps Phase 6)

**Goal:** discover the SysEx for "send a single voice for live audition" — used for the future feature where the app sends the currently-edited voice to the device for instant preview.

1. In MIDI Monitor: **File → New Document**.
2. In the web app: click on a voice slot → make a small parameter edit if the web app exposes it, or use the per-voice "send" affordance. (If the web app doesn't have this, skip — we'll figure this out from the manual instead.)
3. Save → `sysex-data/single-voice-send.mmon`.

**What we expect:** a single 135-byte SysEx going out (matching the per-voice write from Capture 2), or possibly a different "current voice reload" opcode (manual p.35).

This capture is nice-to-have, not blocking.

---

## After capturing

Drop the three `.mmon` files into `sysex-data/`, then ping me with what filenames you saved. I'll:

1. Extend `Tests/MaskCoreTests/Fixtures/extract_fixtures.py` to parse them into Swift test fixtures.
2. Write protocol-conformance tests that compare our `MaskProtocol.encodeVoiceWrite` output to the captured bytes.
3. Update [BankController.swift](../MaskOrganizer/Sources/MaskCore/Transport/BankController.swift) with the confirmed user-bank range.
4. Update [log.md](log.md) with the resolutions.

If a capture looks wrong (zero outgoing messages, wrong device, etc.), the most common causes are:
- **Web MIDI permission not granted** — the URL bar should show a MIDI icon; click it and allow.
- **Wrong source/destination ticked in MIDI Monitor** — if you don't see anything, double-check both Sources and "Spy on output to destinations" panels.
- **Browser tab in background** — Web MIDI sometimes throttles when the tab isn't focused. Keep the web app in the foreground throughout the capture.
