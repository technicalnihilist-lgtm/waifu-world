# Roadmap and honest stage status

The master brief has 10 development stages. This file records exactly where the
project stands, so nobody mistakes a plan for a feature.

| # | Stage | State | Notes |
|---|---|---|---|
| 1 | 3D environment | **Done, improved** | Data-driven room builder with collision, three rooms, day/night lighting, orbit/pinch camera, shadows per preset. |
| 2 | Real 3D female character | **Partially done** | The built-in companion is now genuinely rigged: 20-bone skeleton, skinned mesh, keyframed clips, jaw lip-sync. It is still a stylised low-poly figure without facial blend shapes; a hand-sculpted GLB can be dropped in via the avatar system. |
| 3 | Character management | **Done** | Create, name, select, edit, delete, persist, load; independent profile per companion; 20-profile limit; corrupt-data recovery. |
| 4 | AI backend (FastAPI + Postgres) | **Not started** | No server code, no client networking, no keys anywhere. |
| 5 | Voice conversation | **Not started** | No microphone, no TTS, no permissions. |
| 6 | Character animation | **Partially done** | Expressions, blink, breathing, look-at, gestures and an amplitude-driven mouth exist for the placeholder. No audio-driven lip-sync, no walking/sitting. |
| 7 | AI memory | **Not started** | Only the per-profile `memory_enabled` consent flag exists. |
| 8 | Room customisation | **Partially done** | Three room presets, lighting control, day/night, live weather driving the lighting, room switching. No furniture placement, no decoration editing, no character-position control. |
| 9 | Hybrid online/offline AI | **Not started** | Deliberately not faked. |
| 10 | Full app (17 screens) | **Partially done** | Main room + Companions + Editor + Settings = 4 of 17. Splash, onboarding, login, registration, voice settings, history, memory, provider, account, privacy, subscription and about-as-a-screen are missing. |

## Recommended order for the next sessions

1. **Stage 4 backend** — FastAPI + Postgres, provider abstraction, streaming,
   language detection, quotas. The client already has a natural seam for it:
   `main.gd` owns the Talk action, and `CompanionProfile.conversation` already
   carries reply length / language / memory consent.
2. **Real character asset** — the loading system is ready and waiting. Add one
   licensed rigged GLB, verify the adapter's blendshape mapping against it, then
   Stage 6's audio-driven lip-sync has something to drive.
3. **Stage 5 voice** — Android `SpeechRecognizer` + `TextToSpeech` first
   (honest fallback), neural provider later behind the same interface.
4. **Stage 7 memory** — the consent flag and per-profile storage layout are
   already in place.
5. **Remaining screens** — onboarding/splash/login only once accounts exist;
   building them earlier would mean shipping dead UI.

## Explicit non-claims

- A debug APK exists and its signature is verified, but it has not been launched
  on a device or emulator. No release or Play-ready build exists.
- The app is not production ready.
- The companion is not a realistic human model.
- The Talk button does not call an AI.
- Nothing in this build makes a network request.
