class_name Combatant
extends CharacterBody3D
## Base class for anything that fights: the player and the bots.
## Owns health, team, weapons, stance (stand/crouch), shared movement
## physics, death and respawn. PlayerController and BotController only add
## "how do I decide what to do" on top of this.
##
## The origin is at the FEET (y = 0 is the ground).

signal died(victim: Combatant, killer: Combatant, weapon: WeaponData, headshot: bool)
signal damaged(amount: float, attacker: Combatant, headshot: bool)
signal dealt_damage(victim: Combatant, amount: float, headshot: bool, killed: bool)
signal weapon_changed(weapon: Weapon)
signal respawned

const RADIUS := 0.35
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const EYE_OFFSET := 0.15
## Hits in the top part of the capsule count as headshots.
const HEAD_ZONE := 0.32
const REGEN_DELAY := 5.0
const REGEN_RATE := 12.0
const SPAWN_PROTECTION := 2.0

# ---------------------------------------------------------------- Movement
@export_group("Movement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 7.5
@export var crouch_speed: float = 2.5
@export var ads_speed: float = 3.0
@export var jump_height: float = 1.1
@export var ground_acceleration: float = 45.0
@export var air_acceleration: float = 8.0
@export var stance_speed: float = 6.0

# ------------------------------------------------------------------ State
var team := 0
var display_name := "Soldier"
var is_bot := false
var max_health := 100.0
var health := 100.0
var alive := false
var kills := 0
var deaths := 0
var headshots := 0
var spawn_protection := 0.0

var is_crouching := false
var is_sprinting := false
var is_aiming := false
## 0 = hip, 1 = fully aimed down sights. Blends over the weapon's ads_time.
var ads_amount := 0.0
var current_height := STAND_HEIGHT

var weapons: Array[Weapon] = []
var weapon_index := 0
var visual: CharacterVisual

var _gravity := 9.8
var _capsule: CapsuleShape3D
var _collision: CollisionShape3D
var _since_damage := 100.0
var _step_distance := 0.0


func _init() -> void:
	collision_layer = Game.LAYER_CHARACTER
	collision_mask = Game.LAYER_WORLD      # walk through other characters
	_capsule = CapsuleShape3D.new()
	_capsule.radius = RADIUS
	_capsule.height = STAND_HEIGHT
	_collision = CollisionShape3D.new()
	_collision.shape = _capsule
	_collision.position.y = STAND_HEIGHT * 0.5
	add_child(_collision)
	visual = CharacterVisual.new()
	add_child(visual)
	floor_snap_length = 0.3
	add_to_group("combatants")


func _ready() -> void:
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")


## Gives this fighter an identity and weapons. Call once after creating it.
func setup(p_team: int, p_name: String, primary: WeaponData, secondary: WeaponData) -> void:
	team = p_team
	display_name = p_name
	visual.set_team_color(Game.TEAM_COLORS[team])
	set_weapons(primary, secondary)


## Replaces both weapons (used for loadout changes on respawn).
func set_weapons(primary: WeaponData, secondary: WeaponData) -> void:
	for old in weapons:
		old.queue_free()
	weapons.clear()
	for data: WeaponData in [primary, secondary]:
		var weapon := Weapon.new()
		weapon.setup(data, self)
		add_child(weapon)
		weapons.append(weapon)
	weapon_index = 0
	visual.set_weapon(primary)
	weapon_changed.emit(weapons[0])


func current_weapon() -> Weapon:
	return weapons[weapon_index]


func equip(index: int) -> void:
	if index == weapon_index or index < 0 or index >= weapons.size():
		return
	current_weapon().holster()
	weapon_index = index
	ads_amount = 0.0
	visual.set_weapon(current_weapon().data)
	Sfx.play("switch", global_position, -6.0)
	weapon_changed.emit(current_weapon())


# ------------------------------------------------------------- Aim points
func eye_position() -> Vector3:
	return global_position + Vector3.UP * (current_height - EYE_OFFSET)


func chest_position() -> Vector3:
	return global_position + Vector3.UP * (current_height * 0.62)


func head_position() -> Vector3:
	return global_position + Vector3.UP * (current_height - 0.14)


func is_head_hit(world_position: Vector3) -> bool:
	return world_position.y - global_position.y > current_height - HEAD_ZONE


## Where bullets start. Overridden by the player for third person.
func get_shot_origin() -> Vector3:
	return eye_position()


## The direction this fighter is aiming. Subclasses must override.
func get_shot_direction() -> Vector3:
	return -global_transform.basis.z


## Where the muzzle flash and tracer appear.
func get_muzzle_position() -> Vector3:
	return visual.muzzle_position()


## Hook: called by the weapon after every shot (bots get told about noise).
func on_weapon_fired(weapon: Weapon) -> void:
	if Game.match_node:
		Game.match_node.report_shot(self, weapon.data.suppressed)


# ------------------------------------------------------------ Damage/death
func apply_damage(amount: float, attacker: Combatant, weapon: WeaponData, headshot: bool) -> void:
	if not alive or spawn_protection > 0.0:
		return
	if Game.match_node and not Game.match_node.is_playing():
		return
	health -= amount
	_since_damage = 0.0
	damaged.emit(amount, attacker, headshot)
	var killed := health <= 0.0
	if attacker and attacker != self:
		attacker.dealt_damage.emit(self, amount, headshot, killed)
	if killed:
		_die(attacker, weapon, headshot)


func _die(killer: Combatant, weapon: WeaponData, headshot: bool) -> void:
	alive = false
	health = 0.0
	deaths += 1
	if killer and killer != self:
		killer.kills += 1
		if headshot:
			killer.headshots += 1
	collision_layer = 0            # bullets and sight lines ignore corpses
	velocity = Vector3.ZERO
	is_aiming = false
	is_sprinting = false
	current_weapon().holster()
	visual.play_death()
	Sfx.play("death", global_position, -4.0)
	died.emit(self, killer, weapon, headshot)


## Brings the fighter back to life at the given transform.
func respawn(spawn: Transform3D) -> void:
	global_position = spawn.origin
	rotation = Vector3(0.0, spawn.basis.get_euler().y, 0.0)
	velocity = Vector3.ZERO
	health = max_health
	alive = true
	spawn_protection = SPAWN_PROTECTION
	_since_damage = 100.0
	is_crouching = false
	current_height = STAND_HEIGHT
	_apply_height()
	collision_layer = Game.LAYER_CHARACTER
	for weapon in weapons:
		weapon.refill()
	if weapon_index != 0:
		weapon_index = 0
		visual.set_weapon(weapons[0].data)
		weapon_changed.emit(weapons[0])
	visual.reset_pose()
	respawned.emit()


# ---------------------------------------------------------------- Movement
## Shared per-frame upkeep: timers, health regen, ADS blend, stance.
func update_common(delta: float) -> void:
	spawn_protection = maxf(spawn_protection - delta, 0.0)
	_since_damage += delta
	if alive and health < max_health and _since_damage > REGEN_DELAY:
		health = minf(health + REGEN_RATE * delta, max_health)

	var weapon := current_weapon()
	var want_ads := is_aiming and alive and not weapon.is_reloading and not is_sprinting
	ads_amount = move_toward(ads_amount, 1.0 if want_ads else 0.0,
			delta / maxf(weapon.data.ads_time, 0.05))

	var target_height := CROUCH_HEIGHT if is_crouching else STAND_HEIGHT
	if not is_equal_approx(current_height, target_height):
		current_height = move_toward(current_height, target_height, stance_speed * delta)
		_apply_height()


## Moves the body. `wish_direction` is a horizontal world direction (or zero).
func move_character(delta: float, wish_direction: Vector3, want_jump: bool) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif want_jump and can_stand():
		velocity.y = sqrt(2.0 * _gravity * jump_height)
		is_crouching = false

	var target := wish_direction * target_speed()
	var acceleration := ground_acceleration if is_on_floor() else air_acceleration
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(
			Vector2(target.x, target.z), acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	move_and_slide()

	# Footsteps: one every ~2.2 m of ground covered.
	if is_on_floor():
		_step_distance += horizontal.length() * delta
		if _step_distance > 2.2:
			_step_distance = 0.0
			Sfx.play("step", global_position, -16.0 if is_crouching else -9.0,
					randf_range(0.85, 1.15))


## Top speed allowed in the current state, including the weapon's weight.
func target_speed() -> float:
	var speed := walk_speed
	if is_crouching:
		speed = crouch_speed
	elif ads_amount > 0.5:
		speed = ads_speed
	elif is_sprinting:
		speed = sprint_speed
	return speed * current_weapon().data.move_mult


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## True when a standing-size capsule fits here (no low roof overhead).
func can_stand() -> bool:
	if not is_crouching:
		return true
	var test_shape := CapsuleShape3D.new()
	test_shape.radius = RADIUS * 0.95
	test_shape.height = STAND_HEIGHT - 0.1
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = test_shape
	query.transform = Transform3D(Basis.IDENTITY,
			global_position + Vector3.UP * (STAND_HEIGHT * 0.5 + 0.05))
	query.collision_mask = Game.LAYER_WORLD
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _apply_height() -> void:
	_capsule.height = current_height
	_collision.position.y = current_height * 0.5
