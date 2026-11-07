extends Node3D
## Waifu World — room-first companion application root.
##
## Responsibilities:
##   - build the room, lighting, camera and companion from persisted state
##   - keep the 3D companion the focus of the screen at all times
##   - own the HUD and the screen stack
##   - apply graphics presets, room changes and day/night settings
##
## It never invents data: every companion shown comes from CompanionRepository,
## every setting from SettingsRepository.

const HUD_SCENE := preload("res://scenes/ui/main_hud.tscn")
const SCREEN_MANAGER_SCRIPT := preload("res://scripts/ui/screen_manager.gd")

## Local, clearly-labelled sample lines. These are NOT AI output. They exist so
## the Talk button does something honest until the AI backend stage lands.
const SAMPLE_LINES := {
	"friendly": [
		"Hey! I'm glad you're here.",
		"I was just tidying up the room. Want to hang out?",
		"You look like you had a long day.",
	],
	"playful": [
		"Guess what? I moved the pillow three times today.",
		"Race you to the window!",
		"Bored? I have a terrible idea.",
	],
	"calm": [
		"Take your time. There's no rush in here.",
		"The light is nice at this hour, isn't it?",
		"Sit with me for a minute.",
	],
	"shy": [
		"Oh — hi. I didn't hear you come in.",
		"I, um. I like this room.",
		"Can we talk about something small?",
	],
	"confident": [
		"I've been waiting. Let's get to it.",
		"You're going to like today.",
		"Tell me what you're planning.",
	],
	"witty": [
		"I'd offer you a chair, but I live here.",
		"Statistically, you're my favourite visitor.",
		"Let me guess: you pressed Talk again.",
	],
}

@onready var room_builder: RoomBuilder = $Room
@onready var lighting: LightingController = $Lighting
@onready var camera_rig: CameraRig = $CameraRig
@onready var avatar_loader: AvatarLoader = $AvatarLoader
@onready var ui_layer: CanvasLayer = $UI

var hud: Control
var screens: ScreenManager
var avatar: Node3D = null

var _sample_index: int = 0
var _status_timer: float = 0.0
var _expression_reset_timer: float = 0.0
var _default_status: String = ""


func _ready() -> void:
	# Make the drop-in avatar folder exist so users can add a GLB without hunting
	# for the app's private storage path.
	JsonFile.ensure_dir(AvatarCatalog.USER_AVATAR_DIR)

	_build_ui()
	_apply_quality_preset(false)
	_build_room(AppSettings.room_id())
	_apply_safe_area()
	_load_companion()

	Companions.active_profile_changed.connect(_on_active_profile_changed)
	Companions.profiles_changed.connect(_on_profiles_changed)
	Companions.save_failed.connect(_on_save_failed)

	lighting.set_auto_cycle(bool(AppSettings.get_value("auto_day_night", false)))
	lighting.set_time_of_day(AppSettings.time_of_day())
	hud.set_clock(lighting.get_time_of_day())


# --------------------------------------------------------------------------
# Scene assembly
# --------------------------------------------------------------------------

func _build_ui() -> void:
	hud = HUD_SCENE.instantiate()
	ui_layer.add_child(hud)
	hud.talk_pressed.connect(_on_talk_pressed)
	hud.wave_pressed.connect(_on_wave_pressed)
	hud.characters_pressed.connect(_on_characters_pressed)
	hud.customize_pressed.connect(_on_customize_pressed)
	hud.settings_pressed.connect(_on_settings_pressed)

	screens = SCREEN_MANAGER_SCRIPT.new()
	screens.name = "Screens"
	ui_layer.add_child(screens)
	screens.screen_closed.connect(_on_screen_closed)


func _build_room(room_id: String) -> void:
	room_builder.build(room_id, AppSettings.quality_level())
	lighting.set_window(room_builder.window_anchor)

	var defaults := room_builder.camera_defaults()
	camera_rig.focus_on(Vector3(0.0, float(defaults["height"]), 0.0))

	avatar_loader.position = room_builder.companion_position()
	if avatar != null and is_instance_valid(avatar):
		pass  # avatar stays parented to the loader; the loader moved instead


func _load_companion() -> void:
	var profile := Companions.get_active()
	if profile == null:
		avatar = null
		hud.set_companion(null)
		hud.set_status("No companion yet — tap Companions to create one")
		return

	avatar_loader.position = room_builder.companion_position()
	avatar = avatar_loader.load_for_profile(profile, AppSettings.quality_level())
	hud.set_companion(profile)

	_default_status = "%s · %s" % [profile.personality.capitalize(), profile.language.to_upper()]
	hud.set_status(_default_status)

	if avatar_loader.used_fallback and not avatar_loader.fallback_reason.is_empty():
		# Shown once per launch so the user knows exactly what they are looking at.
		_status_timer = 6.0
		hud.set_status(avatar_loader.fallback_reason)

	if avatar != null and is_instance_valid(avatar):
		camera_rig.focus_on(avatar.head_global_position())


func _apply_quality_preset(rebuild_room: bool = true) -> void:
	var level := AppSettings.quality_level()
	var preset := AppSettings.quality_preset()

	QualityPresets.apply_to_engine(preset)
	QualityPresets.apply_to_viewport(get_viewport(), preset)
	lighting.set_quality(level)

	if rebuild_room:
		room_builder.build(room_builder.current_room_id, level)
		lighting.set_window(room_builder.window_anchor)

	if avatar != null and is_instance_valid(avatar) and avatar.has_method("set_quality"):
		avatar.set_quality(level)

	hud.set_quality_name(level)


func _apply_safe_area() -> void:
	var safe := DisplayServer.get_display_safe_area()
	var window_size := DisplayServer.window_get_size()
	if safe.size.y <= 0 or window_size.y <= 0:
		return
	var inset_ratio := float(safe.position.y) / float(window_size.y)
	if inset_ratio <= 0.0:
		return
	var viewport_height := get_viewport().get_visible_rect().size.y
	hud.apply_top_inset(inset_ratio * viewport_height)


# --------------------------------------------------------------------------
# Per-frame
# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if avatar != null and is_instance_valid(avatar):
		camera_rig.focus_on(avatar.head_global_position())

	if _status_timer > 0.0:
		_status_timer -= delta
		if _status_timer <= 0.0 and hud != null:
			hud.set_status(_default_status)

	if _expression_reset_timer > 0.0:
		_expression_reset_timer -= delta
		if _expression_reset_timer <= 0.0 and avatar != null and is_instance_valid(avatar):
			if avatar.has_method("set_expression"):
				avatar.set_expression("neutral")

	if lighting.is_auto_cycle() and hud != null:
		hud.set_clock(lighting.get_time_of_day())


# --------------------------------------------------------------------------
# HUD actions
# --------------------------------------------------------------------------

func _on_talk_pressed() -> void:
	var profile := Companions.get_active()
	if profile == null:
		hud.set_status("Create a companion first")
		return

	var lines: Array = SAMPLE_LINES.get(profile.personality, SAMPLE_LINES["friendly"])
	var line := str(lines[_sample_index % lines.size()])
	_sample_index += 1

	# Explicitly labelled: this is a local sample line, not an AI reply.
	hud.set_status("%s: \"%s\"  — sample line, no AI connected" % [profile.display_name, line])
	_status_timer = 6.0
	if avatar != null and avatar.has_method("set_expression"):
		# Timed in _process rather than with a coroutine timer so no orphaned
		# SceneTreeTimer survives a screen change or app pause.
		avatar.set_expression("smile")
		_expression_reset_timer = 2.5


func _on_wave_pressed() -> void:
	if avatar == null:
		hud.set_status("No companion to wave")
		return
	if avatar.has_method("play_gesture") and avatar.play_gesture("wave"):
		var profile := Companions.get_active()
		var who := profile.display_name if profile != null else "Your companion"
		hud.set_status("%s waves hello" % who)
		_status_timer = 3.0
	else:
		hud.set_status("This avatar has no wave animation")


func _on_characters_pressed() -> void:
	screens.open("characters")


func _on_customize_pressed() -> void:
	var profile := Companions.get_active()
	if profile == null:
		screens.open("characters")
		return
	screens.open("editor", {"profile_id": profile.id})


func _on_settings_pressed() -> void:
	var data := {
		"quality_level": AppSettings.quality_level(),
		"time_of_day": lighting.get_time_of_day(),
		"auto_cycle": lighting.is_auto_cycle(),
		"room_id": room_builder.current_room_id,
		"camera_distance": camera_rig.get_distance(),
		"capabilities": avatar_loader.capabilities,
		"avatar_notice": avatar_loader.fallback_reason if avatar_loader.used_fallback else "",
	}
	var screen := screens.open("settings", data)
	if screen == null:
		return
	screen.quality_changed.connect(_on_quality_changed)
	screen.time_changed.connect(_on_time_changed)
	screen.auto_cycle_changed.connect(_on_auto_cycle_changed)
	screen.room_changed.connect(_on_room_changed)
	screen.camera_distance_changed.connect(_on_camera_distance_changed)
	screen.reset_view_requested.connect(_on_reset_view)
	screen.delete_all_companions_requested.connect(_on_delete_all_companions)


func _on_quality_changed(level: int) -> void:
	AppSettings.set_quality_level(level)
	_apply_quality_preset(true)


func _on_time_changed(hours: float) -> void:
	AppSettings.set_time_of_day(hours)
	lighting.set_time_of_day(hours)
	hud.set_clock(hours)


func _on_auto_cycle_changed(enabled: bool) -> void:
	AppSettings.set_value("auto_day_night", enabled)
	lighting.set_auto_cycle(enabled)


func _on_room_changed(room_id: String) -> void:
	if not RoomPresets.has_room(room_id):
		return
	AppSettings.set_room_id(room_id)
	_build_room(room_id)
	_apply_quality_preset(true)
	if avatar != null and is_instance_valid(avatar):
		camera_rig.focus_on(avatar.head_global_position())


func _on_camera_distance_changed(distance: float) -> void:
	AppSettings.set_camera_distance(distance)
	camera_rig.set_distance(distance)


func _on_reset_view() -> void:
	camera_rig.reset_view()
	camera_rig.set_distance(AppSettings.camera_distance())


func _on_delete_all_companions() -> void:
	Companions.delete_all_profiles()
	screens.close_all()
	avatar = null
	hud.set_companion(null)
	hud.set_status("All companions deleted")


# --------------------------------------------------------------------------
# Repository signals
# --------------------------------------------------------------------------

func _on_active_profile_changed(_profile_id: String) -> void:
	_load_companion()


func _on_profiles_changed() -> void:
	var profile := Companions.get_active()
	if profile != null:
		hud.set_companion(profile)


func _on_save_failed(error: String) -> void:
	hud.set_status("Could not save: %s" % error)
	_status_timer = 6.0


func _on_screen_closed(_screen_id: String) -> void:
	# Selecting or editing a companion changes the active profile, which is
	# handled by active_profile_changed. This keeps the HUD in sync otherwise.
	var profile := Companions.get_active()
	if profile != null:
		hud.set_companion(profile)
