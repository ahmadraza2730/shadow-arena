class_name SettingsPanel
extends VBoxContainer
## Settings screen. Every change is applied immediately and saved.

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(UiKit.label("SETTINGS", 24, UiKit.ACCENT))

	add_child(UiKit.label("Graphics", 17))
	add_child(UiKit.row("Quality preset", _options(Game.QUALITY_NAMES, "quality")))
	add_child(UiKit.row("Max FPS", _fps_options()))
	add_child(UiKit.row("Fullscreen", _check("fullscreen")))
	add_child(UiKit.row("VSync", _check("vsync")))
	add_child(UiKit.row("Show FPS", _check("show_fps")))
	add_child(UiKit.row("Time of day", _options(Game.TIME_NAMES, "time_of_day")))

	add_child(UiKit.label("Gameplay", 17))
	add_child(UiKit.row("Bot difficulty", _options(Game.DIFFICULTY_NAMES, "difficulty")))
	add_child(UiKit.row("Mouse sensitivity", _slider("sensitivity", 0.2, 3.0, 0.05)))
	add_child(UiKit.row("Field of view", _slider("fov", 60.0, 100.0, 1.0)))
	add_child(UiKit.row("Start in third person", _check("third_person")))

	add_child(UiKit.label("Audio", 17))
	add_child(UiKit.row("Master volume", _slider("volume", 0.0, 1.0, 0.05)))
	add_child(UiKit.label("Quality and time of day apply to the next match.", 13, UiKit.DIM))


func _changed(key: String, value: Variant) -> void:
	Game.settings[key] = value
	Game.apply_settings()
	Game.save_settings()


func _options(names: Array[String], key: String) -> OptionButton:
	var node := OptionButton.new()
	for item in names:
		node.add_item(item)
	node.selected = clampi(int(Game.settings[key]), 0, names.size() - 1)
	node.item_selected.connect(func(index: int) -> void: _changed(key, index))
	return node


func _fps_options() -> OptionButton:
	var values: Array[int] = [30, 60, 120, 0]
	var node := OptionButton.new()
	for value in values:
		node.add_item("Unlimited" if value == 0 else str(value))
	node.selected = maxi(values.find(int(Game.settings["max_fps"])), 0)
	node.item_selected.connect(func(index: int) -> void: _changed("max_fps", values[index]))
	return node


func _check(key: String) -> CheckButton:
	var node := CheckButton.new()
	node.button_pressed = bool(Game.settings[key])
	node.toggled.connect(func(on: bool) -> void: _changed(key, on))
	return node


func _slider(key: String, low: float, high: float, step: float) -> HBoxContainer:
	var box := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = float(Game.settings[key])
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(160, 0)
	var value_label := UiKit.label(str(snappedf(slider.value, 0.01)), 14)
	value_label.custom_minimum_size = Vector2(44, 0)
	slider.value_changed.connect(func(value: float) -> void:
		value_label.text = str(snappedf(value, 0.01))
		_changed(key, value))
	box.add_child(slider)
	box.add_child(value_label)
	return box
