# dmgbuild settings for "Mask EX Voice Manager".
# Run from this directory: dmgbuild -s dmg-settings.py "<volume>" "<output>.dmg"
# Note: dmgbuild loads this via exec(); __file__ is not defined — use os.getcwd().

import os

REPO_DIR = os.path.abspath(os.getcwd())
APP_NAME = "Mask EX Voice Manager.app"

# `filename` deliberately omitted — let the CLI's positional argument win.
volume_name = "Mask EX Voice Manager"
format = "UDZO"
size = None

# Source folder layout: dist-dmg/<APP_NAME>
files = [os.path.join(REPO_DIR, "dist-dmg", APP_NAME)]
symlinks = {"Applications": "/Applications"}

# Volume icon (sidebar / Finder), pulled from the .app's icon resource.
icon = os.path.join(REPO_DIR, "dist-dmg", APP_NAME,
                    "Contents", "Resources", "AppIcon.icns")

# Background image lives at the repo root so it isn't copied into the DMG
# as a visible file. dmgbuild stores it as a hidden .background.tiff.
background = os.path.join(REPO_DIR, "dmg-background.png")

# Window 540 × 380 pt — matches a 540×380 (or 1080×760 retina) background.
# Adjust icon_locations to align with whatever the background image shows.
window_rect = ((200, 120), (540, 380))
icon_size = 96
text_size = 12

icon_locations = {
    APP_NAME:       (140, 200),
    "Applications": (400, 200),
}

default_view = "icon-view"
show_icon_preview = False
show_status_bar = False
show_pathbar = False
show_sidebar = False
arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100
scroll_position = (0, 0)
label_pos = "bottom"
