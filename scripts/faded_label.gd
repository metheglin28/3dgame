extends Label3D
## A world-space text label that fades in only when this client's own player
## is near (see GameState.label_alpha) -- used for signposts and other named
## static objects, so their text doesn't read across the whole map. Purely
## local/cosmetic, same rule as the NPC and player name tags.

func _process(_delta: float) -> void:
	modulate.a = GameState.label_alpha(global_position)
