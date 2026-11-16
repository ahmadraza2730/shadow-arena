class_name LoadoutPanel
extends VBoxContainer
## Loadout screen: pick a primary and a secondary weapon, fit attachments
## and compare stats. Choices are stored in Game.loadout and saved; in a
## match they take effect on the next respawn.

const SLOT_TITLES := {"scope": "Scope", "grip": "Grip", "muzzle": "Muzzle", "magazine": "Magazine"}

var _editing_slot := "primary"
var _weapon_list: VBoxContainer
var _detail: VBoxContainer
var _slot_buttons: Dictionary = {}


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(UiKit.label("LOADOUT", 24, UiKit.ACCENT))

	var tabs := HBoxContainer.new()
	for slot: String in ["primary", "secondary"]:
		var tab := UiKit.button(slot.to_upper(), _select_slot.bind(slot), 15)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(tab)
		_slot_buttons[slot] = tab
	add_child(tabs)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_weapon_list = VBoxContainer.new()
	_weapon_list.custom_minimum_size = Vector2(230, 0)
	columns.add_child(_weapon_list)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 6)
	columns.add_child(_detail)
	add_child(columns)
	_refresh()


func _select_slot(slot: String) -> void:
	_editing_slot = slot
	_refresh()


func _select_weapon(id: String) -> void:
	Game.loadout[_editing_slot] = id
	Game.save_settings()
	_refresh()


func _refresh() -> void:
	for slot: String in _slot_buttons:
		(_slot_buttons[slot] as Button).modulate = UiKit.ACCENT if slot == _editing_slot else Color.WHITE
	for child in _weapon_list.get_children():
		child.queue_free()
	var selected: String = Game.loadout[_editing_slot]
	for id in WeaponDB.weapon_ids(_editing_slot):
		var row: Dictionary = WeaponDB.weapons()[id]
		var text := "%s\n%s" % [row["name"], str(row["category"]).to_upper()]
		var entry := UiKit.button(text, _select_weapon.bind(id), 14)
		entry.custom_minimum_size = Vector2(0, 52)
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if id == selected:
			entry.modulate = UiKit.ACCENT
		_weapon_list.add_child(entry)
	_build_detail(selected)


func _build_detail(id: String) -> void:
	for child in _detail.get_children():
		child.queue_free()
	var data := WeaponDB.build(id, Game.get_attachments(id))
	_detail.add_child(UiKit.label(data.display_name, 22))
	_detail.add_child(UiKit.label("%s  |  %s" % [data.style, _modes_text(data)], 13, UiKit.DIM))

	# Stat bars: value normalised against the best weapon in the table.
	_stat("Damage", data.damage * data.pellets, 110.0, "%d" % int(data.damage * data.pellets))
	_stat("Fire rate", data.rpm, 1100.0, "%d rpm" % int(data.rpm))
	_stat("Range", data.falloff_start, 200.0, "%d m" % int(data.falloff_start))
	_stat("Accuracy", 1.0 / (0.3 + data.hip_spread), 1.0 / 1.8, "%.1f deg" % data.hip_spread)
	_stat("Recoil control", 1.0 / (0.3 + data.recoil_at(0).x), 1.0 / 0.62, "%.2f deg" % data.recoil_at(0).x)
	_stat("Mobility", data.move_mult - 0.8, 0.25, "%d%%" % int(data.move_mult * 100.0))
	_detail.add_child(UiKit.label("Magazine %d   Reload %.1f s   Headshot x%.2f   Zoom FOV %d" % [
			data.mag_size, data.reload_time, data.headshot_mult, int(data.ads_fov)], 13, UiKit.DIM))

	_detail.add_child(UiKit.label("Attachments", 17))
	for slot: String in ["scope", "grip", "muzzle", "magazine"]:
		var options := WeaponDB.attachments_for(id, slot)
		if options.is_empty():
			continue
		var picker := OptionButton.new()
		picker.add_item("None")
		var current: String = Game.get_attachments(id).get(slot, "")
		for i in options.size():
			picker.add_item("%s  -  %s" % [options[i]["name"], options[i]["desc"]])
			if options[i]["id"] == current:
				picker.selected = i + 1
		picker.item_selected.connect(func(index: int) -> void:
			Game.set_attachment(id, slot, "" if index == 0 else str(options[index - 1]["id"]))
			Game.save_settings()
			_build_detail.call_deferred(id))
		_detail.add_child(UiKit.row(SLOT_TITLES[slot], picker))


func _modes_text(data: WeaponData) -> String:
	var names: Array[String] = []
	for mode in data.fire_modes:
		names.append(WeaponData.MODE_LABELS[mode])
	return " / ".join(names)


func _stat(title: String, value: float, best: float, text: String) -> void:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(value / best, 0.03, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.add_theme_stylebox_override("background", UiKit.style(Color(1, 1, 1, 0.08), 2))
	bar.add_theme_stylebox_override("fill", UiKit.style(UiKit.ACCENT, 2))
	var box := HBoxContainer.new()
	var name_label := UiKit.label(title, 14, UiKit.DIM)
	name_label.custom_minimum_size = Vector2(120, 0)
	box.add_child(name_label)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(bar)
	var value_label := UiKit.label(text, 14)
	value_label.custom_minimum_size = Vector2(80, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(value_label)
	_detail.add_child(box)
