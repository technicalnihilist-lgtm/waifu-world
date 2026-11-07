class_name SettingsRepository
extends Node
## Persisted application settings (graphics, room lighting, camera, UI state).
##
## The autoload singleton `AppSettings` is an instance of this class. Unit tests
## instantiate it with a temporary `root_dir`.
##
## Unknown or out-of-range values coming from disk are repaired on load, so a
## hand-edited or outdated settings file can never break startup.

signal settings_changed

const DEFAULT_ROOT_DIR := "user://settings"
const STORAGE_FILE := "app_settings.json"

const DEFAULTS := {
	"quality_level": 1,
	"time_of_day": 20.0,
	"auto_day_night": false,
	"camera_distance": 3.2,
	"room_id": "bedroom",
	"onboarding_done": false,
	"last_avatar_notice": "",
}

const TIME_OF_DAY_MIN := 0.0
const TIME_OF_DAY_MAX := 24.0
const CAMERA_DISTANCE_MIN := 1.8
const CAMERA_DISTANCE_MAX := 6.0

var root_dir: String = DEFAULT_ROOT_DIR
var last_error: String = ""
var loaded: bool = false

var _values: Dictionary = {}


func _ready() -> void:
	if not loaded:
		load_from_disk()


func storage_path() -> String:
	return root_dir.path_join(STORAGE_FILE)


func load_from_disk() -> bool:
	_values = DEFAULTS.duplicate(true)
	last_error = ""

	var result := JsonFile.read(storage_path())
	if result["ok"] and result["data"] is Dictionary:
		for key in DEFAULTS.keys():
			if (result["data"] as Dictionary).has(key):
				_values[key] = result["data"][key]
	elif result["exists"] and not result["corrupt"]:
		last_error = str(result["error"])

	_sanitize()
	loaded = true
	return last_error.is_empty()


func save() -> bool:
	var result := JsonFile.write_atomic(storage_path(), _values)
	if not result["ok"]:
		last_error = str(result["error"])
		return false
	last_error = ""
	return true


func get_value(key: String, fallback: Variant = null) -> Variant:
	return _values.get(key, DEFAULTS.get(key, fallback))


func set_value(key: String, value: Variant, persist: bool = true) -> void:
	if not DEFAULTS.has(key):
		# Silently ignore unknown keys instead of polluting the save file.
		return
	_values[key] = value
	_sanitize()
	if persist:
		save()
	settings_changed.emit()


func quality_level() -> int:
	return int(get_value("quality_level", 1))


func set_quality_level(level: int) -> void:
	set_value("quality_level", clampi(level, 0, QualityPresets.LEVEL_COUNT - 1))


func quality_preset() -> Dictionary:
	return QualityPresets.for_level(quality_level())


func time_of_day() -> float:
	return float(get_value("time_of_day", 20.0))


func set_time_of_day(hours: float) -> void:
	set_value("time_of_day", clampf(hours, TIME_OF_DAY_MIN, TIME_OF_DAY_MAX))


func camera_distance() -> float:
	return float(get_value("camera_distance", 3.2))


func set_camera_distance(distance: float) -> void:
	set_value("camera_distance", clampf(distance, CAMERA_DISTANCE_MIN, CAMERA_DISTANCE_MAX))


func room_id() -> String:
	return str(get_value("room_id", "bedroom"))


func set_room_id(room: String) -> void:
	set_value("room_id", room)


func reset_to_defaults() -> void:
	_values = DEFAULTS.duplicate(true)
	save()
	settings_changed.emit()


func _sanitize() -> void:
	_values["quality_level"] = clampi(int(_as_float(_values.get("quality_level", 1), 1.0)), 0, QualityPresets.LEVEL_COUNT - 1)
	_values["time_of_day"] = clampf(_as_float(_values.get("time_of_day", 20.0), 20.0), TIME_OF_DAY_MIN, TIME_OF_DAY_MAX)
	_values["auto_day_night"] = bool(_values.get("auto_day_night", false))
	_values["camera_distance"] = clampf(_as_float(_values.get("camera_distance", 3.2), 3.2), CAMERA_DISTANCE_MIN, CAMERA_DISTANCE_MAX)
	_values["room_id"] = str(_values.get("room_id", "bedroom"))
	_values["onboarding_done"] = bool(_values.get("onboarding_done", false))
	_values["last_avatar_notice"] = str(_values.get("last_avatar_notice", ""))


static func _as_float(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		return float(value)
	if value is String and str(value).is_valid_float():
		return float(str(value))
	return fallback
