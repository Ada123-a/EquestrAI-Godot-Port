extends Node
class_name RestHandler

## Handles rest button mechanics and dynamic rest event creation
## Extracted from Main.gd to consolidate rest-related logic

# Dependencies (set by parent)
var event_manager = null

# Randomized text for variety
const PASS_TIME_LINES: Array = [
	"You take a moment to catch your breath, watching the world go by.",
	"Time slips away as you relax for a while.",
	"You wait patiently, letting the hours drift past.",
	"Finding a quiet spot, you rest and recover your energy.",
	"You spend some time gathering your thoughts."
]

const SLEEP_LINES: Array = [
	"Exhaustion overtakes you, and you drift into a deep sleep.",
	"You find a comfortable place to rest and settle in for the night.",
	"The day's events weigh heavy on you as you close your eyes until morning.",
	"You curl up and let sleep claim you, waking only with the morning sun.",
	"It's time to rest. You sleep soundly, restoring your strength for tomorrow."
]

func _ready() -> void:
	pass

## Handle rest button press - creates and starts a dynamic rest event
func on_rest_button_pressed() -> void:
	if event_manager == null:
		return
	
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	# Add leading space to ensure separation from the preceding choice text
	var pass_time_text = " " + PASS_TIME_LINES[rng.randi() % PASS_TIME_LINES.size()]
	var sleep_text = " " + SLEEP_LINES[rng.randi() % SLEEP_LINES.size()]
	
	# Create a dynamic event for resting logic
	# This ensures we use the exact same logic/visuals as standard events
	var rest_event = {
		"actions": [
			{
				"type": "branch",
				"prompt": " You find a moment to rest.", # Leading space for safety
				"options": [
					{
						"label": "Pass Time",
						"reverts_prompt": true,
						"condition": {
							"var_name": "time_slot",
							"operator": "!=",
							"value": 2 # Only show if NOT night
						},
						"actions": [
							{
								"type": "dialogue",
								"speaker_id": "narrator",
								"text": pass_time_text
							},
							{
								"type": "advance_time",
								"mode": "next_time_slot"
							}
						]
					},
					{
						"label": "Sleep",
						"reverts_prompt": true,
						"actions": [
							{
								"type": "dialogue",
								"speaker_id": "narrator",
								"text": sleep_text
							},
							{
								"type": "advance_time",
								"mode": "next_day_morning"
							}
						]
					},
					{
						"label": "Cancel",
						"reverts_prompt": true,
						"actions": []
					}
				]
			}
		]
	}
	
	event_manager.events["dynamic_rest"] = rest_event
	event_manager.start_event("dynamic_rest")
