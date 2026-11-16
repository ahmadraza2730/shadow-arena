extends Control
## Main menu: Play, Loadout, Settings, Quit. Built in code.

var _content: PanelContainer


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Music.play("menu")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Background: dark vertical gradient.
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.13, 0.11, 0.09), Color(0.03, 0.04, 0.05)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	var background := TextureRect.new()
	background.texture = texture
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 40)
	margin.add_child(columns)

	# Left column: title and buttons.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", 10)
	columns.add_child(left)
	left.add_child(UiKit.label("SHADOW", 56, UiKit.TEXT))
	left.add_child(UiKit.label("ARENA", 56, UiKit.ACCENT))
	left.add_child(UiKit.label("4 v 4 Team Deathmatch  |  first to %d kills" % TdmMatch.KILL_LIMIT,
			15, UiKit.DIM))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	left.add_child(spacer)
	left.add_child(UiKit.button("PLAY VS BOTS", _play_offline, 22))
	left.add_child(UiKit.button("PLAY ONLINE", _show_online, 22))
	left.add_child(UiKit.button("LOADOUT", _show_loadout))
	left.add_child(UiKit.button("SETTINGS", _show_settings))
	left.add_child(UiKit.button("CONTROLS", _show_controls))
	left.add_child(UiKit.button("QUIT", get_tree().quit))

	# Right column: whichever panel is open.
	_content = UiKit.panel()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(_content)
	if Game.menu_message != "":
		_show_online()
	else:
		_show_loadout()


func _play_offline() -> void:
	Net.close_lobby()
	Game.start_match()


func _show_online() -> void:
	_swap(OnlinePanel.new())


func _swap(panel: Control) -> void:
	for child in _content.get_children():
		child.queue_free()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	_content.add_child(scroll)


func _show_loadout() -> void:
	_swap(LoadoutPanel.new())
	Net.close_lobby()


func _show_settings() -> void:
	_swap(SettingsPanel.new())
	Net.close_lobby()


func _show_controls() -> void:
	var box := VBoxContainer.new()
	box.add_child(UiKit.label("CONTROLS", 24, UiKit.ACCENT))
	var lines := [
		["W A S D", "Move"], ["Mouse", "Look"], ["Left mouse", "Fire"],
		["Right mouse (hold)", "Aim down sights"], ["Shift", "Sprint"],
		["Ctrl / C (hold)", "Crouch"], ["Space", "Jump"], ["R", "Reload"],
		["B", "Change fire mode"], ["1 / 2 / Q / wheel", "Switch weapon"],
		["V", "First / third person"], ["Tab (hold)", "Scoreboard"], ["Esc", "Pause"],
	]
	for line: Array in lines:
		box.add_child(UiKit.row(line[0], UiKit.label(line[1], 15)))
	_swap(box)
