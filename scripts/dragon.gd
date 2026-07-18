extends Node3D
## The water dragon -- a serpent modelled after Ryujin and Glaurung that
## endlessly ARCS between the flooded arena's deep pools: erupting from one,
## sailing over the water, and plunging into the next (the underwater
## crawlspace between pools is lore -- the head just briefly dips below the
## dim surface at each end of an arc and re-emerges at the next pool).
##
## Server-authoritative like everything else: only the server runs the arc
## simulation; every peer renders the body by trailing its many segments along
## the head's recent path (arc-length sampled, so the serpent keeps an even
## length no matter how fast the head is moving). The World folds the head's
## transform into its per-frame snapshot; clients feed that to the same trail.
##
## Stage 2 is motion only -- no surfacing-to-be-struck, no damage. That combat
## loop (and the weak point on top of the head) lands in Stage 3.

# Configured by map_decorations before the node enters the tree.
var pools: Array = []          # Array[Vector2], world XZ of each deep pool
var water_y := -39.65          # the waterline (arc ends dip just below this)
var deep_y := -49.0            # how deep the head sinks at each arc end
var apex_y := -24.0            # arc peak height

const TOUR: Array[int] = [0, 3, 1, 2]  # pool visiting order -- long criss-cross arcs
const HOP_SPEED := 9.0         # target horizontal m/s; hop duration scales with span
const HOP_MIN_DUR := 1.6

const SEG_COUNT := 18
const SEG_GAP := 1.05          # metres between segments along the body
const HEAD_R := 1.35

const BODY_COL := Color(0.13, 0.42, 0.34)
const BELLY_COL := Color(0.55, 0.75, 0.62)
const HEAD_COL := Color(0.10, 0.34, 0.30)
const FIN_COL := Color(0.20, 0.58, 0.55)
const HORN_COL := Color(0.86, 0.84, 0.72)
const EYE_COL := Color(1.0, 0.75, 0.2)

var head_root: Node3D
var _segments: Array[Node3D] = []
var _hist: PackedVector3Array = PackedVector3Array()
var _hop_i := 0
var _t := 0.0
var _hop_dur := 2.0
var _started := false


func _ready() -> void:
	add_to_group("sync_dragon")
	_build_head()
	_build_body()
	# Seed the arc so the head starts at the first pool, and prime the history
	# buffer with a straight tail behind it so the body doesn't spawn crumpled.
	_recompute_hop_dur()
	var start := _head_pose()
	head_root.global_transform = start
	var back := -start.basis.z
	for i in range(SEG_COUNT * 4):
		_hist.append(start.origin - back * (i * 0.4))
	_layout_body()
	_started = true


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return  # clients are driven purely by apply_remote_state
	_advance(delta)
	head_root.global_transform = _head_pose()
	_hist.insert(0, head_root.global_position)
	_trim_history()
	_layout_body()


## Server -> client: just the head pose. The body is rebuilt from it locally.
func apply_remote_state(state: Dictionary) -> void:
	if not _started:
		return
	head_root.global_transform = state["head"]
	_hist.insert(0, head_root.global_position)
	_trim_history()
	_layout_body()


# --- arc simulation -----------------------------------------------------------

func _advance(delta: float) -> void:
	_t += delta / _hop_dur
	while _t >= 1.0:
		_t -= 1.0
		_hop_i = (_hop_i + 1) % TOUR.size()
		_recompute_hop_dur()


func _recompute_hop_dur() -> void:
	var a: Vector2 = pools[TOUR[_hop_i]]
	var b: Vector2 = pools[TOUR[(_hop_i + 1) % TOUR.size()]]
	_hop_dur = maxf(HOP_MIN_DUR, a.distance_to(b) / HOP_SPEED)


## The head's transform this instant: eased horizontal glide pool->pool, with a
## tall sine arc that dips below the surface at both ends (emerge / plunge).
func _head_pose() -> Transform3D:
	var a: Vector2 = pools[TOUR[_hop_i]]
	var b: Vector2 = pools[TOUR[(_hop_i + 1) % TOUR.size()]]
	var e := smoothstep(0.0, 1.0, _t)
	var xz := a.lerp(b, e)
	var arc := lerpf(-0.16, 1.16, _t) * PI
	var y := water_y + (apex_y - water_y) * sin(arc)
	if y < deep_y:
		y = deep_y
	var pos := Vector3(xz.x, y, xz.y)
	# Face along the path tangent (a small look-ahead in eased param).
	var e2 := smoothstep(0.0, 1.0, minf(_t + 0.03, 1.0))
	var xz2 := a.lerp(b, e2)
	var arc2 := lerpf(-0.16, 1.16, minf(_t + 0.03, 1.0)) * PI
	var y2 := maxf(deep_y, water_y + (apex_y - water_y) * sin(arc2))
	var ahead := Vector3(xz2.x, y2, xz2.y)
	return _look_transform(pos, ahead)


## A transform at `from` whose -Z points toward `to`, robust when the direction
## is near-vertical (where a naive look_at with UP would degenerate).
func _look_transform(from: Vector3, to: Vector3) -> Transform3D:
	var fwd := to - from
	if fwd.length() < 0.0001:
		return Transform3D(Basis(), from)
	fwd = fwd.normalized()
	var up := Vector3.UP
	if absf(fwd.dot(up)) > 0.98:
		up = Vector3.FORWARD
	var t := Transform3D(Basis(), from)
	return t.looking_at(to, up)


# --- body trailing ------------------------------------------------------------

func _trim_history() -> void:
	var max_len := SEG_COUNT * 12 + 40
	if _hist.size() > max_len:
		_hist.resize(max_len)


## Place each segment a fixed arc-length behind the head, walking back through
## the recorded head path and interpolating between samples.
func _layout_body() -> void:
	for i in range(_segments.size()):
		var seg := _segments[i]
		var d := SEG_GAP * float(i + 1)
		var p := _point_at_distance(d)
		var ahead := _point_at_distance(maxf(0.0, d - SEG_GAP))
		seg.global_transform = _look_transform(p, ahead)


func _point_at_distance(d: float) -> Vector3:
	if _hist.is_empty():
		return head_root.global_position
	if d <= 0.0:
		return _hist[0]
	var acc := 0.0
	for i in range(1, _hist.size()):
		var seg_len := _hist[i - 1].distance_to(_hist[i])
		if acc + seg_len >= d:
			var f := (d - acc) / maxf(seg_len, 0.0001)
			return _hist[i - 1].lerp(_hist[i], f)
		acc += seg_len
	return _hist[_hist.size() - 1]


# --- construction -------------------------------------------------------------

func _build_head() -> void:
	head_root = Node3D.new()
	head_root.name = "Head"
	add_child(head_root)
	# Skull + elongated snout (the head faces -Z).
	_mesh_on(head_root, _sphere_mesh(HEAD_R, HEAD_COL), Vector3(0, 0, 0))
	_mesh_on(head_root, _box_mesh(Vector3(1.5, 1.1, 2.2), HEAD_COL), Vector3(0, -0.1, -1.5))
	_mesh_on(head_root, _box_mesh(Vector3(1.2, 0.5, 1.3), BELLY_COL), Vector3(0, -0.55, -1.8))  # lower jaw
	# Brow ridge + two swept-back horns.
	for sx in [-1.0, 1.0]:
		var horn := _cone_mesh(0.0, 0.28, 1.8, HORN_COL)
		var m := MeshInstance3D.new()
		m.mesh = horn
		m.position = Vector3(0.55 * sx, 0.9, 0.7)
		m.rotation = Vector3(2.4, 0.0, -0.25 * sx)
		head_root.add_child(m)
		# Amber eye.
		_emis_on(head_root, _sphere_mesh(0.26, EYE_COL), Vector3(0.62 * sx, 0.25, -1.35), EYE_COL)
	# A short dorsal frill of spikes just behind the skull.
	for k in range(3):
		var spike := _cone_mesh(0.0, 0.22, 0.9 - k * 0.12, FIN_COL)
		var sm := MeshInstance3D.new()
		sm.mesh = spike
		sm.position = Vector3(0, 1.0 - k * 0.05, 0.5 + k * 0.55)
		head_root.add_child(sm)
	# Two long trailing whiskers (Ryujin), swept back and down.
	for sx in [-1.0, 1.0]:
		var w := _cone_mesh(0.05, 0.1, 3.4, HORN_COL)
		var wm := MeshInstance3D.new()
		wm.mesh = w
		wm.position = Vector3(0.7 * sx, -0.2, -1.9)
		wm.rotation = Vector3(-1.7, 0.2 * sx, 0.0)
		head_root.add_child(wm)
	# The weak point marker sits on top of the crown (used in Stage 3).
	var weak := Node3D.new()
	weak.name = "Weakpoint"
	weak.position = Vector3(0, HEAD_R, -0.2)
	head_root.add_child(weak)


func _build_body() -> void:
	for i in range(SEG_COUNT):
		var f := float(i) / float(SEG_COUNT - 1)
		var r: float = lerpf(HEAD_R * 0.95, 0.3, f)  # taper head->tail
		var seg := Node3D.new()
		seg.name = "Seg%d" % i
		add_child(seg)
		_mesh_on(seg, _sphere_mesh(r, BODY_COL), Vector3.ZERO)
		# Pale belly slab under the fatter forward segments.
		if f < 0.75:
			_mesh_on(seg, _box_mesh(Vector3(r * 1.1, r * 0.5, r * 1.6), BELLY_COL), Vector3(0, -r * 0.65, 0))
		# Dorsal fin along the first two-thirds.
		if f < 0.66:
			var fin := _cone_mesh(0.0, r * 0.35, r * 1.5, FIN_COL)
			var fm := MeshInstance3D.new()
			fm.mesh = fin
			fm.position = Vector3(0, r * 0.95, 0)
			seg.add_child(fm)
		_segments.append(seg)


# --- mesh helpers -------------------------------------------------------------

func _mesh_on(parent: Node3D, mesh: Mesh, pos: Vector3) -> void:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	parent.add_child(m)


func _emis_on(parent: Node3D, mesh: Mesh, pos: Vector3, col: Color) -> void:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.4
	m.material_override = mat
	parent.add_child(m)


func _sphere_mesh(r: float, col: Color) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.material = _mat(col)
	return s


func _box_mesh(size: Vector3, col: Color) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	b.material = _mat(col)
	return b


func _cone_mesh(top_r: float, bot_r: float, h: float, col: Color) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bot_r
	c.height = h
	c.radial_segments = 6
	c.material = _mat(col)
	return c


func _mat(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	return mat
