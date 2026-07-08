class_name Interactable
extends Area3D
## Base class for anything a player can walk up to and press E on.
## Put objects that should be interactable in the "interactable" group
## (this base already adds itself) and override `interact()` and `get_prompt()`.

@export var prompt_text: String = "Interact"

func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 0
	collision_mask = 0
	set_collision_layer_value(3, true) # "interactable" physics layer

## Called on the server when a player interacts with this object.
## `by` is the Player node that triggered it. Objects whose logic naturally lives on
## a different root node (e.g. a RigidBody3D prop) can leave this Area3D as a plain
## child trigger; interact()/get_prompt() then forward to the parent's
## on_interact()/get_interact_prompt() if it defines them, otherwise this class
## handles it directly (see Door/NPC which extend Interactable themselves instead).
func interact(by: Node3D) -> void:
	var parent := get_parent()
	if parent and parent.has_method("on_interact"):
		parent.on_interact(by)


## Text shown in the on-screen prompt while the player is looking at this object.
func get_prompt() -> String:
	var parent := get_parent()
	if parent and parent.has_method("get_interact_prompt"):
		return parent.get_interact_prompt()
	return prompt_text
