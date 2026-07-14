extends RigidBody3D
## A thrown snowball -- a proper projectile now, not just a physics prop. It
## still LOBS (full throw arc, reduced gravity so it's aimable at range), and it
## POPS on the first thing it touches: characters take a troll-style SHOVE
## (knockback with no ragdoll) plus a SLOW (see apply_slow in player.gd/npc.gd,
## and the frost-blue tint that rides the snapshot), walls and floors just get
## the puff. Same server-authoritative networking as the bullet/lightning:
## the server simulates and detects contacts, everyone renders from the
## projectile snapshot, and the impact puff is broadcast so every peer sees it.

const LIFETIME := 4.0
const THROW_SPEED := 20.0
const KNOCKBACK := 13.0     # same punch as the wizard's lightning...
# ...but a shove, not a ragdoll -- and the target is chilled on top.
const SLOW_DURATION := 2.5

var thrower_id: int = -1

# Direction of travel, sampled every physics frame BEFORE the physics step --
# body_entered fires after the collision is resolved, by which time
# linear_velocity has bounced/slid and can point anywhere (see lightning.gd).
var _travel: Vector3 = Vector3.ZERO

var _net_xform_target: Transform3D
var _has_net_state := false
const NET_SMOOTH_RATE := 18.0
const NET_SNAP_DISTANCE := 6.0


func _ready() -> void:
	add_to_group("sync_projectiles")
	if not multiplayer.is_server():
		freeze = true
		return
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(LIFETIME).timeout.connect(func(): if is_instance_valid(self): queue_free())


func _process(delta: float) -> void:
	if multiplayer.is_server() or not _has_net_state:
		return
	if global_position.distance_to(_net_xform_target.origin) > NET_SNAP_DISTANCE:
		global_transform = _net_xform_target
		return
	var w := 1.0 - exp(-NET_SMOOTH_RATE * delta)
	global_transform = global_transform.interpolate_with(_net_xform_target, w)


func _physics_process(_delta: float) -> void:
	if multiplayer.is_server() and linear_velocity.length_squared() > 1.0:
		_travel = linear_velocity


## Server-only: place the ball at the thrower's hold point and launch it along
## their look direction, same aiming feel as throw_from() in pickup_item.gd.
func launch_from(thrower: Node3D) -> void:
	thrower_id = thrower.peer_id
	global_transform = thrower.hold_point.global_transform
	linear_velocity = thrower.look_direction() * THROW_SPEED + Vector3.UP * 2.0
	_travel = linear_velocity


func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server():
		return
	if body is CharacterBody3D and "peer_id" in body and body.peer_id == thrower_id:
		return # don't pop on your own mitten at the muzzle
	if body.has_method("apply_shove"):
		var dir := (_travel * Vector3(1, 0, 1)).normalized()
		if not dir.is_finite() or dir.length_squared() < 0.5:
			dir = ((body.global_position - global_position) * Vector3(1, 0, 1)).normalized()
		body.apply_shove(dir, KNOCKBACK)
	if body.has_method("apply_slow"):
		body.apply_slow(SLOW_DURATION)
	_pop.rpc(global_position)
	queue_free()


func apply_remote_state(state: Dictionary) -> void:
	_net_xform_target = state["xform"]
	_has_net_state = true


## The impact puff, played on every peer: a handful of little snow flecks that
## burst outward and shrink away. Parented to the scene root because this
## snowball node is about to be freed.
@rpc("authority", "call_local", "reliable")
func _pop(at: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var root := Node3D.new()
	scene.add_child(root)
	root.global_position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.96, 0.97, 1.0)
	for k in range(6):
		var fleck := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.07
		s.height = 0.14
		fleck.mesh = s
		fleck.material_override = mat
		root.add_child(fleck)
		var a := TAU * float(k) / 6.0
		var out := Vector3(cos(a) * 0.5, 0.45 + 0.25 * float(k % 2), sin(a) * 0.5)
		var tween := root.create_tween()
		tween.tween_property(fleck, "position", out, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(fleck, "scale", Vector3(0.05, 0.05, 0.05), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	get_tree().create_timer(0.4).timeout.connect(func(): if is_instance_valid(root): root.queue_free())
