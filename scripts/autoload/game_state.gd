extends Node
## Small autoload for cross-scene state that isn't network-related,
## like the mouse-capture toggle used by the interaction/menu flow.

## Floating name/speech labels fade out with distance from THIS client's own
## player, so you don't read every NPC and player name across the whole map --
## only the ones you're standing near. Purely local/cosmetic (each peer judges
## against its own player), so nothing here is networked.
const LABEL_NEAR := 7.0   # full opacity within this many meters
const LABEL_FAR := 13.0   # fully hidden beyond this

var mouse_captured: bool = false

var _local_player: Node3D = null

## This client's own player node (peer_id == our unique id), cached until it's
## freed. Null before the local player has spawned.
func local_player() -> Node3D:
	if is_instance_valid(_local_player):
		return _local_player
	_local_player = null
	var my_id := multiplayer.get_unique_id()
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == my_id:
			_local_player = p
			break
	return _local_player

## 1.0 when the local player is within LABEL_NEAR of `pos`, ramping to 0.0 at
## LABEL_FAR (and 0.0 when there's no local player yet).
func label_alpha(pos: Vector3) -> float:
	var lp := local_player()
	if lp == null:
		return 0.0
	var d := pos.distance_to(lp.global_position)
	return clampf((LABEL_FAR - d) / (LABEL_FAR - LABEL_NEAR), 0.0, 1.0)

func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse_captured = true

func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mouse_captured = false

func toggle_mouse() -> void:
	if mouse_captured:
		release_mouse()
	else:
		capture_mouse()
