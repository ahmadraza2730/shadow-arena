class_name AimModifier
extends SkeletonModifier3D
## Runs after the animation each frame and points the soldier's chest
## where the fighter is aiming. Whatever the legs are doing (jogging,
## crouching, leaning), the chest is turned back to an upright "aiming"
## orientation and then tilted by the aim pitch, so the arms and weapon
## stay level and on target. Add as a child of the Skeleton3D.

## Aim pitch in radians (positive = up).
var pitch := 0.0
## 0 = leave the animation alone, 1 = fully hold the aiming orientation.
var weight := 1.0
## Index of the chest bone that is re-oriented.
var chest_bone := -1
## The chest's orientation (skeleton space) in the standing aim pose.
var chest_reference := Basis.IDENTITY


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or chest_bone < 0 or weight <= 0.001:
		return
	# The model faces +Z, so a negative rotation about +X tilts it back
	# (looking up).
	var target := Basis(Vector3.RIGHT, -pitch) * chest_reference
	var pose := skeleton.get_bone_global_pose(chest_bone)
	pose.basis = pose.basis.orthonormalized().slerp(target.orthonormalized(), clampf(weight, 0.0, 1.0))
	skeleton.set_bone_global_pose(chest_bone, pose)
