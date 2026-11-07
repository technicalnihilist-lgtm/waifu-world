# Building the Android APK

## Verified build (executed)

A debug APK was built headlessly on Godot `4.3.stable` (Linux x86_64) with no
graphical editor. Reproduce it with:

```bash
ANDROID_HOME=/path/to/android-sdk JAVA_HOME=/path/to/jdk-17 \
KEYSTORE=~/debug.keystore ./tools/build_android.sh build/WaifuWorld.apk
```

Facts about the produced artifact, read back out of the APK itself:

| Property | Value |
|---|---|
| File | `WaifuWorld-0.2.0-debug.apk` (~48 MB) |
| Package id | `world.waifu.companion` |
| Version | code `2`, name `0.2.0` |
| Min / target SDK | 21 / 34 (the prebuilt Android template fixes minSdk at 21; see the note below) |
| Architectures | `arm64-v8a`, `armeabi-v7a` |
| Launcher activity | `com.godot.game.GodotApp` |
| Signing | debug keystore `CN=Android Debug`, verified for **v1 + v2 + v3** schemes |
| Contents | compiled `.gdc` scripts, `.scn` scenes, `assets/avatars/avatars.json`; `tests/` and `docs/` excluded |

`apksigner verify --print-certs` output:

```
Verifies
Verified using v1 scheme (JAR signing): true
Verified using v2 scheme (APK Signature Scheme v2): true
Verified using v3 scheme (APK Signature Scheme v3): true
Number of signers: 1
Signer #1 certificate DN: CN=Android Debug, O=Android, C=US
```

**Not verified:** the APK has never been installed or launched. The build
machine had no device and no `/dev/kvm`, so no emulator could run either. Treat
first-launch behaviour on hardware as untested.

### Two gotchas that cost real time

1. **Godot reads the SDK, JDK and keystore paths from its *editor settings***,
   not from `export_presets.cfg`. In a headless build you must write
   `$XDG_CONFIG_HOME/godot/editor_settings-4.3.tres` (the script does this):
   ```
   export/android/android_sdk_path = "/path/to/sdk"
   export/android/java_sdk_path = "/path/to/jdk17"
   export/android/debug_keystore = "/path/to/debug.keystore"
   export/android/debug_keystore_user = "androiddebugkey"
   export/android/debug_keystore_pass = "android"
   ```
   Without them the export aborts with *"Debug keystore not configured"* /
   *"A valid Android SDK path is required"*.
2. **`apksigner` is a JVM app and Godot will happily export an unsigned APK**
   if it cannot start. In a container with a small memory cgroup the JVM dies
   with `Failed to reserve memory for metaspace` and the only symptom is
   `WARNING: ... The resulting APK is unsigned.` Fix it by capping the heap:
   ```bash
   export _JAVA_OPTIONS="-Xmx384m -XX:MaxMetaspaceSize=192m -XX:ReservedCodeCacheSize=32m"
   ```
   Always run `apksigner verify` on the result.

### Raising minSdk above 21

The non-Gradle export path reuses the prebuilt `android_debug.apk` from the
export templates, so `gradle_build/min_sdk` is ignored. To ship a higher
minimum (for example API 29 as the brief requires) enable
**Use Gradle Build**, set `gradle_build/min_sdk="29"`, and provide the Android
build template (`android_source.zip` is in the export templates). That path
also needs the Gradle distribution and a network connection for dependencies.

## Building it yourself, step by step

## 1. Install prerequisites

1. Godot **4.3+** (same version as the project).
2. **Export templates** for that exact version:
   Editor → *Editor* → *Manage Export Templates* → *Download and Install*.
3. **Android SDK** (command line tools are enough) with:
   - Android SDK Platform **API 34** (or the version your Godot release expects)
   - Android SDK Build-Tools
   - Platform-Tools (`adb`)
4. **OpenJDK 17**.
5. In Godot: *Editor* → *Editor Settings* → *Export* → *Android*:
   - `Android Sdk Path` → your SDK folder
   - `Java Sdk Path` → your JDK 17 folder
   - `Debug Keystore` → create one if the field is empty
     (Godot can generate it; it must **not** be committed).

## 2. Create the export preset

1. *Project* → *Export* → *Add…* → **Android**.
2. Set **Package → Unique Name**, e.g. `world.waifu.companion`
   (must be unique and not contain reserved words).
3. Set **Version → Code** to `2` and **Name** to `0.2.0`.
4. Set **Screen → Orientation** to `Portrait`.
   (`project.godot` already sets `window/handheld/orientation=1`.)
5. Target SDK 34. Min SDK is 21 with the prebuilt template; use a Gradle build
   to raise it (see above).
6. **Permissions.** This build needs none beyond the defaults. Do not add
   `INTERNET` or `RECORD_AUDIO` yet — they belong to the AI and voice stages.
   When you add them:
   - `INTERNET` for the backend stage
   - `RECORD_AUDIO` for the microphone stage
   Remove them again if the feature is not shipped.
7. **Filters to export non-resource files:** add `*.json` so
   `assets/avatars/avatars.json` is included.
8. **Exclude filter:** `tests/*, docs/*, *.md` (keeps the APK small).
9. Graphics: leave *Use Gradle Build* off for a quick debug APK; turn it on when
   you add Android plugins.

## 3. Export

Debug APK (for testing):

1. Tick **Runnable** in the preset.
2. *Export Project…* → choose a path → **Export**.

Install:

```bash
adb install -r build/WaifuWorld.apk
adb logcat | grep -i godot
```

Release build:

1. Create your own keystore and **never commit it**:
   ```bash
   keytool -genkey -v -keystore waifu-release.jks -keyalg RSA -keysize 2048 \
           -validity 10000 -alias waifu
   ```
2. In the preset: *Keystore → Release* → point at the `.jks`, enter the alias and
   password. Store the password in a password manager, not in the repo.
3. Export an APK or AAB. Upload the AAB to Play Console.

`.gitignore` already excludes `*.keystore`, `*.jks` and `export_presets.cfg`
(the preset contains your keystore path).

## 4. Device checklist (untested in this build — please verify)

- [ ] App launches in portrait and stays portrait.
- [ ] Companion is visible and framed on first launch.
- [ ] Drag orbits the camera; pinch zooms; the UI does not steal the gesture.
- [ ] All three buttons rows are reachable on a 6" screen and not under the notch.
- [ ] Companions → Create → Save → the new companion appears in the room.
- [ ] Force-stop the app, relaunch: the same companion is still there.
- [ ] Settings → Graphics → Low: shadows disappear, frame rate holds.
- [ ] Settings → Room: switching rooms does not drop frames badly.
- [ ] Android Back closes an open screen; Back on the room exits the app.
- [ ] `adb shell dumpsys meminfo <package>` stays flat while idling.

## 5. Known Android risks

- **Notch / gesture bar.** The HUD reads
  `DisplayServer.get_display_safe_area()` and insets the top strip. Verify on a
  notched device; this was not tested on hardware.
- **Low-end GPU.** The Compatibility renderer with two shadow-casting lights is
  the heaviest thing here. If a device struggles, ship with the Low preset as
  the default (`SettingsRepository.DEFAULTS["quality_level"] = 0`).
- **Fonts.** The default Godot font covers Latin only. Hindi/Japanese *UI text*
  needs a bundled font with those glyphs; profile data supports the languages,
  but the interface is English in this build.
