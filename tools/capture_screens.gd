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

	_watchdog(210.0)

	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	add_child(_main)
	print("capture: main scene added")

	await _frames(90)                      # avatar build + camera settle
	# The launch-time "no GLB avatar" notice is transient; wait it out so the
	# hero shot shows the normal status line instead of a warning.
	var waited := 0
	while _main._status_timer > 0.0 and waited < 400:
		await get_tree().process_frame
		waited += 1
	print("capture: settled after ", waited, " extra frames")
	await _shot("01-companion-room.png")

	# The clip is 1.6 s; at software-GL frame rates "wait 24 frames" can be longer
	# than that and the arm is back at rest. Play the real clip, seek to its peak
	# and pause so the frame is a genuine pose from it.
	_main.hud.wave_pressed.emit()
	if _main.avatar is RiggedAvatar:
		var player: AnimationPlayer = _main.avatar.animation_player
		player.stop()
		player.play("wave")
		player.seek(0.5, true)
		player.pause()
	await _frames(3)
	await _shot("02-wave-gesture.png")
	if _main.avatar is RiggedAvatar:
		_main.avatar.animation_player.play()

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


## Hard stop so a stalled frame can never hang the job.
func _watchdog(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	print("watchdog: capture took too long, stopping")
	get_tree().quit(1)


## Grabs the framebuffer on the next idle frame.
##
## Deliberately not using `await RenderingServer.frame_post_draw`: if the render
## server never emits it (headless, or a stalled draw) the tool hangs forever and
## takes the CI job with it. A frame counter is boring but it always terminates.
func _shot(file_name: String) -> void:
	if _main != null and _main.avatar is RiggedAvatar:
		# A random blink can land exactly on the capture; hold the eyes open so
		# the hero shots show her face. Only the blink is pinned.
		_main.avatar._blink_progress = -1.0
		_main.avatar._blink_timer = 9999.0
		_main.avatar._apply_face(1.0)

	await get_tree().process_frame
	await get_tree().process_frame

	var texture := get_viewport().get_texture()
	if texture == null:
		print("  ! no viewport texture, skipping ", file_name)
		return
	var image := texture.get_image()
	if image == null or image.is_empty():
		print("  ! empty framebuffer, skipping ", file_name)
		return
	image.save_png(OUT_DIR.path_join(file_name))
	print("  captured ", file_name, " ", image.get_width(), "x", image.get_height())
