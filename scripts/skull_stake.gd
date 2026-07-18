extends Node3D
## A skull mounted on a stake -- the co-op fight trigger. By default it starts
## the Goblin Siege (dungeon arena); set `starts_dragon_raid` and the same stake
## instead starts the Water Dragon raid (flooded arena). Server-authoritative;
## no-op unless we're idle in the hub (see game_director.gd).

@export var starts_dragon_raid := false

func on_interact(_by: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if starts_dragon_raid:
		GameDirector.start_dragon_raid()
	else:
		GameDirector.start_boss_fight()


func get_interact_prompt() -> String:
	if GameDirector.state != GameDirector.HUB:
		return "Fight in progress..."
	return "Wake the Water Dragon" if starts_dragon_raid else "Face the horde"
