extends Node

## Singleton for debug settings that persist during the game session.
## Access via DebugSettings.get_instance() or autoload.

var navigation_narration_enabled: bool = false
var debug_commands_enabled: bool = false

static var _instance: Node = null

static func get_instance() -> Node:
	return _instance

func _enter_tree() -> void:
	_instance = self

func _exit_tree() -> void:
	if _instance == self:
		_instance = null
