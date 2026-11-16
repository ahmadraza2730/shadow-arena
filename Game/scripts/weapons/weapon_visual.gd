class_name WeaponVisual
extends Node3D
## The 3D model of a weapon, used both in the player's hands (first
## person) and on every soldier (third person).
##
## It loads the weapon's .glb from third_party/flat_guns (CC0 "Flat Guns"
## pack) and adds a scope and muzzle device for fitted attachments. If a
## weapon has no model file it falls back to a simple box gun, so new rows
## in weapons.json still work before art exists.
##
## The gun points along -Z with the grip near the origin.

const MODEL_DIR := "res://third_party/flat_guns/"

## Local position of the muzzle tip (where flashes and tracers start).
var muzzle_local := Vector3(0.0, 0.03, -0.5)
## Height of the sight line above the origin; the camera lines up with
## this when aiming down sights.
var sight_height := 0.075
var _meshes: Array[MeshInstance3D] = []
var _dark: StandardMaterial3D


func build(data: WeaponData, shadows: bool) -> void:
	for child in get_children():
		child.queue_free()
	_meshes.clear()
	_dark = StandardMaterial3D.new()
	_dark.albedo_color = Color(0.07, 0.07, 0.08)
	_dark.metallic = 0.6
	_dark.roughness = 0.4

	var path := MODEL_DIR + data.model + ".glb"
	var bounds: AABB
	if data.model != "" and ResourceLoader.exists(path):
		var model: Node3D = (load(path) as PackedScene).instantiate()
		add_child(model)
		_collect_meshes(model)
		bounds = _bounds(model)
	else:
		bounds = _build_box_gun(data)

	var top := bounds.end.y
	var front := bounds.position.z           # most negative Z = muzzle end
	var barrel_y := top - 0.045
	sight_height = top + 0.004

	# Scope: a tube with wider bells at each end, on two small mounts.
	# Snipers always carry one; other weapons only when a scope is fitted.
	var scope: String = data.attachments.get("scope", "")
	if scope != "" or data.category == "sniper":
		var long_scope := scope in ["scope_4x", "scope_8x"] or data.category == "sniper"
		var scope_len := 0.24 if long_scope else 0.06
		var scope_z := lerpf(bounds.position.z, bounds.end.z, 0.56)
		var tube_y := top + 0.022
		_tube(0.010, scope_len, Vector3(0, tube_y, scope_z))
		_tube(0.014, 0.045, Vector3(0, tube_y, scope_z - scope_len * 0.5))
		_tube(0.012, 0.03, Vector3(0, tube_y, scope_z + scope_len * 0.5))
		_box(Vector3(0.012, 0.022, 0.014), Vector3(0, top + 0.008, scope_z - 0.04), _dark)
		_box(Vector3(0.012, 0.022, 0.014), Vector3(0, top + 0.008, scope_z + 0.04), _dark)
		sight_height = tube_y

	var muzzle: String = data.attachments.get("muzzle", "")
	if muzzle == "muzzle_suppressor":
		_tube(0.018, 0.17, Vector3(0, barrel_y, front - 0.085))
		front -= 0.17
	elif muzzle != "":
		_box(Vector3(0.03, 0.03, 0.05), Vector3(0, barrel_y, front - 0.025), _dark)
		front -= 0.05

	muzzle_local = Vector3(0.0, barrel_y, front)
	set_shadow_mode(GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


## Shadow mode for every mesh of the gun (on / off / shadows only).
func set_shadow_mode(mode: GeometryInstance3D.ShadowCastingSetting) -> void:
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.cast_shadow = mode


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		mesh.layers = 2          # characters/weapons layer (decals skip it)
		_meshes.append(mesh)
	for child in node.get_children():
		_collect_meshes(child)


## Bounding box of all meshes, in this node's local space.
func _bounds(model: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh in _meshes:
		var local := _relative_transform(mesh) * mesh.get_aabb()
		result = local if first else result.merge(local)
		first = false
	return result


func _relative_transform(node: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current: Node = node
	while current != self and current != null:
		if current is Node3D:
			xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform


func _box(size: Vector3, position: Vector3, material: Material, tilt: float = 0.0) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.rotation.x = tilt
	instance.layers = 2
	add_child(instance)
	_meshes.append(instance)


## A cylinder lying along the barrel axis (scopes, suppressors).
func _tube(radius: float, length: float, position: Vector3) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	mesh.rings = 1
	mesh.material = _dark
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.rotation.x = PI * 0.5
	instance.layers = 2
	add_child(instance)
	_meshes.append(instance)


## Fallback gun made of boxes; returns its bounding box.
func _build_box_gun(data: WeaponData) -> AABB:
	var body := StandardMaterial3D.new()
	body.albedo_color = data.model_color
	body.metallic = 0.5
	body.roughness = 0.45
	var length := data.model_length
	var is_pistol := data.category == "pistol"
	var body_len := length * (0.9 if is_pistol else 0.45)
	_box(Vector3(0.045, 0.07, body_len), Vector3(0, 0.03, -body_len * 0.5 + 0.04), body)
	_box(Vector3(0.036, 0.11, 0.04), Vector3(0, -0.04, 0.02), _dark, 0.3)
	var front := -body_len + 0.04
	if not is_pistol:
		var barrel_len := length * 0.42
		_box(Vector3(0.022, 0.022, barrel_len), Vector3(0, 0.035, front - barrel_len * 0.5), _dark)
		front -= barrel_len
		_box(Vector3(0.04, 0.06, length * 0.26), Vector3(0, 0.02, 0.04 + length * 0.13), body)
		_box(Vector3(0.035, 0.12, 0.045), Vector3(0, -0.06, -body_len * 0.45), _dark, 0.05)
	return AABB(Vector3(-0.025, -0.1, front), Vector3(0.05, 0.18, 0.04 + length * 0.26 - front))
