class_name TdmMatch
extends Node3D
## Team Deathmatch rules and the root of a running match.
##
##  - 4 v 4: the player plus 3 bots against 4 bots.
##  - First team to KILL_LIMIT kills wins, or the leader when time runs out.
##  - The dead respawn after RESPAWN_DELAY at the safest spawn point:
##    far from enemies and out of their sight.
##
## This node also builds the world (map, sky, navigation), owns the bullet
## and effects systems, and is the bots' shared "blackboard" (who was seen
## where, who heard what).

signal kill_feed(killer: Combatant, victim: Combatant, weapon: WeaponData, headshot: bool)
signal score_changed
signal state_changed(new_state: int)

enum MatchState { LOADING, COUNTDOWN, PLAYING, ENDED }

const MAP_SCENE := "res://scenes/maps/arena.tscn"
const TEAM_SIZE := 4
const KILL_LIMIT := 40
const TIME_LIMIT := 600.0
const RESPAWN_DELAY := 1.5
const COUNTDOWN_TIME := 3.0
const INTEL_LIFETIME := 6.0
## Bots do not walk past this |z| on the enemy side (spawn wall is at 42).
const SPAWN_LINE := 39.0
const BOT_NAMES: Array[String] = [
	"Bilal", "Hamza", "Usman", "Zain", "Saad", "Faizan", "Haris", "Danish", "Taimoor", "Rehan",
]

var state: MatchState = MatchState.LOADING
var scores: Array[int] = [0, 0]
var time_left := TIME_LIMIT
var countdown_left := COUNTDOWN_TIME
## -1 = draw, otherwise the winning team index. Valid once ENDED.
var winner := -1

var combatants: Array[Combatant] = []
var player: PlayerController
var cover_points: Array[Vector3] = []
var hotspots: Array[Vector3] = []

var _teams: Array = [[], []]
var _spawns: Array = [[], []]            # per team: Array[Transform3D]
var _sniper_spots: Array = [[], []]      # per team: Array[Vector3]
var _respawn_queue: Array[Dictionary] = []
var _intel: Array = [{}, {}]             # per team: enemy id -> {"pos", "time"}
var _clock := 0.0
var _environment: ArenaEnvironment
var _hud: Hud
var _nav_region: NavigationRegion3D


func _ready() -> void:
	Game.match_node = self
	var bullets := BulletManager.new()
	add_child(bullets)
	Game.bullets = bullets
	var vfx := Vfx.new()
	add_child(vfx)
	Game.vfx = vfx

	var map: Node3D = (load(MAP_SCENE) as PackedScene).instantiate()
	add_child(map)
	_read_map_markers(map)

	_environment = ArenaEnvironment.new()
	add_child(_environment)
	var preset := int(Game.settings["time_of_day"])
	if preset >= ArenaEnvironment.PRESETS.size():
		preset = randi() % ArenaEnvironment.PRESETS.size()
	_environment.build(preset)

	_spawn_everyone()
	_hud = Hud.new()
	add_child(_hud)
	_hud.setup(self, player)

	# Let one frame draw (so the loading text shows) before the bake.
	await get_tree().process_frame
	_bake_navigation(map)
	await get_tree().physics_frame
	await get_tree().physics_frame

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_state(MatchState.COUNTDOWN)
	Sfx.play("ui_start")


func _exit_tree() -> void:
	if Game.match_node == self:
		Game.match_node = null
		Game.bullets = null
		Game.vfx = null


func is_playing() -> bool:
	return state == MatchState.PLAYING


# ------------------------------------------------------------------ setup
func _read_map_markers(map: Node3D) -> void:
	_nav_region = map.get_node("Navigation") as NavigationRegion3D
	for team in 2:
		for marker: Node3D in get_tree().get_nodes_in_group("spawn_team_%d" % team):
			_spawns[team].append(marker.global_transform)
		for marker: Node3D in get_tree().get_nodes_in_group("sniper_spot_%d" % team):
			_sniper_spots[team].append(marker.global_position)
	var markers := map.get_node("Markers")
	for point: Vector3 in markers.get_meta("cover_points", PackedVector3Array()):
		cover_points.append(point)
	for point: Vector3 in markers.get_meta("hotspots", PackedVector3Array()):
		hotspots.append(point)


## Builds the walkable-area mesh the bots path-find on, from the map's
## collision boxes. Done at load so it always matches the current map.
func _bake_navigation(_map: Node3D) -> void:
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = Game.LAYER_WORLD
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	mesh.agent_radius = 0.5
	mesh.agent_height = 1.75
	mesh.agent_max_climb = 0.25
	mesh.agent_max_slope = 40.0
	# Parse the map's collision boxes and bake synchronously through the
	# server, then hand the finished mesh to the region.
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, _nav_region)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	_nav_region.navigation_mesh = mesh


func _spawn_everyone() -> void:
	var names := BOT_NAMES.duplicate()
	names.shuffle()
	var difficulty := int(Game.settings["difficulty"])

	player = PlayerController.new()
	add_child(player)
	player.setup(0, "You", Game.build_loadout_weapon("primary"), Game.build_loadout_weapon("secondary"))
	_register(player)

	for team in 2:
		while (_teams[team] as Array).size() < TEAM_SIZE:
			var bot := BotController.new()
			add_child(bot)
			bot.setup(team, names.pop_back(), _random_weapon("primary"), _random_weapon("secondary"))
			bot.setup_bot(self, difficulty)
			_register(bot)

	for fighter in combatants:
		fighter.respawn(_choose_spawn(fighter.team))


func _register(fighter: Combatant) -> void:
	combatants.append(fighter)
	(_teams[fighter.team] as Array).append(fighter)
	fighter.died.connect(_on_combatant_died)


## A random weapon with random attachments, for bots.
func _random_weapon(slot: String) -> WeaponData:
	var ids := WeaponDB.weapon_ids(slot)
	var id: String = ids.pick_random()
	var chosen := {}
	for attach_slot: String in ["scope", "grip", "muzzle", "magazine"]:
		var options := WeaponDB.attachments_for(id, attach_slot)
		if not options.is_empty() and randf() < 0.6:
			chosen[attach_slot] = options.pick_random()["id"]
	return WeaponDB.build(id, chosen)


# ------------------------------------------------------------- match flow
func _process(delta: float) -> void:
	if player and _environment:
		_environment.follow(player.global_position)


func _physics_process(delta: float) -> void:
	_clock += delta
	match state:
		MatchState.COUNTDOWN:
			countdown_left -= delta
			if countdown_left <= 0.0:
				_set_state(MatchState.PLAYING)
		MatchState.PLAYING:
			time_left -= delta
			_process_respawns()
			if time_left <= 0.0:
				time_left = 0.0
				_end_match()


func _set_state(new_state: MatchState) -> void:
	state = new_state
	state_changed.emit(state)


func _on_combatant_died(victim: Combatant, killer: Combatant, weapon: WeaponData,
		headshot: bool) -> void:
	if state != MatchState.PLAYING:
		return
	if killer and killer.team != victim.team:
		scores[killer.team] += 1
		score_changed.emit()
	kill_feed.emit(killer, victim, weapon, headshot)
	_respawn_queue.append({"who": victim, "time": _clock + RESPAWN_DELAY})
	(_intel[1 - victim.team] as Dictionary).erase(victim.get_instance_id())
	if scores[0] >= KILL_LIMIT or scores[1] >= KILL_LIMIT:
		_end_match()


func _process_respawns() -> void:
	var i := _respawn_queue.size() - 1
	while i >= 0:
		var entry := _respawn_queue[i]
		if _clock >= float(entry["time"]):
			var fighter: Combatant = entry["who"]
			if fighter == player:
				# Pick up any loadout change made while dead or paused.
				player.set_weapons(Game.build_loadout_weapon("primary"),
						Game.build_loadout_weapon("secondary"))
			fighter.respawn(_choose_spawn(fighter.team))
			_respawn_queue.remove_at(i)
		i -= 1


## Seconds until the player respawns (0 if alive or not queued).
func player_respawn_in() -> float:
	for entry in _respawn_queue:
		if entry["who"] == player:
			return maxf(float(entry["time"]) - _clock, 0.0)
	return 0.0


func _end_match() -> void:
	if state == MatchState.ENDED:
		return
	if scores[0] == scores[1]:
		winner = -1
	else:
		winner = 0 if scores[0] > scores[1] else 1
	player.controls_enabled = false
	_set_state(MatchState.ENDED)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play("kill")


# ----------------------------------------------------------------- spawns
## Picks the safest spawn point for a team: far from living enemies and
## not in their line of sight. Never spawns a soldier next to an enemy.
func _choose_spawn(team: int) -> Transform3D:
	var space := get_world_3d().direct_space_state
	var best: Transform3D = _spawns[team][0]
	var best_score := -INF
	for spawn: Transform3D in _spawns[team]:
		var point := spawn.origin
		var nearest_enemy := 60.0
		var seen := false
		for enemy: Combatant in enemies_of(team):
			if not enemy.alive:
				continue
			var distance := point.distance_to(enemy.global_position)
			nearest_enemy = minf(nearest_enemy, distance)
			if not seen and distance < 70.0:
				var query := PhysicsRayQueryParameters3D.create(
						point + Vector3.UP * 1.6, enemy.eye_position(), Game.LAYER_WORLD)
				seen = space.intersect_ray(query).is_empty()
		var score := nearest_enemy
		if seen:
			score -= 100.0
		if nearest_enemy < 12.0:
			score -= 200.0
		# Do not stack on a team-mate who has just spawned here.
		for mate: Combatant in _teams[team]:
			if mate.alive and mate.global_position.distance_to(point) < 2.0:
				score -= 40.0
		score += randf() * 4.0
		if score > best_score:
			best_score = score
			best = spawn
	return best


# ----------------------------------------------- blackboard for the bots
func enemies_of(team: int) -> Array:
	return _teams[1 - team]


## A bot saw an enemy: remember where, for the whole team.
func report_enemy(team: int, enemy: Combatant) -> void:
	(_intel[team] as Dictionary)[enemy.get_instance_id()] = {
		"pos": enemy.global_position, "time": _clock}


## The closest fresh enemy sighting known to a team, or null.
func nearest_intel(team: int, from: Vector3) -> Variant:
	var best: Variant = null
	var best_distance := 45.0
	for entry: Dictionary in (_intel[team] as Dictionary).values():
		if _clock - float(entry["time"]) > INTEL_LIFETIME:
			continue
		var distance := from.distance_to(entry["pos"])
		if distance < best_distance:
			best_distance = distance
			best = entry["pos"]
	return best


## Gunfire alerts enemy bots within earshot (much less if suppressed).
func report_shot(shooter: Combatant, suppressed: bool) -> void:
	var radius := 12.0 if suppressed else 45.0
	for enemy: Combatant in _teams[1 - shooter.team]:
		if enemy is BotController and enemy.alive \
				and enemy.global_position.distance_to(shooter.global_position) < radius:
			(enemy as BotController).hear(shooter.global_position)


## An objective for a roaming bot. Flankers prefer the side lanes, and
## everyone prefers points on the enemy's half of the map.
func random_hotspot(team: int, role: String) -> Vector3:
	if hotspots.is_empty():
		return Vector3.ZERO
	var enemy_side := -1.0 if team == 0 else 1.0      # team 0 attacks towards -Z
	var best := hotspots[0]
	var best_score := -INF
	for point in hotspots:
		var score := randf() * 10.0
		if point.z * enemy_side > -5.0:
			score += 4.0
		var on_flank := absf(point.x) > 20.0
		if (role == "flank") == on_flank:
			score += 3.0
		if score > best_score:
			best_score = score
			best = point
	return best


func random_sniper_spot(team: int) -> Vector3:
	var spots: Array = _sniper_spots[team]
	if spots.is_empty():
		return random_hotspot(team, "assault")
	return spots.pick_random()


## The yaw that faces the enemy's side of the map from `from`.
func watch_yaw(team: int, from: Vector3) -> float:
	var enemy_base := Vector3(0.0, 0.0, -30.0 if team == 0 else 30.0)
	var offset := enemy_base - from
	return atan2(-offset.x, -offset.z)


## Clamps a destination so bots stop short of the enemy spawn wall.
func keep_out_of_enemy_spawn(team: int, point: Vector3) -> Vector3:
	if team == 0:
		point.z = maxf(point.z, -SPAWN_LINE)
	else:
		point.z = minf(point.z, SPAWN_LINE)
	return point


## Fighters sorted by kills (then fewest deaths) for the scoreboard.
func team_roster(team: int) -> Array:
	var roster: Array = (_teams[team] as Array).duplicate()
	roster.sort_custom(func(a: Combatant, b: Combatant) -> bool:
		return a.kills > b.kills or (a.kills == b.kills and a.deaths < b.deaths))
	return roster
