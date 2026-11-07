class_name QualityPresets
extends RefCounted
## Rendering presets for the Compatibility renderer on low-end Android.
##
## Only features the Compatibility backend actually supports are toggled:
## directional shadows, MSAA, ambient light energy, avatar mesh density and
## the number of real-time lights the room builder spawns.
## SSAO / SSR / SDFGI are Forward+ only and are therefore never advertised.

const LEVELS := ["low", "medium", "high", "ultra"]
const LEVEL_COUNT := 4

const PRESETS := [
	{
		"level": 0,
		"name": "low",
		"shadows": false,
		"shadow_max_distance": 0.0,
		"shadow_size": 0,
		"mesh_detail": 0,
		"msaa": 0,
		"glow": false,
		"realtime_lights": 1,
		"ambient_energy": 0.55,
		"target_fps": 30,
	},
	{
		"level": 1,
		"name": "medium",
		"shadows": true,
		"shadow_max_distance": 12.0,
		"shadow_size": 1024,
		"mesh_detail": 1,
		"msaa": 0,
		"glow": false,
		"realtime_lights": 2,
		"ambient_energy": 0.5,
		"target_fps": 45,
	},
	{
		"level": 2,
		"name": "high",
		"shadows": true,
		"shadow_max_distance": 20.0,
		"shadow_size": 2048,
		"mesh_detail": 2,
		"msaa": 1,
		"glow": false,
		"realtime_lights": 3,
		"ambient_energy": 0.45,
		"target_fps": 60,
	},
	{
		"level": 3,
		"name": "ultra",
		"shadows": true,
		"shadow_max_distance": 32.0,
		"shadow_size": 4096,
		"mesh_detail": 3,
		"msaa": 2,
		"glow": true,
		"realtime_lights": 4,
		"ambient_energy": 0.4,
		"target_fps": 60,
	},
]


## Returns the preset dictionary for a level, clamped into range.
static func for_level(level: int) -> Dictionary:
	var index := clampi(level, 0, LEVEL_COUNT - 1)
	return (PRESETS[index] as Dictionary).duplicate(true)


static func level_name(level: int) -> String:
	var preset := for_level(level)
	return str(preset["name"]).capitalize()


static func next_level(level: int) -> int:
	return (clampi(level, 0, LEVEL_COUNT - 1) + 1) % LEVEL_COUNT


## Applies the viewport-level parts of a preset (MSAA + 3D scaling).
static func apply_to_viewport(viewport: Viewport, preset: Dictionary) -> void:
	if viewport == null:
		return
	match int(preset.get("msaa", 0)):
		0:
			viewport.msaa_3d = Viewport.MSAA_DISABLED
		1:
			viewport.msaa_3d = Viewport.MSAA_2X
		_:
			viewport.msaa_3d = Viewport.MSAA_4X


## Applies the engine-level parts of a preset (frame cap, shadow atlas).
static func apply_to_engine(preset: Dictionary) -> void:
	var fps := int(preset.get("target_fps", 60))
	Engine.max_fps = 0 if fps <= 0 else fps
