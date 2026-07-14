extends Node3D
## A goblin skull mounted on a stake, planted just past the arena entrance.
## Interacting kicks off the co-op Goblin Siege (server-authoritative; see
## game_director.gd). No-op if a round is already running.

func on_interact(_by: Node3D) -> void:
	if not multiplayer.is_server():
		return
	GameDirector.start_boss_fight()


func get_interact_prompt() -> String:
	return "Face the horde" if GameDirector.state == GameDirector.HUB else "Fight in progress..."
