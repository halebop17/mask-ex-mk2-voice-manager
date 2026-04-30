---
name: Mask1EX MK2 Voice Organizer — Changelog
description: Detailed running log of all development activity. Append, never rewrite.
---

# Changelog

Newest entries on top. Each entry: date, brief summary, then bullet detail. Append to this file as work progresses; do not retroactively rewrite history.

---

## 2026-04-30 — End-to-end working: nibble order, UMP framing, UX polish

After getting the protocol right and the write path wired up, the device-driven flow had three more bugs we found by actually plugging in hardware. All resolved, full bank read in ~6 s, copy/reorder/send all working.

### Bug 1: Nibble order was reversed (low-first, not high-first)

The `.m1b` round-trip tests passed because they're symmetric, but the on-device factory voices decoded to gibberish like `0x87 0x44 0x14 0x75 0xE4 …` instead of ASCII names. Decoding factory voice 0 with low-nibble-first packing gave `xDAWN…` — category byte `x` + name `DAWN`, matching what the web app shows.

This **also** retroactively explained the supposed `0x87` "marker byte" we'd been treating as a separator: it was just `'x'` (0x78) read with bytes swapped. Factory and user voices share one layout: byte 0 = category (`x`/`y`/`z`/`{`/etc.), bytes 1–8 = ASCII name, bytes 9–63 = 55 parameter bytes. Same as `.m1b`.

Fix: swapped both nibble pack and expand to low-first. Capture-conformance tests stayed green because they're a symmetric round-trip.

### Bug 2: SysEx bulk read at 3 s/voice (CoreMIDI strips F0/F7 from UMP data)

Per the os.Logger output, the device WAS responding (5 packets per voice, 130 bytes assembled) but our reassembler refused to emit, looking for F0 at start and F7 at end of the buffer. CoreMIDI's MIDI 1.0 UMP delivery (`MT=0x3` SysEx-7) **strips F0/F7** from the data — the framing is implied by the status nibble (1=start, 3=end). So every response got dropped and we hit the 250 ms timeout 3× per voice.

Fix: re-prepend `F0` on `start`/`complete` UMPs and append `F7` on `end`/`complete` UMPs in `MIDIManager.parseSysExFromWords`. After fix, full factory bank loads in **~6 s** (was effectively never).

### Bug 3: Voice name layout was off by one (category byte ≠ name byte)

We had `parsedName` decoding bytes [0..8] (9 bytes) as the name, which surfaced strings like `xAF SIN I` and `{AFWTBLY` in the UI. The web tool shows `AF SIN I` and `AFWTBLY` — i.e., it skips byte 0 and shows bytes 1–8.

Decoded the byte-0 distribution across Avi Fine's bank: 237× `'x'`, 17× `'{'`, 9× `'z'`, 4× `'y'`, plus a few outliers. That's a **category code**, not a name byte. The web app probably renders it as a small badge.

Fix: `Voice.parsedName` now slices bytes [1..8]; `Voice.category` exposes byte [0] for future UI use.

### Other UX changes today
- **`@FocusState` per pane** wired to `paneFocus` so arrow keys, focus highlight, and click-selection all stay coherent.
- **Up/down arrows** move selection within the focused pane; **left/right arrows** switch focus between panes; **Enter** copies selection to the *other* pane (no focus steal — focus stays on the source).
- **Copy semantics rewritten** to be overwrite-then-cursor-advance: no destination selected → first copy goes to slot 0, subsequent copies fill consecutive slots (paste cursor advances). Explicit destination click resets the cursor.
- **`@FocusState`-aware load/send** buttons disabled when transport says `Disconnected`. Loading from device while disconnected was silently filling the bank with 377 blank `Voice NNN` placeholders.
- **`SendSysEx` is now fire-and-forget** — old code awaited the CoreMIDI completion callback, which serialized bulk reads against transmission ACKs.
- **Light mode forced** via `.preferredColorScheme(.light)` — hard-coded light grays clashed with system dark mode. Dark-mode polish deferred.
- **`.app` bundle script** (`build-app.sh`) wraps the SwiftPM-built binary with an Info.plist + ad-hoc codesign so it gets a Dock icon and proper window focus. Without it, the bare executable launched headless behind everything.
- **"Load Factory Bank"** button on the temporary pane was loading into the unused `factory` bank; now correctly populates `temporary` (matches web app behavior).
- **Capacity-aware copy**: user bank is fixed-size 200 — copies overwrite slots, not append.

### Test status
All 34 tests pass. Capture-conformance tests still verify our encoder output matches the web app's bytes byte-for-byte even after the nibble-order swap (symmetric round-trip).

### Open questions still outstanding
- **Trigger-voice-write SysEx** (manual p.35) — possibly the same as the bank-commit `0x05 7F 7F`, possibly a per-voice variant. Not blocking.
- **Partial-voice transmit/receive** (manual p.35) — for live-audition while editing. Phase 7 territory.

---

## 2026-04-30 — Protocol confirmed via captures; write path wired up

User produced two MIDI Monitor captures (`sysex-data/user-bank-read.mmon`, `sysex-data/user-bank-write.mmon`) of the web Voice Organizer. Decoded both and updated the Swift code accordingly. **All open protocol questions are now resolved.**

### Confirmed protocol facts
| Question | Answer | Source |
|---|---|---|
| Write opcode | **`0x01`** (the original guess `0x03` was wrong) | `user-bank-write.mmon`: 200 outgoing TO frames, all length 133, opcode byte `0x01` at offset [2] |
| User-bank read range | **device-absolute 384…583** (200 voices); web app also probes 584 with no response | `user-bank-read.mmon`: 200 read requests with LSB/MSB decoding to consecutive 384…583 |
| Write index encoding | **user-bank-relative 0…199** (NOT device-absolute) | Captured writes used LSB=slot&0x7F, MSB=slot>>7, slots 0…199 |
| Bank-commit trailer | **`F0 00 00 05 7F 7F F7`** must be sent after a bulk write — likely commits to EEPROM | A single length-5 TO message with opcode `0x05` and `7F 7F` at the tail of `user-bank-write.mmon` |
| Device ACKs writes? | **No** — fire-and-forget | `user-bank-write.mmon` has 0 inbound (FROM) frames |
| 130-byte payload format | **Manufacturer ID `00 00` + 128 nibble bytes** (so on-wire is 132 bytes; the original handoff phrasing of "130 bytes of voice data" was slightly misleading) | All FROM samples consistently start `00 00 08 07 …` |
| Voice-name location | **Not in the device protocol.** Factory and user voices both have `0x87` as the first raw byte. Names exist only in `.m1b` files (first 9 bytes of the 64-byte record). The web app must show user-bank slot names from a separate source we haven't identified — possibly slot numbers only. | First raw byte after nibble-pack of every captured response = `0x87`, not ASCII |

### Round-trip verified end-to-end
The user moved the voice at user-slot-1 down to slot-5 in the web app before clicking Send. We read the captured response[0] (the unique voice that was at slot 0), decoded into a `Voice`, and re-encoded as a write to slot 5 — the result is **byte-identical** to the captured write frame:

```swift
func testReadToWriteRoundTripMatchesCapture() throws {
    let readResponse = try Fixtures.userReadResponse0()
    let voice = try Voice.fromSysExResponse(readResponse, index: 0)
    let ourFrame = try MaskProtocol.encodeVoiceWrite(slot: 5, record: voice.record)
    let capturedWrite = try Fixtures.userWriteSlot5()
    XCTAssertEqual(ourFrame, capturedWrite)  // passes
}
```

### Code changes
- **MaskProtocol.swift**:
  - `encodeVoiceWrite` opcode `0x03` → `0x01`; parameter renamed `index:` → `slot:` to reflect that it's user-bank-relative.
  - `Opcode` enum gains `.bankCommit = 0x05`.
  - New `encodeBankCommit()` returns `F0 00 00 05 7F 7F F7`.
- **BankController.swift**:
  - `loadUserBank` range fixed: `377..<577` → `384..<584`.
  - `sendUserBank` rewritten: writes slots 0…199 (always all 200, padding with blank records if the in-memory bank is short), then sends `encodeBankCommit()`. Auto-backup before write still in place.
  - `allowDeviceWrites` now defaults to `true` (was `false` while the opcode was unconfirmed).
- **Fixtures + tests**:
  - `extract_fixtures.py` extended to mine the two new captures. New fixtures: `user-write-slot-{000,005,199}.bin`, `user-bank-commit.bin`, `user-read-request-384.bin`, `user-read-response-000.bin`.
  - New `CaptureConformanceTests.swift` — 4 tests asserting our codec output equals the captured frames byte-for-byte.

### Test status
- 33 tests, all passing (was 27).
- ~1.6s wall time.

### What remains genuinely unknown
- **Trigger-voice-write SysEx** (manual p.35) — possibly the same as the bank-commit `0x05 7F 7F`, or a per-voice variant. Not blocking.
- **Partial-voice transmit/receive SysEx** (manual p.35) — for live-audition while editing. Phase 6/7 territory.
- **Voice-name display in web app** — the web app shows user-bank slot names somewhere; not seen in protocol traffic. Likely just shows slot numbers, or pulls names from a local cache after import. Not blocking either.

### Status of the development plan
Phase 5 ("Bank write flow") is now functionally complete in code. Real-device verification still wanted: read user bank → reorder → write back → power-cycle the device → verify the new order persists. That's the next thing to test against actual hardware.

---

## 2026-04-30 — Phases 0–4 implemented (entire reading path)

Built the Swift package and shipped the first four phases of the development plan. The app builds (`swift build`) and all 27 unit tests pass (`swift test`).

### What was built
- **Swift Package** (`MaskOrganizer/Package.swift`) with two products:
  - Library `MaskCore` — Protocol, Voice/VoiceBank model, FileIO, MIDITransport (protocol), BankController.
  - Executable `MaskOrganizer` — SwiftUI app + CoreMIDI-backed `MIDIManager`.
- **Test fixtures**: extracted by `Tests/MaskCoreTests/Fixtures/extract_fixtures.py` from the existing `factory-dump.mmon` and `Avi Fine Mask1 bank Interactive.m1b`. Stored as plain `.bin`/`.m1b` files for fast Swift unit tests.
- **Phase 1 — codec** (`MaskCore/Protocol`, `MaskCore/Model`, `MaskCore/FileIO`):
  - `MaskProtocol.encodeVoiceRequest/decodeVoiceResponse/nibbleExpand/nibblePack` plus an unconfirmed `encodeVoiceWrite` (opcode `0x03`, gated by feature flag).
  - `Voice` value type — canonical 64-byte record, parsed name + override, m1b/SysEx serializers.
  - `VoiceBank` — observable, kind-aware (factory/user/temporary), reorder/remove/rename, capacity-aware.
  - `FileIO` — `.m1b`, `.syx`, `.csv` readers/writers with atomic-replace semantics.
- **Phase 2 — CoreMIDI** (`MaskOrganizer/MIDI/MIDIManager.swift`):
  - Discovers ports named `Mask1EX MK2`, handles hot-plug via `MIDIClientCreateWithBlock` notifications.
  - Reassembles inbound SysEx across MIDI 1.0 Universal MIDI Packets (UMP MT=0x3) — emits complete `F0…F7` frames on an `AsyncStream`.
  - Sends via `MIDISendSysex`, with a heap-allocated context box that survives the C completion callback.
- **Phase 3 — BankController** (`MaskCore/Transport/BankController.swift`):
  - Async bulk read with per-voice timeout, retries, and a `missingSlots` error for slots that never respond.
  - **Subtle bug encountered & fixed**: timeouts armed for request N were firing against request N+1's continuation under contention. Fix: stamp every request with a monotonically increasing sequence number and only resume the continuation on a timeout if the current sequence still matches.
  - Backup-before-write into `~/Library/Application Support/MaskOrganizer/backups/` (gated by `allowDeviceWrites = false`).
- **Phase 4 — SwiftUI** (`MaskOrganizer/Views/`):
  - Matches the [design mockup](../design-ui/mask%20ex2%20app/uploads/pasted-1777543934499-0.png): top status bar with connection pill, two panes (yellow / green tints) with per-pane action toolbars + search, copy divider in the middle, status bar with progress + cancel.
  - Multi-select (`⌘`-click), search filter, per-pane file import / export (`.m1b`, `.csv`).
  - "Send to MASK1" button is disabled until `controller.allowDeviceWrites` flips on (a deliberate safety gate until the write opcode is confirmed).

### Architectural changes vs. the original plan
- **macOS deployment target bumped from 13 → 14.** `@Observable` requires macOS 14. Plan and architecture docs were updated.
- **Protocol clarification (resolves an open question).** The handoff described the SysEx response as a "130-byte voice payload" with bytes `[0,1] = 00 00 (fixed header)` and bytes `[2,3] = 08 07 (fixed packet marker)`. After parsing the actual capture, we determined those bytes are the **manufacturer ID + first nibble pair** — MIDI Monitor stores the inner bytes after stripping `F0`/`F7` only, leaving the manufacturer prefix in the data. So:
  - On-wire request: `F0 00 00 02 LSB MSB F7` (7 bytes total) — confirmed.
  - On-wire response: `F0 00 00 [128 nibble bytes] F7` (132 bytes total). The 128 nibble bytes pack down to 64 raw bytes — exactly the `.m1b` record size. **The "1-byte alignment" risk in the original plan was a misread; the formats line up cleanly.**
- **`BankController` is not `@MainActor`.** The first attempt was main-actor-isolated, which forced the inbound SysEx pump to hop to MainActor for every response. Under back-to-back requests this queue backed up and ~10% of responses were dropped. Removed `@MainActor` from `BankController` and `VoiceBank`, replaced with an `NSLock`-protected pending-response slot. Tests went from 35-40 failures back to 0. SwiftUI views still run on MainActor by virtue of the View tree.

### What's still open
- [ ] **Write opcode** (assumed `0x03`) — `MaskProtocol.encodeVoiceWrite` is wired up but hidden behind `allowDeviceWrites` until verified by capturing the web app's "Send to MASK1" action. **This is what the next test session will resolve** (see `docs/test-plan.md`).
- [ ] **User-bank index range** — provisionally `377…576`. To verify by sniffing "Load user bank from MASK1" in the web app.
- [ ] **Trigger-voice-write SysEx / Partial-voice SysEx** — manual p.35; not blocking v1 reads.
- [ ] **Inter-request delay** — set to 20 ms by default; tunable via `controller.readDelayMs`. Time-trace the web app to see what it uses.

### File map (new)
```
MaskOrganizer/
├── Package.swift
├── Sources/
│   ├── MaskCore/
│   │   ├── Protocol/MaskProtocol.swift
│   │   ├── Model/Voice.swift
│   │   ├── Model/VoiceBank.swift
│   │   ├── FileIO/FileIO.swift
│   │   └── Transport/{MIDITransport,BankController}.swift
│   └── MaskOrganizer/
│       ├── App/MaskOrganizerApp.swift
│       ├── MIDI/MIDIManager.swift
│       └── Views/{Theme,StatusPill,DeviceToolbar,VoiceRow,BankListView,CopyDivider,StatusBar,ContentView}.swift
└── Tests/MaskCoreTests/
    ├── Fixtures/{extract_fixtures.py, factory-request-000.bin, factory-response-000.bin, factory-response-last.bin, avi-bank.m1b}
    ├── Fixtures.swift
    ├── MaskProtocolTests.swift  (10 tests)
    ├── VoiceTests.swift          (6 tests)
    ├── VoiceBankTests.swift      (4 tests)
    ├── FileIOTests.swift         (5 tests)
    └── BankControllerTests.swift (2 tests)
```

### Build & run
```bash
cd MaskOrganizer
swift test          # 27 tests, ~1.6s
swift build         # builds the executable
swift run MaskOrganizer   # launches the app (CoreMIDI may prompt for permission)
```

To iterate in Xcode: `File > Open` → pick `MaskOrganizer/Package.swift`.

---

## 2026-04-30 — Project handoff received & docs scaffolded

- Read [MASK1EX_ORGANIZER_HANDOFF.md](MASK1EX_ORGANIZER_HANDOFF.md) (the claude.ai handoff). It contains:
  - Decoded request SysEx (`F0 00 00 02 LSB MSB F7`).
  - 130-byte voice payload format (nibble-pair-encoded, 65 parameters).
  - Partial parameter map (still needs cross-referencing with the manual's CC table on pp.39–42).
  - `.m1b` file format (no header, 64 bytes per voice record, ASCII name in first 9 bytes).
  - List of unresolved questions (write opcode, user-bank index range, voice-name location, header alignment between `.m1b` and SysEx, trigger-write SysEx, partial-voice SysEx).
- Inventoried existing project files:
  - `docs/Kodamo MASK1 User Manual.pdf`
  - `docs/MASK1EX_ORGANIZER_HANDOFF.md`
  - `sound-bank/Avi Fine Mask1 bank Interactive.m1b` (17 344 bytes = 271 voices)
  - `sysex-data/factory-dump.mmon` (264 KB MIDI Monitor capture)
- Created [development-plan.md](development-plan.md):
  - 8 phases, from project scaffolding through bank-write to (deferred) parameter editor.
  - Risk register, open questions copied from the handoff plus our own ("`.m1b` ↔ SysEx 1-byte alignment discrepancy").
  - Test strategy: pure-protocol unit tests using fixtures pre-extracted from `factory-dump.mmon` and the sample `.m1b`.
  - Definition of done for v1.
- Created [architecture.md](architecture.md):
  - Decisions (pure protocol layer, value-typed `Voice`, single-writer `BankController`, `MIDITransport` seam for tests, no-write-before-sniffing, backup-before-write).
  - Module layout matching the handoff's suggested structure.
  - Public method signatures for `MaskProtocol`, `Voice`, `VoiceBank`, `MIDITransport`, `MIDIManager`, `BankController`, `FileIO`.
  - Data-flow walkthroughs for the three main operations (factory read, file save, device write).
  - Threading model and error-handling philosophy.
- Created this changelog ([log.md](log.md)).
- **No code yet.** Next step is Phase 0: create the Xcode project skeleton.

### Open questions still outstanding (mirrored from development-plan.md §6)
- [ ] Write SysEx opcode (assumed `0x03`, unconfirmed).
- [ ] User-bank index range.
- [ ] Voice name byte location vs. fixed-header bytes — possible inconsistency in the handoff.
- [ ] `.m1b` ↔ SysEx 1-byte header alignment.
- [ ] Trigger-voice-write SysEx format (manual p.35).
- [ ] Partial-voice transmit/receive SysEx format (manual p.35).
- [ ] Safe inter-request delay during bulk reads.
