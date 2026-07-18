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
## Which game the current round is. KotH is the hub control-point game; BOSS is
## the co-op Goblin Siege in the dungeon arena; RAID is the co-op Water Dragon
## fight in the flooded arena (the World arms/resets the dragon on the
## COUNTDOWN/PLAYING/ROUND_END transitions). The round state machine and timer
## below are shared; `mode` just picks what PLAYING actually does and what the
## HUD/marker show.
enum Mode { KOTH, BOSS, RAID }

const ROUND_TIME := 150.0   # 2.5 minutes of play (KotH / Goblin Siege)
const RAID_TIME := 300.0    # 5 minutes for the Water Dragon raid
const COUNTDOWN_TIME := 3.0
const RESULT_TIME := 6.0
const HILL_RADIUS := 4.5
const HILL_Y_TOLERANCE := 2.5 # count as "on the hill" within this of hill height
## Mid-round hill relocation: the hill moves every HILL_SHIFT_TIME seconds, so
## a ROUND_TIME of 150 gives exactly 3 hills per round. Control time carries
## across shifts -- the round's total decides the winner.
const HILL_SHIFT_TIME := 50.0

## The rotating list of hill spots (surface y). Advances one step per shift
## (and round to round), so it's deterministic -- same order every session,
## no runtime randomness.
const HILL_SPOTS: Array[Vector3] = [
	Vector3(0, 0, -10),    # town plaza, south of the lever-door wall
	Vector3(-35, 0, 28),   # farm field
	Vector3(44, 0, 30),    # forest clearing
	Vector3(-42, 0, -40),  # snowy hills
]

var state: int = HUB
var mode: int = Mode.KOTH
var timer: float = 0.0             # counts down within COUNTDOWN/PLAYING/ROUND_END
var hill_index: int = -1
var hill_center: Vector3 = Vector3.ZERO
var hill_shift_timer: float = 0.0  # counts down to the next mid-round hill move
var king_id: int = -1              # sole occupant right now, or -1
var control_time: Dictionary = {}  # peer_id -> seconds held this round
var session_wins: Dictionary = {}  # peer_id -> rounds won this session
var last_winner: int = -1

# Boss fight (Goblin Siege). `participants` are the peers in the arena when it
# went live (set by the World at PLAYING); the round is lost if they're all out.
var participants: Array = []
var boss_won := false

var _marker: Node3D = null


func reset_session() -> void:
	state = HUB
	mode = Mode.KOTH
	king_id = -1
	control_time.clear()
	session_wins.clear()
	last_winner = -1
	hill_index = -1
	participants.clear()
	boss_won = false


## Server-only. Called by the crown (see crown.gd). Ignored unless we're idle in
## the hub with at least one player around.
func start_round() -> void:
	if not multiplayer.is_server() or state != HUB:
		return
	mode = Mode.KOTH
	_advance_hill()
	control_time.clear()
	king_id = -1
	timer = COUNTDOWN_TIME
	_set_state(COUNTDOWN)


## Server-only. Called by the skull-on-a-stake just past the arena entrance (see
## skull_stake.gd). Kicks off the co-op Goblin Siege: the World spawns the frozen
## enemy wave when we enter COUNTDOWN and turns it loose at PLAYING.
func start_boss_fight() -> void:
	if not multiplayer.is_server() or state != HUB:
		return
	mode = Mode.BOSS
	control_time.clear()
	participants.clear()
	boss_won = false
	king_id = -1
	timer = COUNTDOWN_TIME
	_set_state(COUNTDOWN)


## Server-only. Called by the skull-on-a-stake on the flooded arena's entrance
## ledge (see skull_stake.gd). Kicks off the co-op Water Dragon raid: the World
## rouses the dormant dragon at PLAYING and resets it at ROUND_END. Same round
## machinery as the Goblin Siege, just a 5-minute clock and a different win test.
func start_dragon_raid() -> void:
	if not multiplayer.is_server() or state != HUB:
		return
	mode = Mode.RAID
	control_time.clear()
	participants.clear()
	boss_won = false
	king_id = -1
	timer = COUNTDOWN_TIME
	_set_state(COUNTDOWN)


## Server-only, ticked every physics frame by the World.
func tick(delta: float) -> void:
	match state:
		COUNTDOWN:
			timer -= delta
			if timer <= 0.0:
				timer = RAID_TIME if mode == Mode.RAID else ROUND_TIME
				hill_shift_timer = HILL_SHIFT_TIME
				_set_state(PLAYING)
		PLAYING:
			if mode == Mode.KOTH:
				_update_king(delta)
				# The hill relocates every HILL_SHIFT_TIME; skip the shift that
				# would coincide with the round's own end.
				hill_shift_timer -= delta
				if hill_shift_timer <= 0.0 and timer > HILL_SHIFT_TIME * 0.5:
					hill_shift_timer = HILL_SHIFT_TIME
					_advance_hill()
				timer -= delta
				if timer <= 0.0:
					_finish_round()
			elif mode == Mode.BOSS:
				# Goblin Siege: win when the whole horde is ringed out; lose if
				# every participant is out, or the clock runs out with enemies alive.
				if get_tree().get_nodes_in_group("arena_enemy").is_empty():
					_finish_boss(true)
				elif not participants.is_empty() and _alive_participants() == 0:
					_finish_boss(false)
				else:
					timer -= delta
					if timer <= 0.0:
						_finish_boss(false)
			else:
				# Water Dragon raid: win when the dragon is slain; lose if every
				# participant is out, or the 5-minute clock runs out first.
				if _dragon_defeated():
					_finish_boss(true)
				elif not participants.is_empty() and _alive_participants() == 0:
					_finish_boss(false)
				else:
					timer -= delta
					if timer <= 0.0:
						_finish_boss(false)
		ROUND_END:
			timer -= delta
			if timer <= 0.0:
				king_id = -1
				_set_state(HUB)


func _advance_hill() -> void:
	hill_index = (hill_index + 1) % HILL_SPOTS.size()
	hill_center = HILL_SPOTS[hill_index]


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


func _finish_boss(won: bool) -> void:
	boss_won = won
	last_winner = -1
	timer = RESULT_TIME
	_set_state(ROUND_END)


## Has the water dragon been beaten? (Raid win condition.)
func _dragon_defeated() -> bool:
	for d in get_tree().get_nodes_in_group("sync_dragon"):
		if d.is_defeated():
			return true
	return false


## How many of the arena's participants are still in the fight (not spectating).
func _alive_participants() -> int:
	var n := 0
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id in participants and not p.spectating:
			n += 1
	return n


func _set_state(s: int) -> void:
	state = s
	state_changed.emit(s)


## --- networking: folded into the World snapshot ---------------------------

func net_state() -> Dictionary:
	return {
		"st": state, "md": mode, "t": timer, "hill": hill_center, "king": king_id,
		"ctrl": control_time.duplicate(), "wins": session_wins.duplicate(),
		"win": last_winner, "bwon": boss_won, "hst": hill_shift_timer,
	}


func apply_net_state(d: Dictionary) -> void:
	# Clients mirror the server's round state for HUD + marker.
	state = d["st"]
	mode = d["md"]
	timer = d["t"]
	hill_center = d["hill"]
	king_id = d["king"]
	control_time = d["ctrl"]
	session_wins = d["wins"]
	last_winner = d["win"]
	boss_won = d["bwon"]
	hill_shift_timer = d["hst"]


## --- the hill marker (local visual on every peer, driven by hill_center) ---

func _process(_delta: float) -> void:
	# Only KotH has a hill ring; the boss fight has no marker.
	var show := mode == Mode.KOTH and (state == COUNTDOWN or state == PLAYING)
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
