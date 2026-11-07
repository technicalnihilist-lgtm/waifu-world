class_name JsonFile
extends RefCounted
## Safe JSON persistence helpers.
##
## Every write goes to a temporary file first and is then renamed over the
## target, so a crash or a killed app never leaves a half-written save file.
## Reads never throw: they return a result dictionary the caller can inspect.

## Reads and parses a JSON file.
## Returns {ok: bool, data: Variant, error: String, exists: bool, corrupt: bool}
static func read(path: String) -> Dictionary:
	var result := {
		"ok": false,
		"data": null,
		"error": "",
		"exists": false,
		"corrupt": false,
	}
	if not FileAccess.file_exists(path):
		result["error"] = "missing file: %s" % path
		return result

	result["exists"] = true
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result["error"] = "cannot open %s (error %d)" % [path, FileAccess.get_open_error()]
		return result

	var text := file.get_as_text()
	file.close()

	if text.strip_edges().is_empty():
		result["error"] = "empty file: %s" % path
		result["corrupt"] = true
		return result

	var json := JSON.new()
	var parse_error := json.parse(text)
	if parse_error != OK:
		result["error"] = "parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		result["corrupt"] = true
		return result

	result["ok"] = true
	result["data"] = json.data
	return result


## Writes `data` as indented JSON using a temp file + rename.
## Returns {ok: bool, error: String}
static func write_atomic(path: String, data: Variant) -> Dictionary:
	var dir := path.get_base_dir()
	if not dir.is_empty() and not ensure_dir(dir):
		return {"ok": false, "error": "cannot create directory: %s" % dir}

	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return {
			"ok": false,
			"error": "cannot write %s (error %d)" % [temp_path, FileAccess.get_open_error()],
		}

	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file.close()

	var rename_error := DirAccess.rename_absolute(temp_path, path)
	if rename_error != OK:
		# Some platforms refuse to rename over an existing file.
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
			rename_error = DirAccess.rename_absolute(temp_path, path)
	if rename_error != OK:
		DirAccess.remove_absolute(temp_path)
		return {"ok": false, "error": "cannot replace %s (error %d)" % [path, rename_error]}

	return {"ok": true, "error": ""}


## Creates `dir_path` (recursively) if it does not exist yet.
static func ensure_dir(dir_path: String) -> bool:
	if dir_path.is_empty():
		return false
	if DirAccess.dir_exists_absolute(dir_path):
		return true
	return DirAccess.make_dir_recursive_absolute(dir_path) == OK


## Copies a damaged file aside so the user's data is never silently destroyed.
## Returns the backup path, or "" when the file does not exist.
static func backup(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var backup_path := "%s.corrupt-%s" % [path, stamp]
	if DirAccess.copy_absolute(path, backup_path) != OK:
		return ""
	return backup_path
