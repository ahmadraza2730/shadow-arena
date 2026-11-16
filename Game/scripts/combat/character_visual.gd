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
	_team_material = StandardMaterial3D.new()
	_team_material.roughness = 0.85
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.13, 0.14, 0.12)
	dark.roughness = 0.9
	var skin := StandardMaterial3D.new()
	skin.albedo_color = SKIN
	skin.roughness = 0.8

	_hips = Node3D.new()
	_hips.position.y = 0.92
	add_child(_hips)
	_leg_left = _limb(_hips, Vector3(-0.11, 0, 0), Vector3(0.15, 0.9, 0.17), dark)
	_leg_right = _limb(_hips, Vector3(0.11, 0, 0), Vector3(0.15, 0.9, 0.17), dark)

	_upper = Node3D.new()
	_upper.position.y = 0.92
	add_child(_upper)
	_part(_upper, Vector3(0.44, 0.58, 0.24), Vector3(0, 0.3, 0), _team_material)   # torso
	_part(_upper, Vector3(0.46, 0.3, 0.26), Vector3(0, 0.36, 0), dark)             # vest
	_part(_upper, Vector3(0.2, 0.22, 0.2), Vector3(0, 0.72, 0), skin)              # head
	_part(_upper, Vector3(0.24, 0.1, 0.25), Vector3(0, 0.84, 0), _team_material)   # helmet
	# Arms reach forward to hold the weapon.
	_part(_upper, Vector3(0.1, 0.1, 0.5), Vector3(0.22, 0.42, -0.2), _team_material)
	_part(_upper, Vector3(0.1, 0.1, 0.55), Vector3(-0.16, 0.4, -0.25), _team_material, 0.35)

	weapon_visual = WeaponVisual.new()
	weapon_visual.position = Vector3(0.18, 0.4, -0.38)
	_upper.add_child(weapon_visual)


func set_team_color(color: Color) -> void:
	_team_material.albedo_color = color.darkened(0.25)


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


## A leg: a pivot at the hip with the box hanging below it.
func _limb(parent: Node3D, offset: Vector3, size: Vector3, material: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = offset
	parent.add_child(pivot)
	_part(pivot, size, Vector3(0, -size.y * 0.5, 0), material)
	return pivot
