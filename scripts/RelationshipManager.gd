extends Node

const SAVE_PATH = "user://character_relationships.json"
const MAX_HISTORY = 20
const MIN_DELTA_SCALE = 0.25
const MAX_RELATIONSHIP = 100.0

var relationships: Dictionary = {}

func _ready():
	_load()

func get_relationship_value(tag: String) -> float:
	return _get_entry(tag)["value"]

func get_relationship_descriptor(value: float) -> String:
	if value <= -60:
		return "hostile and openly dismissive"
	elif value <= -30:
		return "dislikes the player and keeps their distance"
	elif value < -10:
		return "wary and skeptical"
	elif value < 10:
		return "neutral acquaintance"
	elif value < 30:
		return "friendly and warming up"
	elif value < 60:
		return "close friend who trusts the player"
	else:
		return "deeply bonded and possibly romantic"

func adjust_relationship(tag: String, raw_delta: float, reason: String = "") -> float:
	if raw_delta == 0:
		return get_relationship_value(tag)
	var entry = _get_entry(tag)
	var weighted_delta = _calculate_weighted_delta(entry["value"], raw_delta)
	entry["value"] = clamp(entry["value"] + weighted_delta, -MAX_RELATIONSHIP, MAX_RELATIONSHIP)
	entry["value"] = round(entry["value"] * 100.0) / 100.0
	if reason != "":
		entry["last_reason"] = reason
	_save()
	return entry["value"]

func record_dialogue(tag: String, line: String):
	if line == "":
		return
	var entry = _get_entry(tag)
	if not entry.has("history"):
		entry["history"] = []
	entry["history"].append({
		"text": line.strip_edges(),
		"timestamp": Time.get_unix_time_from_system()
	})
	while entry["history"].size() > MAX_HISTORY:
		entry["history"].pop_front()
	_save()

func get_recent_dialogue_summary(tag: String, count: int = 3) -> String:
	var entry = _get_entry(tag)
	var history: Array = entry.get("history", [])
	if history.is_empty():
		return ""
	var start = max(history.size() - count, 0)
	var lines: Array = []
	for i in range(start, history.size()):
		var item = history[i]
		lines.append(item.get("text", ""))
	return "; ".join(lines)

func get_full_history(tag: String) -> Array:
	return _get_entry(tag).get("history", [])

func _get_entry(tag: String) -> Dictionary:
	var safe_tag = tag.strip_edges().to_lower()
	if safe_tag == "":
		safe_tag = "oc"
	if not relationships.has(safe_tag):
		relationships[safe_tag] = {
			"value": 0.0,
			"history": []
		}
	return relationships[safe_tag]

func _calculate_weighted_delta(current_value: float, raw_delta: float) -> float:
	var distance = clamp(abs(current_value) / MAX_RELATIONSHIP, 0.0, 1.0)
	var scale = lerp(1.0, MIN_DELTA_SCALE, distance)
	var clamped_delta = clamp(raw_delta, -15.0, 15.0)
	return clamped_delta * scale

func _save():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		return
	file.store_string(JSON.stringify(relationships))
	file.close()

func _load():
	if not FileAccess.file_exists(SAVE_PATH):
		relationships = {}
		return
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var content = file.get_as_text()
	file.close()
	if content == "":
		relationships = {}
		return
	var json = JSON.new()
	if json.parse(content) == OK:
		var data = json.get_data()
		if typeof(data) == TYPE_DICTIONARY:
			relationships = data
	else:
		relationships = {}
