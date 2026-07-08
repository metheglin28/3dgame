extends RigidBody3D
## A physics prop you can pick up, carry, and throw. The interactable trigger zone
## lives on the child Area3D and forwards here via on_interact()/get_interact_prompt().
## Physics is simulated only on the server; every peer renders it from the snapshot
## the World broadcasts each physics frame, same pattern as the player.

@export var throw_force := 9.0

var carried_by: int = -1 # peer_id, or -1 if not held


func _ready() -> void:
	add_to_group("sync_items")
	if not multiplayer.is_server():
		freeze = true


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
	var forward := -by.global_transform.basis.z
	linear_velocity = forward * throw_force + Vector3.UP * 2.0


func get_interact_prompt() -> String:
	return "Pick Up" if carried_by == -1 else "..."


func apply_remote_state(state: Dictionary) -> void:
	global_transform = state["xform"]
	carried_by = state["held"]
