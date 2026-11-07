# Screenshots

**This folder is intentionally empty of images.**

The environment that built and tested this project had no working GPU, no
display server and no device, so no screenshot could be captured. Rather than
paste in a mock-up, the folder holds the tool that generates the real thing.

## Generate them (one command, any machine with a display)

```bash
godot --path . --resolution 720x1280 tools/capture_screens.tscn
```

Headless machine or CI (needs `xvfb`):

```bash
Xvfb :99 -screen 0 720x1280x24 &
DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 godot --path . --resolution 720x1280 tools/capture_screens.tscn
```

PNGs land in `user://screenshots/` — on Linux that is
`~/.local/share/godot/app_userdata/Waifu World/screenshots/`.

The tool drives the **real** `main.tscn`, not a mock-up, and captures:

| File | What it shows |
|---|---|
| `01-companion-room.png` | The main screen: companion in the bedroom, HUD strips |
| `02-wave-gesture.png` | Wave gesture mid-animation |
| `03-companions.png` | Companion list with the active profile |
| `04-editor.png` | Character editor form |
| `05-settings.png` | Settings: graphics, room, lighting, capabilities |
| `06-living-room-morning.png` | Second room at 08:30, proving the room + day/night system |

Copy the six PNGs here and reference them from the top-level README.
