extends Node
## Development tool: renders the real app offscreen and saves PNG screenshots.
##
## Requires a display (X11 or Xvfb) — it drives the actual game scene, not a
## mock-up, so the images are genuine captures of the running app.
##
##   Xvfb :99 -screen 0 720x1280x24 &
##   DISPLAY=:99 godot --path . --resolution 720x1280 tools/capture_screens.tscn
##
## Output: user://screenshots/*.png

const OUT_DIR := "user://screenshots"

var _main: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	add_child(_main)

	await _frames(90)                      # avatar build + camera settle
	# The launch-time "no GLB avatar" notice is transient; wait it out so the
	# hero shot shows the normal status line instead of a warning.
	var waited := 0
	while _main._status_timer > 0.0 and waited < 1200:
		await get_tree().process_frame
		waited += 1
	await _shot("01-companion-room.png")

	_main.hud.wave_pressed.emit()
	await _frames(24)
	await _shot("02-wave-gesture.png")

	_main.hud.characters_pressed.emit()
	await _frames(20)
	await _shot("03-companions.png")
	_main.screens.close_top()

	var profile := Companions.get_active()
	if profile != null:
		_main.screens.open("editor", {"profile_id": profile.id})
		await _frames(20)
		await _shot("04-editor.png")
		_main.screens.close_top()

	_main.hud.settings_pressed.emit()
	await _frames(20)
	await _shot("05-settings.png")
	_main.screens.close_top()

	# A different room and time of day, to show the environment system.
	_main._on_room_changed("living_room")
	_main._on_time_changed(8.5)
	await _frames(40)
	await _shot("06-living-room-morning.png")

	print("screenshots written to ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit(0)


func _frames(count: int) -> void:
	for index in count:
		await get_tree().process_frame


func _shot(file_name: String) -> void:
	# A random blink can land exactly on the capture; hold the eyes open so the
	# hero shots show her face. This only pins the blink, nothing else is faked.
	if _main != null and _main.avatar is ProceduralAvatar:
		_main.avatar._blink_progress = -1.0
		_main.avatar._blink_timer = 9999.0
		_main.avatar._apply_face(1.0)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(OUT_DIR.path_join(file_name))
	print("  captured ", file_name, " ", image.get_width(), "x", image.get_height())
