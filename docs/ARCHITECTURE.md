# Architecture

## The one rule

The 3D companion is the centre of the screen. Screens are translucent overlays
that are pushed and popped on top of the live 3D scene; the room is never
unloaded and the camera never stops running.

## Scene tree

```
WaifuWorld (Node3D, scripts/main.gd)
├── Room          (Node3D, scripts/world/room_builder.gd)
├── Lighting      (Node3D, scripts/world/lighting_controller.gd)
├── CameraRig     (Node3D, scripts/world/camera_rig.gd)
│   └── Camera3D            (created at runtime)
├── AvatarLoader  (Node3D, scripts/avatar/avatar_loader.gd)
│   └── ProceduralAvatar | GlbAvatarAdapter
└── UI            (CanvasLayer)
    ├── MainHud             (scenes/ui/main_hud.tscn)
    └── Screens             (ScreenManager, created at runtime)
```

`main.gd` is the only node that knows about all of the others. Everything else
is independent and testable on its own.

## Autoloads

| Name | Script | Responsibility |
|---|---|---|
| `Companions` | `scripts/autoload/companions.gd` → `CompanionRepository` | profile CRUD, persistence, active companion |
| `AppSettings` | `scripts/autoload/app_settings.gd` → `SettingsRepository` | graphics, room, camera, day/night |

The autoload scripts contain **no logic** — they extend the plain classes in
`scripts/core/`, so tests can instantiate the same classes with a temporary
`root_dir` and never touch real save data.

## Layers

```
UI screens ──signals──► main.gd ──calls──► RoomBuilder / Lighting / CameraRig / AvatarLoader
    │                     │
    │                     └──reads/writes──► Companions, AppSettings
    └──reads──► Companions (list, active id)
```

Rules that keep this from turning into spaghetti:

1. **Screens never touch the 3D scene.** They emit signals (`quality_changed`,
   `room_changed`, …) and `main.gd` applies them.
2. **Screens never mutate the repository directly except through its public
   API** (`create_profile`, `update_profile`, `delete_profile`, `set_active`).
   The editor edits a *draft dictionary* and only writes on Save.
3. **Persistence is write-through.** Every mutation calls `save()` immediately,
   so a process kill loses at most the action in flight.
4. **Pure logic lives in static functions.** Day/night maths
   (`LightingController.sun_elevation`), quality presets, colour sanitising and
   room data are all static and unit-tested without a scene tree.

## Data flow for a typical edit

```
User taps Customize
  → main.gd: screens.open("editor", {profile_id})
  → CharacterEditor.setup() stores the id, _ready() builds the form from a copy
  → user changes fields (draft dictionary only)
  → Save → Companions.update_profile(id, patch)
      → CompanionProfile.apply_patch() → sanitize()
      → save() → JsonFile.write_atomic() (temp file + rename)
      → profiles_changed / active_profile_changed signals
  → main.gd: _load_companion() rebuilds the avatar from the new profile
```

## Avatar contract

`AvatarLoader.load_for_profile()` returns a `Node3D` implementing:

```gdscript
apply_profile(profile: CompanionProfile) -> void
set_quality(level: int) -> void
set_expression(name: String) -> void
set_talking(amount: float) -> void        # 0..1
play_gesture(name: String) -> bool
set_look_at(world_position: Vector3) -> void
clear_look_at() -> void
get_capabilities() -> Dictionary
head_global_position() -> Vector3
```

`get_capabilities()` is what stops the UI from over-promising: the settings
screen prints exactly what the loaded model can do (rigged? blendshapes?
which animations?). A GLB without blend shapes will honestly report
`lip_sync: none`.

## Graphics presets

`QualityPresets.for_level(n)` returns a plain dictionary. `main.gd` applies it to:

- `Engine.max_fps` (30 / 45 / 60 / 60)
- `Viewport.msaa_3d` (off / off / 2x / 4x)
- directional shadows (off / on / on / on) and shadow distance
- ambient light energy
- room rebuild with the preset's real-time light budget
- avatar mesh density (`ProceduralAvatar.preset_detail`)

Compatibility-renderer limits are respected: no SSAO, no SSR, no SDFGI, no
volumetric fog. The settings screen says so instead of offering dead toggles.

## Failure handling

| Failure | Behaviour |
|---|---|
| Corrupt `companions.json` | Copied to `companions.json.corrupt-<timestamp>`, store reseeded, message surfaced in `last_error` |
| Corrupt `app_settings.json` | Defaults loaded, file rewritten on next change |
| Malformed profile entry | That entry is skipped; the rest load |
| Duplicate profile ids | Repaired on load |
| Missing / broken GLB avatar | Procedural fallback + reason string shown in the HUD and settings |
| Save fails (disk full, permissions) | `save_failed` signal → HUD status message |
| Unknown room id | Falls back to the bedroom |
| Unknown expression / gesture | Falls back to neutral / returns `false` |
