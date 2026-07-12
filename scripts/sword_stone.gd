extends Node3D
## The sword in the stone, in the forest clearing. Interacting toggles the
## sword-swinging power (shown as a knight helmet + a sword in hand) for
## whoever pulls it. Server-authoritative, same pattern as snowman.gd; the new
## state reaches every peer through the normal per-player snapshot.
##
## The displayed sword stays in the stone no matter how many players "pull"
## it -- it's a magic sword, it can be in two places at once, don't think
## about it too hard. The powers are mutually exclusive with the snowman's
## hat so a click always means exactly one thing (see player.gd).

func on_interact(by: Node3D) -> void:
	if not multiplayer.is_server():
		return
	by.wearing_helmet = not by.wearing_helmet
	if by.wearing_helmet:
		by.wearing_hat = false
		by.wearing_cowboy_hat = false


func get_interact_prompt() -> String:
	return "Pull the Sword"
