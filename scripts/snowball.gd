extends RigidBody3D
## A thrown snowball. Same server-authoritative physics/snapshot pattern as
## pickup_item.gd, but it's spawned dynamically (via world.gd's projectile
## MultiplayerSpawner) instead of living in a scene file, and it deletes itself
## after a few seconds so thrown snowballs don't pile up forever.

const LIFETIME := 4.0
const THROW_SPEED := 16.0

var thrower_id: int = -1

var _net_xform_target: Transform3D
var _has_net_state := false
const NET_SMOOTH_RATE := 18.0
const NET_SNAP_DISTANCE := 6.0


func _ready() -> void:
	add_to_group("sync_projectiles")
	if not multiplayer.is_server():
		freeze = true
		return
	get_tree().create_timer(LIFETIME).timeout.connect(func(): queue_free())


func _process(delta: float) -> void:
	if multiplayer.is_server() or not _has_net_state:
		return
	if global_position.distance_to(_net_xform_target.origin) > NET_SNAP_DISTANCE:
		global_transform = _net_xform_target
		return
	var w := 1.0 - exp(-NET_SMOOTH_RATE * delta)
	global_transform = global_transform.interpolate_with(_net_xform_target, w)


## Server-only: place the ball at the thrower's hold point and launch it along
## their look direction, same aiming feel as throw_from() in pickup_item.gd.
func launch_from(thrower: Node3D) -> void:
	thrower_id = thrower.peer_id
	global_transform = thrower.hold_point.global_transform
	linear_velocity = thrower.look_direction() * THROW_SPEED + Vector3.UP * 2.0


func apply_remote_state(state: Dictionary) -> void:
	_net_xform_target = state["xform"]
	_has_net_state = true
