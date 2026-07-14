extends RigidBody3D
## A blue lightning bolt cast from the wizard hat. Flies straight and flat (no
## gravity), and on hitting a character delivers MODERATE knockback but a much
## LONGER ragdoll -- whatever it zaps tumbles far longer than a normal hit.
## Same networking as the bullet: server simulates + does contact detection,
## everyone renders from the projectile snapshot. The jagged bolt mesh is built
## in code (on every peer) so it needs no authored sub-resources.

const LIFETIME := 1.4
const SPEED := 27.0
const KNOCKBACK := 13.0     # sword 11, revolver 16 -- moderate, in between
const LONG_RAGDOLL := 3.2   # normal is 1.1s: zapped targets flail much longer
const BOLT_BLUE := Color(0.3, 0.6, 1.0, 1)

var shooter_id: int = -1

var _net_xform_target: Transform3D
var _has_net_state := false
const NET_SMOOTH_RATE := 22.0
const NET_SNAP_DISTANCE := 8.0


func _ready() -> void:
	add_to_group("sync_projectiles")
	_build_bolt()
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


## Server-only: orient along the shooter's aim (so the jagged bolt reads as
## flying point-first) and fire straight.
func launch_from(shooter: Node3D) -> void:
	shooter_id = shooter.peer_id
	var aim: Vector3 = shooter.look_direction()
	var origin: Vector3 = shooter.hold_point.global_position + aim * 0.6
	# Point local -Z down the aim.
	var up := Vector3.UP if absf(aim.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	look_at_from_position(origin, origin + aim, up)
	linear_velocity = aim * SPEED


func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server():
		return
	if body is CharacterBody3D and "peer_id" in body and body.peer_id == shooter_id:
		return
	if body.has_method("apply_knockback"):
		var dir := (linear_velocity * Vector3(1, 0, 1)).normalized()
		body.apply_knockback(dir, KNOCKBACK, LONG_RAGDOLL)
	queue_free()


func apply_remote_state(state: Dictionary) -> void:
	_net_xform_target = state["xform"]
	_has_net_state = true


## The visual: a jagged zig-zag of thin glowing segments along local -Z, plus a
## soft blue light so it pops in the dark.
func _build_bolt() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BOLT_BLUE
	mat.emission_enabled = true
	mat.emission = BOLT_BLUE
	mat.emission_energy_multiplier = 3.0
	# The zig-zag, as a chain of points in local space (z runs forward = -Z).
	var pts := [
		Vector3(0, 0, 0.28), Vector3(0.12, 0.04, 0.12), Vector3(-0.1, -0.03, -0.02),
		Vector3(0.11, 0.02, -0.16), Vector3(0, 0, -0.3),
	]
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.05, 0.05, a.distance_to(b))
		seg.mesh = box
		seg.material_override = mat
		seg.look_at_from_position((a + b) * 0.5, b, Vector3.UP if absf((b - a).normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT)
		add_child(seg)
	var glow := OmniLight3D.new()
	glow.light_color = BOLT_BLUE
	glow.light_energy = 2.0
	glow.omni_range = 4.0
	add_child(glow)
