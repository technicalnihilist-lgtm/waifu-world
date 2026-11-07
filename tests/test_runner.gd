extends Node
## Headless test runner.
##
##   godot --headless --path . tests/test_runner.tscn
##
## Exits with code 0 when every assertion passed, 1 otherwise, so CI can gate on
## the result. No third-party test framework is required.

const SUITES := [
	preload("res://tests/suites/test_json_file.gd"),
	preload("res://tests/suites/test_companion_profile.gd"),
	preload("res://tests/suites/test_companion_repository.gd"),
	preload("res://tests/suites/test_settings_and_quality.gd"),
	preload("res://tests/suites/test_avatar.gd"),
	preload("res://tests/suites/test_main_scene.gd"),
]

var _total_passed: int = 0
var _total_failed: int = 0
var _suite_failures: Array = []


var _temp_root: String = ""


func _ready() -> void:
	# Point the autoload singletons at a scratch directory so tests never touch
	# the player's real save data.
	_temp_root = TestCase.temp_dir("autoload")
	Companions.root_dir = _temp_root
	AppSettings.root_dir = _temp_root
	Companions.load_from_disk()
	AppSettings.load_from_disk()

	await get_tree().process_frame
	print("")
	print("Waifu World test run — Godot %s" % Engine.get_version_info().get("string", "?"))
	print("============================================================")

	for suite_script in SUITES:
		var suite: TestCase = suite_script.new()
		await suite.run_all(get_tree())
		_total_passed += suite.passed_count()
		_total_failed += suite.failed_count()
		if suite.failed_count() > 0:
			_suite_failures.append(suite.suite_name)

	print("============================================================")
	print("TOTAL: %d passed, %d failed across %d suites" % [_total_passed, _total_failed, SUITES.size()])
	if _total_failed > 0:
		print("FAILED SUITES: %s" % ", ".join(_suite_failures))
	print("RESULT: %s" % ("PASS" if _total_failed == 0 else "FAIL"))
	print("")

	TestCase.purge_dir(_temp_root)
	get_tree().quit(0 if _total_failed == 0 else 1)
