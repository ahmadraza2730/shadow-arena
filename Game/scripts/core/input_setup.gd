extends Node
## InputSetup (autoload)
##
## Registers every input action in code when the game starts.
## Why: the Input Map stored in project.godot is long and hard to read or
## merge in Git. Keeping the bindings here makes them one easy table.
## To rebind a key, change it in the dictionaries below.

## Keyboard actions: action name -> list of physical keys.
const KEY_ACTIONS: Dictionary = {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_CTRL, KEY_C],
	"toggle_view": [KEY_V],
	"reload": [KEY_R],
	"fire_mode": [KEY_B],
	"weapon_primary": [KEY_1],
	"weapon_secondary": [KEY_2],
	"weapon_swap": [KEY_Q],
	"scoreboard": [KEY_TAB],
	"pause": [KEY_ESCAPE],
}

## Mouse actions: action name -> list of mouse buttons.
const MOUSE_ACTIONS: Dictionary = {
	"fire": [MOUSE_BUTTON_LEFT],
	"aim": [MOUSE_BUTTON_RIGHT],
}


func _enter_tree() -> void:
	# Autoloads enter the tree before the main scene, so every action
	# exists before any gameplay script asks for it.
	for action: String in KEY_ACTIONS:
		_ensure_action(action)
		for keycode: Key in KEY_ACTIONS[action]:
			var event := InputEventKey.new()
			# physical_keycode = key position, so WASD works on any layout.
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)

	for action: String in MOUSE_ACTIONS:
		_ensure_action(action)
		for button: MouseButton in MOUSE_ACTIONS[action]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			InputMap.action_add_event(action, event)


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
