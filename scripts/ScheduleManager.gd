extends Node
class_name ScheduleManager

const SCHEDULES_PATH: String = "res://assets/Schedules/schedules.json"
const TIME_SLOTS: Array[String] = ["morning", "day", "night"]

signal schedule_loaded(active_schedule_id: String)
signal active_schedule_changed(active_schedule_id: String)
signal location_assignments_rolled(location_id: String, time_slot: String, assignments: Array)

var schedule_sets: Dictionary = {}
var schedule_order: Array[String] = []
var active_schedule_id: String = ""
var assignment_cache: Dictionary = {}
var conversation_groups_cache: Dictionary = {}  # slot_key -> { location_id -> { tag -> group_id } }
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var location_manager: LocationManager = null

func _ready() -> void:
	rng.randomize()
	load_schedule_sets()

func load_schedule_sets() -> void:
	schedule_sets.clear()
	schedule_order.clear()
	active_schedule_id = ""
	assignment_cache.clear()
	conversation_groups_cache.clear()
	var file_data: Dictionary = _read_schedule_json()
	var schedule_array: Array = file_data.get("schedules", [])
	for entry in schedule_array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var normalized := _normalize_schedule_entry(entry)
		if normalized.is_empty():
			continue
		var schedule_id: String = normalized["id"]
		schedule_sets[schedule_id] = normalized
		schedule_order.append(schedule_id)
	var preferred_id: String = str(file_data.get("active_schedule_id", ""))
	if preferred_id != "" and schedule_sets.has(preferred_id):
		set_active_schedule(preferred_id)
	elif not schedule_order.is_empty():
		set_active_schedule(schedule_order[0])
	else:
		emit_signal("schedule_loaded", "")

func reload_from_disk() -> void:
	load_schedule_sets()

func set_active_schedule(schedule_id: String) -> bool:
	if not schedule_sets.has(schedule_id):
		return false
	active_schedule_id = schedule_id
	assignment_cache.clear()
	conversation_groups_cache.clear()
	emit_signal("schedule_loaded", active_schedule_id)
	emit_signal("active_schedule_changed", active_schedule_id)
	return true

func get_active_schedule_name() -> String:
	if active_schedule_id == "" or not schedule_sets.has(active_schedule_id):
		return ""
	var schedule: Dictionary = schedule_sets[active_schedule_id]
	return str(schedule.get("name", active_schedule_id))

func get_schedule_headers() -> Array:
	var headers: Array = []
	for schedule_id in schedule_order:
		var schedule: Dictionary = schedule_sets.get(schedule_id, {})
		var header: Dictionary = {
			"id": schedule_id,
			"name": str(schedule.get("name", schedule_id)),
			"character_count": 0
		}
		if schedule.has("characters") and typeof(schedule["characters"]) == TYPE_DICTIONARY:
			header["character_count"] = schedule["characters"].size()
		headers.append(header)
	return headers

func roll_location_assignments(location_id: String, day_index: int, time_slot: String) -> Array:
	var sanitized_slot: String = _sanitize_time_slot(time_slot)
	var result: Array = []
	var resolved_location_id: String = _normalize_location_id(location_id)
	if resolved_location_id == "" or sanitized_slot == "":
		return result
	if active_schedule_id == "" or not schedule_sets.has(active_schedule_id):
		return result
	var schedule: Dictionary = schedule_sets[active_schedule_id]
	var character_map: Dictionary = schedule.get("characters", {})
	if typeof(character_map) != TYPE_DICTIONARY:
		return result
	var slot_key: String = _build_assignment_key(day_index, sanitized_slot)
	for tag in character_map.keys():
		var tag_str := str(tag)
		var character_data: Dictionary = character_map[tag]
		var assigned_location: String = _get_assignment_for_character(tag_str, character_data, slot_key, sanitized_slot)
		if assigned_location == "" or assigned_location != resolved_location_id:
			continue
		var name: String = str(character_data.get("name", tag_str))
		var notes: Dictionary = {}
		if character_data.has("notes") and typeof(character_data["notes"]) == TYPE_DICTIONARY:
			notes = character_data["notes"]
		var note_text: String = str(notes.get(sanitized_slot, ""))
		result.append({
			"tag": tag_str,
			"name": name,
			"location_id": assigned_location,
			"location_identifier": _get_location_identifier(assigned_location),
			"time_slot": sanitized_slot,
			"schedule_id": active_schedule_id,
			"note": note_text,
			"group_id": "",
			"group_members": []
		})
	
	# Roll conversation groups for characters at this location
	_apply_conversation_groups(result, slot_key, resolved_location_id)
	
	emit_signal("location_assignments_rolled", location_id, sanitized_slot, result.duplicate(true))
	return result

func get_character_assignment(character_tag: String, day_index: int, time_slot: String) -> String:
	var sanitized_slot: String = _sanitize_time_slot(time_slot)
	if sanitized_slot == "" or character_tag == "":
		return ""
	if active_schedule_id == "" or not schedule_sets.has(active_schedule_id):
		return ""
	var schedule: Dictionary = schedule_sets[active_schedule_id]
	var character_map: Dictionary = schedule.get("characters", {})
	if typeof(character_map) != TYPE_DICTIONARY:
		return ""
	if not character_map.has(character_tag):
		return ""
	var slot_key: String = _build_assignment_key(day_index, sanitized_slot)
	var character_data: Dictionary = character_map[character_tag]
	return _get_assignment_for_character(character_tag, character_data, slot_key, sanitized_slot)

func clear_assignments_for_timeslot(day_index: int, time_slot: String) -> void:
	var sanitized_slot: String = _sanitize_time_slot(time_slot)
	if sanitized_slot == "":
		return
	var slot_key: String = _build_assignment_key(day_index, sanitized_slot)
	if assignment_cache.has(slot_key):
		assignment_cache.erase(slot_key)
	if conversation_groups_cache.has(slot_key):
		conversation_groups_cache.erase(slot_key)

func clear_all_assignments() -> void:
	assignment_cache.clear()
	conversation_groups_cache.clear()

func _get_assignment_for_character(tag: String, character_data: Dictionary, slot_key: String, time_slot: String) -> String:
	if not assignment_cache.has(slot_key):
		assignment_cache[slot_key] = {}
	var slot_assignments: Dictionary = assignment_cache[slot_key]
	if slot_assignments.has(tag):
		return str(slot_assignments[tag])
	var location_id: String = _roll_character_location(character_data, time_slot)
	location_id = _normalize_location_id(location_id)
	slot_assignments[tag] = location_id
	return location_id

func _roll_character_location(character_data: Dictionary, time_slot: String) -> String:
	# If no time_slots defined at all, character is unavailable
	if not character_data.has("time_slots") or typeof(character_data["time_slots"]) != TYPE_DICTIONARY:
		return ""
	var slot_entries: Array = character_data["time_slots"].get(time_slot, [])
	# If no entries for this specific time slot, character is unavailable (busy elsewhere)
	if slot_entries.is_empty():
		return ""
	var merged: Dictionary = {}
	for entry in slot_entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var location_id: String = _normalize_location_id(str(entry.get("location_id", "")))
		if location_id == "":
			continue
		var chance_value: float = float(entry.get("chance", 0.0))
		chance_value = clampf(chance_value, 0.0, 1.0)
		var merged_entry: Dictionary = merged.get(location_id, {
			"location_id": location_id,
			"weight": 0.0
		})
		merged_entry["weight"] += chance_value
		if entry.has("note") and not merged_entry.has("note"):
			merged_entry["note"] = str(entry["note"])
		merged[location_id] = merged_entry
	var weighted_entries: Array = []
	var total_weight: float = 0.0
	for merged_entry in merged.values():
		weighted_entries.append(merged_entry)
		total_weight += float(merged_entry.get("weight", 0.0))
	# If no valid entries after processing, character is unavailable
	if weighted_entries.is_empty() or total_weight <= 0.0:
		return ""
	
	# Roll using absolute probabilities
	var roll: float = rng.randf()
	
	# If total weight is less than 1.0, there's a chance of being unavailable
	# If total weight exceeds 1.0, we need to normalize (but this shouldn't happen with proper data)
	if total_weight < 1.0:
		# Use absolute probabilities - if roll exceeds total_weight, character is unavailable
		if roll > total_weight:
			return ""  # Character is busy elsewhere
		# Scale roll to be within the defined probability space
		roll = roll / total_weight * total_weight  # Keep roll in [0, total_weight] range
	
	var cumulative: float = 0.0
	for weighted_entry in weighted_entries:
		cumulative += weighted_entry["weight"]
		if roll <= cumulative:
			return weighted_entry["location_id"]
	
	# Fallback to last entry (should rarely happen due to floating point)
	return weighted_entries.back()["location_id"]

func _build_assignment_key(day_index: int, time_slot: String) -> String:
	return "%d_%s" % [day_index, time_slot]

func _sanitize_time_slot(time_slot: String) -> String:
	var lowered := time_slot.to_lower()
	for slot in TIME_SLOTS:
		if slot == lowered:
			return slot
	return ""

func _normalize_location_id(raw_id: String) -> String:
	var trimmed: String = raw_id.strip_edges()
	if trimmed == "":
		return ""
	if location_manager != null:
		return location_manager.resolve_location_id(trimmed)
	return trimmed

func _get_location_identifier(location_id: String) -> String:
	if location_manager != null:
		return location_manager.get_location_identifier(location_id)
	return location_id

func _normalize_schedule_entry(raw_entry: Dictionary) -> Dictionary:
	var schedule_id: String = str(raw_entry.get("id", "")).strip_edges()
	if schedule_id == "":
		return {}
	var normalized: Dictionary = {
		"id": schedule_id,
		"name": str(raw_entry.get("name", schedule_id)),
		"characters": {}
	}
	var character_block = raw_entry.get("characters", {})
	if typeof(character_block) == TYPE_DICTIONARY:
		for tag in character_block.keys():
			var tag_str := str(tag)
			var char_data = character_block[tag]
			if typeof(char_data) != TYPE_DICTIONARY:
				continue
			normalized["characters"][tag_str] = _normalize_character_entry(char_data, tag_str)
	return normalized

func _normalize_character_entry(raw_entry: Dictionary, fallback_tag: String) -> Dictionary:
	var normalized: Dictionary = raw_entry.duplicate(true)
	normalized["tag"] = str(normalized.get("tag", fallback_tag))
	if normalized["tag"] == "":
		normalized["tag"] = fallback_tag
	if not normalized.has("name"):
		normalized["name"] = str(normalized.get("tag", ""))
	normalized["default_location"] = _normalize_location_id(str(normalized.get("default_location", "")))
	if normalized.has("time_slots") and typeof(normalized["time_slots"]) == TYPE_DICTIONARY:
		for slot in TIME_SLOTS:
			var entries: Array = normalized["time_slots"].get(slot, [])
			var sanitized_entries: Array = []
			for entry in entries:
				if typeof(entry) != TYPE_DICTIONARY:
					continue
				var location_id: String = _normalize_location_id(str(entry.get("location_id", "")).strip_edges())
				if location_id == "":
					continue
				var chance_value: float = clampf(float(entry.get("chance", 0.0)), 0.01, 1.0)
				var sanitized_entry: Dictionary = {
					"location_id": location_id,
					"chance": chance_value
				}
				if entry.has("note"):
					sanitized_entry["note"] = str(entry["note"])
				sanitized_entries.append(sanitized_entry)
			normalized["time_slots"][slot] = sanitized_entries
	else:
		normalized["time_slots"] = {
			"morning": [],
			"day": [],
			"night": []
		}
	return normalized

func _read_schedule_json() -> Dictionary:
	if not FileAccess.file_exists(SCHEDULES_PATH):
		return {"schedules": [], "active_schedule_id": ""}
	var file := FileAccess.open(SCHEDULES_PATH, FileAccess.READ)
	if file == null:
		return {"schedules": [], "active_schedule_id": ""}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var error := json.parse(text)
	if error != OK:
		push_error("Failed to parse schedules file: %s" % json.get_error_message())
		return {"schedules": [], "active_schedule_id": ""}
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return {"schedules": [], "active_schedule_id": ""}
	return data

## Apply conversation groups to assignments at a location
## Groups are cached per timeslot, so traveling within the same timeslot preserves groups
func _apply_conversation_groups(assignments: Array, slot_key: String, location_id: String) -> void:
	if assignments.size() < 2:
		return  # Need at least 2 characters for grouping
	
	# Initialize cache structure if needed
	if not conversation_groups_cache.has(slot_key):
		conversation_groups_cache[slot_key] = {}
	var slot_groups: Dictionary = conversation_groups_cache[slot_key]
	
	# Check if we already have groups rolled for this location+timeslot
	if slot_groups.has(location_id):
		# Apply cached groups
		_apply_cached_groups(assignments, slot_groups[location_id])
		return
	
	# Roll new groups for this location
	var group_assignments: Dictionary = _roll_conversation_groups(assignments)
	slot_groups[location_id] = group_assignments
	
	# Debug: Log the groups that were created
	var groups_formed: Dictionary = {}
	for tag in group_assignments.keys():
		var gid: String = group_assignments[tag]
		if gid != "":
			if not groups_formed.has(gid):
				groups_formed[gid] = []
			groups_formed[gid].append(tag)
	if groups_formed.size() > 0:
		print("DEBUG: Conversation groups rolled for %s: %s" % [location_id, str(groups_formed)])
	else:
		print("DEBUG: No conversation groups formed at %s (all solo)" % location_id)
	
	# Apply the newly rolled groups
	_apply_cached_groups(assignments, group_assignments)

## Roll conversation groups for characters at a location
## Returns Dictionary mapping tag -> group_id (empty string if solo)
func _roll_conversation_groups(assignments: Array) -> Dictionary:
	var result: Dictionary = {}  # tag -> group_id
	var group_counter: int = 0
	var available_tags: Array[String] = []
	
	# Collect all tags
	for entry in assignments:
		var tag: String = str(entry.get("tag", ""))
		if tag != "":
			available_tags.append(tag)
			result[tag] = ""  # Initialize as solo
	
	# Process each character for potential pairing
	for tag in available_tags:
		if result[tag] != "":
			continue  # Already in a group
		
		# 20% chance to seek pairing
		if rng.randf() >= 0.20:
			continue  # Stays solo
		
		# Find available partners (not already grouped)
		var partners: Array[String] = []
		for other_tag in available_tags:
			if other_tag != tag and result[other_tag] == "":
				partners.append(other_tag)
		
		if partners.is_empty():
			continue  # No available partners
		
		# Create new group
		group_counter += 1
		var group_id: String = "group_%d" % group_counter
		result[tag] = group_id
		
		# Pick a random partner
		var partner_index: int = rng.randi_range(0, partners.size() - 1)
		var partner_tag: String = partners[partner_index]
		result[partner_tag] = group_id
		partners.remove_at(partner_index)
		
		# 25% chance to add more members (can chain for larger groups)
		while not partners.is_empty() and rng.randf() < 0.25:
			var next_index: int = rng.randi_range(0, partners.size() - 1)
			var next_tag: String = partners[next_index]
			result[next_tag] = group_id
			partners.remove_at(next_index)
	
	return result

## Apply cached group assignments to the assignment entries
func _apply_cached_groups(assignments: Array, group_assignments: Dictionary) -> void:
	# Build a lookup of group_id -> list of member names
	var group_members_lookup: Dictionary = {}  # group_id -> Array of {tag, name}
	for entry in assignments:
		var tag: String = str(entry.get("tag", ""))
		var group_id: String = group_assignments.get(tag, "")
		if group_id != "":
			if not group_members_lookup.has(group_id):
				group_members_lookup[group_id] = []
			group_members_lookup[group_id].append({
				"tag": tag,
				"name": str(entry.get("name", tag))
			})
	
	# Apply group info to each entry
	for entry in assignments:
		var tag: String = str(entry.get("tag", ""))
		var group_id: String = group_assignments.get(tag, "")
		entry["group_id"] = group_id
		if group_id != "" and group_members_lookup.has(group_id):
			entry["group_members"] = group_members_lookup[group_id].duplicate(true)
		else:
			entry["group_members"] = []

