extends Control
## Create / edit a companion profile.
##
## Every control writes into a single draft dictionary; nothing touches the
## stored profile until Save, so Cancel always leaves the save file untouched.

signal closed
signal profile_saved(profile_id: String)

const LANGUAGE_LABELS := {"en": "English", "hi": "Hindi", "ja": "Japanese"}
const LANGUAGE_CODES := ["en", "hi", "ja"]

var _profile_id: String = ""
var _is_new: bool = true
var _draft: Dictionary = {}
var _error_label: Label

var _name_edit: LineEdit
var _personality_dropdown: OptionButton
var _voice_dropdown: OptionButton
var _language_dropdown: OptionButton
var _reply_dropdown: OptionButton
var _hair_dropdown: OptionButton
var _outfit_dropdown: OptionButton
var _avatar_dropdown: OptionButton
var _speech_slider: HSlider
var _pitch_slider: HSlider
var _height_slider: HSlider
var _memory_toggle: CheckButton
var _emoji_toggle: CheckButton
var _height_label: Label

var _avatar_ids: Array = [""]
var _swatch_rows: Dictionary = {}
var _manager: ScreenManager


func setup(data: Dictionary = {}) -> void:
	_profile_id = str(data.get("profile_id", ""))
	_is_new = _profile_id.is_empty()
	_draft = _draft_from_profile(_profile_id)


func _ready() -> void:
	theme = UiTheme.build_theme()
	_manager = get_parent() as ScreenManager
	if _draft.is_empty():
		_draft = _draft_from_profile(_profile_id)
	_build()


func _draft_from_profile(profile_id: String) -> Dictionary:
	var profile: CompanionProfile = null
	if not profile_id.is_empty():
		profile = Companions.get_profile(profile_id)
	if profile == null:
		profile = CompanionProfile.create_new("Companion")

	return {
		"display_name": profile.display_name,
		"personality": profile.personality,
		"voice_preset": profile.voice_preset,
		"speech_rate": profile.speech_rate,
		"pitch": profile.pitch,
		"language": profile.language,
		"appearance": profile.appearance.duplicate(true),
		"clothing": profile.clothing.duplicate(true),
		"conversation": profile.conversation.duplicate(true),
	}


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

	var title := UiTheme.label(
		"New companion" if _is_new else "Edit companion", UiTheme.FONT_HEADER, UiTheme.TEXT
	)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var cancel_top := UiTheme.button("Cancel", Vector2(88, 44))
	cancel_top.pressed.connect(func() -> void: closed.emit())
	header.add_child(cancel_top)

	root_column.add_child(UiTheme.caption(
		"Companions are fictional AI characters. Appearance options style the built-in "
		+ "placeholder avatar; a loaded GLB avatar keeps its own materials."
	))

	var scroll := UiTheme.scroll_list()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_column.add_child(scroll)

	var form := UiTheme.column(14)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form)

	_build_identity_section(form)
	_build_voice_section(form)
	_build_appearance_section(form)
	_build_conversation_section(form)

	_error_label = UiTheme.label("", UiTheme.FONT_SMALL, UiTheme.DANGER)
	root_column.add_child(_error_label)

	var footer := UiTheme.row(10)
	root_column.add_child(footer)

	var save_button := UiTheme.button("Save companion")
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(_on_save)
	footer.add_child(save_button)


func _section(form: VBoxContainer, title_text: String) -> VBoxContainer:
	form.add_child(UiTheme.label(title_text, UiTheme.FONT_TITLE, UiTheme.ACCENT_DIM.lightened(0.45)))
	var column := UiTheme.column(10)
	form.add_child(column)
	return column


func _field(column: VBoxContainer, label_text: String, control: Control) -> Label:
	var caption := UiTheme.caption(label_text)
	column.add_child(caption)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(control)
	return caption


func _build_identity_section(form: VBoxContainer) -> void:
	var column := _section(form, "Identity")

	_name_edit = LineEdit.new()
	_name_edit.text = str(_draft["display_name"])
	_name_edit.placeholder_text = "Companion name"
	_name_edit.max_length = CompanionProfile.MAX_NAME_LENGTH
	_field(column, "Name (max %d characters)" % CompanionProfile.MAX_NAME_LENGTH, _name_edit)

	_personality_dropdown = UiTheme.dropdown(
		_capitalised(CompanionProfile.PERSONALITIES),
		CompanionProfile.PERSONALITIES.find(str(_draft["personality"]))
	)
	_field(column, "Personality", _personality_dropdown)

	# Avatar choice is part of identity: it decides which model is shown.
	var catalog := AvatarCatalog.list_all()
	var avatar_names: Array = ["Built-in placeholder (procedural)"]
	_avatar_ids = [""]
	var current_avatar := str((_draft["appearance"] as Dictionary).get("avatar_id", ""))
	var selected_avatar_index := 0
	for descriptor in catalog:
		avatar_names.append("%s%s" % [
			str(descriptor["display_name"]),
			"" if bool(descriptor["has_manifest"]) else " (no manifest)",
		])
		_avatar_ids.append(str(descriptor["id"]))
		if str(descriptor["id"]) == current_avatar:
			selected_avatar_index = _avatar_ids.size() - 1

	_avatar_dropdown = UiTheme.dropdown(avatar_names, selected_avatar_index)
	_field(column, "Avatar model", _avatar_dropdown)

	if catalog.is_empty():
		column.add_child(UiTheme.caption(
			"No GLB avatars installed. Add a .glb to user://avatars/ or a manifest entry "
			+ "in res://assets/avatars/avatars.json — see docs/AVATAR_INTEGRATION.md."
		))


func _build_voice_section(form: VBoxContainer) -> void:
	var column := _section(form, "Voice")

	_voice_dropdown = UiTheme.dropdown(
		_capitalised(CompanionProfile.VOICE_PRESETS),
		CompanionProfile.VOICE_PRESETS.find(str(_draft["voice_preset"]))
	)
	_field(column, "Voice preset", _voice_dropdown)

	var language_labels: Array = []
	for code in LANGUAGE_CODES:
		language_labels.append(LANGUAGE_LABELS[code])
	_language_dropdown = UiTheme.dropdown(language_labels, LANGUAGE_CODES.find(str(_draft["language"])))
	_field(column, "Conversation language", _language_dropdown)

	_speech_slider = UiTheme.slider(
		CompanionProfile.MIN_SPEECH_RATE, CompanionProfile.MAX_SPEECH_RATE, 0.05, float(_draft["speech_rate"])
	)
	var speed_caption := _field(column, "Speech speed (%.2fx)" % float(_draft["speech_rate"]), _speech_slider)
	_speech_slider.value_changed.connect(func(value: float) -> void:
		speed_caption.text = "Speech speed (%.2fx)" % value
	)

	_pitch_slider = UiTheme.slider(
		CompanionProfile.MIN_PITCH, CompanionProfile.MAX_PITCH, 0.05, float(_draft["pitch"])
	)
	var pitch_caption := _field(column, "Voice pitch (%.2fx)" % float(_draft["pitch"]), _pitch_slider)
	_pitch_slider.value_changed.connect(func(value: float) -> void:
		pitch_caption.text = "Voice pitch (%.2fx)" % value
	)

	column.add_child(UiTheme.caption(
		"Voice settings are saved with the profile. Speech playback arrives with the "
		+ "voice stage; no audio is generated yet."
	))


func _build_appearance_section(form: VBoxContainer) -> void:
	var column := _section(form, "Appearance")
	var appearance: Dictionary = _draft["appearance"]
	var clothing: Dictionary = _draft["clothing"]

	_hair_dropdown = UiTheme.dropdown(
		_capitalised(CompanionProfile.HAIR_STYLES),
		CompanionProfile.HAIR_STYLES.find(str(appearance.get("hair_style", "long")))
	)
	_field(column, "Hair style", _hair_dropdown)

	_outfit_dropdown = UiTheme.dropdown(
		_capitalised(CompanionProfile.OUTFITS),
		CompanionProfile.OUTFITS.find(str(clothing.get("outfit", "dress")))
	)
	_field(column, "Outfit", _outfit_dropdown)

	_add_color_field(column, "Skin tone", "skin_tone", UiTheme.SWATCHES.slice(0, 4))
	_add_color_field(column, "Hair colour", "hair_color", UiTheme.SWATCHES.slice(4, 8))
	_add_color_field(column, "Eye colour", "eye_color", UiTheme.SWATCHES.slice(12, 16))
	_add_color_field(column, "Outfit colour", "primary_color", UiTheme.SWATCHES.slice(8, 12))
	_add_color_field(column, "Accent colour", "accent_color", UiTheme.SWATCHES.slice(4, 8))

	_height_slider = UiTheme.slider(
		CompanionProfile.MIN_HEIGHT_SCALE, CompanionProfile.MAX_HEIGHT_SCALE, 0.01, float(appearance.get("height_scale", 1.0))
	)
	_height_label = UiTheme.caption("Height (%.2fx)" % float(appearance.get("height_scale", 1.0)))
	column.add_child(_height_label)
	_height_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_height_slider)
	_height_slider.value_changed.connect(func(value: float) -> void:
		_height_label.text = "Height (%.2fx)" % value
	)


func _add_color_field(column: VBoxContainer, label_text: String, field_key: String, colors: Array) -> void:
	var current := _current_color(field_key)
	var container := UiTheme.swatch_row(colors, _on_color_picked.bind(field_key), current)
	_swatch_rows[field_key] = {"container": container, "colors": colors}
	column.add_child(UiTheme.caption(label_text))
	column.add_child(container)


func _current_color(field_key: String) -> String:
	if field_key == "primary_color" or field_key == "accent_color":
		return str((_draft["clothing"] as Dictionary).get(field_key, ""))
	return str((_draft["appearance"] as Dictionary).get(field_key, ""))


func _on_color_picked(hex: String, field_key: String) -> void:
	if field_key == "primary_color" or field_key == "accent_color":
		(_draft["clothing"] as Dictionary)[field_key] = hex
	else:
		(_draft["appearance"] as Dictionary)[field_key] = hex

	var entry: Dictionary = _swatch_rows.get(field_key, {})
	var old_container: HBoxContainer = entry.get("container", null)
	if old_container != null and is_instance_valid(old_container):
		var parent := old_container.get_parent()
		var index := old_container.get_index()
		parent.remove_child(old_container)
		old_container.queue_free()
		var rebuilt := UiTheme.swatch_row(entry["colors"], _on_color_picked.bind(field_key), hex)
		parent.add_child(rebuilt)
		parent.move_child(rebuilt, index)
		_swatch_rows[field_key] = {"container": rebuilt, "colors": entry["colors"]}


func _build_conversation_section(form: VBoxContainer) -> void:
	var column := _section(form, "Conversation")
	var conversation: Dictionary = _draft["conversation"]

	_reply_dropdown = UiTheme.dropdown(
		_capitalised(CompanionProfile.REPLY_LENGTHS),
		CompanionProfile.REPLY_LENGTHS.find(str(conversation.get("reply_length", "balanced")))
	)
	_field(column, "Reply length", _reply_dropdown)

	_memory_toggle = CheckButton.new()
	_memory_toggle.text = "Allow approved memories"
	_memory_toggle.button_pressed = bool(conversation.get("memory_enabled", true))
	column.add_child(_memory_toggle)

	_emoji_toggle = CheckButton.new()
	_emoji_toggle.text = "Use emoji in replies"
	_emoji_toggle.button_pressed = bool(conversation.get("use_emoji", false))
	column.add_child(_emoji_toggle)

	column.add_child(UiTheme.caption(
		"Memory stays on this device and is only written after you approve it in the "
		+ "memory stage. Nothing is sent anywhere by this build."
	))


func _on_save() -> void:
	var patch := _collect_patch()

	if _is_new:
		var created := Companions.create_profile(str(patch["display_name"]), patch)
		if created == null:
			_show_error(Companions.last_error)
			return
		Companions.set_active(created.id)
		profile_saved.emit(created.id)
		closed.emit()
		return

	if Companions.update_profile(_profile_id, patch):
		profile_saved.emit(_profile_id)
		closed.emit()
	else:
		_show_error(Companions.last_error)


func _collect_patch() -> Dictionary:
	_draft["display_name"] = _name_edit.text
	_draft["personality"] = CompanionProfile.PERSONALITIES[clampi(_personality_dropdown.selected, 0, CompanionProfile.PERSONALITIES.size() - 1)]
	_draft["voice_preset"] = CompanionProfile.VOICE_PRESETS[clampi(_voice_dropdown.selected, 0, CompanionProfile.VOICE_PRESETS.size() - 1)]
	_draft["language"] = LANGUAGE_CODES[clampi(_language_dropdown.selected, 0, LANGUAGE_CODES.size() - 1)]
	_draft["speech_rate"] = float(_speech_slider.value)
	_draft["pitch"] = float(_pitch_slider.value)

	var appearance: Dictionary = _draft["appearance"]
	appearance["hair_style"] = CompanionProfile.HAIR_STYLES[clampi(_hair_dropdown.selected, 0, CompanionProfile.HAIR_STYLES.size() - 1)]
	appearance["height_scale"] = float(_height_slider.value)
	appearance["avatar_id"] = str(_avatar_ids[clampi(_avatar_dropdown.selected, 0, _avatar_ids.size() - 1)])

	var clothing: Dictionary = _draft["clothing"]
	clothing["outfit"] = CompanionProfile.OUTFITS[clampi(_outfit_dropdown.selected, 0, CompanionProfile.OUTFITS.size() - 1)]

	var conversation: Dictionary = _draft["conversation"]
	conversation["reply_length"] = CompanionProfile.REPLY_LENGTHS[clampi(_reply_dropdown.selected, 0, CompanionProfile.REPLY_LENGTHS.size() - 1)]
	conversation["memory_enabled"] = _memory_toggle.button_pressed
	conversation["use_emoji"] = _emoji_toggle.button_pressed

	return _draft


func _show_error(message: String) -> void:
	if _error_label != null:
		_error_label.text = message if not message.is_empty() else "Could not save this companion."


static func _capitalised(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(str(value).capitalize())
	return out
