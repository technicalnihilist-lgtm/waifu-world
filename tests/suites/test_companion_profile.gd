extends TestCase
## CompanionProfile: defaults, validation, clamping, serialisation.

func run(_tree: SceneTree) -> void:
	await _tree.process_frame

	# --- defaults --------------------------------------------------------
	var profile := CompanionProfile.create_new("Mira")
	check(profile.id.begins_with("cmp_"), "generated id has the expected prefix")
	equal(profile.display_name, "Mira", "name is stored")
	check(profile.validate().is_empty(), "a fresh profile is valid")
	check(profile.created_at > 0, "created_at is stamped")
	equal(profile.updated_at, profile.created_at, "updated_at matches created_at on creation")
	equal(profile.personality, "friendly", "default personality")
	equal(profile.language, "en", "default language")
	equal(profile.hair_style(), "long_straight", "default hair style")
	equal(profile.outfit(), "school_uniform", "default outfit")
	approx(profile.height_scale(), 1.0, 0.001, "default height scale")
	check(profile.appearance.has("avatar_id"), "appearance carries an avatar_id slot")
	equal(str(profile.appearance["avatar_id"]), "", "avatar_id defaults to the built-in placeholder")

	# --- id uniqueness ---------------------------------------------------
	var seen := {}
	var collisions := 0
	for index in 2000:
		var new_id := CompanionProfile.generate_id()
		if seen.has(new_id):
			collisions += 1
		seen[new_id] = true
	equal(collisions, 0, "2000 generated ids are unique")
	equal(seen.size(), 2000, "2000 generated ids all differ")

	# --- round trip ------------------------------------------------------
	profile.apply_patch({
		"display_name": "  Aiko  ",
		"personality": "playful",
		"voice_preset": "bright",
		"speech_rate": 1.25,
		"pitch": 1.1,
		"language": "ja",
		"appearance": {"hair_style": "twin_tails", "hair_color": "#c8a35b", "height_scale": 0.95},
		"clothing": {"outfit": "uniform", "primary_color": "#b03f5a"},
		"conversation": {"reply_length": "short", "memory_enabled": false},
	})
	equal(profile.display_name, "Aiko", "names are trimmed on save")
	var restored := CompanionProfile.from_dict(profile.to_dict())
	equal(restored.id, profile.id, "id survives round trip")
	equal(restored.display_name, "Aiko", "name survives round trip")
	equal(restored.personality, "playful", "personality survives round trip")
	equal(restored.voice_preset, "bright", "voice preset survives round trip")
	approx(restored.speech_rate, 1.25, 0.001, "speech rate survives round trip")
	equal(restored.language, "ja", "language survives round trip")
	equal(restored.hair_style(), "twin_tails", "hair style survives round trip")
	equal(restored.outfit(), "uniform", "outfit survives round trip")
	equal(restored.clothing["primary_color"], "#b03f5a", "outfit colour survives round trip")
	equal(bool(restored.conversation["memory_enabled"]), false, "memory flag survives round trip")
	equal(restored.created_at, profile.created_at, "created_at survives round trip")

	# --- hostile / malformed input ---------------------------------------
	var broken := CompanionProfile.from_dict({
		"id": "",
		"display_name": 12345,
		"personality": "nonexistent",
		"voice": "not a dictionary",
		"appearance": {"hair_style": "mohawk", "height_scale": 99.0, "skin_tone": "not-a-colour"},
		"clothing": {"outfit": "spacesuit", "primary_color": "#zzz"},
		"conversation": {"reply_length": "epic"},
		"created_at": "yesterday",
		"updated_at": null,
	})
	check(broken.id.begins_with("cmp_"), "missing id is regenerated")
	equal(broken.display_name, "12345", "non-string name is coerced")
	equal(broken.personality, "friendly", "unknown personality falls back")
	equal(broken.voice_preset, "soft", "malformed voice block falls back")
	equal(broken.hair_style(), "long_straight", "unknown hair style falls back")
	approx(broken.height_scale(), CompanionProfile.MAX_HEIGHT_SCALE, 0.001, "height is clamped")
	equal(broken.appearance["skin_tone"], "#e8b79c", "invalid colour falls back")
	equal(broken.outfit(), "school_uniform", "unknown outfit falls back")
	equal(broken.clothing["primary_color"], "#8a3fb0", "invalid outfit colour falls back")
	equal(str(broken.conversation["reply_length"]), "balanced", "unknown reply length falls back")
	check(broken.created_at > 0, "invalid timestamp is repaired")
	check(broken.validate().is_empty(), "sanitised profile validates cleanly")

	# --- clamping of numeric ranges --------------------------------------
	var clamped := CompanionProfile.create_new("Clamp")
	clamped.apply_patch({"speech_rate": 5.0, "pitch": 0.1})
	approx(clamped.speech_rate, CompanionProfile.MAX_SPEECH_RATE, 0.001, "speech rate upper clamp")
	approx(clamped.pitch, CompanionProfile.MIN_PITCH, 0.001, "pitch lower clamp")

	# --- name rules ------------------------------------------------------
	var long_name := CompanionProfile.create_new("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
	equal(long_name.display_name.length(), CompanionProfile.MAX_NAME_LENGTH, "long names are truncated")
	var empty_name := CompanionProfile.create_new("    ")
	check(not empty_name.display_name.is_empty(), "blank name falls back to a default")

	var invalid := CompanionProfile.create_new("")
	invalid.display_name = ""
	check(not invalid.validate().is_empty(), "empty name fails validation")

	# --- unknown patch keys are ignored ----------------------------------
	var guarded := CompanionProfile.create_new("Guarded")
	guarded.apply_patch({"admin": true, "id": "hijacked", "display_name": "Kept"})
	equal(guarded.display_name, "Kept", "known patch key is applied")
	check(not guarded.to_dict().has("admin"), "unknown patch key is not stored")
	check(guarded.id.begins_with("cmp_"), "id cannot be changed through a patch")

	# --- duplication -----------------------------------------------------
	var copy := profile.duplicate_profile(true)
	check(copy.id != profile.id, "duplicated profile gets a new id")
	equal(copy.display_name, profile.display_name, "duplicated profile keeps its data")

	# --- colour accessors ------------------------------------------------
	var colored := CompanionProfile.create_new("Colour")
	colored.apply_patch({"appearance": {"skin_tone": "#7a4c33", "eye_color": "#2f5a6b"}})
	approx(colored.skin_color().r, Color.from_string("#7a4c33", Color.BLACK).r, 0.01, "skin colour parses")
	approx(colored.eye_color().b, Color.from_string("#2f5a6b", Color.BLACK).b, 0.01, "eye colour parses")
