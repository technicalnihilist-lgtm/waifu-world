class_name CompanionRepository
extends Node
## Persistent store for companion profiles.
##
## The autoload singleton `Companions` is an instance of this class. Unit tests
## create their own instance with a temporary `root_dir`, which is why this is a
## plain Node with no tree-dependent code.
##
## Storage: `<root_dir>/companions.json`
##   {
##     "schema": 1,
##     "active_id": "cmp_...",
##     "profiles": [ { ...profile dict... } ]
##   }
##
## Guarantees:
##   - Writes are atomic (temp file + rename), so a crash cannot truncate data.
##   - A corrupt file is copied aside, never overwritten silently.
##   - One malformed profile never prevents the other profiles from loading.
##   - Profiles survive app restarts (data lives in `user://`, outside the APK).

signal profiles_changed
signal active_profile_changed(profile_id: String)
signal save_failed(error: String)

const MAX_PROFILES := 20
const DEFAULT_ROOT_DIR := "user://profiles"
const STORAGE_FILE := "companions.json"
const SEED_NAME := "Mira"

## Directory holding `companions.json`. Overridden by tests.
var root_dir: String = DEFAULT_ROOT_DIR

## Last error message, empty when everything is fine.
var last_error: String = ""
## True when the previous save file was damaged and got copied aside.
var recovered_from_corruption: bool = false
## True once load() has run.
var loaded: bool = false

var _profiles: Array = []
var _active_id: String = ""


func _ready() -> void:
	if not loaded:
		load_from_disk()


func storage_path() -> String:
	return root_dir.path_join(STORAGE_FILE)


# --------------------------------------------------------------------------
# Load / save
# --------------------------------------------------------------------------

## Loads profiles from disk. Always leaves the store in a usable state:
## a missing file or a damaged file results in a seeded default companion.
func load_from_disk() -> bool:
	_profiles = []
	_active_id = ""
	last_error = ""
	recovered_from_corruption = false

	var path := storage_path()
	var read_result := JsonFile.read(path)
	# Messages survive the save() calls below, which reset last_error.
	var messages: Array = []

	if read_result["corrupt"]:
		var backup_path := JsonFile.backup(path)
		recovered_from_corruption = true
		var message := "Recovered from a damaged save file."
		if not backup_path.is_empty():
			message += " Backup: %s" % backup_path
		messages.append(message)

	var data: Variant = read_result["data"]
	if read_result["ok"] and data is Dictionary:
		_load_from_dict(data)
	elif read_result["exists"] and not read_result["corrupt"]:
		messages.append(str(read_result["error"]))

	loaded = true

	# Seed only on a genuine first launch (or after recovering a damaged file).
	# An existing save file with zero profiles means the user deleted them all,
	# and that choice has to survive a restart.
	if _profiles.is_empty() and (not read_result["exists"] or read_result["corrupt"]):
		_seed_default()

	if not _active_id_is_valid():
		_active_id = _profiles[0].id if not _profiles.is_empty() else ""

	# A first launch (or a recovered file) is persisted immediately so the
	# companion the user sees is the companion that exists on disk.
	if not FileAccess.file_exists(path) or recovered_from_corruption:
		save()

	last_error = "\n".join(messages)
	profiles_changed.emit()
	active_profile_changed.emit(_active_id)
	return last_error.is_empty() or recovered_from_corruption


## Writes the current state to disk atomically.
func save() -> bool:
	var payload := {
		"schema": CompanionProfile.SCHEMA_VERSION,
		"active_id": _active_id,
		"profiles": [],
	}
	for profile in _profiles:
		payload["profiles"].append(profile.to_dict())

	var result := JsonFile.write_atomic(storage_path(), payload)
	if not result["ok"]:
		last_error = str(result["error"])
		save_failed.emit(last_error)
		return false

	last_error = ""
	return true


func _load_from_dict(data: Dictionary) -> void:
	var raw_profiles: Variant = data.get("profiles", [])
	if not (raw_profiles is Array):
		last_error = "Save file has no profile list."
		return

	var seen_ids := {}
	for entry in raw_profiles:
		if not (entry is Dictionary):
			continue
		if _profiles.size() >= MAX_PROFILES:
			break
		var profile := CompanionProfile.from_dict(entry)
		# Repair duplicate ids so selection and deletion stay unambiguous.
		while seen_ids.has(profile.id):
			profile.id = CompanionProfile.generate_id()
		seen_ids[profile.id] = true
		_profiles.append(profile)

	var stored_active := str(data.get("active_id", ""))
	_active_id = stored_active if seen_ids.has(stored_active) else ""


func _seed_default() -> void:
	var profile := CompanionProfile.create_new(SEED_NAME)
	_profiles.append(profile)
	_active_id = profile.id


# --------------------------------------------------------------------------
# Queries
# --------------------------------------------------------------------------

## All profiles, in creation order.
func list_profiles() -> Array:
	return _profiles.duplicate()


func count() -> int:
	return _profiles.size()


func has_profile(profile_id: String) -> bool:
	return _index_of(profile_id) >= 0


## Returns the profile or null.
func get_profile(profile_id: String) -> CompanionProfile:
	var index := _index_of(profile_id)
	return null if index < 0 else _profiles[index]


func get_active_id() -> String:
	return _active_id


## Returns the active profile, or null when there are no profiles at all.
func get_active() -> CompanionProfile:
	var profile := get_profile(_active_id)
	if profile != null:
		return profile
	return _profiles[0] if not _profiles.is_empty() else null


func can_create_more() -> bool:
	return _profiles.size() < MAX_PROFILES


# --------------------------------------------------------------------------
# Mutations (each one persists immediately)
# --------------------------------------------------------------------------

## Creates a companion. Returns the new profile, or null when the limit is hit
## or the name is invalid.
func create_profile(new_name: String, patch: Dictionary = {}) -> CompanionProfile:
	if not can_create_more():
		last_error = "You can keep at most %d companions." % MAX_PROFILES
		return null

	var trimmed := new_name.strip_edges()
	if trimmed.length() < CompanionProfile.MIN_NAME_LENGTH:
		last_error = "Please enter a name."
		return null

	var profile := CompanionProfile.create_new(trimmed)
	if not patch.is_empty():
		profile.apply_patch(patch)
	# Uniqueness is applied last so a patched name is covered too.
	profile.display_name = unique_name(profile.display_name)

	_profiles.append(profile)
	if _active_id.is_empty():
		_active_id = profile.id

	_commit()
	active_profile_changed.emit(_active_id)
	return profile


## Applies a partial update to an existing profile.
func update_profile(profile_id: String, patch: Dictionary) -> bool:
	var profile := get_profile(profile_id)
	if profile == null:
		last_error = "Companion not found."
		return false

	if patch.has("display_name"):
		var requested := str(patch["display_name"]).strip_edges()
		if requested.length() < CompanionProfile.MIN_NAME_LENGTH:
			last_error = "Please enter a name."
			return false
		patch["display_name"] = unique_name(requested, profile_id)

	profile.apply_patch(patch)
	_commit()
	return true


## Deletes one companion. The active companion moves to the next remaining one.
func delete_profile(profile_id: String) -> bool:
	var index := _index_of(profile_id)
	if index < 0:
		last_error = "Companion not found."
		return false

	_profiles.remove_at(index)

	var active_moved := false
	if _active_id == profile_id or not _active_id_is_valid():
		_active_id = _profiles[0].id if not _profiles.is_empty() else ""
		active_moved = true

	_commit()
	if active_moved:
		active_profile_changed.emit(_active_id)
	return true


## Deletes every companion and starts again from an empty store.
## Used by the privacy screen ("delete all data").
func delete_all_profiles() -> bool:
	_profiles = []
	_active_id = ""
	_commit()
	active_profile_changed.emit("")
	return true


## Makes a profile active. Returns false when the id is unknown.
func set_active(profile_id: String) -> bool:
	if not has_profile(profile_id):
		last_error = "Companion not found."
		return false
	if _active_id == profile_id:
		return true
	_active_id = profile_id
	save()
	active_profile_changed.emit(_active_id)
	return true


## Turns `base` into a name that no other profile uses, e.g. "Mira (2)".
## `ignore_id` lets a profile keep its own name while being edited.
func unique_name(base: String, ignore_id: String = "") -> String:
	var cleaned := base.strip_edges()
	if cleaned.is_empty():
		cleaned = "Companion"
	if cleaned.length() > CompanionProfile.MAX_NAME_LENGTH:
		cleaned = cleaned.substr(0, CompanionProfile.MAX_NAME_LENGTH).strip_edges()

	if not _name_taken(cleaned, ignore_id):
		return cleaned

	var suffix_index := 2
	while suffix_index < 100:
		var suffix := " (%d)" % suffix_index
		var room := CompanionProfile.MAX_NAME_LENGTH - suffix.length()
		var candidate := cleaned.substr(0, maxi(1, room)).strip_edges() + suffix
		if not _name_taken(candidate, ignore_id):
			return candidate
		suffix_index += 1
	return cleaned


func _name_taken(candidate: String, ignore_id: String) -> bool:
	for profile in _profiles:
		if profile.id == ignore_id:
			continue
		if profile.display_name.to_lower() == candidate.to_lower():
			return true
	return false


func _commit() -> void:
	save()
	profiles_changed.emit()


func _index_of(profile_id: String) -> int:
	for index in _profiles.size():
		if _profiles[index].id == profile_id:
			return index
	return -1


func _active_id_is_valid() -> bool:
	return not _active_id.is_empty() and has_profile(_active_id)
