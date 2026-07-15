extends "res://scripts/npc.gd"
## The Bunny Man: a mysterious moon resident. A white pill (a bit bigger than a
## player) with a pink belly and bunny ears. He wanders his little patch of
## lunar dust and, for now, says nothing -- but interacting with him grants the
## GOLDEN EARS (the bunny-ears variation with the ground-pound slam; see
## player.gd's wearing_golden_ears). His interact area lives in his scene.
##
## (When the easter egg hunt lands, the ears will be re-gated behind completing
## it; for now he hands them over so the moon trip pays off today.)
##
## He can't be hit, shoved, or chilled: the moon's exit teleport plane only
## catches PLAYERS, so a knockable Bunny Man could be swatted off the disc and
## would fall to the kill plane and despawn forever. He is beyond such things.

func _ready() -> void:
	super()
	add_to_group("bunny_man")


func on_interact(by: Node3D) -> void:
	if not multiplayer.is_server():
		return
	by.wearing_golden_ears = not by.wearing_golden_ears
	if by.wearing_golden_ears:
		by.wearing_hat = false
		by.wearing_helmet = false
		by.wearing_cowboy_hat = false
		by.wearing_bunny_ears = false
		by.wearing_wizard_hat = false


func get_interact_prompt() -> String:
	return "Borrow the golden ears"


func apply_knockback(_dir: Vector3, _power: float, _ragdoll_time: float = RAGDOLL_MIN_TIME) -> void:
	pass


func apply_shove(_dir: Vector3, _power: float) -> void:
	pass


func apply_slow(_duration: float) -> void:
	pass
