extends Node
## Automated multiplayer test (run with Tools/tests/run_mp_test.sh): the JOINER side.
var m: TdmMatch
var f := 0
var phase := 0
var fails := 0
var hits := 0
var kills_seen := []
var t_phase := 0
var target: Combatant
var died := false
var damaged := 0
func ok(name: String, cond: bool, info = "") -> void:
	print(("JOIN PASS " if cond else "JOIN FAIL ") + name + " " + str(info))
	if not cond: fails += 1
func face(p: PlayerController, point: Vector3) -> void:
	var d := (point - p.eye_position()).normalized()
	p.rotation.y = atan2(-d.x, -d.z); p._pitch = asin(d.y); p._head.rotation.x = p._pitch
func _physics_process(_d: float) -> void:
	f += 1
	if phase == 0:
		if not FileAccess.file_exists("/tmp/sa_room.txt"): return
		if not Net.is_connected_to_relay():
			Net.open_lobby(); return
		if Net.rooms.is_empty() and f < 600: return
		ok("server list shows the host's room", Net.rooms.size() == 1, Net.rooms.keys())
		Net.join_room(FileAccess.get_file_as_string("/tmp/sa_room.txt"))
		m = load("res://scenes/match.tscn").instantiate(); add_child(m)
		phase = 1
	if m == null: return
	if phase == 1 and m.player != null and m.state == TdmMatch.MatchState.PLAYING and FileAccess.file_exists("/tmp/sa_ready.txt"):
		ok("received roster: 8 soldiers, me on team 1", m.combatants.size() == 8 and m.player.team == 1 and m.net.welcomed, [m.combatants.size(), m.player.team])
		m.player.require_mouse_capture = false
		m.player.dealt_damage.connect(func(v, a, hs, k): hits += 1)
		m.player.damaged.connect(func(a, att, hs): damaged += 1)
		m.player.died.connect(func(v, k, w, hs): died = true)
		m.kill_feed.connect(func(k, v, w, hs): kills_seen.append([k.display_name if k else "?", v.display_name]))
		m.player.global_position = Vector3(0, 0.02, 20); m.player.rotation.y = 0
		target = m.combatant_by_id(int(FileAccess.get_file_as_string("/tmp/sa_ready.txt")))
		phase = 2; t_phase = f
	elif phase == 2:
		if f - t_phase == 60:
			ok("bot puppet drawn where the host put it", target.global_position.distance_to(Vector3(0, 0.02, 8)) < 0.5, target.global_position)
			Input.action_press("fire")
		if f - t_phase > 60 and target.alive: face(m.player, target.chest_position())
		if f - t_phase > 60 and not target.alive:
			Input.action_release("fire")
			ok("hit markers came back from the host", hits >= 3, hits)
			ok("kill feed shows my kill", kills_seen.size() >= 1 and kills_seen[-1][0] == m.player.display_name, kills_seen)
			ok("ping measured", m.net.ping_ms > 50 and m.net.ping_ms < 800, m.net.ping_ms)
			phase = 3; t_phase = f
		if f - t_phase > 600:
			Input.action_release("fire"); ok("killed target", false, [target.health, hits]); phase = 3
	elif phase == 3:
		if died and m.player.alive:
			ok("host's shots hurt and killed me, then I respawned in my spawn", damaged >= 1 and absf(m.player.global_position.z) > 40, [damaged, m.player.global_position])
			phase = 4; t_phase = f
		if f - t_phase > 1200:
			ok("died and respawned", false, [died, damaged, m.player.alive]); phase = 4
	elif phase == 4:
		Input.action_press("move_left")
		if f - t_phase > 200:
			Input.action_release("move_left")
			print("JOIN FAILS=", fails); get_tree().quit(fails)
	if f > 60 * 90:
		print("JOIN TIMEOUT phase ", phase); get_tree().quit(9)
