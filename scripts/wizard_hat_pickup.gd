extends Node3D

const WIZARD_HAT_VISUAL := preload("res://scripts/wizard_hat_visual.gd")
## A wizard hat sitting on the ground in the woods -- it has no permanent home
## yet. Interacting toggles the lightning-bolt power (shown as the hat on your
## head) for whoever grabs it. Server-authoritative, same mutually-exclusive
## pattern as the other power granters (snowman/sword_stone/coat_rack/chest);
## the hat's look is built in code (WizardHatVisual), shared with the worn hat.

func _ready() -> void:
	var visual := Node3D.new()
	visual.scale = Vector3(1.6, 1.6, 1.6)
	add_child(visual)
	WIZARD_HAT_VISUAL.build(visual)


func on_interact(by: Node3D) -> void:
	if not multiplayer.is_server():
		return
	by.wearing_wizard_hat = not by.wearing_wizard_hat
	if by.wearing_wizard_hat:
		by.wearing_hat = false
		by.wearing_helmet = false
		by.wearing_cowboy_hat = false
		by.wearing_bunny_ears = false


func get_interact_prompt() -> String:
	return "Take the Wizard Hat"
