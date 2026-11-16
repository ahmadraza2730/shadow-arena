class_name ArenaEnvironment
extends Node3D
## Sky, sun, fog, post-processing and weather for the arena, built in code
## from one of the PRESETS below and scaled by the graphics quality preset.
##
## The Mobile renderer is used for speed, so the look comes from: a
## procedural sky, one shadowed sun, sky ambient light, depth fog (the
## "dusty air"), bloom, filmic tonemapping and colour grading. Volumetric
## fog and SSAO need the Forward+ renderer and a much stronger GPU.

const PRESETS: Array[Dictionary] = [
	{"name": "Dusty Afternoon",
		"sun_pitch": -52.0, "sun_yaw": 35.0, "sun_color": Color(1.0, 0.95, 0.84), "sun_energy": 1.0,
		"sky_top": Color(0.3, 0.5, 0.82), "sky_horizon": Color(0.82, 0.76, 0.64),
		"ambient": 0.42, "ambient_color": Color(0.7, 0.68, 0.66), "fog_color": Color(0.78, 0.72, 0.62), "fog_density": 0.0022,
		"saturation": 1.1, "contrast": 1.1, "rain": false, "clouds": Color(1.0, 0.98, 0.95, 0.9)},
	{"name": "Golden Dusk",
		"sun_pitch": -11.0, "sun_yaw": 80.0, "sun_color": Color(1.0, 0.6, 0.32), "sun_energy": 0.95,
		"sky_top": Color(0.22, 0.24, 0.5), "sky_horizon": Color(0.95, 0.55, 0.3),
		"ambient": 0.38, "ambient_color": Color(0.62, 0.5, 0.5), "fog_color": Color(0.8, 0.5, 0.34), "fog_density": 0.004,
		"saturation": 1.15, "contrast": 1.12, "rain": false, "clouds": Color(1.0, 0.7, 0.5, 1.0)},
	{"name": "Overcast Rain",
		"sun_pitch": -65.0, "sun_yaw": 10.0, "sun_color": Color(0.75, 0.8, 0.88), "sun_energy": 0.55,
		"sky_top": Color(0.4, 0.43, 0.47), "sky_horizon": Color(0.6, 0.62, 0.64),
		"ambient": 0.6, "ambient_color": Color(0.62, 0.66, 0.7), "fog_color": Color(0.52, 0.55, 0.58), "fog_density": 0.008,
		"saturation": 0.85, "contrast": 1.04, "rain": true, "clouds": Color(0.5, 0.52, 0.55, 1.0)},
]

var sun: DirectionalLight3D
var _dust: CPUParticles3D
var _rain: CPUParticles3D


func build(preset_index: int) -> void:
	var preset := PRESETS[clampi(preset_index, 0, PRESETS.size() - 1)]
	var quality := Game.quality()

	# --- Sky ---
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = preset["sky_top"]
	sky_material.sky_horizon_color = preset["sky_horizon"]
	sky_material.ground_horizon_color = preset["sky_horizon"]
	sky_material.ground_bottom_color = (preset["sky_horizon"] as Color).darkened(0.5)
	# A generated cloud layer wrapped around the sky dome.
	sky_material.sky_cover = load("res://assets/textures/clouds.png")
	sky_material.sky_cover_modulate = preset["clouds"]
	var sky := Sky.new()
	sky.sky_material = sky_material

	# --- Environment: ambient light, fog, tonemap, bloom, colour grade ---
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# A fixed ambient colour (not the blue sky) keeps interiors neutral.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = preset["ambient_color"]
	env.ambient_light_energy = preset["ambient"]
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = quality["fog"]
	env.fog_light_color = preset["fog_color"]
	env.fog_density = preset["fog_density"]
	env.fog_sky_affect = 0.3
	env.glow_enabled = quality["glow"]
	env.glow_intensity = 0.6
	env.glow_bloom = 0.08
	env.adjustment_enabled = true
	env.adjustment_saturation = preset["saturation"]
	env.adjustment_contrast = preset["contrast"]
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# --- Sun ---
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(preset["sun_pitch"], preset["sun_yaw"], 0.0)
	sun.light_color = preset["sun_color"]
	sun.light_energy = preset["sun_energy"]
	sun.shadow_enabled = quality["shadows"]
	sun.directional_shadow_max_distance = quality["shadow_distance"]
	sun.directional_shadow_mode = (DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			if int(Game.settings["quality"]) == 2 else DirectionalLight3D.SHADOW_ORTHOGONAL)
	add_child(sun)

	if quality["dust"] and not preset["rain"]:
		_build_dust(preset["fog_color"], quality["particles"])
	if preset["rain"]:
		_build_rain(quality["particles"])


## Keeps the weather centred on the player so it never has to cover the
## whole map.
func follow(position: Vector3) -> void:
	if _dust:
		_dust.global_position = position + Vector3.UP * 2.0
	if _rain:
		_rain.global_position = position + Vector3.UP * 9.0


func _particle_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	return material


## Slow drifting motes that catch the light: cheap "dusty air".
func _build_dust(color: Color, amount_scale: float) -> void:
	_dust = CPUParticles3D.new()
	_dust.amount = int(90 * amount_scale)
	_dust.lifetime = 7.0
	_dust.preprocess = 7.0
	_dust.local_coords = false
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(14.0, 3.0, 14.0)
	_dust.direction = Vector3(1.0, 0.1, 0.3)
	_dust.spread = 40.0
	_dust.gravity = Vector3.ZERO
	_dust.initial_velocity_min = 0.1
	_dust.initial_velocity_max = 0.5
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	quad.material = _particle_material(Color(color.r, color.g, color.b, 0.45))
	_dust.mesh = quad
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dust)


func _build_rain(amount_scale: float) -> void:
	_rain = CPUParticles3D.new()
	_rain.amount = int(500 * amount_scale)
	_rain.lifetime = 0.7
	_rain.preprocess = 0.7
	_rain.local_coords = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(16.0, 0.5, 16.0)
	_rain.direction = Vector3(0.08, -1.0, 0.0)
	_rain.spread = 2.0
	_rain.gravity = Vector3.ZERO
	_rain.initial_velocity_min = 15.0
	_rain.initial_velocity_max = 18.0
	var streak := BoxMesh.new()
	streak.size = Vector3(0.008, 0.45, 0.008)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.8, 0.85, 0.9, 0.35)
	streak.material = material
	_rain.mesh = streak
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)
