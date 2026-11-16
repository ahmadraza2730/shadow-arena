class_name CharacterVisual
extends Node3D
## A soldier built from boxes, animated in code: legs swing with movement
## speed, the upper body pitches with the aim, the whole body lowers when
## crouching and falls over on death. It stands in for a rigged character
## until a real model (e.g. from Mixamo) is imported.

const SKIN := Color(0.78, 0.6, 0.46)

var weapon_visual: WeaponVisual
var _upper: Node3D            # torso + head + arms, pitches with aim
var _hips: Node3D
var _leg_left: Node3D
var _leg_right: Node3D
var _meshes: Array[MeshInstance3D] = []
var _walk_phase := 0.0
var _team_material: StandardMaterial3D
var _death_tween: Tween


func _init() -> void:
	# Materials: camouflage cloth, dark gear, skin, and one bright team
	# colour used on the helmet and armbands so friend and foe read at a glance.
	_team_material = StandardMaterial3D.new()
	_team_material.roughness = 0.7
	var camo := StandardMaterial3D.new()
	camo.albedo_texture = load("res://assets/textures/camo_albedo.jpg")
	camo.normal_enabled = true
	camo.normal_texture = load("res://assets/textures/camo_normal.jpg")
	camo.roughness = 0.95
	camo.uv1_scale = Vector3(1.6, 1.6, 1.6)
	camo.uv1_triplanar = true
	var gear := StandardMaterial3D.new()
	gear.albedo_color = Color(0.16, 0.17, 0.13)
	gear.roughness = 0.9
	var boot := StandardMaterial3D.new()
	boot.albedo_color = Color(0.07, 0.06, 0.05)
	boot.roughness = 0.6
	var skin := StandardMaterial3D.new()
	skin.albedo_color = SKIN
	skin.roughness = 0.8

	# --- Legs (each pivots at the hip) ---
	_hips = Node3D.new()
	_hips.position.y = 0.92
	add_child(_hips)
	_leg_left = _leg(-0.11, camo, gear, boot)
	_leg_right = _leg(0.11, camo, gear, boot)
	_part(_hips, Vector3(0.4, 0.14, 0.24), Vector3(0, 0.02, 0), gear)                 # belt

	# --- Upper body (pitches with the aim) ---
	_upper = Node3D.new()
	_upper.position.y = 0.92
	add_child(_upper)
	_part(_upper, Vector3(0.4, 0.56, 0.22), Vector3(0, 0.3, 0), camo)                  # torso
	_part(_upper, Vector3(0.44, 0.34, 0.27), Vector3(0, 0.36, 0), gear)                # plate carrier
	for x: float in [-0.13, 0.0, 0.13]:
		_part(_upper, Vector3(0.1, 0.13, 0.07), Vector3(x, 0.24, -0.16), gear)         # magazine pouches
	_part(_upper, Vector3(0.3, 0.38, 0.14), Vector3(0, 0.36, 0.19), gear)              # backpack
	_part(_upper, Vector3(0.11, 0.08, 0.11), Vector3(0, 0.6, 0), skin)                 # neck
	_part(_upper, Vector3(0.19, 0.21, 0.2), Vector3(0, 0.72, 0), skin)                 # head
	_part(_upper, Vector3(0.2, 0.05, 0.03), Vector3(0, 0.75, -0.1), boot)              # goggles
	_part(_upper, Vector3(0.25, 0.12, 0.27), Vector3(0, 0.85, 0.0), _team_material)    # helmet
	_part(_upper, Vector3(0.27, 0.03, 0.29), Vector3(0, 0.79, 0.0), gear)              # helmet rim
	# Right arm: shoulder -> elbow -> hand on the grip.
	_part(_upper, Vector3(0.11, 0.3, 0.12), Vector3(0.27, 0.42, -0.02), camo)
	_part(_upper, Vector3(0.12, 0.07, 0.13), Vector3(0.27, 0.5, -0.02), _team_material)   # armband
	_part(_upper, Vector3(0.09, 0.09, 0.3), Vector3(0.24, 0.32, -0.2), camo)
	_part(_upper, Vector3(0.09, 0.09, 0.09), Vector3(0.2, 0.33, -0.36), boot)          # glove
	# Left arm reaches across to the handguard.
	_part(_upper, Vector3(0.11, 0.3, 0.12), Vector3(-0.27, 0.42, -0.02), camo)
	_part(_upper, Vector3(0.12, 0.07, 0.13), Vector3(-0.27, 0.5, -0.02), _team_material)
	_part(_upper, Vector3(0.09, 0.09, 0.46), Vector3(-0.12, 0.34, -0.3), camo, 0.55)
	_part(_upper, Vector3(0.09, 0.09, 0.09), Vector3(0.06, 0.36, -0.56), boot)

	weapon_visual = WeaponVisual.new()
	weapon_visual.position = Vector3(0.18, 0.4, -0.38)
	_upper.add_child(weapon_visual)


## A leg: a hip pivot with thigh/shin, knee pad and boot hanging below it.
func _leg(x: float, cloth: Material, pad: Material, boot: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(x, 0, 0)
	_hips.add_child(pivot)
	_part(pivot, Vector3(0.15, 0.8, 0.17), Vector3(0, -0.4, 0), cloth)
	_part(pivot, Vector3(0.16, 0.1, 0.06), Vector3(0, -0.44, -0.09), pad)
	_part(pivot, Vector3(0.16, 0.13, 0.27), Vector3(0, -0.855, -0.04), boot)
	return pivot


func set_team_color(color: Color) -> void:
	_team_material.albedo_color = color


func set_weapon(data: WeaponData) -> void:
	weapon_visual.build(data, true)


## World position of the muzzle of the held weapon.
func muzzle_position() -> Vector3:
	return weapon_visual.to_global(weapon_visual.muzzle_local)


## In first person the local player's own body is hidden but keeps casting
## a shadow.
func set_shadow_only(shadow_only: bool) -> void:
	var mode := (GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if shadow_only
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	for mesh in _meshes:
		mesh.cast_shadow = mode
	for child in weapon_visual.get_children():
		if child is MeshInstance3D:
			child.cast_shadow = mode


## Call every frame. `height` is the capsule height (stand 1.8, crouch 1.1).
func animate(delta: float, horizontal_speed: float, height: float, pitch: float,
		on_floor: bool) -> void:
	# Crouch: lower the hips and fold the legs.
	var crouch := clampf((1.8 - height) / 0.7, 0.0, 1.0)
	var hip_y := lerpf(0.92, 0.5, crouch)
	_hips.position.y = hip_y
	_upper.position.y = hip_y
	_upper.rotation.x = pitch * 0.8

	# Walk cycle: phase advances with distance covered.
	var swing := 0.0
	if on_floor and horizontal_speed > 0.3:
		_walk_phase += delta * horizontal_speed * 2.6
		swing = sin(_walk_phase) * clampf(horizontal_speed / 5.0, 0.2, 1.0) * 0.7
	var fold := crouch * 1.1
	_leg_left.rotation.x = swing + fold
	_leg_right.rotation.x = -swing + fold * 0.3
	if not on_floor:
		_leg_left.rotation.x = 0.5
		_leg_right.rotation.x = -0.3


func play_death() -> void:
	if _death_tween:
		_death_tween.kill()
	_death_tween = create_tween()
	_death_tween.tween_property(self, "rotation:x", -PI * 0.5, 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_death_tween.parallel().tween_property(self, "position:y", 0.15, 0.35)


func reset_pose() -> void:
	if _death_tween:
		_death_tween.kill()
	rotation = Vector3.ZERO
	position = Vector3.ZERO


func _part(parent: Node3D, size: Vector3, position: Vector3, material: Material,
		yaw: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.rotation.y = yaw
	instance.layers = 2        # render layer 2 = characters (decals skip them)
	parent.add_child(instance)
	_meshes.append(instance)
	return instance
