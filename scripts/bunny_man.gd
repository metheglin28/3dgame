extends "res://scripts/npc.gd"
## The Bunny Man: a mysterious moon resident. A player-sized white pill with a
## pink belly, wearing the bunny-ear headband. He wanders his little patch of
## lunar dust and, for now, says nothing (no Interactable area in his scene, so
## there's no prompt) -- his role in the easter egg hunt comes later.
##
## He can't be hit, shoved, or chilled: the moon's exit teleport plane only
## catches PLAYERS, so a knockable Bunny Man could be swatted off the disc and
## would fall to the kill plane and despawn forever. He is beyond such things.

func _ready() -> void:
	super()
	add_to_group("bunny_man")


func apply_knockback(_dir: Vector3, _power: float, _ragdoll_time: float = RAGDOLL_MIN_TIME) -> void:
	pass


func apply_shove(_dir: Vector3, _power: float) -> void:
	pass


func apply_slow(_duration: float) -> void:
	pass
