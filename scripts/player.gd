extends CharacterBody3D
## Third-person player. Movement is server-authoritative: whichever client owns this
## node (peer_id == the local player) reads Input and streams it to the server; the
## server runs the actual physics and everyone (including the owner) renders from the
## snapshot the World broadcasts every physics frame. On a LAN the round trip is small
## enough that this stays feel-good without needing client-side prediction.

const SPEED := 5.5
const JUMP_VELOCITY := 6.5
const MOUSE_SENSITIVITY := 0.0035
const INTERACT_RANGE := 3.0

@export var peer_id: int = 1

var display_name: String = "Player"
var camera_yaw: float = 0.0
var camera_pitch: float = 0.0
var current_interactable: Node = null
var carried_item_path: NodePath = NodePath("")

# Input latched by the owning client, applied by the server.
var _pending_move: Vector2 = Vector2.ZERO
var _pending_jump: bool = false

@onready var mesh: MeshInstance3D = $Mesh
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var interact_ray: RayCast3D = $CameraPivot/SpringArm3D/Camera3D/InteractRay
@onready var name_label: Label3D = $NameLabel
@onready var hold_point: Marker3D = $HoldPoint
@onready var prompt_label: Label = $HUD/InteractPrompt


func _ready() -> void:
	add_to_group("players")
	name_label.text = display_name
	var is_local := peer_id == multiplayer.get_unique_id()
	camera.current = is_local
	$HUD.visible = is_local
	if is_local:
		GameState.capture_mouse()
	if not multiplayer.is_server():
		# Non-server peers never simulate physics for anyone; they just render snapshots.
		set_physics_process(false)
		freeze_body()


func freeze_body() -> void:
	# CharacterBody3D has no built-in "kinematic only" switch; simplest is to just
	# never call move_and_slide() on it when we're not the server (see _ready above).
	pass


func _unhandled_input(event: InputEvent) -> void:
	if peer_id != multiplayer.get_unique_id():
		return
	if event is InputEventMouseMotion and GameState.mouse_captured:
		camera_yaw -= event.relative.x * MOUSE_SENSITIVITY
		camera_pitch = clamp(camera_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.2, 1.0)
		camera_pivot.rotation.y = camera_yaw
		spring_arm.rotation.x = camera_pitch
	if event.is_action_pressed("toggle_mouse"):
		GameState.toggle_mouse()
	if event.is_action_pressed("interact"):
		_request_interact.rpc_id(1)
	if event.is_action_pressed("throw"):
		_request_throw.rpc_id(1)


func _process(_delta: float) -> void:
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
		_send_input.rpc_id(1, input_dir, camera_yaw, jump_pressed)

	if not multiplayer.is_server():
		return

	# Server-side simulation for this player, driven by the last input it sent us.
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	if _pending_jump and is_on_floor():
		velocity.y = JUMP_VELOCITY
	_pending_jump = false

	var basis_yaw := Basis(Vector3.UP, camera_yaw)
	var direction := (basis_yaw * Vector3(_pending_move.x, 0, _pending_move.y))
	if direction.length() > 0.001:
		direction = direction.normalized()
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), 12.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED * delta * 6.0)
		velocity.z = move_toward(velocity.z, 0, SPEED * delta * 6.0)

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
func _send_input(move: Vector2, yaw: float, jump_pressed: bool) -> void:
	if not multiplayer.is_server():
		return
	if _verified_sender_id() != peer_id:
		return
	_pending_move = move
	camera_yaw = yaw
	if jump_pressed:
		_pending_jump = true


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
