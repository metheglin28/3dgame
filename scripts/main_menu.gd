extends Control

const WORLD_SCENE := "res://scenes/world.tscn"

@onready var name_edit: LineEdit = $Panel/VBox/NameEdit
@onready var ip_edit: LineEdit = $Panel/VBox/JoinRow/IpEdit
@onready var host_button: Button = $Panel/VBox/HostButton
@onready var join_button: Button = $Panel/VBox/JoinRow/JoinButton
@onready var status_label: Label = $Panel/VBox/StatusLabel


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)


func _player_name() -> String:
	var n := name_edit.text.strip_edges()
	return n if n != "" else "Player%d" % (randi() % 1000)


func _on_host_pressed() -> void:
	var err := NetworkManager.host_game(_player_name())
	if err != OK:
		status_label.text = "Couldn't host: error %d" % err
		return
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_join_pressed() -> void:
	var address := ip_edit.text.strip_edges()
	if address == "":
		address = "127.0.0.1"
	status_label.text = "Connecting to %s..." % address
	var err := NetworkManager.join_game(address, _player_name())
	if err != OK:
		status_label.text = "Couldn't connect: error %d" % err


func _on_connection_succeeded() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_connection_failed() -> void:
	status_label.text = "Connection failed. Check the IP and that the host is running."
