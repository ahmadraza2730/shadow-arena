class_name NetMatch
extends Node
## The online half of a match. Added to TdmMatch when Net is hosting or
## joining.
##
## HOST: every tick it records where everyone was (for lag compensation),
## and 7-10 times a second it sends a snapshot: match state, every
## soldier's position/aim/health, and events (kills, hits, welcomes). It
## turns each joiner's packets into movement for their puppet and resolves
## their shots against the world AS THE JOINER SAW IT (rewound to the time
## on their screen), so a shot that was on target for them counts.
##
## JOINER: moves its own soldier locally (instant response), sends its
## position and shots to the host, and draws everyone else from snapshots,
## shown INTERP_DELAY seconds in the past for smooth movement.

const INTERP_DELAY := 0.15          # joiner: how far in the past others are drawn
const HOST_PUPPET_DELAY := 0.12     # host: how far behind a joiner's packets their puppet is drawn
const HISTORY_TIME := 1.0
const MAX_REWIND := 0.6
const ROSTER_RESEND := 2.0
const HELLO_INTERVAL := 1.0
## Joiner: give up if the host has not let us in after this much game time.
const JOIN_TIMEOUT := 30.0

var match_ref: TdmMatch
## A new id per match, so joiners notice when the host restarts.
var match_id := ""
var welcomed := false
var ping_ms := 0.0

# --- host ---
var _send_left := 0.0
var _events: Array = []
var _event_seq := 0
var _roster_version := 0
var _roster_left := 0.0
var _history: Dictionary = {}          # net_id -> Array of [time, position, height]
var _acks: Dictionary = {}             # peer_id -> joiner's local time echo
var _rejects: Dictionary = {}          # peer_id -> consecutive rejected positions

# --- joiner ---
var _clock_offset := 0.0               # host clock - local clock
var _has_clock := false
var _last_event_seq := -1
var _roster_seen := -1
var _pending_shots: Array = []
var _hello_left := 0.0
var _local_time := 0.0
var _last_shot_frame := -1


func setup(p_match: TdmMatch) -> void:
	match_ref = p_match
	if Net.is_host():
		match_id = "%x" % (randi() & 0xffffff)
		Net.uplink_received.connect(_on_uplink)
		Net.peer_left.connect(_on_peer_left)
	else:
		Net.snapshot_received.connect(_on_snapshot)


func _physics_process(delta: float) -> void:
	_local_time += delta
	if Net.is_host():
		_record_history()
		_send_left -= delta
		_roster_left -= delta
		if _send_left <= 0.0:
			_send_left = 1.0 / Net.send_rate()
			Net.send_snapshot(_build_snapshot())
	elif Net.is_client():
		_send_left -= delta
		_hello_left -= delta
		if not welcomed:
			if _local_time > JOIN_TIMEOUT:
				Net.leave_room("Room %s not found, or the host is not responding" % Net.room_code)
				return
			if _hello_left <= 0.0:
				_hello_left = HELLO_INTERVAL
				Net.send_uplink("hello", {"name": Net.player_name(), "mid": match_id,
						"lo": _loadout_message()})
		elif _send_left <= 0.0:
			_send_left = 1.0 / Net.send_rate()
			_send_input()


## The host-clock time at which puppets should be drawn right now.
func puppet_render_time() -> float:
	if Net.is_host():
		return match_ref.clock() - HOST_PUPPET_DELAY
	return host_time() - INTERP_DELAY


## Joiner's estimate of the host's match clock.
func host_time() -> float:
	return _local_time + _clock_offset


# =================================================================== HOST
func _record_history() -> void:
	var now := match_ref.clock()
	for fighter in match_ref.combatants:
		var list: Array = _history.get(fighter.net_id, [])
		list.append([now, fighter.global_position, fighter.current_height])
		while list.size() > 2 and float(list[0][0]) < now - HISTORY_TIME:
			list.pop_front()
		_history[fighter.net_id] = list


## Moves everyone (except the shooter) back to where they were at `time`,
## runs `action`, then puts them back. Used for a joiner's hitscan shots.
func with_rewind(time: float, shooter: Combatant, action: Callable) -> void:
	var now := match_ref.clock()
	time = clampf(time, now - MAX_REWIND, now)
	var saved := []
	for fighter in match_ref.combatants:
		if fighter == shooter or not fighter.alive:
			continue
		var list: Array = _history.get(fighter.net_id, [])
		if list.is_empty():
			continue
		var past := _sample_history(list, time)
		saved.append([fighter, fighter.global_position, fighter.current_height])
		fighter.global_position = past[0]
		fighter.current_height = past[1]
		fighter._apply_height()
	action.call()
	for entry in saved:
		var fighter: Combatant = entry[0]
		fighter.global_position = entry[1]
		fighter.current_height = entry[2]
		fighter._apply_height()


func _sample_history(list: Array, time: float) -> Array:
	for i in range(list.size() - 1, -1, -1):
		if float(list[i][0]) <= time:
			var a: Array = list[i]
			var b: Array = list[mini(i + 1, list.size() - 1)]
			var span := float(b[0]) - float(a[0])
			var w := 0.0 if span <= 0.0001 else clampf((time - float(a[0])) / span, 0.0, 1.0)
			return [(a[1] as Vector3).lerp(b[1], w), lerpf(a[2], b[2], w)]
	return [list[0][1], list[0][2]]


## Host: queue an event for the next snapshot.
func add_event(event: Array) -> void:
	_event_seq += 1
	_events.append([_event_seq] + event)


func roster_changed() -> void:
	_roster_version += 1
	_roster_left = 0.0


func _build_snapshot() -> Dictionary:
	var fighters := []
	for f in match_ref.combatants:
		var shots := int(match_ref.shots_fired.get(f.net_id, 0))
		fighters.append([f.net_id, snappedf(f.global_position.x, 0.01), snappedf(f.global_position.y, 0.01),
				snappedf(f.global_position.z, 0.01), snappedf(_yaw_of(f), 0.001), snappedf(_pitch_of(f), 0.001),
				snappedf(f.current_height, 0.01), int(ceil(f.health)), 1 if f.alive else 0, f.weapon_index,
				snappedf(f.horizontal_speed(), 0.1), shots, 1 if f.is_on_floor() else 0,
				f.kills, f.deaths, f.headshots, f.life])
	var snapshot := {
		"hid": Net.my_id, "mid": match_id, "t": snappedf(match_ref.clock(), 0.001),
		"st": match_ref.state, "tl": snappedf(match_ref.time_left, 0.1),
		"cd": snappedf(match_ref.countdown_left, 0.1), "sc": match_ref.scores, "w": match_ref.winner,
		"c": fighters, "ev": _events, "rv": _roster_version, "ak": _acks,
	}
	if _roster_left <= 0.0:
		_roster_left = ROSTER_RESEND
		snapshot["ro"] = _build_roster()
	_events = []
	return snapshot


func _build_roster() -> Array:
	var roster := []
	for f in match_ref.combatants:
		var kind := 0
		var peer := ""
		if f == match_ref.player:
			kind = 1
		elif f is NetPuppet:
			kind = 2
			peer = (f as NetPuppet).peer_id
		roster.append([f.net_id, f.display_name, f.team, kind, peer,
				_weapon_message(f.weapons[0].data), _weapon_message(f.weapons[1].data)])
	return roster


func _yaw_of(f: Combatant) -> float:
	if f is NetPuppet:
		return (f as NetPuppet).aim_yaw
	return f.rotation.y


func _pitch_of(f: Combatant) -> float:
	var direction := f.get_shot_direction()
	if f is NetPuppet:
		return (f as NetPuppet).aim_pitch
	return asin(clampf(direction.y, -1.0, 1.0))


func _on_uplink(peer_id: String, event: String, data: Dictionary) -> void:
	if event == "hello":
		var puppet := match_ref.remote_for(peer_id)
		if puppet == null:
			if match_ref.state == TdmMatch.MatchState.ENDED:
				return
			var loadout := _parse_loadout(data.get("lo", {}))
			puppet = match_ref.admit_remote(peer_id, str(data.get("name", "Player")).left(16),
					loadout[0], loadout[1])
			if puppet == null:
				add_event(["x", peer_id, "Room is full"])
				return
		add_event(["w", peer_id, puppet.net_id, match_id])
		roster_changed()
		return
	if event != "u":
		return
	var puppet := match_ref.remote_for(peer_id)
	if puppet == null:
		return
	_acks[peer_id] = data.get("lt", 0.0)
	var now := match_ref.clock()
	if puppet.alive and int(data.get("lf", -1)) == puppet.life:
		var p: Array = data.get("p", [0, 0, 0])
		var position := Vector3(float(p[0]), float(p[1]), float(p[2]))
		# Sanity check: ignore an impossible jump in one packet (a glitch),
		# but resync if the joiner keeps insisting on the new position.
		var last: Vector3 = puppet._states[-1]["p"] if not puppet._states.is_empty() else position
		var rejects := int(_rejects.get(peer_id, 0))
		if last.distance_to(position) < 25.0 or rejects >= 4:
			_rejects[peer_id] = 0
			if last.distance_to(position) >= 25.0:
				puppet.snap_to(position, float(data.get("y", 0.0)))
			puppet.push_state(now, position, float(data.get("y", 0.0)), float(data.get("pi", 0.0)),
					float(data.get("h", 1.8)), float(data.get("s", 0.0)), int(data.get("f", 1)) == 1)
		else:
			_rejects[peer_id] = rejects + 1
	var wi := int(data.get("wi", 0))
	if wi != puppet.weapon_index and wi >= 0 and wi < puppet.weapons.size():
		puppet.equip(wi)
	if puppet.alive:
		for shot: Array in data.get("sh", []):
			_resolve_remote_shot(puppet, shot)


## shot = [weapon index, ox, oy, oz, dx, dy, dz, time on joiner's screen]
func _resolve_remote_shot(puppet: NetPuppet, shot: Array) -> void:
	if shot.size() < 8:
		return
	var wi := int(shot[0])
	if wi < 0 or wi >= puppet.weapons.size():
		return
	var data := puppet.weapons[wi].data
	var origin := Vector3(float(shot[1]), float(shot[2]), float(shot[3]))
	var direction := Vector3(float(shot[4]), float(shot[5]), float(shot[6])).normalized()
	# The origin must be near the puppet (no shooting from across the map).
	if origin.distance_to(puppet.eye_position()) > 3.0:
		origin = puppet.eye_position()
	if data.projectile:
		Game.bullets.fire(puppet, data, origin, direction)
	else:
		with_rewind(float(shot[7]), puppet, func() -> void:
			Game.bullets.fire(puppet, data, origin, direction))
	if shot.size() < 9 or int(shot[8]) == 1:
		puppet.shots_fired += 1
		match_ref.report_shot(puppet, data.suppressed)


func _on_peer_left(peer_id: String) -> void:
	if match_ref.remove_remote(peer_id):
		roster_changed()


# ================================================================= JOINER
func _send_input() -> void:
	var p := match_ref.player
	if p == null:
		return
	Net.send_uplink("u", {
		"lt": snappedf(_local_time, 0.001), "lf": p.life,
		"p": [snappedf(p.global_position.x, 0.01), snappedf(p.global_position.y, 0.01),
				snappedf(p.global_position.z, 0.01)],
		"y": snappedf(p.rotation.y, 0.001), "pi": snappedf(p.aim_pitch(), 0.001),
		"h": snappedf(p.current_height, 0.01), "s": snappedf(p.horizontal_speed(), 0.1),
		"f": 1 if p.is_on_floor() else 0, "wi": p.weapon_index, "sh": _pending_shots,
	})
	_pending_shots = []


## Joiner: remember a shot to send with the next packet.
## Shotgun pellets fired in the same frame are one trigger pull: only the
## first is marked, so the host plays one gunshot, not eight.
func queue_shot(weapon_index: int, origin: Vector3, direction: Vector3) -> void:
	var frame := Engine.get_physics_frames()
	var first := 1 if frame != _last_shot_frame else 0
	_last_shot_frame = frame
	_pending_shots.append([weapon_index, snappedf(origin.x, 0.01), snappedf(origin.y, 0.01),
			snappedf(origin.z, 0.01), snappedf(direction.x, 0.0001), snappedf(direction.y, 0.0001),
			snappedf(direction.z, 0.0001), snappedf(puppet_render_time(), 0.001), first])


func _on_snapshot(snap: Dictionary) -> void:
	var mid := str(snap.get("mid", ""))
	if match_id == "":
		match_id = mid
	elif mid != match_id:
		# The host started a new match: load it.
		Game.start_match()
		return
	# Clock: the snapshot time is the host's clock "now" (minus travel time).
	var sample := float(snap.get("t", 0.0)) - _local_time
	if not _has_clock or absf(sample - _clock_offset) > 0.5:
		_clock_offset = sample
		_has_clock = true
	else:
		_clock_offset = lerpf(_clock_offset, sample, 0.1)
	var acks: Dictionary = snap.get("ak", {})
	if acks.has(Net.my_id):
		ping_ms = lerpf(ping_ms, (_local_time - float(acks[Net.my_id])) * 1000.0, 0.3)

	if snap.has("ro") and int(snap.get("rv", 0)) != _roster_seen:
		_roster_seen = int(snap.get("rv", 0))
		match_ref.apply_roster(snap["ro"])
	for event: Array in snap.get("ev", []):
		if int(event[0]) <= _last_event_seq:
			continue
		_last_event_seq = int(event[0])
		_apply_event(event)
	match_ref.apply_net_state(int(snap.get("st", 0)), float(snap.get("tl", 0.0)),
			float(snap.get("cd", 0.0)), snap.get("sc", [0, 0]), int(snap.get("w", -1)))
	var time := float(snap.get("t", 0.0))
	for entry: Array in snap.get("c", []):
		match_ref.apply_fighter_state(entry, time)


func _apply_event(event: Array) -> void:
	match str(event[1]):
		"w":
			if str(event[2]) == Net.my_id:
				welcomed = true
				match_ref.my_net_id = int(event[3])
		"x":
			if str(event[2]) == Net.my_id:
				Net.leave_room(str(event[3]))
		"k":
			match_ref.apply_kill_event(int(event[2]), int(event[3]), str(event[4]), bool(event[5]))
		"h":
			match_ref.apply_hit_event(int(event[2]), int(event[3]), float(event[4]), bool(event[5]),
					bool(event[6]))


# ---------------------------------------------------------------- helpers
func _weapon_message(data: WeaponData) -> Array:
	return [data.id, data.attachments]


func _loadout_message() -> Dictionary:
	return {"p": Game.loadout["primary"], "pa": Game.get_attachments(Game.loadout["primary"]),
			"s": Game.loadout["secondary"], "sa": Game.get_attachments(Game.loadout["secondary"])}


## Turns a joiner's loadout message into weapons, falling back to defaults
## for anything invalid.
func _parse_loadout(message: Variant) -> Array:
	var data: Dictionary = message if message is Dictionary else {}
	var primary := str(data.get("p", "ar_kestrel"))
	var secondary := str(data.get("s", "pistol_wasp"))
	if not WeaponDB.weapon_ids("primary").has(primary):
		primary = "ar_kestrel"
	if not WeaponDB.weapon_ids("secondary").has(secondary):
		secondary = "pistol_wasp"
	var pa: Variant = data.get("pa", {})
	var sa: Variant = data.get("sa", {})
	return [WeaponDB.build(primary, pa if pa is Dictionary else {}),
			WeaponDB.build(secondary, sa if sa is Dictionary else {})]


static func weapon_from_message(message: Variant) -> WeaponData:
	var arr: Array = message if message is Array else []
	var id := str(arr[0]) if arr.size() > 0 else "ar_kestrel"
	if not WeaponDB.weapons().has(id):
		id = "ar_kestrel"
	var atts: Variant = arr[1] if arr.size() > 1 else {}
	return WeaponDB.build(id, atts if atts is Dictionary else {})
