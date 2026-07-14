extends CharacterBody3D
## A wandering NPC. The server drives its "AI" (walk to a random nearby point,
## pause, repeat) and every peer renders it from the position snapshot the
## World broadcasts each frame, same as players and items. Talking to it is
## purely cosmetic: the server picks a random line and every peer is told to
## display it above the NPC's head at the same time.
##
## Combat: NPCs don't have health -- getting hit means getting RAGDOLLED
## (apply_knockback): control cut, launched with weapon-specific force,
## tumbling end over end until they land, then they get up and carry on. The
## tumble angle rides the same snapshot as position so every peer sees the
## same flip.

const PAUSE_TIME := 2.0
const SPEECH_DURATION := 2.5
const RAGDOLL_MIN_TIME := 1.1
const HIT_IMMUNITY := 0.8
const TUMBLE_SPEED := 9.0

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
# Exported (not consts) so cave dwellers like the goblins can be given a
# leash short enough to keep them in their own room, and their own gait.
@export var wander_radius := 6.0
@export var speed := 2.0

@onready var name_label: Label3D = $NameLabel
@onready var speech_label: Label3D = $SpeechLabel
@onready var mesh: MeshInstance3D = $Mesh

# Labels fade in only when the local player is near (see GameState). `_speaking`
# gates the speech bubble on top of that; `_speech_rgb` preserves its tint.
var _speaking := false
var _speech_rgb := Color.WHITE

var _home: Vector3
var _target: Vector3
var _pause_timer := 0.0

# Ragdoll state. `tumble` is the mesh's mid-air pitch, synced to all peers.
var tumble := 0.0
var _ragdolled := false
var _ragdoll_timer := 0.0
var _hit_immunity := 0.0

# Frozen: used by the boss round's countdown -- the spawned wave stands still and
# intangible (collision off) until the fight goes live. Server-side only; clients
# just render the (unmoving) snapshot position.
var frozen := false

# Shove (snowball): a brief burst of velocity the AI can't override -- no
# ragdoll, no immunity. Slow (also the snowball): grounded movement scaled down
# for a few seconds, shown everywhere as a frost-blue tint (the `slow` flag
# rides the npc snapshot). The troll inherits both, so snowballs are a real
# counter in the boss fight.
const SHOVE_SCALE := 0.6
const SHOVE_TIME := 0.35
const SLOW_MULT := 0.55
# Slowed targets blend toward ONE shared frost blue -- a moderate blend keeps
# identity, and lifting the blue channel to ~red guarantees even warm colors
# (the orange player) read cool rather than merely washed out.
const FROST_COLOR := Color(0.5, 0.7, 1.0)
const FROST_BLEND := 0.45
# Dark bodies (the troll) would otherwise LIGHTEN dramatically under the blend;
# cap the frost target's brightness at 1.5x the target's own luminance so the
# chill cools everyone by a comparable amount instead.
const FROST_MAX_BRIGHTEN := 1.5
var _push_timer := 0.0
var _slow_timer := 0.0
var _slow_tinted := false
var _pre_slow_material: Material = null

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
	_speech_rgb = speech_label.modulate
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


## Server-only entry point for any weapon/ability that hits this NPC. `power`
## is the weapon's knockback strength -- this is where "different weapons have
## varying knockback" plugs in. Launches up-and-away, cuts AI control until
## they've landed and the timer has run out. A short immunity window stops a
## flying NPC being juggled indefinitely.
## Server-side freeze toggle for the boss countdown: turn collision off so
## players pass through, and (via _physics_process) hold still. Restores the
## scene's collision layer (8) when the fight goes live.
func set_frozen(v: bool) -> void:
	frozen = v
	collision_layer = 0 if v else 8


func apply_knockback(dir: Vector3, power: float, ragdoll_time: float = RAGDOLL_MIN_TIME) -> void:
	if not multiplayer.is_server():
		return
	if frozen or _hit_immunity > 0.0:
		return
	_hit_immunity = HIT_IMMUNITY
	_ragdolled = true
	_ragdoll_timer = ragdoll_time
	var flat := (dir * Vector3(1, 0, 1)).normalized()
	velocity = flat * power + Vector3.UP * power * 0.6


## Server-only. A troll-style hit: pushed back with the AI briefly locked out,
## but no ragdoll and no immunity. The snowball's punch.
func apply_shove(dir: Vector3, power: float) -> void:
	if not multiplayer.is_server() or frozen:
		return
	var flat := (dir * Vector3(1, 0, 1)).normalized()
	velocity.x = flat.x * power * SHOVE_SCALE
	velocity.z = flat.z * power * SHOVE_SCALE
	_push_timer = SHOVE_TIME


## Server-only. Slow this NPC's movement for `duration` seconds (refreshes,
## doesn't stack). Tint is applied in _physics_process and mirrored to clients
## through the snapshot's `slow` flag.
func apply_slow(duration: float) -> void:
	if not multiplayer.is_server() or frozen:
		return
	_slow_timer = maxf(_slow_timer, duration)


func is_slowed() -> bool:
	return _slow_timer > 0.0


## Frost-blue tint while slowed: a cold-shifted copy of the active body material
## (so each goblin keeps its own green), swapped in as an override and restored
## after. Runs on the server and, via the snapshot flag, on every client.
func set_slow_tint(v: bool) -> void:
	if v == _slow_tinted:
		return
	_slow_tinted = v
	if v:
		_pre_slow_material = mesh.material_override
		var base := mesh.get_active_material(0)
		var frost := StandardMaterial3D.new()
		if base is StandardMaterial3D:
			frost = (base as StandardMaterial3D).duplicate()
			var c: Color = frost.albedo_color
			var frost_target := FROST_COLOR
			var frost_lum := FROST_COLOR.get_luminance()
			if frost_lum > c.get_luminance() * FROST_MAX_BRIGHTEN:
				frost_target = FROST_COLOR * (c.get_luminance() * FROST_MAX_BRIGHTEN / frost_lum)
				frost_target.a = 1.0
			var cold := c.lerp(frost_target, FROST_BLEND)
			cold.b = maxf(cold.b, cold.r * 0.95)
			frost.albedo_color = Color(cold, c.a)
		else:
			frost.albedo_color = FROST_COLOR
		mesh.material_override = frost
	else:
		mesh.material_override = _pre_slow_material


func _physics_process(delta: float) -> void:
	if frozen:
		velocity = Vector3.ZERO
		return
	_hit_immunity = maxf(_hit_immunity - delta, 0.0)
	_slow_timer = maxf(_slow_timer - delta, 0.0)
	set_slow_tint(_slow_timer > 0.0)
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	elif not _ragdolled:
		velocity.y = 0.0

	if _ragdolled:
		_ragdoll_timer -= delta
		tumble += TUMBLE_SPEED * delta
		mesh.rotation.x = tumble
		if is_on_floor():
			# Skid to a stop once down; get up when the timer allows.
			velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 14.0 * delta)
			if _ragdoll_timer <= 0.0:
				_ragdolled = false
				tumble = 0.0
				mesh.rotation.x = 0.0
				_pause_timer = PAUSE_TIME # sit dazed a moment, then carry on
		move_and_slide()
		return

	# Shoved (snowball): the push carries us for a beat, AI locked out.
	if _push_timer > 0.0:
		_push_timer -= delta
		if is_on_floor():
			velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 14.0 * delta)
		move_and_slide()
		return

	_ai(delta)
	# Chilled: the AI's chosen walk (wander or chase, goblin or troll alike)
	# runs slower. Deliberately NOT applied to ragdoll/shove flight above, so a
	# slow never weakens a knockback in progress.
	if _slow_timer > 0.0:
		velocity.x *= SLOW_MULT
		velocity.z *= SLOW_MULT
	move_and_slide()


## The upright brain, called every physics tick when not ragdolled (gravity
## and knockback recovery are already handled). The default is the harmless
## wander; subclasses override this for less harmless behavior (see goblin.gd)
## and can fall back to `super(delta)` to wander when idle.
func _ai(delta: float) -> void:
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
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 8.0 * delta)


func _pick_new_target() -> void:
	var angle := randf() * TAU
	var dist := randf() * wander_radius
	_target = _home + Vector3(cos(angle) * dist, 0, sin(angle) * dist)
	_pause_timer = PAUSE_TIME


@rpc("authority", "call_local", "reliable")
func _say(line: String) -> void:
	speech_label.text = line
	_speaking = true
	await get_tree().create_timer(SPEECH_DURATION).timeout
	_speaking = false


func apply_remote_state(state: Dictionary) -> void:
	_net_pos_target = state["pos"]
	_net_rot_target = state["rot"]
	_has_net_state = true
	tumble = state["tumble"]
	mesh.rotation.x = tumble
	set_slow_tint(state["slow"])


func _process(delta: float) -> void:
	_update_labels()
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


## Fade the name tag (and speech bubble, when talking) by the local player's
## distance. Runs on every peer, including the host -- hence before _process's
## server early-return. Goblins keep their name label hidden (visible=false in
## the scene), so this only ever pushes alpha on a node that's already hidden;
## nothing reveals it.
func _update_labels() -> void:
	var a := GameState.label_alpha(global_position)
	name_label.modulate.a = a
	speech_label.visible = _speaking and a > 0.01
	if speech_label.visible:
		speech_label.modulate = Color(_speech_rgb.r, _speech_rgb.g, _speech_rgb.b, a)
