extends Node3D
## Ties the whole vertical slice together: spawns a Player for each connected peer
## and, every physics frame, broadcasts a snapshot of every networked object's
## position so all peers can render a consistent world without simulating physics
## for anything they don't own. The server is the only one that ever calls
## move_and_slide()/simulates RigidBody3D physics; everyone else just renders.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const SNOWBALL_SCENE := preload("res://scenes/snowball.tscn")

@onready var players_node: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $Players/MultiplayerSpawner

var player_nodes: Dictionary = {} # peer_id -> Player

# Projectiles (snowballs) are spawned dynamically at runtime, so their parent
# and MultiplayerSpawner are built in code here rather than hand-edited into
# world.tscn -- editing world.tscn by hand is exactly what caused the earlier
# "invisible ground" bug from a silently-dropped scene node.
var projectiles_node: Node3D
var projectile_spawner: MultiplayerSpawner
var _next_projectile_id: int = 0


func _ready() -> void:
	spawner.spawn_function = _spawn_player

	projectiles_node = Node3D.new()
	projectiles_node.name = "Projectiles"
	add_child(projectiles_node)
	projectile_spawner = MultiplayerSpawner.new()
	projectile_spawner.spawn_path = projectiles_node.get_path()
	projectile_spawner.spawn_function = _spawn_snowball
	projectiles_node.add_child(projectile_spawner)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	# Only ever fires for a client: if the host quits or crashes, don't leave
	# us stuck staring at a dead scene -- bail back to the menu automatically.
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	if multiplayer.is_server():
		# MultiplayerSpawner replays already-spawned nodes to peers that join later,
		# so it's safe to just spawn everyone currently known about right now.
		for id in NetworkManager.player_names:
			_spawn_for_peer(id)
	else:
		set_physics_process(false)


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_spawn_for_peer(id)


func _on_peer_disconnected(id: int) -> void:
	if player_nodes.has(id):
		player_nodes[id].queue_free()
		player_nodes.erase(id)


func _on_server_disconnected() -> void:
	GameState.release_mouse()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _spawn_for_peer(id: int) -> void:
	if not player_nodes.has(id):
		spawner.spawn(id)


func _spawn_player(id: int) -> Node:
	var p := PLAYER_SCENE.instantiate()
	p.name = str(id)
	p.peer_id = id
	p.display_name = NetworkManager.player_names.get(id, "Player")
	player_nodes[id] = p
	var spawn_points := get_tree().get_nodes_in_group("player_spawn")
	if spawn_points.size() > 0:
		var point: Node3D = spawn_points[randi() % spawn_points.size()]
		p.position = point.global_position
	return p


func _physics_process(_delta: float) -> void:
	var snapshot := {"players": {}, "items": {}, "npcs": {}, "projectiles": {}}
	for id in player_nodes:
		var p: Node3D = player_nodes[id]
		# "rot" is the MESH facing, not the body -- the body root never rotates
		# (see player.gd for why).
		snapshot["players"][id] = {"pos": p.global_position, "rot": p.mesh.rotation.y, "hat": p.wearing_hat}
	for item in get_tree().get_nodes_in_group("sync_items"):
		snapshot["items"][item.get_path()] = {"xform": item.global_transform, "held": item.carried_by}
	for npc in get_tree().get_nodes_in_group("npc"):
		snapshot["npcs"][npc.get_path()] = {"pos": npc.global_position, "rot": npc.rotation.y}
	for proj in get_tree().get_nodes_in_group("sync_projectiles"):
		snapshot["projectiles"][proj.get_path()] = {"xform": proj.global_transform}
	_apply_snapshot.rpc(snapshot)


@rpc("authority", "call_remote", "unreliable")
func _apply_snapshot(snapshot: Dictionary) -> void:
	for id_variant in snapshot["players"]:
		var id: int = int(id_variant)
		if player_nodes.has(id):
			player_nodes[id].apply_remote_state(snapshot["players"][id])
	for path in snapshot["items"]:
		var item := get_node_or_null(path)
		if item:
			item.apply_remote_state(snapshot["items"][path])
	for path in snapshot["npcs"]:
		var npc := get_node_or_null(path)
		if npc:
			npc.apply_remote_state(snapshot["npcs"][path])
	for path in snapshot["projectiles"]:
		var proj := get_node_or_null(path)
		if proj:
			proj.apply_remote_state(snapshot["projectiles"][path])


## Called by a player (server-side only, see player.gd's _request_throw) to
## launch a snowball from their hold point. Spawned dynamically via
## projectile_spawner so every peer gets a replicated copy.
func spawn_snowball(thrower: Node3D) -> void:
	if not multiplayer.is_server():
		return
	var id := _next_projectile_id
	_next_projectile_id += 1
	var data := {"id": id, "xform": thrower.hold_point.global_transform, "peer": thrower.peer_id}
	projectile_spawner.spawn(data)


func _spawn_snowball(data: Dictionary) -> Node:
	var s := SNOWBALL_SCENE.instantiate()
	s.name = "Snowball%d" % int(data["id"])
	s.global_transform = data["xform"]
	if multiplayer.is_server():
		var thrower: Node3D = player_nodes.get(int(data["peer"]))
		if thrower:
			s.launch_from(thrower)
	return s
