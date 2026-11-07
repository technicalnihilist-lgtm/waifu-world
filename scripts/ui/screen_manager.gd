class_name ScreenManager
extends Control
## Stack based screen switcher with Android back-button support.
##
## The 3D room stays alive behind every screen: screens are translucent
## overlays, never scene changes. Only one screen is visible at a time and the
## back gesture closes the top one.

signal screen_opened(screen_id: String)
signal screen_closed(screen_id: String)
signal back_pressed()

const SCREENS := {
	"characters": "res://scenes/ui/character_select.tscn",
	"editor": "res://scenes/ui/character_editor.tscn",
	"settings": "res://scenes/ui/settings_panel.tscn",
}

var _stack: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Opens a screen. `data` is handed to the screen's setup() if it has one.
## Returns the screen node, or null when the id is unknown.
func open(screen_id: String, data: Dictionary = {}) -> Control:
	if not SCREENS.has(screen_id):
		push_warning("ScreenManager: unknown screen '%s'" % screen_id)
		return null

	# Re-opening the current screen is a no-op (prevents double taps stacking).
	if current_id() == screen_id:
		return _top_node()

	var packed: PackedScene = load(SCREENS[screen_id])
	if packed == null:
		push_error("ScreenManager: cannot load scene for '%s'" % screen_id)
		return null

	var screen := packed.instantiate() as Control
	if screen == null:
		push_error("ScreenManager: screen '%s' is not a Control" % screen_id)
		return null

	# setup() runs before the node enters the tree so _ready() can build the UI
	# from the data it was given.
	if screen.has_method("setup"):
		screen.call("setup", data)

	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.set_meta("screen_id", screen_id)

	if screen.has_signal("closed"):
		screen.connect("closed", Callable(self, "_on_screen_closed").bind(screen))

	_stack.append(screen)
	_refresh_visibility()
	screen_opened.emit(screen_id)
	return screen


## Closes the top screen. Returns false when nothing was open.
func close_top() -> bool:
	if _stack.is_empty():
		return false
	var screen: Control = _stack.pop_back()
	var screen_id := str(screen.get_meta("screen_id", ""))
	if is_instance_valid(screen):
		if screen.get_parent() == self:
			remove_child(screen)
		screen.queue_free()
	_refresh_visibility()
	screen_closed.emit(screen_id)
	return true


func close_all() -> void:
	while not _stack.is_empty():
		close_top()


func current_id() -> String:
	var top := _top_node()
	return "" if top == null else str(top.get_meta("screen_id", ""))


func is_open() -> bool:
	return not _stack.is_empty()


func _top_node() -> Control:
	if _stack.is_empty():
		return null
	return _stack[_stack.size() - 1]


func _refresh_visibility() -> void:
	for index in _stack.size():
		var screen: Control = _stack[index]
		if is_instance_valid(screen):
			screen.visible = index == _stack.size() - 1
	mouse_filter = Control.MOUSE_FILTER_IGNORE if _stack.is_empty() else Control.MOUSE_FILTER_STOP


func _on_screen_closed(screen: Control) -> void:
	var index := _stack.find(screen)
	if index < 0:
		return
	_stack.remove_at(index)
	if is_instance_valid(screen):
		if screen.get_parent() == self:
			remove_child(screen)
		screen.queue_free()
	_refresh_visibility()
	screen_closed.emit(str(screen.get_meta("screen_id", "")))


## Android back / Escape.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if is_open():
			close_top()
			get_viewport().set_input_as_handled()
		else:
			# Nothing open: let the OS handle Back (it closes the app).
			back_pressed.emit()
