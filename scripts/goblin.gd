extends "res://scripts/npc.gd"
## A goblin: a small, green, pointy-eared cave dweller. Reuses the regular
## NPC brain wholesale (server-driven wander + snapshot sync + talk RPC) --
## for now they just skulk around their room and mouth off when bothered.
## They're tagged "goblins" so future combat mechanics can find them.
##
## Skin color is per-instance (hand-picked in world.tscn, yellowish green
## through dark moss). The material is created at runtime because a scene
## sub_resource would be shared by every goblin instance, and then they'd
## all be the same green.

const GOBLIN_LINES: Array[String] = [
	"Ssss... the shiny is OURS.",
	"You smell like soap. Disgusting.",
	"The boss says no eating visitors. Yet.",
	"I found this skull. It's my friend now.",
	"We're not short. YOU'RE just tall.",
	"Touch the gold and lose a finger. We keep the fingers.",
	"A troll's moving in soon. Then you'll be sorry.",
]

@export var skin_color: Color = Color(0.38, 0.55, 0.22)

func _ready() -> void:
	if lines.is_empty():
		lines = GOBLIN_LINES
	super()
	add_to_group("goblins")
	var mat := StandardMaterial3D.new()
	mat.albedo_color = skin_color
	$Mesh.material_override = mat
	$Mesh/EarL.material_override = mat
	$Mesh/EarR.material_override = mat


func get_interact_prompt() -> String:
	return "Bother"
