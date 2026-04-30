# Mask EX Voice Manager

Native macOS voice organizer for the **Kodamo Mask1EX MK2** synthesizer. A Swift / SwiftUI / CoreMIDI replacement for the web tool at [kodamo.org/mask1organizer](https://kodamo.org/mask1organizer) — same workflow, native, keyboard-friendly.

![two-pane voice list, yellow temporary on the left, green user bank on the right]

## Requirements

- macOS 14 (Sonoma) or newer
- A Mask1EX MK2 connected over USB-C
- Xcode 15+ (only if you want to build / iterate)

## Install / run

Pre-built `.app` bundle:
```bash
cd MaskOrganizer
./build-app.sh           # debug build, fast (≈1 s)
./build-app.sh release   # optimized build
open MaskOrganizer.app
```

Or open `MaskOrganizer/Package.swift` in Xcode and hit Run.

The first launch may prompt for MIDI access. If macOS Stage Manager is on, the window may join a new stage — find it in the Stage Manager strip on the left.

## What it does

| Pane | Contents | Source |
|---|---|---|
| **Temporary** (left, yellow) | Working area / clipboard. Holds factory presets or imported voices. | "Load Factory Bank" reads all 377 device presets, "From file…" opens an `.m1b` or `.syx` file. |
| **User Bank** (right, green) | The 200 editable slots on the device. | "From device" reads the user bank, edits live in the app. "Send to MASK1" writes back. |

Core operations:

- **Connect** — finds and opens the `Mask1EX MK2` MIDI ports. Pill turns green when connected.
- **Load Factory Bank** — reads all 377 factory presets into the Temporary pane (~6 s).
- **From device** (User Bank) — reads the 200 user voices off the device.
- **From file…** — imports an `.m1b` or `.syx` file into the chosen pane.
- **Save bank…** — writes the User Bank to disk as `.m1b`.
- **CSV** — exports a slot/name listing.
- **Copy →  / ← Copy** — moves the selected voice(s) between panes.
- **⇒  / ⇐ (long arrow buttons)** — copies the entire pane to the other side.
- **Save selection…** (User Bank) — exports just the selected voices as a `.m1b`.
- **Send to MASK1** — writes the User Bank back to the device. Disabled until a user bank is loaded (avoids overwriting the device with empty voices). Auto-backs up the previous user bank to `~/Library/Application Support/MaskOrganizer/backups/` before writing.

## Keyboard

| Key | What it does |
|---|---|
| **↑ / ↓** | Move selection one row up / down in the focused pane |
| **⌥↑ / ⌥↓** | Reorder: shift the selected voice up / down within the focused pane |
| **→** | Switch focus to the User Bank (when in Temporary) |
| **←** | Switch focus to Temporary (when in User Bank) |
| **Enter** | Copy current selection to the *other* pane. Focus stays where it is. |
| **⌘-click** | Toggle a row's membership in the selection (multi-select) |
| **Click** | Select a single row |
| **⌘⇧↩** | Send User Bank to MASK1 |
| **Search field** | Filters the focused pane by name (per-pane search) |

Copy behavior, in detail:

- If you **don't** select a destination slot first, repeated Enter / `→` button presses fill consecutive destination slots starting at the current paste cursor (which begins at slot 0 and advances after every copy).
- If you **do** click a destination slot, that slot becomes the start point — the next copy overwrites it, and subsequent copies cascade down from there.
- Loading a bank from device or file resets the cursor.

## Project layout

```
MaskOrganizer/
├── Package.swift
├── build-app.sh                    # wraps SwiftPM binary into a clickable .app
├── Bundle/Info.plist
├── Sources/
│   ├── MaskCore/                   # pure Swift library, fully unit-tested
│   │   ├── Protocol/MaskProtocol.swift
│   │   ├── Model/{Voice,VoiceBank}.swift
│   │   ├── FileIO/FileIO.swift
│   │   └── Transport/{MIDITransport,BankController}.swift
│   └── MaskOrganizer/              # SwiftUI app + CoreMIDI implementation
│       ├── App/MaskOrganizerApp.swift
│       ├── MIDI/MIDIManager.swift
│       └── Views/{ContentView,BankListView,VoiceRow,…}.swift
└── Tests/MaskCoreTests/
    ├── *Tests.swift                # 34 tests, ~1.6 s
    └── Fixtures/                   # captured SysEx + .m1b round-trip fixtures
```

## Tests

```bash
cd MaskOrganizer
swift test                          # 34 tests
```

Tests run against pre-extracted fixtures (a captured factory dump, a captured user-bank read, a captured user-bank write, and a 271-voice `.m1b` sample). Capture-conformance tests assert that our encoder output matches the web app's wire bytes byte-for-byte.

## Status

| Feature | State |
|---|---|
| Read factory bank | ✅ |
| Read user bank | ✅ |
| Reorder (⌥↑/↓) / multi-select / search | ✅ |
| Copy selection / copy all between panes | ✅ |
| Import / export `.m1b` and `.syx` | ✅ |
| Export selection only as `.m1b` | ✅ |
| Export CSV | ✅ |
| Write user bank to device | ✅ — confirmed against the web app's "Send to MASK1" capture; refuses to send if bank not loaded |
| Inline rename | ⚠️ data path works, UI not yet wired |
| Per-voice parameter editor | ❌ deferred (Phase 7) |
| Live audition | ❌ deferred |
| Dark mode | ❌ light mode forced for now |

## Documentation

- [docs/development-plan.md](docs/development-plan.md) — phased plan
- [docs/architecture.md](docs/architecture.md) — module decisions, public method signatures, protocol facts
- [docs/log.md](docs/log.md) — running changelog (read this if you're picking up where someone left off)
- [docs/test-plan.md](docs/test-plan.md) — MIDI Monitor capture instructions
- [docs/MASK1EX_ORGANIZER_HANDOFF.md](docs/MASK1EX_ORGANIZER_HANDOFF.md) — original protocol notes
