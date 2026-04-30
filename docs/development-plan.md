---
name: Mask1EX MK2 Voice Organizer — Development Plan
status: draft
last_updated: 2026-04-30
---

# Mask1EX MK2 Voice Organizer — Development Plan

A native macOS app, written in Swift / SwiftUI / CoreMIDI, that reproduces and improves on Kodamo's web-based Voice Organizer (`kodamo.org/mask1organizer`).

> Source of truth: [MASK1EX_ORGANIZER_HANDOFF.md](MASK1EX_ORGANIZER_HANDOFF.md). Anything here that conflicts with the handoff loses; anything missing from the handoff is flagged as an open question.

---

## 1. Goals & Non-goals

### Must have (parity with web app)
- Connect to a Mask1EX MK2 over USB MIDI (CoreMIDI, no third-party deps).
- Read **factory bank** (377 voices, read-only) into a left "temporary" pane.
- Read **user bank** (200 voices, read/write) into a right pane.
- Reorder voices in the user bank with drag-and-drop or arrow keys.
- Multi-select (cmd-click / shift-click) and copy selection between panes.
- Import / export `.m1b` and `.syx` bank files.
- Export voice list as CSV.
- Send the modified user bank back to the device.

### Should have (improvements over web app)
- Live single-voice send-on-edit (audition while editing).
- Per-voice rename in place (writes the 9-byte ASCII name field).
- Undo / redo for any bank-level operation.
- Search / filter by name.
- Backup with timestamp on every device write.
- Diff view: which slots changed since last device read.

### Nice to have (later)
- Decoded parameter editor (full UI for the 65 voice parameters).
- A/B compare two voices side-by-side.
- Tagging / categories (synthetic metadata stored in a sidecar `.json`).

### Non-goals
- Audio engine / playback. The hardware does that.
- Firmware update flow. Out of scope; Kodamo's tool handles it.
- Cross-platform. macOS 14+ only (bumped from 13 during Phase 1 — `@Observable` macro requires Sonoma).

---

## 2. Architecture at a glance

See [architecture.md](architecture.md) for module-level decisions and method signatures.

```
┌──────────────── SwiftUI views ─────────────────┐
│ ContentView  ←→  BankListView  ←→  Toolbar     │
└────────────────────┬───────────────────────────┘
                     │ @Observable view models
┌────────────────────▼───────────────────────────┐
│ BankController  (orchestrates reads / writes)  │
└──┬───────────────┬──────────────┬──────────────┘
   │               │              │
   ▼               ▼              ▼
MIDIManager    MaskProtocol    FileIO
(CoreMIDI)    (SysEx codec)   (.m1b / .syx)
                                     │
                                     ▼
                                 Voice / VoiceBank model
```

Key principles:
- **Protocol layer is pure** — no CoreMIDI, no I/O. Just bytes in / bytes out. Easy to unit test.
- **MIDIManager owns the CoreMIDI client** and exposes async streams.
- **BankController is the single writer** of the voice banks — views observe, never mutate raw bytes.
- **Voice is value-typed** (struct) so undo is just snapshot diffing.

---

## 3. Phased delivery

Phases are sized so each ends in something demoable. Estimates assume one engineer, full-time-ish.

### Phase 0 — Project scaffolding (½ day)
- Create Xcode project `MaskOrganizer` (SwiftUI App, macOS 13+).
- Set up folder structure per the handoff ([architecture.md](architecture.md) §2).
- Add `Package.swift` if we later need SwiftPM tests separable from the app.
- Add SwiftLint config (loose — only the obviously-broken rules).
- Wire CI later; not a blocker for solo dev.
- **Exit:** app builds, opens an empty window.

### Phase 1 — Pure protocol codec (1–2 days)
No CoreMIDI yet. Just the `MaskProtocol` and `Voice` types, with thorough tests.

- `MaskProtocol.encodeVoiceRequest(index: Int) -> [UInt8]` (the `F0 00 00 02 LSB MSB F7` form).
- `MaskProtocol.decodeVoiceResponse(_ bytes: [UInt8]) -> VoicePayload` — validates the 134-byte frame, strips F0/F7, returns the 130-byte payload.
- `Voice.parameters` — nibble-pair-decode the 130 bytes into 65 parameter values.
- `Voice.name` — extract ASCII name from the appropriate slice (see §6 open questions).
- Round-trip tests against the captured `factory-dump.mmon` data (parse the plist in Swift or pre-extract to fixture `.bin` files).
- `.m1b` import: `FileIO.readM1B(_ url: URL) -> [Voice]`.
- `.m1b` export: `FileIO.writeM1B(_ voices: [Voice], to url: URL)`.
- Round-trip test: load `Avi_Fine_Mask1_bank_Interactive.m1b`, re-encode, byte-compare.
- **Exit:** `swift test` green; we can load the sample bank from disk and inspect names in a unit test.

### Phase 2 — CoreMIDI plumbing (1–2 days)
- `MIDIManager` with discovery: enumerate sources/destinations, find ones named `Mask1EX MK2`.
- Subscribe to source; reassemble incoming SysEx (CoreMIDI delivers it in `MIDIPacket`s, possibly chunked).
- Send SysEx via `MIDISend` with a packet list large enough for 134 bytes.
- A debug pane: show raw hex of every in/out message. Keep behind a `#DEBUG` flag.
- Reconnection on device hot-plug (`MIDIClientCreateWithBlock` notification block).
- **Exit:** clicking "Connect" finds the device and we can request voice 0 and log its 130 bytes.

### Phase 3 — Bank read flows (2 days)
- `BankController.loadFactoryBank()` — issues 377 sequential requests with a small inter-request delay (start with 20 ms; tune by measuring how the web app paces). Show progress.
- `BankController.loadUserBank()` — same, but for the user index range. **Verify range first** (see §6).
- Robust timeout / retry per voice. If a voice never responds, mark it as "missing" rather than blocking the whole load.
- Cancel button.
- **Exit:** both panes populate from the device; CSV export works.

### Phase 4 — UI parity (2–3 days)
- Two-pane SwiftUI layout (`HSplitView`).
- `BankListView`: row per voice with `name`, `index`, optional category badge.
- Selection model: single, range (shift), discontiguous (cmd).
- Keyboard: ↑/↓ to move selection, ⌥↑/⌥↓ to reorder, ⌘C / ⌘V between panes.
- Drag-and-drop inside the user bank for reorder.
- Copy-to-pane button.
- File menu: Open .m1b / .syx, Save As, Export CSV.
- **Exit:** can rearrange a user bank, save it as `.m1b`, reopen it, all without touching hardware.

### Phase 5 — Bank write flow (1–2 days, partly blocked)
- **First, sniff the web app writing back** to capture the real "Send to MASK1" SysEx (handoff §"Still Unknown" #1).
- Implement `BankController.sendUserBank()` once the write opcode is confirmed.
- Auto-backup the current user bank to `~/Library/Application Support/MaskOrganizer/backups/` before any write.
- Confirmation dialog with byte count and slot count.
- **Exit:** can read user bank, reorder, write back, power-cycle device, verify the new order persists.

### Phase 6 — Polish & improvements (ongoing)
- Undo / redo (NSUndoManager-backed).
- In-place rename with 8-char ASCII validation.
- Search field that filters by name.
- Diff highlighting (per-slot "changed since last read" badge).
- Live single-voice audition: when a voice is selected with hardware connected, send a "current voice reload" SysEx (format unknown — handoff §"Still Unknown" #6).

### Phase 7 — Voice parameter editor (separate, larger track)
- Cross-reference manual pp.39–42 CC list with nibble-pair positions, fully label all 65 slots.
- Build a `VoiceParameterMap` table (CC# ↔ pair index ↔ display name ↔ value range).
- `VoiceDetailView` with grouped controls (Osc1, Osc2, Noise, Env, Filter, LFO1/2, FX, Arp, Pitch, Global).
- Live edit → re-encode → send single-voice SysEx → audition.
- Could be a multi-week effort on its own; deliberately deferred.

---

## 4. Testing strategy

| Layer | Approach |
|---|---|
| Protocol codec | Unit tests with fixture bytes from `factory-dump.mmon` and `Avi_Fine_Mask1_bank_Interactive.m1b`. |
| FileIO | Round-trip: load → save → load again, byte-equal. |
| MIDIManager | Manual / smoke test against the device. CoreMIDI is awkward to mock; not worth it. |
| BankController | Use a `MIDITransport` protocol so tests inject a fake transport that records sent bytes and replays canned responses. |
| UI | Snapshot tests for `BankListView` with a mock bank. Reorder logic gets unit-tested in the view model, not the view. |

Test data lives in `Tests/Fixtures/`:
- `factory-voice-0.bin` (130 bytes, extracted from the dump)
- `factory-voice-376.bin`
- `avi-bank.m1b`

Pre-extract these from the existing capture in Phase 1 with a small Swift command-line target so we don't ship the `.mmon` plist parser in the app.

---

## 5. Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Write opcode is wrong | Med | High (corrupts user bank) | Don't ship write until sniffed and confirmed. Back up before every write. |
| Header alignment is off by one byte (handoff flags this in the `.m1b` ↔ SysEx conversion) | Med | High (silently scrambles parameters) | Round-trip test: read a known voice via SysEx, save as `.m1b`, reload, send back, dump again, compare. |
| Voice name location ambiguous (handoff §3) | High | Med | Keep name extraction behind a single function with fallback to "Voice N" if decoded name is non-ASCII. |
| Device drops a voice during bulk read | Med | Low | Per-voice timeout + retry; mark unrecoverable slots, never block the whole bank. |
| User-bank index range unknown (handoff §"Still Unknown" #2) | Med | Med | Probe by requesting indices 377+ until F7 with empty payload (or a NAK) appears; record the working range. |
| CoreMIDI SysEx fragmentation | Low | Med | Reassemble across packets in `MIDIManager` until `0xF7`; never assume single-packet delivery. |
| 38 kHz audio sample rate is unusual | n/a | n/a | Audio is out of scope; no risk. |

---

## 6. Open questions (must resolve before claiming "done")

These come straight from the handoff and our own reading. Each gets a checkbox; resolving one updates [log.md](log.md).

- [ ] **Write SysEx opcode** — assumed `03`, not confirmed. Action: capture `Send to MASK1` in MIDI Monitor.
- [ ] **User-bank index range** — needs probing.
- [ ] **Voice name byte location** — handoff says nibble pairs [0–8] = bytes [0–17] of the 130-byte payload, but also says pair 0 = `0x00` fixed and pair 1 = `0x87` packet marker. These can't both be true unless captured names happened to be empty. Verify against a `.m1b`-loaded voice with a known non-empty name.
- [ ] **`.m1b` ↔ SysEx byte alignment** — 64 bytes nibble-expanded = 128 bytes; 130-byte SysEx payload has 2 extra bytes. Where do those go? Handoff says "verify header alignment". Round-trip test required.
- [ ] **Trigger voice write SysEx** — needed to commit user bank to EEPROM (or is the per-voice write self-committing?). Manual p.35.
- [ ] **Partial voice transmit/receive** — could enable cheap live audition. Manual p.35.
- [ ] **Inter-request delay** — at what rate can we request voices without overruns? Start at 20 ms, time-trace the web app, tune.

---

## 7. Build & tooling

- Xcode 15+, Swift 5.9+.
- Deployment target: macOS 14 (Sonoma).
- Code-sign for local dev only (no notarization needed until distribution).
- App ID: `org.local.MaskOrganizer` (placeholder).
- No SPM dependencies in v1 — keep the surface tiny.
- App sandbox: enable, with `com.apple.security.device.audio-input` (covers MIDI on macOS) and `com.apple.security.files.user-selected.read-write`.

---

## 8. Out-of-scope reminders

- No firmware updates.
- No bank merging across factory + user (the device doesn't support it).
- No cloud sync.
- No automatic preset packs / store.

---

## 9. Definition of done (v1)

- Connects to a Mask1EX MK2.
- Reads both banks reliably (no missing voices over 5 successive reads).
- Reorders, copies, renames in the user bank.
- Imports and exports `.m1b` files round-trip-clean.
- Writes the user bank back; power-cycle confirms persistence.
- All open questions in §6 are resolved or explicitly punted with a written reason.
- README explains setup and known limits.
