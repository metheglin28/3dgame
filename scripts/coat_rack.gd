extends Node3D
## A coat rack, inexplicably deep in the canyon maze, with a cowboy hat on
## it. Interacting toggles the revolver power (shown as the hat + a revolver
## at the hip) for whoever grabs it. Server-authoritative, same pattern as
## snowman.gd and sword_stone.gd; the new state reaches every peer through
## the normal per-player snapshot.
##
## Like the sword's displayed copy, the hat stays on the rack no matter how
## many players "take" it -- clearly whoever left it here had spares. All
## three powers are mutually exclusive so a click always means one thing.

func on_interact(by: Node3D) -> void:
	if not multiplayer.is_server():
		return
	by.wearing_cowboy_hat = not by.wearing_cowboy_hat
	if by.wearing_cowboy_hat:
		by.wearing_hat = false
		by.wearing_helmet = false


func get_interact_prompt() -> String:
	return "Take the Hat"
