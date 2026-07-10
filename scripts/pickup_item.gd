extends RigidBody3D
## A physics prop you can pick up, carry, and throw. The interactable trigger zone
## lives on the child Area3D and forwards here via on_interact()/get_interact_prompt().
## Physics is simulated only on the server; every peer renders it from the snapshot
## the World broadcasts each physics frame, same pattern as the player.

@export var throw_force := 9.0

var carried_by: int = -1 # peer_id, or -1 if not held

# Latest server snapshot, glided toward in _process on non-server peers
# (same smoothing pattern as the player -- see player.gd).
var _net_xform_target: Transform3D
var _has_net_state := false
const NET_SMOOTH_RATE := 18.0
const NET_SNAP_DISTANCE := 6.0


func _ready() -> void:
	add_to_group("sync_items")
	if not multiplayer.is_server():
		freeze = true


func _process(delta: float) -> void:
	if multiplayer.is_server() or not _has_net_state:
		return
	if global_position.distance_to(_net_xform_target.origin) > NET_SNAP_DISTANCE:
		global_transform = _net_xform_target
		return
	var w := 1.0 - exp(-NET_SMOOTH_RATE * delta)
	global_transform = global_transform.interpolate_with(_net_xform_target, w)


func on_interact(by: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if carried_by != -1:
		return
	carried_by = by.peer_id
	freeze = true
	linear_velocity = Vector3.ZERO
	by.carried_item_path = get_path()


func throw_from(by: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if carried_by != by.peer_id:
		return
	carried_by = -1
	freeze = false
	global_transform = by.hold_point.global_transform
	# Throw where the player is LOOKING (camera aim, pitch included), not where
	# the character model happens to be facing -- aiming a throw with the camera
	# is what feels natural in third person.
	linear_velocity = by.look_direction() * throw_force + Vector3.UP * 2.0


func get_interact_prompt() -> String:
	return "Pick Up" if carried_by == -1 else "..."


func apply_remote_state(state: Dictionary) -> void:
	_net_xform_target = state["xform"]
	_has_net_state = true
	carried_by = state["held"]
