extends Node
## Sfx (autoload)
##
## Gunshots and footsteps are real recordings (CC0: Free Firearm Sound
## Library and Fantozzi footsteps) stored in assets/audio/. Every other
## sound (reload, hit marker, UI...) is synthesised here at start-up from
## noise and sine waves. Any sound without a file falls back to the
## synthesised version, and dropping "<name>.ogg" into assets/audio/
## replaces it.
##
## Use:  Sfx.play("shot_rifle", world_position)   # 3D, positional
##       Sfx.play("ui_click")                     # 2D, no position

const MIX_RATE := 22050
const POOL_3D := 20
const POOL_2D := 8
const AUDIO_DIR := "res://assets/audio/"
const STEP_VARIANTS := 6

var streams: Dictionary = {}
var _steps: Array[AudioStream] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _players_2d: Array[AudioStreamPlayer] = []
var _next_3d := 0
var _next_2d := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1234
	_build_streams()
	_load_recordings()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 14.0
		p.max_distance = 110.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_players_3d.append(p)
	for i in POOL_2D:
		var p2 := AudioStreamPlayer.new()
		add_child(p2)
		_players_2d.append(p2)


## Plays a sound. Pass a Vector3 for positional audio, or null for UI/2D.
func play(sound: String, position: Variant = null, volume_db: float = 0.0,
		pitch: float = 1.0) -> void:
	var stream: AudioStream = streams.get(sound)
	if sound == "step" and not _steps.is_empty():
		stream = _steps.pick_random()
	if stream == null:
		return
	if position is Vector3:
		var p := _players_3d[_next_3d]
		_next_3d = (_next_3d + 1) % POOL_3D
		p.stream = stream
		p.global_position = position
		p.volume_db = volume_db
		p.pitch_scale = pitch
		p.play()
	else:
		var p2 := _players_2d[_next_2d]
		_next_2d = (_next_2d + 1) % POOL_2D
		p2.stream = stream
		p2.volume_db = volume_db
		p2.pitch_scale = pitch
		p2.play()


## Replaces synthesised sounds with recorded ones where a file exists.
func _load_recordings() -> void:
	for sound: String in streams.keys():
		var path := AUDIO_DIR + sound + ".ogg"
		if ResourceLoader.exists(path):
			streams[sound] = load(path)
	for i in range(1, STEP_VARIANTS + 1):
		var path := AUDIO_DIR + "step_%d.ogg" % i
		if ResourceLoader.exists(path):
			_steps.append(load(path))


# ------------------------------------------------------------- synthesis
func _build_streams() -> void:
	# Gunshots: name, length, noise decay, low-pass, thump Hz, thump amount.
	streams["shot_rifle"] = _gunshot(0.22, 22.0, 0.55, 110.0, 0.7)
	streams["shot_rifle_heavy"] = _gunshot(0.28, 17.0, 0.4, 85.0, 0.9)
	streams["shot_smg"] = _gunshot(0.14, 34.0, 0.7, 150.0, 0.45)
	streams["shot_pistol"] = _gunshot(0.13, 38.0, 0.75, 170.0, 0.4)
	streams["shot_pistol_heavy"] = _gunshot(0.26, 18.0, 0.5, 95.0, 0.9)
	streams["shot_shotgun"] = _gunshot(0.4, 11.0, 0.3, 70.0, 1.0)
	streams["shot_sniper"] = _gunshot(0.6, 7.5, 0.35, 60.0, 1.0)
	streams["shot_sniper_heavy"] = _gunshot(0.7, 6.5, 0.3, 50.0, 1.0)
	streams["shot_suppressed"] = _gunshot(0.1, 45.0, 0.12, 200.0, 0.15)

	streams["reload"] = _clicks([0.0, 0.16, 0.34], 0.42, 1500.0)
	streams["bolt"] = _clicks([0.0, 0.12, 0.26, 0.36], 0.45, 1100.0)
	streams["empty"] = _clicks([0.0], 0.06, 2400.0)
	streams["switch"] = _clicks([0.0, 0.07], 0.14, 900.0)
	streams["hit"] = _tone(0.05, 1900.0, 1900.0, 60.0, 0.5)
	streams["headshot"] = _tone(0.16, 2600.0, 3100.0, 18.0, 0.6)
	streams["kill"] = _tone(0.22, 880.0, 1320.0, 10.0, 0.6)
	streams["hurt"] = _tone(0.14, 150.0, 70.0, 16.0, 0.9)
	streams["ui_click"] = _tone(0.04, 900.0, 700.0, 70.0, 0.4)
	streams["ui_start"] = _tone(0.35, 440.0, 880.0, 6.0, 0.5)
	streams["step"] = _gunshot(0.07, 60.0, 0.1, 90.0, 0.5)
	streams["impact"] = _gunshot(0.05, 90.0, 0.8, 400.0, 0.1)
	streams["ricochet"] = _tone(0.12, 3200.0, 1800.0, 25.0, 0.35)
	streams["death"] = _gunshot(0.25, 14.0, 0.08, 60.0, 1.0)


## Wraps float samples (-1..1) in a 16-bit mono AudioStreamWAV.
func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## Filtered noise burst + low "thump" = a gunshot-like bang.
func _gunshot(length: float, decay: float, lowpass: float, thump_hz: float,
		thump_amount: float) -> AudioStreamWAV:
	var count := int(length * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var filtered := 0.0
	var phase := 0.0
	for i in count:
		var t := float(i) / MIX_RATE
		var noise := _rng.randf_range(-1.0, 1.0)
		# One-pole low-pass: lower `lowpass` = duller, heavier sound.
		filtered += (noise - filtered) * lowpass
		var envelope := exp(-decay * t)
		# The thump drops in pitch over time like a real muzzle blast.
		phase += TAU * thump_hz * (1.0 - 0.5 * t / length) / MIX_RATE
		var thump := sin(phase) * exp(-decay * 0.6 * t) * thump_amount
		samples[i] = (filtered * envelope + thump) * 0.8
	return _to_stream(samples)


## A short sine "blip" that slides from one pitch to another.
func _tone(length: float, hz_from: float, hz_to: float, decay: float,
		volume: float) -> AudioStreamWAV:
	var count := int(length * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / MIX_RATE
		phase += TAU * lerpf(hz_from, hz_to, t / length) / MIX_RATE
		samples[i] = sin(phase) * exp(-decay * t) * volume
	return _to_stream(samples)


## Several metallic clicks at the given times (reload, bolt, switch).
func _clicks(times: Array, length: float, hz: float) -> AudioStreamWAV:
	var count := int(length * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / MIX_RATE
		var value := 0.0
		for start: float in times:
			var local := t - start
			if local >= 0.0 and local < 0.05:
				value += (sin(TAU * hz * local) * 0.6 + _rng.randf_range(-0.4, 0.4)) \
						* exp(-90.0 * local)
		samples[i] = value * 0.6
	return _to_stream(samples)
