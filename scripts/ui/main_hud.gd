extends Control
## Persistent overlay for the companion room.
##
## The 3D room is always the star: the HUD is two translucent strips that never
## cover the character. Every button here is wired to a real action.

signal talk_pressed
signal wave_pressed
signal characters_pressed
signal customize_pressed
signal settings_pressed

var _name_label: Label
var _status_label: Label
var _clock_label: Label
var _weather_label: Label
var _quality_button: Button
var _top_margin: MarginContainer


func _ready() -> void:
	theme = UiTheme.build_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	# -- top strip --------------------------------------------------------
	_top_margin = MarginContainer.new()
	_top_margin.anchor_left = 0.035
	_top_margin.anchor_right = 0.965
	_top_margin.anchor_top = 0.0
	_top_margin.anchor_bottom = 0.0
	_top_margin.offset_top = 14
	_top_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_margin)

	var top_panel := UiTheme.panel(Color(0.09, 0.07, 0.14, 0.80), 20)
	top_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_margin.add_child(top_panel)

	var top_row := UiTheme.row(10)
	top_panel.add_child(top_row)

	var name_column := UiTheme.column(2)
	name_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(name_column)

	_name_label = UiTheme.label("Companion", UiTheme.FONT_TITLE, UiTheme.TEXT)
	name_column.add_child(_name_label)

	_status_label = UiTheme.label("Loading…", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	name_column.add_child(_status_label)

	var right_column := UiTheme.column(4)
	top_row.add_child(right_column)

	_clock_label = UiTheme.label("--:--", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right_column.add_child(_clock_label)

	_weather_label = UiTheme.label("", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	_weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weather_label.visible = false
	right_column.add_child(_weather_label)

	_quality_button = UiTheme.button("Graphics", Vector2(104, 38))
	_quality_button.pressed.connect(func() -> void: settings_pressed.emit())
	right_column.add_child(_quality_button)

	# -- bottom strip -----------------------------------------------------
	var bottom_margin := MarginContainer.new()
	bottom_margin.anchor_left = 0.035
	bottom_margin.anchor_right = 0.965
	bottom_margin.anchor_top = 1.0
	bottom_margin.anchor_bottom = 1.0
	bottom_margin.offset_top = -186
	bottom_margin.offset_bottom = -16
	bottom_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_margin)

	var bottom_panel := UiTheme.panel(Color(0.08, 0.06, 0.13, 0.88), 22)
	bottom_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_margin.add_child(bottom_panel)

	var bottom_column := UiTheme.column(8)
	bottom_panel.add_child(bottom_column)

	var action_row := UiTheme.row(10)
	bottom_column.add_child(action_row)

	var talk_button := UiTheme.button("Talk", Vector2(0, 54))
	talk_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	talk_button.add_theme_font_size_override("font_size", 18)
	talk_button.pressed.connect(func() -> void: talk_pressed.emit())
	action_row.add_child(talk_button)

	var wave_button := UiTheme.button("Wave", Vector2(0, 54))
	wave_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wave_button.add_theme_font_size_override("font_size", 18)
	wave_button.pressed.connect(func() -> void: wave_pressed.emit())
	action_row.add_child(wave_button)

	var nav_row := UiTheme.row(8)
	bottom_column.add_child(nav_row)

	var companions_button := UiTheme.button("Companions", Vector2(0, 42))
	companions_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	companions_button.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	companions_button.pressed.connect(func() -> void: characters_pressed.emit())
	nav_row.add_child(companions_button)

	var customize_button := UiTheme.button("Customize", Vector2(0, 42))
	customize_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	customize_button.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	customize_button.pressed.connect(func() -> void: customize_pressed.emit())
	nav_row.add_child(customize_button)

	var settings_button := UiTheme.button("Settings", Vector2(0, 42))
	settings_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_button.add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
	settings_button.pressed.connect(func() -> void: settings_pressed.emit())
	nav_row.add_child(settings_button)

	var disclaimer := UiTheme.caption("AI character · no AI service connected in this build")
	disclaimer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom_column.add_child(disclaimer)


func set_companion(profile: CompanionProfile) -> void:
	if profile == null:
		_name_label.text = "No companion"
		_status_label.text = "Create one to begin"
		return
	_name_label.text = profile.display_name
	_status_label.text = "%s · %s" % [profile.personality.capitalize(), profile.language.to_upper()]


func set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func set_clock(hours: float) -> void:
	if _clock_label != null:
		_clock_label.text = LightingController.format_clock(hours)


## Shows live weather next to the clock. Empty text hides the chip.
func set_weather(text: String) -> void:
	if _weather_label == null:
		return
	_weather_label.text = text
	_weather_label.visible = not text.is_empty()


func set_quality_name(level: int) -> void:
	if _quality_button != null:
		_quality_button.text = QualityPresets.level_name(level)


## Keeps the top strip clear of notches and status bars.
func apply_top_inset(pixels: float) -> void:
	if _top_margin != null:
		_top_margin.offset_top = 14.0 + maxf(0.0, pixels)
