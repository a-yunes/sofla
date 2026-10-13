#!/usr/bin/env python3
"""Build Sofla's disk image with persisted layout, without Finder automation."""
import pathlib
import sys

import dmgbuild

app, background, output, version = sys.argv[1:]
dmgbuild.build_dmg(output, f"Sofla {version}", settings={
    "files": [app],
    "symlinks": {"Applications": "/Applications"},
    "background": background,
    "icon": str(pathlib.Path(app) / "Contents/Resources/AppIcon.icns"),
    "format": "UDZO",
    "compression_level": 9,
    "window_rect": ((120, 120), (660, 440)),
    "default_view": "icon-view",
    "icon_size": 88,
    "text_size": 14,
    "icon_locations": {"Sofla.app": (180, 220), "Applications": (480, 220)},
    "show_icon_preview": True,
    "include_icon_view_settings": True,
    "include_list_view_settings": False,
})
