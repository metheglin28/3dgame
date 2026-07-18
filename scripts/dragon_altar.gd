extends Node3D
## A draconite altar on the flooded arena's entrance ledge. Interacting rouses
## the water dragon and begins the raid (server-authoritative). No-op once the
## fight is underway or the dragon is slain.

func on_interact(_by: Node3D) -> void:
	if not multiplayer.is_server():
		return
	for d in get_tree().get_nodes_in_group("sync_dragon"):
		d.begin_raid()


func get_interact_prompt() -> String:
	for d in get_tree().get_nodes_in_group("sync_dragon"):
		if d.is_defeated():
			return "The water dragon is slain"
		if d.fight_live():
			return "The water dragon rages..."
	return "Rouse the Water Dragon"
