extends Node
## Autoload singleton holding player-tunable control-feel settings, persisted
## to user://settings.cfg. UI (options_menu.gd) writes these and calls
## notify_changed(); the local player listens for `changed` and applies them.
##
## Movement-feel values are expressed as multipliers of the base constants in
## player.gd so defaults are obviously 1.0 and the server can clamp what a
## client sends it to the same ranges the sliders allow.

signal changed

const SAVE_PATH := "user://settings.cfg"
const BASE_SENSITIVITY := 0.0035

const SENS_RANGE := Vector2(0.2, 3.0)
const ACCEL_RANGE := Vector2(0.3, 2.5)
const JUMP_RANGE := Vector2(0.5, 1.8)
const CAMERA_RANGE := Vector2(1.5, 8.0)

var sens_mult := 1.0
var invert_y := false
var accel_mult := 1.0
var jump_mult := 1.0
var camera_distance := 4.5

var _save_pending := false


func _ready() -> void:
	load_from_disk()


func notify_changed() -> void:
	changed.emit()
	_queue_save()


func reset_to_defaults() -> void:
	sens_mult = 1.0
	invert_y = false
	accel_mult = 1.0
	jump_mult = 1.0
	camera_distance = 4.5
	notify_changed()


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	sens_mult = clampf(cfg.get_value("controls", "sens_mult", sens_mult), SENS_RANGE.x, SENS_RANGE.y)
	invert_y = bool(cfg.get_value("controls", "invert_y", invert_y))
	accel_mult = clampf(cfg.get_value("controls", "accel_mult", accel_mult), ACCEL_RANGE.x, ACCEL_RANGE.y)
	jump_mult = clampf(cfg.get_value("controls", "jump_mult", jump_mult), JUMP_RANGE.x, JUMP_RANGE.y)
	camera_distance = clampf(cfg.get_value("controls", "camera_distance", camera_distance), CAMERA_RANGE.x, CAMERA_RANGE.y)


func save_now() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "sens_mult", sens_mult)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "accel_mult", accel_mult)
	cfg.set_value("controls", "jump_mult", jump_mult)
	cfg.set_value("controls", "camera_distance", camera_distance)
	cfg.save(SAVE_PATH)


## Debounced save so dragging a slider (or scrolling the zoom wheel) doesn't
## hit the disk on every tick of the gesture.
func _queue_save() -> void:
	if _save_pending:
		return
	_save_pending = true
	await get_tree().create_timer(1.0).timeout
	_save_pending = false
	save_now()
