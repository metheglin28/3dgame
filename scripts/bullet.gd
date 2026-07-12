extends RigidBody3D
## A revolver bullet: small, very fast, flies nearly flat, and RAGDOLLS
## whatever character it hits with the revolver's high knockback (harder than
## the sword). Same networking as the snowball -- server simulates, everyone
## renders from the projectile snapshot -- plus server-side contact detection:
## first thing it touches ends its flight (characters get launched, walls just
## stop it). continuous_cd is on because at this speed a discrete step could
## tunnel straight through a 1m wall.

const LIFETIME := 1.6
const MUZZLE_SPEED := 34.0
const KNOCKBACK := 16.0  # the sword is 11; getting shot means getting LAUNCHED

var shooter_id: int = -1

var _net_xform_target: Transform3D
var _has_net_state := false
const NET_SMOOTH_RATE := 22.0
const NET_SNAP_DISTANCE := 8.0


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


## Server-only: start just ahead of the shooter (clear of their own capsule)
## and fly flat along their aim.
func launch_from(shooter: Node3D) -> void:
	shooter_id = shooter.peer_id
	var aim: Vector3 = shooter.look_direction()
	global_position = shooter.hold_point.global_position + aim * 0.6
	linear_velocity = aim * MUZZLE_SPEED


func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server():
		return
	if body is CharacterBody3D and "peer_id" in body and body.peer_id == shooter_id:
		return # don't shoot yourself in the foot at the muzzle
	if body.has_method("apply_knockback"):
		var dir := (linear_velocity * Vector3(1, 0, 1)).normalized()
		body.apply_knockback(dir, KNOCKBACK)
	queue_free()


func apply_remote_state(state: Dictionary) -> void:
	_net_xform_target = state["xform"]
	_has_net_state = true
