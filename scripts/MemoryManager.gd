extends Node
class_name MemoryManager

const SUMMARY_CONTEXT_GAP: int = 10000

var settings_manager: SettingsManager = null
var max_context_limit: int = 32000
var auto_summary_limit: int = 20000

var rolling_summary: String = ""
var recent_entries: Array[Dictionary] = []

func set_settings_manager(manager: SettingsManager) -> void:
	settings_manager = manager
	_refresh_limits()

func _refresh_limits() -> void:
	if settings_manager == null:
		return
	max_context_limit = int(settings_manager.get_setting("max_context"))
	auto_summary_limit = int(settings_manager.get_setting("auto_summary_context"))
	var allowed_limit: int = max_context_limit - SUMMARY_CONTEXT_GAP
	if allowed_limit < 0:
		allowed_limit = 0
	auto_summary_limit = clamp(auto_summary_limit, 0, allowed_limit)

func record_transcript_block(lines: Array[String], location_id: String, location_name: String, entry_type: String = "scene") -> void:
	var clean_lines: Array[String] = []
	for line in lines:
		var trimmed: String = line.strip_edges(true, false)  # Keep trailing space for continuity
		if trimmed.strip_edges() != "":
			clean_lines.append(trimmed)
	if clean_lines.is_empty():
		return

	var entry_text: String = "\n".join(clean_lines)
	var entry: Dictionary = {
		"text": entry_text,
		"location_id": location_id,
		"location_name": location_name,
		"type": entry_type,
		"timestamp": Time.get_unix_time_from_system()
	}
	recent_entries.append(entry)

func record_location_change(previous_name: String, new_name: String, previous_id: String, new_id: String) -> void:
	if new_id == previous_id:
		return
	var text: String = "[location: %s]" % new_id
	record_transcript_block([text], new_id, new_name, "navigation")

func replace_last_entry(new_text: String, location_id: String, location_name: String, entry_type: String) -> void:
	var cleaned: String = new_text.strip_edges(true, false)  # Keep trailing space for continuity
	if cleaned.strip_edges() == "":
		return
	if recent_entries.is_empty():
		record_transcript_block([cleaned], location_id, location_name, entry_type)
		return
	var last_index: int = recent_entries.size() - 1
	var entry: Dictionary = recent_entries[last_index]
	entry["text"] = cleaned
	entry["location_id"] = location_id
	entry["location_name"] = location_name
	entry["type"] = entry_type
	entry["timestamp"] = Time.get_unix_time_from_system()
	recent_entries[last_index] = entry

## Remove the last entry from memory (for reverting prompts)
func pop_last_entry() -> void:
	if not recent_entries.is_empty():
		recent_entries.pop_back()

func replace_llm_history(texts: Array[String], location_id: String, location_name: String, entry_type: String = "llm_response") -> void:
	var cleaned_texts: Array[String] = []
	for text in texts:
		var trimmed: String = text.strip_edges(true, false)  # Keep trailing space for continuity
		if trimmed.strip_edges() != "":
			cleaned_texts.append(trimmed)
	if cleaned_texts.is_empty():
		return

	# Remove existing entries of the given type
	var filtered: Array[Dictionary] = []
	for entry in recent_entries:
		if entry.get("type", "") != entry_type:
			filtered.append(entry)

	# Append the new history entries in order
	var timestamp: int = Time.get_unix_time_from_system()
	for text in cleaned_texts:
		filtered.append({
			"text": text,
			"location_id": location_id,
			"location_name": location_name,
			"type": entry_type,
			"timestamp": timestamp
		})
		timestamp += 1

	recent_entries = filtered

func get_total_context_length() -> int:
	var total: int = rolling_summary.length()
	for entry in recent_entries:
		total += String(entry.get("text", "")).length()
	return total

func get_remaining_until_summary(include_summary_gap: bool = false) -> int:
	_refresh_limits()
	var remaining: int = auto_summary_limit - get_total_context_length()
	if include_summary_gap:
		remaining -= SUMMARY_CONTEXT_GAP
	return remaining

func get_summary_gap() -> int:
	return SUMMARY_CONTEXT_GAP

func get_auto_summary_limit() -> int:
	return auto_summary_limit

func get_max_context_limit() -> int:
	return max_context_limit

func should_summarize() -> bool:
	_refresh_limits()
	if auto_summary_limit <= 0:
		return false
	return get_total_context_length() >= auto_summary_limit

func build_context_block() -> String:
	var parts: Array[String] = []
	if rolling_summary.strip_edges() != "":
		parts.append("Long-term memory (summarized):")
		parts.append(rolling_summary)
	if not recent_entries.is_empty():
		for i in range(recent_entries.size()):
			var entry: Dictionary = recent_entries[i]
			var tag: String = entry.get("type", "scene")
			if tag == "player_input":
				tag = "user"
			var snippet: String = entry.get("text", "")
			# Filter out commands that the LLM doesn't need
			snippet = _filter_context_commands(snippet)
			if snippet.strip_edges() == "":
				continue  # Skip empty entries after filtering
			if tag == "user":
				parts.append("player \"%s\"" % snippet)
			else:
				parts.append(snippet)
	var result = "\n\n".join(parts)
	
	# Collapse triple+ newlines into double newlines
	var regex = RegEx.new()
	regex.compile("\\n{3,}")
	result = regex.sub(result, "\n\n", true)
	
	return result

## Filter out command lines that the LLM doesn't need to see in context
## This keeps sprite commands, enter/exit commands out of the story context
func _filter_context_commands(text: String) -> String:
	var lines: Array[String] = []
	for line in text.split("\n"):
		var trimmed: String = line.strip_edges()
		# Skip [Enter: tag] commands
		if trimmed.begins_with("[Enter:") and trimmed.ends_with("]"):
			continue
		# Skip [Exit: tag] commands  
		if trimmed.begins_with("[Exit:") and trimmed.ends_with("]"):
			continue
		# Skip (Sprite: tag emotion) commands
		if trimmed.begins_with("(Sprite:") and trimmed.ends_with(")"):
			continue
		lines.append(line)
	return "\n".join(lines)

func build_summary_request() -> Dictionary:
	var summary_prompt: String = ""
	if settings_manager:
		summary_prompt = str(settings_manager.get_setting("summary_prompt", ""))
	
	if summary_prompt.strip_edges() == "":
		summary_prompt = "Summarize the recent story events for continuity. Focus on key relationships and revelations."

	var system_lines: Array[String] = []
	system_lines.append(summary_prompt)

	var user_lines: Array[String] = []
	user_lines.append("Dialogue History:")
	user_lines.append(_build_history_payload())

	return {
		"system_prompt": "\n\n".join(system_lines),
		"user_prompt": "\n\n".join(user_lines)
	}

func apply_summary(summary_text: String) -> void:
	# Strip markdown fences if present since we just want the text
	var clean_text = summary_text.replace("```json", "").replace("```text", "").replace("```", "").strip_edges()
	rolling_summary = clean_text
	recent_entries.clear()

func _build_history_payload() -> String:
	var lines: Array[String] = []
	if rolling_summary.strip_edges() != "":
		lines.append("Existing summary:")
		lines.append(rolling_summary)
	for i in range(recent_entries.size()):
		var entry: Dictionary = recent_entries[i]
		var entry_type: String = entry.get("type", "scene")
		if entry_type == "player_input":
			entry_type = "user"
		var text: String = entry.get("text", "")
		if entry_type == "user":
			lines.append("user \"%s\"" % text)
		elif i == 0 and entry_type == "llm_response":
			lines.append(text)
		else:
			lines.append("[%s]" % entry_type)
			lines.append(text)
	return "\n".join(lines)
