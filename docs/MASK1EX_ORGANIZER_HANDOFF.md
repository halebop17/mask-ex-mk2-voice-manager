# Kodamo Mask1EX MK2 — Voice Organizer Mac App Handoff

## Project Goal
Build a native macOS desktop app that replicates (and improves on) the Kodamo web-based Voice Organizer at `kodamo.org/mask1organizer`. The web app uses the browser Web MIDI API; the Mac app will use CoreMIDI directly.

---

## The Device
- **Kodamo Mask1EX MK2** — FM/bitmask desktop synthesizer
- USB-C connection: class-compliant USB Audio (38,000 Hz, 2ch, 16-bit) + class-compliant USB MIDI
- Also has DIN MIDI in/out
- macOS sees it as: **"Mask1EX MK2"** (both input and output port names)
- 377 factory presets (read-only), 200 user voice slots (read/write)
- Manual: `kodamo.org` → Support page

---

## Fully Decoded SysEx Protocol

### Manufacturer ID
Kodamo uses a **3-byte manufacturer ID**: `00 00` (after the F0 start byte).  
Note: MIDI Monitor misidentifies these as "IOTA Systems" / "IVL Technologies" etc — ignore those labels, they're wrong.

### Request a single voice (HOST → DEVICE)
```
F0 00 00 02 [LSB] [MSB] F7
```
- `02` = "transmit voice" command
- Voice index N encoded as two 7-bit bytes:
  - `LSB = N & 0x7F`
  - `MSB = N >> 7`
- Examples:
  - Voice 0   → `F0 00 00 02 00 00 F7`
  - Voice 127 → `F0 00 00 02 7F 00 F7`
  - Voice 128 → `F0 00 00 02 00 01 F7`
  - Voice 376 → `F0 00 00 02 78 02 F7`

### Voice response (DEVICE → HOST)
```
F0 00 00 [130 bytes of voice data] F7
```
Total SysEx message = 134 bytes (F0 + 00 + 00 + 130 data bytes + F7)

### Voice data format (130 bytes)
- Every byte is in range 0x00–0x0F (a nibble)
- Parameters are **nibble-pair encoded**: two consecutive bytes form one 8-bit value
  - `value = (byte[n] << 4) | byte[n+1]`
- 130 bytes → **65 parameters** per voice
- Bytes [0,1] always = `0x00, 0x00` (fixed header)
- Bytes [2,3] always = `0x08, 0x07` → reconstructed = `0x87` (likely fixed packet type marker)
- Voice parameters start from byte pair index 2 onward

### Bank ranges
| Bank | Voice indices | Type |
|------|--------------|------|
| Factory presets | 0–376 (P00–P119 × 3 banks?) | Read-only |
| User voices | 200 slots starting after factory | Read/write |

The web organizer requests voices sequentially. For factory bank it sends requests 0–376. For user bank it sends a different range. Exact user bank index range: **not yet confirmed** — sniff separately or check by requesting indices 377+ and seeing what comes back.

### Writing a voice back (HOST → DEVICE)
Command not yet captured. Likely:
```
F0 00 00 03 [LSB] [MSB] [130 bytes of voice data] F7
```
(`03` being the "receive voice" command, symmetric to `02`). **Verify by sniffing the web app's "Send to MASK1" action in MIDI Monitor before implementing write.**

---

## Voice Data — Parameter Map (partially decoded)

Parameters are nibble-pair encoded. Pair index = byte_position / 2.

| Pair index | Bytes | Notes |
|-----------|-------|-------|
| 0 | [0,1] | Always 0x00 — fixed header |
| 1 | [2,3] | Always 0x87 — fixed packet marker |
| 2–4 | [4–9] | Osc1 parameters (MASK, SEMI, TUNE area) |
| 5–7 | [10–15] | Osc2 parameters |
| 8–9 | [16–19] | Noise parameters |
| 10–19 | [20–39] | Envelope parameters (Osc1, Osc2, Noise, Filter ADSR) |
| 20–25 | [40–51] | Filter parameters (CUTF, RESO, MODE, TRK, EXTRA) |
| 26–35 | [52–71] | LFO1 parameters (AMT, SPD, DEST, WAVE, DLAY, DCAY) |
| 36–45 | [72–91] | LFO2 parameters |
| 46–50 | [92–101] | FX1 and FX2 (BAL, TYPE) |
| 51–55 | [102–111] | Arpeggiator (TYPE, SPD, HOLD, TRIG) |
| 56–60 | [112–121] | Pitch envelope, Modulations |
| 61–64 | [122–129] | General (MODE, VOL, SEMI, PORT, PANS, RATE) |

**Note:** The above is approximate — full parameter-to-byte mapping requires further reverse engineering by comparing known preset values against the CC map in the manual (pages 39–42). The manual has a complete CC list which maps to the same parameters.

### Key constraint ranges from the analysis:
- Byte [5]: only values 4 or 5 (2 options — likely a flag/type)
- Byte [7]: values 2, 4, 5 (3 options)  
- Bytes [29],[35]: values 0–3 and 8–11 (suggests signed/offset encoding)
- Byte [47]: values 0–3 and 8 (loop mode: NO/YES/BIDI + off)
- Byte [51],[61]: values 0–3 and 12–15 (another flag pattern)
- Byte [83]: only 0, 1, 2 (3 options — e.g. loop off/on/bidi)
- Byte [95]: only 0 or 1 (binary flag)
- Byte [103]: only 0, 4, 8 (3 options, step of 4)

---

## What the Web App Does (feature reference)

**Temporary area (left pane, yellow):**
- Load voices from file (.syx or similar)
- Load factory bank from MASK1 (requests all 377 factory voices)
- Download voice list (CSV)

**User bank (right pane, green):**
- Load user bank from MASK1 (requests all 200 user voices)
- Load user bank from file
- Download bank to computer (backup)
- Download selection to computer
- Download voice list (CSV)
- Send to MASK1 (writes modified bank back)

**Interaction:**
- Click to select slot
- Up/down arrow keys to reorder voices
- Ctrl+click for multi-select
- Copy selection / Copy all → moves voices between panes

---

## Recommended Mac App Stack

**Language:** Swift  
**UI:** SwiftUI  
**MIDI:** CoreMIDI (native, no dependencies)  
**Target:** macOS 13+ (Ventura)

### CoreMIDI key APIs
```swift
import CoreMIDI

// Setup
var client = MIDIClientRef()
MIDIClientCreate("MaskOrganizer" as CFString, nil, nil, &client)

// Find device ports by name "Mask1EX MK2"
// Send SysEx
var outputPort = MIDIPortRef()
MIDIOutputPortCreate(client, "Output" as CFString, &outputPort)

// Receive SysEx  
var inputPort = MIDIPortRef()
MIDIInputPortCreateWithProtocol(...)

// Send a voice request
let requestBytes: [UInt8] = [0xF0, 0x00, 0x00, 0x02, lsb, msb, 0xF7]
// wrap in MIDIPacket and send via MIDISend()
```

### Suggested app structure
```
MaskOrganizerApp/
├── App/
│   └── MaskOrganizerApp.swift
├── MIDI/
│   ├── MIDIManager.swift        # CoreMIDI setup, device discovery
│   ├── MaskProtocol.swift       # SysEx encode/decode
│   └── VoiceData.swift          # 130-byte voice model
├── Model/
│   ├── Voice.swift              # Voice struct (name, index, raw bytes, decoded params)
│   └── VoiceBank.swift          # Array of voices, load/save/reorder
├── Views/
│   ├── ContentView.swift        # Main split view
│   ├── BankListView.swift       # Reorderable voice list
│   ├── VoiceDetailView.swift    # Optional: show decoded params
│   └── DeviceToolbar.swift      # Connect/load/send buttons
└── Utilities/
    └── FileIO.swift             # Import/export .syx files
```

---

## Data Files Available

The following captures were made and analyzed:

1. **`load-user-bank.mmon`** — MIDI Monitor capture of empty user bank (200 identical init voices)
2. **`load-user-bank.mmon` (second)** — Factory bank capture, 377 unique voice packets
3. **`factory-dump.mmon`** — Factory bank capture WITH both To/From traffic, confirmed request protocol

All parsing was done in Python — the key extraction code:

```python
import plistlib

with open('factory-dump.mmon', 'rb') as f:
    outer = plistlib.load(f)

raw = bytes(outer['messageData'])
inner = plistlib.loads(raw)
objects = inner['$objects']

# Separate To/From messages
to_msgs = []
from_msgs = []
i = 0
while i < len(objects):
    obj = objects[i]
    if isinstance(obj, str) and obj in ('To Mask1EX MK2', 'From Mask1EX MK2'):
        direction = obj
        for j in range(i+1, min(i+4, len(objects))):
            if isinstance(objects[j], bytes):
                if direction == 'To Mask1EX MK2':
                    to_msgs.append(objects[j])
                else:
                    from_msgs.append(objects[j])
                break
    i += 1

# Decode a voice packet (130 bytes → 65 parameters)
def decode_voice(data: bytes) -> list[int]:
    params = []
    for i in range(0, 130, 2):
        val = (data[i] << 4) | data[i+1]
        params.append(val)
    return params
```

---

## Still Unknown / TODO

1. **Write command byte** — Assumed `03` but not confirmed. Sniff "Send to MASK1" in MIDI Monitor.
2. **User bank index range** — Need to sniff "Load user bank from MASK1" with a populated user bank to confirm which voice indices are requested.
3. **Voice name location** — Voice names are not visible as ASCII in the 130-byte packets. They may be stored separately, encoded differently, or not transmitted at all (the web app may display them from a separate name dump). Investigate.
4. **Full parameter map** — Cross-reference the manual's CC table (pages 39–42) with nibble-pair values from known presets to label all 65 parameter slots.
5. **Partial voice SysEx** — The manual mentions "Partial voice transmit/receive" — unknown format, possibly for single-parameter edits.
6. **Trigger voice write SysEx** — Mentioned in manual, unknown format. May be needed to commit writes to EEPROM.

---

## Manual Reference (key pages)
- p.39–42: Full MIDI CC map (all voice parameters)
- p.35: SysEx mentioned: voice transmit, voice receive, partial voice transmit/receive, trigger voice write, firmware upgrade, current voice reload
- Manual PDF available at `kodamo.org` support page
- Device: Mask1EX MK2, also compatible with Mask1 and Mask1EX Mk1 (same voice format)

---

## ADDENDUM: .m1b File Format (fully decoded)

### File structure
- **No file header**
- **64 bytes per voice record**, packed contiguously
- File contains N voices = `filesize / 64`

### Record structure (64 bytes)
```
Bytes  0–8  : Voice name, ASCII, null-padded (9 bytes, max 8 visible chars + null)
Bytes  9–63 : Voice parameters, dense binary encoding (55 bytes)
```

### Encoding difference: .m1b vs SysEx
The `.m1b` file stores parameters as **raw bytes** (0x00–0xFF).  
The SysEx protocol **nibble-encodes** the same data: each byte → two 4-bit nibbles → two MIDI-safe bytes.  
So 55 bytes in `.m1b` = 110 nibble bytes in SysEx (plus ~20 header/name bytes = 130 total).

### Voice name discovery
Voice names ARE embedded in the voice data — first 9 bytes of each record.  
In SysEx, this corresponds to nibble pairs [0–8] = bytes [0–17] of the 130-byte payload.  
The name is ASCII, space-padded or null-terminated, max 8 characters.  
Example names from the sample bank: `xAF SIN I`, `xAF WAFFL`, `xAFARNARP`  
(The `xAF` prefix is a user/author tag convention, not part of the format.)

### Converting between formats
```python
def m1b_record_to_sysex_payload(record: bytes) -> bytes:
    """Convert 64-byte .m1b record to 130-byte SysEx voice payload"""
    # The 55 data bytes need to be nibble-expanded to 110 bytes
    # Plus 9 name bytes nibble-expanded to 18 bytes = 128... 
    # + 2 header bytes = 130 total
    # NOTE: exact mapping needs verification by cross-referencing
    # a voice loaded from .m1b file vs same voice dumped via SysEx
    result = []
    for b in record:  # 64 bytes → 128 nibbles + 2 header = 130
        result.append((b >> 4) & 0x0F)
        result.append(b & 0x0F)
    return bytes(result)  # 128 bytes - verify header alignment

def sysex_payload_to_m1b_record(payload: bytes) -> bytes:
    """Convert 130-byte SysEx payload to 64-byte .m1b record"""
    # Skip first 2 header bytes, then pack nibble pairs back to bytes
    result = []
    for i in range(2, 130, 2):
        b = (payload[i] << 4) | payload[i+1]
        result.append(b)
    return bytes(result)  # 64 bytes
```
**Important:** Verify the above conversion with a real round-trip test before shipping.

### Sample bank analysed
File: `Avi_Fine_Mask1_bank_Interactive.m1b`  
271 voices, all prefixed with `xAF` (author tag), various categories.
