class_name CompanionProfile
extends RefCounted
## A single AI companion's saved configuration.
##
## The profile is deliberately plain data (dictionaries + primitives) so that it
## can be written to JSON, shown in the editor UI and unit tested without the
## scene tree. Nothing in here talks to a network or a renderer.
##
## Field groups:
##   identity      -> id, display_name, created_at, updated_at
##   personality   -> personality
##   voice         -> voice_preset, speech_rate, pitch, language
##   appearance    -> skin_tone, hair_color, eye_color, hair_style, height_scale
##   clothing      -> outfit, primary_color, accent_color
##   conversation  -> reply_length, memory_enabled, use_emoji

const SCHEMA_VERSION := 1
const MIN_NAME_LENGTH := 1
const MAX_NAME_LENGTH := 24

const PERSONALITIES := ["friendly", "playful", "calm", "shy", "confident", "witty"]
const VOICE_PRESETS := ["soft", "warm", "bright", "deep", "playful"]
const LANGUAGES := ["en", "hi", "ja"]
const HAIR_STYLES := ["long", "twin_tails", "bob", "ponytail", "short"]
const OUTFITS := ["dress", "hoodie", "uniform", "casual", "gown"]
const REPLY_LENGTHS := ["short", "balanced", "detailed"]

const MIN_SPEECH_RATE := 0.6
const MAX_SPEECH_RATE := 1.6
const MIN_PITCH := 0.7
const MAX_PITCH := 1.4
const MIN_HEIGHT_SCALE := 0.88
const MAX_HEIGHT_SCALE := 1.12

var id: String = ""
var display_name: String = "Companion"
var personality: String = "friendly"
var voice_preset: String = "soft"
var speech_rate: float = 1.0
var pitch: float = 1.0
var language: String = "en"
var appearance: Dictionary = {}
var clothing: Dictionary = {}
var conversation: Dictionary = {}
var created_at: int = 0
var updated_at: int = 0


func _init() -> void:
	appearance = default_appearance()
	clothing = default_clothing()
	conversation = default_conversation()


static func default_appearance() -> Dictionary:
	return {
		"skin_tone": "#e8b79c",
		"hair_color": "#4a2a3c",
		"eye_color": "#3f2a52",
		"hair_style": "long",
		"height_scale": 1.0,
		"avatar_id": "",
	}


static func default_clothing() -> Dictionary:
	return {
		"outfit": "dress",
		"primary_color": "#8a3fb0",
		"accent_color": "#f2e6ff",
	}


static func default_conversation() -> Dictionary:
	return {
		"reply_length": "balanced",
		"memory_enabled": true,
		"use_emoji": false,
	}


## Monotonic per-process counter; guarantees ids are unique even when many
## companions are created inside the same second.
static var _id_counter: int = 0


## Generates an id that sorts by creation time and never repeats: readable
## timestamp + microsecond/random mix + a process-local counter.
static func generate_id() -> String:
	var stamp := Time.get_datetime_dict_from_system()
	var readable := "%04d%02d%02d%02d%02d%02d" % [
		stamp.get("year", 0), stamp.get("month", 0), stamp.get("day", 0),
		stamp.get("hour", 0), stamp.get("minute", 0), stamp.get("second", 0),
	]
	_id_counter += 1
	var entropy := (Time.get_ticks_usec() ^ (randi() << 12)) & 0xFFFFFFFF
	return "cmp_%s_%08x%04x" % [readable, entropy, _id_counter & 0xFFFF]


## Builds a brand new profile with defaults and the given display name.
static func create_new(new_name: String) -> CompanionProfile:
	var profile := CompanionProfile.new()
	profile.id = generate_id()
	profile.display_name = new_name
	var now := int(Time.get_unix_time_from_system())
	profile.created_at = now
	profile.updated_at = now
	profile.sanitize()
	return profile


## Returns a deep copy, optionally with a fresh identity.
func duplicate_profile(fresh_identity: bool = true) -> CompanionProfile:
	var copy := CompanionProfile.from_dict(to_dict())
	if fresh_identity:
		copy.id = generate_id()
		copy.created_at = int(Time.get_unix_time_from_system())
		copy.updated_at = copy.created_at
	return copy


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"id": id,
		"display_name": display_name,
		"personality": personality,
		"voice": {
			"preset": voice_preset,
			"speech_rate": speech_rate,
			"pitch": pitch,
			"language": language,
		},
		"appearance": appearance.duplicate(true),
		"clothing": clothing.duplicate(true),
		"conversation": conversation.duplicate(true),
		"created_at": created_at,
		"updated_at": updated_at,
	}


## Tolerant constructor: any missing or malformed field falls back to a default
## instead of failing the whole load. This is what keeps a damaged save file
## from destroying every other companion.
static func from_dict(source: Dictionary) -> CompanionProfile:
	var profile := CompanionProfile.new()

	profile.id = str(source.get("id", ""))
	if profile.id.is_empty():
		profile.id = generate_id()

	profile.display_name = str(source.get("display_name", "Companion"))
	profile.personality = str(source.get("personality", "friendly"))

	var voice: Dictionary = source.get("voice", {}) if source.get("voice") is Dictionary else {}
	profile.voice_preset = str(voice.get("preset", "soft"))
	profile.speech_rate = _to_float(voice.get("speech_rate", 1.0), 1.0)
	profile.pitch = _to_float(voice.get("pitch", 1.0), 1.0)
	profile.language = str(voice.get("language", "en"))

	profile.appearance = _merge_dict(default_appearance(), source.get("appearance", {}))
	profile.clothing = _merge_dict(default_clothing(), source.get("clothing", {}))
	profile.conversation = _merge_dict(default_conversation(), source.get("conversation", {}))

	profile.created_at = int(_to_float(source.get("created_at", 0), 0.0))
	profile.updated_at = int(_to_float(source.get("updated_at", profile.created_at), float(profile.created_at)))

	profile.sanitize()
	return profile


## Applies a partial update coming from the editor UI.
## Only known keys are accepted; everything else is ignored.
func apply_patch(patch: Dictionary) -> void:
	if patch.has("display_name"):
		display_name = str(patch["display_name"])
	if patch.has("personality"):
		personality = str(patch["personality"])
	if patch.has("voice_preset"):
		voice_preset = str(patch["voice_preset"])
	if patch.has("speech_rate"):
		speech_rate = _to_float(patch["speech_rate"], speech_rate)
	if patch.has("pitch"):
		pitch = _to_float(patch["pitch"], pitch)
	if patch.has("language"):
		language = str(patch["language"])
	if patch.has("appearance") and patch["appearance"] is Dictionary:
		appearance = _merge_dict(appearance, patch["appearance"])
	if patch.has("clothing") and patch["clothing"] is Dictionary:
		clothing = _merge_dict(clothing, patch["clothing"])
	if patch.has("conversation") and patch["conversation"] is Dictionary:
		conversation = _merge_dict(conversation, patch["conversation"])
	sanitize()
	updated_at = int(Time.get_unix_time_from_system())


## Returns human readable validation problems. An empty array means valid.
func validate() -> Array:
	var problems: Array = []
	var trimmed := display_name.strip_edges()
	if trimmed.length() < MIN_NAME_LENGTH:
		problems.append("Name cannot be empty.")
	if trimmed.length() > MAX_NAME_LENGTH:
		problems.append("Name must be %d characters or fewer." % MAX_NAME_LENGTH)
	if not PERSONALITIES.has(personality):
		problems.append("Unknown personality '%s'." % personality)
	if not VOICE_PRESETS.has(voice_preset):
		problems.append("Unknown voice preset '%s'." % voice_preset)
	if not LANGUAGES.has(language):
		problems.append("Unknown language '%s'." % language)
	if not HAIR_STYLES.has(str(appearance.get("hair_style", ""))):
		problems.append("Unknown hair style.")
	if not OUTFITS.has(str(clothing.get("outfit", ""))):
		problems.append("Unknown outfit.")
	if not REPLY_LENGTHS.has(str(conversation.get("reply_length", ""))):
		problems.append("Unknown reply length.")
	return problems


## Forces every field into a valid range/value. Never fails.
func sanitize() -> void:
	display_name = display_name.strip_edges()
	if display_name.length() > MAX_NAME_LENGTH:
		display_name = display_name.substr(0, MAX_NAME_LENGTH)
	if display_name.is_empty():
		display_name = "Companion"

	personality = _pick(personality, PERSONALITIES, "friendly")
	voice_preset = _pick(voice_preset, VOICE_PRESETS, "soft")
	language = _pick(language, LANGUAGES, "en")

	speech_rate = clampf(speech_rate, MIN_SPEECH_RATE, MAX_SPEECH_RATE)
	pitch = clampf(pitch, MIN_PITCH, MAX_PITCH)

	appearance = _merge_dict(default_appearance(), appearance)
	appearance["hair_style"] = _pick(str(appearance["hair_style"]), HAIR_STYLES, "long")
	appearance["height_scale"] = clampf(
		_to_float(appearance["height_scale"], 1.0), MIN_HEIGHT_SCALE, MAX_HEIGHT_SCALE
	)
	appearance["skin_tone"] = _sanitize_color(str(appearance["skin_tone"]), "#e8b79c")
	appearance["hair_color"] = _sanitize_color(str(appearance["hair_color"]), "#4a2a3c")
	appearance["eye_color"] = _sanitize_color(str(appearance["eye_color"]), "#3f2a52")
	appearance["avatar_id"] = str(appearance.get("avatar_id", "")).strip_edges()

	clothing = _merge_dict(default_clothing(), clothing)
	clothing["outfit"] = _pick(str(clothing["outfit"]), OUTFITS, "dress")
	clothing["primary_color"] = _sanitize_color(str(clothing["primary_color"]), "#8a3fb0")
	clothing["accent_color"] = _sanitize_color(str(clothing["accent_color"]), "#f2e6ff")

	conversation = _merge_dict(default_conversation(), conversation)
	conversation["reply_length"] = _pick(str(conversation["reply_length"]), REPLY_LENGTHS, "balanced")
	conversation["memory_enabled"] = bool(conversation["memory_enabled"])
	conversation["use_emoji"] = bool(conversation["use_emoji"])

	if created_at <= 0:
		created_at = int(Time.get_unix_time_from_system())
	if updated_at <= 0:
		updated_at = created_at


## Colour accessors used by the avatar so callers never parse hex strings.
func skin_color() -> Color:
	return Color.from_string(str(appearance.get("skin_tone", "#e8b79c")), Color(0.91, 0.72, 0.61))


func hair_color() -> Color:
	return Color.from_string(str(appearance.get("hair_color", "#4a2a3c")), Color(0.29, 0.16, 0.24))


func eye_color() -> Color:
	return Color.from_string(str(appearance.get("eye_color", "#3f2a52")), Color(0.25, 0.16, 0.32))


func outfit_color() -> Color:
	return Color.from_string(str(clothing.get("primary_color", "#8a3fb0")), Color(0.54, 0.25, 0.69))


func accent_color() -> Color:
	return Color.from_string(str(clothing.get("accent_color", "#f2e6ff")), Color(0.95, 0.90, 1.0))


func height_scale() -> float:
	return clampf(_to_float(appearance.get("height_scale", 1.0), 1.0), MIN_HEIGHT_SCALE, MAX_HEIGHT_SCALE)


func hair_style() -> String:
	return str(appearance.get("hair_style", "long"))


func outfit() -> String:
	return str(clothing.get("outfit", "dress"))


static func _to_float(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		return float(value)
	if value is String and str(value).is_valid_float():
		return float(str(value))
	return fallback


static func _pick(value: String, allowed: Array, fallback: String) -> String:
	return value if allowed.has(value) else fallback


## Normalises a colour to lowercase "#rrggbb" so stored values compare cleanly
## against the palette used by the editor UI.
static func _sanitize_color(value: String, fallback: String) -> String:
	if value.is_empty():
		return fallback
	if Color.html_is_valid(value):
		return "#" + Color.html(value).to_html(false)
	return fallback


static func _merge_dict(base: Dictionary, override: Variant) -> Dictionary:
	var merged := base.duplicate(true)
	if override is Dictionary:
		for key in override.keys():
			merged[key] = override[key]
	return merged
