extends "res://scripts/npc.gd"
## A goblin: a small, green, pointy-eared cave dweller with a little dagger.
## Reuses the NPC body (server-driven movement, snapshot sync, ragdoll
## knockback) but overrides the brain: while a player is INSIDE the cave, the
## nearest goblins hunt them down and stab, knocking them flying (dagger =
## a weaker knockback than the player's sword). The moment the player leaves
## the cave -- or when there's simply nobody inside -- they give up and go
## back to skulking around their own room. They never chase outside; the
## cave is theirs, the forest is your problem.
##
## Skin color is per-instance (hand-picked in world.tscn, yellowish green
## through dark moss). The material is created at runtime because a scene
## sub_resource would be shared by every goblin instance, and then they'd
## all be the same green.

const DAGGER_KNOCKBACK := 7.0   # the player's sword is 11; daggers sting less
const ATTACK_RANGE := 1.4
const ATTACK_COOLDOWN := 1.4
const CHASE_SPEED_MULT := 1.5
const AGGRO_RANGE := 14.0       # don't grind against walls chasing someone rooms away

## The cave's interior, as rough boxes (AABB position is the min corner).
## Both the prey check ("is that player in our cave?") and the leash check
## ("am I still in the cave?") run against these.
const CAVE_BOXES: Array[AABB] = [
	AABB(Vector3(40.6, -1, 41.5), Vector3(5, 6, 4.5)),   # entry tunnel
	AABB(Vector3(39, -1, 46), Vector3(7.5, 6, 4.5)),     # warren
	AABB(Vector3(41, -6, 50.5), Vector3(7.5, 11, 21.5)), # hall 1, incl. the descent
	AABB(Vector3(37.2, -6, 72), Vector3(10, 9.5, 9.5)),  # main chamber
	AABB(Vector3(37.5, -10, 81.5), Vector3(9.5, 8, 11)), # hall 2
	AABB(Vector3(36.4, -10, 92.5), Vector3(6, 8, 5.5)),  # loot room
]

## The boss dungeon arena (disc center + radius, see map_decorations DUNGEON_*).
## In arena_mode the goblin forgets the cave entirely: it hunts whoever is on the
## disc and leashes to the disc instead of the warren.
const ARENA_CENTER := Vector3(92, -16, 40)
const ARENA_RADIUS := 15.0
const ARENA_AGGRO := 40.0  # the whole disc -- no dawdling once the fight is on

@export var skin_color: Color = Color(0.38, 0.55, 0.22)
@export var arena_mode := false

@onready var dagger: Node3D = $Mesh/DaggerPivot

var _attack_cooldown := 0.0

func _ready() -> void:
	super()
	add_to_group("goblins")
	var mat := StandardMaterial3D.new()
	mat.albedo_color = skin_color
	$Mesh.material_override = mat
	$Mesh/EarL.material_override = mat
	$Mesh/EarR.material_override = mat


static func is_in_cave(p: Vector3) -> bool:
	for b in CAVE_BOXES:
		if b.has_point(p):
			return true
	return false


func _ai(delta: float) -> void:
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	var prey: Node3D
	if arena_mode:
		prey = _find_arena_prey()
	else:
		# Knocked (or wandered) out of the cave somehow? Head home first.
		if not is_in_cave(global_position):
			super(delta)
			return
		prey = _find_prey()
	if prey == null:
		super(delta)
		return
	var to := prey.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var dir := to.normalized()
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 10.0 * delta)
	if dist > ATTACK_RANGE * 0.75:
		velocity.x = dir.x * speed * CHASE_SPEED_MULT
		velocity.z = dir.z * speed * CHASE_SPEED_MULT
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	if dist <= ATTACK_RANGE and _attack_cooldown <= 0.0:
		_attack_cooldown = ATTACK_COOLDOWN
		_play_stab.rpc()
		prey.apply_knockback(dir, DAGGER_KNOCKBACK)


## Nearest player who is inside the cave and close enough to bother chasing.
func _find_prey() -> Node3D:
	var best: Node3D = null
	var best_dist := AGGRO_RANGE
	for p in get_tree().get_nodes_in_group("players"):
		if not is_in_cave(p.global_position):
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_dist:
			best_dist = d
			best = p
	return best


## Is this position on (or just over) the arena disc, and not down the pit?
static func _in_arena(p: Vector3) -> bool:
	return Vector2(p.x - ARENA_CENTER.x, p.z - ARENA_CENTER.z).length() < ARENA_RADIUS + 2.0 and p.y > -30.0


## Nearest player still up on the arena disc (fallen/spectating players, who are
## down the pit or gone, drop out of the group and this check naturally).
func _find_arena_prey() -> Node3D:
	var best: Node3D = null
	var best_dist := ARENA_AGGRO
	for p in get_tree().get_nodes_in_group("players"):
		if not _in_arena(p.global_position):
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_dist:
			best_dist = d
			best = p
	return best


## Cosmetic stab, played on every peer (reliable broadcast, same pattern as
## the player's sword swing). The dagger tips forward and snaps back.
@rpc("authority", "call_local", "reliable")
func _play_stab() -> void:
	var tween := create_tween()
	dagger.rotation.x = 0.0
	tween.tween_property(dagger, "rotation:x", 1.7, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(dagger, "rotation:x", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
