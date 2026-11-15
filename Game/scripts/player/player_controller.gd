class_name PlayerController
extends CharacterBody3D
## First/third-person character controller.
##
## Handles: walk, sprint, crouch, jump, mouse look, aim down sights (ADS)
## and switching between first-person and third-person cameras.
##
## Node layout expected (see scenes/player.tscn). The player origin is at
## the FEET, so y = 0 is the ground:
##   Player (CharacterBody3D)        <- this script
##   |- CollisionShape3D             capsule, resized when crouching
##   |- BodyMesh (MeshInstance3D)    placeholder body, hidden in first person
##   `- Head (Node3D)                pitches up/down
##      `- SpringArm3D               0 m long in FP, pulls back in TP
##         `- Camera3D

# ---------------------------------------------------------------- Movement
@export_group("Movement")
## Normal jogging speed in m/s.
@export var walk_speed: float = 5.0
## Speed while holding sprint and moving forward.
@export var sprint_speed: float = 7.5
## Speed while crouched.
@export var crouch_speed: float = 2.5
## Speed while aiming down sights (standing).
@export var ads_speed: float = 3.0
## Jump apex height in metres.
@export var jump_height: float = 1.1
## How fast we reach target speed on the ground (m/s^2).
@export var ground_acceleration: float = 45.0
## How much control we have in the air (m/s^2).
@export var air_acceleration: float = 8.0

# -------------------------------------------------------------------- Look
@export_group("Look")
## Radians of rotation per pixel of mouse movement.
@export var mouse_sensitivity: float = 0.0025
## Sensitivity multiplier while aiming (lower = steadier aim).
@export_range(0.1, 1.0) var ads_sensitivity_scale: float = 0.6
## How far up/down the camera can pitch, in degrees.
@export_range(10.0, 89.0) var pitch_limit_degrees: float = 85.0

# ------------------------------------------------------------------ Stance
@export_group("Stance")
## Capsule height when standing (metres).
@export var stand_height: float = 1.8
## Capsule height when crouched (metres).
@export var crouch_height: float = 1.1
## How far below the top of the capsule the eyes sit.
@export var eye_offset: float = 0.15
## How quickly the capsule and camera move between stances.
@export var stance_speed: float = 10.0

# ------------------------------------------------------------------ Camera
@export_group("Camera")
## Field of view when not aiming.
@export var hip_fov: float = 75.0
## Field of view while aiming down sights.
@export var ads_fov: float = 50.0
## Slightly wider FOV while sprinting, for a sense of speed.
@export var sprint_fov: float = 82.0
## How quickly FOV and camera distance blend.
@export var camera_blend_speed: float = 12.0
## Camera distance behind the player in third person.
@export var third_person_distance: float = 2.8
## Camera distance in third person while aiming (over-the-shoulder).
@export var third_person_ads_distance: float = 1.4
## Sideways/up offset of the third-person camera (right shoulder).
@export var shoulder_offset: Vector3 = Vector3(0.55, 0.1, 0.0)
## Start the game in third person instead of first person.
@export var start_in_third_person: bool = false

# --------------------------------------------------------- Runtime state
## True while the player is crouched (read by weapons/animation later).
var is_crouching: bool = false
## True while the player is sprinting.
var is_sprinting: bool = false
## True while the player is aiming down sights.
var is_aiming: bool = false
## True when the third-person camera is active.
var is_third_person: bool = false

var _pitch: float = 0.0                 # current camera pitch in radians
var _current_height: float = 1.8        # capsule height right now
var _gravity: float = 9.8               # read from Project Settings
var _capsule: CapsuleShape3D            # our own copy of the collision shape
var _body_capsule_mesh: CapsuleMesh     # our own copy of the body mesh

@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _body_mesh: MeshInstance3D = $BodyMesh
@onready var _head: Node3D = $Head
@onready var _spring_arm: SpringArm3D = $Head/SpringArm3D
@onready var _camera: Camera3D = $Head/SpringArm3D/Camera3D


func _ready() -> void:
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

	# Resources are shared between instances of a scene. Duplicate them so
	# crouching one character does not shrink every other character.
	_capsule = _collision.shape.duplicate() as CapsuleShape3D
	_collision.shape = _capsule
	_body_capsule_mesh = _body_mesh.mesh.duplicate() as CapsuleMesh
	_body_mesh.mesh = _body_capsule_mesh

	_current_height = stand_height
	_apply_height(_current_height)

	# The camera arm must not collide with our own body.
	_spring_arm.add_excluded_object(get_rid())
	_spring_arm.spring_length = 0.0

	is_third_person = start_in_third_person
	_camera.fov = hip_fov
	_camera.current = true

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	# --- Mouse look (only while the cursor is captured) ---
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var sensitivity := mouse_sensitivity
		if is_aiming:
			sensitivity *= ads_sensitivity_scale
		# Yaw turns the whole body; pitch only tilts the head.
		rotate_y(-motion.relative.x * sensitivity)
		var limit := deg_to_rad(pitch_limit_degrees)
		_pitch = clampf(_pitch - motion.relative.y * sensitivity, -limit, limit)
		_head.rotation.x = _pitch

	# --- Esc frees the cursor, clicking the window grabs it again ---
	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# --- V switches first person <-> third person ---
	if event.is_action_pressed("toggle_view"):
		is_third_person = not is_third_person


func _physics_process(delta: float) -> void:
	# x = strafe (left -, right +), y = forward/back (forward is -1).
	var input_vector := Input.get_vector(
			"move_left", "move_right", "move_forward", "move_back")
	# Turn the 2D input into a world direction relative to where we face.
	var direction := (global_transform.basis
			* Vector3(input_vector.x, 0.0, input_vector.y)).normalized()

	_update_states(input_vector)

	# --- Vertical movement ---
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump") and _can_stand():
		# v = sqrt(2 * g * h) gives exactly jump_height at the apex.
		velocity.y = sqrt(2.0 * _gravity * jump_height)
		is_crouching = false

	# --- Horizontal movement ---
	var target_velocity := direction * _target_speed()
	var acceleration := ground_acceleration if is_on_floor() else air_acceleration
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(
			Vector2(target_velocity.x, target_velocity.z), acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y

	move_and_slide()

	_update_stance(delta)
	_update_camera(delta)


## Works out crouch / sprint / aim from the held buttons.
func _update_states(input_vector: Vector2) -> void:
	is_aiming = Input.is_action_pressed("aim")

	if Input.is_action_pressed("crouch"):
		is_crouching = true
	elif is_crouching and _can_stand():
		# Only stand up when there is head room (e.g. not under a low roof).
		is_crouching = false

	var moving_forward := input_vector.y < -0.1
	is_sprinting = (Input.is_action_pressed("sprint") and moving_forward
			and is_on_floor() and not is_crouching and not is_aiming)


## The top speed allowed in the current state.
func _target_speed() -> float:
	if is_crouching:
		return crouch_speed
	if is_aiming:
		return ads_speed
	if is_sprinting:
		return sprint_speed
	return walk_speed


## Smoothly resizes the capsule and moves the head when the stance changes.
func _update_stance(delta: float) -> void:
	var target_height := crouch_height if is_crouching else stand_height
	if is_equal_approx(_current_height, target_height):
		return
	_current_height = move_toward(
			_current_height, target_height, stance_speed * delta)
	_apply_height(_current_height)


## Applies a capsule height to the collider, the body mesh and the head.
func _apply_height(height: float) -> void:
	_capsule.height = height
	_collision.position.y = height * 0.5      # keep the feet on the ground
	_body_capsule_mesh.height = height
	_body_mesh.position.y = height * 0.5
	_head.position.y = height - eye_offset


## Returns true when a standing-size capsule fits at our position.
func _can_stand() -> bool:
	if not is_crouching:
		return true
	var test_shape := CapsuleShape3D.new()
	test_shape.radius = _capsule.radius * 0.95
	# Slightly shorter and lifted off the floor so the floor itself is
	# never counted as an obstacle.
	test_shape.height = stand_height - 0.1
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = test_shape
	query.transform = Transform3D(
			Basis.IDENTITY,
			global_position + Vector3.UP * (stand_height * 0.5 + 0.05))
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	var hits := get_world_3d().direct_space_state.intersect_shape(query, 1)
	return hits.is_empty()


## Blends FOV (ADS / sprint) and the first/third-person camera position.
func _update_camera(delta: float) -> void:
	# Frame-rate independent smoothing factor (0..1).
	var blend := 1.0 - exp(-camera_blend_speed * delta)

	# --- Field of view ---
	var target_fov := hip_fov
	if is_aiming:
		target_fov = ads_fov
	elif is_sprinting:
		target_fov = sprint_fov
	_camera.fov = lerpf(_camera.fov, target_fov, blend)

	# --- First person: arm length 0. Third person: pull back over shoulder ---
	var target_length := 0.0
	var target_offset := Vector3.ZERO
	if is_third_person:
		target_length = third_person_ads_distance if is_aiming else third_person_distance
		target_offset = shoulder_offset
	_spring_arm.spring_length = lerpf(_spring_arm.spring_length, target_length, blend)
	_spring_arm.position = _spring_arm.position.lerp(target_offset, blend)

	# In first person we must not see our own body from the inside, but it
	# should still cast a shadow on the ground.
	if _spring_arm.spring_length > 0.4:
		_body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	else:
		_body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
