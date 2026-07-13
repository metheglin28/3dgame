extends Node3D
## The goblin cave's treasure chest -- the reward at the end of the line.
## Interacting dons a bunny-ear headband that grants the high-jump / bounce
## power (see player.gd's wearing_bunny_ears). The chest's own look lives in
## map_decorations.gd and is left untouched; this is just the invisible
## interact volume sitting over it. Server-authoritative, mutually exclusive
## with the other three powers, same pattern as snowman/sword_stone/coat_rack.

func on_interact(by: Node3D) -> void:
	if not multiplayer.is_server():
		return
	by.wearing_bunny_ears = not by.wearing_bunny_ears
	if by.wearing_bunny_ears:
		by.wearing_hat = false
		by.wearing_helmet = false
		by.wearing_cowboy_hat = false


func get_interact_prompt() -> String:
	return "Open Chest"
