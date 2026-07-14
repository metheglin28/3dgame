extends CharacterBody3D
## Third-person player. Movement is server-authoritative: whichever client owns this
## node (peer_id == the local player) reads Input and streams it to the server; the
## server runs the actual physics and everyone (including the owner) renders from the
## snapshot the World broadcasts every physics frame. On a LAN the round trip is small
## enough that this stays feel-good without needing client-side prediction.

const SPEED := 5.5
const SPRINT_MULTIPLIER := 1.7
const ACCEL := 10.0
const DECEL := 12.0
const JUMP_VELOCITY := 6.5
const COYOTE_TIME := 0.15
const JUMP_BUFFER_TIME := 0.15
const MOUSE_SENSITIVITY := 0.0035
const ZOOM_STEP := 0.6
const MIN_ZOOM := 1.5
const MAX_ZOOM := 8.0
const INTERACT_RANGE := 3.0
const WIZARD_HAT_VISUAL := preload("res://scripts/wizard_hat_visual.gd")

@export var peer_id: int = 1

var display_name: String = "Player"
var camera_yaw: float = 0.0
var camera_pitch: float = 0.0
var current_interactable: Node = null
var carried_item_path: NodePath = NodePath("")

## Snowball-throwing power, granted/revoked by talking to the snowman in the
## snowy hills (see snowman.gd). Server-authoritative like everything else;
## broadcast to every peer via the same per-player snapshot as position, so
## the hat shows up for everyone, not just the wearer. A setter drives the
## visual directly because _apply_snapshot is call_remote (never invoked on
## the server itself), so the host's own hat has no other update path.
var wearing_hat: bool = false:
	set(value):
		wearing_hat = value
		if hat:
			hat.visible = value

## Sword-swinging power, granted/revoked by pulling the sword from the stone
## in the forest (see sword_stone.gd). Same setter-drives-the-visual pattern
## as wearing_hat, and same snapshot-based sync. All the powers are mutually
## exclusive (each granter clears the others) so a click always unambiguously
## means one thing: throw held item > snowball > sword swing > revolver shot.
var wearing_helmet: bool = false:
	set(value):
		wearing_helmet = value
		if helmet:
			helmet.visible = value
		if sword:
			sword.visible = value

## Revolver power, granted/revoked at the coat rack deep in the canyon maze
## (see coat_rack.gd). Cowboy hat on the head, revolver at the hip.
var wearing_cowboy_hat: bool = false:
	set(value):
		wearing_cowboy_hat = value
		if cowboy_hat:
			cowboy_hat.visible = value
		if revolver:
			revolver.visible = value

# Server-side revolver rate limit.
var _shoot_cooldown: float = 0.0
const SHOOT_COOLDOWN := 0.55

# Server-side snowball-throw rate limit -- the snowball used to be harmless so
# it had none; now that it shoves and slows, spam needs a cap.
var _throw_ball_cooldown: float = 0.0
const THROW_BALL_COOLDOWN := 0.5

## Bunny-ears power, granted at the goblin cave's treasure chest (see
## chest.gd). While worn, your base jump is 1.5x, and every consecutive
## bounce (re-jumping the instant you land) stacks another BOUNCE_STEP on top,
## higher and higher with no cap. Miss the rhythm -- land and dawdle past
## BOUNCE_WINDOW without jumping -- and the streak drops back to the 1.5x base.
var wearing_bunny_ears: bool = false:
	set(value):
		wearing_bunny_ears = value
		if bunny_ears:
			bunny_ears.visible = value
		if not value:
			_bounce_mult = 1.0
## Wizard-hat power, granted by the hat sitting in the woods (see
## wizard_hat_pickup.gd). While worn, click to cast a blue lightning bolt --
## moderate knockback, but it leaves whatever it hits ragdolling far longer than
## a normal hit. Same setter-drives-the-visual + snapshot-sync pattern; the hat
## itself is built in code (WizardHatVisual) in _ready.
var wearing_wizard_hat: bool = false:
	set(value):
		wearing_wizard_hat = value
		if wizard_hat:
			wizard_hat.visible = value
const CAST_COOLDOWN := 0.5
var _cast_cooldown: float = 0.0

# The lunar low-gravity band: any airtime above LOW_GRAV_Y falls softly. Only
# the secret moon area (and the teleport arrival above it) lives that high.
const LOW_GRAV_Y := 150.0
const LOW_GRAV_MULT := 0.35

const BUNNY_JUMP_BASE := 1.2247 # = sqrt(1.5): a 1.5x jump HEIGHT (height goes as velocity^2)
const BOUNCE_STEP := 1.12      # each in-rhythm bounce multiplies jump by this
const BOUNCE_WINDOW := 0.25    # re-jump within this long of landing to keep the streak
var _bounce_mult: float = 1.0  # server-side; grows per consecutive bounce
var _time_since_land: float = 0.0
var _was_on_floor: bool = false

# Server-side swing rate limit; also drives the swing animation duration.
var _swing_cooldown: float = 0.0
const SWING_COOLDOWN := 0.5
const SWING_RANGE := 2.6
const SWING_PUSH := 10.0       # knockback on physics props
const SWING_KNOCKBACK := 11.0  # knockback on characters (goblins, players)

# Ragdoll state, same slapstick combat rules as NPCs (see npc.gd): no health,
# a hit just cuts your controls and launches you tumbling until you land and
# get back up. Simulated entirely on the server -- while ragdolled the
# server ignores this player's streamed movement input; the owning client
# doesn't need to know or cooperate. `tumble` (mesh pitch) rides the normal
# per-player snapshot so every peer sees the same flip.
var tumble := 0.0
var ragdolled := false
var _ragdoll_timer := 0.0
var _hit_immunity := 0.0
const RAGDOLL_MIN_TIME := 1.1
const HIT_IMMUNITY := 0.8
const TUMBLE_SPEED := 9.0

# Shove (snowball hit): a brief no-control push -- no tumble, no immunity,
# same feel as shoving the troll. Slow (also the snowball): movement scaled
# down for a few seconds, shown to everyone as a frost-blue body tint (the
# `slow` flag rides the per-player snapshot).
const SHOVE_SCALE := 0.6
const SHOVE_TIME := 0.35
const SLOW_MULT := 0.55         # 45% slower
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

# Input latched by the owning client, applied by the server.
var _pending_move: Vector2 = Vector2.ZERO
var _pending_sprint: bool = false
var _jump_buffer_timer: float = 0.0
var _coyote_timer: float = 0.0

# Per-player feel multipliers, applied by the SERVER during simulation. The
# owning client pushes its Settings values here via _set_feel (server clamps
# them to the same ranges the options sliders allow).
var _accel_mult: float = 1.0
var _jump_mult: float = 1.0

# Purely cosmetic squash-and-stretch, driven off observed vertical position
# rather than the server's real velocity -- that way it works identically
# whether this Player instance is being physically simulated (the server) or
# just rendered from the snapshot (everyone else), with no networking needed.
var _prev_y: float = 0.0
var _fall_speed: float = 0.0
var _time_since_y_change: float = 0.0
const LAND_SQUASH_THRESHOLD := -3.0

# Latest server snapshot, rendered via exponential smoothing on non-server
# peers so motion stays fluid even when unreliable snapshot packets bunch up.
var _net_pos_target: Vector3
var _net_rot_target: float = 0.0
var _has_net_state: bool = false
const NET_SMOOTH_RATE := 18.0
const NET_SNAP_DISTANCE := 4.0

@onready var mesh: MeshInstance3D = $Mesh
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
# The interact ray deliberately does NOT live under the third-person Camera3D:
# the spring arm holds that camera several meters behind the player, so a short
# ray cast from there would never reach back past the player's own body, let
# alone anything they're looking at. AimPivot mirrors the camera's yaw/pitch
# but stays at the player's head position, so the ray actually reaches forward.
@onready var aim_pivot: Node3D = $CameraPivot/AimPivot
@onready var interact_ray: RayCast3D = $CameraPivot/AimPivot/InteractRay
@onready var name_label: Label3D = $NameLabel
# Under the mesh so carried items swing around to stay in front of the
# character as it turns to face its movement.
@onready var hold_point: Marker3D = $Mesh/HoldPoint
@onready var hat: Node3D = $Mesh/Hat
@onready var helmet: Node3D = $Mesh/Helmet
# SwordPivot sits at the shoulder and the sword hangs off it, so tweening the
# pivot's rotation swings the blade through an arc instead of spinning it in place.
@onready var sword: Node3D = $Mesh/SwordPivot
@onready var cowboy_hat: Node3D = $Mesh/CowboyHat
@onready var revolver: Node3D = $Mesh/RevolverPivot
@onready var bunny_ears: Node3D = $Mesh/BunnyEars
@onready var wizard_hat: Node3D = $Mesh/WizardHat
@onready var prompt_label: Label = $HUD/InteractPrompt
@onready var leave_button: Button = $HUD/LeaveButton
@onready var options_button: Button = $HUD/OptionsButton
@onready var options_menu: Control = $HUD/OptionsMenu
@onready var player_list_label: Label = $HUD/PlayerListLabel
@onready var round_label: Label = $HUD/RoundLabel
@onready var spectator_cam: Camera3D = $SpectatorCam

# Spectator: set (server-authoritative) when this player falls out during a boss
# fight. Synced to all peers so the body hides everywhere; the owning client
# swaps to a chase-cam that follows a living teammate (click to cycle).
var spectating := false
var _spec_target: Node3D = null


func _ready() -> void:
	add_to_group("players")
	WIZARD_HAT_VISUAL.build(wizard_hat)
	wizard_hat.visible = wearing_wizard_hat
	name_label.text = display_name
	# A newly-joined peer's chosen name hasn't necessarily round-tripped back to
	# whoever is spawning this node yet (spawning happens right when the ENet
	# connection completes; name registration is a separate RPC that arrives
	# slightly later), so `display_name` is very often still the "Player"
	# fallback at this point. Self-correct once/if the real name shows up.
	NetworkManager.player_connected.connect(_on_player_registered)
	var is_local := peer_id == multiplayer.get_unique_id()
	camera.current = is_local
	$HUD.visible = is_local
	if is_local:
		GameState.capture_mouse()
		NetworkManager.player_connected.connect(func(_id, _name): _refresh_player_list())
		NetworkManager.player_disconnected.connect(func(_id): _refresh_player_list())
		_refresh_player_list()
		leave_button.pressed.connect(_on_leave_pressed)
		options_button.pressed.connect(func(): options_menu.visible = not options_menu.visible)
		Settings.changed.connect(_apply_settings)
		_apply_settings()
	# _physics_process always stays enabled, even on non-server peers: it's also
	# where the *local* player reads Input and streams it to the server (see
	# below). Only the actual movement simulation later in that function is
	# gated behind `multiplayer.is_server()`.


func _unhandled_input(event: InputEvent) -> void:
	if peer_id != multiplayer.get_unique_id():
		return
	if event is InputEventMouseMotion and GameState.mouse_captured:
		var sens: float = Settings.BASE_SENSITIVITY * Settings.sens_mult
		var dy: float = event.relative.y * sens
		if Settings.invert_y:
			dy = -dy
		camera_yaw -= event.relative.x * sens
		camera_pitch = clamp(camera_pitch - dy, -1.2, 1.0)
		camera_pivot.rotation.y = camera_yaw
		spring_arm.rotation.x = camera_pitch
		aim_pivot.rotation.x = camera_pitch
	if event is InputEventMouseButton and event.pressed:
		# Zoom routes through Settings (still local-only) so the wheel and the
		# options slider stay in sync and the preference persists.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			Settings.camera_distance = clampf(Settings.camera_distance - ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
			Settings.notify_changed()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			Settings.camera_distance = clampf(Settings.camera_distance + ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
			Settings.notify_changed()
	if event.is_action_pressed("toggle_mouse"):
		GameState.toggle_mouse()
		if GameState.mouse_captured:
			options_menu.hide()
	# While spectating, a click just switches which teammate you're watching --
	# no interacting or throwing from the sidelines.
	if spectating:
		if event.is_action_pressed("throw") or event.is_action_pressed("interact"):
			_cycle_spec_target()
		return
	if event.is_action_pressed("interact"):
		_request_interact.rpc_id(1)
	if event.is_action_pressed("throw"):
		_request_throw.rpc_id(1)


func _on_player_registered(id: int, registered_name: String) -> void:
	if id == peer_id:
		display_name = registered_name
		name_label.text = display_name


## Local player only: apply Settings to the camera immediately and ship the
## movement-feel multipliers to the server, which simulates us.
## (Mouse sensitivity/invert are read live in _unhandled_input.)
func _apply_settings() -> void:
	spring_arm.spring_length = clampf(Settings.camera_distance, MIN_ZOOM, MAX_ZOOM)
	_set_feel.rpc_id(1, Settings.accel_mult, Settings.jump_mult)


@rpc("any_peer", "call_local", "reliable")
func _set_feel(accel_mult: float, jump_mult: float) -> void:
	if not multiplayer.is_server():
		return
	if _verified_sender_id() != peer_id:
		return
	# Clamp to the same ranges the options sliders offer, so a modified client
	# can't grant itself moon-gravity jumps.
	_accel_mult = clampf(accel_mult, Settings.ACCEL_RANGE.x, Settings.ACCEL_RANGE.y)
	_jump_mult = clampf(jump_mult, Settings.JUMP_RANGE.x, Settings.JUMP_RANGE.y)


func _on_leave_pressed() -> void:
	# Works the same whether this player is the host or a joined client:
	# closing our own peer either shuts the server down (dropping everyone
	# else too) or just disconnects us, and either way we land back on the menu.
	GameState.release_mouse()
	GameDirector.reset_session() # so the hill ring / round state doesn't linger
	NetworkManager.leave_game()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _refresh_player_list() -> void:
	var lines := ["Players Online:"]
	for id in NetworkManager.player_names:
		lines.append("- " + str(NetworkManager.player_names[id]))
	player_list_label.text = "\n".join(lines)


func _process(delta: float) -> void:
	_smooth_to_net_state(delta)
	_update_squash_stretch(delta)
	# Fade this player's name tag by the local player's distance, same rule as
	# NPC labels (see GameState) -- so you don't read everyone's name across the
	# whole map. Runs for every player node; the local one sits at distance ~0
	# and so stays fully visible.
	name_label.modulate.a = GameState.label_alpha(global_position)
	if peer_id != multiplayer.get_unique_id():
		return
	if spectating:
		_update_spectator_cam()
		_update_round_hud()
		return
	# Local-only "am I looking at something?" check purely for the UI prompt text;
	# the server does its own raycast before actually running the interaction.
	if interact_ray.is_colliding():
		var collider := interact_ray.get_collider()
		if collider and collider.is_in_group("interactable"):
			current_interactable = collider
		else:
			current_interactable = null
	else:
		current_interactable = null
	prompt_label.visible = current_interactable != null
	if current_interactable:
		prompt_label.text = "[E] " + current_interactable.get_prompt()
	_update_round_hud()


## Draws the King of the Hill banner/scoreboard from the synced GameDirector
## state (local player only). Plain text keeps the HUD change tiny.
func _update_round_hud() -> void:
	if GameDirector.mode == GameDirector.Mode.BOSS:
		_update_boss_hud()
		return
	match GameDirector.state:
		GameDirector.HUB:
			if GameDirector.session_wins.is_empty():
				round_label.text = ""
			else:
				round_label.text = "King of the Hill — round wins\n" + _score_lines()
		GameDirector.COUNTDOWN:
			round_label.text = "KING OF THE HILL\nget to the crowned ring!  %d" % ceili(GameDirector.timer)
		GameDirector.PLAYING:
			var king := "—"
			if GameDirector.king_id != -1:
				king = str(NetworkManager.player_names.get(GameDirector.king_id, "?"))
			var shift := ""
			# Only warn about the next hill move if one is actually coming: the
			# shift fires when hill_shift_timer runs out, and the director skips
			# any shift landing in the round's final stretch.
			if GameDirector.timer - GameDirector.hill_shift_timer > GameDirector.HILL_SHIFT_TIME * 0.5:
				shift = "   hill moves in %d" % ceili(GameDirector.hill_shift_timer)
			round_label.text = "%s   King: %s%s\n%s" % [_clock(GameDirector.timer), king, shift, _score_lines()]
		GameDirector.ROUND_END:
			var w := "Nobody"
			if GameDirector.last_winner != -1:
				w = str(NetworkManager.player_names.get(GameDirector.last_winner, "?"))
			round_label.text = "%s wins the round!\n" % w + _score_lines()


## The Goblin Siege banner. Enemies-left is counted locally from the replicated
## arena_enemy group (works on every peer). Win/lose result text lands in a later
## stage; for now ROUND_END just says the siege is over.
func _update_boss_hud() -> void:
	var enemies := get_tree().get_nodes_in_group("arena_enemy").size()
	match GameDirector.state:
		GameDirector.HUB:
			round_label.text = ""
		GameDirector.COUNTDOWN:
			round_label.text = "GOBLIN SIEGE\nbrace yourself!  %d" % ceili(GameDirector.timer)
		GameDirector.PLAYING:
			round_label.text = "%s   Enemies left: %d" % [_clock(GameDirector.timer), enemies]
			if spectating:
				var who := "—"
				if _spec_target != null and is_instance_valid(_spec_target):
					who = _spec_target.display_name
				round_label.text += "\nYou're out! Spectating %s  (click to switch)" % who
		GameDirector.ROUND_END:
			round_label.text = "Victory! The horde is broken." if GameDirector.boss_won else "Wiped out. The horde wins..."


func _clock(t: float) -> String:
	var s := int(ceilf(t))
	return "%d:%02d" % [s / 60, s % 60]


func _score_lines() -> String:
	# Show each player's control time this round (if any) + their session wins.
	var names := NetworkManager.player_names
	var lines: Array[String] = []
	for id in names:
		var ct := float(GameDirector.control_time.get(id, 0.0))
		var wins := int(GameDirector.session_wins.get(id, 0))
		lines.append("%s  %ds held  ·  %d win%s" % [str(names[id]), int(ct), wins, "" if wins == 1 else "s"])
	return "\n".join(lines)


func _physics_process(delta: float) -> void:
	var is_local := peer_id == multiplayer.get_unique_id()
	if is_local:
		var input_dir := Vector2(
			Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
			Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
		)
		var jump_pressed := Input.is_action_just_pressed("jump")
		var sprint_held := Input.is_action_pressed("sprint")
		_send_input.rpc_id(1, input_dir, camera_yaw, camera_pitch, jump_pressed, sprint_held)

	if not multiplayer.is_server():
		return

	# Out of the fight: the body is parked and inert until the round ends.
	if spectating:
		velocity = Vector3.ZERO
		return

	# Server-side simulation for this player, driven by the last input it sent us.
	_coyote_timer = COYOTE_TIME if is_on_floor() else maxf(_coyote_timer - delta, 0.0)
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	_swing_cooldown = maxf(_swing_cooldown - delta, 0.0)
	_shoot_cooldown = maxf(_shoot_cooldown - delta, 0.0)
	_cast_cooldown = maxf(_cast_cooldown - delta, 0.0)
	_throw_ball_cooldown = maxf(_throw_ball_cooldown - delta, 0.0)
	_hit_immunity = maxf(_hit_immunity - delta, 0.0)
	_slow_timer = maxf(_slow_timer - delta, 0.0)
	set_slow_tint(_slow_timer > 0.0)

	if not is_on_floor():
		var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
		# The lunar band: anything this high is the secret moon area (or the
		# float down onto it) -- gravity goes soft. See world.gd's moon planes.
		if global_position.y > LOW_GRAV_Y:
			g *= LOW_GRAV_MULT
		velocity.y -= g * delta

	# Track how long we've been grounded, for the bunny-ears bounce rhythm:
	# 0 the instant we land, growing while we stand around.
	if is_on_floor():
		_time_since_land = 0.0 if not _was_on_floor else _time_since_land + delta
	_was_on_floor = is_on_floor()

	if ragdolled:
		# No control while flying: gravity and momentum only, tumbling all the
		# way, then skid out and stand back up.
		_ragdoll_timer -= delta
		tumble += TUMBLE_SPEED * delta
		mesh.rotation.x = tumble
		if is_on_floor():
			velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 14.0 * delta)
			if _ragdoll_timer <= 0.0:
				ragdolled = false
				tumble = 0.0
				mesh.rotation.x = 0.0
				_play_land_squash()
		move_and_slide()
		return

	# Shoved (snowball): control briefly cut while the push carries us -- like a
	# mini-ragdoll but upright, no tumble and no recovery pause.
	if _push_timer > 0.0:
		_push_timer -= delta
		if is_on_floor():
			velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 14.0 * delta)
		move_and_slide()
		return

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		var jump_v := JUMP_VELOCITY * _jump_mult
		if wearing_bunny_ears:
			# Bounce in rhythm (jump again within BOUNCE_WINDOW of landing) and
			# the streak grows; land and dawdle and it resets to the 1.5x base.
			if _time_since_land <= BOUNCE_WINDOW:
				_bounce_mult *= BOUNCE_STEP
			else:
				_bounce_mult = 1.0
			jump_v = JUMP_VELOCITY * _jump_mult * BUNNY_JUMP_BASE * _bounce_mult
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		velocity.y = jump_v

	var speed := SPEED * SPRINT_MULTIPLIER if _pending_sprint else SPEED
	# Wading: shallow water is charming, but it is not fast.
	for w in get_tree().get_nodes_in_group("water"):
		if w.is_wading(global_position):
			speed *= 0.65
			break
	if _slow_timer > 0.0:
		speed *= SLOW_MULT
	var basis_yaw := Basis(Vector3.UP, camera_yaw)
	var direction := (basis_yaw * Vector3(_pending_move.x, 0, _pending_move.y))
	if direction.length() > 0.001:
		direction = direction.normalized()
		velocity.x = move_toward(velocity.x, direction.x * speed, speed * ACCEL * _accel_mult * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, speed * ACCEL * _accel_mult * delta)
		# Only the visible MESH turns to face movement -- never the body root.
		# The camera rig and interact ray are children of the root, so rotating
		# the root would drag the camera around whenever you strafe (the world
		# swivels under your mouse) and skew the interact aim by the body's yaw.
		# atan2(-x, -z) rather than atan2(x, z) because the mesh's modeled
		# forward is -Z (Godot's convention).
		mesh.rotation.y = lerp_angle(mesh.rotation.y, atan2(-direction.x, -direction.z), 12.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, speed * DECEL * _accel_mult * delta)
		velocity.z = move_toward(velocity.z, 0, speed * DECEL * _accel_mult * delta)

	move_and_slide()

	if carried_item_path != NodePath(""):
		var item := get_node_or_null(carried_item_path)
		if item:
			item.global_transform = hold_point.global_transform


## Godot reports sender id 0 (not a real remote sender) when an RPC ends up being
## invoked directly in-process rather than delivered over the network -- which is
## exactly what happens when the host controls its own player, since peer 1 calling
## rpc_id(1, ...) never actually goes over the wire. Treat that case as "it's me".
func _verified_sender_id() -> int:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	return sender_id


@rpc("any_peer", "call_local", "unreliable_ordered")
func _send_input(move: Vector2, yaw: float, pitch: float, jump_pressed: bool, sprint_held: bool) -> void:
	if not multiplayer.is_server():
		return
	if _verified_sender_id() != peer_id:
		return
	_pending_move = move
	_pending_sprint = sprint_held
	camera_yaw = yaw
	# Needed so the server's own interact raycast (see _server_side_look_target)
	# looks the same direction the real player on this client is actually aiming,
	# both horizontally and vertically.
	camera_pivot.rotation.y = yaw
	spring_arm.rotation.x = pitch
	aim_pivot.rotation.x = pitch
	if jump_pressed:
		_jump_buffer_timer = JUMP_BUFFER_TIME


## Server-only: some weapon/ability hit this player. Same rules as NPCs
## (npc.gd): launch with weapon-specific power, cut movement control until
## landed and recovered, brief immunity against juggling. Whatever they were
## carrying goes flying too -- getting smacked means dropping your stuff.
func apply_knockback(dir: Vector3, power: float, ragdoll_time: float = RAGDOLL_MIN_TIME) -> void:
	if not multiplayer.is_server():
		return
	if _hit_immunity > 0.0:
		return
	_hit_immunity = HIT_IMMUNITY
	ragdolled = true
	_ragdoll_timer = ragdoll_time
	if carried_item_path != NodePath(""):
		var item := get_node_or_null(carried_item_path)
		if item:
			item.carried_by = -1
			item.freeze = false
		carried_item_path = NodePath("")
	var flat := (dir * Vector3(1, 0, 1)).normalized()
	velocity = flat * power + Vector3.UP * power * 0.6


## Server-only. A troll-style hit: pushed back with control briefly cut, but no
## ragdoll, no tumble, and no immunity window. The snowball's punch.
func apply_shove(dir: Vector3, power: float) -> void:
	if not multiplayer.is_server() or spectating:
		return
	var flat := (dir * Vector3(1, 0, 1)).normalized()
	velocity.x = flat.x * power * SHOVE_SCALE
	velocity.z = flat.z * power * SHOVE_SCALE
	_push_timer = SHOVE_TIME


## Server-only. Slow this player's movement for `duration` seconds (refreshes,
## doesn't stack). The frost tint is applied in _physics_process and mirrored to
## clients through the snapshot's `slow` flag.
func apply_slow(duration: float) -> void:
	if not multiplayer.is_server() or spectating:
		return
	_slow_timer = maxf(_slow_timer, duration)


func is_slowed() -> bool:
	return _slow_timer > 0.0


## Frost-blue tint while slowed: a cold-shifted copy of the active body
## material, swapped in as an override and restored after. Runs on the server
## (its own physics) and on clients (from the snapshot).
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


## Server-only teleport used by the kill plane (see world.gd): drop the player
## at `pos`, kill all momentum, and clear any ragdoll/tumble/bounce state so
## they land clean. Clients pick this up through the snapshot -- the jump is far
## larger than NET_SNAP_DISTANCE, so they snap instead of zipping across the map.
func respawn_at(pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	global_position = pos
	velocity = Vector3.ZERO
	ragdolled = false
	_ragdoll_timer = 0.0
	tumble = 0.0
	mesh.rotation.x = 0.0
	_bounce_mult = 1.0


## Server-only. Called by the kill plane when this player falls out during a boss
## fight (see world.gd): freeze the body where it is, drop anything carried, and
## flip to spectator so they watch a teammate instead of respawning.
func enter_spectator() -> void:
	if not multiplayer.is_server() or spectating:
		return
	velocity = Vector3.ZERO
	ragdolled = false
	_ragdoll_timer = 0.0
	tumble = 0.0
	mesh.rotation.x = 0.0
	if carried_item_path != NodePath(""):
		var item := get_node_or_null(carried_item_path)
		if item:
			item.carried_by = -1
			item.freeze = false
		carried_item_path = NodePath("")
	set_spectating(true)


## Server-only. Undo spectator (at the end of the round, before the teleport home).
func exit_spectator() -> void:
	if not multiplayer.is_server():
		return
	set_spectating(false)


## Applies the spectator flag + its visuals. Runs on the server (via
## enter/exit_spectator) and on every client (via apply_remote_state), so the
## body vanishes for everyone and the owner swaps cameras.
func set_spectating(v: bool) -> void:
	if spectating == v:
		return
	spectating = v
	mesh.visible = not v
	name_label.visible = not v
	collision_layer = 0 if v else 2
	if peer_id == multiplayer.get_unique_id():
		spectator_cam.current = v
		camera.current = not v
		if v:
			_pick_spec_target()


## Living teammates worth watching: other players who aren't themselves out.
func _spec_candidates() -> Array:
	var out: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if p == self or p.spectating:
			continue
		out.append(p)
	return out


func _pick_spec_target() -> void:
	var c := _spec_candidates()
	_spec_target = c[0] if not c.is_empty() else null


func _cycle_spec_target() -> void:
	var c := _spec_candidates()
	if c.is_empty():
		_spec_target = null
		return
	var i := c.find(_spec_target)
	_spec_target = c[(i + 1) % c.size()]


## Park the spectator camera behind whichever teammate we're watching, using the
## body facing (which IS synced) for a clean over-the-shoulder chase view.
func _update_spectator_cam() -> void:
	if _spec_target == null or not is_instance_valid(_spec_target) or _spec_target.spectating:
		_pick_spec_target()
	if _spec_target == null:
		return
	var yaw: float = _spec_target.mesh.rotation.y
	var forward := Vector3(sin(yaw), 0, cos(yaw))
	var focus: Vector3 = _spec_target.global_position + Vector3(0, 1.2, 0)
	spectator_cam.global_position = focus - forward * 6.0 + Vector3(0, 2.0, 0)
	spectator_cam.look_at(focus, Vector3.UP)


@rpc("any_peer", "call_local", "reliable")
func _request_interact() -> void:
	if not multiplayer.is_server():
		return
	if _verified_sender_id() != peer_id:
		return
	if ragdolled:
		return
	var target := _server_side_look_target()
	if target and target.has_method("interact"):
		target.interact(self)


@rpc("any_peer", "call_local", "reliable")
func _request_throw() -> void:
	if not multiplayer.is_server():
		return
	if _verified_sender_id() != peer_id:
		return
	if ragdolled:
		return
	if carried_item_path != NodePath(""):
		var item := get_node_or_null(carried_item_path)
		if item and item.has_method("throw_from"):
			item.throw_from(self)
		carried_item_path = NodePath("")
		return
	# Nothing held: use whichever power we have (the granters keep them
	# mutually exclusive, see sword_stone.gd / coat_rack.gd).
	if wearing_hat and _throw_ball_cooldown <= 0.0:
		_throw_ball_cooldown = THROW_BALL_COOLDOWN
		var world := get_tree().current_scene
		if world and world.has_method("spawn_snowball"):
			world.spawn_snowball(self)
	elif wearing_helmet and _swing_cooldown <= 0.0:
		_swing_cooldown = SWING_COOLDOWN
		_do_swing_effects()
		_play_swing.rpc()
	elif wearing_cowboy_hat and _shoot_cooldown <= 0.0:
		_shoot_cooldown = SHOOT_COOLDOWN
		var world := get_tree().current_scene
		if world and world.has_method("spawn_bullet"):
			world.spawn_bullet(self)
			_play_shoot.rpc()
	elif wearing_wizard_hat and _cast_cooldown <= 0.0:
		_cast_cooldown = CAST_COOLDOWN
		var world := get_tree().current_scene
		if world and world.has_method("spawn_lightning"):
			world.spawn_lightning(self)
			_play_cast.rpc()


## Server-only: the gameplay half of a swing. Shoves any physics prop (items,
## snowballs) in front of us, and RAGDOLLS any character (goblin, villager,
## other player) -- the visual half is _play_swing on every peer.
func _do_swing_effects() -> void:
	var forward := mesh.global_transform.basis * Vector3.FORWARD
	var targets: Array[Node] = []
	targets.append_array(get_tree().get_nodes_in_group("sync_items"))
	targets.append_array(get_tree().get_nodes_in_group("sync_projectiles"))
	for t in targets:
		if not t is RigidBody3D:
			continue
		var to_target: Vector3 = t.global_position - global_position
		if to_target.length() > SWING_RANGE:
			continue
		# Only things roughly in the half-space we're facing get hit.
		if forward.dot(to_target.normalized()) < 0.3:
			continue
		if "carried_by" in t and t.carried_by != -1:
			continue
		t.freeze = false
		var push_dir := (to_target * Vector3(1, 0, 1)).normalized()
		t.apply_central_impulse((push_dir + Vector3.UP * 0.6).normalized() * SWING_PUSH * t.mass)

	var characters: Array[Node] = []
	characters.append_array(get_tree().get_nodes_in_group("npc"))
	characters.append_array(get_tree().get_nodes_in_group("players"))
	for c in characters:
		if c == self or not c.has_method("apply_knockback"):
			continue
		var to_char: Vector3 = c.global_position - global_position
		if to_char.length() > SWING_RANGE:
			continue
		if forward.dot(to_char.normalized()) < 0.3:
			continue
		c.apply_knockback((to_char * Vector3(1, 0, 1)).normalized(), SWING_KNOCKBACK)


## Cosmetic revolver recoil: the barrel kicks up and settles back.
@rpc("authority", "call_local", "reliable")
func _play_shoot() -> void:
	var tween := create_tween()
	revolver.rotation.x = 0.0
	tween.tween_property(revolver, "rotation:x", 0.7, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(revolver, "rotation:x", 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


## Cosmetic cast: the wizard hat gives a little magic squash-and-pop.
@rpc("authority", "call_local", "reliable")
func _play_cast() -> void:
	if wizard_hat == null:
		return
	var tween := create_tween()
	wizard_hat.scale = Vector3.ONE
	tween.tween_property(wizard_hat, "scale", Vector3(1.18, 0.85, 1.18), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(wizard_hat, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Cosmetic swing arc, played identically on every peer (reliable broadcast,
## same pattern as the door toggle -- rare events don't go in the snapshot).
@rpc("authority", "call_local", "reliable")
func _play_swing() -> void:
	var tween := create_tween()
	sword.rotation = Vector3(0, 0, 0)
	tween.tween_property(sword, "rotation:x", -2.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sword, "rotation:x", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func _server_side_look_target() -> Node:
	# The server trusts the yaw/pitch this player already streamed us and re-runs
	# the same forward raycast itself, so a modified client can't interact with
	# things it can't actually see.
	if interact_ray.is_colliding():
		var collider := interact_ray.get_collider()
		if collider and collider.is_in_group("interactable"):
			return collider
	return null


func apply_remote_state(state: Dictionary) -> void:
	# Non-server peers don't apply the snapshot directly -- they store it as a
	# target and glide toward it in _process (see _smooth_to_net_state), which
	# hides the jitter of unreliable snapshot packets arriving unevenly.
	_net_pos_target = state["pos"]
	_net_rot_target = state["rot"]
	_has_net_state = true
	wearing_hat = state["hat"]
	wearing_helmet = state["helmet"]
	wearing_cowboy_hat = state["cowboy"]
	wearing_bunny_ears = state["bunny"]
	wearing_wizard_hat = state["wizard"]
	tumble = state["tumble"]
	mesh.rotation.x = tumble
	set_spectating(state["spec"])
	set_slow_tint(state["slow"])


func _smooth_to_net_state(delta: float) -> void:
	if multiplayer.is_server() or not _has_net_state:
		return
	if global_position.distance_to(_net_pos_target) > NET_SNAP_DISTANCE:
		# Teleport (spawn, respawn, etc.) -- don't visibly zip across the map.
		global_position = _net_pos_target
		mesh.rotation.y = _net_rot_target
		return
	var w := 1.0 - exp(-NET_SMOOTH_RATE * delta)
	global_position = global_position.lerp(_net_pos_target, w)
	mesh.rotation.y = lerp_angle(mesh.rotation.y, _net_rot_target, w)


## Where this player is looking, pitch included -- the aim pivot carries the
## camera's yaw+pitch but none of the mesh's facing. Used for throw direction.
func look_direction() -> Vector3:
	return -aim_pivot.global_transform.basis.z


func _update_squash_stretch(delta: float) -> void:
	# global_position.y only actually changes once per physics tick (for the
	# server) or once per incoming snapshot (for everyone else) -- both much
	# rarer than _process's idle-rate delta. Comparing against the last frame
	# unconditionally would read near-zero "velocity" on every frame where
	# position hasn't moved yet, falsely detecting a landing on every idle
	# frame throughout an entire fall. Only sample once position actually
	# changes, using the real elapsed time since the last sample.
	_time_since_y_change += delta
	if is_equal_approx(global_position.y, _prev_y):
		return
	var vertical_speed := (global_position.y - _prev_y) / _time_since_y_change
	_prev_y = global_position.y
	_time_since_y_change = 0.0
	if vertical_speed < LAND_SQUASH_THRESHOLD:
		_fall_speed = vertical_speed
	elif _fall_speed < LAND_SQUASH_THRESHOLD and absf(vertical_speed) < 1.0:
		_play_land_squash()
		_fall_speed = 0.0


func _play_land_squash() -> void:
	mesh.scale = Vector3(1.25, 0.7, 1.25)
	var tween := create_tween()
	tween.tween_property(mesh, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
