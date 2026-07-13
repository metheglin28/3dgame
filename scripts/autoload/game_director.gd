extends Node
## Runs party-game rounds on top of the hub. Server-authoritative: the server
## ticks the round (see World._physics_process) and folds the round state into
## the same per-frame snapshot the World already broadcasts, so clients just
## mirror it for their HUD and the hill marker. The whole hub map is the arena;
## players keep and pick up powers as normal during a round.
##
## First (and so far only) mode: King of the Hill. A control zone sits at one of
## a rotating list of spots; while you're its SOLE occupant you bank control
## time. Most control time when the ~2.5 min timer runs out wins the round.
## Start a round by interacting with the crown in the town's south house.

signal state_changed(new_state: int)

enum { HUB, COUNTDOWN, PLAYING, ROUND_END }

const ROUND_TIME := 150.0   # 2.5 minutes of play
const COUNTDOWN_TIME := 3.0
const RESULT_TIME := 6.0
const HILL_RADIUS := 4.5
const HILL_Y_TOLERANCE := 2.5 # count as "on the hill" within this of hill height

## The rotating list of hill spots (surface y). Advances one step per round, so
## it's deterministic -- same order every session, no runtime randomness.
const HILL_SPOTS: Array[Vector3] = [
	Vector3(0, 0, -10),    # town plaza, south of the lever-door wall
	Vector3(-35, 0, 28),   # farm field
	Vector3(44, 0, 30),    # forest clearing
	Vector3(-42, 0, -40),  # snowy hills
]

var state: int = HUB
var timer: float = 0.0             # counts down within COUNTDOWN/PLAYING/ROUND_END
var hill_index: int = -1
var hill_center: Vector3 = Vector3.ZERO
var king_id: int = -1              # sole occupant right now, or -1
var control_time: Dictionary = {}  # peer_id -> seconds held this round
var session_wins: Dictionary = {}  # peer_id -> rounds won this session
var last_winner: int = -1

var _marker: Node3D = null


func reset_session() -> void:
	state = HUB
	king_id = -1
	control_time.clear()
	session_wins.clear()
	last_winner = -1
	hill_index = -1


## Server-only. Called by the crown (see crown.gd). Ignored unless we're idle in
## the hub with at least one player around.
func start_round() -> void:
	if not multiplayer.is_server() or state != HUB:
		return
	hill_index = (hill_index + 1) % HILL_SPOTS.size()
	hill_center = HILL_SPOTS[hill_index]
	control_time.clear()
	king_id = -1
	timer = COUNTDOWN_TIME
	_set_state(COUNTDOWN)


## Server-only, ticked every physics frame by the World.
func tick(delta: float) -> void:
	match state:
		COUNTDOWN:
			timer -= delta
			if timer <= 0.0:
				timer = ROUND_TIME
				_set_state(PLAYING)
		PLAYING:
			_update_king(delta)
			timer -= delta
			if timer <= 0.0:
				_finish_round()
		ROUND_END:
			timer -= delta
			if timer <= 0.0:
				king_id = -1
				_set_state(HUB)


func _update_king(delta: float) -> void:
	var on_hill: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		var d := Vector2(p.global_position.x - hill_center.x, p.global_position.z - hill_center.z)
		if d.length() <= HILL_RADIUS and absf(p.global_position.y - hill_center.y) <= HILL_Y_TOLERANCE:
			on_hill.append(p.peer_id)
	# Only a SOLE occupant is king and banks time; empty or contested = nobody.
	if on_hill.size() == 1:
		king_id = on_hill[0]
		control_time[king_id] = float(control_time.get(king_id, 0.0)) + delta
	else:
		king_id = -1


func _finish_round() -> void:
	var best := -1
	var best_t := 0.0
	for id in control_time:
		if control_time[id] > best_t:
			best_t = control_time[id]
			best = id
	last_winner = best
	if best != -1:
		session_wins[best] = int(session_wins.get(best, 0)) + 1
	timer = RESULT_TIME
	_set_state(ROUND_END)


func _set_state(s: int) -> void:
	state = s
	state_changed.emit(s)


## --- networking: folded into the World snapshot ---------------------------

func net_state() -> Dictionary:
	return {
		"st": state, "t": timer, "hill": hill_center, "king": king_id,
		"ctrl": control_time.duplicate(), "wins": session_wins.duplicate(),
		"win": last_winner,
	}


func apply_net_state(d: Dictionary) -> void:
	# Clients mirror the server's round state for HUD + marker.
	state = d["st"]
	timer = d["t"]
	hill_center = d["hill"]
	king_id = d["king"]
	control_time = d["ctrl"]
	session_wins = d["wins"]
	last_winner = d["win"]


## --- the hill marker (local visual on every peer, driven by hill_center) ---

func _process(_delta: float) -> void:
	var show := state == COUNTDOWN or state == PLAYING
	if show and _marker == null:
		_marker = _make_marker()
		add_child(_marker)
	if _marker:
		_marker.visible = show
		if show and _marker.is_inside_tree():
			_marker.global_position = hill_center + Vector3(0, 0.06, 0)


func _make_marker() -> Node3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = HILL_RADIUS - 0.35
	torus.outer_radius = HILL_RADIUS
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.15)
	mat.emission_energy_multiplier = 0.8
	ring.material_override = mat
	return ring
