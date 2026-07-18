extends Node3D
## The water dragon -- a serpent modelled after Ryujin and Glaurung.
##
## MOTION: it endlessly ARCS between the flooded arena's deep pools -- erupting
## from one, sailing over the water, and plunging into the next (the underwater
## crawlspace between pools is lore; the head just dips below the dim surface at
## each arc end and re-emerges at the next).
##
## COMBAT (Phase 1): after a spell of roaming it surfaces at the TOP pool, rears
## up (the telegraph), and flops its head down onto the floor -- EXPOSED, its
## crown weak point glowing. Strike the top of the head while it's down and it
## recoils back into the pool. Three strikes fell it. Falling into a deep pool
## is the players' own failure state (handled in world.gd). Phases 2-3 (extra
## attacks, enrage) and the draconite reward land in Stage 4.
##
## Server-authoritative: only the server runs the state machine; the head pose,
## the vulnerable flag and the hit count ride the World's per-frame snapshot,
## and every peer trails the body + mirrors the glow locally.

enum State { ROAM, RISING, EXPOSED, RECOIL, DEFEATED, DEAD }

# Configured by map_decorations before the node enters the tree.
var pools: Array = []          # Array[Vector2], world XZ of each deep pool
var water_y := -39.65          # the waterline (arc ends dip just below this)
var deep_y := -49.0            # how deep the head sinks at each arc end
var apex_y := -24.0            # arc peak height

const TOUR: Array[int] = [0, 3, 1, 2]  # pool visiting order -- long criss-cross arcs
const HOP_SPEED := 9.0         # target horizontal m/s; hop duration scales with span
const HOP_MIN_DUR := 1.6

const ROAM_TIME := 9.0         # how long it arcs before surfacing to be struck
const RISE_DUR := 2.3          # rear-up + flop telegraph
const EXPOSE_TIME := 4.5       # vulnerable window on the floor
const RECOIL_DUR := 1.5        # rear back + dive away
const DEATH_DUR := 3.0
const HITS_TO_KILL := 3
const STRIKE_R := 2.6          # horizontal reach of a strike on the crown
const STRIKE_BOUNCE := 13.0    # upward pop the striker gets (a stomp)

const SEG_COUNT := 18
const SEG_GAP := 1.05          # metres between segments along the body
const HEAD_R := 1.35

const BODY_COL := Color(0.13, 0.42, 0.34)
const BELLY_COL := Color(0.55, 0.75, 0.62)
const HEAD_COL := Color(0.10, 0.34, 0.30)
const FIN_COL := Color(0.20, 0.58, 0.55)
const HORN_COL := Color(0.86, 0.84, 0.72)
const EYE_COL := Color(1.0, 0.75, 0.2)
const WEAK_COL := Color(1.0, 0.42, 0.2)

var active := true             # Stage 4 will gate this on the raid actually starting
var hits := 0

var head_root: Node3D
var _weak: Node3D
var _glow: MeshInstance3D
var _head_meshes: Array[MeshInstance3D] = []
var _segments: Array[Node3D] = []
var _hist: PackedVector3Array = PackedVector3Array()

var _state: int = State.ROAM
var _hop_i := 0
var _t := 0.0
var _hop_dur := 2.0
var _roam_timer := ROAM_TIME
var _want_surface := false
var _phase_t := 0.0            # 0..1 progress through a scripted (non-roam) phase
var _expose_timer := 0.0
var _struck := false           # a strike already landed this exposure
var _vuln := false             # networked: crown is glowing / hittable
var _flash := 0.0
var _bob := 0.0
var _started := false


func _ready() -> void:
	add_to_group("sync_dragon")
	_build_head()
	_build_body()
	_recompute_hop_dur()
	var start := _head_pose_roam()
	head_root.global_transform = start
	var back := -start.basis.z
	for i in range(SEG_COUNT * 4):
		_hist.append(start.origin - back * (i * 0.4))
	_layout_body()
	_set_glow(false)
	_started = true


## True while the dragon is a live threat (used by the arena's fall-in rule).
func fight_live() -> bool:
	return active and _state != State.DEFEATED and _state != State.DEAD


func _physics_process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		_apply_flash()
	if not multiplayer.is_server():
		return  # clients are driven purely by apply_remote_state
	_bob += delta
	match _state:
		State.ROAM:
			_tick_roam(delta)
		State.RISING:
			_tick_rising(delta)
		State.EXPOSED:
			_tick_exposed(delta)
		State.RECOIL:
			_tick_recoil(delta)
		State.DEFEATED:
			_tick_defeated(delta)
		State.DEAD:
			pass
	_hist.insert(0, head_root.global_position)
	_trim_history()
	_layout_body()


## Server -> client: the head pose plus the fight's networked bits.
func apply_remote_state(state: Dictionary) -> void:
	if not _started:
		return
	head_root.global_transform = state["head"]
	hits = state.get("hits", hits)
	_set_glow(state.get("vuln", false))
	_hist.insert(0, head_root.global_position)
	_trim_history()
	_layout_body()


# --- state ticks --------------------------------------------------------------

func _tick_roam(delta: float) -> void:
	if active:
		_roam_timer -= delta
		if _roam_timer <= 0.0:
			_want_surface = true
	_advance_roam(delta)
	# Slip into the rise only while underwater at the top pool, so the little
	# snap to the pool's deep point never shows above the surface.
	if _want_surface and head_root.global_position.y < water_y - 0.5 \
			and Vector2(head_root.global_position.x, head_root.global_position.z).distance_to(_p0()) < 6.0:
		_want_surface = false
		_state = State.RISING
		_phase_t = 0.0
		head_root.global_transform = _look_transform(_deep_pt(), _deep_pt() + Vector3(0, 1, 0))
	else:
		head_root.global_transform = _head_pose_roam()


func _tick_rising(delta: float) -> void:
	_phase_t += delta / RISE_DUR
	var t := clampf(_phase_t, 0.0, 1.0)
	if t < 0.5:
		# Rear up out of the pool (telegraph).
		var f := smoothstep(0.0, 1.0, t / 0.5)
		var pos := _deep_pt().lerp(_rear_apex(), f)
		head_root.global_transform = _look_transform(pos, pos + Vector3(0, 1.5, -1.0))
	else:
		# Flop the head forward and down onto the floor.
		var f := smoothstep(0.0, 1.0, (t - 0.5) / 0.5)
		var pos := _rear_apex().lerp(_flop_pos(), f)
		head_root.global_transform = _rest_pose(pos)
	if _phase_t >= 1.0:
		_state = State.EXPOSED
		_expose_timer = EXPOSE_TIME
		_struck = false
		_set_glow(true)


func _tick_exposed(delta: float) -> void:
	_expose_timer -= delta
	var pos := _flop_pos() + Vector3(0, sin(_bob * 3.0) * 0.08, 0)
	head_root.global_transform = _rest_pose(pos)
	if not _struck:
		_check_strikes()
	if _struck or _expose_timer <= 0.0:
		_set_glow(false)
		_state = State.RECOIL
		_phase_t = 0.0


func _tick_recoil(delta: float) -> void:
	_phase_t += delta / RECOIL_DUR
	var t := clampf(_phase_t, 0.0, 1.0)
	if t < 0.5:
		var f := smoothstep(0.0, 1.0, t / 0.5)
		var pos := _flop_pos().lerp(_rear_apex(), f)
		head_root.global_transform = _look_transform(pos, pos + Vector3(0, 1.5, 1.0))
	else:
		var f := smoothstep(0.0, 1.0, (t - 0.5) / 0.5)
		var pos := _rear_apex().lerp(_deep_pt(), f)
		head_root.global_transform = _look_transform(pos, _deep_pt() + Vector3(0, -1, 0))
	if _phase_t >= 1.0:
		if hits >= HITS_TO_KILL:
			_state = State.DEFEATED
			_phase_t = 0.0
		else:
			_state = State.ROAM
			_roam_timer = ROAM_TIME
			_hop_i = 0
			_t = 0.0
			_recompute_hop_dur()


func _tick_defeated(delta: float) -> void:
	# A final thrash, then sink to the pool floor and go still.
	_phase_t += delta / DEATH_DUR
	var t := clampf(_phase_t, 0.0, 1.0)
	var thrash := sin(t * PI * 5.0) * (1.0 - t) * 2.0
	var pos := _deep_pt().lerp(Vector3(_p0().x, deep_y - 2.0, _p0().y), t) + Vector3(thrash, 0, 0)
	head_root.global_transform = _look_transform(pos, pos + Vector3(thrash, -1, 0))
	if _phase_t >= 1.0:
		_state = State.DEAD


func _check_strikes() -> void:
	var wp := _weak.global_position
	for pl in get_tree().get_nodes_in_group("players"):
		var p := pl as Node3D
		if p == null or p.get("spectating"):
			continue
		var flat := Vector2(p.global_position.x - wp.x, p.global_position.z - wp.z).length()
		if flat < STRIKE_R and p.global_position.y > wp.y - 0.6:
			_register_strike(p)
			return


func _register_strike(striker: Node3D) -> void:
	_struck = true
	hits += 1
	_flash = 0.35
	_play_strike.rpc()
	# A Mario-stomp bounce off the crown.
	if striker.has_method("apply_stomp_bounce"):
		striker.apply_stomp_bounce(STRIKE_BOUNCE)
	elif "velocity" in striker:
		var v: Vector3 = striker.velocity
		striker.velocity = Vector3(v.x, STRIKE_BOUNCE, v.z)


@rpc("authority", "call_local", "reliable")
func _play_strike() -> void:
	_flash = 0.35
	_apply_flash()


# --- roam arc (unchanged from Stage 2) ----------------------------------------

func _advance_roam(delta: float) -> void:
	_t += delta / _hop_dur
	while _t >= 1.0:
		_t -= 1.0
		# When it's time to surface, steer the next hop at the top pool.
		if _want_surface:
			_hop_i = _index_of_hop_into(0)
		else:
			_hop_i = (_hop_i + 1) % TOUR.size()
		_recompute_hop_dur()


## The tour position whose NEXT pool is `pool_idx` (so this hop dives into it).
func _index_of_hop_into(pool_idx: int) -> int:
	for i in range(TOUR.size()):
		if TOUR[(i + 1) % TOUR.size()] == pool_idx:
			return i
	return _hop_i


func _recompute_hop_dur() -> void:
	var a: Vector2 = pools[TOUR[_hop_i]]
	var b: Vector2 = pools[TOUR[(_hop_i + 1) % TOUR.size()]]
	_hop_dur = maxf(HOP_MIN_DUR, a.distance_to(b) / HOP_SPEED)


func _head_pose_roam() -> Transform3D:
	var a: Vector2 = pools[TOUR[_hop_i]]
	var b: Vector2 = pools[TOUR[(_hop_i + 1) % TOUR.size()]]
	var e := smoothstep(0.0, 1.0, _t)
	var xz := a.lerp(b, e)
	var arc := lerpf(-0.16, 1.16, _t) * PI
	var y := maxf(deep_y, water_y + (apex_y - water_y) * sin(arc))
	var pos := Vector3(xz.x, y, xz.y)
	var tf := minf(_t + 0.03, 1.0)
	var e2 := smoothstep(0.0, 1.0, tf)
	var xz2 := a.lerp(b, e2)
	var y2 := maxf(deep_y, water_y + (apex_y - water_y) * sin(lerpf(-0.16, 1.16, tf) * PI))
	return _look_transform(pos, Vector3(xz2.x, y2, xz2.y))


# --- key positions ------------------------------------------------------------

func _p0() -> Vector2:
	return pools[0]


func _deep_pt() -> Vector3:
	return Vector3(_p0().x, deep_y, _p0().y)


func _rear_apex() -> Vector3:
	return Vector3(_p0().x, water_y + 7.0, _p0().y)


func _flop_pos() -> Vector3:
	# Head laid on the floor just inside the pool, toward the arena / dry path.
	return Vector3(_p0().x, -39.0, _p0().y - 5.0)


## A resting transform: snout tipped down and forward so the crown faces up and
## the weak point sits proud on top.
func _rest_pose(pos: Vector3) -> Transform3D:
	return _look_transform(pos, pos + Vector3(0, -0.35, -1.0))


func _look_transform(from: Vector3, to: Vector3) -> Transform3D:
	var fwd := to - from
	if fwd.length() < 0.0001:
		return Transform3D(Basis(), from)
	var up := Vector3.UP
	if absf(fwd.normalized().dot(up)) > 0.98:
		up = Vector3.FORWARD
	var t := Transform3D(Basis(), from)
	return t.looking_at(to, up)


# --- body trailing ------------------------------------------------------------

func _trim_history() -> void:
	var max_len := SEG_COUNT * 12 + 40
	if _hist.size() > max_len:
		_hist.resize(max_len)


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


# --- glow / flash -------------------------------------------------------------

func _set_glow(v: bool) -> void:
	_vuln = v
	if _glow:
		_glow.visible = v


func _apply_flash() -> void:
	var e := _flash / 0.35
	for m in _head_meshes:
		var mat := m.material_override as StandardMaterial3D
		if mat == null:
			continue
		mat.emission_enabled = e > 0.0
		mat.emission = Color(1, 1, 1)
		mat.emission_energy_multiplier = e * 2.5


# --- construction -------------------------------------------------------------

func _build_head() -> void:
	head_root = Node3D.new()
	head_root.name = "Head"
	add_child(head_root)
	_head_meshes.append(_mesh_on(head_root, _sphere_mesh(HEAD_R, HEAD_COL), Vector3(0, 0, 0)))
	_head_meshes.append(_mesh_on(head_root, _box_mesh(Vector3(1.5, 1.1, 2.2), HEAD_COL), Vector3(0, -0.1, -1.5)))
	_head_meshes.append(_mesh_on(head_root, _box_mesh(Vector3(1.2, 0.5, 1.3), BELLY_COL), Vector3(0, -0.55, -1.8)))  # jaw
	for sx in [-1.0, 1.0]:
		var horn := _cone_mesh(0.0, 0.28, 1.8, HORN_COL)
		var m := MeshInstance3D.new()
		m.mesh = horn
		m.position = Vector3(0.55 * sx, 0.9, 0.7)
		m.rotation = Vector3(2.4, 0.0, -0.25 * sx)
		head_root.add_child(m)
		_emis_on(head_root, _sphere_mesh(0.26, EYE_COL), Vector3(0.62 * sx, 0.25, -1.35), EYE_COL, 1.4)
	for k in range(3):
		var spike := _cone_mesh(0.0, 0.22, 0.9 - k * 0.12, FIN_COL)
		var sm := MeshInstance3D.new()
		sm.mesh = spike
		sm.position = Vector3(0, 1.0 - k * 0.05, 0.5 + k * 0.55)
		head_root.add_child(sm)
	for sx in [-1.0, 1.0]:
		var w := _cone_mesh(0.05, 0.1, 3.4, HORN_COL)
		var wm := MeshInstance3D.new()
		wm.mesh = w
		wm.position = Vector3(0.7 * sx, -0.2, -1.9)
		wm.rotation = Vector3(-1.7, 0.2 * sx, 0.0)
		head_root.add_child(wm)
	# The weak point on the crown + its glow (shown only while vulnerable).
	_weak = Node3D.new()
	_weak.name = "Weakpoint"
	_weak.position = Vector3(0, HEAD_R, -0.2)
	head_root.add_child(_weak)
	_glow = MeshInstance3D.new()
	_glow.mesh = _sphere_mesh(0.5, WEAK_COL)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = WEAK_COL
	gmat.emission_enabled = true
	gmat.emission = WEAK_COL
	gmat.emission_energy_multiplier = 2.2
	_glow.material_override = gmat
	_glow.position = Vector3(0, HEAD_R + 0.15, -0.2)
	head_root.add_child(_glow)


func _build_body() -> void:
	for i in range(SEG_COUNT):
		var f := float(i) / float(SEG_COUNT - 1)
		var r: float = lerpf(HEAD_R * 0.95, 0.3, f)
		var seg := Node3D.new()
		seg.name = "Seg%d" % i
		add_child(seg)
		_mesh_on(seg, _sphere_mesh(r, BODY_COL), Vector3.ZERO)
		if f < 0.75:
			_mesh_on(seg, _box_mesh(Vector3(r * 1.1, r * 0.5, r * 1.6), BELLY_COL), Vector3(0, -r * 0.65, 0))
		if f < 0.66:
			var fin := _cone_mesh(0.0, r * 0.35, r * 1.5, FIN_COL)
			var fm := MeshInstance3D.new()
			fm.mesh = fin
			fm.position = Vector3(0, r * 0.95, 0)
			seg.add_child(fm)
		_segments.append(seg)


# --- mesh helpers -------------------------------------------------------------

func _mesh_on(parent: Node3D, mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	# Give every head/body piece its own material override so the strike flash
	# can drive emission without disturbing the shared mesh materials.
	if mesh is PrimitiveMesh and (mesh as PrimitiveMesh).material is StandardMaterial3D:
		m.material_override = ((mesh as PrimitiveMesh).material as StandardMaterial3D).duplicate()
	parent.add_child(m)
	return m


func _emis_on(parent: Node3D, mesh: Mesh, pos: Vector3, col: Color, energy: float) -> void:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = energy
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
