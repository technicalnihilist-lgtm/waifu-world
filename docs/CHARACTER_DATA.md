# Companion data model

## Profile fields

| Field | Type | Range / values | Notes |
|---|---|---|---|
| `id` | String | `cmp_<timestamp>_<entropy><counter>` | generated, never user-editable |
| `display_name` | String | 1–24 chars, trimmed, unique per device | duplicates get ` (2)`, ` (3)` … |
| `personality` | enum | friendly, playful, calm, shy, confident, witty | drives sample lines and (later) prompt templates |
| `voice_preset` | enum | soft, warm, bright, deep, playful | stored for the voice stage |
| `speech_rate` | float | 0.6 – 1.6 | TTS rate |
| `pitch` | float | 0.7 – 1.4 | TTS pitch |
| `language` | enum | en, hi, ja | conversation language |
| `appearance.skin_tone` | hex | `#rrggbb` | normalised to lowercase with `#` |
| `appearance.hair_color` | hex | `#rrggbb` | |
| `appearance.eye_color` | hex | `#rrggbb` | |
| `appearance.hair_style` | enum | long, twin_tails, bob, ponytail, short | |
| `appearance.height_scale` | float | 0.88 – 1.12 | body scale multiplier |
| `appearance.avatar_id` | String | `""` = built-in placeholder | id of a GLB from the avatar catalog |
| `clothing.outfit` | enum | dress, hoodie, uniform, casual, gown | |
| `clothing.primary_color` | hex | `#rrggbb` | |
| `clothing.accent_color` | hex | `#rrggbb` | |
| `conversation.reply_length` | enum | short, balanced, detailed | |
| `conversation.memory_enabled` | bool | | consent flag for the memory stage |
| `conversation.use_emoji` | bool | | |
| `created_at` | int | unix seconds | set once |
| `updated_at` | int | unix seconds | refreshed on every save |

`CompanionProfile.sanitize()` forces every value into range; `validate()`
returns human-readable problems for the UI. `from_dict()` never throws: a
malformed field falls back to its default instead of failing the whole load.

## Storage file

`user://profiles/companions.json`

```json
{
  "schema": 1,
  "active_id": "cmp_20261107161316_0a1b2c3d0001",
  "profiles": [
    {
      "schema": 1,
      "id": "cmp_20261107161316_0a1b2c3d0001",
      "display_name": "Mira",
      "personality": "friendly",
      "voice": { "preset": "soft", "speech_rate": 1.0, "pitch": 1.0, "language": "en" },
      "appearance": {
        "skin_tone": "#e8b79c", "hair_color": "#4a2a3c", "eye_color": "#3f2a52",
        "hair_style": "long", "height_scale": 1.0, "avatar_id": ""
      },
      "clothing": { "outfit": "dress", "primary_color": "#8a3fb0", "accent_color": "#f2e6ff" },
      "conversation": { "reply_length": "balanced", "memory_enabled": true, "use_emoji": false },
      "created_at": 1794067996,
      "updated_at": 1794067996
    }
  ]
}
```

## Guarantees

- **Atomic writes.** Data is written to `companions.json.tmp` and renamed over
  the target, so a kill mid-write cannot truncate the save.
- **First launch** seeds one companion named `Mira`.
- **An explicitly emptied store stays empty.** Deleting every companion is a
  user decision and is not undone by a restart.
- **Damaged files are preserved**, not overwritten: they are copied to
  `companions.json.corrupt-<timestamp>` before recovery.
- **Limits:** 20 profiles. `can_create_more()` reports the state so the UI can
  disable the create button.
- **Isolation:** profiles are separate documents in one array; editing one never
  touches another (covered by a test).
- **Schema version** is stored per file and per profile so a future migration
  can detect old data.

## Not in this schema yet

Conversation history, memory entries, usage counters and account identity all
belong to later stages. They will be added as separate files keyed by
`profile.id` rather than bloating this document.
