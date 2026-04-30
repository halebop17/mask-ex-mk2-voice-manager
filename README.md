# Mask EX Voice Manager

Native macOS voice organizer for the **Kodamo Mask1EX MK2** synthesizer. A Swift / SwiftUI / CoreMIDI replacement for the web tool at [kodamo.org/mask1organizer](https://kodamo.org/mask1organizer) — same workflow, native, keyboard-friendly.

![two-pane voice list, yellow temporary on the left, green user bank on the right]

## Requirements

- macOS 14 (Sonoma) or newer
- A Mask1EX MK2 connected over USB-C

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
