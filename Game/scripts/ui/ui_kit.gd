class_name UiKit
extends RefCounted
## Small helpers so every menu and HUD element shares one look.

const ACCENT := Color(1.0, 0.72, 0.2)
const TEXT := Color(0.92, 0.92, 0.9)
const DIM := Color(0.62, 0.64, 0.66)
const PANEL := Color(0.07, 0.08, 0.1, 0.88)


static func style(color: Color, radius: int = 4, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(10)
	if border.a > 0.0:
		box.border_color = border
		box.set_border_width_all(1)
	return box


static func label(text: String, size: int = 16, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	node.add_theme_constant_override("shadow_offset_x", 1)
	node.add_theme_constant_override("shadow_offset_y", 1)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func button(text: String, on_pressed: Callable, size: int = 18) -> Button:
	var node := Button.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_stylebox_override("normal", style(Color(0.14, 0.15, 0.18, 0.95), 4, Color(1, 1, 1, 0.08)))
	node.add_theme_stylebox_override("hover", style(Color(0.24, 0.22, 0.16, 0.98), 4, ACCENT))
	node.add_theme_stylebox_override("pressed", style(ACCENT.darkened(0.3), 4, ACCENT))
	node.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	node.custom_minimum_size = Vector2(0, 40)
	node.pressed.connect(func() -> void:
		Sfx.play("ui_click")
		on_pressed.call())
	return node


static func panel(color: Color = PANEL) -> PanelContainer:
	var node := PanelContainer.new()
	node.add_theme_stylebox_override("panel", style(color, 6, Color(1, 1, 1, 0.06)))
	return node


## A labelled row: "Name ........ [control]".
static func row(name: String, control: Control) -> HBoxContainer:
	var box := HBoxContainer.new()
	var text := label(name, 15, DIM)
	text.custom_minimum_size = Vector2(170, 0)
	box.add_child(text)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(control)
	return box
