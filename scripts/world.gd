extends Node3D
## Ties the whole vertical slice together: spawns a Player for each connected peer
## and, every physics frame, broadcasts a snapshot of every networked object's
## position so all peers can render a consistent world without simulating physics
## for anything they don't own. The server is the only one that ever calls
## move_and_slide()/simulates RigidBody3D physics; everyone else just renders.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const SNOWBALL_SCENE := preload("res://scenes/snowball.tscn")
const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const LIGHTNING_SCENE := preload("res://scenes/lightning.tscn")
const GOBLIN_SCENE := preload("res://scenes/goblin.tscn")
const TROLL_SCENE := preload("res://scenes/troll.tscn")

# The co-op Goblin Siege wave, spawned onto the dungeon arena disc when a boss
# round starts (see GameDirector). Six goblins for now; the troll joins in a
# later stage. Skins reuse the cave goblins' palette.
const ARENA_CENTER := Vector3(92, -15.5, 40) # just above the disc top (y=-16)
const BOSS_GOBLIN_SKINS: Array[Color] = [
	Color(0.65, 0.68, 0.28), Color(0.52, 0.6, 0.22), Color(0.42, 0.58, 0.24),
	Color(0.33, 0.5, 0.22), Color(0.22, 0.36, 0.16), Color(0.6, 0.66, 0.3),
]

# Kill plane. The only thing on the whole map that sits below this is the boss
# dungeon's pit (arena disc at y=-16, catch floor at y=-40), so in practice this
# only ever fires there: fall off the arena and you cross it before hitting the
# floor. Players teleport back to a town spawn; NPCs despawn.
const KILL_PLANE_Y := -34.0

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

# Arena enemies (Goblin Siege) are also spawned dynamically, through their own
# spawner so late joiners replicate them and freeing on the server auto-despawns
# them on clients.
var enemies_node: Node3D
var enemy_spawner: MultiplayerSpawner


func _ready() -> void:
	spawner.spawn_function = _spawn_player

	projectiles_node = Node3D.new()
	projectiles_node.name = "Projectiles"
	add_child(projectiles_node)
	projectile_spawner = MultiplayerSpawner.new()
	projectile_spawner.spawn_path = projectiles_node.get_path()
	projectile_spawner.spawn_function = _spawn_projectile
	projectiles_node.add_child(projectile_spawner)

	enemies_node = Node3D.new()
	enemies_node.name = "Enemies"
	add_child(enemies_node)
	enemy_spawner = MultiplayerSpawner.new()
	enemy_spawner.spawn_path = enemies_node.get_path()
	enemy_spawner.spawn_function = _spawn_enemy
	enemies_node.add_child(enemy_spawner)

	# The director drives the boss wave: spawn frozen on COUNTDOWN, turn loose on
	# PLAYING, clean up on ROUND_END. state_changed only ever fires on the server.
	GameDirector.state_changed.connect(_on_director_state)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	# Only ever fires for a client: if the host quits or crashes, don't leave
	# us stuck staring at a dead scene -- bail back to the menu automatically.
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	if multiplayer.is_server():
		GameDirector.reset_session()
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
	GameDirector.reset_session()
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


func _physics_process(delta: float) -> void:
	GameDirector.tick(delta)
	_enforce_kill_plane()
	var snapshot := {"players": {}, "items": {}, "npcs": {}, "projectiles": {}, "director": GameDirector.net_state()}
	for id in player_nodes:
		var p: Node3D = player_nodes[id]
		# "rot" is the MESH facing, not the body -- the body root never rotates
		# (see player.gd for why).
		snapshot["players"][id] = {"pos": p.global_position, "rot": p.mesh.rotation.y, "hat": p.wearing_hat, "helmet": p.wearing_helmet, "cowboy": p.wearing_cowboy_hat, "bunny": p.wearing_bunny_ears, "wizard": p.wearing_wizard_hat, "tumble": p.tumble, "spec": p.spectating, "slow": p.is_slowed()}
	for item in get_tree().get_nodes_in_group("sync_items"):
		snapshot["items"][item.get_path()] = {"xform": item.global_transform, "held": item.carried_by}
	for npc in get_tree().get_nodes_in_group("npc"):
		snapshot["npcs"][npc.get_path()] = {"pos": npc.global_position, "rot": npc.rotation.y, "tumble": npc.tumble, "slow": npc.is_slowed()}
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
	GameDirector.apply_net_state(snapshot["director"])


## Server-only (this whole node stops physics-processing on clients). Anything
## that has fallen below the kill plane gets dealt with: players are teleported
## back to a town spawn, NPCs are despawned across every peer.
func _enforce_kill_plane() -> void:
	var boss_live: bool = GameDirector.mode == GameDirector.Mode.BOSS and GameDirector.state == GameDirector.PLAYING
	for id in player_nodes:
		var p: Node3D = player_nodes[id]
		if p.spectating:
			continue
		if p.global_position.y < KILL_PLANE_Y:
			if boss_live:
				# Fall out of the arena mid-fight -> spectate, don't respawn.
				p.enter_spectator()
			else:
				p.respawn_at(_town_spawn())
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc.is_queued_for_deletion():
			continue
		if npc.global_position.y < KILL_PLANE_Y:
			if npc.is_in_group("arena_enemy"):
				# Spawner-managed: a server-side free auto-despawns it on clients.
				npc.queue_free()
			else:
				# A static scene NPC lives on every peer; free it everywhere.
				_remove_node.rpc(npc.get_path())


## A random town spawn marker's position (same set the game spawns players at).
func _town_spawn() -> Vector3:
	var points := get_tree().get_nodes_in_group("player_spawn")
	if points.is_empty():
		return Vector3(0, 1, 8)
	var point: Node3D = points[randi() % points.size()]
	return point.global_position


## Free a node on every peer. NPCs live in the static scene on all peers, so a
## server-only queue_free wouldn't reach clients -- this reliable RPC does.
@rpc("authority", "call_local", "reliable")
func _remove_node(path: NodePath) -> void:
	var n := get_node_or_null(path)
	if n:
		n.queue_free()


## --- Goblin Siege boss wave (server-only; wired to GameDirector) -----------

func _on_director_state(new_state: int) -> void:
	if not multiplayer.is_server() or GameDirector.mode != GameDirector.Mode.BOSS:
		return
	match new_state:
		GameDirector.COUNTDOWN:
			_spawn_boss_wave()
		GameDirector.PLAYING:
			_set_enemies_frozen(false)
			_mark_participants()
		GameDirector.ROUND_END:
			_despawn_boss_wave()
			_end_boss_players()


## Spawn the enemy wave onto the arena disc, frozen until the countdown ends.
## Goblins ring the disc; the troll (center) arrives in a later stage.
func _spawn_boss_wave() -> void:
	for i in range(BOSS_GOBLIN_SKINS.size()):
		var a := TAU * float(i) / float(BOSS_GOBLIN_SKINS.size())
		var pos := ARENA_CENTER + Vector3(cos(a) * 8.0, 0, sin(a) * 8.0)
		enemy_spawner.spawn({"kind": "goblin", "idx": i, "pos": pos})
	# The troll: the seventh enemy, planted dead center.
	enemy_spawner.spawn({"kind": "troll", "idx": 6, "pos": ARENA_CENTER})


func _spawn_enemy(data: Dictionary) -> Node:
	var idx := int(data["idx"])
	var e: Node3D
	if data["kind"] == "troll":
		e = TROLL_SCENE.instantiate()
		e.name = "Troll"
		e.npc_name = "Troll"
	else:
		e = GOBLIN_SCENE.instantiate()
		e.name = "Enemy%d" % idx
		e.skin_color = BOSS_GOBLIN_SKINS[idx % BOSS_GOBLIN_SKINS.size()]
		e.npc_name = "Goblin"
	e.arena_mode = true
	e.position = data["pos"]
	e.add_to_group("arena_enemy")
	e.set_frozen(true)
	return e


func _set_enemies_frozen(v: bool) -> void:
	for e in get_tree().get_nodes_in_group("arena_enemy"):
		e.set_frozen(v)


func _despawn_boss_wave() -> void:
	for e in get_tree().get_nodes_in_group("arena_enemy"):
		e.queue_free()


## Record who's actually in the arena when the fight goes live; the round's lose
## condition ("everyone's out") is measured against this set.
func _mark_participants() -> void:
	GameDirector.participants.clear()
	for id in player_nodes:
		var p: Node3D = player_nodes[id]
		if _in_arena(p.global_position):
			GameDirector.participants.append(p.peer_id)


func _in_arena(pos: Vector3) -> bool:
	return Vector2(pos.x - ARENA_CENTER.x, pos.z - ARENA_CENTER.z).length() < 17.0 and pos.y > -30.0


## Round over: un-spectate everyone and send all the fighters back to the hub.
func _end_boss_players() -> void:
	for id in player_nodes:
		var p: Node3D = player_nodes[id]
		if p.spectating:
			p.exit_spectator()
		if p.peer_id in GameDirector.participants:
			p.respawn_at(_town_spawn())


## Called by a player (server-side only, see player.gd's _request_throw) to
## launch a projectile from their hold point. Spawned dynamically via
## projectile_spawner so every peer gets a replicated copy; "kind" picks the
## scene, so new projectile types are one dictionary entry away.
func spawn_snowball(thrower: Node3D) -> void:
	_spawn_from(thrower, "snowball")


func spawn_bullet(shooter: Node3D) -> void:
	_spawn_from(shooter, "bullet")


func spawn_lightning(caster: Node3D) -> void:
	_spawn_from(caster, "lightning")


func _spawn_from(shooter: Node3D, kind: String) -> void:
	if not multiplayer.is_server():
		return
	var id := _next_projectile_id
	_next_projectile_id += 1
	var data := {"id": id, "kind": kind, "xform": shooter.hold_point.global_transform, "peer": shooter.peer_id}
	projectile_spawner.spawn(data)


func _spawn_projectile(data: Dictionary) -> Node:
	var scene: PackedScene = SNOWBALL_SCENE
	match data["kind"]:
		"bullet":
			scene = BULLET_SCENE
		"lightning":
			scene = LIGHTNING_SCENE
	var s := scene.instantiate()
	s.name = "%s%d" % [str(data["kind"]).capitalize(), int(data["id"])]
	s.global_transform = data["xform"]
	if multiplayer.is_server():
		var shooter: Node3D = player_nodes.get(int(data["peer"]))
		if shooter:
			s.launch_from(shooter)
	return s
