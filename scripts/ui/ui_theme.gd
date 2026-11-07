class_name UiTheme
extends RefCounted
## Shared look and small widget factories for every screen.
##
## Built in code (no .tres theme file) so colours live in one place and the
## whole UI can be restyled without opening the editor.

const BG_DEEP := Color(0.05, 0.04, 0.08)
const PANEL := Color(0.11, 0.09, 0.16, 0.94)
const PANEL_SOFT := Color(0.15, 0.12, 0.21, 0.92)
const BORDER := Color(0.62, 0.45, 0.86, 0.35)
const ACCENT := Color(0.72, 0.45, 0.96)
const ACCENT_DIM := Color(0.42, 0.27, 0.58)
const TEXT := Color(0.97, 0.95, 1.0)
const TEXT_DIM := Color(0.72, 0.68, 0.82)
const DANGER := Color(0.94, 0.42, 0.48)
const SUCCESS := Color(0.52, 0.86, 0.66)

const FONT_SMALL := 12
const FONT_BODY := 15
const FONT_TITLE := 20
const FONT_HEADER := 26

const SWATCHES := [
	"#e8b79c", "#c98f74", "#a86f52", "#7a4c33",
	"#4a2a3c", "#2a1c26", "#c8a35b", "#e8dcc0",
	"#8a3fb0", "#4a6fb0", "#b03f5a", "#3f9b7a",
	"#3f2a52", "#2f5a6b", "#6b4a20", "#1f2a3f",
]


static func build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = FONT_BODY

	theme.set_stylebox("panel", "PanelContainer", panel_style(PANEL, 18))

	theme.set_stylebox("normal", "Button", button_style(ACCENT_DIM, BORDER))
	theme.set_stylebox("hover", "Button", button_style(ACCENT_DIM.lightened(0.1), BORDER))
	theme.set_stylebox("pressed", "Button", button_style(ACCENT, ACCENT))
	theme.set_stylebox("disabled", "Button", button_style(Color(0.2, 0.18, 0.24), Color(0.3, 0.28, 0.34)))
	theme.set_stylebox("focus", "Button", button_style(Color(0, 0, 0, 0), ACCENT))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color(0.55, 0.52, 0.6))
	theme.set_font_size("font_size", "Button", FONT_BODY)

	theme.set_color("font_color", "Label", TEXT)
	theme.set_font_size("font_size", "Label", FONT_BODY)

	theme.set_stylebox("normal", "LineEdit", input_style())
	theme.set_stylebox("focus", "LineEdit", input_style(true))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	theme.set_font_size("font_size", "LineEdit", FONT_BODY)

	theme.set_stylebox("normal", "OptionButton", button_style(PANEL_SOFT, BORDER))
	theme.set_stylebox("hover", "OptionButton", button_style(PANEL_SOFT.lightened(0.08), BORDER))
	theme.set_stylebox("pressed", "OptionButton", button_style(ACCENT_DIM, ACCENT))
	theme.set_color("font_color", "OptionButton", TEXT)
	theme.set_font_size("font_size", "OptionButton", FONT_BODY)

	# CheckButton is a Button subclass: without explicit overrides it inherits the
	# filled Button stylebox and stops reading as a switch.
	theme.set_stylebox("normal", "CheckButton", StyleBoxEmpty.new())
	theme.set_stylebox("hover", "CheckButton", StyleBoxEmpty.new())
	theme.set_stylebox("pressed", "CheckButton", StyleBoxEmpty.new())
	theme.set_stylebox("disabled", "CheckButton", StyleBoxEmpty.new())
	theme.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	theme.set_color("font_color", "CheckButton", TEXT)
	theme.set_color("font_pressed_color", "CheckButton", TEXT)
	theme.set_color("font_hover_color", "CheckButton", Color.WHITE)
	theme.set_font_size("font_size", "CheckButton", FONT_BODY)

	theme.set_stylebox("slider", "HSlider", slider_style())
	theme.set_stylebox("grabber_area", "HSlider", grabber_area_style())
	theme.set_stylebox("grabber_area_highlight", "HSlider", grabber_area_style())

	theme.set_stylebox("panel", "PopupPanel", panel_style(PANEL_SOFT, 14))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_font_size("font_size", "PopupMenu", FONT_BODY)

	return theme


static func panel_style(color: Color, radius: int = 18, bordered: bool = true) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	if bordered:
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		style.border_color = BORDER
	return style


static func button_style(color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = border_color
	return style


static func input_style(focused: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.12, 0.95)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = ACCENT if focused else BORDER
	return style


static func slider_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.22, 0.18, 0.28)
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


static func grabber_area_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = ACCENT
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


# --------------------------------------------------------------------------
# Widget factories
# --------------------------------------------------------------------------

static func label(text: String, size: int = FONT_BODY, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node


static func heading(text: String) -> Label:
	var node := label(text, FONT_HEADER, TEXT)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return node


static func caption(text: String) -> Label:
	var node := label(text, FONT_SMALL, TEXT_DIM)
	return node


static func button(text: String, min_size: Vector2 = Vector2(0, 46)) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = min_size
	node.focus_mode = Control.FOCUS_NONE
	return node


static func danger_button(text: String) -> Button:
	var node := button(text)
	var style := button_style(Color(0.34, 0.12, 0.16), Color(0.62, 0.24, 0.3))
	node.add_theme_stylebox_override("normal", style)
	node.add_theme_stylebox_override("hover", button_style(Color(0.44, 0.15, 0.2), DANGER))
	return node


static func panel(bg: Color = PANEL, radius: int = 18) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", panel_style(bg, radius))
	return node


static func row(separation: int = 8) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func column(separation: int = 8) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	return node


static func slider(min_value: float, max_value: float, step: float, value: float) -> HSlider:
	var node := HSlider.new()
	node.min_value = min_value
	node.max_value = max_value
	node.step = step
	node.value = value
	node.custom_minimum_size = Vector2(0, 34)
	node.focus_mode = Control.FOCUS_NONE
	return node


static func dropdown(items: Array, selected_index: int = 0) -> OptionButton:
	var node := OptionButton.new()
	for item in items:
		node.add_item(str(item))
	node.selected = clampi(selected_index, 0, maxi(0, items.size() - 1))
	node.custom_minimum_size = Vector2(0, 44)
	node.focus_mode = Control.FOCUS_NONE
	return node


## Horizontal strip of colour swatches. Returns the container; the caller keeps
## the buttons it needs to highlight the current choice.
static func swatch_row(colors: Array, on_pick: Callable, selected: String = "") -> HBoxContainer:
	var container := row(6)
	for color_hex in colors:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(34, 34)
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.tooltip_text = str(color_hex)
		var style := button_style(Color.from_string(str(color_hex), Color.GRAY), Color(1, 1, 1, 0.15))
		swatch.add_theme_stylebox_override("normal", style)
		swatch.add_theme_stylebox_override("hover", button_style(Color.from_string(str(color_hex), Color.GRAY).lightened(0.15), ACCENT))
		swatch.add_theme_stylebox_override("pressed", button_style(Color.from_string(str(color_hex), Color.GRAY), ACCENT))
		swatch.set_meta("hex", str(color_hex))
		if str(color_hex) == selected:
			swatch.add_theme_stylebox_override("normal", button_style(Color.from_string(str(color_hex), Color.GRAY), ACCENT))
		swatch.pressed.connect(func() -> void: on_pick.call(str(color_hex)))
		container.add_child(swatch)
	return container


static func scroll_list() -> ScrollContainer:
	var node := ScrollContainer.new()
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	node.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return node


## Full-screen dim background used behind modal screens.
static func dim_background() -> ColorRect:
	var node := ColorRect.new()
	node.color = Color(0.02, 0.02, 0.04, 0.72)
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	return node


static func format_date(unix_time: int) -> String:
	if unix_time <= 0:
		return "unknown"
	var date := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d-%02d-%02d" % [date.get("year", 0), date.get("month", 0), date.get("day", 0)]
