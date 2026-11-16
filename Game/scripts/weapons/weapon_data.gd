class_name WeaponData
extends RefCounted
## The stats of one weapon: exactly one row of data/weapons.json, plus any
## attachment modifiers applied on top. Pure data, no behaviour.

enum FireMode { SEMI, AUTO, BURST, BOLT }

const MODE_NAMES := {"semi": FireMode.SEMI, "auto": FireMode.AUTO,
		"burst": FireMode.BURST, "bolt": FireMode.BOLT}
const MODE_LABELS: Array[String] = ["SEMI", "AUTO", "BURST", "BOLT"]

var id := ""
var display_name := ""
var style := ""                 # which real weapon it is modelled on
var category := "ar"            # ar / sniper / smg / shotgun / pistol
var slot := "primary"           # primary / secondary

var damage := 20.0              # per bullet (per pellet for shotguns)
var headshot_mult := 2.0
var rpm := 600.0                # rounds per minute
var mag_size := 30
var reload_time := 2.0          # seconds
var falloff_start := 30.0       # full damage up to this distance (m)
var falloff_end := 80.0         # minimum damage from this distance (m)
var min_damage_mult := 0.7
var max_range := 300.0
var fire_modes: Array[int] = [FireMode.AUTO]
var pellets := 1

var hip_spread := 2.0           # cone half-angle in degrees, from the hip
var ads_spread := 0.3           # cone half-angle in degrees, aiming
var bloom := 0.1                # degrees added per shot (decays)
var move_spread := 1.0          # degrees added at full walking speed

var recoil_pattern: Array[Vector2] = []   # per shot: x = up, y = right (degrees)
var recoil_random := 0.1        # random sideways degrees per shot
var recoil_recovery := 0.6      # fraction of the climb that settles back

var ads_fov := 55.0
var ads_time := 0.2
var projectile := false         # true = simulated bullet with travel time + drop
var bullet_speed := 800.0       # m/s
var drop_scale := 1.0           # multiplier on gravity for bullet drop
var move_mult := 1.0            # movement speed multiplier while held

var sound := "shot_rifle"
var suppressed := false
var attach_slots: Array[String] = []
var attachments: Dictionary = {}          # slot -> attachment id (applied)
var model_length := 0.8
var model_color := Color(0.2, 0.2, 0.2)


static func from_dict(row: Dictionary) -> WeaponData:
	var w := WeaponData.new()
	w.id = row["id"]
	w.display_name = row["name"]
	w.style = row.get("style", "")
	w.category = row["category"]
	w.slot = row["slot"]
	w.damage = row["damage"]
	w.headshot_mult = row["headshot_mult"]
	w.rpm = row["rpm"]
	w.mag_size = int(row["mag"])
	w.reload_time = row["reload"]
	w.falloff_start = row["falloff_start"]
	w.falloff_end = row["falloff_end"]
	w.min_damage_mult = row["min_damage_mult"]
	w.max_range = row["max_range"]
	w.fire_modes.clear()
	for mode_name: String in row["modes"]:
		w.fire_modes.append(MODE_NAMES[mode_name])
	w.pellets = int(row["pellets"])
	w.hip_spread = row["hip_spread"]
	w.ads_spread = row["ads_spread"]
	w.bloom = row["bloom"]
	w.move_spread = row["move_spread"]
	for pair: Array in row["recoil"]:
		w.recoil_pattern.append(Vector2(pair[0], pair[1]))
	w.recoil_random = row["recoil_random"]
	w.recoil_recovery = row["recoil_recovery"]
	w.ads_fov = row["ads_fov"]
	w.ads_time = row["ads_time"]
	w.projectile = row["projectile"]
	w.bullet_speed = row["bullet_speed"]
	w.drop_scale = row["drop"]
	w.move_mult = row["move_mult"]
	w.sound = row["sound"]
	for slot_name: String in row["attach"]:
		w.attach_slots.append(slot_name)
	w.model_length = row["length"]
	var c: Array = row["color"]
	w.model_color = Color(c[0], c[1], c[2])
	return w


## Applies one attachment row (from data/attachments.json) to these stats.
func apply_attachment(att: Dictionary) -> void:
	attachments[att["slot"]] = att["id"]
	var mods: Dictionary = att["mods"]
	if mods.has("ads_fov"):
		ads_fov = mods["ads_fov"]
	ads_time *= float(mods.get("ads_time_mult", 1.0))
	ads_spread *= float(mods.get("ads_spread_mult", 1.0))
	var spread_mult := float(mods.get("spread_mult", 1.0))
	hip_spread *= spread_mult
	ads_spread *= spread_mult
	var v_mult := float(mods.get("recoil_v_mult", 1.0))
	var h_mult := float(mods.get("recoil_h_mult", 1.0))
	for i in recoil_pattern.size():
		recoil_pattern[i] = Vector2(recoil_pattern[i].x * v_mult, recoil_pattern[i].y * h_mult)
	recoil_random *= h_mult
	mag_size = int(round(mag_size * float(mods.get("mag_mult", 1.0))))
	reload_time *= float(mods.get("reload_mult", 1.0))
	if mods.get("suppressed", false):
		suppressed = true


## Seconds between two shots.
func shot_interval() -> float:
	return 60.0 / rpm


## Damage of one bullet after distance falloff (before headshot bonus).
func damage_at(distance: float) -> float:
	if distance <= falloff_start:
		return damage
	var t := clampf((distance - falloff_start) / maxf(falloff_end - falloff_start, 0.01), 0.0, 1.0)
	return damage * lerpf(1.0, min_damage_mult, t)


## Recoil kick for the Nth shot of a spray (x = up, y = right, degrees).
func recoil_at(shot_index: int) -> Vector2:
	if recoil_pattern.is_empty():
		return Vector2.ZERO
	return recoil_pattern[shot_index % recoil_pattern.size()]


## True when aiming should show the full-screen sniper scope.
func uses_scope_overlay() -> bool:
	return ads_fov <= 24.0
