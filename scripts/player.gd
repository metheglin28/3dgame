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

# Input latched by the owning client, applied by the server.
var _pending_move: Vector2 = Vector2.ZERO
var _pending_sprint: bool = false
var _jump_buffer_timer: float = 0.0
var _coyote_timer: float = 0.0

# Purely cosmetic squash-and-stretch, driven off observed vertical position
# rather than the server's real velocity -- that way it works identically
# whether this Player instance is being physically simulated (the server) or
# just rendered from the snapshot (everyone else), with no networking needed.
var _prev_y: float = 0.0
var _fall_speed: float = 0.0
var _time_since_y_change: float = 0.0
const LAND_SQUASH_THRESHOLD := -3.0

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
@onready var hold_point: Marker3D = $HoldPoint
@onready var prompt_label: Label = $HUD/InteractPrompt
@onready var leave_button: Button = $HUD/LeaveButton


func _ready() -> void:
	add_to_group("players")
	name_label.text = display_name
	var is_local := peer_id == multiplayer.get_unique_id()
	camera.current = is_local
	$HUD.visible = is_local
	if is_local:
		GameState.capture_mouse()
		leave_button.pressed.connect(_on_leave_pressed)
	# _physics_process always stays enabled, even on non-server peers: it's also
	# where the *local* player reads Input and streams it to the server (see
	# below). Only the actual movement simulation later in that function is
	# gated behind `multiplayer.is_server()`.


func _unhandled_input(event: InputEvent) -> void:
	if peer_id != multiplayer.get_unique_id():
		return
	if event is InputEventMouseMotion and GameState.mouse_captured:
		camera_yaw -= event.relative.x * MOUSE_SENSITIVITY
		camera_pitch = clamp(camera_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.2, 1.0)
		camera_pivot.rotation.y = camera_yaw
		spring_arm.rotation.x = camera_pitch
		aim_pivot.rotation.x = camera_pitch
	if event is InputEventMouseButton and event.pressed:
		# Zoom is purely a local viewing preference, so it never touches the network.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			spring_arm.spring_length = clamp(spring_arm.spring_length - ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			spring_arm.spring_length = clamp(spring_arm.spring_length + ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
	if event.is_action_pressed("toggle_mouse"):
		GameState.toggle_mouse()
	if event.is_action_pressed("interact"):
		_request_interact.rpc_id(1)
	if event.is_action_pressed("throw"):
		_request_throw.rpc_id(1)


func _on_leave_pressed() -> void:
	# Works the same whether this player is the host or a joined client:
	# closing our own peer either shuts the server down (dropping everyone
	# else too) or just disconnects us, and either way we land back on the menu.
	GameState.release_mouse()
	NetworkManager.leave_game()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _process(delta: float) -> void:
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
		var sprint_held := Input.is_key_pressed(KEY_SHIFT)
		_send_input.rpc_id(1, input_dir, camera_yaw, camera_pitch, jump_pressed, sprint_held)

	if not multiplayer.is_server():
		return

	# Server-side simulation for this player, driven by the last input it sent us.
	_coyote_timer = COYOTE_TIME if is_on_floor() else maxf(_coyote_timer - delta, 0.0)
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	var speed := SPEED * SPRINT_MULTIPLIER if _pending_sprint else SPEED
	var basis_yaw := Basis(Vector3.UP, camera_yaw)
	var direction := (basis_yaw * Vector3(_pending_move.x, 0, _pending_move.y))
	if direction.length() > 0.001:
		direction = direction.normalized()
		velocity.x = move_toward(velocity.x, direction.x * speed, speed * ACCEL * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, speed * ACCEL * delta)
		# atan2(direction.x, direction.z) would give the angle for a mesh whose
		# modeled "forward" is +Z; ours (and Godot's convention generally) faces
		# -Z, which is the exact opposite direction, hence the negation.
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 12.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, speed * DECEL * delta)
		velocity.z = move_toward(velocity.z, 0, speed * DECEL * delta)

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
	if carried_item_path == NodePath(""):
		return
	var item := get_node_or_null(carried_item_path)
	if item and item.has_method("throw_from"):
		item.throw_from(self)
	carried_item_path = NodePath("")


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
	# Used by non-server clients to render a player purely from the server snapshot.
	# (Their own camera pivot, if any, was already updated locally from mouse input.)
	global_position = state["pos"]
	rotation.y = state["rot"]


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
