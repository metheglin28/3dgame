extends Node
## Autoload singleton. Owns the ENet peer and knows how to host or join a LAN game.
## Any script can read NetworkManager.player_names or listen to its signals.

signal player_connected(peer_id: int, player_name: String)
signal player_disconnected(peer_id: int)
signal server_disconnected
signal connection_failed
signal connection_succeeded

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 8

var player_names: Dictionary = {} # peer_id -> String
var my_player_name: String = "Player"

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Handle the window's X button ourselves (see _notification below).
	get_tree().auto_accept_quit = false


## Closing the window while hosting must disconnect gracefully BEFORE the
## process dies: an abruptly killed host trips an engine-level teardown crash
## (Godot 4.3) on every connected client. A clean peer close takes the same
## path as the Leave button, which clients handle fine.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		graceful_quit()


func graceful_quit() -> void:
	if multiplayer.multiplayer_peer == null:
		get_tree().quit()
		return
	leave_game()
	# Keep the process alive a few frames so ENet actually transmits the
	# disconnect handshake before we exit.
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()


func host_game(player_name: String, port: int = DEFAULT_PORT) -> Error:
	my_player_name = player_name
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	# The host counts as peer id 1 and registers itself immediately.
	player_names[1] = my_player_name
	return OK


func join_game(address: String, player_name: String, port: int = DEFAULT_PORT) -> Error:
	my_player_name = player_name
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	player_names.clear()


func is_host() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()


func _on_peer_connected(id: int) -> void:
	if is_host():
		# Tell the new peer about everyone who already exists, and tell everyone about the new peer.
		_register_player.rpc_id(id, 1, my_player_name)
		for existing_id in player_names:
			_register_player.rpc_id(id, existing_id, player_names[existing_id])


func _on_peer_disconnected(id: int) -> void:
	player_names.erase(id)
	player_disconnected.emit(id)


func _on_connected_to_server() -> void:
	var my_id := multiplayer.get_unique_id()
	_register_player.rpc(my_id, my_player_name)
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	player_names.clear()
	server_disconnected.emit()


@rpc("any_peer", "call_local", "reliable")
func _register_player(id: int, player_name: String) -> void:
	player_names[id] = player_name
	player_connected.emit(id, player_name)
