extends Node
## Game (autoload)
##
## Global state shared by menus and matches:
##  - player settings (saved to user://settings.cfg)
##  - the chosen loadout
##  - graphics quality presets
##  - scene switching between the menu and a match

signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"
const MENU_SCENE := "res://scenes/main.tscn"
const MATCH_SCENE := "res://scenes/match.tscn"

## Physics layers (bit values).
const LAYER_WORLD := 1
const LAYER_CHARACTER := 2

const TEAM_NAMES: Array[String] = ["SHAHEEN", "MARKHOR"]
const TEAM_COLORS: Array[Color] = [Color(0.25, 0.6, 1.0), Color(1.0, 0.42, 0.25)]

const QUALITY_NAMES: Array[String] = ["Low", "Medium", "High"]
## Graphics presets. Index 0 = Low, 1 = Medium, 2 = High.
##  scale        3D render resolution (1.0 = native). Biggest FPS lever.
##  msaa         0 = off, 1 = 2x.
##  shadows      sun shadows on/off.  shadow_size = shadow map resolution.
##  glow         bloom post-process.
##  particles    multiplier on particle counts.
##  decals       how many bullet holes are kept.
##  casings/dust ejected shells and floating dust motes.
const QUALITY: Array[Dictionary] = [
	{"scale": 0.6, "msaa": 0, "fxaa": false, "shadows": false, "shadow_size": 1024,
		"shadow_distance": 40.0, "glow": false, "particles": 0.4, "decals": 16,
		"casings": false, "dust": false, "fog": true},
	{"scale": 0.8, "msaa": 0, "fxaa": true, "shadows": true, "shadow_size": 2048,
		"shadow_distance": 60.0, "glow": true, "particles": 0.7, "decals": 32,
		"casings": true, "dust": true, "fog": true},
	{"scale": 1.0, "msaa": 1, "fxaa": true, "shadows": true, "shadow_size": 4096,
		"shadow_distance": 90.0, "glow": true, "particles": 1.0, "decals": 64,
		"casings": true, "dust": true, "fog": true},
]

const DIFFICULTY_NAMES: Array[String] = ["Easy", "Normal", "Hard"]
const TIME_NAMES: Array[String] = ["Dusty Afternoon", "Golden Dusk", "Overcast Rain", "Random"]

var settings: Dictionary = {
	"quality": 1,
	"sensitivity": 1.0,
	"fov": 75.0,
	"volume": 0.8,
	"fullscreen": false,
	"vsync": true,
	"max_fps": 60,
	"show_fps": true,
	"difficulty": 1,
	"time_of_day": 0,
	"third_person": false,
}

## Chosen weapons and their attachments.
## attachments = { weapon_id: { slot: attachment_id } }
var loadout: Dictionary = {
	"primary": "ar_kestrel",
	"secondary": "pistol_wasp",
	"attachments": {},
}

## Set by the running match so any script can reach these systems.
var match_node: Node = null
var bullets: Node = null
var vfx: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply_settings()


func quality() -> Dictionary:
	return QUALITY[clampi(int(settings["quality"]), 0, 2)]


# ------------------------------------------------------------ persistence
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for key: String in settings:
		settings[key] = cfg.get_value("settings", key, settings[key])
	var saved: Variant = cfg.get_value("loadout", "data", null)
	if saved is Dictionary:
		for key: String in loadout:
			if saved.has(key):
				loadout[key] = saved[key]
	# Guard against weapons that no longer exist in the data table.
	if not WeaponDB.weapons().has(loadout["primary"]):
		loadout["primary"] = "ar_kestrel"
	if not WeaponDB.weapons().has(loadout["secondary"]):
		loadout["secondary"] = "pistol_wasp"


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key: String in settings:
		cfg.set_value("settings", key, settings[key])
	cfg.set_value("loadout", "data", loadout)
	cfg.save(SETTINGS_PATH)


# --------------------------------------------------------------- applying
func apply_settings() -> void:
	var window := get_window()
	var want_full: bool = settings["fullscreen"]
	var mode := Window.MODE_FULLSCREEN if want_full else Window.MODE_WINDOWED
	if window.mode != mode and DisplayServer.get_name() != "headless":
		window.mode = mode
	DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if settings["vsync"] else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(settings["max_fps"])
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(settings["volume"]), 0.0001)))
	apply_quality()
	settings_changed.emit()


## Pushes the current quality preset into the renderer.
func apply_quality() -> void:
	var q := quality()
	var viewport := get_viewport()
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = float(q["scale"])
	viewport.msaa_3d = Viewport.MSAA_2X if int(q["msaa"]) == 1 else Viewport.MSAA_DISABLED
	viewport.screen_space_aa = (Viewport.SCREEN_SPACE_AA_FXAA if q["fxaa"]
			else Viewport.SCREEN_SPACE_AA_DISABLED)
	RenderingServer.directional_shadow_atlas_set_size(int(q["shadow_size"]), true)


# ---------------------------------------------------------------- scenes
func start_match() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MATCH_SCENE)


func goto_menu() -> void:
	get_tree().paused = false
	match_node = null
	bullets = null
	vfx = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


# --------------------------------------------------------------- loadout
func get_attachments(weapon_id: String) -> Dictionary:
	var all: Dictionary = loadout["attachments"]
	if not all.has(weapon_id):
		all[weapon_id] = {}
	return all[weapon_id]


func set_attachment(weapon_id: String, slot: String, attachment_id: String) -> void:
	var slots := get_attachments(weapon_id)
	if attachment_id == "":
		slots.erase(slot)
	else:
		slots[slot] = attachment_id


## Builds the final WeaponData (base stats + attachments) for a loadout slot.
func build_loadout_weapon(slot: String) -> WeaponData:
	var id: String = loadout[slot]
	return WeaponDB.build(id, get_attachments(id))
