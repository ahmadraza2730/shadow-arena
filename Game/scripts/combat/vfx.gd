class_name Vfx
extends Node3D
## All short-lived visual effects, pooled so nothing is created or freed
## during a firefight:
##   impacts (dust / sparks / splinters / blood), bullet-hole decals,
##   tracers, muzzle flashes and ejected shell casings.

const IMPACT_KINDS := {
	# kind: [colour, particle count, speed, gravity, size, sound]
	"concrete": [Color(0.72, 0.68, 0.6), 10, 3.0, 6.0, 0.05, "impact"],
	"brick": [Color(0.6, 0.32, 0.24), 10, 3.0, 6.0, 0.05, "impact"],
	"metal": [Color(1.0, 0.8, 0.35), 8, 7.0, 9.0, 0.025, "ricochet"],
	"wood": [Color(0.55, 0.4, 0.22), 9, 3.5, 8.0, 0.045, "impact"],
	"blood": [Color(0.6, 0.03, 0.03), 9, 2.5, 8.0, 0.04, ""],
}
const EMITTERS_PER_KIND := 5
const TRACER_COUNT := 24
const FLASH_COUNT := 6
const CASING_COUNT := 14

var _emitters: Dictionary = {}       # kind -> Array[CPUParticles3D]
var _emitter_next: Dictionary = {}   # kind -> int
var _decals: Array[Decal] = []
var _decal_next := 0
var _tracers: Array[MeshInstance3D] = []
var _tracer_ttl: PackedFloat32Array = []
var _tracer_next := 0
var _flashes: Array[Node3D] = []
var _flash_ttl: PackedFloat32Array = []
var _flash_next := 0
var _casings: Array[MeshInstance3D] = []
var _casing_vel: Array[Vector3] = []
var _casing_ttl: PackedFloat32Array = []
var _casing_next := 0
var _quality: Dictionary


func _ready() -> void:
	_quality = Game.quality()
	_build_emitters()
	_build_decals()
	_build_tracers()
	_build_flashes()
	_build_casings()


# ------------------------------------------------------------------ public
## Particle burst (and optionally a bullet hole) where a bullet landed.
func impact(kind: String, position: Vector3, normal: Vector3, with_decal: bool) -> void:
	if not _emitters.has(kind):
		kind = "concrete"
	var list: Array = _emitters[kind]
	var index: int = _emitter_next[kind]
	_emitter_next[kind] = (index + 1) % list.size()
	var emitter: CPUParticles3D = list[index]
	emitter.global_position = position + normal * 0.02
	emitter.direction = normal
	emitter.restart()
	emitter.emitting = true
	var sound: String = IMPACT_KINDS[kind][5]
	if sound != "" and randf() < 0.5:
		Sfx.play(sound, position, -10.0, randf_range(0.8, 1.2))
	if with_decal and not _decals.is_empty():
		var decal := _decals[_decal_next]
		_decal_next = (_decal_next + 1) % _decals.size()
		decal.visible = true
		decal.global_transform = Transform3D(_basis_with_up(normal), position)
		decal.rotate_object_local(Vector3.UP, randf() * TAU)


## A bright streak from `from` to `to` that lasts a couple of frames.
func tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 1.5:
		return
	var mesh := _tracers[_tracer_next]
	_tracer_ttl[_tracer_next] = 0.05
	_tracer_next = (_tracer_next + 1) % TRACER_COUNT
	# Draw only the last part of the path so it reads as a fast streak.
	var streak := minf(length, 30.0)
	var direction := (to - from) / length
	var centre := to - direction * streak * 0.5
	mesh.global_transform = Transform3D(_basis_with_forward(direction), centre)
	mesh.scale = Vector3(1.0, 1.0, streak)
	mesh.visible = true


func muzzle_flash(position: Vector3, direction: Vector3) -> void:
	var flash := _flashes[_flash_next]
	_flash_ttl[_flash_next] = 0.045
	_flash_next = (_flash_next + 1) % FLASH_COUNT
	flash.global_transform = Transform3D(_basis_with_forward(direction), position)
	flash.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	flash.visible = true


func eject_casing(position: Vector3, aim: Vector3) -> void:
	if _casings.is_empty():
		return
	var casing := _casings[_casing_next]
	var right := aim.cross(Vector3.UP).normalized()
	_casing_vel[_casing_next] = right * randf_range(1.5, 2.5) + Vector3.UP * randf_range(1.5, 2.5)
	_casing_ttl[_casing_next] = 2.5
	_casing_next = (_casing_next + 1) % _casings.size()
	casing.global_position = position
	casing.rotation = Vector3(randf() * TAU, randf() * TAU, 0.0)
	casing.visible = true


func _process(delta: float) -> void:
	for i in TRACER_COUNT:
		if _tracer_ttl[i] > 0.0:
			_tracer_ttl[i] -= delta
			if _tracer_ttl[i] <= 0.0:
				_tracers[i].visible = false
	for i in FLASH_COUNT:
		if _flash_ttl[i] > 0.0:
			_flash_ttl[i] -= delta
			if _flash_ttl[i] <= 0.0:
				_flashes[i].visible = false
	for i in _casings.size():
		if _casing_ttl[i] <= 0.0:
			continue
		_casing_ttl[i] -= delta
		var casing := _casings[i]
		if _casing_ttl[i] <= 0.0:
			casing.visible = false
		elif _casing_ttl[i] > 1.9:
			# Simple arc for the first 0.6 s, then it just lies there.
			_casing_vel[i].y -= 9.8 * delta
			casing.global_position += _casing_vel[i] * delta
			casing.rotate_x(12.0 * delta)


# ----------------------------------------------------------------- helpers
## A basis whose Y axis points along `up` (used for decals).
func _basis_with_up(up: Vector3) -> Basis:
	var y := up.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	return Basis(x, y, x.cross(y).normalized())


## A basis whose -Z axis points along `forward`.
func _basis_with_forward(forward: Vector3) -> Basis:
	var z := -forward.normalized()
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 0.001:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	return Basis(x, z.cross(x).normalized(), z)


func _unshaded(color: Color, emission := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	if emission:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


# ------------------------------------------------------------------ pools
func _build_emitters() -> void:
	var scale_amount: float = _quality["particles"]
	for kind: String in IMPACT_KINDS:
		var spec: Array = IMPACT_KINDS[kind]
		var list: Array = []
		for i in EMITTERS_PER_KIND:
			var p := CPUParticles3D.new()
			p.emitting = false
			p.one_shot = true
			p.explosiveness = 1.0
			p.amount = maxi(3, int(spec[1] * scale_amount))
			p.lifetime = 0.45
			p.spread = 40.0
			p.initial_velocity_min = spec[2] * 0.4
			p.initial_velocity_max = spec[2]
			p.gravity = Vector3(0.0, -spec[3], 0.0)
			p.scale_amount_min = 0.6
			p.scale_amount_max = 1.4
			var mesh := BoxMesh.new()
			mesh.size = Vector3.ONE * spec[4]
			mesh.material = _unshaded(spec[0]) if kind == "metal" else _lit(spec[0])
			p.mesh = mesh
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(p)
			list.append(p)
		_emitters[kind] = list
		_emitter_next[kind] = 0


func _lit(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material


func _build_decals() -> void:
	# A soft dark dot generated in code: no texture file needed.
	var size := 32
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x - size / 2.0 + 0.5, y - size / 2.0 + 0.5).length() / (size / 2.0)
			var alpha := clampf(1.0 - d, 0.0, 1.0)
			image.set_pixel(x, y, Color(0.03, 0.03, 0.03, pow(alpha, 0.6)))
	var texture := ImageTexture.create_from_image(image)
	for i in int(_quality["decals"]):
		var decal := Decal.new()
		decal.texture_albedo = texture
		decal.size = Vector3(0.14, 0.2, 0.14)
		decal.visible = false
		decal.cull_mask = 1          # world only, never characters (layer 2)
		add_child(decal)
		_decals.append(decal)


func _build_tracers() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.025, 1.0)
	mesh.material = _unshaded(Color(1.0, 0.85, 0.5, 0.55), true)
	_tracer_ttl.resize(TRACER_COUNT)
	for i in TRACER_COUNT:
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.visible = false
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		_tracers.append(instance)


func _build_flashes() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.32, 0.32)
	quad.material = _unshaded(Color(1.0, 0.75, 0.35, 0.9), true)
	_flash_ttl.resize(FLASH_COUNT)
	for i in FLASH_COUNT:
		var root := Node3D.new()
		root.visible = false
		var a := MeshInstance3D.new()
		a.mesh = quad
		a.position.z = -0.12
		a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(a)
		# A second quad seen from the side so the flash has depth.
		var b := MeshInstance3D.new()
		b.mesh = quad
		b.position.z = -0.16
		b.rotation.y = PI * 0.5
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(b)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.75, 0.4)
		light.light_energy = 2.0
		light.omni_range = 5.0
		light.shadow_enabled = false
		root.add_child(light)
		add_child(root)
		_flashes.append(root)


func _build_casings() -> void:
	if not _quality["casings"]:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.006
	mesh.bottom_radius = 0.006
	mesh.height = 0.03
	mesh.radial_segments = 6
	mesh.rings = 1
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.8, 0.62, 0.25)
	material.metallic = 0.9
	material.roughness = 0.35
	mesh.material = material
	_casing_ttl.resize(CASING_COUNT)
	for i in CASING_COUNT:
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.visible = false
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		_casings.append(instance)
		_casing_vel.append(Vector3.ZERO)
