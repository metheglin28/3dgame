extends CharacterBody3D
## A completely harmless wandering NPC. The server drives its "AI" (walk to a random
## nearby point, pause, repeat) and every peer renders it from the position snapshot
## the World broadcasts each frame, same as players and items. Talking to it is
## purely cosmetic: the server picks a random line and every peer is told to display
## it above the NPC's head at the same time.

const WANDER_RADIUS := 6.0
const SPEED := 2.0
const PAUSE_TIME := 2.0
const SPEECH_DURATION := 2.5

const DEFAULT_LINES: Array[String] = [
	"I used to be an adventurer, then I took a nap instead.",
	"Have you tried turning yourself off and on again?",
	"This grass isn't going to stand on itself.",
	"I'm not lost. I'm exploring my own front yard.",
	"Nice weather we're having, for the third day in a row.",
	"Don't mind me, just doing NPC things.",
]

@export var npc_name: String = "Some Guy"
@export var lines: Array[String] = []

@onready var name_label: Label3D = $NameLabel
@onready var speech_label: Label3D = $SpeechLabel

var _home: Vector3
var _target: Vector3
var _pause_timer := 0.0

# Latest server snapshot, smoothed toward in _process on non-server peers.
var _net_pos_target: Vector3
var _net_rot_target := 0.0
var _has_net_state := false
const NET_SMOOTH_RATE := 18.0
const NET_SNAP_DISTANCE := 4.0


func _ready() -> void:
	add_to_group("npc")
	name_label.text = npc_name
	if lines.is_empty():
		lines = DEFAULT_LINES
	speech_label.visible = false
	if multiplayer.is_server():
		_home = global_position
		_target = _home
		set_physics_process(true)
	else:
		set_physics_process(false)


func on_interact(_by: Node3D) -> void:
	if not multiplayer.is_server():
		return
	var line: String = lines[randi() % lines.size()]
	_say.rpc(line)


func get_interact_prompt() -> String:
	return "Talk"


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	else:
		velocity.y = 0.0

	var to_target := _target - global_position
	to_target.y = 0.0
	if to_target.length() < 0.3:
		_pause_timer -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if _pause_timer <= 0.0:
			_pick_new_target()
	else:
		var dir := to_target.normalized()
		velocity.x = dir.x * SPEED
		velocity.z = dir.z * SPEED
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 8.0 * delta)

	move_and_slide()


func _pick_new_target() -> void:
	var angle := randf() * TAU
	var dist := randf() * WANDER_RADIUS
	_target = _home + Vector3(cos(angle) * dist, 0, sin(angle) * dist)
	_pause_timer = PAUSE_TIME


@rpc("authority", "call_local", "reliable")
func _say(line: String) -> void:
	speech_label.text = line
	speech_label.visible = true
	await get_tree().create_timer(SPEECH_DURATION).timeout
	speech_label.visible = false


func apply_remote_state(state: Dictionary) -> void:
	_net_pos_target = state["pos"]
	_net_rot_target = state["rot"]
	_has_net_state = true


func _process(delta: float) -> void:
	# Same snapshot smoothing as the player (see player.gd) -- NPCs otherwise
	# visibly stutter on clients when unreliable snapshot packets bunch up.
	if multiplayer.is_server() or not _has_net_state:
		return
	if global_position.distance_to(_net_pos_target) > NET_SNAP_DISTANCE:
		global_position = _net_pos_target
		rotation.y = _net_rot_target
		return
	var w := 1.0 - exp(-NET_SMOOTH_RATE * delta)
	global_position = global_position.lerp(_net_pos_target, w)
	rotation.y = lerp_angle(rotation.y, _net_rot_target, w)
