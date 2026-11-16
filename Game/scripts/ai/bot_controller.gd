class_name BotController
extends Combatant
## AI soldier. A small state machine on top of Combatant:
##
##   ADVANCE  walk a navigation path to an objective chosen by role
##   HOLD     stay put and watch (snipers at their nest, others briefly)
##   ENGAGE   an enemy is visible: strafe, keep the weapon's ideal range, shoot
##   HUNT     go to where an enemy was last seen or heard
##   COVER    low health or reloading under fire: run to a cover point
##
## Team behaviour comes from the match "blackboard": bots share enemy
## sightings, react to gunfire, and take different roles from their weapon
## (snipers hold lanes, SMG/shotgun bots flank, rifles push the middle).
##
## Bots "cheat" less than they could: they see only inside a view cone and
## view range, need a clear line of sight, take a reaction time before
## firing and aim with an error that shrinks the longer they track a target.

enum State { ADVANCE, HOLD, ENGAGE, HUNT, COVER }

## Per-difficulty skill. reaction = seconds before first shot,
## error = starting aim error in degrees, turn = degrees per second,
## settle = seconds for the aim error to shrink, view = sight range in m.
const SKILLS: Array[Dictionary] = [
	{"reaction": 0.65, "error": 5.5, "turn": 190.0, "settle": 1.4, "view": 70.0},
	{"reaction": 0.38, "error": 3.2, "turn": 280.0, "settle": 0.9, "view": 90.0},
	{"reaction": 0.22, "error": 1.7, "turn": 400.0, "settle": 0.55, "view": 110.0},
]
## [min, max] comfortable fighting distance per weapon category.
const PREFERRED_RANGE := {
	"shotgun": [3.0, 9.0], "smg": [5.0, 16.0], "pistol": [5.0, 15.0],
	"ar": [10.0, 35.0], "sniper": [25.0, 90.0],
}
const VIEW_CONE_DOT := 0.3        # cos of half the view cone (~145 degrees total)

var match_ref: TdmMatch
var role := "assault"
var state: State = State.ADVANCE
var target: Combatant

var _skill: Dictionary = SKILLS[1]
var _nav: NavigationAgent3D
var _yaw := 0.0
var _pitch := 0.0
var _goal := Vector3.ZERO
var _has_goal := false
var _think_left := 0.0
var _target_visible := false
var _reaction_left := 0.0
var _time_on_target := 0.0
var _aim_error := Vector2.ZERO
var _aim_head := false
var _last_seen := Vector3.ZERO
var _since_seen := 100.0
var _strafe_sign := 1.0
var _strafe_left := 0.0
var _burst_left := 0.5
var _pause_left := 0.0
var _tap_left := 0.0
var _stuck_time := 0.0
var _hold_left := 0.0
var _state_time := 0.0
var _trigger := false
var _want_jump := false
var _scan_phase := 0.0


func _ready() -> void:
	super()
	is_bot = true
	_nav = NavigationAgent3D.new()
	_nav.path_desired_distance = 0.8
	_nav.target_desired_distance = 1.5
	_nav.avoidance_enabled = false
	add_child(_nav)
	damaged.connect(_on_damaged)
	respawned.connect(_on_respawned)
	_scan_phase = randf() * TAU


func setup_bot(p_match: TdmMatch, difficulty: int) -> void:
	match_ref = p_match
	_skill = SKILLS[clampi(difficulty, 0, 2)]
	match weapons[0].data.category:
		"sniper":
			role = "sniper"
		"smg", "shotgun":
			role = "flank"
		_:
			role = "assault"


func get_shot_direction() -> Vector3:
	return Vector3(-sin(_yaw) * cos(_pitch), sin(_pitch), -cos(_yaw) * cos(_pitch))


## Told by the match when an enemy fires nearby.
func hear(position: Vector3) -> void:
	if target == null and alive:
		_last_seen = position
		_since_seen = 0.0


func on_weapon_fired(weapon: Weapon) -> void:
	super(weapon)
	# Each shot disturbs the aim a little, like recoil does for a human.
	_time_on_target = maxf(_time_on_target - 0.07, 0.0)


# ---------------------------------------------------------------- physics
func _physics_process(delta: float) -> void:
	update_common(delta)
	if not alive:
		return
	if match_ref == null or not match_ref.is_playing():
		_trigger = false
		move_character(delta, Vector3.ZERO, false)
		visual.animate(delta, 0.0, current_height, 0.0, true)
		return

	_since_seen += delta
	_state_time += delta
	_think_left -= delta
	if _think_left <= 0.0:
		# Thinking is staggered and only ~6 times a second: perception ray
		# casts are the expensive part of a bot.
		_think_left = randf_range(0.13, 0.2)
		_think()

	var wish := _steer(delta)
	_aim(delta)
	_fire_control(delta)
	move_character(delta, wish, _want_jump)
	_want_jump = false
	current_weapon().tick(delta, _trigger)
	rotation.y = _yaw
	visual.animate(delta, horizontal_speed(), current_height, _pitch, is_on_floor())


# --------------------------------------------------------------- thinking
func _think() -> void:
	var seen := _find_visible_enemy()
	if seen:
		if seen != target:
			# New target: start the reaction timer and a fresh aim error.
			_reaction_left = float(_skill["reaction"]) * randf_range(0.8, 1.3)
			_time_on_target = 0.0
			var error: float = _skill["error"]
			_aim_error = Vector2(randf_range(-error, error), randf_range(-error, error) * 0.6)
			_aim_head = randf() < (0.35 if role == "sniper" else 0.15)
		target = seen
		_target_visible = true
		_last_seen = seen.global_position
		_since_seen = 0.0
		match_ref.report_enemy(team, seen)
	else:
		target = null
		_target_visible = false

	_manage_weapons()
	var weapon := current_weapon()

	if target:
		var in_trouble := health < 35.0 or (weapon.is_reloading and weapon.ammo == 0)
		if in_trouble and state != State.COVER and _find_cover(target):
			_set_state(State.COVER)
		elif state != State.COVER:
			_set_state(State.ENGAGE)
		elif _state_time > 5.0 or (health > 60.0 and not weapon.is_reloading):
			_set_state(State.ENGAGE)
	elif state == State.COVER:
		if _state_time > 4.0 or (health > 60.0 and not weapon.is_reloading):
			_pick_objective()
	elif _since_seen < 5.0:
		_set_state(State.HUNT)
		_set_goal(_last_seen)
	else:
		var intel: Variant = match_ref.nearest_intel(team, global_position)
		if intel != null and role != "sniper" and state != State.HOLD:
			_set_state(State.HUNT)
			_set_goal(intel)
		elif state in [State.ENGAGE, State.HUNT] or not _has_goal:
			_pick_objective()


## The nearest enemy this bot can actually see, or null.
func _find_visible_enemy() -> Combatant:
	var best: Combatant = null
	var best_distance: float = _skill["view"]
	var eye := eye_position()
	var facing := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	for enemy: Combatant in match_ref.enemies_of(team):
		if not enemy.alive:
			continue
		var offset := enemy.chest_position() - eye
		var distance := offset.length()
		if distance >= best_distance:
			continue
		# Outside the view cone you are only noticed up close, unless the
		# bot is already fighting you.
		if distance > 7.0 and enemy != target and facing.dot(offset / distance) < VIEW_CONE_DOT:
			continue
		if not _has_line_of_sight(eye, enemy):
			continue
		best = enemy
		best_distance = distance
	return best


func _has_line_of_sight(eye: Vector3, enemy: Combatant) -> bool:
	var space := get_world_3d().direct_space_state
	for point: Vector3 in [enemy.head_position(), enemy.chest_position()]:
		var query := PhysicsRayQueryParameters3D.create(eye, point, Game.LAYER_WORLD)
		if space.intersect_ray(query).is_empty():
			return true
	return false


## Reload when safe; pull the sidearm when the primary runs dry up close.
func _manage_weapons() -> void:
	var weapon := current_weapon()
	if target:
		var distance := global_position.distance_to(target.global_position)
		if weapon_index == 0 and weapon.ammo == 0 and distance < 15.0 and weapons[1].ammo > 0:
			equip(1)
	else:
		if weapon_index == 1 and _since_seen > 1.5:
			equip(0)
		elif weapon.ammo < weapon.data.mag_size * 0.5 and _since_seen > 1.5:
			weapon.start_reload()


func _set_state(new_state: State) -> void:
	if new_state != state:
		state = new_state
		_state_time = 0.0


func _set_goal(point: Vector3) -> void:
	# Never push into the enemy's spawn zone: no spawn camping.
	point = match_ref.keep_out_of_enemy_spawn(team, point)
	if _has_goal and _goal.distance_squared_to(point) < 1.0:
		return
	_goal = point
	_has_goal = true
	_nav.target_position = point


## Chooses where to go when there is nothing to shoot at.
func _pick_objective() -> void:
	_set_state(State.ADVANCE)
	_stuck_time = 0.0
	if role == "sniper":
		_set_goal(match_ref.random_sniper_spot(team))
	else:
		_set_goal(match_ref.random_hotspot(team, role))


## Finds a nearby point where a wall or crate blocks the enemy's view.
func _find_cover(threat: Combatant) -> bool:
	var space := get_world_3d().direct_space_state
	var threat_eye := threat.eye_position()
	var best := Vector3.ZERO
	var best_distance := 16.0
	for point: Vector3 in match_ref.cover_points:
		var distance := global_position.distance_to(point)
		if distance >= best_distance:
			continue
		# Is a crouching soldier at this point hidden from the threat?
		var query := PhysicsRayQueryParameters3D.create(
				point + Vector3.UP * 0.9, threat_eye, Game.LAYER_WORLD)
		if space.intersect_ray(query).is_empty():
			continue
		best = point
		best_distance = distance
	if best_distance >= 16.0:
		return false
	_set_goal(best)
	return true


# --------------------------------------------------------------- movement
## Returns the horizontal direction to walk this frame and sets the
## stance flags (sprint / crouch / aim) for the current state.
func _steer(delta: float) -> Vector3:
	is_sprinting = false
	is_aiming = false
	var wish := Vector3.ZERO

	match state:
		State.ENGAGE:
			if target == null:
				return wish
			var to_target := target.global_position - global_position
			to_target.y = 0.0
			var distance := to_target.length()
			var forward := to_target / maxf(distance, 0.01)
			var range_pref: Array = PREFERRED_RANGE.get(current_weapon().data.category, [8.0, 30.0])
			_strafe_left -= delta
			if _strafe_left <= 0.0:
				_strafe_sign = 1.0 if randf() < 0.5 else -1.0
				_strafe_left = randf_range(0.5, 1.4)
			wish = forward.cross(Vector3.UP) * _strafe_sign * 0.8
			if distance > range_pref[1]:
				_set_goal(target.global_position)
				wish += _path_direction()
			elif distance < range_pref[0]:
				wish -= forward
			is_aiming = distance > 9.0
			var steady := role == "sniper" or (distance > 28.0 and current_weapon().data.category == "ar")
			is_crouching = steady
			if role == "sniper":
				wish *= 0.15       # snipers plant their feet to shoot
		State.HUNT, State.ADVANCE:
			_release_crouch()
			wish = _path_direction()
			var remaining := global_position.distance_to(_goal)
			is_sprinting = remaining > 10.0 and state == State.ADVANCE
			if _nav.is_navigation_finished() or remaining < 1.6:
				if state == State.ADVANCE:
					_set_state(State.HOLD)
					_hold_left = randf_range(9.0, 16.0) if role == "sniper" else randf_range(1.0, 3.0)
				else:
					_since_seen = 100.0       # nothing here; stop hunting
				wish = Vector3.ZERO
		State.COVER:
			wish = _path_direction()
			is_sprinting = true
			if _nav.is_navigation_finished() or global_position.distance_to(_goal) < 1.2:
				wish = Vector3.ZERO
				is_sprinting = false
				is_crouching = true
				current_weapon().start_reload()
		State.HOLD:
			is_crouching = role == "sniper"
			is_aiming = role == "sniper"
			_hold_left -= delta
			if _hold_left <= 0.0:
				_pick_objective()

	if wish.length_squared() > 0.001:
		wish = wish.normalized()
		# Not getting anywhere? Hop, and if that fails pick a new goal.
		if horizontal_speed() < 0.5:
			_stuck_time += delta
			if _stuck_time > 0.6:
				_want_jump = true
			if _stuck_time > 2.5:
				_pick_objective()
		else:
			_stuck_time = 0.0
	return wish


func _release_crouch() -> void:
	if is_crouching and can_stand():
		is_crouching = false


func _path_direction() -> Vector3:
	if not _has_goal or _nav.is_navigation_finished():
		return Vector3.ZERO
	var next := _nav.get_next_path_position()
	var direction := next - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return Vector3.ZERO
	return direction.normalized()


# ----------------------------------------------------------------- aiming
func _aim(delta: float) -> void:
	var desired_yaw := _yaw
	var desired_pitch := 0.0
	if target and _target_visible:
		_time_on_target += delta
		var eye := eye_position()
		var point := target.head_position() if _aim_head else target.chest_position()
		var distance := eye.distance_to(point)
		# Lead moving targets by the bullet's flight time.
		point += target.velocity * (distance / current_weapon().data.bullet_speed)
		var direction := (point - eye).normalized()
		desired_yaw = atan2(-direction.x, -direction.z)
		desired_pitch = asin(clampf(direction.y, -1.0, 1.0))
		# Aim error: large at first, shrinking as the bot tracks, never zero.
		var settle := 0.22 + 0.78 * exp(-_time_on_target / float(_skill["settle"]))
		desired_yaw += deg_to_rad(_aim_error.x) * settle
		desired_pitch += deg_to_rad(_aim_error.y) * settle
	elif state == State.HOLD:
		# Sweep left and right while watching.
		_scan_phase += delta * 0.7
		desired_yaw = match_ref.watch_yaw(team, global_position) + sin(_scan_phase) * 0.6
	elif _since_seen < 3.0 and state == State.HUNT and horizontal_speed() < 0.5:
		var offset := _last_seen - global_position
		desired_yaw = atan2(-offset.x, -offset.z)
	elif horizontal_speed() > 0.5:
		desired_yaw = atan2(-velocity.x, -velocity.z)

	var turn := deg_to_rad(float(_skill["turn"])) * delta
	_yaw = rotate_toward(_yaw, desired_yaw, turn)
	_pitch = move_toward(_pitch, desired_pitch, turn)


## Decides whether the trigger is held this frame.
func _fire_control(delta: float) -> void:
	_trigger = false
	if target == null or not _target_visible:
		return
	_reaction_left -= delta
	if _reaction_left > 0.0:
		return
	var weapon := current_weapon()
	if weapon.is_reloading:
		return
	# Only shoot when the sights are roughly on the target.
	var eye := eye_position()
	var to_target := target.chest_position() - eye
	var distance := to_target.length()
	var tolerance := deg_to_rad(3.0) + atan(0.45 / maxf(distance, 1.0))
	if get_shot_direction().angle_to(to_target) > tolerance:
		return

	if weapon.fire_mode() == WeaponData.FireMode.AUTO:
		# Short controlled bursts; shorter at long range.
		if _pause_left > 0.0:
			_pause_left -= delta
			return
		_trigger = true
		_burst_left -= delta
		if _burst_left <= 0.0:
			_pause_left = randf_range(0.15, 0.45)
			_burst_left = randf_range(0.25, 0.5) if distance > 30.0 else randf_range(0.4, 1.0)
	else:
		# Semi / bolt / burst weapons need a fresh trigger pull per shot.
		_tap_left -= delta
		if _tap_left <= 0.0:
			_trigger = true
			_tap_left = weapon.data.shot_interval() + randf_range(0.06, 0.25)


func _on_damaged(_amount: float, attacker: Combatant, _headshot: bool) -> void:
	# Being shot reveals roughly where the shooter is.
	if target == null and attacker and attacker.alive:
		_last_seen = attacker.global_position
		_since_seen = 0.0


func _on_respawned() -> void:
	target = null
	_target_visible = false
	_has_goal = false
	_since_seen = 100.0
	_yaw = rotation.y
	_pitch = 0.0
	_set_state(State.ADVANCE)
	_think_left = randf_range(0.0, 0.2)
