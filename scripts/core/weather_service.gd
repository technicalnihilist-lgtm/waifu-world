class_name WeatherService
extends Node
## Live weather for the companion room, from Open-Meteo (no API key, no account).
##
## Open-Meteo is a free, keyless weather API; attribution is required and shown
## in Settings → Credits.
##
## Design rules:
##   - the app must work with no network: the last good snapshot is cached on
##     disk and reused, and the room simply falls back to manual lighting
##   - parsing is a pure static function so it can be unit tested against a real
##     captured response (tests/fixtures/open_meteo_mumbai.json)
##   - nothing here invents weather: if the request fails and there is no cache,
##     `ok` is false and the UI says so

signal weather_changed(snapshot: Dictionary)

const API_URL := "https://api.open-meteo.com/v1/forecast"
const CACHE_PATH := "user://weather/last_weather.json"
const REFRESH_SECONDS := 900.0  # Open-Meteo updates every 15 minutes
const REQUEST_TIMEOUT := 12.0

## WMO weather interpretation codes -> room conditions.
const CONDITION_BY_CODE := {
	0: "clear",
	1: "mostly_clear", 2: "partly_cloudy", 3: "overcast",
	45: "fog", 48: "fog",
	51: "drizzle", 53: "drizzle", 55: "drizzle",
	56: "drizzle", 57: "drizzle",
	61: "rain", 63: "rain", 65: "rain",
	66: "rain", 67: "rain",
	71: "snow", 73: "snow", 75: "snow", 77: "snow",
	80: "rain", 81: "rain", 82: "storm",
	85: "snow", 86: "snow",
	95: "storm", 96: "storm", 99: "storm",
}

const DESCRIPTION_BY_CONDITION := {
	"clear": "Clear sky",
	"mostly_clear": "Mostly clear",
	"partly_cloudy": "Partly cloudy",
	"overcast": "Overcast",
	"fog": "Fog",
	"drizzle": "Drizzle",
	"rain": "Rain",
	"snow": "Snow",
	"storm": "Thunderstorm",
	"unknown": "Weather unavailable",
}

var snapshot: Dictionary = empty_snapshot()
var enabled: bool = false
var latitude: float = 19.076
var longitude: float = 72.8777
var location_label: String = "Mumbai"

var _request: HTTPRequest
var _last_fetch_at: float = -1000.0
var _pending: bool = false


func _ready() -> void:
	_request = HTTPRequest.new()
	_request.timeout = REQUEST_TIMEOUT
	_request.use_threads = true
	add_child(_request)
	_request.request_completed.connect(_on_request_completed)
	load_cache()


# --------------------------------------------------------------------------
# Public API
# --------------------------------------------------------------------------

static func empty_snapshot() -> Dictionary:
	return {
		"ok": false,
		"condition": "unknown",
		"description": DESCRIPTION_BY_CONDITION["unknown"],
		"temperature_c": 0.0,
		"cloud_cover": 0.0,
		"wind_kph": 0.0,
		"is_day": true,
		"humidity": 0.0,
		"observed_at": "",
		"source": "",
		"error": "No weather data yet.",
	}


func configure(new_enabled: bool, new_latitude: float, new_longitude: float, label: String) -> void:
	enabled = new_enabled
	latitude = clampf(new_latitude, -90.0, 90.0)
	longitude = clampf(new_longitude, -180.0, 180.0)
	location_label = label
	if enabled:
		refresh(false)


## Fetches current weather. Returns false when a request is already in flight.
func refresh(force: bool = true) -> bool:
	if _pending:
		return false
	if not force and (Time.get_ticks_msec() / 1000.0 - _last_fetch_at) < REFRESH_SECONDS and bool(snapshot["ok"]):
		return false

	var url := "%s?latitude=%.4f&longitude=%.4f&current=temperature_2m,relative_humidity_2m,weather_code,cloud_cover,is_day,wind_speed_10m&timezone=auto" % [
		API_URL, latitude, longitude,
	]
	var error := _request.request(url)
	if error != OK:
		_set_failure("Could not start the weather request (error %d)." % error)
		return false

	_pending = true
	return true


func is_fetching() -> bool:
	return _pending


## Human readable one-liner for the HUD, e.g. "Mumbai · 28°C · Clear sky".
func summary() -> String:
	if not bool(snapshot["ok"]):
		return "Weather offline"
	return "%s · %d°C · %s" % [location_label, int(round(float(snapshot["temperature_c"]))), str(snapshot["description"])]


func load_cache() -> void:
	var result := JsonFile.read(CACHE_PATH)
	if result["ok"] and result["data"] is Dictionary:
		var cached: Dictionary = result["data"]
		if cached.has("condition") and cached.has("temperature_c"):
			snapshot = cached
			snapshot["ok"] = true
			snapshot["source"] = "cache"
			weather_changed.emit(snapshot)


func save_cache() -> void:
	if bool(snapshot["ok"]):
		JsonFile.write_atomic(CACHE_PATH, snapshot)


# --------------------------------------------------------------------------
# Parsing (pure, unit tested)
# --------------------------------------------------------------------------

## Maps a WMO weather code to a room condition string.
static func condition_for_code(code: int) -> String:
	return str(CONDITION_BY_CODE.get(code, "unknown"))


static func description_for_condition(condition: String) -> String:
	return str(DESCRIPTION_BY_CONDITION.get(condition, DESCRIPTION_BY_CONDITION["unknown"]))


## Turns an Open-Meteo `current` payload into a snapshot. Never throws: a
## malformed payload yields an ok=false snapshot with an explanation.
static func parse_open_meteo(data: Variant) -> Dictionary:
	var result := empty_snapshot()
	if not (data is Dictionary):
		result["error"] = "Weather response was not an object."
		return result

	var current: Variant = (data as Dictionary).get("current", null)
	if not (current is Dictionary):
		result["error"] = "Weather response had no 'current' block."
		return result

	var block: Dictionary = current
	if not block.has("temperature_2m"):
		result["error"] = "Weather response had no temperature."
		return result

	var code := int(block.get("weather_code", -1))
	var condition := condition_for_code(code)
	result["ok"] = true
	result["condition"] = condition
	result["description"] = description_for_condition(condition)
	result["temperature_c"] = float(block.get("temperature_2m", 0.0))
	result["humidity"] = float(block.get("relative_humidity_2m", 0.0))
	result["cloud_cover"] = clampf(float(block.get("cloud_cover", 0.0)), 0.0, 100.0)
	result["wind_kph"] = maxf(float(block.get("wind_speed_10m", 0.0)), 0.0)
	result["is_day"] = int(block.get("is_day", 1)) == 1
	result["observed_at"] = str(block.get("time", ""))
	result["source"] = "open-meteo"
	result["weather_code"] = code
	result["error"] = ""
	return result


# --------------------------------------------------------------------------
# Networking
# --------------------------------------------------------------------------

func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_pending = false
	_last_fetch_at = Time.get_ticks_msec() / 1000.0

	if response_code != 200:
		_set_failure("Weather service returned HTTP %d." % response_code)
		return

	var text := body.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(text) != OK:
		_set_failure("Weather response was not valid JSON.")
		return

	var parsed := parse_open_meteo(json.data)
	if not bool(parsed["ok"]):
		_set_failure(str(parsed["error"]))
		return

	snapshot = parsed
	save_cache()
	weather_changed.emit(snapshot)


func _set_failure(message: String) -> void:
	# Keep the last good snapshot if we have one; otherwise report the failure.
	var had_data := bool(snapshot["ok"])
	snapshot["error"] = message
	if not had_data:
		snapshot["ok"] = false
		snapshot["description"] = DESCRIPTION_BY_CONDITION["unknown"]
	weather_changed.emit(snapshot)
