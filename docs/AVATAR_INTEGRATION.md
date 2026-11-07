# Replacing the placeholder with a real character

The placeholder avatar is a real 3D mesh hierarchy, but it is **not** a rigged
human model and has **no facial blendshapes**. This document explains how to
drop in a proper character without touching game code.

## 1. Get a model you are allowed to use

You need a **rigged, humanoid GLB** (glTF 2.0 binary). Ideally it also has:

- ARKit-style blend shapes (`jawOpen`, `eyeBlinkLeft`, `mouthSmileLeft`, …)
- an idle animation clip
- a T-pose or A-pose rest pose

Record where it came from and its licence. **This repository ships no
third-party character art**, and you should not add any without checking the
licence (VRM models, Mixamo clips, Sketchfab CC0/CC-BY assets and similar all
have different terms). Put the author and licence into the manifest below so
the app can show it.

## 2. Install it

Two supported locations.

### A. User-installed (no rebuild needed)

Copy the file into the app's private storage:

```
user://avatars/nova.glb          # the model
user://avatars/nova.json         # optional sidecar manifest
```

On desktop that is
`~/.local/share/godot/app_userdata/Waifu World/avatars/`.
On Android: `/data/data/<your.package.id>/files/avatars/` (use
`adb push` while debugging).

The app creates the folder on first launch and scans it every time the avatar
picker opens. Files here are imported at runtime through `GLTFDocument`, so no
editor import step is required.

Sidecar `nova.json`:

```json
{
  "display_name": "Nova",
  "author": "Example Artist",
  "license": "CC-BY-4.0",
  "height_meters": 1.68,
  "idle_animation": "Idle"
}
```

### B. Bundled (shipped inside the APK)

1. Put `nova.glb` in `assets/avatars/`.
2. Open the project in the Godot editor once so it imports the GLB into a scene.
3. Add an entry to `assets/avatars/avatars.json`:

```json
{
  "schema": 1,
  "avatars": [
    {
      "id": "nova",
      "path": "res://assets/avatars/nova.glb",
      "display_name": "Nova",
      "author": "Example Artist",
      "license": "CC-BY-4.0",
      "height_meters": 1.68,
      "idle_animation": "Idle"
    }
  ]
}
```

4. In the export preset, add `*.json` to **Filters to export non-resource files**
   so the manifest survives export. (A `.glb` inside an APK is compiled into an
   imported scene and is not listable as a file, which is exactly why the
   manifest exists.)

## 3. Select it

Companions → Edit (or Create) → **Avatar model** → pick the model → Save.
The choice is stored as `appearance.avatar_id` on the profile, so each
companion can use a different model.

## 4. What the app does with it

`AvatarLoader` wraps the imported scene in `GlbAvatarAdapter`, which:

- scales the model so its bounding box is `height_meters` tall (0.05×–20×
  sanity clamp),
- finds `Skeleton3D`, `AnimationPlayer` and any mesh with blend shapes,
- plays the configured idle clip (falls back to `Idle`, `idle`, `Breathing`,
  `rest`),
- maps expressions and lip-sync onto blend shapes by name, using aliases:

  | App concept | Blend shape names matched (case-insensitive substring) |
  |---|---|
  | blink | `eyeBlinkLeft`, `eyesClosed`, `blink`, `eye_blink_L` |
  | smile | `mouthSmile`, `mouthSmileLeft`, `smile` |
  | mouth open | `jawOpen`, `mouthOpen`, `viseme_aa` |
  | brow raise | `browInnerUp`, `browOuterUpLeft`, `eyebrowUp` |

- reports everything it actually found through `get_capabilities()`.

If the model has no blend shapes, `get_capabilities()` returns
`lip_sync: "none"` and the settings screen says so. Nothing is faked.

## 5. What a GLB model does *not* get

- **Colour / hair / outfit editing.** Those fields style the procedural
  placeholder only; a GLB brings its own materials and textures. The editor
  says this in the Appearance section.
- **Gestures** other than a `Wave`/`wave` clip, if the model has one.
- **Look-at tracking** (the adapter accepts the call and ignores it). Add a
  bone-driven implementation in `GlbAvatarAdapter.set_look_at()` when you have
  a head bone.

## 6. Performance notes for low-end Android

- Keep the model under ~25k triangles and textures under 1024².
- Prefer a single material atlas over many materials.
- The Low preset disables shadows on avatar meshes automatically.
- Test on a 4 GB device; a 60k-triangle character with 4K textures will stutter
  in the Compatibility renderer.

## 7. If loading fails

The loader never crashes. It returns the procedural placeholder and sets
`fallback_reason`, which is shown in the HUD at launch and in Settings →
Companion model. Common causes:

| Message | Cause |
|---|---|
| `Avatar 'x' is not installed.` | id not found in either catalog source |
| `Could not read 'x.glb'. Re-export it as GLB (glTF 2.0 binary).` | broken or Draco-compressed export |
| `Avatar root node is not a 3D node.` | the glTF root is a Node2D or plain Node |
| `Bundled avatar is missing: res://…` | manifest path wrong, or `*.json`/GLB not included in the export |
