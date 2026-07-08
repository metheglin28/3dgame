extends Node
## Small autoload for cross-scene state that isn't network-related,
## like the mouse-capture toggle used by the interaction/menu flow.

var mouse_captured: bool = false

func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse_captured = true

func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mouse_captured = false

func toggle_mouse() -> void:
	if mouse_captured:
		release_mouse()
	else:
		capture_mouse()
