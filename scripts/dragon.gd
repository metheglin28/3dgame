extends Node3D
## The water dragon -- a serpent modelled after Ryujin and Glaurung.
##
## MOTION: it travels the pools in alternating legs -- a low ARC over the water
## (erupt from one hole, skim across, dive into another) then a hidden SWIM
## (submerged, from the hole it just entered to a DIFFERENT one). So it always
## exits a different hole than it entered, and the long body sweeps low enough to
## catch players: brushing the body knocks you down, the head flat-out launches
## you (see _body_contact).
##
## COMBAT: dormant until the stake rouses it (begin_raid). It roams, and after a
## spell surfaces at the TOP pool, rears up (the telegraph) and flops its head
## onto the floor -- EXPOSED, crown weak point glowing. Stomp the crown to land a
## hit; three hits fell it. Each hit escalates the PHASE (1->3):
##   phase 1 -- low hole-to-hole hopping (the body is the hazard);
##   phase 2 -- same, but it periodically pops its head from a hole and BREATHES
##              FIRE at the nearest player before resuming;
##   phase 3 -- ENRAGED (red-eyed): everything faster -- quicker hops and much
##              more frequent fire.
## Falling into a deep pool is the players' own lose (world.gd). Beaten, it sinks
## and yields the draconite jewel.
##
## Server-authoritative: only the server runs the state machine; the head pose,
## the vulnerable flag, the hit count and the enrage flag ride the World's
## per-frame snapshot, the fire plume replicates by RPC, and every peer trails
## the body + mirrors the glow locally.

enum State { ROAM, RISING, EXPOSED, RECOIL, DEFEATED, DEAD, DORMANT, BREATHING }

# Configured by map_decorations before the node enters the tree.
var pools: Array = []          # Array[Vector2], world XZ of each deep pool
var water_y := -39.65          # the waterline (arc ends dip just below this)
var deep_y := -49.0            # how deep the head sinks at each arc end
var apex_y := -24.0            # arc peak height

# Roam legs (see _leg_pose). A leg is an ARC (over water) or a SWIM (submerged).
const HOP_MIN_DUR := 1.0
const ARC_APEX_OVER := 2.5   # how high the low hop hump peaks above the waterline
const SWIM_BOB := 2.0        # how far the submerged swim rises (stays below water)

# Per-phase escalation (index = phase-1).
const ROAM_BY_PHASE: Array[float] = [9.0, 7.0, 5.0]
const EXPOSE_BY_PHASE: Array[float] = [4.5, 3.8, 3.0]
const HOPSPEED_BY_PHASE: Array[float] = [16.0, 20.0, 26.0]  # m/s the head travels a leg

# Body-contact hazard (roam only -- NOT during the exposed hit window).
const HEAD_HIT_R := 2.0
const BODY_HIT_R := 1.7
const HEAD_LAUNCH := 16.0    # a brush from the head: pistol-equivalent launch
const BODY_KB := 11.0        # a brush from the body: knockback + ragdoll

# Fire breath (phase >= 2). It pops from a hole, breathes at the nearest player.
const FIRE_INTERVAL_BY_PHASE: Array[float] = [999.0, 7.0, 3.5]
const BREATHE_DUR_BY_PHASE: Array[float] = [2.4, 2.4, 1.7]  # whole pop-breathe-dive
const FIRE_KB := 13.0        # lightning-equivalent: moderate knockback...
const FIRE_ROLL := 3.2       # ...but a long roll
const FIRE_RANGE := 15.0
const FIRE_HALF_ANGLE := 0.42  # ~24 degrees to each side of the aim

const RISE_DUR := 2.3
const RECOIL_DUR := 1.5
const DEATH_DUR := 3.0
const HITS_TO_KILL := 3
const STRIKE_R := 2.6
const STRIKE_BOUNCE := 13.0

const SEG_COUNT := 32        # much longer than before -- more body to bump into
const SEG_GAP := 1.05
const HEAD_R := 1.35

const BODY_COL := Color(0.13, 0.42, 0.34)
const BELLY_COL := Color(0.55, 0.75, 0.62)
const HEAD_COL := Color(0.10, 0.34, 0.30)
const FIN_COL := Color(0.20, 0.58, 0.55)
const HORN_COL := Color(0.86, 0.84, 0.72)
const EYE_COL := Color(1.0, 0.75, 0.2)
const EYE_RAGE := Color(1.0, 0.2, 0.12)
const WEAK_COL := Color(1.0, 0.42, 0.2)

var armed := false             # has the raid been roused? (dormant until then)
var hits := 0

var head_root: Node3D
var _weak: Node3D
var _glow: MeshInstance3D
var _eyes: Array[MeshInstance3D] = []
var _head_meshes: Array[MeshInstance3D] = []
var _segments: Array[Node3D] = []
var _hist: PackedVector3Array = PackedVector3Array()

var _state: int = State.DORMANT
var _cur_hole := 0             # pool the head is leaving
var _next_hole := 1           # pool the head is heading to
var _leg_arc := true          # this leg: true = arc over water, false = submerged swim
var _leg_t := 0.0             # 0..1 through the current leg
var _leg_dur := 1.5
var _roam_timer := 0.0
var _want_surface := false
var _fire_timer := 0.0
var _fire_dir := Vector3.FORWARD  # locked aim of the current fire breath
var _fire_shown := false
var _phase_t := 0.0
var _expose_timer := 0.0
var _struck := false
var _vuln := false
var _enraged := false
var _flash := 0.0
var _bob := 0.0
var _rng := RandomNumberGenerator.new()
var _started := false


func _ready() -> void:
	add_to_group("sync_dragon")
	_rng.seed = 0xD2A6
	_build_head()
	_build_body()
	var start := _dormant_pose()
	head_root.global_transform = start
	var back := -start.basis.z
	for i in range(SEG_COUNT * 4):
		_hist.append(start.origin - back * (i * 0.4))
	_layout_body()
	_set_glow(false)
	_started = true


## True while the dragon is a live threat (used by the arena's fall-in rule).
func fight_live() -> bool:
	return armed and _state != State.DEFEATED and _state != State.DEAD


func is_defeated() -> bool:
	return _state == State.DEFEATED or _state == State.DEAD


## Server-only. Rouse the dormant dragon and start the raid.
func begin_raid() -> void:
	if not multiplayer.is_server() or armed or is_defeated():
		return
	armed = true
	hits = 0
	_state = State.ROAM
	_start_roam()
	_update_enrage()


## Set up a fresh roam: the head is at the top pool (where it lurked), so start
## an arc out of it toward a random other pool, and arm the surface/fire timers.
func _start_roam() -> void:
	_cur_hole = 0
	_next_hole = _pick_hole(0)
	_leg_arc = true
	_leg_t = 0.0
	_leg_dur = _compute_leg_dur()
	_roam_timer = _roam_time()
	_fire_timer = _fire_interval()
	_want_surface = false


## Server-only. Stand the dragon back down after a raid ends, so the altar/stake
## can start a fresh one. (Beaten or not -- a timed-out raid resets too.)
func reset_to_dormant() -> void:
	if not multiplayer.is_server():
		return
	armed = false
	hits = 0
	_want_surface = false
	_struck = false
	_state = State.DORMANT
	_set_glow(false)
	_set_enrage(false)
	head_root.global_transform = _dormant_pose()


func _physics_process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		_apply_flash()
	if not multiplayer.is_server():
		return  # clients are driven purely by apply_remote_state
	_bob += delta
	match _state:
		State.DORMANT:
			head_root.global_transform = _dormant_pose()
		State.ROAM:
			_tick_roam(delta)
		State.BREATHING:
			_tick_breathing(delta)
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
	_set_enrage(state.get("enrage", false))
	_hist.insert(0, head_root.global_position)
	_trim_history()
	_layout_body()


# --- phase tuning -------------------------------------------------------------

func phase() -> int:
	return clampi(hits + 1, 1, 3)


func _roam_time() -> float:
	return ROAM_BY_PHASE[phase() - 1]


func _expose_time() -> float:
	return EXPOSE_BY_PHASE[phase() - 1]


func _update_enrage() -> void:
	_set_enrage(fight_live() and phase() == 3)


# --- state ticks --------------------------------------------------------------

func _tick_roam(delta: float) -> void:
	_roam_timer -= delta
	if _roam_timer <= 0.0:
		_want_surface = true
	if phase() >= 2 and not _want_surface:
		_fire_timer -= delta
	# Advance the leg; act on leg boundaries (head sitting in a hole).
	_leg_t += delta / _leg_dur
	if _leg_t >= 1.0:
		_leg_t = 0.0
		_cur_hole = _next_hole
		_leg_arc = not _leg_arc
		# At the top pool with the surface cue up -> rise to be struck.
		if _want_surface and _cur_hole == 0:
			_want_surface = false
			_state = State.RISING
			_phase_t = 0.0
			head_root.global_transform = _look_transform(_deep_pt(), _deep_pt() + Vector3(0, 1, 0))
			return
		# Otherwise, maybe pop up and breathe fire (phase 2+); else pick the next hole.
		if not _want_surface and _fire_timer <= 0.0 and phase() >= 2 and _nearest_player() != null:
			_enter_breathing()
			return
		_next_hole = 0 if _want_surface else _pick_hole(_cur_hole)
		_leg_dur = _compute_leg_dur()
	head_root.global_transform = _leg_pose()
	_body_contact()


func _pick_hole(cur: int) -> int:
	var n := pools.size()
	if n <= 1:
		return cur
	var h := cur
	while h == cur:
		h = _rng.randi() % n
	return h


func _compute_leg_dur() -> float:
	var d: float = pools[_cur_hole].distance_to(pools[_next_hole])
	var speed: float = HOPSPEED_BY_PHASE[phase() - 1]
	if _leg_arc:
		return maxf(HOP_MIN_DUR, d / speed)
	return maxf(0.6, d / (speed * 1.5))  # the submerged transit is a touch quicker


## The head this instant along the current leg. ARC legs hump LOW over the water
## (emerge -> skim -> dive); SWIM legs stay submerged, so the head vanishes at one
## hole and reappears at another.
func _leg_pose() -> Transform3D:
	var a: Vector2 = pools[_cur_hole]
	var b: Vector2 = pools[_next_hole]
	var e := smoothstep(0.0, 1.0, _leg_t)
	var xz := a.lerp(b, e)
	var y := _leg_y(_leg_t)
	var pos := Vector3(xz.x, y, xz.y)
	var t2 := minf(_leg_t + 0.04, 1.0)
	var xz2 := a.lerp(b, smoothstep(0.0, 1.0, t2))
	var ahead := Vector3(xz2.x, _leg_y(t2), xz2.y)
	return _look_transform(pos, ahead)


func _leg_y(t: float) -> float:
	if _leg_arc:
		# Deep at both ends, a low hump (apex just over the waterline) in the middle.
		return lerpf(deep_y, water_y + ARC_APEX_OVER, sin(PI * t))
	# Submerged the whole way: bob up a little but stay under the surface.
	return minf(water_y - 1.5, deep_y + sin(PI * t) * SWIM_BOB)


# --- body-contact hazard ------------------------------------------------------

## Server-only, roam-only. Anyone the above-water head or body brushes gets hit:
## the head flat-out launches you (pistol), the body knocks you down (ragdoll).
## apply_knockback's own immunity window keeps it a bump, not a stunlock. Skipped
## during the exposed hit window, where you're meant to walk up and strike.
func _body_contact() -> void:
	var players := get_tree().get_nodes_in_group("players")
	var hp := head_root.global_position
	var head_live := hp.y > water_y - 1.2
	for pl in players:
		var p := pl as Node3D
		if p == null or p.get("spectating") or not p.has_method("apply_knockback"):
			continue
		var pp: Vector3 = p.global_position
		if head_live and _touching(pp, hp, HEAD_HIT_R):
			_shove_from(p, pp, hp, HEAD_LAUNCH, RAGDOLL_MIN)
			continue
		for seg in _segments:
			var sp: Vector3 = seg.global_position
			if sp.y > water_y - 1.2 and _touching(pp, sp, BODY_HIT_R):
				_shove_from(p, pp, sp, BODY_KB, RAGDOLL_MIN)
				break


const RAGDOLL_MIN := 1.1

func _touching(pp: Vector3, cp: Vector3, r: float) -> bool:
	return Vector2(pp.x - cp.x, pp.z - cp.z).length() < r and absf(pp.y - cp.y) < r + 1.2


func _shove_from(p: Node3D, pp: Vector3, cp: Vector3, power: float, ragtime: float) -> void:
	var dir := Vector3(pp.x - cp.x, 0.0, pp.z - cp.z)
	if dir.length() < 0.1:
		dir = Vector3(cos(_bob * 2.0), 0, sin(_bob * 2.0))
	p.apply_knockback(dir.normalized(), power, ragtime)


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var bd := INF
	var hp := head_root.global_position
	for pl in get_tree().get_nodes_in_group("players"):
		var p := pl as Node3D
		if p == null or p.get("spectating"):
			continue
		var d: float = Vector2(p.global_position.x - hp.x, p.global_position.z - hp.z).length()
		if d < bd:
			bd = d
			best = p
	return best


# --- fire breath (phase 2+) ---------------------------------------------------

func _fire_interval() -> float:
	return FIRE_INTERVAL_BY_PHASE[phase() - 1]


func _enter_breathing() -> void:
	_state = State.BREATHING
	_phase_t = 0.0
	_fire_shown = false
	var target := _nearest_player()
	var hole: Vector2 = pools[_cur_hole]
	if target != null:
		_fire_dir = Vector3(target.global_position.x - hole.x, 0.0, target.global_position.z - hole.y)
	if _fire_dir.length() < 0.1:
		_fire_dir = Vector3.FORWARD
	_fire_dir = _fire_dir.normalized()


## Pop the head from the current hole, breathe a fire cone at the locked aim for
## the middle of the window, then dive back and resume roaming.
func _tick_breathing(delta: float) -> void:
	_phase_t += delta / BREATHE_DUR_BY_PHASE[phase() - 1]
	var t := clampf(_phase_t, 0.0, 1.0)
	var hole: Vector2 = pools[_cur_hole]
	var deep := Vector3(hole.x, deep_y, hole.y)
	var up := Vector3(hole.x, water_y + 1.5, hole.y)
	var aim := Vector3(_fire_dir.x, -0.1, _fire_dir.z)
	if t < 0.22:
		head_root.global_transform = _look_transform(deep.lerp(up, smoothstep(0.0, 1.0, t / 0.22)), up + aim)
	elif t < 0.82:
		head_root.global_transform = _look_transform(up, up + aim)
		if not _fire_shown:
			_fire_shown = true
			var secs := BREATHE_DUR_BY_PHASE[phase() - 1] * 0.6
			var origin := head_root.global_position + _fire_dir * 1.6
			if multiplayer.multiplayer_peer != null:
				_play_fire.rpc(origin, _fire_dir, secs)
			else:
				_play_fire(origin, _fire_dir, secs)
		_fire_damage()
	else:
		var f := smoothstep(0.0, 1.0, (t - 0.82) / 0.18)
		head_root.global_transform = _look_transform(up.lerp(deep, f), deep + Vector3(0, -1, 0))
	if _phase_t >= 1.0:
		_fire_timer = _fire_interval()
		_state = State.ROAM
		_leg_arc = false  # slink away submerged to a different hole
		_next_hole = _pick_hole(_cur_hole)
		_leg_t = 0.0
		_leg_dur = _compute_leg_dur()


func _fire_damage() -> void:
	var origin := head_root.global_position + _fire_dir * 1.6
	for pl in get_tree().get_nodes_in_group("players"):
		var p := pl as Node3D
		if p == null or p.get("spectating") or not p.has_method("apply_knockback"):
			continue
		var to := Vector3(p.global_position.x - origin.x, 0.0, p.global_position.z - origin.z)
		var dist := to.length()
		if dist < 0.5 or dist > FIRE_RANGE:
			continue
		if _fire_dir.angle_to(to.normalized()) < FIRE_HALF_ANGLE:
			p.apply_knockback(to.normalized(), FIRE_KB, FIRE_ROLL)  # blown back along the flame


@rpc("authority", "call_local", "reliable")
func _play_fire(origin: Vector3, dir: Vector3, secs: float) -> void:
	var flame := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = FIRE_RANGE * tan(FIRE_HALF_ANGLE)  # wide mouth at the far end
	cone.bottom_radius = 0.25                            # narrow at the muzzle
	cone.height = FIRE_RANGE
	cone.radial_segments = 10
	flame.mesh = cone
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.45, 0.1, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.15)
	mat.emission_energy_multiplier = 2.0
	flame.material_override = mat
	add_child(flame)
	# The cylinder's axis is local +Y; point it down the fire direction, muzzle at origin.
	flame.global_position = origin + dir * (FIRE_RANGE * 0.5)
	flame.look_at_from_position(flame.global_position, flame.global_position + dir, Vector3.UP)
	flame.rotate_object_local(Vector3(1, 0, 0), PI * 0.5)
	flame.scale = Vector3(0.2, 1, 0.2)
	var tween := create_tween()
	tween.tween_property(flame, "scale", Vector3(1, 1, 1), 0.15)
	tween.tween_interval(maxf(0.05, secs - 0.35))
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	tween.tween_callback(flame.queue_free)


func _tick_rising(delta: float) -> void:
	_phase_t += delta / RISE_DUR
	var t := clampf(_phase_t, 0.0, 1.0)
	if t < 0.5:
		var f := smoothstep(0.0, 1.0, t / 0.5)
		var pos := _deep_pt().lerp(_rear_apex(), f)
		head_root.global_transform = _look_transform(pos, pos + Vector3(0, 1.5, -1.0))
	else:
		var f := smoothstep(0.0, 1.0, (t - 0.5) / 0.5)
		var pos := _rear_apex().lerp(_flop_pos(), f)
		head_root.global_transform = _rest_pose(pos)
	if _phase_t >= 1.0:
		_state = State.EXPOSED
		_expose_timer = _expose_time()
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
			_set_enrage(false)
			_drop_reward()
		else:
			_state = State.ROAM
			_start_roam()


func _tick_defeated(delta: float) -> void:
	_phase_t += delta / DEATH_DUR
	var t := clampf(_phase_t, 0.0, 1.0)
	var thrash := sin(t * PI * 5.0) * (1.0 - t) * 2.0
	var pos := _deep_pt().lerp(Vector3(_p0().x, deep_y - 2.0, _p0().y), t) + Vector3(thrash, 0, 0)
	head_root.global_transform = _look_transform(pos, pos + Vector3(thrash, -1, 0))
	if _phase_t >= 1.0:
		_state = State.DEAD


func _dormant_pose() -> Transform3D:
	# Lurking submerged in the top pool, coiled and gently stirring.
	var p := _deep_pt() + Vector3(0, sin(_bob * 0.8) * 0.3, 0)
	return _look_transform(p, p + Vector3(0.25, 1.0, 0.1))


# --- strikes ------------------------------------------------------------------

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
	if multiplayer.multiplayer_peer != null:
		_play_strike.rpc()
	else:
		_play_strike()
	_update_enrage()
	if striker.has_method("apply_stomp_bounce"):
		striker.apply_stomp_bounce(STRIKE_BOUNCE)
	elif "velocity" in striker:
		var v: Vector3 = striker.velocity
		striker.velocity = Vector3(v.x, STRIKE_BOUNCE, v.z)


@rpc("authority", "call_local", "reliable")
func _play_strike() -> void:
	_flash = 0.35
	_apply_flash()


# --- reward -------------------------------------------------------------------

## Server-only. Beaten: bring the draconite up from where the head sank, resting
## on the floor beside the top pool for the players to collect.
func _drop_reward() -> void:
	if not multiplayer.is_server():
		return
	for n in get_tree().get_nodes_in_group("draconite_reward"):
		# Don't yank it out of a player's hands if a past raid already gave it out.
		if n.get("carried_by") != -1:
			continue
		(n as Node3D).global_position = Vector3(_p0().x, -38.2, _p0().y - 5.0)


# --- key positions ------------------------------------------------------------

func _p0() -> Vector2:
	return pools[0]


func _deep_pt() -> Vector3:
	return Vector3(_p0().x, deep_y, _p0().y)


func _rear_apex() -> Vector3:
	return Vector3(_p0().x, water_y + 7.0, _p0().y)


func _flop_pos() -> Vector3:
	return Vector3(_p0().x, -39.0, _p0().y - 5.0)


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


# --- glow / flash / enrage ----------------------------------------------------

func _set_glow(v: bool) -> void:
	_vuln = v
	if _glow:
		_glow.visible = v


func _set_enrage(v: bool) -> void:
	if v == _enraged:
		return
	_enraged = v
	var col := EYE_RAGE if v else EYE_COL
	for eye in _eyes:
		var mat := eye.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = col
			mat.emission = col


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
		_eyes.append(_emis_on(head_root, _sphere_mesh(0.26, EYE_COL), Vector3(0.62 * sx, 0.25, -1.35), EYE_COL, 1.4))
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
	if mesh is PrimitiveMesh and (mesh as PrimitiveMesh).material is StandardMaterial3D:
		m.material_override = ((mesh as PrimitiveMesh).material as StandardMaterial3D).duplicate()
	parent.add_child(m)
	return m


func _emis_on(parent: Node3D, mesh: Mesh, pos: Vector3, col: Color, energy: float) -> MeshInstance3D:
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
	return m


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
