extends Control
## Graphics, room, lighting and privacy settings.
##
## The panel is intentionally dumb: it shows current values and emits signals.
## Main applies the changes to the live scene, so the panel can never desync
## from what is actually rendered.

signal closed
signal quality_changed(level: int)
signal time_changed(hours: float)
signal auto_cycle_changed(enabled: bool)
signal room_changed(room_id: String)
signal camera_distance_changed(distance: float)
signal reset_view_requested
signal delete_all_companions_requested
signal weather_toggled(enabled: bool)
signal weather_refresh_requested

var _data: Dictionary = {}

var _clock_label: Label
var _time_slider: HSlider
var _capability_label: Label
var _overlay: Control = null


func setup(data: Dictionary = {}) -> void:
	_data = data.duplicate(true)


func _ready() -> void:
	theme = UiTheme.build_theme()
	_build()


func _build() -> void:
	add_child(UiTheme.dim_background())

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var panel := UiTheme.panel()
	margin.add_child(panel)

	var root_column := UiTheme.column(10)
	panel.add_child(root_column)

	var header := UiTheme.row(8)
	root_column.add_child(header)

	var title := UiTheme.label("Settings", UiTheme.FONT_HEADER, UiTheme.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_button := UiTheme.button("Close", Vector2(88, 44))
	close_button.pressed.connect(func() -> void: closed.emit())
	header.add_child(close_button)

	var scroll := UiTheme.scroll_list()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_column.add_child(scroll)

	var form := UiTheme.column(16)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form)

	_build_graphics(form)
	_build_room(form)
	_build_camera(form)
	_build_model(form)
	_build_weather(form)
	_build_privacy(form)
	_build_about(form)
	_build_credits(form)


func _section(form: VBoxContainer, title_text: String) -> VBoxContainer:
	form.add_child(UiTheme.label(title_text, UiTheme.FONT_TITLE, UiTheme.ACCENT_DIM.lightened(0.45)))
	var column := UiTheme.column(10)
	form.add_child(column)
	return column


func _build_graphics(form: VBoxContainer) -> void:
	var column := _section(form, "Graphics")

	var labels: Array = []
	for level in QualityPresets.LEVEL_COUNT:
		labels.append(QualityPresets.level_name(level))
	var dropdown := UiTheme.dropdown(labels, int(_data.get("quality_level", 1)))
	dropdown.item_selected.connect(func(index: int) -> void: quality_changed.emit(index))
	column.add_child(dropdown)

	column.add_child(UiTheme.caption(
		"Low: no shadows, 30 fps cap. Medium: shadows, 45 fps. High: sharper shadows and "
		+ "denser meshes, 60 fps. Ultra: maximum mesh density and MSAA 4x. "
		+ "The Compatibility renderer has no SSAO or screen-space reflections, so they are not offered."
	))


func _build_room(form: VBoxContainer) -> void:
	var column := _section(form, "Room and lighting")

	var room_labels: Array = []
	var room_ids := RoomPresets.room_ids()
	var selected := 0
	var current_room := str(_data.get("room_id", "bedroom"))
	for index in room_ids.size():
		room_labels.append(RoomPresets.display_name(room_ids[index]))
		if room_ids[index] == current_room:
			selected = index
	var room_dropdown := UiTheme.dropdown(room_labels, selected)
	room_dropdown.item_selected.connect(func(index: int) -> void: room_changed.emit(room_ids[index]))
	column.add_child(UiTheme.caption("Room"))
	column.add_child(room_dropdown)

	var hours := float(_data.get("time_of_day", 20.0))
	_clock_label = UiTheme.caption("Time of day: %s" % LightingController.format_clock(hours))
	column.add_child(_clock_label)

	_time_slider = UiTheme.slider(0.0, 24.0, 0.25, hours)
	_time_slider.value_changed.connect(_on_time_changed)
	column.add_child(_time_slider)

	var auto_toggle := CheckButton.new()
	auto_toggle.text = "Automatic day / night cycle"
	auto_toggle.button_pressed = bool(_data.get("auto_cycle", false))
	auto_toggle.toggled.connect(func(pressed: bool) -> void: auto_cycle_changed.emit(pressed))
	column.add_child(auto_toggle)


func _on_time_changed(value: float) -> void:
	if _clock_label != null:
		_clock_label.text = "Time of day: %s" % LightingController.format_clock(value)
	time_changed.emit(value)


func _build_camera(form: VBoxContainer) -> void:
	var column := _section(form, "Camera")
	column.add_child(UiTheme.caption("Drag the room to orbit. Pinch to zoom."))

	var distance := float(_data.get("camera_distance", 3.2))
	var distance_label := UiTheme.caption("Distance: %.1f m" % distance)
	column.add_child(distance_label)

	var slider := UiTheme.slider(
		SettingsRepository.CAMERA_DISTANCE_MIN, SettingsRepository.CAMERA_DISTANCE_MAX, 0.1, distance
	)
	slider.value_changed.connect(func(value: float) -> void:
		distance_label.text = "Distance: %.1f m" % value
		camera_distance_changed.emit(value)
	)
	column.add_child(slider)

	var reset_button := UiTheme.button("Reset view")
	reset_button.pressed.connect(func() -> void: reset_view_requested.emit())
	column.add_child(reset_button)


func _build_model(form: VBoxContainer) -> void:
	var column := _section(form, "Companion model")

	var capabilities: Dictionary = _data.get("capabilities", {})
	var kind := str(capabilities.get("kind", "unknown"))
	var lines: Array = []
	lines.append("Model type: %s" % ("GLB avatar" if kind == "glb" else "Built-in rigged companion"))
	lines.append("Rigged skeleton: %s" % ("yes" if bool(capabilities.get("rigged", false)) else "no"))
	lines.append("Facial blendshapes: %s" % ("yes" if bool(capabilities.get("blendshapes", false)) else "no"))
	lines.append("Lip-sync source: %s" % str(capabilities.get("lip_sync", "none")))
	var animations: Array = capabilities.get("animations", [])
	lines.append("Animations: %s" % ("none" if animations.is_empty() else ", ".join(animations)))

	_capability_label = UiTheme.caption("\n".join(lines))
	column.add_child(_capability_label)

	var notice := str(_data.get("avatar_notice", ""))
	if not notice.is_empty():
		column.add_child(UiTheme.caption(notice))

	column.add_child(UiTheme.caption(
		"To use a real rigged character, add a licensed GLB avatar — see "
		+ "docs/AVATAR_INTEGRATION.md. This build ships no third-party character art."
	))


func _build_weather(form: VBoxContainer) -> void:
	var column := _section(form, "Live weather")

	var toggle := CheckButton.new()
	toggle.text = "Use live weather in the room"
	toggle.button_pressed = bool(_data.get("weather_enabled", false))
	toggle.toggled.connect(func(pressed: bool) -> void: weather_toggled.emit(pressed))
	column.add_child(toggle)

	var summary := str(_data.get("weather_summary", "Weather not loaded yet."))
	column.add_child(UiTheme.caption(summary))

	var location := str(_data.get("weather_location", ""))
	if not location.is_empty():
		column.add_child(UiTheme.caption("Location: %s (%.3f, %.3f)" % [
			location, float(_data.get("weather_latitude", 0.0)), float(_data.get("weather_longitude", 0.0))
		]))

	var error := str(_data.get("weather_error", ""))
	if not error.is_empty():
		column.add_child(UiTheme.label(error, UiTheme.FONT_SMALL, UiTheme.DANGER))

	var refresh := UiTheme.button("Refresh weather now")
	refresh.pressed.connect(func() -> void: weather_refresh_requested.emit())
	column.add_child(refresh)

	column.add_child(UiTheme.caption(
		"Live weather comes from Open-Meteo (open-meteo.com) and needs the INTERNET "
		+ "permission. Cloud cover and rain dim the room's daylight; with no network the "
		+ "last reading is reused and the room falls back to manual lighting."
	))


func _build_credits(form: VBoxContainer) -> void:
	var column := _section(form, "Credits")
	var credits := [
		"Waifu World — application code, room system, rigged companion and UI. Original work, MIT licensed.",
		"Godot Engine 4.3 — godotengine.org (MIT). The Compatibility renderer and its built-in font (Noto Sans, SIL OFL 1.1).",
		"Weather data — Open-Meteo.com, licensed CC BY 4.0. No API key is used.",
		"Character design — an original low-poly interpretation drawn from a reference sheet; no third-party model, texture or scan is bundled.",
		"No Wikimedia Commons or Wikipedia media is included in this build.",
	]
	for line in credits:
		column.add_child(UiTheme.caption(line))
	column.add_child(UiTheme.caption(
		"Attribution requirements are satisfied by this screen: Open-Meteo data must be "
		+ "credited wherever it is displayed, which is here and in the About text."
	))


func _build_privacy(form: VBoxContainer) -> void:
	var column := _section(form, "Privacy and data")
	column.add_child(UiTheme.caption(
		"Companion profiles and settings are stored in this app's private storage on this "
		+ "device. This build makes no network requests and holds no API keys."
	))

	var delete_companions := UiTheme.danger_button("Delete all companions")
	delete_companions.pressed.connect(func() -> void:
		_confirm(
			"Delete every companion profile on this device? This cannot be undone.",
			"Delete all",
			func() -> void: delete_all_companions_requested.emit()
		)
	)
	column.add_child(delete_companions)


func _build_about(form: VBoxContainer) -> void:
	var column := _section(form, "About")
	column.add_child(UiTheme.caption(
		"Waifu World — Stage 2 build. 3D companion room with persistent character profiles "
		+ "and a replaceable avatar system. AI conversation, voice and memory are not part of "
		+ "this build; the Talk button shows locally generated sample lines only."
	))
	column.add_child(UiTheme.caption("All companions are fictional AI characters. They are not real people."))


func _confirm(message: String, confirm_text: String, on_confirm: Callable) -> void:
	_dismiss()
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var dim := UiTheme.dim_background()
	dim.color = Color(0.02, 0.02, 0.04, 0.6)
	_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)

	var panel := UiTheme.panel()
	panel.custom_minimum_size = Vector2(300, 0)
	center.add_child(panel)

	var column := UiTheme.column(12)
	panel.add_child(column)
	column.add_child(UiTheme.label(message, UiTheme.FONT_BODY, UiTheme.TEXT))

	var buttons := UiTheme.row(10)
	column.add_child(buttons)

	var cancel := UiTheme.button("Cancel")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(_dismiss)
	buttons.add_child(cancel)

	var confirm := UiTheme.danger_button(confirm_text)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(func() -> void:
		_dismiss()
		on_confirm.call()
	)
	buttons.add_child(confirm)


func _dismiss() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		remove_child(_overlay)
		_overlay.queue_free()
	_overlay = null
