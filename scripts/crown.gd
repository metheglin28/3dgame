extends Node3D
## The crown on the table in the town's south house. Interacting starts a King
## of the Hill round (server-authoritative; see game_director.gd). No-op if a
## round is already running.

func on_interact(_by: Node3D) -> void:
	if not multiplayer.is_server():
		return
	GameDirector.start_round()


func get_interact_prompt() -> String:
	return "Start King of the Hill" if GameDirector.state == GameDirector.HUB else "Round in progress..."
