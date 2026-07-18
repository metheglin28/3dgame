extends Node3D
## Lives at the center of a water surface. Two jobs:
##
## 1. RIPPLES: spawns expanding rings under anyone wading through the water.
##    Entirely LOCAL -- every peer already renders every character from the
##    normal position snapshots, so each client detects wading motion itself
##    and draws its own rings. Identical inputs, identical-looking output,
##    nothing to network.
##
## 2. WADING ZONE: joins the "water" group and answers is_wading() so the
##    server can slow characters slogging through it (see player.gd).
##
## The node sits AT the water surface, so its own y is the waterline.

var half := 5.6  # water half-extent along X (and Z, unless half_z is set)
var half_z := 0.0  # if > 0, a separate Z half-extent (rectangular water, e.g. the flooded arena)

const RIPPLE_INTERVAL := 0.35
const MIN_WADE_SPEED := 1.0
const RIPPLE_LIFETIME := 0.9

var _cooldown := {}  # instance_id -> seconds until that body may ripple again
var _prev_pos := {}  # instance_id -> last frame's position

func _ready() -> void:
	add_to_group("water")


## Is this (feet) position standing in the water?
func is_wading(p: Vector3) -> bool:
	var hz := half_z if half_z > 0.0 else half
	return absf(p.x - global_position.x) < half - 0.3 \
		and absf(p.z - global_position.z) < hz - 0.3 \
		and p.y < global_position.y + 0.15 and p.y > global_position.y - 2.0


func _process(delta: float) -> void:
	var bodies: Array[Node] = []
	bodies.append_array(get_tree().get_nodes_in_group("players"))
	bodies.append_array(get_tree().get_nodes_in_group("npc"))
	for b in bodies:
		var id := b.get_instance_id()
		var p: Vector3 = b.global_position
		var prev: Vector3 = _prev_pos.get(id, p)
		_prev_pos[id] = p
		_cooldown[id] = _cooldown.get(id, 0.0) - delta
		if not is_wading(p):
			continue
		var speed := Vector2(p.x - prev.x, p.z - prev.z).length() / maxf(delta, 0.0001)
		if speed < MIN_WADE_SPEED or _cooldown[id] > 0.0:
			continue
		_cooldown[id] = RIPPLE_INTERVAL
		_spawn_ripple(Vector3(p.x, global_position.y + 0.03, p.z))


func _spawn_ripple(pos: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.95, 1.0, 0.5)
	ring.material_override = mat
	ring.scale = Vector3(0.5, 0.12, 0.5)
	add_child(ring)
	ring.global_position = pos
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(2.6, 0.12, 2.6), RIPPLE_LIFETIME)
	tween.tween_property(mat, "albedo_color:a", 0.0, RIPPLE_LIFETIME)
	tween.chain().tween_callback(ring.queue_free)
