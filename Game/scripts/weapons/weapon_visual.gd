class_name WeaponVisual
extends Node3D
## Builds a simple gun model out of boxes from a WeaponData row, so every
## weapon has a distinct silhouette without any imported model. The gun
## points along -Z with the grip at the origin. Swap this for a real mesh
## later by replacing build().

## Local position of the muzzle tip (where flashes and tracers start).
var muzzle_local := Vector3(0.0, 0.03, -0.5)
## Height of the sight line above the grip; the camera lines up with this
## when aiming down sights.
var sight_height := 0.075
var _material: StandardMaterial3D
var _dark: StandardMaterial3D


func build(data: WeaponData, shadows: bool) -> void:
	for child in get_children():
		child.queue_free()
	_material = StandardMaterial3D.new()
	_material.albedo_color = data.model_color
	_material.metallic = 0.5
	_material.roughness = 0.45
	_dark = StandardMaterial3D.new()
	_dark.albedo_color = Color(0.07, 0.07, 0.08)
	_dark.metallic = 0.6
	_dark.roughness = 0.4

	var length := data.model_length
	var is_pistol := data.category == "pistol"
	var body_len := length * (0.9 if is_pistol else 0.45)
	var body_h := 0.05 if is_pistol else 0.075
	var width := 0.035 if is_pistol else 0.05

	# Receiver / slide.
	_box(Vector3(width, body_h, body_len), Vector3(0, 0.03, -body_len * 0.5 + 0.04), _material)
	# Grip.
	_box(Vector3(width * 0.8, 0.11, 0.04), Vector3(0, -0.04, 0.02), _dark, 0.3)

	var front := -body_len + 0.04
	if not is_pistol:
		# Barrel and handguard.
		var barrel_len := length * 0.42
		_box(Vector3(0.022, 0.022, barrel_len), Vector3(0, 0.035, front - barrel_len * 0.5), _dark)
		_box(Vector3(width * 0.9, 0.05, barrel_len * 0.55),
				Vector3(0, 0.03, front - barrel_len * 0.28), _material)
		front -= barrel_len
		# Stock.
		var stock_len := length * 0.26
		_box(Vector3(width * 0.8, 0.06, stock_len), Vector3(0, 0.02, 0.04 + stock_len * 0.5), _material)
		# Magazine (snipers have a short internal one).
		var mag_h := 0.05 if data.category == "sniper" else 0.13
		if data.attachments.get("magazine", "") == "mag_extended":
			mag_h *= 1.4
		var mag_tilt := 0.25 if data.id == "ar_vulture" else 0.05
		_box(Vector3(width * 0.7, mag_h, 0.045), Vector3(0, -mag_h * 0.5, -body_len * 0.45), _dark, mag_tilt)
		if data.attachments.has("grip"):
			_box(Vector3(0.025, 0.07, 0.025), Vector3(0, -0.03, -body_len - 0.08), _dark)

	# Scope: a built-in one for snipers, otherwise only if attached.
	var scope: String = data.attachments.get("scope", "")
	if scope != "" or data.category == "sniper":
		var long_scope := scope in ["scope_4x", "scope_8x"] or data.category == "sniper"
		var scope_len := 0.24 if long_scope else 0.08
		_box(Vector3(0.035, 0.035, scope_len), Vector3(0, 0.095, -body_len * 0.45), _dark)
		_box(Vector3(0.02, 0.03, 0.03), Vector3(0, 0.07, -body_len * 0.45), _dark)

	var muzzle: String = data.attachments.get("muzzle", "")
	if muzzle == "muzzle_suppressor":
		_box(Vector3(0.036, 0.036, 0.16), Vector3(0, 0.035, front - 0.08), _dark)
		front -= 0.16
	elif muzzle != "":
		_box(Vector3(0.03, 0.03, 0.05), Vector3(0, 0.035, front - 0.025), _dark)
		front -= 0.05

	sight_height = 0.115 if (scope != "" or data.category == "sniper") else 0.075
	muzzle_local = Vector3(0.0, 0.035, front)
	set_shadows(shadows)


func set_shadows(enabled: bool) -> void:
	for child in get_children():
		if child is MeshInstance3D:
			child.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func _box(size: Vector3, position: Vector3, material: Material, tilt: float = 0.0) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.rotation.x = tilt
	add_child(instance)
