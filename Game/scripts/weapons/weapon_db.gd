class_name WeaponDB
extends RefCounted
## Loads the weapon and attachment data tables (JSON) once and hands out
## WeaponData objects. To add or rebalance a weapon, edit data/weapons.json;
## no code changes are needed.

const WEAPONS_PATH := "res://data/weapons.json"
const ATTACHMENTS_PATH := "res://data/attachments.json"

static var _weapons: Dictionary = {}       # id -> row Dictionary
static var _attachments: Dictionary = {}   # id -> row Dictionary
static var _weapon_order: Array[String] = []
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	for row: Dictionary in _read_rows(WEAPONS_PATH):
		_weapons[row["id"]] = row
		_weapon_order.append(row["id"])
	for row: Dictionary in _read_rows(ATTACHMENTS_PATH):
		_attachments[row["id"]] = row


static func _read_rows(path: String) -> Array:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Array:
		return parsed
	push_error("WeaponDB: could not read %s" % path)
	return []


## id -> raw row, for every weapon.
static func weapons() -> Dictionary:
	_load()
	return _weapons


## id -> raw row, for every attachment.
static func attachments() -> Dictionary:
	_load()
	return _attachments


## Weapon ids in table order, optionally filtered by slot.
static func weapon_ids(slot: String = "") -> Array[String]:
	_load()
	var ids: Array[String] = []
	for id in _weapon_order:
		if slot == "" or _weapons[id]["slot"] == slot:
			ids.append(id)
	return ids


## Attachment rows that fit a weapon in a given slot.
static func attachments_for(weapon_id: String, slot: String) -> Array[Dictionary]:
	_load()
	var result: Array[Dictionary] = []
	var weapon: Dictionary = _weapons[weapon_id]
	if not (weapon["attach"] as Array).has(slot):
		return result
	for att: Dictionary in _attachments.values():
		if att["slot"] == slot and (att["categories"] as Array).has(weapon["category"]):
			result.append(att)
	return result


## Base stats + chosen attachments = the weapon actually used in a match.
## `chosen` is { slot: attachment_id }.
static func build(weapon_id: String, chosen: Dictionary = {}) -> WeaponData:
	_load()
	var data := WeaponData.from_dict(_weapons[weapon_id])
	for slot: String in chosen:
		var att_id: String = chosen[slot]
		if not _attachments.has(att_id):
			continue
		var att: Dictionary = _attachments[att_id]
		if data.attach_slots.has(att["slot"]) and (att["categories"] as Array).has(data.category):
			data.apply_attachment(att)
	return data
