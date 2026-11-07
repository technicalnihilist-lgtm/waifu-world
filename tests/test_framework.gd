class_name TestCase
extends RefCounted
## Minimal, dependency-free test harness.
##
## Suites are plain scripts extending TestCase and implementing `run()`. The
## runner calls them one at a time, prints a per-suite result and finally exits
## with a non-zero code when anything failed, so CI can gate on it.
##
## Usage from a shell:
##   godot --headless --path . tests/test_runner.tscn

var suite_name: String = "suite"

var _passed: int = 0
var _failed: int = 0
var _failures: Array = []


func before() -> void:
	pass


func after() -> void:
	pass


## Implemented by every suite. Must contain at least one `await` so the runner
## can treat it as a coroutine uniformly.
func run(_tree: SceneTree) -> void:
	pass


func run_all(tree: SceneTree) -> void:
	suite_name = get_script().resource_path.get_file().get_basename() if get_script() != null else "suite"
	before()
	await run(tree)
	after()

	var status := "PASS" if _failed == 0 else "FAIL"
	print("[%s] %-34s %3d passed, %3d failed" % [status, suite_name, _passed, _failed])
	for failure in _failures:
		print("        - %s" % failure)


func passed_count() -> int:
	return _passed


func failed_count() -> int:
	return _failed


func failures() -> Array:
	return _failures.duplicate()


# --------------------------------------------------------------------------
# Assertions
# --------------------------------------------------------------------------

func check(condition: bool, message: String) -> bool:
	if condition:
		_passed += 1
		return true
	_failed += 1
	_failures.append(message)
	return false


func equal(actual: Variant, expected: Variant, message: String) -> bool:
	var ok := false
	if actual is float or expected is float:
		ok = absf(float(actual) - float(expected)) < 0.0001
	else:
		ok = actual == expected
	return check(ok, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func approx(actual: float, expected: float, tolerance: float, message: String) -> bool:
	return check(
		absf(actual - expected) <= tolerance,
		"%s (expected %.4f +/- %.4f, got %.4f)" % [message, expected, tolerance, actual]
	)


func not_null(value: Variant, message: String) -> bool:
	return check(value != null, "%s (got null)" % message)


func is_null(value: Variant, message: String) -> bool:
	return check(value == null, "%s (expected null, got %s)" % [message, str(value)])


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

## Creates a unique scratch directory under user:// for a suite.
static func temp_dir(prefix: String) -> String:
	var dir := "user://test_tmp/%s_%d" % [prefix, Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


static func purge_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			purge_dir(full)
			DirAccess.remove_absolute(full)
		else:
			DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_path)


static func write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true
