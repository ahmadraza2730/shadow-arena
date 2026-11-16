class_name NetPuppet
extends Combatant
## A soldier controlled over the network instead of by input or AI.
##
##  - On the HOST it stands for a joining player: their position, aim and
##    weapon come from that player's packets. It is a normal Combatant, so
##    bots see it and bullets hit it; damage is decided on the host.
##  - On a JOINER it stands for everyone else (the host, other joiners and
##    all bots), drawn from the host's snapshots.
##
## Positions are buffered and shown slightly in the past, interpolating
## between the two packets around that time, so movement stays smooth even
## though updates only arrive 7-10 times a second.

const BUFFER_TIME := 1.0
const MAX_REMOTE_SHOTS_PER_UPDATE := 3

## Joiner's id on the host side ("" for puppets on a joiner's machine).
var peer_id := ""
var aim_yaw := 0.0
var aim_pitch := 0.0
## Shots fired so far, as counted by the host (drives remote gun effects).
var shots_fired := 0

var _states: Array[Dictionary] = []
var _shots_shown := 0
var _move_speed := 0.0
var _on_floor := true


func _ready() -> void:
	super()
	floor_snap_length = 0.0


## Adds a movement sample. `time` is on the host's match clock.
func push_state(time: float, position: Vector3, yaw: float, pitch: float, height: float,
		speed: float, on_floor: bool) -> void:
	_states.append({"t": time, "p": position, "y": yaw, "pi": pitch, "h": height,
			"s": speed, "f": on_floor})
	while _states.size() > 2 and float(_states[0]["t"]) < time - BUFFER_TIME:
		_states.pop_front()


## Respawning forgets the old movement samples, or the puppet would be
## pulled back to where it died.
func respawn(spawn: Transform3D) -> void:
	super(spawn)
	_states.clear()
	aim_yaw = rotation.y


## Teleports (respawn) and forgets older samples.
func snap_to(position: Vector3, yaw: float) -> void:
	_states.clear()
	global_position = position
	rotation.y = yaw
	aim_yaw = yaw


func get_shot_direction() -> Vector3:
	return Vector3(-sin(aim_yaw) * cos(aim_pitch), sin(aim_pitch), -cos(aim_yaw) * cos(aim_pitch))


func _physics_process(delta: float) -> void:
	if Net.is_host():
		update_common(delta)        # regen, spawn protection, ADS blend
	if Game.match_node == null or Game.match_node.net == null:
		return
	if alive:
		_sample(Game.match_node.net.puppet_render_time())
	# Remote gunfire: play up to a few shots per update for effects.
	if shots_fired > _shots_shown:
		var count := mini(shots_fired - _shots_shown, MAX_REMOTE_SHOTS_PER_UPDATE)
		_shots_shown = shots_fired
		for i in count:
			_play_shot_effects()
	visual.animate(delta, _move_speed if alive else 0.0, current_height, aim_pitch, _on_floor)


func _sample(render_time: float) -> void:
	if _states.is_empty():
		return
	var a: Dictionary = _states[0]
	var b: Dictionary = _states[0]
	for i in range(_states.size() - 1, -1, -1):
		if float(_states[i]["t"]) <= render_time:
			a = _states[i]
			b = _states[mini(i + 1, _states.size() - 1)]
			break
	var span := float(b["t"]) - float(a["t"])
	var w := 0.0 if span <= 0.0001 else clampf((render_time - float(a["t"])) / span, 0.0, 1.0)
	var target: Vector3 = (a["p"] as Vector3).lerp(b["p"], w)
	# Large jumps (respawn, teleport) snap instead of sliding across the map.
	if global_position.distance_to(target) > 6.0:
		global_position = target
	else:
		global_position = target
	aim_yaw = lerp_angle(float(a["y"]), float(b["y"]), w)
	aim_pitch = lerpf(float(a["pi"]), float(b["pi"]), w)
	rotation.y = aim_yaw
	var height := lerpf(float(a["h"]), float(b["h"]), w)
	if not is_equal_approx(height, current_height):
		current_height = height
		_apply_height()
	_move_speed = lerpf(float(a["s"]), float(b["s"]), w)
	_on_floor = bool(b["f"])
	is_crouching = current_height < 1.5


## Sound, muzzle flash and a tracer for a shot fired by this soldier.
func _play_shot_effects() -> void:
	if weapons.is_empty() or Game.vfx == null:
		return
	var data := current_weapon().data
	var muzzle := get_muzzle_position()
	var aim := get_shot_direction()
	if data.suppressed:
		Sfx.play("shot_suppressed", muzzle, -4.0, randf_range(0.95, 1.05))
	else:
		Sfx.play(data.sound, muzzle, 0.0, randf_range(0.96, 1.04))
		Game.vfx.muzzle_flash(muzzle, aim)
	var end := eye_position() + aim * minf(data.max_range, 120.0)
	var query := PhysicsRayQueryParameters3D.create(eye_position(), end,
			Game.LAYER_WORLD | Game.LAYER_CHARACTER, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	Game.vfx.tracer(muzzle, hit["position"] if not hit.is_empty() else end)
