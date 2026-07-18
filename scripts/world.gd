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

# Kill plane. Below this sit the boss dungeon's pit (arena disc at y=-16, catch
# floor at y=-40) and the flooded raid arena. Fall off the boss arena and you
# cross it: players teleport back to a town spawn; NPCs despawn. The flooded
# arena is EXEMPT (its whole floor is below this line) -- it has its own rule
# below, keyed off falling into a deep pool rather than a flat height.
const KILL_PLANE_Y := -34.0

# The flooded raid arena (Level C, see map_decorations._build_flooded_arena).
# Its walkable floor sits at y=-40 -- well under the kill plane -- so the global
# plane can't apply there. Instead, dropping below FLOOD_DEEP_OUT_Y means you've
# fallen into one of the deep pools: the players' own failure state. During a
# live dragon fight that means spectating; otherwise you're set back on the
# entrance ledge.
const FLOOD_ARENA_HALF_X := 17.5
const FLOOD_ARENA_HALF_Z := 28.5
const FLOOD_ARENA_TOP_Y := -16.0
const FLOOD_DEEP_OUT_Y := -42.5
const FLOOD_ENTRANCE := Vector3(0, -38.2, -27.0)

# The secret lunar area's teleport planes (see map_decorations._build_moon for
# the place itself; the low-gravity band is in player.gd). Both are server-side
# position checks, not colliders, so they can't be tunneled through at speed.
# Bounce above MOON_ENTRY_Y anywhere over the hub -> arrive in the sky above
# the moon and float down; fall past MOON_EXIT_Y anywhere around the moon
# (i.e., off any edge) -> dropped out of the sky high over town.
const MOON_ENTRY_Y := 85.0
const MOON_HUB_HALF := 62.0                    # "over the hub" bounds for entry
const MOON_ARRIVAL := Vector3(400, 275, 400)   # ~14m above the lunar surface
const MOON_EXIT_Y := 230.0
const MOON_REGION_HALF := 90.0                 # exit plane's span around the moon
const MOON_REENTRY := Vector3(0, 70, 8)        # high over the town spawn

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
	_enforce_moon_planes()
	var snapshot := {"players": {}, "items": {}, "npcs": {}, "projectiles": {}, "dragon": {}, "gemdoor": {}, "director": GameDirector.net_state()}
	for id in player_nodes:
		var p: Node3D = player_nodes[id]
		# "rot" is the MESH facing, not the body -- the body root never rotates
		# (see player.gd for why).
		snapshot["players"][id] = {"pos": p.global_position, "rot": p.mesh.rotation.y, "hat": p.wearing_hat, "helmet": p.wearing_helmet, "cowboy": p.wearing_cowboy_hat, "bunny": p.wearing_bunny_ears, "wizard": p.wearing_wizard_hat, "golden": p.wearing_golden_ears, "tumble": p.tumble, "spec": p.spectating, "slow": p.is_slowed()}
	for item in get_tree().get_nodes_in_group("sync_items"):
		snapshot["items"][item.get_path()] = {"xform": item.global_transform, "held": item.carried_by}
	for npc in get_tree().get_nodes_in_group("npc"):
		snapshot["npcs"][npc.get_path()] = {"pos": npc.global_position, "rot": npc.rotation.y, "tumble": npc.tumble, "slow": npc.is_slowed()}
	for proj in get_tree().get_nodes_in_group("sync_projectiles"):
		snapshot["projectiles"][proj.get_path()] = {"xform": proj.global_transform}
	for dragon in get_tree().get_nodes_in_group("sync_dragon"):
		snapshot["dragon"][dragon.get_path()] = {"head": dragon.head_root.global_transform, "vuln": dragon._vuln, "hits": dragon.hits, "enrage": dragon._enraged}
	for door in get_tree().get_nodes_in_group("sync_gem_door"):
		snapshot["gemdoor"][door.get_path()] = door.is_open
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
	for path in snapshot.get("dragon", {}):
		var dragon := get_node_or_null(path)
		if dragon:
			dragon.apply_remote_state(snapshot["dragon"][path])
	for path in snapshot.get("gemdoor", {}):
		var door := get_node_or_null(path)
		if door:
			door.apply_remote_state(snapshot["gemdoor"][path])
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
		if _in_flood_arena(p.global_position):
			# The flooded arena runs its own fall-in rule; the global plane (which
			# the whole arena floor sits beneath) does not apply here.
			if p.global_position.y < FLOOD_DEEP_OUT_Y:
				if _flood_fight_live():
					p.enter_spectator()
				else:
					p.respawn_at(FLOOD_ENTRANCE)
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


## Server-only. The lunar teleport planes: entry (bounce high over the hub) and
## exit (fall off the moon's edge). Simple position checks each physics frame.
func _enforce_moon_planes() -> void:
	for id in player_nodes:
		var p: Node3D = player_nodes[id]
		if p.spectating:
			continue
		var pos: Vector3 = p.global_position
		if pos.y > MOON_ENTRY_Y and absf(pos.x) < MOON_HUB_HALF and absf(pos.z) < MOON_HUB_HALF:
			p.global_position = MOON_ARRIVAL
			# Kill the launch: crest gently and float down in low gravity.
			p.velocity = Vector3(0, minf(p.velocity.y, 4.0), 0)
		elif pos.y < MOON_EXIT_Y and pos.y > MOON_EXIT_Y - 60.0 \
				and absf(pos.x - MOON_ARRIVAL.x) < MOON_REGION_HALF \
				and absf(pos.z - MOON_ARRIVAL.z) < MOON_REGION_HALF:
			p.global_position = MOON_REENTRY
			p.velocity = Vector3.ZERO


## Is this position inside the flooded raid arena's air space? (XZ footprint
## plus the deep-underground Y band, so it never collides with the hub above.)
func _in_flood_arena(pos: Vector3) -> bool:
	return pos.y < FLOOD_ARENA_TOP_Y \
		and absf(pos.x) < FLOOD_ARENA_HALF_X and absf(pos.z) < FLOOD_ARENA_HALF_Z


## Is the water dragon currently a live threat? (Falling into a deep pool only
## costs you the fight -- spectator -- while it is.)
func _flood_fight_live() -> bool:
	for d in get_tree().get_nodes_in_group("sync_dragon"):
		if d.fight_live():
			return true
	return false


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
	if not multiplayer.is_server():
		return
	match GameDirector.mode:
		GameDirector.Mode.BOSS:
			match new_state:
				GameDirector.COUNTDOWN:
					_spawn_boss_wave()
				GameDirector.PLAYING:
					_set_enemies_frozen(false)
					_mark_participants()
				GameDirector.ROUND_END:
					_despawn_boss_wave()
					_end_boss_players()
		GameDirector.Mode.RAID:
			match new_state:
				GameDirector.PLAYING:
					_rouse_dragon()
					_mark_participants()
				GameDirector.ROUND_END:
					_reset_dragon()
					_end_raid_players()


## Rouse / stand down the water dragon on the raid's PLAYING / ROUND_END edges.
func _rouse_dragon() -> void:
	for d in get_tree().get_nodes_in_group("sync_dragon"):
		d.begin_raid()


func _reset_dragon() -> void:
	for d in get_tree().get_nodes_in_group("sync_dragon"):
		d.reset_to_dormant()


## Raid over: restore anyone who fell in, setting them back on the entrance
## ledge. Survivors are left where they are so they can collect the draconite
## and climb out (the reward is a physical drop in the arena, unlike the
## Goblin Siege which just returns everyone to the hub).
func _end_raid_players() -> void:
	for id in player_nodes:
		var p: Node3D = player_nodes[id]
		if p.spectating:
			p.exit_spectator()
			p.respawn_at(FLOOD_ENTRANCE)


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
	var raid: bool = GameDirector.mode == GameDirector.Mode.RAID
	for id in player_nodes:
		var p: Node3D = player_nodes[id]
		var here := _in_flood_arena(p.global_position) if raid else _in_arena(p.global_position)
		if here:
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
