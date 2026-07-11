extends Node3D
## The snowman in the snowy hills. Interacting toggles the snowball-throwing
## power on/off for whoever talks to it (see player.gd's wearing_hat/_request_throw).
## Server-authoritative like every other interaction: the client only sends the
## request, the server decides the new state and it comes back down in the
## normal per-player snapshot.

func on_interact(by: Node3D) -> void:
	if not multiplayer.is_server():
		return
	by.wearing_hat = not by.wearing_hat


func get_interact_prompt() -> String:
	return "Talk to Snowman"
