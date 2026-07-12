extends "res://scripts/npc.gd"
## A goblin: a small, green, pointy-eared cave dweller. Reuses the regular
## NPC brain (server-driven wander, snapshot sync, ragdoll knockback) via
## npc.gd, but unlike villagers they're enemies: no name tag over the head,
## no talk prompt, no dialogue -- they just skulk around their room and get
## ragdolled when hit. Tagged "goblins" so combat mechanics can find them.
##
## Skin color is per-instance (hand-picked in world.tscn, yellowish green
## through dark moss). The material is created at runtime because a scene
## sub_resource would be shared by every goblin instance, and then they'd
## all be the same green.

@export var skin_color: Color = Color(0.38, 0.55, 0.22)

func _ready() -> void:
	super()
	add_to_group("goblins")
	var mat := StandardMaterial3D.new()
	mat.albedo_color = skin_color
	$Mesh.material_override = mat
	$Mesh/EarL.material_override = mat
	$Mesh/EarR.material_override = mat
