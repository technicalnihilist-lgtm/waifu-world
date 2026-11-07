class_name LightingController
extends Node3D
## Day / night lighting for the companion room.
##
## All time-of-day maths lives in static functions so it can be unit tested
## without a scene tree. The node part only applies those values to a
## WorldEnvironment, one directional sun/moon light and an optional window light.
##
## Compatibility-renderer constraints respected here:
##   - no SSAO / SSR / volumetric fog (Forward+ only)
##   - one shadow-casting directional light, shadow quality from the preset
##   - ambient light from a colour instead of sky radiance (cheap on mobile)

signal time_changed(hours: float)

const DAY_START := 6.0
const DAY_END := 18.0

var hours: float = 20.0
var quality_level: int = 1
var world_environment: WorldEnvironment
var sun: DirectionalLight3D
var fill_light: DirectionalLight3D
var window_light: SpotLight3D
var environment: Environment

var _window_anchor: Dictionary = {}
var _auto_cycle: bool = false
var _cycle_speed: float = 0.12  # in-game hours per real second


func _ready() -> void:
	setup()


func setup() -> void:
	if world_environment != null:
		return

	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.04, 0.03, 0.06)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.42, 0.36, 0.55)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0

	world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)

	sun = DirectionalLight3D.new()
	sun.name = "SunMoon"
	sun.shadow_enabled = false
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 18.0
	sun.shadow_bias = 0.04
	add_child(sun)

	# Soft, shadowless fill from the camera side. Without it the companion is a
	# silhouette whenever the window is behind her, which is exactly what the
	# first night screenshots showed.
	fill_light = DirectionalLight3D.new()
	fill_light.name = "FillLight"
	fill_light.rotation_degrees = Vector3(-22.0, 8.0, 0.0)
	fill_light.light_color = Color(0.86, 0.84, 1.0)
	fill_light.light_energy = 0.42
	fill_light.shadow_enabled = false
	add_child(fill_light)

	window_light = SpotLight3D.new()
	window_light.name = "WindowLight"
	window_light.spot_range = 8.0
	window_light.spot_angle = 48.0
	window_light.spot_angle_attenuation = 1.2
	window_light.shadow_enabled = false
	window_light.light_energy = 0.0
	add_child(window_light)

	apply()
	_place_window_light()


## 0..24 clock hours.
func set_time_of_day(new_hours: float) -> void:
	hours = fposmod(new_hours, 24.0)
	apply()
	time_changed.emit(hours)


func get_time_of_day() -> float:
	return hours


func set_auto_cycle(enabled: bool) -> void:
	_auto_cycle = enabled


func is_auto_cycle() -> bool:
	return _auto_cycle


func set_quality(level: int) -> void:
	quality_level = clampi(level, 0, QualityPresets.LEVEL_COUNT - 1)
	var preset := QualityPresets.for_level(quality_level)
	var shadows := bool(preset.get("shadows", false))
	if sun != null:
		sun.shadow_enabled = shadows
		sun.directional_shadow_max_distance = float(preset.get("shadow_max_distance", 18.0))
		# 0/1/2/3 -> 1024/2048/4096 atlas via the engine project setting is not
		# per-light, so we only scale distance and enable/disable here.
	if window_light != null:
		window_light.shadow_enabled = false
	if environment != null:
		environment.ambient_light_energy = float(preset.get("ambient_energy", 0.5))
	apply()


## Tells the lighting rig where the room's main window is, so daylight can be
## aimed into the room from that direction.
func set_window(anchor: Dictionary) -> void:
	_window_anchor = anchor.duplicate(true)
	_place_window_light()


func _place_window_light() -> void:
	if window_light == null or _window_anchor.is_empty():
		return
	if not is_inside_tree():
		return
	var position_value: Variant = _window_anchor.get("position", Vector3.ZERO)
	if not (position_value is Vector3):
		return
	var origin: Vector3 = position_value
	# Step inside the room from the window and look back out at it.
	var inward := (Vector3.ZERO - origin)
	inward.y = 0.0
	if inward.length() < 0.01:
		inward = Vector3(0, 0, 1)
	inward = inward.normalized()
	window_light.position = origin + inward * 0.6
	window_light.look_at(origin, Vector3.UP)


func _process(delta: float) -> void:
	if not _auto_cycle:
		return
	set_time_of_day(hours + delta * _cycle_speed)


## Applies the current hour to every light and the environment.
func apply() -> void:
	if sun == null or environment == null:
		return

	sun.rotation_degrees = sun_rotation_degrees(hours)
	sun.light_color = sun_color(hours)
	sun.light_energy = sun_energy(hours)

	environment.ambient_light_color = ambient_color(hours)
	environment.ambient_light_energy = ambient_energy(hours) * (1.0 - quality_level * 0.05)
	environment.background_color = background_color(hours)

	if fill_light != null:
		# Slightly stronger fill at night, when there is no daylight to help.
		fill_light.light_energy = lerpf(0.55, 0.34, daylight_factor(hours))

	if window_light != null:
		window_light.light_energy = window_energy(hours)
		window_light.light_color = sun_color(hours).lerp(Color(0.85, 0.92, 1.0), 0.4)


# --------------------------------------------------------------------------
# Pure time-of-day maths (unit tested)
# --------------------------------------------------------------------------

## Height of the sun in the sky, -1 (midnight) .. 1 (noon).
static func sun_elevation(hours: float) -> float:
	return sin((fposmod(hours, 24.0) - 6.0) / 12.0 * PI)


## 0 at night, 1 in full daylight, smoothly ramped around sunrise/sunset.
static func daylight_factor(hours: float) -> float:
	var elevation := sun_elevation(hours)
	if elevation <= 0.0:
		return 0.0
	return smoothstep(0.0, 0.35, elevation)


## 0 in daylight, 1 at deep night.
static func night_factor(hours: float) -> float:
	return 1.0 - daylight_factor(hours)


static func is_night(hours: float) -> bool:
	return daylight_factor(hours) < 0.25


static func sun_rotation_degrees(hours: float) -> Vector3:
	var elevation_angle := rad_to_deg(asin(clampf(sun_elevation(hours), -1.0, 1.0)))
	# The sun travels east -> west; the azimuth follows the clock.
	var azimuth := -120.0 + (fposmod(hours, 24.0) / 24.0) * 240.0
	# At night the light is the moon, so point it from the opposite side.
	if sun_elevation(hours) < 0.0:
		return Vector3(-elevation_angle - 20.0, azimuth + 180.0, 0.0)
	return Vector3(-(elevation_angle + 8.0), azimuth, 0.0)


static func sun_color(hours: float) -> Color:
	var elevation := sun_elevation(hours)
	if elevation < 0.0:
		# Moonlight: cool and dim.
		return Color(0.55, 0.66, 0.95)
	# Warm at the horizon, neutral near noon.
	var warmth := 1.0 - clampf(elevation / 0.7, 0.0, 1.0)
	return Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.66, 0.42), warmth * 0.85)


static func sun_energy(hours: float) -> float:
	var elevation := sun_elevation(hours)
	if elevation < 0.0:
		return 0.32 + clampf(-elevation, 0.0, 1.0) * 0.16
	return 0.25 + clampf(elevation, 0.0, 1.0) * 1.15


static func window_energy(hours: float) -> float:
	return daylight_factor(hours) * 2.4


static func ambient_color(hours: float) -> Color:
	var day := daylight_factor(hours)
	var night_color := Color(0.20, 0.22, 0.38)
	var day_color := Color(0.72, 0.74, 0.82)
	# Golden hour tint.
	var golden := clampf(1.0 - absf(sun_elevation(hours)) * 3.0, 0.0, 1.0)
	var blended := night_color.lerp(day_color, day)
	return blended.lerp(Color(0.85, 0.66, 0.55), golden * 0.25 * day)


static func ambient_energy(hours: float) -> float:
	# Night is dim but never unreadable: the room has to stay legible at 22:00.
	return lerpf(0.58, 0.78, daylight_factor(hours))


static func background_color(hours: float) -> Color:
	return Color(0.03, 0.03, 0.06).lerp(Color(0.10, 0.10, 0.14), daylight_factor(hours))


## "20:30" style label for the UI.
static func format_clock(hours: float) -> String:
	var total_minutes := int(round(fposmod(hours, 24.0) * 60.0)) % (24 * 60)
	return "%02d:%02d" % [total_minutes / 60, total_minutes % 60]
