class_name Hud
extends CanvasLayer
## In-match interface: crosshair, hit markers, sniper scope, health, ammo,
## team scores and timer, kill feed, damage vignette, respawn and
## countdown messages, the Tab scoreboard, the pause menu and the
## end-of-match screen. Everything is created in code.

const FEED_LIFETIME := 5.0
const FEED_MAX := 5

var _match: TdmMatch
var _player: PlayerController

var _overlay: Control              # custom-drawn layer (crosshair, scope, hit marker)
var _vignette: TextureRect
var _health_bar: ProgressBar
var _health_label: Label
var _ammo_label: Label
var _weapon_label: Label
var _score_labels: Array[Label] = []
var _timer_label: Label
var _feed: VBoxContainer
var _feed_ttl: Array[float] = []
var _center_label: Label
var _sub_label: Label
var _fps_label: Label
var _scoreboard: PanelContainer
var _scoreboard_body: VBoxContainer
var _pause_panel: PanelContainer
var _pause_content: VBoxContainer
var _end_panel: PanelContainer

var _net_label: Label
var _menu_open := false
var _hit_marker := 0.0
var _hit_color := Color.WHITE
var _damage_flash := 0.0
var _kill_text_ttl := 0.0
var _board_refresh := 0.0


func setup(p_match: TdmMatch, p_player: PlayerController) -> void:
	_match = p_match
	_player = p_player
	_match.kill_feed.connect(_on_kill_feed)
	_match.state_changed.connect(_on_state_changed)
	_player.dealt_damage.connect(_on_dealt_damage)
	_player.damaged.connect(_on_damaged)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS      # keeps working while paused
	layer = 10
	_build()


# ------------------------------------------------------------------ build
func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Permanent soft dark corners: a cheap "camera lens" look.
	var lens_gradient := Gradient.new()
	lens_gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	lens_gradient.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.32)])
	var lens_texture := GradientTexture2D.new()
	lens_texture.gradient = lens_gradient
	lens_texture.fill = GradientTexture2D.FILL_RADIAL
	lens_texture.fill_from = Vector2(0.5, 0.5)
	lens_texture.fill_to = Vector2(1.05, 0.5)
	var lens := TextureRect.new()
	lens.texture = lens_texture
	lens.stretch_mode = TextureRect.STRETCH_SCALE
	lens.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lens)

	# Red edge glow when hurt (a radial gradient, transparent in the middle).
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color(0.7, 0, 0, 0), Color(0.7, 0, 0, 0), Color(0.7, 0, 0, 0.85)])
	var vignette_texture := GradientTexture2D.new()
	vignette_texture.gradient = gradient
	vignette_texture.fill = GradientTexture2D.FILL_RADIAL
	vignette_texture.fill_from = Vector2(0.5, 0.5)
	vignette_texture.fill_to = Vector2(1.0, 0.5)
	_vignette = TextureRect.new()
	_vignette.texture = vignette_texture
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	root.add_child(_vignette)

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	root.add_child(_overlay)

	# --- Top centre: score | timer | score ---
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.position.y = 10
	top.add_theme_constant_override("separation", 6)
	root.add_child(top)
	for team in 2:
		var holder := UiKit.panel(Game.TEAM_COLORS[team].darkened(0.45))
		holder.custom_minimum_size = Vector2(120, 0)
		var text := UiKit.label("0", 24)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		holder.add_child(text)
		_score_labels.append(text)
		top.add_child(holder)
		if team == 0:
			var clock := UiKit.panel()
			clock.custom_minimum_size = Vector2(100, 0)
			_timer_label = UiKit.label("10:00", 24)
			_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			clock.add_child(_timer_label)
			top.add_child(clock)

	# --- Top right: kill feed ---
	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.position = Vector2(-16, 14)
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(_feed)

	# --- Top left: FPS ---
	_fps_label = UiKit.label("", 14, UiKit.DIM)
	_fps_label.position = Vector2(12, 10)
	root.add_child(_fps_label)
	# --- Under it: online room info ---
	_net_label = UiKit.label("", 14, UiKit.ACCENT)
	_net_label.position = Vector2(12, 30)
	root.add_child(_net_label)

	# --- Bottom left: health ---
	var health_box := VBoxContainer.new()
	health_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	health_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	health_box.position = Vector2(24, -24)
	root.add_child(health_box)
	_health_label = UiKit.label("100", 30)
	health_box.add_child(_health_label)
	_health_bar = ProgressBar.new()
	_health_bar.custom_minimum_size = Vector2(240, 12)
	_health_bar.show_percentage = false
	_health_bar.max_value = 100.0
	_health_bar.add_theme_stylebox_override("background", UiKit.style(Color(0, 0, 0, 0.55), 2))
	_health_bar.add_theme_stylebox_override("fill", UiKit.style(Color(0.9, 0.9, 0.9), 2))
	health_box.add_child(_health_bar)

	# --- Bottom right: weapon and ammo ---
	var ammo_box := VBoxContainer.new()
	ammo_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ammo_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ammo_box.position = Vector2(-24, -24)
	root.add_child(ammo_box)
	_ammo_label = UiKit.label("30", 40)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_box.add_child(_ammo_label)
	_weapon_label = UiKit.label("", 15, UiKit.DIM)
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_box.add_child(_weapon_label)

	# --- Centre messages ---
	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.position.y = -150
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_center_label = UiKit.label("LOADING...", 44)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_center_label)
	_sub_label = UiKit.label("Building navigation", 18, UiKit.DIM)
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_sub_label)

	_build_scoreboard(root)
	_build_pause(root)


func _build_scoreboard(root: Control) -> void:
	_scoreboard = UiKit.panel()
	_scoreboard.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_scoreboard.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_scoreboard.grow_vertical = Control.GROW_DIRECTION_BOTH
	_scoreboard.custom_minimum_size = Vector2(640, 0)
	_scoreboard.visible = false
	_scoreboard_body = VBoxContainer.new()
	_scoreboard.add_child(_scoreboard_body)
	root.add_child(_scoreboard)


func _build_pause(root: Control) -> void:
	_pause_panel = UiKit.panel(Color(0.05, 0.06, 0.08, 0.96))
	_pause_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_pause_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pause_panel.custom_minimum_size = Vector2(720, 460)
	_pause_panel.visible = false
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	_pause_panel.add_child(columns)
	var buttons := VBoxContainer.new()
	buttons.custom_minimum_size = Vector2(180, 0)
	buttons.add_child(UiKit.label("PAUSED", 26, UiKit.ACCENT))
	buttons.add_child(UiKit.button("RESUME", _set_paused.bind(false)))
	buttons.add_child(UiKit.button("LOADOUT", _pause_show.bind("loadout")))
	buttons.add_child(UiKit.button("SETTINGS", _pause_show.bind("settings")))
	buttons.add_child(UiKit.button("LEAVE MATCH" if Net.is_online() else "MAIN MENU", Game.goto_menu))
	columns.add_child(buttons)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pause_content = VBoxContainer.new()
	_pause_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_pause_content)
	columns.add_child(scroll)
	root.add_child(_pause_panel)


func _pause_show(which: String) -> void:
	for child in _pause_content.get_children():
		child.queue_free()
	if which == "loadout":
		_pause_content.add_child(LoadoutPanel.new())
		_pause_content.add_child(UiKit.label("Changes apply on your next respawn.", 13, UiKit.DIM))
	else:
		_pause_content.add_child(SettingsPanel.new())


# ------------------------------------------------------------------ input
func _unhandled_input(event: InputEvent) -> void:
	if _match == null:
		return
	if event.is_action_pressed("pause") and _match.state != TdmMatch.MatchState.ENDED \
			and _match.state != TdmMatch.MatchState.LOADING:
		_set_paused(not _menu_open)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not _menu_open \
			and _match.state in [TdmMatch.MatchState.PLAYING, TdmMatch.MatchState.COUNTDOWN] \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Clicking the window grabs the mouse again (e.g. after Alt+Tab).
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Opens or closes the pause menu. Offline the game freezes; online it
## keeps running (other players do not stop), only your controls stop.
func _set_paused(paused: bool) -> void:
	_menu_open = paused
	if not Net.is_online():
		get_tree().paused = paused
	_pause_panel.visible = paused
	if paused:
		_pause_show("settings")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED


# ----------------------------------------------------------------- update
func _process(delta: float) -> void:
	if _match == null or _player == null:
		return
	var weapon := _player.current_weapon()

	# Health.
	_health_bar.value = _player.health
	_health_label.text = str(int(ceil(_player.health)))
	var low := _player.health < 35.0 and _player.alive
	_health_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3) if low else UiKit.TEXT)

	# Ammo and weapon.
	_ammo_label.text = "RELOADING" if weapon.is_reloading else "%d / %d" % [weapon.ammo, weapon.data.mag_size]
	_ammo_label.add_theme_font_size_override("font_size", 24 if weapon.is_reloading else 40)
	var other := _player.weapons[1 - _player.weapon_index]
	_weapon_label.text = "%s  [%s]\n%s: %s" % [weapon.data.display_name,
			WeaponData.MODE_LABELS[weapon.fire_mode()],
			"1" if _player.weapon_index == 1 else "2", other.data.display_name]

	# Scores and clock.
	for team in 2:
		_score_labels[team].text = "%s  %d" % [Game.TEAM_NAMES[team], _match.scores[team]]
	var seconds := int(ceil(_match.time_left))
	_timer_label.text = "%d:%02d" % [seconds / 60, seconds % 60]

	# Kill feed entries fade out.
	for i in range(_feed_ttl.size() - 1, -1, -1):
		_feed_ttl[i] -= delta
		var entry := _feed.get_child(i) as Control
		entry.modulate.a = clampf(_feed_ttl[i], 0.0, 1.0)
		if _feed_ttl[i] <= 0.0:
			entry.queue_free()
			_feed.remove_child(entry)
			_feed_ttl.remove_at(i)

	# Hurt vignette: a flash per hit plus a steady glow at low health.
	_damage_flash = maxf(_damage_flash - delta * 1.8, 0.0)
	var steady := 0.0
	if _player.alive and _player.health < 50.0:
		steady = (1.0 - _player.health / 50.0) * 0.6
	_vignette.modulate.a = clampf(maxf(_damage_flash, steady), 0.0, 1.0)

	_hit_marker = maxf(_hit_marker - delta, 0.0)
	_update_center(delta)

	if Net.is_online():
		var text := "ROOM %s   %d/%d players" % [Net.room_code, Net.human_count(), Net.MAX_HUMANS]
		if Net.is_client() and _match.net:
			text += "   %d ms" % int(_match.net.ping_ms)
		elif Net.is_host():
			text += "   (you are the host)"
		_net_label.text = text
	_fps_label.visible = bool(Game.settings["show_fps"])
	if _fps_label.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()

	# Scoreboard while Tab is held (always on the end screen).
	var show_board := Input.is_action_pressed("scoreboard") and not _menu_open \
			and _match.state != TdmMatch.MatchState.ENDED
	_scoreboard.visible = show_board
	if show_board:
		_board_refresh -= delta
		if _board_refresh <= 0.0:
			_board_refresh = 0.3
			_fill_scoreboard(_scoreboard_body)

	_overlay.queue_redraw()


func _update_center(delta: float) -> void:
	_kill_text_ttl = maxf(_kill_text_ttl - delta, 0.0)
	match _match.state:
		TdmMatch.MatchState.LOADING:
			_center_label.text = "LOADING..."
			_sub_label.text = "Building navigation"
		TdmMatch.MatchState.COUNTDOWN:
			_center_label.text = str(int(ceil(_match.countdown_left)))
			_sub_label.text = "Team %s  -  first to %d kills" % [Game.TEAM_NAMES[0], TdmMatch.KILL_LIMIT]
		TdmMatch.MatchState.PLAYING:
			if not _player.alive:
				_center_label.text = "ELIMINATED"
				_sub_label.text = "Respawning in %.1f" % _match.player_respawn_in()
			elif _kill_text_ttl <= 0.0:
				_center_label.text = ""
				_sub_label.text = ""
		TdmMatch.MatchState.ENDED:
			_center_label.text = ""
			_sub_label.text = ""


# -------------------------------------------------------------- overlay
## Custom drawing: sniper scope, crosshair and hit marker.
func _draw_overlay() -> void:
	if _player == null:
		return
	var size := _overlay.size
	var center := size * 0.5
	var weapon := _player.current_weapon()

	if _player.is_scoped():
		# Black mask with a round hole: 4 bars around a square, plus a
		# thick ring that fills the square's corners.
		var radius := size.y * 0.46
		var black := Color.BLACK
		_overlay.draw_rect(Rect2(0, 0, center.x - radius, size.y), black)
		_overlay.draw_rect(Rect2(center.x + radius, 0, size.x - center.x - radius, size.y), black)
		_overlay.draw_rect(Rect2(0, 0, size.x, center.y - radius), black)
		_overlay.draw_rect(Rect2(0, center.y + radius, size.x, size.y - center.y - radius), black)
		_overlay.draw_arc(center, radius * 1.22, 0.0, TAU, 96, black, radius * 0.46)
		var line := Color(0, 0, 0, 0.9)
		_overlay.draw_line(center - Vector2(radius, 0), center - Vector2(12, 0), line, 2.0)
		_overlay.draw_line(center + Vector2(12, 0), center + Vector2(radius, 0), line, 2.0)
		_overlay.draw_line(center + Vector2(0, 12), center + Vector2(0, radius), line, 2.0)
		_overlay.draw_line(center - Vector2(0, radius), center - Vector2(0, 12), line, 1.0)
		# Hold-over ticks below the centre for bullet drop.
		for i in range(1, 5):
			_overlay.draw_line(center + Vector2(-6, i * 22), center + Vector2(6, i * 22), line, 1.0)
		_overlay.draw_circle(center, 1.5, Color(1, 0.2, 0.2))
	elif _player.alive and _match.state != TdmMatch.MatchState.ENDED:
		# Crosshair gap follows the real spread cone, so what you see is
		# where the bullets can go. It fades out as you aim down sights
		# in first person (the weapon's own sights take over).
		var alpha := 1.0
		if not _player.is_third_person:
			alpha = 1.0 - smoothstep(0.3, 0.9, _player.ads_amount)
		if alpha > 0.02:
			var camera := _player.camera()
			var spread := deg_to_rad(weapon.current_spread())
			var gap := tan(spread) / tan(deg_to_rad(camera.fov * 0.5)) * center.y + 3.0
			var color := Color(1, 1, 1, 0.95 * alpha)
			var outline := Color(0, 0, 0, 0.6 * alpha)
			var length := 9.0
			# Each tick is drawn twice: a dark outline, then the white line,
			# so the crosshair stays visible on bright and dark surfaces.
			for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
				var from := center + direction * gap
				var to := center + direction * (gap + length)
				_overlay.draw_line(from - direction, to + direction, outline, 4.0)
				_overlay.draw_line(from, to, color, 2.0)
			_overlay.draw_circle(center, 2.2, outline)
			_overlay.draw_circle(center, 1.2, color)

	if _hit_marker > 0.0:
		var color := _hit_color
		color.a = clampf(_hit_marker / 0.12, 0.0, 1.0)
		for direction: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			_overlay.draw_line(center + direction * 7.0, center + direction * 15.0, color, 2.5)


# --------------------------------------------------------------- signals
func _on_dealt_damage(_victim: Combatant, _amount: float, headshot: bool, killed: bool) -> void:
	_hit_marker = 0.22 if killed else 0.14
	if killed:
		_hit_color = Color(1.0, 0.25, 0.2)
		Sfx.play("kill", null, -4.0)
		_center_label.text = ""
		_sub_label.text = "ELIMINATED  %s%s" % [_victim.display_name, "  (HEADSHOT)" if headshot else ""]
		_kill_text_ttl = 1.6
	elif headshot:
		_hit_color = Color(1.0, 0.8, 0.2)
		Sfx.play("headshot", null, -5.0)
	else:
		_hit_color = Color.WHITE
		Sfx.play("hit", null, -7.0)


func _on_damaged(amount: float, _attacker: Combatant, _headshot: bool) -> void:
	_damage_flash = clampf(_damage_flash + amount / 60.0, 0.25, 1.0)
	Sfx.play("hurt", null, -4.0)


func _on_kill_feed(killer: Combatant, victim: Combatant, weapon: WeaponData, headshot: bool) -> void:
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_OFF
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.custom_minimum_size = Vector2(360, 0)
	line.add_theme_font_size_override("normal_font_size", 15)
	var killer_text := "?"
	if killer:
		killer_text = "[color=#%s]%s[/color]" % [Game.TEAM_COLORS[killer.team].to_html(false), killer.display_name]
	var weapon_text := weapon.display_name if weapon else "killed"
	if headshot:
		weapon_text += " (HS)"
	line.text = "[right]%s  [color=#aaaaaa]%s[/color]  [color=#%s]%s[/color][/right]" % [
			killer_text, weapon_text, Game.TEAM_COLORS[victim.team].to_html(false), victim.display_name]
	_feed.add_child(line)
	_feed_ttl.append(FEED_LIFETIME)
	if _feed_ttl.size() > FEED_MAX:
		var oldest := _feed.get_child(0)
		_feed.remove_child(oldest)
		oldest.queue_free()
		_feed_ttl.remove_at(0)


func _on_state_changed(new_state: int) -> void:
	if new_state == TdmMatch.MatchState.ENDED:
		_show_end_screen()


# ------------------------------------------------------ scoreboard / end
func _fill_scoreboard(body: VBoxContainer) -> void:
	for child in body.get_children():
		child.queue_free()
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	body.add_child(columns)
	for team in 2:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(column)
		column.add_child(UiKit.label("%s   %d" % [Game.TEAM_NAMES[team], _match.scores[team]],
				20, Game.TEAM_COLORS[team]))
		column.add_child(_board_row("Name", "K", "D", "HS", UiKit.DIM))
		for fighter: Combatant in _match.team_roster(team):
			var color := UiKit.ACCENT if fighter == _player else UiKit.TEXT
			column.add_child(_board_row(fighter.display_name, str(fighter.kills),
					str(fighter.deaths), str(fighter.headshots), color))


func _board_row(name: String, kills: String, deaths: String, headshots: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := UiKit.label(name, 16, color)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	for text: String in [kills, deaths, headshots]:
		var cell := UiKit.label(text, 16, color)
		cell.custom_minimum_size = Vector2(44, 0)
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(cell)
	return row


func _show_end_screen() -> void:
	_pause_panel.visible = false
	_end_panel = UiKit.panel(Color(0.05, 0.06, 0.08, 0.95))
	_end_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_end_panel.custom_minimum_size = Vector2(680, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_end_panel.add_child(box)

	var title := "DRAW"
	var color := UiKit.TEXT
	if _match.winner == _player.team:
		title = "VICTORY"
		color = UiKit.ACCENT
	elif _match.winner >= 0:
		title = "DEFEAT"
		color = Color(1.0, 0.35, 0.3)
	var heading := UiKit.label(title, 52, color)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	var board := VBoxContainer.new()
	box.add_child(board)
	_fill_scoreboard(board)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	if Net.is_client():
		buttons.add_child(UiKit.label("Waiting for the host to start the next match...", 16, UiKit.DIM))
	else:
		var again := UiKit.button("PLAY AGAIN", Game.start_match)
		again.custom_minimum_size = Vector2(180, 44)
		buttons.add_child(again)
	var menu := UiKit.button("LEAVE" if Net.is_online() else "MAIN MENU", Game.goto_menu)
	menu.custom_minimum_size = Vector2(180, 44)
	buttons.add_child(menu)
	box.add_child(buttons)
	get_child(0).add_child(_end_panel)
