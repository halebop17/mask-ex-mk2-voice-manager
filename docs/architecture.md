---
name: Mask1EX MK2 Voice Organizer — Architecture
status: draft
last_updated: 2026-04-30
---

# Architecture

Companion document to [development-plan.md](development-plan.md). Captures the architectural decisions and the public method signatures of each module so they don't drift across phases.

---

## 1. Decisions log

### 1.1 Native Swift / SwiftUI / CoreMIDI
- **Why:** the handoff specifies it; matches the user's stated goal. SwiftUI is enough for a two-pane list app.
- **Trade-off:** CoreMIDI is a C API with awkward callbacks. We isolate that ugliness in `MIDIManager` and expose async streams from there.

### 1.2 Pure protocol layer
- `MaskProtocol` knows nothing about CoreMIDI, files, or UI. It's a stateless byte transformer.
- **Why:** unit-testable without a device, and reusable if we ever want a CLI port.
- **Implication:** the protocol layer never throws on MIDI errors — it throws on malformed bytes. Transport errors live in `MIDIManager`.

### 1.3 `Voice` is a value type
- A `struct` with a `name`, a `rawPayload: [UInt8]` (the 130-byte SysEx payload), and a lazy `parameters: [UInt8]` (65-element decoded view).
- **Why:** undo / redo becomes free (snapshot the bank). No reference cycles. Trivially `Codable`.
- **Trade-off:** mutation copies the bank's array. A 200-voice bank is ~26 KB of payload — not a concern.

### 1.4 Single writer (`BankController`)
- Views observe two `@Observable` `VoiceBank` instances (factory, user). Only `BankController` mutates them.
- **Why:** keeps the "did the device respond? did the file load? did the user reorder?" logic in one place.

### 1.5 Transport seam
- `BankController` depends on a `MIDITransport` protocol, not on `MIDIManager` directly.
- **Why:** lets us inject a fake transport in tests that replays canned responses.

### 1.6 No write before sniffing
- The write-back code path is gated behind a feature flag (`.experimental.allowDeviceWrite`) that defaults off until the write opcode is confirmed against a real capture.
- **Why:** wrong opcode + correct-looking payload could brick a user bank. The handoff explicitly flags this.

### 1.7 Backup before every device write
- `BankController.sendUserBank()` first reads the current user bank, dumps it to `~/Library/Application Support/MaskOrganizer/backups/userbank-<ISO8601>.m1b`, then writes.
- **Why:** the device is the source of truth; if our bytes are wrong, the timestamped backup is the recovery path.

### 1.8 SysEx reassembly is the manager's job
- CoreMIDI delivers SysEx in `MIDIPacket`s that may split a single F0…F7 message. `MIDIManager` buffers until it sees `0xF7`, then emits a complete message.
- **Why:** the rest of the app should never see partial frames.

### 1.9 macOS 14+
- `@Observable` macro requires macOS 14 (originally planned 13; bumped during Phase 1). Sonoma is widely deployed by 2026 — fine for a hobby app.

### 1.10 Defer the voice parameter editor
- Phase 7 in the plan. The 65-parameter map needs cross-referencing the manual's CC table; it's a separate research task and not blocking bank organization.

---

## 2. Module layout

```
MaskOrganizer/
├── App/
│   └── MaskOrganizerApp.swift           # @main, scene wiring
├── MIDI/
│   ├── MIDIManager.swift                # CoreMIDI client, discovery, SysEx I/O
│   ├── MIDITransport.swift              # protocol seam used by BankController
│   └── MaskProtocol.swift               # pure SysEx encode/decode
├── Model/
│   ├── Voice.swift                      # value-typed voice
│   ├── VoiceBank.swift                  # @Observable container
│   └── BankController.swift             # orchestrates load/save/send
├── Views/
│   ├── ContentView.swift                # split-view root
│   ├── BankListView.swift               # one pane (factory or user)
│   ├── VoiceRow.swift                   # row UI
│   ├── DeviceToolbar.swift              # connect / read / send
│   └── VoiceDetailView.swift            # placeholder until Phase 7
├── Utilities/
│   ├── FileIO.swift                     # .m1b and .syx readers/writers
│   └── HexLog.swift                     # debug pane formatter
└── Resources/
    └── Assets.xcassets
Tests/
├── ProtocolTests.swift
├── FileIOTests.swift
├── BankControllerTests.swift
└── Fixtures/
    ├── factory-voice-0.bin
    ├── factory-voice-376.bin
    └── avi-bank.m1b
```

---

## 3. Public method signatures by module

These are the contracts. Implementations may add private helpers; these signatures are what other modules depend on.

### 3.1 `MaskProtocol.swift`

```swift
enum MaskProtocol {
    /// Build the 7-byte SysEx that asks the device for voice `index`.
    /// Encodes index as 2× 7-bit (LSB then MSB).
    static func encodeVoiceRequest(index: Int) -> [UInt8]

    /// Validate a 134-byte response frame and return the inner 130-byte payload.
    /// Throws if framing, length, or fixed-header bytes are wrong.
    static func decodeVoiceResponse(_ frame: [UInt8]) throws -> [UInt8]

    /// Build a "send voice" SysEx (opcode `0x03`, unconfirmed).
    /// Gated behind a feature flag at the call site until verified.
    static func encodeVoiceWrite(index: Int, payload: [UInt8]) throws -> [UInt8]

    /// Nibble-pair-decode 130 bytes → 65 8-bit parameters.
    static func decodeParameters(_ payload: [UInt8]) -> [UInt8]

    /// Inverse of decodeParameters: 65 bytes → 130 nibbles.
    static func encodeParameters(_ params: [UInt8]) -> [UInt8]

    enum Error: Swift.Error {
        case badFraming, wrongLength(Int), badHeader, badPayload
    }
}
```

### 3.2 `Voice.swift`

```swift
struct Voice: Equatable, Hashable, Codable, Identifiable {
    /// Stable identity within a bank. Not the device index.
    let id: UUID
    /// Slot index on the device (0…N). May change when reordered.
    var index: Int
    /// 8-character ASCII name, trimmed.
    var name: String
    /// Full 130-byte SysEx payload (nibble-encoded).
    var rawPayload: [UInt8]

    /// Lazily decoded 65-parameter view.
    var parameters: [UInt8] { get }

    /// Build from a 130-byte SysEx payload.
    init(index: Int, payload: [UInt8])

    /// Build from a 64-byte .m1b record.
    init(index: Int, m1bRecord: [UInt8]) throws

    /// Serialize to a 64-byte .m1b record.
    func m1bRecord() -> [UInt8]
}
```

### 3.3 `VoiceBank.swift`

```swift
@Observable
final class VoiceBank {
    enum Kind { case factory, user }
    let kind: Kind
    private(set) var voices: [Voice]

    init(kind: Kind, voices: [Voice] = [])

    /// Replace the entire bank atomically (used after a fresh device read).
    func replaceAll(_ voices: [Voice])

    /// Reorder by moving `indices` to before `destination`.
    func move(_ indices: IndexSet, to destination: Int)

    /// Insert (or overwrite) a voice at a slot.
    func upsert(_ voice: Voice, at slot: Int)

    /// Remove voices at the given slots (user bank only — factory throws).
    func remove(at slots: IndexSet) throws
}
```

### 3.4 `MIDITransport.swift`

```swift
protocol MIDITransport: AnyObject {
    var isConnected: Bool { get }
    var connectionState: AsyncStream<ConnectionState> { get }
    var incomingSysEx: AsyncStream<[UInt8]> { get }

    func connect() async throws
    func disconnect()
    func sendSysEx(_ bytes: [UInt8]) async throws

    enum ConnectionState { case disconnected, searching, connected, error(String) }
}
```

### 3.5 `MIDIManager.swift`

```swift
final class MIDIManager: MIDITransport {
    static let deviceName = "Mask1EX MK2"

    init() throws  // creates the CoreMIDI client and ports

    // MIDITransport conformance
    var isConnected: Bool { get }
    var connectionState: AsyncStream<MIDITransport.ConnectionState> { get }
    var incomingSysEx: AsyncStream<[UInt8]> { get }
    func connect() async throws
    func disconnect()
    func sendSysEx(_ bytes: [UInt8]) async throws

    // Internals (not part of the protocol surface):
    // - reassembleBuffer: [UInt8]
    // - midiReadProc: assembles packets until 0xF7, then emits
    // - notifyProc: handles device hot-plug
}
```

### 3.6 `BankController.swift`

```swift
@Observable
final class BankController {
    let factory: VoiceBank
    let user: VoiceBank
    private(set) var status: Status

    init(transport: MIDITransport)

    func loadFactoryBank(progress: ((Double) -> Void)?) async throws
    func loadUserBank(progress: ((Double) -> Void)?) async throws
    func sendUserBank(progress: ((Double) -> Void)?) async throws  // gated by feature flag

    func importM1B(from url: URL, into bank: VoiceBank.Kind) throws
    func exportM1B(from bank: VoiceBank.Kind, to url: URL) throws
    func exportCSV(from bank: VoiceBank.Kind, to url: URL) throws

    enum Status: Equatable {
        case idle
        case reading(slot: Int, total: Int)
        case writing(slot: Int, total: Int)
        case error(String)
    }
}
```

### 3.7 `FileIO.swift`

```swift
enum FileIO {
    /// Read a .m1b file as a sequence of 64-byte records → Voices.
    /// Throws if file size isn't a multiple of 64.
    static func readM1B(_ url: URL) throws -> [Voice]

    /// Write voices as a .m1b file (no header, packed records).
    static func writeM1B(_ voices: [Voice], to url: URL) throws

    /// Read a .syx file (one or more SysEx frames) → Voices.
    static func readSyx(_ url: URL) throws -> [Voice]

    /// Write voices as a .syx file (one frame per voice).
    static func writeSyx(_ voices: [Voice], to url: URL) throws

    /// Write a CSV listing of voice indices, names, and category badges.
    static func writeCSV(_ voices: [Voice], to url: URL) throws
}
```

### 3.8 `MaskOrganizerApp.swift` and views

```swift
@main
struct MaskOrganizerApp: App {
    @State private var transport = try! MIDIManager()
    @State private var controller: BankController

    var body: some Scene {
        WindowGroup { ContentView(controller: controller) }
            .commands { /* File menu: Open, Save, Export */ }
    }
}

struct ContentView: View {
    let controller: BankController
    var body: some View { /* HSplitView of two BankListViews + DeviceToolbar */ }
}

struct BankListView: View {
    let bank: VoiceBank
    @Binding var selection: Set<Voice.ID>
    var body: some View { /* List with VoiceRow, drag/drop, key handlers */ }
}
```

---

## 4. Data flow examples

### 4.1 Reading the factory bank
```
User clicks "Load factory" in DeviceToolbar
 → BankController.loadFactoryBank()
   → for index in 0..<377:
       → MaskProtocol.encodeVoiceRequest(index)
       → transport.sendSysEx(bytes)
       → await first frame from transport.incomingSysEx
       → MaskProtocol.decodeVoiceResponse(frame)
       → Voice(index:, payload:)
       → factory.upsert(voice, at: index)
   → status = .idle
View observes factory.voices and updates.
```

### 4.2 Saving a reordered user bank to disk
```
User drags voices around in BankListView
 → BankListView calls user.move(indices, to: destination)
File → Save As → URL
 → FileIO.writeM1B(user.voices, to: url)
   → for each Voice: voice.m1bRecord()  (64 bytes)
   → concatenate, write
```

### 4.3 Sending the user bank back
```
User clicks "Send to MASK1"
 → confirmation dialog
 → BankController.sendUserBank()
   → exportM1B(from: .user, to: backups/userbank-<timestamp>.m1b)
   → for slot in 0..<200:
       → MaskProtocol.encodeVoiceWrite(slot, user.voices[slot].rawPayload)
       → transport.sendSysEx(bytes)
       → await ack? (TBD — may be fire-and-forget)
       → small delay (TBD — start at 20 ms)
   → optionally: send "trigger voice write" SysEx (TBD)
```

---

## 4a. Protocol facts (post-hardware verification)

After running against a real Mask1EX MK2 and capturing live MIDI, the protocol is fully understood. These are no longer assumptions:

| Concern | Final answer |
|---|---|
| **Manufacturer ID** | `00 00` (3-byte form). MIDI Monitor mislabels it; ignore. |
| **Read request** | `F0 00 00 02 [LSB] [MSB] F7` (7 bytes). Index = `(MSB << 7) \| LSB`. |
| **Read response** | `F0 00 00 [128 nibble bytes] F7` (132 bytes total). Nibbles pack to 64 raw bytes. |
| **Write request** | `F0 00 00 01 [LSB] [MSB] [128 nibble bytes] F7` (135 bytes). Index is **user-bank-relative 0…199**, not device-absolute. |
| **Bank commit** | `F0 00 00 05 7F 7F F7` — sent after a bulk write to flush to EEPROM. Fire-and-forget; no ACK. |
| **Nibble order** | Low nibble first, high second. Decoding factory voice 0 produces `xDAWN…` only with this order. |
| **Voice record (64 bytes)** | byte [0] = category code (`x`/`y`/`z`/`{`/…); bytes [1..8] = 8-char ASCII name (null-padded); bytes [9..63] = 55 raw parameter bytes. Same layout in `.m1b` files and SysEx. |
| **Factory bank** | Device indices 0…376 (377 voices), read-only. |
| **User bank** | Device indices 384…583 for **reads**, slots 0…199 for **writes**. Slots 377…383 are reserved/unused. The web app probes index 584 with no response — sentinel; we skip it. |
| **Device ACKs** | Reads return one 132-byte response per request. Writes are silent (no ACK). |
| **CoreMIDI quirk** | `MIDIInputPortCreateWithProtocol` with MIDI 1.0 protocol delivers SysEx-7 UMPs that **strip F0/F7** from the data bytes — the framing is implicit in the status nibble (start/end). The receiver must re-add F0/F7 to produce on-wire frames. |

## 5. Threading model

- CoreMIDI callbacks run on the MIDI client thread → we hop straight onto an `AsyncStream`'s continuation, so consumers see them on whatever queue they await from.
- `BankController` and `VoiceBank` are **not** `@MainActor` (revised in Phase 3 — the original plan had them on MainActor but it caused dropped responses under back-to-back requests). The inbound SysEx pump now dispatches synchronously through an `NSLock`-protected pending-response slot.
- The pending-response slot is keyed by a monotonically-increasing **request sequence number**. A timeout armed for request N only fires if the slot still belongs to N — prevents stale timeouts from poisoning newer requests.
- SwiftUI views still observe via `@Observable`; reads happen on the main thread by virtue of the View tree, no explicit isolation needed.
- File I/O: synchronous reads inside `Task` blocks; small enough that a detached queue isn't worth the complexity.

---

## 6. Error handling philosophy

- Protocol errors: throw, surface in UI as "Voice N: malformed response".
- Transport errors: throw, surface as a banner, leave the bank in its prior state.
- File errors: throw, surface as a sheet, no partial writes (write to a temp file then rename).
- We do NOT silently retry forever. Reads have a per-voice timeout (start at 500 ms) and a max of 2 retries; after that the slot is marked missing and the load continues.
