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
## as wearing_hat, and same snapshot-based sync. The two powers are mutually
## exclusive (each granter clears the other) so a click always unambiguously
## means one thing: throw held item > snowball > sword swing.
var wearing_helmet: bool = false:
	set(value):
		wearing_helmet = value
		if helmet:
			helmet.visible = value
		if sword:
			sword.visible = value

# Server-side swing rate limit; also drives the swing animation duration.
var _swing_cooldown: float = 0.0
const SWING_COOLDOWN := 0.5
const SWING_RANGE := 2.6
const SWING_PUSH := 10.0

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
@onready var prompt_label: Label = $HUD/InteractPrompt
@onready var leave_button: Button = $HUD/LeaveButton
@onready var options_button: Button = $HUD/OptionsButton
@onready var options_menu: Control = $HUD/OptionsMenu
@onready var player_list_label: Label = $HUD/PlayerListLabel


func _ready() -> void:
	add_to_group("players")
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
	if peer_id != multiplayer.get_unique_id():
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

	# Server-side simulation for this player, driven by the last input it sent us.
	_coyote_timer = COYOTE_TIME if is_on_floor() else maxf(_coyote_timer - delta, 0.0)
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	_swing_cooldown = maxf(_swing_cooldown - delta, 0.0)

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY * _jump_mult
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	var speed := SPEED * SPRINT_MULTIPLIER if _pending_sprint else SPEED
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


@rpc("any_peer", "call_local", "reliable")
func _request_interact() -> void:
	if not multiplayer.is_server():
		return
	if _verified_sender_id() != peer_id:
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
	if carried_item_path != NodePath(""):
		var item := get_node_or_null(carried_item_path)
		if item and item.has_method("throw_from"):
			item.throw_from(self)
		carried_item_path = NodePath("")
		return
	# Nothing held: throw a snowball or swing the sword, whichever power we
	# have (the granters keep them mutually exclusive, see sword_stone.gd).
	if wearing_hat:
		var world := get_tree().current_scene
		if world and world.has_method("spawn_snowball"):
			world.spawn_snowball(self)
	elif wearing_helmet and _swing_cooldown <= 0.0:
		_swing_cooldown = SWING_COOLDOWN
		_do_swing_effects()
		_play_swing.rpc()


## Server-only: the gameplay half of a swing. Shoves any physics prop (items,
## snowballs) in front of us; the visual half is _play_swing on every peer.
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
