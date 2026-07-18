extends Node3D
## The Level C gate: a heavy stone door with a gem-shaped indent at its base,
## hidden in an alcove behind a waterfall in the gem caverns. Carry the red gem
## here and interact to seat it in the indent -- the door grinds down into the
## floor and the descent to the flooded raid (Level C) opens. One-way and
## permanent: the gem locks into the socket for good.
##
## Server-authoritative: the server seats the gem and flips is_open; the open
## state rides the World snapshot (so late joiners see it too), and every peer
## slides the slab to match.

const SLIDE_SPEED := 2.6
const OPEN_DROP := 4.2   # how far the slab sinks when it opens

var is_open := false
var _closed_y := 0.0

@onready var slab: Node3D = $Slab
@onready var slot: Marker3D = $GemSlot


func _ready() -> void:
	add_to_group("sync_gem_door")
	_closed_y = slab.position.y


func on_interact(by: Node3D) -> void:
	if not multiplayer.is_server() or is_open:
		return
	var path: NodePath = by.carried_item_path
	if path == NodePath(""):
		return
	var item := get_node_or_null(path)
	if item == null or not item.is_in_group("cave_gem"):
		return
	# Seat the gem: lock it into the socket (carried_by -2 is an un-pickable
	# sentinel), park it in the indent, and take it out of the player's hands.
	item.carried_by = -2
	item.freeze = true
	item.global_position = slot.global_position
	by.carried_item_path = NodePath("")
	is_open = true


func get_interact_prompt() -> String:
	if is_open:
		return "The way lies open"
	return "Place the Red Gem"


func _process(delta: float) -> void:
	var target := _closed_y - OPEN_DROP if is_open else _closed_y
	slab.position.y = move_toward(slab.position.y, target, SLIDE_SPEED * delta)


func apply_remote_state(open: bool) -> void:
	is_open = open
