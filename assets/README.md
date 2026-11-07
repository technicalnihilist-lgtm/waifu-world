# Assets

This folder holds optional runtime assets. Nothing here is required to run the
app — the built-in character is generated procedurally at runtime.

## avatars/

- `avatars.json` — manifest of **bundled** GLB avatars. Ships empty on purpose:
  no third-party character art is included in this repository.
- `example_manifest.json` — a template showing every supported field. Rename or
  merge entries into `avatars.json` when you add a model.
- `nova.glb` / `nova.json` — user-installed avatars live in `user://avatars/`
  instead, so they survive reinstalls of the APK and need no re-export.

Read [../docs/AVATAR_INTEGRATION.md](../docs/AVATAR_INTEGRATION.md) before adding
a model, and record its author and licence in the manifest.
