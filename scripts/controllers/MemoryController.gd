extends Node
class_name MemoryController

## Handles memory recording, summarization triggers, and context window management
## Extracted from Main.gd to consolidate memory-related logic

# Signals
signal context_warning_updated(should_show: bool, message: String)
signal context_debug_updated(debug_text: String)
signal summary_needed(force: bool)

# Dependencies (set by parent)
var memory_manager = null
var location_manager = null
var dialogue_display_manager = null

# UI references (set by parent)
var context_warning_panel: Panel = null
var context_warning_label: Label = null
var context_debug_label: Label = null

# State
var context_warning_dismissed: bool = false
var context_debug_visible: bool = false
var current_sequence_label: String = "scene"

func _ready() -> void:
	pass

## Set UI references for context warning and connect signals
func set_context_warning_ui(panel: Panel, label: Label, close_btn: Button, summarize_btn: Button) -> void:
	context_warning_panel = panel
	context_warning_label = label
	
	if close_btn:
		if not close_btn.pressed.is_connected(on_context_warning_close_pressed):
			close_btn.pressed.connect(on_context_warning_close_pressed)
			
	if summarize_btn:
		if not summarize_btn.pressed.is_connected(on_context_warning_summarize_pressed):
			summarize_btn.pressed.connect(on_context_warning_summarize_pressed)

# =============================================================================
# MEMORY RECORDING
# =============================================================================

## Record player's input to memory
func record_player_memory(text: String) -> void:
	if memory_manager == null or location_manager == null:
		return
	var cleaned: String = text.strip_edges()
	if cleaned == "":
		return
	var loc_id: String = location_manager.current_location_id
	var loc_name: String = _get_location_name(loc_id)
	var text_array: Array[String] = [cleaned]
	memory_manager.record_transcript_block(text_array, loc_id, loc_name, "user")
	_update_context_warning()
	_update_context_debug_label()

## Record raw AI response to memory
func record_raw_ai_memory(text: String, label: String = "llm_response") -> void:
	if memory_manager == null or location_manager == null:
		return
	var cleaned: String = text.strip_edges(true, false)  # Keep trailing space for continuity
	if cleaned.strip_edges() == "":
		return
	var loc_id: String = location_manager.current_location_id
	var loc_name: String = _get_location_name(loc_id)
	var text_array: Array[String] = [cleaned]
	memory_manager.record_transcript_block(text_array, loc_id, loc_name, label)
	_update_context_warning()
	_update_context_debug_label()

## Record the latest AI response (handles merge case)
func record_latest_ai_response() -> void:
	if dialogue_display_manager == null:
		return
	var raw_response: String = dialogue_display_manager.get_current_raw_response()
	if dialogue_display_manager.last_sequence_was_merge:
		if memory_manager == null or location_manager == null:
			return
		var cleaned: String = raw_response.strip_edges(true, false)  # Keep trailing space for continuity
		if cleaned.strip_edges() == "":
			return
		var loc_id: String = location_manager.current_location_id
		var loc_name: String = _get_location_name(loc_id)
		memory_manager.replace_last_entry(cleaned, loc_id, loc_name, current_sequence_label)
		_update_context_warning()
		_update_context_debug_label()
	else:
		record_raw_ai_memory(raw_response, current_sequence_label)

## Record location change to memory
func record_location_memory(previous_id: String, new_id: String) -> void:
	if memory_manager == null or previous_id == new_id:
		return
	# Don't record the initial setting of location as a "move"
	if previous_id == "":
		return
	var previous_name: String = _get_location_name(previous_id)
	var new_name: String = _get_location_name(new_id)
	memory_manager.record_location_change(previous_name, new_name, previous_id, new_id)
	_update_context_warning()
	_update_context_debug_label()

## Handle raw response updated (from edit mode)
func on_raw_response_updated(edited_text: String) -> void:
	if memory_manager == null or location_manager == null:
		return
	var loc_id: String = location_manager.current_location_id
	var loc_name: String = _get_location_name(loc_id)
	var history: Array[String] = []
	if dialogue_display_manager:
		history = dialogue_display_manager.get_raw_response_history()
	if history.is_empty():
		history.append(edited_text)
	memory_manager.replace_llm_history(history, loc_id, loc_name, current_sequence_label)
	trigger_memory_summary_if_needed()

# =============================================================================
# SUMMARIZATION
# =============================================================================

## Check if a memory summary should be triggered
func should_summarize() -> bool:
	if memory_manager == null:
		return false
	return memory_manager.should_summarize()

## Trigger memory summary if needed
func trigger_memory_summary_if_needed(force: bool = false) -> void:
	_update_context_warning()
	_update_context_debug_label()
	
	if memory_manager == null:
		return
	if not force and not memory_manager.should_summarize():
		return
	
	summary_needed.emit(force)

## Called when memory summary is completed
func on_summary_completed() -> void:
	context_warning_dismissed = false
	_hide_context_warning()
	_update_context_warning()
	_update_context_debug_label()

# =============================================================================
# CONTEXT WARNING UI
# =============================================================================

func _update_context_warning() -> void:
	if memory_manager == null:
		_update_context_debug_label()
		return
	
	var remaining_raw: int = memory_manager.get_remaining_until_summary(false)
	
	if remaining_raw > 15000:
		context_warning_dismissed = false
	
	if context_warning_dismissed:
		_hide_context_warning()
		_update_context_debug_label()
		return
	
	if remaining_raw <= 0:
		_hide_context_warning()
		_update_context_debug_label()
		return
	
	if remaining_raw > 5000:
		_hide_context_warning()
		_update_context_debug_label()
		return
	
	var display_remaining: int = max(remaining_raw, 0)
	var thousands: int = int(ceil(float(display_remaining) / 1000.0))
	var message: String = "%dk context from auto summarization." % thousands
	
	if context_warning_label:
		context_warning_label.text = message
	
	_show_context_warning()
	context_warning_updated.emit(true, message)
	_update_context_debug_label()

func _show_context_warning() -> void:
	if context_warning_panel:
		context_warning_panel.visible = true

func _hide_context_warning() -> void:
	if context_warning_panel:
		context_warning_panel.visible = false
	context_warning_updated.emit(false, "")

## Handle close button on context warning
func on_context_warning_close_pressed() -> void:
	context_warning_dismissed = true
	_hide_context_warning()

## Handle summarize button on context warning
func on_context_warning_summarize_pressed() -> void:
	context_warning_dismissed = false
	_hide_context_warning()
	trigger_memory_summary_if_needed(true)

## Public method to force refresh context UI
func refresh_context_ui() -> void:
	_update_context_warning()
	_update_context_debug_label()

# =============================================================================
# CONTEXT DEBUG LABEL
# =============================================================================

func _update_context_debug_label() -> void:
	if context_debug_label == null:
		return
	if not context_debug_visible:
		context_debug_label.visible = false
		return
	if memory_manager == null:
		context_debug_label.text = "Context: N/A"
		context_debug_label.visible = true
		return
	
	var used: int = memory_manager.get_current_context_size()
	var budget: int = memory_manager.get_context_budget()
	var remaining: int = memory_manager.get_remaining_until_summary(false)
	var pct: float = 100.0 * float(used) / float(budget) if budget > 0 else 0.0
	
	context_debug_label.text = "Context: %d / %d (%.1f%%) | %d to summary" % [used, budget, pct, remaining]
	context_debug_label.visible = true
	
	context_debug_updated.emit(context_debug_label.text)

## Toggle debug label visibility
func toggle_debug_visible() -> void:
	context_debug_visible = not context_debug_visible
	if context_debug_label:
		context_debug_label.visible = context_debug_visible
	_update_context_debug_label()

## Set visibility of debug label
func set_debug_visible(visible: bool) -> void:
	context_debug_visible = visible
	if context_debug_label:
		context_debug_label.visible = visible
	_update_context_debug_label()

# =============================================================================
# HELPERS
# =============================================================================

func _get_location_name(location_id: String) -> String:
	if location_manager == null:
		return ""
	var loc = location_manager.get_location(location_id)
	if loc:
		return loc.name
	return location_id

## Set the current sequence label for memory tracking
func set_sequence_label(label: String) -> void:
	current_sequence_label = label

## Get the current sequence label
func get_sequence_label() -> String:
	return current_sequence_label
