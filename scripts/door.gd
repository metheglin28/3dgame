extends Node3D
## A door that swings open/closed when you interact with its lever. Unlike the
## player/items, a door's state barely ever changes, so instead of a per-frame
## snapshot it's just a reliable RPC broadcast whenever it toggles; every peer then
## animates the same open/close tween locally and reaches the same end state.

const OPEN_ANGLE := deg_to_rad(100.0)
const SWING_SPEED := 3.0

var is_open: bool = false

@onready var pivot: Node3D = $Pivot


func on_interact(_by: Node3D) -> void:
	if not multiplayer.is_server():
		return
	_set_open.rpc(not is_open)


func get_interact_prompt() -> String:
	return "Close Door" if is_open else "Open Door"


func _process(delta: float) -> void:
	var target := OPEN_ANGLE if is_open else 0.0
	pivot.rotation.y = move_toward(pivot.rotation.y, target, SWING_SPEED * delta)


@rpc("authority", "call_local", "reliable")
func _set_open(value: bool) -> void:
	is_open = value
