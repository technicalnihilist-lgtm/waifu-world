extends TestCase
## Persistence layer: atomic writes, corrupt-file recovery, JSON round trips.

var _dir: String = ""


func before() -> void:
	_dir = TestCase.temp_dir("json")


func after() -> void:
	TestCase.purge_dir(_dir)


func run(_tree: SceneTree) -> void:
	await _tree.process_frame

	# --- round trip ------------------------------------------------------
	var path := _dir.path_join("sample.json")
	var payload := {"schema": 1, "name": "Mira", "list": [1, 2, 3], "nested": {"a": true}}
	var write_result := JsonFile.write_atomic(path, payload)
	check(bool(write_result["ok"]), "write_atomic reports success")
	check(FileAccess.file_exists(path), "file exists after write")
	check(not FileAccess.file_exists(path + ".tmp"), "temp file is gone after rename")

	var read_result := JsonFile.read(path)
	check(bool(read_result["ok"]), "read reports success")
	check(bool(read_result["exists"]), "read reports the file exists")
	equal(str(read_result["data"].get("name", "")), "Mira", "string survives round trip")
	equal((read_result["data"].get("list", []) as Array).size(), 3, "array survives round trip")
	equal(bool(read_result["data"].get("nested", {}).get("a", false)), true, "nested bool survives round trip")

	# --- overwrite -------------------------------------------------------
	write_result = JsonFile.write_atomic(path, {"name": "Nova"})
	check(bool(write_result["ok"]), "second write succeeds")
	read_result = JsonFile.read(path)
	equal(str(read_result["data"].get("name", "")), "Nova", "overwrite replaces content")

	# --- missing file ----------------------------------------------------
	read_result = JsonFile.read(_dir.path_join("does_not_exist.json"))
	check(not bool(read_result["ok"]), "missing file reports failure")
	check(not bool(read_result["exists"]), "missing file reports exists=false")
	check(not bool(read_result["corrupt"]), "missing file is not flagged corrupt")

	# --- corrupt file ----------------------------------------------------
	var corrupt_path := _dir.path_join("broken.json")
	TestCase.write_text(corrupt_path, "{ this is not json ][")
	read_result = JsonFile.read(corrupt_path)
	check(not bool(read_result["ok"]), "corrupt file reports failure")
	check(bool(read_result["corrupt"]), "corrupt file is flagged")
	var backup := JsonFile.backup(corrupt_path)
	check(not backup.is_empty(), "backup path returned for corrupt file")
	check(FileAccess.file_exists(backup), "backup file written")
	check(FileAccess.file_exists(corrupt_path), "original corrupt file is left in place")

	# --- empty file ------------------------------------------------------
	var empty_path := _dir.path_join("empty.json")
	TestCase.write_text(empty_path, "   ")
	read_result = JsonFile.read(empty_path)
	check(bool(read_result["corrupt"]), "empty file is flagged corrupt")

	# --- directory creation ---------------------------------------------
	var nested_dir := _dir.path_join("a/b/c")
	check(JsonFile.ensure_dir(nested_dir), "ensure_dir creates nested directories")
	check(DirAccess.dir_exists_absolute(nested_dir), "nested directory exists")
	check(JsonFile.ensure_dir(nested_dir), "ensure_dir is idempotent")

	# --- writes into a directory that does not exist yet ------------------
	write_result = JsonFile.write_atomic(nested_dir.path_join("auto.json"), {"ok": 1})
	check(bool(write_result["ok"]), "write creates missing parent directories")
