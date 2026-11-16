extends Node
## Automated multiplayer test (run with Tools/tests/run_mp_test.sh): the HOST side.
var m: TdmMatch
var f := 0
var phase := 0
var target: Combatant
var puppet: NetPuppet
var fails := 0
var t_phase := 0
var puppet_died := false
var puppet_respawned_moved := false
func ok(name: String, cond: bool, info = "") -> void:
	print(("HOST PASS " if cond else "HOST FAIL ") + name + " " + str(info))
	if not cond: fails += 1
func _ready() -> void:
	Net.open_lobby()
func face(p: PlayerController, point: Vector3) -> void:
	var d := (point - p.eye_position()).normalized()
	p.rotation.y = atan2(-d.x, -d.z); p._pitch = asin(d.y); p._head.rotation.x = p._pitch
func _physics_process(_d: float) -> void:
	f += 1
	if phase == 0 and Net.is_connected_to_relay():
		var code := Net.host_room()
		var fa := FileAccess.open("/tmp/sa_room.txt", FileAccess.WRITE); fa.store_string(code); fa.close()
		m = load("res://scenes/match.tscn").instantiate(); add_child(m)
		phase = 1
		print("HOST room ", code)
	if m == null: return
	if phase == 1:
		for c in m.combatants:
			if c is NetPuppet: puppet = c
		if puppet != null and m.state == TdmMatch.MatchState.PLAYING:
			ok("joiner admitted as puppet on team 1", puppet.team == 1 and m.combatants.size() == 8, [puppet.team, m.combatants.size(), puppet.display_name])
			for c in m.combatants:
				if c is BotController:
					c.set_physics_process(false); c.global_position = Vector3(50, 0.02, -50 if c.team == 1 else 50)
					if c.team == 0 and target == null: target = c
			target.global_position = Vector3(0, 0.02, 8); target.rotation.y = 0; target.health = 100; target.spawn_protection = 0
			m.player.require_mouse_capture = false; m.player.global_position = Vector3(3, 0.02, 13); m.player.spawn_protection = 0
			var fa := FileAccess.open("/tmp/sa_ready.txt", FileAccess.WRITE); fa.store_string(str(target.net_id)); fa.close()
			phase = 2; t_phase = f
	elif phase == 2:
		if not target.alive or f - t_phase > 600:
			ok("joiner's lag-compensated shots killed the bot on the host", not target.alive and m.scores[1] >= 1, [target.health, m.scores])
			phase = 3; t_phase = f
	elif phase == 3:
		# Host shoots the joiner's puppet.
		if f - t_phase == 90: Input.action_press("fire")
		if f - t_phase > 90 and puppet.alive: face(m.player, puppet.chest_position())
		if not puppet.alive and not puppet_died and m.scores[0] >= 1:
			puppet_died = true; Input.action_release("fire")
			ok("host killed the joiner", true, m.scores)
		if puppet_died and is_instance_valid(puppet) and puppet.alive:
			phase = 4; t_phase = f
		if f - t_phase > 900:
			Input.action_release("fire"); ok("host killed the joiner", false, puppet.health); phase = 5
	elif phase == 4:
		if f - t_phase == 1:
			print("HOST puppet respawned at ", puppet.global_position)
			set_meta("spawn", puppet.global_position)
		if f - t_phase == 240:
			var moved: float = puppet.global_position.distance_to(get_meta("spawn"))
			ok("joiner respawned in their own spawn and moves again (life sync)", absf(puppet.global_position.z) > 40 and moved > 1.0 and puppet.life == 2, [puppet.global_position, moved, puppet.life])
			phase = 5; t_phase = f
	elif phase == 5:
		var bots := 0
		var puppets := 0
		for c in m.combatants:
			if c is BotController: bots += 1
			if c is NetPuppet: puppets += 1
		if puppets == 0 or f - t_phase > 900:
			ok("joiner left: a bot took their slot", puppets == 0 and bots == 7 and m.combatants.size() == 8 and Net.peers.is_empty(), [bots, puppets, Net.peers])
			print("HOST FAILS=", fails)
			get_tree().quit(fails)
	if f > 60 * 90:
		print("HOST TIMEOUT phase ", phase); get_tree().quit(9)
