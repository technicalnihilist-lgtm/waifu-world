# Testing

## How to run

```bash
godot --headless --path . --import                 # once, builds the global class cache
godot --headless --path . tests/test_runner.tscn   # runs everything
```

Exit code `0` = all assertions passed, `1` = failures. The runner prints one
line per suite and a total, so it can gate CI directly.

## Latest real result

Run on Godot `4.3.stable` (Linux x86_64, headless, no GPU):

```
[PASS] test_json_file                      23 passed,   0 failed
[PASS] test_companion_profile              50 passed,   0 failed
[PASS] test_companion_repository           48 passed,   0 failed
[PASS] test_settings_and_quality          280 passed,   0 failed
[PASS] test_avatar                         54 passed,   0 failed
[PASS] test_main_scene                     51 passed,   0 failed
============================================================
TOTAL: 506 passed, 0 failed across 6 suites
RESULT: PASS
```

## What is covered

**test_json_file** — atomic write, temp-file cleanup, overwrite, missing file,
corrupt file (+ backup), empty file, recursive directory creation.

**test_companion_profile** — defaults, id uniqueness (2000 ids), full
round-trip, hostile input (wrong types, unknown enums, invalid colours, bad
timestamps), numeric clamping, name trimming/truncation, unknown patch keys
ignored, id immutability, duplication, colour parsing.

**test_companion_repository** — first-launch seeding, create/select/delete,
persistence across a simulated restart, active-focus migration on delete,
name uniquifying, 20-profile limit, `profiles_changed` signal, delete-all
persisting as empty, corrupt-file recovery + backup, malformed-entry skipping,
duplicate-id repair, per-profile data isolation.

**test_settings_and_quality** — defaults, persistence across restart, clamping,
unknown-key rejection, reset, corrupt settings recovery, preset monotonicity,
quality cycling, day/night maths (elevation, daylight/night factors, ambient and
sun energy ordering, clock formatting, colour warmth), and full validation of
all three room presets (item completeness, unique node names, valid colours,
furniture inside the room, window and practical light present).

**test_avatar** — avatar builds, capability honesty (no rig, no blendshapes),
material colour application, twin-tail geometry, height scale, expression
selection and fallback, **blink regression** (eyes squash, never inflate),
eyelid travel, mouth opening for lip-sync, talking stop, gesture acceptance and
rejection, LOD keeping node count constant, catalog file detection, missing-file
detection, sidecar merging, directory scanning, and loader fallback paths.

**test_main_scene** — boots the real `main.tscn` and asserts: room item count,
collision bodies *with* shapes, world environment, directional light, active
camera, avatar loaded, **camera framing** (head inside the frustum, human-scale
height, feet on the floor, standing inside the room), HUD/screen manager
presence, wave + talk paths, all four graphics presets, time-of-day
application and persistence, room switching, camera distance persistence,
opening/closing every screen, and creating/deleting a companion through the
running app.

## What is NOT covered (honest list)

| Not tested | Why |
|---|---|
| Real GPU rendering / visuals | No display server in the build environment (headless only). Framing is verified geometrically instead. |
| Actual GLB loading | No licensed rigged model available to test with. The fallback path *is* tested. |
| Android device behaviour | No Android SDK or device. Touch, thermals, memory and back-button behaviour are untested on hardware. |
| APK on a device | An APK **was** built and signature-verified (see ANDROID_BUILD.md), but no device or emulator was available to install it. |
| Voice, AI, memory, backend | Not implemented in this stage. |
| 60 fps performance | Frame rate cannot be measured headless. |

## Notes for whoever runs this next

- Headless runs print `ERROR: Parameter "m" is null. at: mesh_get_surface_count`
  many times. That is the **dummy renderer** in `--headless` mode, not a project
  bug: it appears in a two-node test project too. Ignore it, or filter it.
- Tests point the autoloads at a temporary `user://test_tmp/...` directory, so
  running them never touches real save data. The directory is removed at exit.
- To add a suite: create `tests/suites/test_something.gd` extending `TestCase`,
  implement `run(tree)` (with at least one `await`), and add it to `SUITES` in
  `tests/test_runner.gd`.
