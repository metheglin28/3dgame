extends "res://scripts/npc.gd"
## A stall rabbit in the barn. Reuses the NPC body for the server-driven wander
## and snapshot sync, but bunnies are PETS, not combatants or conversationalists:
## they can't be knocked back by anything, they say nothing, and they physically
## cannot leave their stall (hard position clamp on top of the tiny wander
## leash, so not even a player body squeezing past can push one out the gap).
##
## The mama (is_mama) is also the bunny-ears power granter -- interact with her
## to borrow the headband (see player.gd's wearing_bunny_ears). The babies
## aren't interactable at all. `bunny_scale` scales the VISUAL only; the
## collider stays baby-sized, which nobody will ever notice on a rabbit.

@export var bunny_scale := 1.0
@export var is_mama := false

## The bunny stall's interior (see map_decorations._build_barn), minus a small
## margin for the capsule. Wander targets already stay inside via the leash;
## this clamp is the guarantee.
const STALL_X_MIN := -48.75
const STALL_X_MAX := -46.45
const STALL_Z_MIN := 43.75
const STALL_Z_MAX := 46.25


func _ready() -> void:
	npc_name = "Bunny"
	super()
	add_to_group("bunnies")
	mesh.scale = Vector3.ONE * bunny_scale
	if not is_mama:
		# Babies aren't interactable: no prompt, no dialogue, just vibes.
		$Interactable.queue_free()


func _physics_process(delta: float) -> void:
	super(delta)
	global_position.x = clampf(global_position.x, STALL_X_MIN, STALL_X_MAX)
	global_position.z = clampf(global_position.z, STALL_Z_MIN, STALL_Z_MAX)


## Bunnies can't be hit: swords, bullets, lightning, club, and snowballs
## (shove AND slow) all no-op here.
func apply_knockback(_dir: Vector3, _power: float, _ragdoll_time: float = RAGDOLL_MIN_TIME) -> void:
	pass


func apply_shove(_dir: Vector3, _power: float) -> void:
	pass


func apply_slow(_duration: float) -> void:
	pass


## The mama hands out the bunny-ear headband (mutually exclusive with the other
## powers, same as every granter). Babies never get here -- their interact area
## is removed in _ready.
func on_interact(by: Node3D) -> void:
	if not multiplayer.is_server() or not is_mama:
		return
	by.wearing_bunny_ears = not by.wearing_bunny_ears
	if by.wearing_bunny_ears:
		by.wearing_hat = false
		by.wearing_helmet = false
		by.wearing_cowboy_hat = false
		by.wearing_wizard_hat = false
		by.wearing_golden_ears = false


func get_interact_prompt() -> String:
	return "Borrow the bunny ears"
