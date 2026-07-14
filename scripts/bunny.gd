extends "res://scripts/npc.gd"
## A stall rabbit in the barn. Reuses the whole NPC body (server-driven wander,
## snapshot sync, ragdoll knockback, speech bubbles) with a tiny leash so it
## hops around its own stall. `bunny_scale` scales the VISUAL only (mama is
## bigger than the babies); the collider stays baby-sized, which nobody will
## ever notice on a rabbit.

@export var bunny_scale := 1.0

const BUNNY_LINES: Array[String] = [
	"Squeak!",
	"*wiggles nose*",
	"*flops over*",
	"The bunny regards you with total indifference.",
	"Munch munch.",
	"*thump*",
]


func _ready() -> void:
	npc_name = "Bunny"
	if lines.is_empty():
		lines = BUNNY_LINES
	super()
	add_to_group("bunnies")
	mesh.scale = Vector3.ONE * bunny_scale


func get_interact_prompt() -> String:
	return "Pet the bunny"
