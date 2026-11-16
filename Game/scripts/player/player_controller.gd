class_name PlayerController
extends Combatant
## The human player: turns keyboard/mouse input into movement, aiming and
## shooting, and owns the camera (first person or over-the-shoulder third
## person), the first-person weapon model and view recoil.
##
## Built entirely in code, so scenes/player.tscn is just this script on a
## CharacterBody3D.

const BASE_SENSITIVITY := 0.0022
const PITCH_LIMIT := 1.48                  # ~85 degrees
const HIP_POSITION := Vector3(0.2, -0.19, -0.42)
const THIRD_PERSON_DISTANCE := 2.8
const THIRD_PERSON_ADS_DISTANCE := 1.3
const SHOULDER_OFFSET := Vector3(0.55, 0.1, 0.0)

var is_third_person := false
## False while paused, in menus or after the match ends.
var controls_enabled := true
## Normally input only counts while the mouse is captured by the game
## window. Automated tests turn this off because they have no real mouse.
var require_mouse_capture := true

var _pitch := 0.0
var _head: Node3D
var _spring_arm: SpringArm3D
var _camera: Camera3D
var _viewmodel: WeaponVisual
var _recoil_pending := Vector2.ZERO        # kick not yet applied to the view
var _recoil_climb := 0.0                   # how far recoil has pushed the view up
var _kick_back := 0.0                      # viewmodel pushed back by firing
var _sway := Vector2.ZERO
var _bob_phase := 0.0
var _sprint_fov := 0.0
var _shadow_only := false
var _dead_view := false


func _ready() -> void:
	super()
	_head = Node3D.new()
	_head.position.y = STAND_HEIGHT - EYE_OFFSET
	add_child(_head)
	_spring_arm = SpringArm3D.new()
	_spring_arm.spring_length = 0.0
	_spring_arm.margin = 0.15
	_spring_arm.collision_mask = Game.LAYER_WORLD
	_head.add_child(_spring_arm)
	_camera = Camera3D.new()
	_camera.near = 0.04
	_camera.far = 400.0
	_camera.fov = float(Game.settings["fov"])
	_spring_arm.add_child(_camera)
	_camera.current = true
	_viewmodel = WeaponVisual.new()
	_camera.add_child(_viewmodel)
	is_third_person = bool(Game.settings["third_person"])
	died.connect(_on_died)
	respawned.connect(_on_respawned)
	weapon_changed.connect(_on_weapon_changed)
	if not weapons.is_empty():
		_on_weapon_changed(current_weapon())


func set_weapons(primary: WeaponData, secondary: WeaponData) -> void:
	super(primary, secondary)
	for weapon in weapons:
		weapon.recoil_kick.connect(_on_recoil_kick)


func camera() -> Camera3D:
	return _camera


## True when the full-screen sniper scope should be drawn.
func is_scoped() -> bool:
	return alive and current_weapon().data.uses_scope_overlay() and ads_amount > 0.85


# ------------------------------------------------------------------ input
func _unhandled_input(event: InputEvent) -> void:
	if not _can_control():
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		# Lower sensitivity when zoomed in, in proportion to the zoom.
		var sensitivity := BASE_SENSITIVITY * float(Game.settings["sensitivity"]) \
				* (_camera.fov / float(Game.settings["fov"]))
		rotate_y(-motion.relative.x * sensitivity)
		_pitch = clampf(_pitch - motion.relative.y * sensitivity, -PITCH_LIMIT, PITCH_LIMIT)
		_head.rotation.x = _pitch
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			equip(1 - weapon_index)
	elif event.is_action_pressed("weapon_primary"):
		equip(0)
	elif event.is_action_pressed("weapon_secondary"):
		equip(1)
	elif event.is_action_pressed("weapon_swap"):
		equip(1 - weapon_index)
	elif event.is_action_pressed("fire_mode"):
		current_weapon().cycle_fire_mode()
	elif event.is_action_pressed("toggle_view"):
		is_third_person = not is_third_person
		Game.settings["third_person"] = is_third_person


func _can_control() -> bool:
	return alive and controls_enabled and (not require_mouse_capture
			or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)


# ---------------------------------------------------------------- physics
func _physics_process(delta: float) -> void:
	update_common(delta)
	_head.position.y = current_height - EYE_OFFSET
	if not alive:
		move_character(delta, Vector3.ZERO, false)
		_update_camera(delta)
		return

	var active := _can_control()
	var input_vector := Vector2.ZERO
	if active:
		input_vector = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (global_transform.basis
			* Vector3(input_vector.x, 0.0, input_vector.y)).normalized()

	# --- Stance and state flags ---
	var trigger := active and Input.is_action_pressed("fire")
	is_aiming = active and Input.is_action_pressed("aim")
	if active and Input.is_action_pressed("crouch"):
		is_crouching = true
	elif is_crouching and can_stand():
		is_crouching = false
	is_sprinting = (active and Input.is_action_pressed("sprint") and input_vector.y < -0.1
			and is_on_floor() and not is_crouching and not is_aiming and not trigger)

	move_character(delta, direction, active and Input.is_action_just_pressed("jump"))

	# --- Weapon ---
	var weapon := current_weapon()
	if active and Input.is_action_just_pressed("reload"):
		weapon.start_reload()
	weapon.tick(delta, trigger)

	_apply_recoil(delta)
	_update_camera(delta)
	_update_viewmodel(delta, input_vector)
	visual.animate(delta, horizontal_speed(), current_height, _pitch, is_on_floor())


# ----------------------------------------------------------------- aiming
func get_shot_direction() -> Vector3:
	var forward := -_camera.global_transform.basis.z
	if _spring_arm.spring_length < 0.2:
		return forward
	# Third person: find what the crosshair is over, then shoot from the
	# eyes towards that point, so bullets go where the crosshair is.
	var start := _camera.global_position + forward * (_spring_arm.spring_length + 0.6)
	var end := start + forward * 300.0
	var query := PhysicsRayQueryParameters3D.create(
			start, end, Game.LAYER_WORLD | Game.LAYER_CHARACTER, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var aim_point: Vector3 = hit["position"] if not hit.is_empty() else end
	return (aim_point - eye_position()).normalized()


func get_muzzle_position() -> Vector3:
	if _viewmodel.visible:
		return _viewmodel.to_global(_viewmodel.muzzle_local)
	return visual.muzzle_position()


func _on_recoil_kick(kick: Vector2) -> void:
	_recoil_pending += kick


## Feeds recoil into the view over a few frames, then lets part of the
## climb settle back once the player stops firing.
func _apply_recoil(delta: float) -> void:
	var weapon := current_weapon()
	if _recoil_pending.length_squared() > 0.000001:
		var step := _recoil_pending * minf(1.0, 30.0 * delta)
		_recoil_pending -= step
		_pitch += deg_to_rad(step.x)
		rotate_y(-deg_to_rad(step.y))
		_recoil_climb += step.x
		_kick_back = minf(_kick_back + step.x * 0.012, 0.07)
	elif _recoil_climb > 0.001 and weapon.time_since_shot() > 0.12:
		var back := _recoil_climb * minf(1.0, 8.0 * delta)
		_recoil_climb -= back
		_pitch -= deg_to_rad(back * weapon.data.recoil_recovery)
	_pitch = clampf(_pitch, -PITCH_LIMIT, PITCH_LIMIT)
	_head.rotation.x = _pitch


# ----------------------------------------------------------------- camera
func _update_camera(delta: float) -> void:
	var blend := 1.0 - exp(-12.0 * delta)
	var weapon := current_weapon()

	# Field of view: hip -> weapon zoom as ads_amount goes 0 -> 1.
	var base_fov := float(Game.settings["fov"])
	_sprint_fov = lerpf(_sprint_fov, 6.0 if is_sprinting else 0.0, blend)
	_camera.fov = lerpf(base_fov, weapon.data.ads_fov, smoothstep(0.0, 1.0, ads_amount)) + _sprint_fov

	# Third person pulls the camera back over the right shoulder. Scoped
	# weapons snap to first person while aiming so the scope makes sense.
	var want_third := is_third_person and not (weapon.data.uses_scope_overlay() and ads_amount > 0.05)
	var target_length := 0.0
	var target_offset := Vector3.ZERO
	if _dead_view:
		target_length = 4.0
	elif want_third:
		target_length = lerpf(THIRD_PERSON_DISTANCE, THIRD_PERSON_ADS_DISTANCE, ads_amount)
		target_offset = SHOULDER_OFFSET
	_spring_arm.spring_length = lerpf(_spring_arm.spring_length, target_length, blend)
	_spring_arm.position = _spring_arm.position.lerp(target_offset, blend)
	if _dead_view:
		_pitch = lerpf(_pitch, -0.7, blend * 0.5)
		_head.rotation.x = _pitch

	var first_person := _spring_arm.spring_length < 0.4
	if first_person != _shadow_only:
		_shadow_only = first_person
		visual.set_shadow_only(first_person)
	_viewmodel.visible = first_person and alive and not is_scoped()


## Positions the first-person weapon: hip <-> sights, sway, bob, recoil
## push-back and the reload dip.
func _update_viewmodel(delta: float, input_vector: Vector2) -> void:
	var weapon := current_weapon()
	var blend := 1.0 - exp(-10.0 * delta)
	var ads := smoothstep(0.0, 1.0, ads_amount)
	var sights := Vector3(0.0, -_viewmodel.sight_height, -0.3)
	var target := HIP_POSITION.lerp(sights, ads)

	# Walking bob (smaller when aiming).
	var speed := horizontal_speed()
	if is_on_floor() and speed > 0.5:
		_bob_phase += delta * speed * 1.8
	var bob_amount := clampf(speed / 6.0, 0.0, 1.0) * (1.0 - 0.85 * ads)
	target.x += cos(_bob_phase) * 0.008 * bob_amount
	target.y += absf(sin(_bob_phase)) * 0.01 * bob_amount

	# Lag slightly behind strafing so the gun feels like it has weight.
	_sway = _sway.lerp(Vector2(-input_vector.x, 0.0) * 0.015 * (1.0 - ads), blend)
	target.x += _sway.x

	_kick_back = lerpf(_kick_back, 0.0, 1.0 - exp(-14.0 * delta))
	target.z += _kick_back

	# Reload: tip the gun down and back up.
	var reload := sin(weapon.reload_progress() * PI)
	target.y -= reload * 0.09
	_viewmodel.rotation.x = -reload * 0.7 + _kick_back * 1.5
	_viewmodel.rotation.z = reload * 0.3
	if is_sprinting:
		target += Vector3(-0.05, -0.04, 0.05)
		_viewmodel.rotation.y = lerpf(_viewmodel.rotation.y, 0.5, blend)
	else:
		_viewmodel.rotation.y = lerpf(_viewmodel.rotation.y, 0.0, blend)
	_viewmodel.position = _viewmodel.position.lerp(target, 1.0 - exp(-18.0 * delta))


func _on_weapon_changed(weapon: Weapon) -> void:
	if _viewmodel == null:
		return
	_viewmodel.build(weapon.data, false)
	_viewmodel.position = HIP_POSITION + Vector3(0.0, -0.15, 0.0)   # rises into view
	_recoil_pending = Vector2.ZERO
	_recoil_climb = 0.0


func _on_died(_victim: Combatant, _killer: Combatant, _weapon: WeaponData, _headshot: bool) -> void:
	_dead_view = true
	_recoil_pending = Vector2.ZERO
	_recoil_climb = 0.0


func _on_respawned() -> void:
	_dead_view = false
	_pitch = 0.0
	_head.rotation.x = 0.0
	_spring_arm.spring_length = 0.0
