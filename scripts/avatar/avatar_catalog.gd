class_name AvatarCatalog
extends RefCounted
## Discovers replaceable avatar assets (GLB / glTF).
##
## Two discovery paths, because they have different constraints on Android:
##
## 1. Bundled avatars — `res://assets/avatars/avatars.json`
##    A `.glb` inside an exported APK is compiled into an imported scene, so the
##    source file may not be listable at runtime. A plain JSON manifest ships
##    alongside and names each avatar and its `res://` scene path.
##
## 2. User-installed avatars — `user://avatars/`
##    Real files on disk. Each `<name>.glb` may have a sidecar `<name>.json`
##    with the same fields as a manifest entry. These are imported at runtime
##    through GLTFDocument, so no editor import step is needed.
##
## A descriptor is a plain dictionary so it can be shown in UI and tested:
##   { id, path, source, display_name, author, license, format,
##     height_meters, idle_animation, has_manifest, valid, problem }

const SUPPORTED_EXTENSIONS := ["glb", "gltf"]
const MANIFEST_PATH := "res://assets/avatars/avatars.json"
const USER_AVATAR_DIR := "user://avatars"

const DEFAULT_DESCRIPTOR := {
	"id": "",
	"path": "",
	"source": "",
	"display_name": "Avatar",
	"author": "",
	"license": "",
	"format": "",
	"height_meters": 1.65,
	"idle_animation": "Idle",
	"has_manifest": false,
	"valid": false,
	"problem": "No avatar file.",
}


## Returns every descriptor this build can offer: bundled first, then user files.
static func list_all() -> Array:
	var descriptors: Array = []
	descriptors.append_array(list_bundled())
	descriptors.append_array(list_user_installed())
	return descriptors


## Reads the bundled manifest. Missing or malformed entries are skipped and
## reported through the descriptor's `problem` field instead of crashing.
static func list_bundled() -> Array:
	var descriptors: Array = []
	var result := JsonFile.read(MANIFEST_PATH)
	if not result["ok"]:
		return descriptors

	var data: Variant = result["data"]
	var entries: Variant = data.get("avatars", []) if data is Dictionary else data
	if not (entries is Array):
		return descriptors

	for entry in entries:
		if not (entry is Dictionary):
			continue
		var descriptor := DEFAULT_DESCRIPTOR.duplicate(true)
		descriptor["source"] = MANIFEST_PATH.get_base_dir()
		descriptor["has_manifest"] = true
		for key in entry.keys():
			descriptor[key] = entry[key]
		descriptor = _finalise(descriptor)
		if descriptor["valid"]:
			descriptors.append(descriptor)
	return descriptors


## Scans `user://avatars/` for `.glb` / `.gltf` files with optional sidecars.
static func list_user_installed(dir_path: String = USER_AVATAR_DIR) -> Array:
	var descriptors: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return descriptors

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and is_supported_file(file_name):
			descriptors.append(descriptor_for(dir_path.path_join(file_name)))
		file_name = dir.get_next()
	dir.list_dir_end()
	return descriptors


static func is_supported_file(file_name: String) -> bool:
	var extension := file_name.get_extension().to_lower()
	return SUPPORTED_EXTENSIONS.has(extension)


## Builds a descriptor for one avatar file, merging a sidecar manifest if present.
static func descriptor_for(path: String) -> Dictionary:
	var descriptor := DEFAULT_DESCRIPTOR.duplicate(true)
	descriptor["path"] = path
	descriptor["source"] = path.get_base_dir()
	descriptor["id"] = path.get_file().get_basename()
	descriptor["format"] = path.get_extension().to_lower()

	var sidecar := read_sidecar(path)
	if not sidecar.is_empty():
		descriptor["has_manifest"] = true
		for key in sidecar.keys():
			descriptor[key] = sidecar[key]
		# The file path always wins over whatever the sidecar claims.
		descriptor["path"] = path
		descriptor["format"] = path.get_extension().to_lower()

	return _finalise(descriptor)


## Reads `<name>.json` or `<name>.glb.json` next to the avatar file.
static func read_sidecar(path: String) -> Dictionary:
	var candidates := [path.get_basename() + ".json", path + ".json"]
	for candidate in candidates:
		var result := JsonFile.read(candidate)
		if result["ok"] and result["data"] is Dictionary:
			return result["data"]
	return {}


## Finds a descriptor by id across all sources, or {} when unknown.
static func find_by_id(avatar_id: String) -> Dictionary:
	if avatar_id.is_empty():
		return {}
	for descriptor in list_all():
		if str(descriptor["id"]) == avatar_id:
			return descriptor
	return {}


static func _finalise(descriptor: Dictionary) -> Dictionary:
	var path := str(descriptor.get("path", ""))
	descriptor["id"] = str(descriptor.get("id", ""))
	descriptor["display_name"] = str(descriptor.get("display_name", descriptor["id"])).strip_edges()
	if str(descriptor["display_name"]).is_empty():
		descriptor["display_name"] = str(descriptor["id"])
	descriptor["height_meters"] = clampf(float(descriptor.get("height_meters", 1.65)), 0.8, 2.4)
	descriptor["idle_animation"] = str(descriptor.get("idle_animation", "Idle"))

	if path.is_empty():
		descriptor["valid"] = false
		descriptor["problem"] = "Avatar entry has no path."
		return descriptor

	var extension := path.get_extension().to_lower()
	if not SUPPORTED_EXTENSIONS.has(extension):
		descriptor["valid"] = false
		descriptor["problem"] = "Unsupported format '.%s' (use GLB or glTF)." % extension
		return descriptor

	if path.begins_with("res://"):
		# An imported .glb becomes a PackedScene; either form is acceptable.
		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
			descriptor["valid"] = false
			descriptor["problem"] = "Bundled avatar is missing: %s" % path
			return descriptor
	elif not FileAccess.file_exists(path):
		descriptor["valid"] = false
		descriptor["problem"] = "Avatar file is missing: %s" % path
		return descriptor

	descriptor["valid"] = true
	descriptor["problem"] = ""
	return descriptor
