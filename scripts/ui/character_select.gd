extends Control
## Character selection: list, select, edit and delete companions.
##
## Talks only to the `Companions` autoload, so it works with any number of
## profiles and never keeps its own copy of the data.

signal closed
signal edit_requested(profile_id: String)

var _list_box: VBoxContainer
var _count_label: Label
var _confirm_overlay: Control = null
var _manager: ScreenManager


func _ready() -> void:
	theme = UiTheme.build_theme()
	_manager = get_parent() as ScreenManager
	_build()
	Companions.profiles_changed.connect(_refresh)
	_refresh()


func _build() -> void:
	var background := UiTheme.dim_background()
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var panel := UiTheme.panel()
	margin.add_child(panel)

	var column := UiTheme.column(12)
	panel.add_child(column)

	var header_row := UiTheme.row(8)
	column.add_child(header_row)

	var title_column := UiTheme.column(2)
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title_column)
	title_column.add_child(UiTheme.label("Your Companions", UiTheme.FONT_HEADER, UiTheme.TEXT))

	_count_label = UiTheme.caption("")
	title_column.add_child(_count_label)

	var close_button := UiTheme.button("Close", Vector2(88, 44))
	close_button.pressed.connect(func() -> void: closed.emit())
	header_row.add_child(close_button)

	column.add_child(UiTheme.caption(
		"Every companion is a fictional AI character. Profiles are stored on this device only."
	))

	var scroll := UiTheme.scroll_list()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	_list_box = UiTheme.column(10)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_box)

	var footer := UiTheme.row(10)
	column.add_child(footer)

	var create_button := UiTheme.button("Create companion")
	create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_button.pressed.connect(_on_create_pressed)
	footer.add_child(create_button)


func _refresh() -> void:
	if _list_box == null:
		return
	for child in _list_box.get_children():
		_list_box.remove_child(child)
		child.queue_free()

	var profiles := Companions.list_profiles()
	var active_id := Companions.get_active_id()
	_count_label.text = "%d of %d slots used" % [profiles.size(), CompanionRepository.MAX_PROFILES]

	for profile in profiles:
		_list_box.add_child(_make_row(profile, profile.id == active_id))

	if profiles.is_empty():
		_list_box.add_child(UiTheme.caption("No companions yet. Create your first one below."))


func _make_row(profile: CompanionProfile, is_active: bool) -> Control:
	var card := UiTheme.panel(UiTheme.PANEL_SOFT if not is_active else Color(0.20, 0.14, 0.28, 0.95), 14)
	var column := UiTheme.column(6)
	card.add_child(column)

	var name_row := UiTheme.row(8)
	column.add_child(name_row)

	var name_label := UiTheme.label(profile.display_name, UiTheme.FONT_TITLE, UiTheme.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)

	if is_active:
		name_row.add_child(UiTheme.label("ACTIVE", UiTheme.FONT_SMALL, UiTheme.SUCCESS))

	column.add_child(UiTheme.caption(
		"%s · %s voice · %s · created %s" % [
			profile.personality.capitalize(),
			profile.voice_preset.capitalize(),
			profile.language.to_upper(),
			UiTheme.format_date(profile.created_at),
		]
	))

	var actions := UiTheme.row(8)
	column.add_child(actions)

	var select_button := UiTheme.button("Select", Vector2(0, 40))
	select_button.disabled = is_active
	select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_button.pressed.connect(func() -> void: _on_select(profile.id))
	actions.add_child(select_button)

	var edit_button := UiTheme.button("Edit", Vector2(0, 40))
	edit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_button.pressed.connect(func() -> void: _on_edit(profile.id))
	actions.add_child(edit_button)

	var delete_button := UiTheme.danger_button("Delete")
	delete_button.custom_minimum_size = Vector2(0, 40)
	delete_button.pressed.connect(func() -> void: _confirm_delete(profile))
	actions.add_child(delete_button)

	return card


func _on_select(profile_id: String) -> void:
	if Companions.set_active(profile_id):
		closed.emit()


func _on_edit(profile_id: String) -> void:
	if _manager != null:
		_manager.open("editor", {"profile_id": profile_id})
	else:
		edit_requested.emit(profile_id)


func _on_create_pressed() -> void:
	if not Companions.can_create_more():
		_show_message("You already have the maximum number of companions.")
		return
	if _manager != null:
		_manager.open("editor", {"profile_id": ""})
	else:
		edit_requested.emit("")


func _confirm_delete(profile: CompanionProfile) -> void:
	_confirm(
		"Delete %s? This removes the profile and its settings from this device." % profile.display_name,
		"Delete",
		func() -> void:
			Companions.delete_profile(profile.id)
			if Companions.count() == 0:
				_show_message("All companions deleted. Create a new one to continue.")
	)


# --------------------------------------------------------------------------
# Small in-screen modal helpers (no separate scene, no OS dialog)
# --------------------------------------------------------------------------

func _confirm(message: String, confirm_text: String, on_confirm: Callable) -> void:
	_dismiss_overlay()

	_confirm_overlay = Control.new()
	_confirm_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_confirm_overlay)

	var dim := UiTheme.dim_background()
	dim.color = Color(0.02, 0.02, 0.04, 0.6)
	_confirm_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.add_child(center)

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
	cancel.pressed.connect(_dismiss_overlay)
	buttons.add_child(cancel)

	var confirm := UiTheme.danger_button(confirm_text)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(func() -> void:
		_dismiss_overlay()
		on_confirm.call()
	)
	buttons.add_child(confirm)


func _show_message(message: String) -> void:
	_dismiss_overlay()

	_confirm_overlay = Control.new()
	_confirm_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_confirm_overlay)

	var dim := UiTheme.dim_background()
	dim.color = Color(0.02, 0.02, 0.04, 0.5)
	_confirm_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.add_child(center)

	var panel := UiTheme.panel()
	panel.custom_minimum_size = Vector2(300, 0)
	center.add_child(panel)

	var column := UiTheme.column(12)
	panel.add_child(column)
	column.add_child(UiTheme.label(message, UiTheme.FONT_BODY, UiTheme.TEXT))

	var ok := UiTheme.button("OK")
	ok.pressed.connect(_dismiss_overlay)
	column.add_child(ok)


func _dismiss_overlay() -> void:
	if _confirm_overlay != null and is_instance_valid(_confirm_overlay):
		remove_child(_confirm_overlay)
		_confirm_overlay.queue_free()
	_confirm_overlay = null
