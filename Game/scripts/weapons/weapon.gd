class_name Weapon
extends Node
## One weapon in a character's hands. Handles ammo, fire modes, fire rate,
## spread, recoil and reloading. It does not know who is holding it beyond
## the Combatant interface, so the player and the bots share this code.
##
## The owner calls tick() every physics frame for the weapon it is holding.

signal fired
signal recoil_kick(kick: Vector2)          # x = up, y = right (degrees)
signal ammo_changed
signal reload_started(duration: float)
signal reload_finished

var data: WeaponData
var holder: Combatant
var ammo := 0
var is_reloading := false
var mode_index := 0
## Extra spread built up by firing; decays when you stop.
var bloom := 0.0

var _cooldown := 0.0
var _reload_left := 0.0
var _burst_left := 0
var _shot_index := 0
var _since_shot := 10.0
var _trigger_prev := false
var _empty_click_cooldown := 0.0


func setup(weapon_data: WeaponData, weapon_holder: Combatant) -> void:
	data = weapon_data
	holder = weapon_holder
	ammo = data.mag_size
	mode_index = 0


func fire_mode() -> int:
	return data.fire_modes[mode_index]


func cycle_fire_mode() -> void:
	if data.fire_modes.size() < 2:
		return
	mode_index = (mode_index + 1) % data.fire_modes.size()
	Sfx.play("switch", holder.global_position, -8.0, 1.3)
	ammo_changed.emit()


## 0..1 progress of the current reload (0 when not reloading).
func reload_progress() -> float:
	if not is_reloading:
		return 0.0
	return 1.0 - _reload_left / data.reload_time


## Seconds since the last shot (used for recoil recovery and animation).
func time_since_shot() -> float:
	return _since_shot


func refill() -> void:
	ammo = data.mag_size
	is_reloading = false
	_burst_left = 0
	_cooldown = 0.0
	bloom = 0.0
	ammo_changed.emit()


func start_reload() -> void:
	if is_reloading or ammo >= data.mag_size:
		return
	is_reloading = true
	_reload_left = data.reload_time
	_burst_left = 0
	Sfx.play("reload", holder.global_position, -6.0)
	reload_started.emit(data.reload_time)


## Called when the holder switches away: an unfinished reload is lost.
func holster() -> void:
	is_reloading = false
	_burst_left = 0
	_trigger_prev = false


func tick(delta: float, trigger: bool) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_empty_click_cooldown = maxf(_empty_click_cooldown - delta, 0.0)
	_since_shot += delta
	bloom = move_toward(bloom, 0.0, maxf(data.bloom, 0.05) * 5.0 * delta)
	# A pause in firing restarts the recoil pattern from its first shot.
	if _since_shot > 0.3:
		_shot_index = 0

	if is_reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			is_reloading = false
			ammo = data.mag_size
			ammo_changed.emit()
			reload_finished.emit()
		_trigger_prev = trigger
		return

	if _burst_left > 0:
		# Finish the burst even if the trigger was released.
		if _cooldown <= 0.0:
			_burst_left -= 1
			_shoot()
	elif trigger and _cooldown <= 0.0:
		var fresh_press := not _trigger_prev
		match fire_mode():
			WeaponData.FireMode.AUTO:
				_shoot()
			WeaponData.FireMode.SEMI, WeaponData.FireMode.BOLT:
				if fresh_press:
					_shoot()
			WeaponData.FireMode.BURST:
				if fresh_press:
					_burst_left = 2
					_shoot()
	_trigger_prev = trigger


## Current spread cone half-angle in degrees.
func current_spread() -> float:
	var ads := holder.ads_amount
	var spread := lerpf(data.hip_spread, data.ads_spread, ads)
	spread += bloom * (1.0 - 0.5 * ads)
	var speed := Vector2(holder.velocity.x, holder.velocity.z).length()
	spread += data.move_spread * clampf(speed / 5.0, 0.0, 1.5) * (1.0 - 0.5 * ads)
	if not holder.is_on_floor():
		spread += 3.0
	if holder.is_crouching:
		spread *= 0.8
	return spread


func _shoot() -> void:
	if ammo <= 0:
		_burst_left = 0
		if _empty_click_cooldown <= 0.0:
			_empty_click_cooldown = 0.25
			Sfx.play("empty", holder.global_position, -6.0)
		start_reload()
		return

	ammo -= 1
	_cooldown = data.shot_interval()
	if fire_mode() == WeaponData.FireMode.BURST:
		# Shots inside a burst are quick; then a short pause.
		_cooldown = data.shot_interval() * (0.75 if _burst_left > 0 else 2.2)

	var origin := holder.get_shot_origin()
	var aim := holder.get_shot_direction()
	var spread := deg_to_rad(current_spread())
	for i in data.pellets:
		Game.bullets.fire(holder, data, origin, _spread_direction(aim, spread))

	# Sound, muzzle flash and the ejected shell.
	var muzzle := holder.get_muzzle_position()
	if data.suppressed:
		Sfx.play("shot_suppressed", muzzle, -4.0, randf_range(0.95, 1.05))
	else:
		Sfx.play(data.sound, muzzle, 0.0, randf_range(0.96, 1.04))
		Game.vfx.muzzle_flash(muzzle, aim)
	Game.vfx.eject_casing(muzzle - aim * data.model_length * 0.6, aim)
	if fire_mode() == WeaponData.FireMode.BOLT:
		Sfx.play("bolt", holder.global_position, -8.0)

	# Recoil: the pattern entry for this shot plus a little randomness.
	var kick := data.recoil_at(_shot_index)
	kick.y += randf_range(-data.recoil_random, data.recoil_random)
	if holder.is_crouching:
		kick *= 0.8
	recoil_kick.emit(kick)

	_shot_index += 1
	_since_shot = 0.0
	bloom += data.bloom
	holder.on_weapon_fired(self)
	fired.emit()
	ammo_changed.emit()
	if ammo <= 0:
		start_reload()


## Returns `aim` rotated by a random angle inside a cone of `spread` radians.
func _spread_direction(aim: Vector3, spread: float) -> Vector3:
	if spread <= 0.0:
		return aim
	var right := aim.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(aim).normalized()
	var angle := randf() * TAU
	# sqrt() spreads the shots evenly over the circle instead of bunching
	# them in the centre.
	var radius := tan(spread) * sqrt(randf())
	return (aim + right * cos(angle) * radius + up * sin(angle) * radius).normalized()
