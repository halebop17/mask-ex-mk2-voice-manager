# DMG Generation Guide

How to create a styled DMG file with a background image, custom layout, and app icon. This guide was written after solving repeated issues — follow it exactly.

---

## Tool: dmgbuild

Use **`dmgbuild`** (Python). Do NOT use `create-dmg` — it sets the background via AppleScript which is unreliable and often fails silently.

Install if needed:
```bash
pip3 install dmgbuild
```

---

## File Layout

```
repo-root/
├── dmg/
│   ├── Zahl.app          ← signed app (exported from Xcode)
│   └── manual.pdf        ← any extra files to include
├── dmg-background.png    ← background image (MUST be outside dmg/ folder)
├── dmg-settings.py       ← build settings
└── Zahl-1.0.dmg          ← output (generated)
```

**Critical rule:** The background image must live OUTSIDE the `dmg/` source folder. If it's inside `dmg/`, it gets copied in as a visible file AND set as the background at the same time — the result is the background image shows up as an icon in the window instead of as the background.

---

## Background Image

- Format: PNG
- Size: **540×380 px** for a 540×380 pt window (non-retina). For retina sharpness, use 1080×760 px.
- The image will be stored as a hidden `.background.tiff` inside the DMG — users never see it as a file.

---

## Settings File (dmg-settings.py)

Place at the repo root. Run `dmgbuild` from the repo root directory.

**Important:** `dmgbuild` loads settings via `exec()` so `__file__` is not defined. Use `os.getcwd()` for the base path instead.

```python
import os

REPO_DIR = os.path.abspath(os.getcwd())

filename = os.path.join(REPO_DIR, 'Zahl-1.0.dmg')
volume_name = 'Zahl'
format = 'UDZO'
size = None

files = [
    os.path.join(REPO_DIR, 'dmg', 'Zahl.app'),
    os.path.join(REPO_DIR, 'dmg', 'manual.pdf'),
]

symlinks = {'Applications': '/Applications'}

icon = os.path.join(REPO_DIR, 'dmg', 'Zahl.app', 'Contents', 'Resources', 'AppIcon.icns')

background = os.path.join(REPO_DIR, 'dmg-background.png')
window_rect = ((200, 120), (540, 380))
icon_size = 80
text_size = 12

icon_locations = {
    'Zahl.app':     (140, 200),
    'Applications': (400, 200),
    'manual.pdf':   (270, 320),
}

default_view = 'icon-view'
show_icon_preview = False
show_status_bar = False
show_pathbar = False
show_sidebar = False
arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100
scroll_position = (0, 0)
label_pos = 'bottom'
```

Coordinates in `icon_locations` are `(x, y)` in points from the top-left of the window. Adjust to match the background image design.

---

## Build the DMG

Run from the repo root:

```bash
dmgbuild -s dmg-settings.py "Zahl" "Zahl-1.0.dmg"
```

---

## Set the DMG File Icon

`dmgbuild`'s `icon` key only sets the mounted volume icon (Finder sidebar). It does NOT set the icon of the `.dmg` file itself in Finder. Run this Python script after every build to set the file icon:

```bash
python3 -c "
import Cocoa, os
dmg = os.path.abspath('Zahl-1.0.dmg')
icns = os.path.abspath('dmg/Zahl.app/Contents/Resources/AppIcon.icns')
icon = Cocoa.NSImage.alloc().initWithContentsOfFile_(icns)
result = Cocoa.NSWorkspace.sharedWorkspace().setIcon_forFile_options_(icon, dmg, 0)
print('success' if result else 'failed')
"
```

Run this from the repo root. Requires PyObjC (included with macOS system Python / Xcode).

---

## Full Build Command (one shot)

```bash
cd "/path/to/repo" && \
dmgbuild -s dmg-settings.py "Zahl" "Zahl-1.0.dmg" && \
python3 -c "
import Cocoa, os
dmg = os.path.abspath('Zahl-1.0.dmg')
icns = os.path.abspath('dmg/Zahl.app/Contents/Resources/AppIcon.icns')
icon = Cocoa.NSImage.alloc().initWithContentsOfFile_(icns)
result = Cocoa.NSWorkspace.sharedWorkspace().setIcon_forFile_options_(icon, dmg, 0)
print('icon:', 'set' if result else 'failed')
"
```

---

## Updating the App in the DMG

Before rebuilding, replace the app in the `dmg/` folder with the newly exported/signed one from Xcode:

1. Export the signed app from Xcode Organizer (Developer ID / Direct Distribution)
2. Replace `dmg/Zahl.app` with the new version
3. Run the full build command above

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Background image shows as a file icon in the window | Background image is inside the `dmg/` source folder | Move it to the repo root |
| Background not visible at all | `create-dmg` AppleScript failed silently | Switch to `dmgbuild` |
| DMG file has generic download icon | `icon` key only sets volume icon, not file icon | Run the NSWorkspace Python snippet after build |
| Icons clustered in wrong position | Window size mismatch with background image dimensions | Match `window_rect` to background image size in points |
| `NameError: __file__ is not defined` | `dmgbuild` uses `exec()` — `__file__` doesn't exist | Use `os.getcwd()` instead |
