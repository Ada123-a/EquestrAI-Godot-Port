extends Node

const MORNING: int = 0
const DAY: int = 1
const NIGHT: int = 2
const DAYS_OF_WEEK = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
const TIME_SLOT_LABELS: Array[String] = ["Morning", "Day", "Night"]
const TIME_SLOT_KEYS: Array[String] = ["morning", "day", "night"]

# Reference to Main.gd
var main_node = null

# Fallback stats if main_node is not available
var _fallback_stats = {
	"current_location_id": "ponyville_main_square",
	"day_index": 0,
	"time_slot": MORNING
}

func _get_stats_ref() -> Dictionary:
	if main_node and main_node.get("global_vars") != null:
		return main_node.global_vars
	return _fallback_stats

# Used during initialization before main_node is injected, or if running standalone
var stats: Dictionary:
	get:
		return _get_stats_ref()

func update_stat(stat_name, value):
	# Ignore updates to "location" display name as we derive it
	if stat_name == "location":
		return
		
	var s = _get_stats_ref()
	if stat_name == "player_location" or stat_name == "current_location_id":
		s["current_location_id"] = value
	else:
		s[stat_name] = value
	print("Stat updated: ", stat_name, " = ", value)

func get_stats_string():
	var s = _get_stats_ref()
	var day_idx = s.get("day_index", 0)
	if typeof(day_idx) != TYPE_INT:
		day_idx = int(day_idx)
		
	var day_name = DAYS_OF_WEEK[day_idx % DAYS_OF_WEEK.size()]
	var time_str = get_time_slot_label(s.get("time_slot", MORNING))
	
	# Derive Location Name
	var loc_name = "Unknown"
	var loc_id = s.get("current_location_id", "ponyville_main_square")
	if main_node and main_node.location_manager:
		var loc = main_node.location_manager.get_location(loc_id)
		if loc:
			loc_name = loc.name
	
	return "Current Location: %s\nDay: %s\n%s" % [loc_name, day_name, time_str]

func advance_time():
	var s = _get_stats_ref()
	var current_slot = s.get("time_slot", MORNING)
	if typeof(current_slot) != TYPE_INT:
		current_slot = int(current_slot)
		
	current_slot = (current_slot + 1) % TIME_SLOT_LABELS.size()
	s["time_slot"] = current_slot
	
	if current_slot == MORNING:
		var d = s.get("day_index", 0)
		s["day_index"] = int(d) + 1
		print("Time advanced to Next Day (Morning)")
	else:
		print("Time advanced to %s" % get_time_slot_label(current_slot))

func get_time_slot_label(slot: int = -1) -> String:
	if slot == -1:
		slot = _get_stats_ref().get("time_slot", MORNING)
	
	if slot >= 0 and slot < TIME_SLOT_LABELS.size():
		return TIME_SLOT_LABELS[slot]
	return TIME_SLOT_LABELS[0]

func get_time_slot_key(slot: int = -1) -> String:
	if slot == -1:
		slot = _get_stats_ref().get("time_slot", MORNING)

	if slot >= 0 and slot < TIME_SLOT_KEYS.size():
		return TIME_SLOT_KEYS[slot]
	return TIME_SLOT_KEYS[0]
