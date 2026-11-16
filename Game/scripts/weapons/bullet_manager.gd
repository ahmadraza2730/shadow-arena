class_name BulletManager
extends Node3D
## Resolves every shot in the match.
##
##  - Hitscan weapons: one instant ray out to the weapon's max range.
##  - Projectile weapons (snipers): a simulated bullet that moves each
##    physics frame at bullet_speed and falls with gravity, so long shots
##    need a little lead and hold-over.
##
## Bullets are plain dictionaries stepped in one loop (no node per bullet),
## which keeps this cheap on a low-end CPU.

const GRAVITY := 9.8
const RAY_MASK := Game.LAYER_WORLD | Game.LAYER_CHARACTER

var _bullets: Array[Dictionary] = []


func fire(shooter: Combatant, data: WeaponData, origin: Vector3, direction: Vector3) -> void:
	if data.projectile:
		_bullets.append({
			"pos": origin,
			"vel": direction * data.bullet_speed,
			"shooter": shooter,
			"data": data,
			"travelled": 0.0,
		})
		return

	var end := origin + direction * data.max_range
	var hit := _cast(origin, end, shooter)
	var tracer_from := shooter.get_muzzle_position()
	if hit.is_empty():
		Game.vfx.tracer(tracer_from, end)
	else:
		Game.vfx.tracer(tracer_from, hit["position"])
		_resolve_hit(hit, shooter, data, origin.distance_to(hit["position"]), direction)


func _physics_process(delta: float) -> void:
	var i := _bullets.size() - 1
	while i >= 0:
		var b := _bullets[i]
		var data: WeaponData = b["data"]
		var from: Vector3 = b["pos"]
		var vel: Vector3 = b["vel"]
		var to := from + vel * delta
		vel.y -= GRAVITY * data.drop_scale * delta
		var shooter: Combatant = b["shooter"]
		var finished := false

		if not is_instance_valid(shooter):
			finished = true
		else:
			var hit := _cast(from, to, shooter)
			if not hit.is_empty():
				var distance: float = b["travelled"] + from.distance_to(hit["position"])
				Game.vfx.tracer(from, hit["position"])
				_resolve_hit(hit, shooter, data, distance, vel.normalized())
				finished = true
			else:
				Game.vfx.tracer(from, to)
				b["travelled"] += from.distance_to(to)
				b["pos"] = to
				b["vel"] = vel
				if b["travelled"] > data.max_range:
					finished = true

		if finished:
			_bullets.remove_at(i)
		i -= 1


## Ray cast that ignores the shooter and passes through teammates
## (no friendly fire).
func _cast(from: Vector3, to: Vector3, shooter: Combatant) -> Dictionary:
	var exclude: Array[RID] = [shooter.get_rid()]
	var space := get_world_3d().direct_space_state
	for attempt in 6:
		var query := PhysicsRayQueryParameters3D.create(from, to, RAY_MASK, exclude)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return hit
		var collider: Object = hit["collider"]
		if collider is Combatant and (collider.team == shooter.team or not collider.alive):
			exclude.append(collider.get_rid())
			continue
		return hit
	return {}


func _resolve_hit(hit: Dictionary, shooter: Combatant, data: WeaponData,
		distance: float, direction: Vector3) -> void:
	var collider: Object = hit["collider"]
	var position: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	if collider is Combatant:
		var victim := collider as Combatant
		var headshot := victim.is_head_hit(position)
		var amount := data.damage_at(distance)
		if headshot:
			amount *= data.headshot_mult
		victim.apply_damage(amount, shooter, data, headshot)
		Game.vfx.impact("blood", position, -direction, false)
	else:
		var surface := "concrete"
		if collider.has_meta("surface"):
			surface = str(collider.get_meta("surface"))
		Game.vfx.impact(surface, position, normal, true)
