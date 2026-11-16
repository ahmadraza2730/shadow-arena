class_name OnlinePanel
extends VBoxContainer
## Online play screen: your name, HOST a match, JOIN by room code, or pick
## an open room from the live list.

var _status: Label
var _name_edit: LineEdit
var _code_edit: LineEdit
var _host_button: Button
var _join_button: Button
var _rooms_box: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(UiKit.label("PLAY ONLINE", 24, UiKit.ACCENT))
	add_child(UiKit.label("4 v 4 Team Deathmatch. Up to %d real players per match; bots fill the other slots."
			% Net.MAX_HUMANS, 14, UiKit.DIM))

	if Game.menu_message != "":
		add_child(UiKit.label(Game.menu_message, 16, Color(1.0, 0.45, 0.35)))
		Game.menu_message = ""

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = Net.player_name()
	_name_edit.text = str(Game.settings.get("player_name", ""))
	_name_edit.max_length = 16
	_name_edit.text_changed.connect(func(text: String) -> void:
		Game.settings["player_name"] = text.strip_edges()
		Game.save_settings())
	add_child(UiKit.row("Your name", _name_edit))

	_status = UiKit.label("", 15)
	add_child(UiKit.row("Server", _status))

	_host_button = UiKit.button("HOST A MATCH", _on_host, 18)
	add_child(_host_button)

	var join_row := HBoxContainer.new()
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "Room code (e.g. K7QM)"
	_code_edit.max_length = 4
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.text_submitted.connect(func(_t: String) -> void: _on_join(_code_edit.text))
	join_row.add_child(_code_edit)
	_join_button = UiKit.button("JOIN", func() -> void: _on_join(_code_edit.text), 18)
	_join_button.custom_minimum_size = Vector2(110, 40)
	join_row.add_child(_join_button)
	add_child(join_row)

	add_child(UiKit.label("Open rooms", 17))
	_rooms_box = VBoxContainer.new()
	add_child(_rooms_box)

	Net.status_changed.connect(_on_status)
	Net.rooms_changed.connect(_refresh_rooms)
	Net.open_lobby()
	_on_status(Net.status)
	_refresh_rooms()


func _exit_tree() -> void:
	if Net.status_changed.is_connected(_on_status):
		Net.status_changed.disconnect(_on_status)
		Net.rooms_changed.disconnect(_refresh_rooms)


func _on_status(text: String) -> void:
	_status.text = text
	var ready := Net.is_connected_to_relay()
	_host_button.disabled = not ready
	_join_button.disabled = not ready


func _on_host() -> void:
	if Net.is_online():
		return            # already starting (double click)
	Net.host_room()
	Game.start_match()


func _on_join(code: String) -> void:
	code = code.strip_edges().to_upper()
	if code.length() != 4:
		_status.text = "Room codes have 4 letters/numbers"
		return
	if Net.is_online():
		return            # already joining (double click)
	Net.join_room(code)
	Game.start_match()


func _refresh_rooms() -> void:
	for child in _rooms_box.get_children():
		child.queue_free()
	if Net.rooms.is_empty():
		_rooms_box.add_child(UiKit.label("No open rooms right now. Host one and share the code!", 14, UiKit.DIM))
		return
	for code: String in Net.rooms:
		var room: Dictionary = Net.rooms[code]
		var humans := int(room.get("humans", 1))
		var full := humans >= int(room.get("max", Net.MAX_HUMANS))
		var text := "%s   %s's match   %d/%d players   %s" % [code, str(room.get("host", "?")),
				humans, int(room.get("max", Net.MAX_HUMANS)), str(room.get("state", ""))]
		var button := UiKit.button(text, _on_join.bind(code), 15)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = full
		_rooms_box.add_child(button)
