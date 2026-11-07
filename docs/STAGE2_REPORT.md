# Stage 2 report

## 1. Stage 1 inspection — structure

Five files, ~450 lines, everything built at runtime from `main.gd`:

```
WaifuWorld_Stage1/
  project.godot                 # Godot 4.2, GL Compatibility, portrait 720x1280
  scenes/main.tscn              # Node3D + main.gd, nothing else
  scripts/main.gd               # room, camera, lighting, UI and companion, all in one
  scripts/procedural_companion.gd
  README.md, .gitignore
```

It ran, but it was a single-scene demo: no persistence, no profile model, no
asset pipeline, no tests, and the room/UI were hardcoded.

## 2. Defects found in Stage 1

| # | Defect | Evidence | Fix |
|---|---|---|---|
| 1 | `camera.look_at()` called before `add_child()`, so the camera orientation was never applied | runtime `ERROR: Node not inside tree. Use look_at_from_position() instead.` | camera lives in `CameraRig`, positioned after entering the tree, and `look_at` is guarded |
| 2 | Blinking set `eye.scale.y = 0.12` (absolute) instead of multiplying, so eyes **grew** instead of closing | code inspection; base eye scale was 0.09 | eyes scale relative to a 1.0 group; lids slide down; covered by a regression test |
| 3 | `react("smile")` set `mouth.scale.x = 1.35` absolute, making the mouth ~15× too wide, and never reset it | code inspection; base mouth width 0.09 | mouth is driven by a lerped expression parameter |
| 4 | `_make_box()` created `StaticBody3D` nodes with **no `CollisionShape3D`** — collision did nothing | code inspection | `RoomBuilder` always adds a `BoxShape3D`; a test asserts shapes == bodies |
| 5 | Quality preset inconsistent: initial shadow state used `>= 1`, the cycle used `>= 2` | code inspection | single `QualityPresets` source of truth, 4 levels, persisted |
| 6 | `set_quality()` on the companion was a no-op — a fake feature | code inspection | real LOD: mesh segment counts per preset |
| 7 | Wave rotated the right arm to `z = -1.25`, swinging it **across the body** instead of outward | sign analysis of the rotation | arm raised outward (`+2.05`) with a forearm oscillation |
| 8 | Arms rotated around their own mesh centre instead of a shoulder joint | code inspection | jointed hierarchy: shoulder → elbow → hand |
| 9 | Hardcoded greetings presented as an AI companion speaking ("Hi! I'm your AI companion") | `main.gd` greeting list | lines are labelled `sample line, no AI connected`, and the HUD carries a permanent disclaimer |
| 10 | No persistence: graphics choice and character were lost on every launch | code inspection | `SettingsRepository` + `CompanionRepository` with atomic writes |
| 11 | Android Back was not handled — an open overlay could not be dismissed | no `ui_cancel` handling | `ScreenManager` pops the top screen; Back with nothing open still exits |
| 12 | No `assets/`, `docs/`, `tests/` or input configuration | file listing | added, with documentation |
| 13 | `randomize()` was called after building, so the first blink timing was not randomised | code inspection | `randomize()` before first use |
| 14 | No safe-area handling for notches | code inspection | HUD reads `DisplayServer.get_display_safe_area()` |

## 3. New features implemented

- **Persistent companion profiles** — full CRUD, 20-profile limit, unique names,
  atomic writes, corrupt-file backup and recovery, per-profile data isolation.
- **Character management UI** — list/select/edit/delete with confirmation, and a
  complete create/edit form (name, personality, voice, language, appearance,
  clothing, height, avatar model, conversation preferences).
- **Replaceable avatar system** — GLB/glTF discovery from a bundled manifest and
  from `user://avatars/`, runtime import through `GLTFDocument`, automatic
  scaling, skeleton/blendshape/animation detection, honest capability reporting,
  and a documented fallback path with a visible reason.
- **Upgraded procedural character** — jointed skeleton hierarchy, parameterised
  appearance (skin/hair/eye/outfit colours, five hair styles, five outfits,
  height), eight expressions blended per frame, amplitude-driven mouth opening,
  wave/nod/shake gestures, head and eye look-at, breathing, LOD by preset.
- **Data-driven rooms** — bedroom, living room and apartment built from data,
  with collision, emissive windows and lamps, and a per-preset real-time light
  budget.
- **Day/night lighting** — full 0–24h model with sunrise/sunset warmth, moonlight,
  ambient response and a window spot light aimed at the room's window.
- **Mobile camera** — drag to orbit, pinch to zoom, mouse wheel on desktop,
  smooth easing, clamped pitch and yaw.
- **Four graphics presets** — shadows, MSAA, mesh density, light budget, frame
  cap; persisted and applied live.
- **Test infrastructure** — 6 suites, 506 assertions, runnable headless, non-zero
  exit on failure.

## 4. Existing features preserved

The 3D room, the companion standing in it, Talk, Wave, the About/status line and
the four graphics levels all still exist. Talk and Wave now drive the upgraded
character; the room is the same idea with more furniture and real collision.

## 5. Bugs fixed during development (found by the tests)

| Found by | Bug | Fix |
|---|---|---|
| test_companion_profile / repository | Colour sanitising stripped the `#`, so stored colours never matched the palette and the selected swatch could not highlight | colours normalised to `#rrggbb` |
| test_companion_repository | The corrupt-file recovery message was erased by the save that follows recovery | messages collected and applied after saving |
| test_companion_repository | `delete all companions` was undone on restart, because loading always reseeded | seeding now happens only on a genuine first launch or after corruption |
| test_companion_profile | Profile ids could collide (65536 values per second) | timestamp + entropy + monotonic counter; 2000-id uniqueness test |
| verbose exit trace | A `SceneTreeTimer` coroutine leaked when the app was torn down | expression reset moved into `_process`; no leak at exit |
| manual review | `load()` shadowed the GDScript built-in and broke parsing | renamed to `load_from_disk()` |
| manual review | `_sphere_mesh` returned `ArrayMesh` while declaring `SphereMesh` | return type corrected to `Mesh` |

## 6. Tests actually executed

Godot `4.3.stable`, Linux x86_64, headless:

```
[PASS] test_json_file                      23 passed,   0 failed
[PASS] test_companion_profile              50 passed,   0 failed
[PASS] test_companion_repository           48 passed,   0 failed
[PASS] test_settings_and_quality          280 passed,   0 failed
[PASS] test_avatar                         54 passed,   0 failed
[PASS] test_main_scene                     51 passed,   0 failed
TOTAL: 506 passed, 0 failed across 6 suites — RESULT: PASS
```

Also executed: a 400-frame headless run of the real `main.tscn` with no script
errors, and a manual inspection of the written save files.

Not executed: anything requiring a GPU, an Android device, an Android SDK, or a
licensed GLB model. See [TESTING.md](TESTING.md).

## 7. APK build (executed)

A debug APK was built and verified in a headless container with no editor and no
device:

- JDK 17 (Temurin) and Android SDK build-tools 34 / platform-tools installed from
  `dl.google.com`, Godot 4.3 export templates from GitHub releases.
- `godot --headless --path . --export-debug "Android" build/WaifuWorld.apk`
  (wrapped by `tools/build_android.sh`).
- Result: `world.waifu.companion` v0.2.0, minSdk 21 / targetSdk 34,
  arm64-v8a + armeabi-v7a, **48 MB**, signed with a debug keystore and verified
  for APK signature schemes v1, v2 and v3.
- `tests/` and `docs/` are excluded from the package; `assets/avatars/avatars.json`
  is included.

Two real problems were found and solved on the way, both documented in
[ANDROID_BUILD.md](ANDROID_BUILD.md): Godot reads SDK/JDK/keystore paths from
editor settings rather than the export preset, and `apksigner` silently fails
under a constrained memory cgroup, producing an **unsigned** APK unless
`_JAVA_OPTIONS` caps the JVM heap.

**Not verified:** the APK was never installed or launched. No device and no
`/dev/kvm` were available, so no emulator could boot either. First-launch
behaviour on Android hardware remains untested.

## 8. Remaining limitations

1. The companion is still a placeholder — no rigged human model, no blendshapes.
2. No AI, no network, no accounts, no backend.
3. No microphone, no TTS, no audio-driven lip-sync.
4. No memory system (only the consent flag).
5. 4 of the 17 target screens exist.
6. A debug APK exists and is signature-verified, but it has never been run on a
   device or emulator; the Android checklist in
   [ANDROID_BUILD.md](ANDROID_BUILD.md) is untested on hardware. No release or
   Play-ready build exists.
7. UI text is English only; the default font has no Devanagari or Japanese glyphs.
8. No furniture placement or character-position editing.

## 9. How to run

```bash
godot --path .                                    # play
godot --headless --path . --import                # first time
godot --headless --path . tests/test_runner.tscn  # test
```

## 10. How to build the APK

```bash
ANDROID_HOME=/path/to/android-sdk JAVA_HOME=/path/to/jdk-17 \
KEYSTORE=~/debug.keystore ./tools/build_android.sh build/WaifuWorld.apk
```

See [ANDROID_BUILD.md](ANDROID_BUILD.md) for prerequisites, the two headless
gotchas and the device checklist.
