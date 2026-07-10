extends Control
## In-game options panel for control feel, opened from the HUD's Options
## button (free the mouse with Esc first). Every slider applies live -- the
## local player listens to Settings.changed -- and persists via Settings.
## The UI is built in code; this node just needs to be a full-rect Control.

var _sens_slider: HSlider
var _invert_check: CheckBox
var _accel_slider: HSlider
var _jump_slider: HSlider
var _cam_slider: HSlider
var _value_labels: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	visibility_changed.connect(_sync_from_settings)
	_sync_from_settings()


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(440, 0)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Options"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	_sens_slider = _add_slider_row(vbox, "Mouse Sensitivity", Settings.SENS_RANGE, 0.05,
		func(v): Settings.sens_mult = v; Settings.notify_changed())

	_invert_check = CheckBox.new()
	_invert_check.text = "Invert Mouse Y"
	_invert_check.toggled.connect(func(on): Settings.invert_y = on; Settings.notify_changed())
	vbox.add_child(_invert_check)

	_accel_slider = _add_slider_row(vbox, "Movement Snappiness", Settings.ACCEL_RANGE, 0.05,
		func(v): Settings.accel_mult = v; Settings.notify_changed())
	_jump_slider = _add_slider_row(vbox, "Jump Strength", Settings.JUMP_RANGE, 0.05,
		func(v): Settings.jump_mult = v; Settings.notify_changed())
	_cam_slider = _add_slider_row(vbox, "Camera Distance", Settings.CAMERA_RANGE, 0.1,
		func(v): Settings.camera_distance = v; Settings.notify_changed())

	var buttons := HBoxContainer.new()
	vbox.add_child(buttons)
	var reset := Button.new()
	reset.text = "Reset to Defaults"
	reset.pressed.connect(func():
		Settings.reset_to_defaults()
		_sync_from_settings()
	)
	buttons.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): hide())
	buttons.add_child(close)


func _add_slider_row(parent: Control, label_text: String, value_range: Vector2, step: float, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(180, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = value_range.x
	slider.max_value = value_range.y
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(48, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	_value_labels[slider] = value_label
	slider.value_changed.connect(func(v):
		value_label.text = "%.2f" % v
		on_change.call(v)
	)
	return slider


## Push current Settings values into the widgets without re-triggering their
## change callbacks in a way that would matter (setting the same values back
## into Settings is harmless).
func _sync_from_settings() -> void:
	if _sens_slider == null:
		return
	_sens_slider.set_value_no_signal(Settings.sens_mult)
	_invert_check.set_pressed_no_signal(Settings.invert_y)
	_accel_slider.set_value_no_signal(Settings.accel_mult)
	_jump_slider.set_value_no_signal(Settings.jump_mult)
	_cam_slider.set_value_no_signal(Settings.camera_distance)
	for slider in _value_labels:
		_value_labels[slider].text = "%.2f" % slider.value
