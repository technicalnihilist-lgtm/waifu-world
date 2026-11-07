extends TestCase
## Settings persistence, graphics presets, lighting maths and room data.

var _dir: String = ""
var _settings: SettingsRepository


func before() -> void:
	_dir = TestCase.temp_dir("settings")
	_settings = SettingsRepository.new()
	_settings.root_dir = _dir


func after() -> void:
	_settings.free()
	TestCase.purge_dir(_dir)


func run(_tree: SceneTree) -> void:
	await _tree.process_frame

	# --- defaults --------------------------------------------------------
	_settings.load_from_disk()
	equal(_settings.quality_level(), int(SettingsRepository.DEFAULTS["quality_level"]), "default quality level")
	approx(_settings.camera_distance(), float(SettingsRepository.DEFAULTS["camera_distance"]), 0.001, "default camera distance")
	equal(_settings.room_id(), "bedroom", "default room")

	# --- set and persist -------------------------------------------------
	_settings.set_quality_level(3)
	_settings.set_time_of_day(9.5)
	_settings.set_camera_distance(4.4)
	_settings.set_room_id("apartment")
	_settings.set_value("auto_day_night", true)

	var reloaded := SettingsRepository.new()
	reloaded.root_dir = _dir
	reloaded.load_from_disk()
	equal(reloaded.quality_level(), 3, "quality level survives a restart")
	approx(reloaded.time_of_day(), 9.5, 0.001, "time of day survives a restart")
	approx(reloaded.camera_distance(), 4.4, 0.001, "camera distance survives a restart")
	equal(reloaded.room_id(), "apartment", "room survives a restart")
	equal(bool(reloaded.get_value("auto_day_night", false)), true, "auto cycle flag survives a restart")
	reloaded.free()

	# --- clamping --------------------------------------------------------
	_settings.set_quality_level(99)
	equal(_settings.quality_level(), QualityPresets.LEVEL_COUNT - 1, "quality level clamps high")
	_settings.set_quality_level(-5)
	equal(_settings.quality_level(), 0, "quality level clamps low")
	_settings.set_time_of_day(48.0)
	approx(_settings.time_of_day(), SettingsRepository.TIME_OF_DAY_MAX, 0.001, "time of day clamps")
	_settings.set_camera_distance(100.0)
	approx(_settings.camera_distance(), SettingsRepository.CAMERA_DISTANCE_MAX, 0.001, "camera distance clamps")

	# --- unknown keys are ignored ----------------------------------------
	_settings.set_value("not_a_real_setting", 42)
	check(_settings.get_value("not_a_real_setting", null) == null, "unknown setting is not stored")

	# --- reset -----------------------------------------------------------
	_settings.reset_to_defaults()
	equal(_settings.quality_level(), int(SettingsRepository.DEFAULTS["quality_level"]), "reset restores defaults")

	# --- corrupt settings file -------------------------------------------
	var corrupt := SettingsRepository.new()
	var corrupt_dir := TestCase.temp_dir("settings_corrupt")
	corrupt.root_dir = corrupt_dir
	DirAccess.make_dir_recursive_absolute(corrupt_dir)
	TestCase.write_text(corrupt.storage_path(), "not json at all")
	corrupt.load_from_disk()
	equal(corrupt.quality_level(), int(SettingsRepository.DEFAULTS["quality_level"]), "corrupt settings fall back to defaults")
	corrupt.free()
	TestCase.purge_dir(corrupt_dir)

	# --- graphics presets -------------------------------------------------
	var previous_detail := -1
	var previous_distance := -1.0
	for level in QualityPresets.LEVEL_COUNT:
		var preset := QualityPresets.for_level(level)
		equal(int(preset["level"]), level, "preset reports its own level")
		check(str(preset["name"]) == QualityPresets.LEVELS[level], "preset name matches its index")
		check(int(preset["mesh_detail"]) >= previous_detail, "mesh detail never decreases with quality")
		check(float(preset["shadow_max_distance"]) >= previous_distance, "shadow distance never decreases with quality")
		check(int(preset["realtime_lights"]) >= 1, "every preset allows at least one light")
		previous_detail = int(preset["mesh_detail"])
		previous_distance = float(preset["shadow_max_distance"])

	check(not bool(QualityPresets.for_level(0)["shadows"]), "low quality disables shadows")
	check(bool(QualityPresets.for_level(1)["shadows"]), "medium quality enables shadows")
	equal(QualityPresets.for_level(99)["name"], "ultra", "out-of-range preset clamps to ultra")
	equal(QualityPresets.next_level(3), 0, "quality cycles back to low")
	equal(QualityPresets.next_level(0), 1, "quality advances to medium")
	equal(QualityPresets.level_name(2), "High", "quality level names are readable")

	# --- lighting maths ---------------------------------------------------
	approx(LightingController.sun_elevation(12.0), 1.0, 0.001, "sun is highest at noon")
	approx(LightingController.sun_elevation(0.0), -1.0, 0.001, "sun is lowest at midnight")
	approx(LightingController.sun_elevation(6.0), 0.0, 0.001, "sun crosses the horizon at 06:00")
	approx(LightingController.daylight_factor(12.0), 1.0, 0.001, "noon is full daylight")
	approx(LightingController.daylight_factor(0.0), 0.0, 0.001, "midnight has no daylight")
	check(LightingController.is_night(0.0), "midnight is night")
	check(not LightingController.is_night(12.0), "noon is not night")
	check(
		LightingController.ambient_energy(12.0) > LightingController.ambient_energy(0.0),
		"ambient light is stronger by day"
	)
	check(
		LightingController.sun_energy(12.0) > LightingController.sun_energy(0.0),
		"the sun is brighter than the moon"
	)
	check(
		LightingController.window_energy(12.0) > LightingController.window_energy(0.0),
		"window daylight is stronger by day"
	)
	equal(LightingController.format_clock(20.5), "20:30", "clock formatting")
	equal(LightingController.format_clock(0.0), "00:00", "clock formatting at midnight")
	equal(LightingController.format_clock(24.0), "00:00", "clock wraps at 24:00")

	var noon_colour := LightingController.sun_color(12.0)
	var sunset_colour := LightingController.sun_color(17.0)
	check(sunset_colour.g < noon_colour.g, "late afternoon light is warmer than noon light")
	check(LightingController.sun_color(0.0).b > LightingController.sun_color(0.0).r, "moonlight is blue")

	# --- room presets -----------------------------------------------------
	for room_id in RoomPresets.room_ids():
		check(RoomPresets.has_room(room_id), "room '%s' is registered" % room_id)
		var room := RoomPresets.get_room(room_id)
		var items: Array = room["items"]
		check(items.size() >= 15, "room '%s' has a reasonable amount of furniture" % room_id)
		check(not str(room["display_name"]).is_empty(), "room '%s' has a display name" % room_id)
		var position_value: Variant = room["companion_position"]
		check(position_value is Vector3, "room '%s' defines a companion position" % room_id)
		var names := {}
		var has_window := false
		var has_lamp := false
		for item in items:
			check(item.has("name") and item.has("pos") and item.has("size"), "room '%s' item is complete" % room_id)
			names[item["name"]] = true
			if bool(item.get("window", false)):
				has_window = true
			if bool(item.get("lamp", false)):
				has_lamp = true
			check(
				Color.html_is_valid(str(item["color"])),
				"room '%s' item '%s' has a valid colour" % [room_id, str(item["name"])]
			)
			var item_pos: Vector3 = item["pos"]
			check(
				absf(item_pos.x) <= 3.0 and absf(item_pos.z) <= 3.0,
				"room '%s' item '%s' sits inside the room" % [room_id, str(item["name"])]
			)
		equal(names.size(), items.size(), "room '%s' node names are unique" % room_id)
		check(has_window, "room '%s' has a window for daylight" % room_id)
		check(has_lamp, "room '%s' has a practical light" % room_id)

	check(not RoomPresets.has_room("spaceship"), "unknown rooms are reported as missing")
	var fallback := RoomPresets.get_room("spaceship")
	equal(str(fallback["display_name"]), "Modern Bedroom", "unknown room falls back to the bedroom")
