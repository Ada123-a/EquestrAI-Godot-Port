extends Control
class_name BaseStartFlow

signal finished(data)
signal closed
signal request_location_change(location_id)

var character_manager
var location_manager
var settings_manager
var llm_controller: LLMController

# Common UI elements
const PromptBuilderUtils = preload("res://scripts/PromptBuilder.gd")

func _ready():
	_setup_layout()

# Virtual methods to be overridden
func initialize(char_mgr, loc_mgr, settings_mgr, llm_ctrl: LLMController = null):
	character_manager = char_mgr
	location_manager = loc_mgr
	settings_manager = settings_mgr
	llm_controller = llm_ctrl
	
	if llm_controller:
		# Connect signals if needed, or rely on callbacks passed during request?
		# CustomStart waits for LLM response.
		# Ideally we listen to llm_controller.llm_response_received, but it broadcasts.
		# We might need to check if the response is meant for us.
		# For simplicity, CustomStart might need to connect to llm_client directly via controller access,
		# or LLMController supports a one-off callback?
		# Currently LLMController emits broadcast signals.
		# The start flow is likely exclusive (game not running).
		pass

func _setup_layout():
	pass

func _make_panel_style(alpha := 0.55) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, alpha)
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_color = Color(1, 1, 1, alpha * 0.4)
	return style

func _cancel():
	closed.emit()
	queue_free()

func _finish(data: Dictionary):
	finished.emit(data)
	queue_free()
