extends TestCase
## Live weather: parsing a real Open-Meteo response, failure handling, cache,
## and the credits screen that satisfies the attribution requirement.

const FIXTURE := "res://tests/fixtures/open_meteo_mumbai.json"

var _service: WeatherService
var _lighting: LightingController


func before() -> void:
	_service = WeatherService.new()


func after() -> void:
	if is_instance_valid(_service):
		_service.free()


func run(tree: SceneTree) -> void:
	await tree.process_frame

	# --- parsing a real captured response --------------------------------
	var raw := FileAccess.get_file_as_string(FIXTURE)
	check(not raw.is_empty(), "the captured Open-Meteo response is present")
	var json := JSON.new()
	check(json.parse(raw) == OK, "the captured response is valid JSON")

	var snapshot := WeatherService.parse_open_meteo(json.data)
	check(bool(snapshot["ok"]), "a real Open-Meteo payload parses")
	equal(str(snapshot["source"]), "open-meteo", "the source is recorded")
	check(float(snapshot["temperature_c"]) > -60.0 and float(snapshot["temperature_c"]) < 60.0,
		"temperature is in a sane range (%.1f C)" % float(snapshot["temperature_c"]))
	check(float(snapshot["cloud_cover"]) >= 0.0 and float(snapshot["cloud_cover"]) <= 100.0,
		"cloud cover is a percentage")
	check(str(snapshot["observed_at"]) != "", "the observation time is kept")
	check(str(snapshot["description"]) != "", "a human description is produced")
	check(WeatherService.CONDITION_BY_CODE.values().has(str(snapshot["condition"])),
		"the condition is one of the known room conditions")

	# --- WMO code mapping ------------------------------------------------
	equal(WeatherService.condition_for_code(0), "clear", "code 0 is clear")
	equal(WeatherService.condition_for_code(3), "overcast", "code 3 is overcast")
	equal(WeatherService.condition_for_code(63), "rain", "code 63 is rain")
	equal(WeatherService.condition_for_code(75), "snow", "code 75 is snow")
	equal(WeatherService.condition_for_code(95), "storm", "code 95 is a storm")
	equal(WeatherService.condition_for_code(45), "fog", "code 45 is fog")
	equal(WeatherService.condition_for_code(1234), "unknown", "unknown codes are reported as unknown")
	equal(WeatherService.description_for_condition("rain"), "Rain", "descriptions are readable")

	# --- hostile payloads -------------------------------------------------
	var broken := WeatherService.parse_open_meteo("not a dictionary")
	check(not bool(broken["ok"]), "a non-object payload fails cleanly")
	check(not str(broken["error"]).is_empty(), "the failure explains itself")

	var empty := WeatherService.parse_open_meteo({})
	check(not bool(empty["ok"]), "a payload without 'current' fails cleanly")

	var no_temp := WeatherService.parse_open_meteo({"current": {"weather_code": 0}})
	check(not bool(no_temp["ok"]), "a payload without temperature fails cleanly")

	# --- summary line ------------------------------------------------------
	_service.snapshot = snapshot
	_service.location_label = "Mumbai"
	check(_service.summary().contains("Mumbai"), "the summary names the location")
	check(_service.summary().contains("C"), "the summary shows a temperature")
	_service.snapshot = WeatherService.empty_snapshot()
	equal(_service.summary(), "Weather offline", "no data reads as offline")

	# --- cache round trip --------------------------------------------------
	_service.snapshot = snapshot
	_service.save_cache()
	var reloaded := WeatherService.new()
	reloaded.load_cache()
	check(bool(reloaded.snapshot["ok"]), "the last reading survives a restart")
	approx(float(reloaded.snapshot["temperature_c"]), float(snapshot["temperature_c"]), 0.01,
		"the cached temperature matches")
	reloaded.free()

	# --- weather actually changes the room lighting -----------------------
	_lighting = LightingController.new()
	tree.root.add_child(_lighting)
	await tree.process_frame

	_lighting.set_weather({})
	approx(_lighting.weather_sun_factor(), 1.0, 0.001, "no weather data leaves lighting untouched")
	approx(_lighting.cloud_factor(), 0.0, 0.001, "no weather data means no cloud")

	_lighting.set_weather({"ok": true, "cloud_cover": 0.0, "condition": "clear"})
	approx(_lighting.weather_sun_factor(), 1.0, 0.001, "a clear sky does not dim the sun")

	_lighting.set_weather({"ok": true, "cloud_cover": 100.0, "condition": "overcast"})
	approx(_lighting.cloud_factor(), 1.0, 0.001, "full cloud cover is detected")
	check(_lighting.weather_sun_factor() < 0.6, "overcast dims the sun (%.2f)" % _lighting.weather_sun_factor())

	_lighting.set_weather({"ok": true, "cloud_cover": 100.0, "condition": "storm"})
	var storm_factor := _lighting.weather_sun_factor()
	check(storm_factor < 0.45, "a storm darkens the room further (%.2f)" % storm_factor)
	equal(_lighting.weather_condition(), "storm", "the condition is exposed for the UI")

	_lighting.set_weather({"ok": false, "cloud_cover": 100.0, "condition": "rain"})
	approx(_lighting.weather_sun_factor(), 1.0, 0.001, "a failed reading does not fake weather")

	_lighting.queue_free()
	await tree.process_frame

	# --- credits screen (Open-Meteo requires attribution) ------------------
	var packed: PackedScene = load("res://scenes/ui/settings_panel.tscn")
	not_null(packed, "the settings scene loads")
	var panel := packed.instantiate() as Control
	panel.setup({"quality_level": 1, "time_of_day": 12.0, "room_id": "bedroom",
		"camera_distance": 3.8, "capabilities": {}, "avatar_notice": "",
		"weather_enabled": false, "weather_summary": "Weather offline",
		"weather_error": "", "weather_location": "Mumbai",
		"weather_latitude": 19.076, "weather_longitude": 72.8777})
	tree.root.add_child(panel)
	await tree.process_frame

	var texts := _collect_text(panel)
	check(texts.contains("Credits"), "settings has a Credits section")
	check(texts.contains("Open-Meteo"), "the weather provider is credited")
	check(texts.contains("Godot Engine 4.3"), "the engine is credited")
	check(texts.contains("CC BY 4.0"), "the weather licence is named")
	check(texts.contains("Live weather"), "settings exposes the weather section")

	panel.queue_free()
	await tree.process_frame


func _collect_text(node: Node) -> String:
	var buffer := ""
	if node is Label:
		buffer += (node as Label).text + "\n"
	if node is CheckButton:
		buffer += (node as CheckButton).text + "\n"
	if node is Button and not (node is CheckButton):
		buffer += (node as Button).text + "\n"
	for child in node.get_children():
		buffer += _collect_text(child)
	return buffer
