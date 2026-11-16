class_name CharacterVisual
extends Node3D
## The soldier you see in the world: a rigged, animated human body
## (Quaternius "Universal Animation Library" mannequin, CC0) dressed in
## camouflage with a helmet, goggles, plate carrier and backpack, holding
## the current weapon's 3D model.
##
## Animation is driven by an AnimationTree built in code:
##   legs  = idle / walk / jog / sprint / crouch / jump / death, cross-faded
##   arms  = a two-handed aim pose, blended over the upper body only
##   spine = bent up/down by AimModifier to follow the aim pitch

const BODY_SCENE := "res://third_party/quaternius_ual/AnimationLibrary_Godot_Standard.gltf"
const UPPER_BODY := ["spine.002", "spine.003", "neck", "head", "shoulder", "upper_arm",
		"forearm", "hand", "f_index", "f_middle", "f_pinky", "f_ring", "thumb"]
## Locomotion states: tree input name -> animation clip.
const CLIPS := {
	"idle": "Idle", "walk": "Walk", "jog": "Jog_Fwd", "sprint": "Sprint",
	"crouch_idle": "Crouch_Idle", "crouch_walk": "Crouch_Fwd", "jump": "Jump",
	"death": "Death01",
}
const AIM_CLIP := "Pistol_Aim_Neutral"

var weapon_visual: WeaponVisual
var _body: Node3D
var _skeleton: Skeleton3D
var _tree: AnimationTree
var _aim: AimModifier
var _meshes: Array[MeshInstance3D] = []
var _team_material: StandardMaterial3D
var _state := ""
var _aim_blend := 1.0
var _dead := false
var _shadow_mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _init() -> void:
	_team_material = StandardMaterial3D.new()
	_team_material.roughness = 0.7

	_body = (load(BODY_SCENE) as PackedScene).instantiate()
	_body.rotation.y = PI          # the model faces +Z; fighters face -Z
	add_child(_body)
	_skeleton = _body.find_child("Skeleton3D", true, false)
	var player: AnimationPlayer = _body.find_child("AnimationPlayer", true, false)

	_dress()
	_build_animation_tree(player)

	_aim = AimModifier.new()
	_aim.chest_bone = _skeleton.find_bone("DEF-spine.003")
	_aim.chest_reference = _pose_in_clip(player.get_animation(AIM_CLIP), _aim.chest_bone).basis
	_skeleton.add_child(_aim)

	# The weapon rides on the right hand. Its offset is solved once from
	# the aim pose so that the barrel points straight ahead.
	weapon_visual = WeaponVisual.new()
	var hand := BoneAttachment3D.new()
	hand.bone_name = "DEF-hand.R"
	_skeleton.add_child(hand)
	hand.add_child(weapon_visual)
	# Target in model space: barrel along +Z (model forward), grip in the palm.
	var hand_pose := _pose_in_clip(player.get_animation(AIM_CLIP), _skeleton.find_bone("DEF-hand.R"))
	var grip := Transform3D(Basis(Vector3.UP, PI), hand_pose.origin + Vector3(0.0, 0.07, 0.04))
	weapon_visual.transform = hand_pose.affine_inverse() * grip


# ------------------------------------------------------------------ public
func set_team_color(color: Color) -> void:
	_team_material.albedo_color = color.darkened(0.15)


func set_weapon(data: WeaponData) -> void:
	weapon_visual.build(data, true)
	weapon_visual.set_shadow_mode(_shadow_mode)


## World position of the muzzle of the held weapon.
func muzzle_position() -> Vector3:
	return weapon_visual.to_global(weapon_visual.muzzle_local)


## In first person the local player's own body is hidden but keeps casting
## a shadow.
func set_shadow_only(shadow_only: bool) -> void:
	_shadow_mode = (GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if shadow_only
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	for mesh in _meshes:
		mesh.cast_shadow = _shadow_mode
	weapon_visual.set_shadow_mode(_shadow_mode)


## Call every frame. `height` is the capsule height (stand 1.8, crouch 1.1).
func animate(delta: float, horizontal_speed: float, height: float, pitch: float,
		on_floor: bool) -> void:
	if _dead:
		return
	var crouched := height < 1.5
	var state := "idle"
	if not on_floor:
		state = "jump"
	elif crouched:
		state = "crouch_walk" if horizontal_speed > 0.4 else "crouch_idle"
	elif horizontal_speed > 6.2:
		state = "sprint"
	elif horizontal_speed > 3.2:
		state = "jog"
	elif horizontal_speed > 0.4:
		state = "walk"
	_set_state(state)

	# Sprinting lowers the weapon; otherwise it is held up and aimed.
	var target_aim := 0.25 if state == "sprint" else 1.0
	_aim_blend = move_toward(_aim_blend, target_aim, delta * 5.0)
	_tree.set("parameters/aim/blend_amount", _aim_blend)
	_aim.pitch = pitch
	_aim.weight = _aim_blend


func play_death() -> void:
	_dead = true
	_aim.weight = 0.0
	_tree.set("parameters/aim/blend_amount", 0.0)
	_set_state("death")


func reset_pose() -> void:
	_dead = false
	_aim.weight = 1.0
	_aim_blend = 1.0
	_tree.set("parameters/aim/blend_amount", 1.0)
	_set_state("idle")


# ------------------------------------------------------------------- setup
func _set_state(state: String) -> void:
	if state == _state:
		return
	_state = state
	_tree.set("parameters/legs/transition_request", state)


## Camouflage and gear on the body, plus helmet, goggles, vest and pack.
func _dress() -> void:
	var camo := StandardMaterial3D.new()
	camo.albedo_texture = load("res://assets/textures/camo_albedo.jpg")
	camo.normal_enabled = true
	camo.normal_texture = load("res://assets/textures/camo_normal.jpg")
	camo.roughness = 0.95
	camo.uv1_scale = Vector3(1.8, 1.8, 1.8)
	camo.uv1_triplanar = true
	camo.albedo_color = Color(0.85, 0.85, 0.8)
	var gear := StandardMaterial3D.new()
	gear.albedo_color = Color(0.13, 0.14, 0.11)
	gear.roughness = 0.9
	var balaclava := StandardMaterial3D.new()
	balaclava.albedo_color = Color(0.07, 0.075, 0.07)
	balaclava.roughness = 1.0
	var glove := StandardMaterial3D.new()
	glove.albedo_color = Color(0.1, 0.1, 0.09)
	glove.roughness = 0.75
	var boot := StandardMaterial3D.new()
	boot.albedo_color = Color(0.2, 0.15, 0.1)
	boot.roughness = 0.65
	var pouch := StandardMaterial3D.new()
	pouch.albedo_color = Color(0.3, 0.29, 0.21)
	pouch.roughness = 0.95
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(0.03, 0.03, 0.04)
	lens.roughness = 0.15
	lens.metallic = 0.4

	var body_mesh: MeshInstance3D = _body.find_child("Mannequin", true, false)
	body_mesh.set_surface_override_material(0, camo)     # cloth
	body_mesh.set_surface_override_material(1, gear)     # joints -> pads
	body_mesh.layers = 2
	_meshes.append(body_mesh)

	# Gear positions are given in the model's rest pose (metres, model
	# faces +Z) and converted into each bone's local space.
	var helmet := SphereMesh.new()
	helmet.radius = 0.138
	helmet.height = 0.2
	helmet.radial_segments = 18
	helmet.rings = 9
	helmet.is_hemisphere = true
	_gear("DEF-head", helmet, Vector3(0, 1.735, -0.005), _team_material)
	# Balaclava: a fabric hood over the whole head, like a real operator.
	var hood := SphereMesh.new()
	hood.radius = 0.112
	hood.height = 0.25
	hood.radial_segments = 16
	hood.rings = 10
	_gear("DEF-head", hood, Vector3(0, 1.665, 0.004), balaclava)
	_gear("DEF-head", _box_mesh(Vector3(0.17, 0.05, 0.04)), Vector3(0, 1.69, 0.105), lens)      # goggles
	_gear("DEF-head", _box_mesh(Vector3(0.2, 0.025, 0.025)), Vector3(0, 1.69, 0.085), gear)    # goggle strap
	_gear("DEF-head", _box_mesh(Vector3(0.05, 0.05, 0.05)), Vector3(0.12, 1.66, 0.0), gear)    # headset cup
	_gear("DEF-spine.003", _box_mesh(Vector3(0.33, 0.31, 0.23)), Vector3(0, 1.3, 0.01), gear)   # plate carrier
	_gear("DEF-spine.003", _box_mesh(Vector3(0.26, 0.34, 0.12)), Vector3(0, 1.3, -0.17), gear)  # backpack
	_gear("DEF-spine.003", _box_mesh(Vector3(0.08, 0.3, 0.09)), Vector3(-0.08, 1.32, -0.26), pouch)  # hydration
	for x: float in [-0.11, 0.0, 0.11]:
		_gear("DEF-spine.002", _box_mesh(Vector3(0.09, 0.13, 0.07)), Vector3(x, 1.17, 0.15), pouch)  # magazine pouches
	_gear("DEF-spine.002", _box_mesh(Vector3(0.16, 0.08, 0.06)), Vector3(0, 1.06, 0.14), gear)   # admin pouch
	_gear("DEF-hips", _box_mesh(Vector3(0.38, 0.07, 0.25)), Vector3(0, 0.99, 0.0), gear)          # belt
	_gear("DEF-hips", _box_mesh(Vector3(0.07, 0.1, 0.06)), Vector3(0.2, 0.95, 0.03), pouch)       # belt pouch
	_gear("DEF-thigh.R", _box_mesh(Vector3(0.08, 0.17, 0.12)), Vector3(-0.17, 0.8, 0.0), gear)    # holster
	# Gloves, boots and knee pads sit on the limb bones, placed from the rest pose.
	for side: String in ["L", "R"]:
		var x := 1.0 if side == "L" else -1.0
		# The rest pose is a T-pose, so hands point along X.
		_gear_on_bone("DEF-hand." + side, _box_mesh(Vector3(0.11, 0.05, 0.09)), Vector3(x * 0.045, 0.0, 0.0), glove)
		_gear_on_bone("DEF-foot." + side, _box_mesh(Vector3(0.1, 0.1, 0.24)), Vector3(0, -0.05, 0.07), boot)
		_gear_on_bone("DEF-shin." + side, _box_mesh(Vector3(0.1, 0.09, 0.05)), Vector3(0, 0.0, 0.065), gear)  # knee pad

	# Team-colour armbands follow the upper arms (bone space: Y runs along the bone).
	for side: String in ["L", "R"]:
		var band := _attach("DEF-upper_arm." + side)
		_add_mesh(band, _box_mesh(Vector3(0.125, 0.07, 0.125)),
				Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)), _team_material)


func _attach(bone: String) -> BoneAttachment3D:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone
	_skeleton.add_child(attachment)
	return attachment


func _gear(bone: String, mesh: Mesh, rest_position: Vector3, material: Material) -> void:
	if _skeleton.find_bone(bone) < 0:
		return
	var attachment := _attach(bone)
	var bone_rest := _skeleton.get_bone_global_rest(_skeleton.find_bone(bone))
	_add_mesh(attachment, mesh, bone_rest.affine_inverse() * Transform3D(Basis.IDENTITY, rest_position),
			material)


## Like _gear, but the position is an offset from the bone's own rest
## position (handy for hands and feet, wherever the model puts them).
func _gear_on_bone(bone: String, mesh: Mesh, offset: Vector3, material: Material) -> void:
	var index := _skeleton.find_bone(bone)
	if index < 0:
		return
	_gear(bone, mesh, _skeleton.get_bone_global_rest(index).origin + offset, material)


func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _add_mesh(parent: Node3D, mesh: Mesh, xform: Transform3D, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.transform = xform
	instance.layers = 2
	parent.add_child(instance)
	_meshes.append(instance)


func _build_animation_tree(player: AnimationPlayer) -> void:
	var root := AnimationNodeBlendTree.new()

	# Legs: one input per locomotion clip, cross-faded on request.
	var legs := AnimationNodeTransition.new()
	legs.xfade_time = 0.18
	legs.input_count = CLIPS.size()
	root.add_node("legs", legs)
	var index := 0
	for state: String in CLIPS:
		legs.set_input_name(index, state)
		var clip := AnimationNodeAnimation.new()
		clip.animation = CLIPS[state]
		root.add_node("clip_" + state, clip)
		root.connect_node("legs", index, "clip_" + state)
		index += 1

	# Arms: the aim pose, applied only to upper-body bones.
	var aim_clip := AnimationNodeAnimation.new()
	aim_clip.animation = AIM_CLIP
	root.add_node("aim_pose", aim_clip)
	var aim := AnimationNodeBlend2.new()
	aim.filter_enabled = true
	var animation := player.get_animation(AIM_CLIP)
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		var bone := str(path.get_concatenated_subnames())
		for part: String in UPPER_BODY:
			if bone.contains(part):
				aim.set_filter_path(path, true)
				break
	root.add_node("aim", aim)
	root.connect_node("aim", 0, "legs")
	root.connect_node("aim", 1, "aim_pose")
	root.connect_node("output", 0, "aim")

	_tree = AnimationTree.new()
	_tree.tree_root = root
	_body.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(player)
	_tree.active = true
	_tree.set("parameters/aim/blend_amount", 1.0)
	_set_state("idle")


## Where a bone is (skeleton space) at the start of an animation clip.
## Walks up the bone chain sampling each bone's tracks at time 0, using
## the rest pose for bones the clip does not animate.
func _pose_in_clip(animation: Animation, bone: int) -> Transform3D:
	var pose := Transform3D.IDENTITY
	var current := bone
	while current >= 0:
		var local := _skeleton.get_bone_rest(current)
		var bone_name := _skeleton.get_bone_name(current)
		for track in animation.get_track_count():
			if str(animation.track_get_path(track).get_concatenated_subnames()) != bone_name:
				continue
			match animation.track_get_type(track):
				Animation.TYPE_ROTATION_3D:
					local.basis = Basis(animation.rotation_track_interpolate(track, 0.0))
				Animation.TYPE_POSITION_3D:
					local.origin = animation.position_track_interpolate(track, 0.0)
		pose = local * pose
		current = _skeleton.get_bone_parent(current)
	return pose
