extends Control

var llm_client
var stats_manager
var character_manager
var sprite_manager
var location_manager: LocationManager
var location_graph_manager
var game_manager
var music_manager
var settings_manager: SettingsManager
var relationship_manager
var schedule_manager: ScheduleManager
var map_manager
var event_manager: Node
var inventory_manager
var memory_manager: MemoryManager = null

# Controllers (extracted to reduce Main.gd size)
var llm_controller: LLMController = null
var memory_controller: MemoryController = null
var travel_manager: TravelManager = null
var rest_handler: RestHandler = null
var speak_controller: SpeakController = null
var debug_controller: DebugController = null

var background_rect
var current_settings_menu = null
var current_map_overlay = null
var current_quick_start = null

# New dialogue system
var dialogue_panel: EnhancedDialoguePanel = null
var dialogue_display_manager: DialogueDisplayManager = null
var pending_impersonation_request: bool = false
var end_scene_button: Button = null
var end_scene_request_active: bool = false
var location_nav_panel: PanelContainer = null
var location_nav_list: VBoxContainer = null
var location_nav_empty_label: Label = null
var location_schedule_label: Label = null
var top_bar: Control = null
var last_schedule_assignments: Array = []
var schedule_sprite_tags: Array[String] = []
var is_scene_active: bool = false
var exit_scene_after_sequence: bool = false
var travel_request_active: bool = false
var memory_summary_request_active: bool = false
var current_sequence_label: String = "scene"
var context_warning_panel: Panel = null
var context_warning_label: Label = null
var context_warning_close: Button = null
var context_warning_summarize_button: Button = null
var context_warning_dismissed: bool = false
var context_debug_label: Label = null
var context_debug_visible: bool = false
var global_vars: Dictionary = {}
var fade_overlay: ColorRect
var was_map_travel: bool = false


var main_menu
var game_ui_container: Control

func _ready():	
	# Initialize Settings Manager first
	settings_manager = load("res://scripts/SettingsManager.gd").new()
	add_child(settings_manager)
	
	# Initialize world state in global_vars if empty
	if not global_vars.has("day_index"):
		global_vars["day_index"] = 0
	if not global_vars.has("time_slot"):
		global_vars["time_slot"] = 0 # Morning
	if not global_vars.has("current_location_id"):
		global_vars["current_location_id"] = "ponyville_main_square"
	if not global_vars.has("location"):
		global_vars["location"] = "Ponyville Main Square"
	if not global_vars.has("valid_rest_locations"):
		global_vars["valid_rest_locations"] = []

	# Memory manager (conversation + navigation context)
	memory_manager = load("res://scripts/MemoryManager.gd").new()
	memory_manager.set_settings_manager(settings_manager)
	add_child(memory_manager)
	
	# Initialize other Managers
	stats_manager = load("res://scripts/StatsManager.gd").new()
	stats_manager.main_node = self
	add_child(stats_manager)

	relationship_manager = load("res://scripts/RelationshipManager.gd").new()
	add_child(relationship_manager)

	schedule_manager = load("res://scripts/ScheduleManager.gd").new()
	add_child(schedule_manager)

	character_manager = load("res://scripts/CharacterManager.gd").new()
	add_child(character_manager)
	
	location_manager = load("res://scripts/LocationManager.gd").new()
	add_child(location_manager)
	schedule_manager.location_manager = location_manager
	schedule_manager.reload_from_disk()

	location_graph_manager = load("res://scripts/LocationGraphManager.gd").new()
	add_child(location_graph_manager)

	map_manager = load("res://scripts/MapManager.gd").new()
	add_child(map_manager)
	
	music_manager = load("res://scripts/MusicManager.gd").new()
	add_child(music_manager)
	
	llm_client = load("res://scripts/LLMClient.gd").new()
	add_child(llm_client)
	llm_client.settings_manager = settings_manager
	# NOTE: LLMController handles llm_client signals now (see _setup_controllers)
	# The old handlers are kept but called via _on_llm_controller_response instead
	
	event_manager = load("res://scripts/EventManager.gd").new()
	add_child(event_manager)
	
	game_manager = load("res://scripts/GameManager.gd").new()
	add_child(game_manager)
	
	# Initialize Inventory Manager
	var inventory_manager = load("res://scripts/InventoryManager.gd").new()
	inventory_manager.main_node = self
	add_child(inventory_manager)
	inventory_manager.initialize_inventory()
	
	# Inject dependencies
	game_manager.stats_manager = stats_manager
	game_manager.location_manager = location_manager
	game_manager.location_graph_manager = location_graph_manager
	game_manager.character_manager = character_manager
	game_manager.llm_client = llm_client
	game_manager.sprite_manager = sprite_manager
	game_manager.relationship_manager = relationship_manager
	game_manager.settings_manager = settings_manager
	game_manager.schedule_manager = schedule_manager
	
	# Setup base layers (Background, Sprites)
	setup_base_layers()

	# Initialize Controllers (extracted from Main.gd for modularity)
	_setup_controllers()

	event_manager.main_node = self
	event_manager.location_manager = location_manager
	event_manager.character_manager = character_manager
	event_manager.sprite_manager = sprite_manager
	event_manager.llm_client = llm_client
	event_manager.dialogue_display_manager = dialogue_display_manager # Will be null here, needs update in _setup_enhanced_dialogue_panel
	event_manager.request_branch.connect(_on_event_branch_requested)
	event_manager.request_persona_editor.connect(_on_persona_editor_requested)
	event_manager.event_started.connect(func(_id): 
		# Reset free roam conversation flags when event starts
		exit_scene_after_sequence = false
		end_scene_request_active = false
		_set_scene_active(true)
	)
	event_manager.event_finished.connect(func(): _enter_free_roam_mode())
	
	# Make Inventory Manager accessible via GameManager or directly if needed
	# For now, we can access it via helper or just keep it as child
	game_manager.set_meta("inventory_manager", inventory_manager) 
	
	# Show Main Menu
	show_main_menu()
	
	_setup_custom_cursors()

func _setup_custom_cursors():
	# Default Arrow (Unicorn Horn) - Tip shifted to 2,2
	_set_cursor("res://assets/UI/Cursors/MLP/mlp_arrow.png", Input.CURSOR_ARROW, Vector2(2, 2))
	
	# Pointing Hand (Magic Aura Horn) - Tip shifted to 2,2
	_set_cursor("res://assets/UI/Cursors/MLP/mlp_select.png", Input.CURSOR_POINTING_HAND, Vector2(2, 2))
	
	# Text IBeam - Center at x=16, y=16
	_set_cursor("res://assets/UI/Cursors/MLP/mlp_ibeam.png", Input.CURSOR_IBEAM, Vector2(16, 16))
	
	# Busy / Wait - Center (Using frame 1 of animation)
	_set_cursor("res://assets/UI/Cursors/MLP/mlp_busy_1.png", Input.CURSOR_WAIT, Vector2(16, 16))
	_set_cursor("res://assets/UI/Cursors/MLP/mlp_busy_1.png", Input.CURSOR_BUSY, Vector2(16, 16))
	
	# Move - Center
	_set_cursor("res://assets/UI/Cursors/MLP/mlp_move.png", Input.CURSOR_DRAG, Vector2(16, 16))
	_set_cursor("res://assets/UI/Cursors/MLP/mlp_move.png", Input.CURSOR_CAN_DROP, Vector2(16, 16))
	_set_cursor("res://assets/UI/Cursors/MLP/mlp_move.png", Input.CURSOR_CROSS, Vector2(16, 16))
	
	# Resize (Use Move cursor as fallback or reuse arrows if we had them)
	# For now, reusing move or keeping defaults if specific resize cursors aren't generated
	# But we generated a move cursor which is a 4-way arrow.
	_set_cursor("res://assets/UI/Cursors/MLP/mlp_move.png", Input.CURSOR_HSIZE, Vector2(16, 16))
	_set_cursor("res://assets/UI/Cursors/MLP/mlp_move.png", Input.CURSOR_VSIZE, Vector2(16, 16)) 

func _set_cursor(path: String, type: int, hotspot: Vector2 = Vector2.ZERO):
	if FileAccess.file_exists(path):
		var texture = load(path)
		if texture:
			Input.set_custom_mouse_cursor(texture, type, hotspot)



func setup_base_layers():
	# Create background
	background_rect = TextureRect.new()
	background_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background_rect.stretch_mode = TextureRect.STRETCH_SCALE
	background_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	background_rect.z_index = -200  # Behind sprites (-100 to -98) and UI (0)
	add_child(background_rect)

	# Sprite Manager (on top of BG)
	sprite_manager = load("res://scripts/SpriteManager.gd").new()
	sprite_manager.set_anchors_preset(Control.PRESET_FULL_RECT)
	sprite_manager.sprite_clicked.connect(_on_sprite_clicked)
	add_child(sprite_manager)

	# Fade Overlay (on top of everything but UI might be higher, z_index of 100 should cover game world)
	fade_overlay = ColorRect.new()
	fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_overlay.color = Color(0, 0, 0, 0) # Transparent start
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE # Don't block clicks when invisible
	fade_overlay.z_index = 100 # High enough to cover sprites
	add_child(fade_overlay)

	# Update game_manager dependency since sprite_manager is created here
	game_manager.sprite_manager = sprite_manager

## Initialize all extracted controllers and wire their dependencies
func _setup_controllers() -> void:
	# LLM Controller - handles all LLM requests/responses
	llm_controller = LLMController.new()
	llm_controller.llm_client = llm_client
	llm_controller.settings_manager = settings_manager
	llm_controller.location_manager = location_manager
	llm_controller.location_graph_manager = location_graph_manager
	llm_controller.character_manager = character_manager
	llm_controller.memory_manager = memory_manager
	llm_controller.stats_manager = stats_manager
	llm_controller.event_manager = event_manager  # For checking waiting_for_dialogue
	llm_controller.connect_llm_client(llm_client)
	llm_controller.llm_response_received.connect(_on_llm_controller_response)
	llm_controller.llm_error_occurred.connect(_on_llm_controller_error)
	llm_controller.impersonation_completed.connect(_on_impersonation_completed)
	llm_controller.memory_summary_completed.connect(_on_memory_summary_completed)
	add_child(llm_controller)
	
	# Memory Controller - handles memory recording and context warnings
	memory_controller = MemoryController.new()
	memory_controller.memory_manager = memory_manager
	memory_controller.location_manager = location_manager
	memory_controller.summary_needed.connect(_on_memory_summary_needed)
	add_child(memory_controller)
	
	# Travel Manager - handles location transitions
	travel_manager = TravelManager.new()
	travel_manager.location_manager = location_manager
	travel_manager.location_graph_manager = location_graph_manager
	travel_manager.character_manager = character_manager
	travel_manager.sprite_manager = sprite_manager
	travel_manager.stats_manager = stats_manager
	travel_manager.music_manager = music_manager
	travel_manager.memory_controller = memory_controller
	travel_manager.background_rect = background_rect
	travel_manager.global_vars = global_vars
	travel_manager.travel_started.connect(_on_travel_started)
	travel_manager.travel_completed.connect(_on_travel_completed)
	travel_manager.location_changed.connect(_on_location_changed_by_travel)
	travel_manager.enter_free_roam_requested.connect(_enter_free_roam_mode)
	add_child(travel_manager)
	travel_manager.travel_narration_generated.connect(_on_travel_narration_generated)
	
	# Rest Handler - handles rest button mechanics
	rest_handler = RestHandler.new()
	rest_handler.event_manager = event_manager
	add_child(rest_handler)
	
	# Speak Controller - handles speak-to-character panel
	speak_controller = SpeakController.new()
	speak_controller.character_manager = character_manager
	speak_controller.sprite_manager = sprite_manager
	speak_controller.last_schedule_assignments = last_schedule_assignments
	speak_controller.schedule_sprite_tags = schedule_sprite_tags
	speak_controller.speak_conversation_started.connect(_on_speak_conversation_started)
	speak_controller.scene_mode_requested.connect(func(active): _set_scene_active(active))
	add_child(speak_controller)
	
	# Debug Controller - handles debug menu
	debug_controller = DebugController.new()
	debug_controller.character_manager = character_manager
	debug_controller.sprite_manager = sprite_manager
	debug_controller.schedule_sprite_tags = schedule_sprite_tags
	debug_controller.last_schedule_assignments = last_schedule_assignments
	debug_controller.character_added.connect(func(_tag): _update_schedule_label(last_schedule_assignments))
	add_child(debug_controller)

func show_main_menu():
	if main_menu == null:
		var menu_scene = load("res://scenes/ui/MainMenuUI.tscn")
		main_menu = menu_scene.instantiate()
		main_menu.open_quick_start.connect(_on_open_quick_start)
		main_menu.open_options.connect(_on_open_options)
		main_menu.open_custom_start.connect(_on_open_custom_start)
		main_menu.open_debug_start.connect(_on_open_debug_start)

		main_menu.resume_game.connect(_on_resume_game)
		add_child(main_menu)

	# Update resume button visibility based on whether game is active
	if main_menu and game_ui_container:
		main_menu.set_game_active(game_ui_container.visible or (game_ui_container != null and not main_menu.visible))

	main_menu.visible = true

	if game_ui_container:
		game_ui_container.visible = false

func _on_resume_game():
	if main_menu:
		main_menu.visible = false
	if game_ui_container:
		game_ui_container.visible = true

func _on_open_quick_start():
	if main_menu:
		main_menu.visible = false
	if game_ui_container == null:
		setup_game_ui()
	game_ui_container.visible = true
	
	# Ensure dialogue panel is ready
	if dialogue_display_manager == null or dialogue_panel == null:
		_setup_enhanced_dialogue_panel()
	
	# Start the event
	event_manager.start_event("Quick Start")

func _on_event_branch_requested(options: Array):
	# Show choices in the dialogue panel
	if dialogue_display_manager:
		dialogue_display_manager.display_choices(options)

# Helper to connect back to event manager when choice is made
func _on_choice_selected(index: int, options: Array):
	print("Main: _on_choice_selected index=", index)
	event_manager.select_branch_option(index, options)

var current_persona_editor_popup = null

## Called when an event requests the persona editor popup
func _on_persona_editor_requested():
	print("DEBUG Main: _on_persona_editor_requested called")
	if current_persona_editor_popup != null:
		print("DEBUG Main: Popup already open")
		return
	
	# Load and show the persona editor popup
	var path = "res://scenes/ui/PersonaEditorPopup.tscn"
	if not FileAccess.file_exists(path):
		push_warning("PersonaEditorPopup.tscn not found at " + path)
		event_manager.on_persona_editor_closed()
		return
		
	var popup_scene = load(path)
	if popup_scene:
		current_persona_editor_popup = popup_scene.instantiate()
		current_persona_editor_popup.set_settings_manager(settings_manager)
		current_persona_editor_popup.editor_closed.connect(_on_persona_editor_popup_closed)
		
		# Ensure it's on top of everything
		current_persona_editor_popup.z_index = 4096 
		if "visible" in current_persona_editor_popup:
			current_persona_editor_popup.visible = true
		
		add_child(current_persona_editor_popup)
		
		# Force Geometry
		if current_persona_editor_popup is Control:
			current_persona_editor_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	else:
		# Fallback: just continue the event if scene doesn't exist
		push_warning("PersonaEditorPopup.tscn load failed")
		event_manager.on_persona_editor_closed()

func _on_persona_editor_popup_closed():
	if current_persona_editor_popup:
		current_persona_editor_popup.queue_free()
		current_persona_editor_popup = null
	# Notify event manager to continue
	event_manager.on_persona_editor_closed()

func _on_open_options():
	if current_settings_menu != null:
		return

	# Hide main menu
	if main_menu:
		main_menu.visible = false

	var settings_scene = load("res://scenes/ui/SettingsUI.tscn")
	var settings_menu = settings_scene.instantiate()
	settings_menu.set_settings_manager(settings_manager)
	settings_menu.settings_closed.connect(_on_settings_closed)
	add_child(settings_menu)
	current_settings_menu = settings_menu

func _on_settings_closed():
	current_settings_menu = null
	# Resume game if it was active, otherwise show main menu
	if game_ui_container and game_ui_container != null:
		# Game was active, resume it
		game_ui_container.visible = true
	elif main_menu:
		# No game active, show main menu
		main_menu.visible = true

var current_custom_start = null

var current_debug_menu = null
var speak_to_character_panel = null

func _on_open_custom_start():
	if current_custom_start != null:
		return

	# Hide main menu
	if main_menu:
		main_menu.visible = false

	var custom_start_scene = load("res://scenes/ui/CustomStartUI.tscn")
	var custom_start = custom_start_scene.instantiate()
	custom_start.initialize(character_manager, location_manager, settings_manager, llm_controller)
	custom_start.finished.connect(_on_custom_start_finished)
	custom_start.closed.connect(_on_custom_start_closed)
	custom_start.request_location_change.connect(func(loc_id): change_location(loc_id))
	add_child(custom_start)
	current_custom_start = custom_start

func _on_custom_start_closed():
	current_custom_start = null
	# Show main menu again
	if main_menu:
		main_menu.visible = true

func _on_open_debug_start():
	# Hide main menu
	if main_menu:
		main_menu.visible = false

	# Setup game UI if needed
	if game_ui_container == null:
		setup_game_ui()
	game_ui_container.visible = true

	# Change to Ponyville Main Square (this triggers schedule roll and sprite display)
	var start_location_id: String = "ponyville_main_square"
	change_location(start_location_id)

	# Setup the dialogue panel if needed
	if dialogue_display_manager == null or dialogue_panel == null:
		_setup_enhanced_dialogue_panel()

	# Enter free roam mode immediately (shows travel menu)
	_enter_free_roam_mode()

	# Display a simple welcome message
	if dialogue_panel:
		dialogue_panel.display_narration("You find yourself in the heart of Ponyville's Main Square.", false)

func _on_custom_start_finished(data):
	current_custom_start = null
	if game_ui_container == null:
		setup_game_ui()
	game_ui_container.visible = true
	var start_location_id: String = str(data.get("start_location_id", ""))
	if start_location_id.strip_edges() == "":
		start_location_id = "ponyville_main_square"
	
	# We process the location change as part of the event mainly, but pre-setting it helps avoid glitches
	change_location(start_location_id)
	
	var plan_text: String = data.get("plan_text", "")
	var scene_text: String = data.get("scene_text", "")
	var selected_tags: Array = data.get("selected_tags", [])
	
	if dialogue_display_manager == null or dialogue_panel == null:
		_setup_enhanced_dialogue_panel()
		
	# If we have legacy scene text, just run it (fallback)
	if scene_text.strip_edges() != "":
		_on_llm_response_enhanced(scene_text)
	elif plan_text.strip_edges() != "":
		# Construct a Dynamic Event based on the Plan
		var dynamic_event = {
			"id": "Custom Start Dynamic",
			"actions": []
		}
		
		# 1. Location
		dynamic_event["actions"].append({
			"type": "change_location",
			"location_id": start_location_id
		})
		
		# 2. LLM Prompt - PromptBuilder handles character appearance and formatting
		dynamic_event["actions"].append({
			"type": "llm_prompt",
			"user_prompt": "Write the opening scene based on the following approved plan:\n\n%s" % plan_text,
			"characters": selected_tags.duplicate()
		})
		
		# 3. End Event (Clean up)
		dynamic_event["actions"].append({
			"type": "end_event"
		})
		
		# Inject and Start
		if event_manager:
			event_manager.events["Custom Start Dynamic"] = dynamic_event
			print("Starting Dynamic Event with Plan: ", plan_text.left(100), "...")
			event_manager.start_event("Custom Start Dynamic")
			
	if main_menu:
		main_menu.visible = false



func _on_open_map():
	if current_map_overlay != null:
		return

	# Fade out (black screen)
	var tween = fade_screen(false, 0.5)
	if tween:
		tween.tween_callback(_open_map_step2)
	else:
		_open_map_step2()

func _open_map_step2():
	if game_ui_container:
		game_ui_container.visible = false
	
	var map_scene = load("res://scenes/ui/MapOverlayUI.tscn")
	var map_ui = map_scene.instantiate()
	map_ui.initialize(location_manager, map_manager, schedule_manager, character_manager, self)
	map_ui.location_selected.connect(_on_map_location_selected)
	map_ui.map_closed.connect(_on_map_closed)
	add_child(map_ui)
	current_map_overlay = map_ui
	
	if music_manager:
		var music_to_play = ""
		# Try to find correct music for current region
		if location_manager and map_manager:
			var loc = location_manager.get_location(location_manager.current_location_id)
			if loc:
				var map_data = map_manager.get_map_for_region(loc.region)
				if map_data and map_data.music_path != "":
					music_to_play = map_data.music_path
		
		# Fallback
		if music_to_play == "" and map_manager and map_manager.default_map_id != "":
			var def = map_manager.maps.get(map_manager.default_map_id)
			if def: music_to_play = def.music_path
			
		music_manager.play_temporary_music(music_to_play, 0.5)
	
	# Fade back in (show map)
	fade_screen(true, 0.5)

func _on_map_location_selected(loc_id: String):
	was_map_travel = change_location(loc_id)

func _on_map_closed():
	# Fade out (black screen)
	var tween = fade_screen(false, 0.5)
	if tween:
		tween.tween_callback(_close_map_step2)
	else:
		_close_map_step2()

func _close_map_step2():
	if current_map_overlay:
		current_map_overlay.queue_free()
		current_map_overlay = null
	
	# Always restore UI visibility
	if game_ui_container:
		game_ui_container.visible = true
	
	if was_map_travel:
		# Music already changed by change_location
		pass
	else:
		# Restore previous music only if we didn't travel
		if music_manager:
			music_manager.restore_saved_music(0.5)
	
	was_map_travel = false
	
	# Fade back in (show game/new location)
	fade_screen(true, 0.5)

var current_inventory_panel = null
func _toggle_inventory():
	if current_inventory_panel != null:
		current_inventory_panel.queue_free()
		current_inventory_panel = null
		return

	var inv_scene = load("res://scenes/ui/InventoryPanel.tscn")
	current_inventory_panel = inv_scene.instantiate()
	add_child(current_inventory_panel)
	current_inventory_panel.initialize(game_manager.get_meta("inventory_manager"))
	current_inventory_panel.closed.connect(func(): 
		if current_inventory_panel:
			current_inventory_panel.queue_free()
			current_inventory_panel = null
	)

func _on_quick_start_finished(data):
	current_quick_start = null
	if game_ui_container == null:
		setup_game_ui()
	game_ui_container.visible = true
	change_location("golden_oak_library")

	# Get the scene text from quick start
	var scene_text = data.get("scene_text", "Welcome to Ponyville.")

	# Use the enhanced dialogue system (initialize if needed)
	if dialogue_display_manager == null or dialogue_panel == null:
		_setup_enhanced_dialogue_panel()
	if dialogue_display_manager and dialogue_panel:
		_on_llm_response_enhanced(scene_text)

	# Keep main menu hidden so the player can continue exploring
	if main_menu:
		main_menu.visible = false

func _on_quick_start_closed():
	current_quick_start = null
	if game_ui_container:
		game_ui_container.visible = false
	if main_menu:
		main_menu.visible = true

func setup_game_ui():
	var game_ui_scene = load("res://scenes/ui/GameUI.tscn")
	game_ui_container = game_ui_scene.instantiate()
	add_child(game_ui_container)

	context_warning_panel = game_ui_container.get_node_or_null("ContextWarningPanel") as Panel
	if context_warning_panel:
		context_warning_label = game_ui_container.get_node_or_null("ContextWarningPanel/ContextWarningMargin/ContextWarningHBox/ContextWarningLabel") as Label
		context_warning_close = game_ui_container.get_node_or_null("ContextWarningPanel/ContextWarningMargin/ContextWarningHBox/ContextWarningClose") as Button
		context_warning_summarize_button = game_ui_container.get_node_or_null("ContextWarningPanel/ContextWarningMargin/ContextWarningHBox/ContextSummarizeButton") as Button
		
		# Assign to controller
		if memory_controller:
			memory_controller.set_context_warning_ui(context_warning_panel, context_warning_label, context_warning_close, context_warning_summarize_button)
			
	context_debug_label = game_ui_container.get_node_or_null("ContextDebugLabel") as Label
	if memory_controller:
		memory_controller.context_debug_label = context_debug_label

	location_nav_panel = game_ui_container.get_node_or_null("LocationNavPanel") as PanelContainer
	if location_nav_panel:
		location_nav_list = location_nav_panel.get_node_or_null("NavMargin/NavVBox/LocationList") as VBoxContainer
		location_nav_empty_label = location_nav_panel.get_node_or_null("NavMargin/NavVBox/EmptyLabel") as Label
		location_schedule_label = location_nav_panel.get_node_or_null("NavMargin/NavVBox/ScheduleLabel") as Label
		_update_schedule_label(last_schedule_assignments)
	_update_navigation_visibility()
	_refresh_neighbor_list()

	# Setup enhanced dialogue system
	_setup_enhanced_dialogue_panel()

	top_bar = game_ui_container.get_node_or_null("TopBar")
	var settings_btn = game_ui_container.get_node("TopBar/SettingsButton")
	settings_btn.pressed.connect(show_main_menu)
	end_scene_button = game_ui_container.get_node("TopBar/EndSceneButton")
	end_scene_button.visible = false
	end_scene_button.pressed.connect(_on_end_scene_pressed)
	
	var map_btn = game_ui_container.get_node("TopBar/MapButton")
	map_btn.pressed.connect(_on_open_map)

	var inv_btn = game_ui_container.get_node("TopBar/InventoryButton")
	if inv_btn:
		inv_btn.pressed.connect(_toggle_inventory)





func _set_scene_active(active: bool) -> void:
	is_scene_active = active
	_update_navigation_visibility()
	
	# Enable/disable click-to-continue based on scene state
	# When active, clicking dialogue box should allow advancing; when inactive (free roam), it shouldn't
	if dialogue_panel:
		dialogue_panel.set_click_to_continue_enabled(active)

func _has_active_characters() -> bool:
	if character_manager == null:
		return false
	return character_manager.active_characters.size() > 0

func _update_navigation_visibility() -> void:
	if location_nav_panel:
		location_nav_panel.visible = not is_scene_active
	if top_bar:
		top_bar.visible = not is_scene_active

func _refresh_neighbor_list() -> void:
	if location_nav_list == null:
		return

	for child in location_nav_list.get_children():
		child.queue_free()

	if location_manager == null or location_graph_manager == null:
		if location_nav_empty_label:
			location_nav_empty_label.visible = true
			location_nav_empty_label.text = "Navigation data unavailable."
		return

	var neighbors: Array = location_graph_manager.get_neighbors_with_names(
		location_manager.current_location_id,
		location_manager
	)
	
	# Check for valid rest location
	var can_rest: bool = false
	if not is_scene_active:
		var loc_id = global_vars.get("current_location_id", "")
		# Fallback to checking location manager if global var assumes sync
		if loc_id == "" and location_manager:
			loc_id = location_manager.current_location_id
			
		var valid_locs = global_vars.get("valid_rest_locations", [])
		if loc_id in valid_locs:
			can_rest = true

	if neighbors.is_empty() and not can_rest:
		if location_nav_empty_label:
			location_nav_empty_label.visible = true
			location_nav_empty_label.text = "No nearby locations."
		return

	if location_nav_empty_label:
		location_nav_empty_label.visible = false

	for neighbor_dict in neighbors:
		var neighbor_id: String = str(neighbor_dict.get("id", ""))
		if neighbor_id == "":
			continue
		var neighbor_name: String = str(neighbor_dict.get("name", neighbor_id))
		var nav_button: Button = Button.new()
		nav_button.text = neighbor_name
		nav_button.set_text_alignment(HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)
		nav_button.custom_minimum_size = Vector2(0, 36)
		nav_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nav_button.pressed.connect(Callable(self, "_on_navigation_target_selected").bind(neighbor_id))
		location_nav_list.add_child(nav_button)
		
	if can_rest:
		var r_btn: Button = Button.new()
		r_btn.text = "Rest"
		r_btn.set_text_alignment(HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT)
		r_btn.custom_minimum_size = Vector2(0, 36)
		r_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r_btn.pressed.connect(_on_rest_button_pressed)
		location_nav_list.add_child(r_btn)

func _enter_free_roam_mode() -> void:
	print("DEBUG: _enter_free_roam_mode called")
	travel_request_active = false
	exit_scene_after_sequence = false
	_set_scene_active(false)
	_refresh_neighbor_list()
	
	# Hide UI elements for free roam mode, but keep dialogue history visible
	if dialogue_display_manager:
		dialogue_display_manager.set_input_mode(false, true) # Keep edit button visible
		dialogue_display_manager.set_edit_button_visible(true)
	
	# CRITICAL: Disable click-to-continue so clicking the dialogue box doesn't
	# accidentally trigger end scene logic or send new LLM requests
	if dialogue_panel:
		dialogue_panel.set_interrupt_button_visible(false)
		dialogue_panel.hide_input(true)
		dialogue_panel.set_edit_button_visible(true)
		dialogue_panel.set_click_to_continue_enabled(false)  # Prevent accidental triggers
	
	# Roll the schedule for the current location to show NPCs
	if location_manager:
		_handle_schedule_for_location(location_manager.current_location_id)

func _handle_schedule_for_location(location_id: String) -> void:
	if schedule_manager == null or stats_manager == null:
		print("DEBUG: schedule_manager or stats_manager is null")
		last_schedule_assignments = []
		_sync_controllers_schedule_data()
		_update_schedule_label([])
		_clear_schedule_sprites()
		return
	
	# Use global_vars for time state
	var day_index: int = int(global_vars.get("day_index", 0))
	var time_slot_key: String = "morning"
	if stats_manager:
		time_slot_key = stats_manager.get_time_slot_key() # StatsManager will use global_vars
	
	print("DEBUG: Rolling schedule for location=%s, day=%d, time_slot=%s" % [location_id, day_index, time_slot_key])
	var assignments: Array = schedule_manager.roll_location_assignments(location_id, day_index, time_slot_key)
	print("DEBUG: Got %d assignments" % assignments.size())
	for a in assignments:
		print("DEBUG: Assignment - %s" % str(a))
	last_schedule_assignments = assignments.duplicate(true)
	
	_display_schedule_sprites(assignments)
	
	# Update controllers with new data
	_sync_controllers_schedule_data()
	
	_update_schedule_label(assignments)
	_announce_schedule_results(location_id, assignments)

func _sync_controllers_schedule_data() -> void:
	if speak_controller:
		speak_controller.last_schedule_assignments = last_schedule_assignments
		speak_controller.schedule_sprite_tags = schedule_sprite_tags
	if debug_controller:
		debug_controller.last_schedule_assignments = last_schedule_assignments
		debug_controller.schedule_sprite_tags = schedule_sprite_tags

func _update_schedule_label(assignments: Array) -> void:
	if location_schedule_label == null:
		return
	if schedule_manager == null or stats_manager == null:
		location_schedule_label.text = "Time: --"
		return
	var slot_label: String = stats_manager.get_time_slot_label()
	location_schedule_label.text = "Time: %s" % slot_label.capitalize()

func _announce_schedule_results(location_id: String, assignments: Array) -> void:
	if stats_manager == null:
		return
	var slot_label: String = stats_manager.get_time_slot_label()
	var location_label: String = location_id
	if location_manager:
		location_label = location_manager.get_location_identifier(location_id)
	if assignments.is_empty():
		print("Schedule [%s]: No characters scheduled at %s." % [slot_label, location_label])
		return
	var names: Array[String] = []
	for entry in assignments:
		var display_name: String = str(entry.get("name", entry.get("tag", "")))
		var tag: String = str(entry.get("tag", ""))
		names.append("%s (%s)" % [display_name, tag])
	print("Schedule [%s -> %s]: %s" % [slot_label, location_label, ", ".join(names)])

func change_location(loc_id: String) -> bool:
	if travel_manager:
		return travel_manager.change_location(loc_id)
	return false

## Change location while preserving active characters (used during events)
## Characters will "follow" the player to the new location
func change_location_preserve_characters(loc_id: String) -> bool:
	if travel_manager:
		return travel_manager.change_location_preserve_characters(loc_id)
	return false

## Change location preserving ONLY grouped characters
## Does NOT call schedule handling to avoid clearing grouped sprites
func change_location_preserve_grouped(loc_id: String, grouped_chars: Array, group_map: Dictionary) -> bool:
	if travel_manager:
		return travel_manager.change_location_preserve_grouped(loc_id, grouped_chars, group_map)
	return false

## Change location automatically preserving any currently grouped characters
func change_location_with_groups(loc_id: String) -> bool:
	if travel_manager:
		return travel_manager.change_location_with_groups(loc_id)
	return false



func _on_navigation_target_selected(location_id: String) -> void:
	if travel_manager:
		travel_manager.on_navigation_target_selected(location_id)

func _display_schedule_sprites(assignments: Array) -> void:
	print("DEBUG: _display_schedule_sprites called with %d assignments" % assignments.size())
	
	if sprite_manager == null or character_manager == null:
		print("DEBUG: sprite_manager=%s, character_manager=%s" % [sprite_manager, character_manager])
		return
	
	# During events: filter out characters already in a group, show remaining
	if event_manager and event_manager.is_event_running:
		var group_state = sprite_manager.get_current_group_state()
		var grouped_chars = group_state.get("grouped_chars", [])
		
		if not grouped_chars.is_empty():
			# Filter out grouped characters from schedule assignments
			var filtered_assignments: Array = []
			for entry in assignments:
				var tag: String = str(entry.get("tag", ""))
				if tag != "" and tag not in grouped_chars:
					filtered_assignments.append(entry)
			
			print("DEBUG: Event running - filtered %d grouped chars, %d schedule chars remaining" % [grouped_chars.size(), filtered_assignments.size()])
			
			if filtered_assignments.is_empty():
				# No additional characters to show
				return
			
			# Add remaining scheduled characters without clearing existing sprites
			for entry in filtered_assignments:
				var tag: String = str(entry.get("tag", ""))
				if tag != "":
					character_manager.add_active_character(tag)
					sprite_manager.show_sprite(tag, "neutral", character_manager)
					schedule_sprite_tags.append(tag)
			
			sprite_manager.update_layout()
			print("DEBUG: Added %d schedule sprites alongside grouped chars" % filtered_assignments.size())
			return
	
	# Normal case: clear and display all schedule sprites
	_clear_schedule_sprites()
	if assignments.is_empty():
		print("DEBUG: No assignments to display")
		return
	
	# Use group-aware positioning
	sprite_manager.display_grouped_assignments(assignments, character_manager)
	
	# Track displayed tags for cleanup
	for entry in assignments:
		var tag: String = str(entry.get("tag", ""))
		if tag != "" and sprite_manager.active_sprites.has(tag):
			schedule_sprite_tags.append(tag)
	
	print("DEBUG: Displayed %d sprites" % schedule_sprite_tags.size())

func _clear_schedule_sprites() -> void:
	if sprite_manager:
		for tag in schedule_sprite_tags:
			sprite_manager.hide_sprite(tag, true)
	schedule_sprite_tags.clear()



func _on_sprite_test_pressed():
	character_manager.add_active_character("twi")
	sprite_manager.show_sprite("twi", "neutral", character_manager)
	sprite_manager.update_layout()

func _on_test_btn_pressed():
	if dialogue_panel:
		dialogue_panel.set_waiting_for_response(true)
	var stats_str = stats_manager.get_stats_string()
	var base_prompt = settings_manager.get_setting("system_prompt")
	if base_prompt == null:
		base_prompt = "You are writing a My Little Pony visual novel."
	var system_prompt = base_prompt + " Current Stats: " + stats_str
	var persona_lines = settings_manager.get_active_persona_context_lines()
	if persona_lines.size() > 0:
		system_prompt += "\nPlayer Persona:\n"
		for line in persona_lines:
			system_prompt += line + "\n"
	llm_client.send_request(system_prompt, "Hello! Who are you?")

func _on_llm_response(text):
	# If EventManager is handling an LLM request (e.g. from LLM Prompt action),
	# let it handle the response exclusively.
	if event_manager and event_manager.waiting_for_dialogue:
		return

	# Memory summary is handled via MemoryController signals now.
	if memory_summary_request_active:
		# If we receive a raw LLM response but we think we are summarizing, 
		# we should check if it's actually the summary response.
		# However, LLMController routes summary responses to _on_memory_summary_response via signal.
		# So if we are here, it might be a collision or error.
		return
	print("LLM Response: ", text)
	if dialogue_panel:
		dialogue_panel.set_waiting_for_response(false)
	end_scene_request_active = false
	if end_scene_button:
		end_scene_button.disabled = false

	if pending_impersonation_request:
		# Handled via signal _on_impersonation_completed
		return
	if travel_request_active:
		if travel_manager:
			travel_manager.on_travel_response_received(text)
		return

	current_sequence_label = "llm_response"
	_set_scene_active(true)
	if dialogue_display_manager == null or dialogue_panel == null:
		_setup_enhanced_dialogue_panel()

	if dialogue_display_manager and dialogue_panel:
		_on_llm_response_enhanced(text)
	elif dialogue_panel:
		var trimmed: String = text.strip_edges()
		if trimmed != "":
			dialogue_panel.display_narration(trimmed, false)
			memory_controller.record_raw_ai_memory(trimmed, current_sequence_label)
			memory_controller.trigger_memory_summary_if_needed()
	else:
		memory_controller.record_raw_ai_memory(text, current_sequence_label)
		print("Unable to display LLM response: enhanced dialogue system unavailable.")

func _on_llm_response_enhanced(text: String):
	current_sequence_label = "llm_response"
	_set_scene_active(true)

	if dialogue_display_manager == null:
		_setup_enhanced_dialogue_panel()

	if dialogue_display_manager == null:
		print("Error: Failed to initialize dialogue display manager in _on_llm_response_enhanced")
		return

	# Parse the LLM response
	var parsed = DialogueParser.parse(text, character_manager)
	print("Parsed %d dialogue lines" % parsed.lines.size())

	# Add all mentioned characters to active list
	var mentioned_chars = DialogueParser.get_mentioned_characters(text)
	for tag in mentioned_chars:
		if character_manager.get_character(tag):
			character_manager.add_active_character(tag)

	print("Mentioned characters: ", mentioned_chars)

	# Play the dialogue sequence with raw response for editing
	dialogue_display_manager.play_sequence(parsed, text)

func _on_llm_error(error):
	if memory_summary_request_active:
		memory_summary_request_active = false
		print("Memory summary request failed: ", error)
		if dialogue_panel:
			dialogue_panel.set_waiting_for_response(false)
		if memory_controller:
			memory_controller.refresh_context_ui()

		return
	print("LLM Error: ", error)
	if pending_impersonation_request:
		pending_impersonation_request = false
		if dialogue_panel:
			dialogue_panel.set_impersonate_button_enabled(true)
	if dialogue_panel:
		dialogue_panel.set_waiting_for_response(false)
	end_scene_request_active = false
	if travel_request_active:
		travel_request_active = false
		_enter_free_roam_mode()
	exit_scene_after_sequence = false
	if end_scene_button:
		end_scene_button.disabled = false
	if dialogue_panel:
		dialogue_panel.display_line("System", "Error: " + str(error), Color(1.0, 0.6, 0.6), false)



# =============================================================================
# CONTROLLER SIGNAL HANDLERS
# =============================================================================

## LLM Controller response handler - routes responses based on type
func _on_llm_controller_response(text: String, response_type: String) -> void:
	match response_type:
		"travel":
			_on_travel_narration_generated(text)
		"end_scene":
			end_scene_request_active = false
			_on_llm_response_enhanced(text)
		"scene":
			_on_llm_response_enhanced(text)
		_:
			_on_llm_response_enhanced(text)

## LLM Controller error handler
func _on_llm_controller_error(error: String) -> void:
	_on_llm_error(error)

## Impersonation completed - fill in player text
func _on_impersonation_completed(cleaned_line: String) -> void:
	pending_impersonation_request = false
	if dialogue_panel:
		dialogue_panel.set_impersonate_button_enabled(true)
	if cleaned_line.is_empty():
		print("Warning: Failed to parse impersonated player line.")
		return
	if dialogue_panel:
		dialogue_panel.set_input_text(cleaned_line)

## Memory summary completed
func _on_memory_summary_completed(summary: String) -> void:
	memory_summary_request_active = false
	if dialogue_panel:
		dialogue_panel.set_waiting_for_response(false)
	if memory_controller:
		memory_controller.refresh_context_ui()


## Memory summary needed - trigger via LLM controller
func _on_memory_summary_needed(force: bool) -> void:
	if llm_controller:
		llm_controller.request_memory_summary()

## Travel started - prepare UI
func _on_travel_started(previous_location_id: String, destination_id: String) -> void:
	if memory_summary_request_active:
		return
	travel_request_active = true
	exit_scene_after_sequence = true
	_set_scene_active(true)
	if dialogue_display_manager:
		dialogue_display_manager.skip_prompt_after_next_sequence()
	if dialogue_panel:
		dialogue_panel.set_waiting_for_response(true)
	
	# Get history text
	var history_text: String = ""
	if dialogue_panel:
		history_text = dialogue_panel.get_transcript_text()
	
	# Request travel narration via LLM controller
	if llm_controller:
		llm_controller.request_travel_narration(previous_location_id, destination_id, history_text, last_schedule_assignments)

## Travel completed
func _on_travel_completed() -> void:
	travel_request_active = false

## Location changed by travel manager
func _on_location_changed_by_travel(location_id: String, preserve_characters: bool) -> void:
	_refresh_neighbor_list()
	_handle_schedule_for_location(location_id)

## Speak conversation started - setup dialogue input
func _on_speak_conversation_started(tags: Array, names: Array) -> void:
	# Setup dialogue panel if needed
	if dialogue_display_manager == null or dialogue_panel == null:
		_setup_enhanced_dialogue_panel()

	# Reset auto_show_input for free roam conversations
	# (EventManager sets this to false during events)
	if dialogue_display_manager:
		dialogue_display_manager.set_input_mode(true)

	# Show input field so user can start the conversation
	var placeholder: String = "Say something..."
	if names.size() == 1:
		placeholder = "Say something to %s..." % names[0]
	elif names.size() == 2:
		placeholder = "Say something to %s and %s..." % [names[0], names[1]]
	elif names.size() > 2:
		var last_name: String = names[names.size() - 1]
		var other_names: Array[String] = []
		for i in range(names.size() - 1):
			other_names.append(names[i])
		placeholder = "Say something to %s, and %s..." % [", ".join(other_names), last_name]
	
	# Show input with "Nevermind" button so user can cancel before starting
	if dialogue_display_manager:
		dialogue_display_manager.show_user_input(placeholder, "", true, "Nevermind")
	elif dialogue_panel:
		dialogue_panel.show_input(placeholder, "", true, "Nevermind")

## Setup the dialogue panel system
func _setup_enhanced_dialogue_panel():
	var panel_valid: bool = dialogue_panel != null and is_instance_valid(dialogue_panel)
	if dialogue_display_manager and panel_valid:
		return
	if game_ui_container == null:
		print("Cannot set up enhanced dialogue panel: game UI is not ready.")
		return

	# Create the dialogue panel
	if not panel_valid:
		var panel_scene = load("res://scenes/ui/components/EnhancedDialoguePanel.tscn")
		dialogue_panel = panel_scene.instantiate()
		game_ui_container.add_child(dialogue_panel)
	elif dialogue_panel.get_parent() == null:
		game_ui_container.add_child(dialogue_panel)

	if dialogue_display_manager:
		dialogue_display_manager.queue_free()

	# Create the dialogue display manager
	dialogue_display_manager = DialogueDisplayManager.new(
		dialogue_panel,
		sprite_manager,
		character_manager
	)
	dialogue_display_manager.location_manager = location_manager
	dialogue_display_manager.music_manager = music_manager
	add_child(dialogue_display_manager)
	
	if event_manager:
		event_manager.dialogue_display_manager = dialogue_display_manager
	
	# Wire up MemoryController so it can access raw response history for "Story so far" context
	if memory_controller:
		memory_controller.dialogue_display_manager = dialogue_display_manager
	
	# Connect signals
	dialogue_display_manager.dialogue_line_displayed.connect(_on_dialogue_line_displayed)
	dialogue_display_manager.dialogue_sequence_finished.connect(_on_dialogue_sequence_finished)
	dialogue_display_manager.dialogue_interrupted.connect(_on_dialogue_interrupted)
	dialogue_display_manager.location_changed.connect(_on_dialogue_location_changed)
	# Connect continue signal to allow "End Scene"/"Continue" logic from the dialogue panel
	if not dialogue_display_manager.continue_pressed.is_connected(_on_end_scene_pressed):
		dialogue_display_manager.continue_pressed.connect(_on_end_scene_pressed)
	
	dialogue_display_manager.raw_response_updated.connect(memory_controller.on_raw_response_updated)
	dialogue_display_manager.dialogue_choice_selected.connect(_on_choice_selected)
	dialogue_panel.user_input_submitted.connect(_on_user_interrupt_input)
	dialogue_panel.user_turn_started.connect(_on_user_turn_started)
	dialogue_panel.user_turn_ended.connect(_on_user_turn_ended)
	dialogue_panel.impersonate_requested.connect(_on_impersonate_requested)
	dialogue_panel.nevermind_pressed.connect(_on_nevermind_pressed)

## Called when the dialogue system processes a [location: ...] command
## Preserves grouped characters when an event is running OR during active scenes
func _on_dialogue_location_changed(location_id: String) -> void:
	var event_running: bool = event_manager.is_event_running if event_manager else false
	print("DEBUG _on_dialogue_location_changed: loc=%s, event_running=%s, is_scene_active=%s" % [location_id, event_running, is_scene_active])
	
	# Preserve grouped characters during events OR active scenes (free-roam conversations)
	if event_running or is_scene_active:
		change_location_with_groups(location_id)
	else:
		# Not in an event or scene, change location normally
		change_location(location_id)

## Called when a dialogue line is displayed (for relationship tracking) WIP
func _on_dialogue_line_displayed(line: DialogueParser.DialogueLine):
	if line.type == "dialogue" and relationship_manager:
		relationship_manager.record_dialogue(line.speaker_tag, line.text)
		#var sentiment = llm_controller.estimate_sentiment_score(line.text)
		#if sentiment != 0:
			#relationship_manager.adjust_relationship(
				#line.speaker_tag,
				#float(sentiment),
				#"Dialogue sentiment sample"
			#)

## Called when a dialogue sequence finishes
func _on_dialogue_sequence_finished():
	# Record memory via controller (handles merge vs new automatically)
	memory_controller.record_latest_ai_response()
	memory_controller.trigger_memory_summary_if_needed()
	
	# If an event is running, let EventManager handle the flow COMPLETELY.
	# EventManager connects its own one-shot handlers to dialogue_sequence_finished
	# (e.g., _on_dialogue_finished, _on_branch_prompt_finished, _on_llm_turn_finished_interactive)
	# We should NOT interfere while EventManager is actively processing.
	if event_manager and event_manager.is_event_running:
		# CRITICAL: If EventManager is waiting for dialogue, choice, or continue button click,
		# it means its one-shot handler is about to run (or is running). We must completely defer to it.
		# Do NOT check characters or trigger free roam here - that would cause a race condition.
		if event_manager.waiting_for_dialogue or event_manager.waiting_for_choice or event_manager.waiting_for_continue:
			print("DEBUG _on_dialogue_sequence_finished: Event is waiting (dialogue=%s, choice=%s, continue=%s), deferring to EventManager" % [event_manager.waiting_for_dialogue, event_manager.waiting_for_choice, event_manager.waiting_for_continue])
			return
		
		# EventManager is NOT waiting - this might be a case where characters left mid-event
		# and no more actions are pending. However, we should still be careful.
		# Check if all characters have left (group is empty + no active characters)
		var has_grouped_chars = false
		var has_active_chars = false
		if sprite_manager:
			var group_state = sprite_manager.get_current_group_state()
			has_grouped_chars = not group_state.get("grouped_chars", []).is_empty()
		if character_manager:
			has_active_chars = character_manager.get_active_characters().size() > 0
		
		if not has_grouped_chars and not has_active_chars:
			# All characters have left - check if there are more event actions
			var has_more_actions = event_manager.current_action_index < event_manager.current_event_sequence.size()
			
			if has_more_actions:
				# More actions to process - continue the event
				print("DEBUG: All characters left but more actions remain, continuing event")
				event_manager._process_next_action()
			else:
				# No more actions - end event and enter free roam
				print("DEBUG: All characters left and no more actions, entering free roam")
				event_manager._end_event()
				_enter_free_roam_mode()
			return
		
		# During events, if this was an LLM response (multi-turn conversation in event),
		# show input so user can reply or advance
		if current_sequence_label == "llm_response" and dialogue_display_manager:
			dialogue_display_manager.show_user_input("What do you say or do?", "", true)
		return

	if exit_scene_after_sequence:
		# Conversation ending sequence just finished - automatically enter free roam
		# No second click required - user already saw the goodbye text during playback
		exit_scene_after_sequence = false
		end_scene_request_active = false
		if dialogue_panel and dialogue_panel.input_field:
			dialogue_panel.input_field.editable = true  # Reset for next conversation
		_enter_free_roam_mode()
		return

## Called when user presses "Nevermind" to cancel starting a conversation
func _on_nevermind_pressed() -> void:
	print("Nevermind pressed - canceling conversation")
	
	# Clear any characters that were added for this conversation
	# They were shown via speak controller, so hide them now
	if character_manager:
		var active_chars = character_manager.get_active_characters()
		for char_data in active_chars:
			var tag = char_data.tag if char_data else ""
			if tag != "" and sprite_manager:
				sprite_manager.hide_sprite(tag, true)
		character_manager.clear_active_characters()
	
	_enter_free_roam_mode()

## Called when user interrupts the dialogue
func _on_dialogue_interrupted():
	print("Dialogue interrupted by user")

## Called when user submits their interrupt input
func _on_user_interrupt_input(text: String):
	print("User interrupt input: ", text)
	if exit_scene_after_sequence:
		# If user types something while we are waiting to exit, just exit?
		# Or maybe they want to add a final thought?
		# For now, treat any input in this state as "Okay, I'm done"
		exit_scene_after_sequence = false
		_enter_free_roam_mode()
		return

	if memory_summary_request_active:
		print("Memory summary in progress; waiting before sending new user input.")
		if dialogue_panel:
			dialogue_panel.set_waiting_for_response(true, "Summarizing")
		return

	if dialogue_panel:
		# Re-enable editing for next turn if we disabled it
		dialogue_panel.input_field.editable = true
		
		dialogue_panel.display_line(
			"You",
			text,
			Color(0.5, 0.8, 1.0),  # Light blue for player
			false  # Don't animate
		)
		memory_controller.record_player_memory(text)

	# Request response via controller
	llm_controller.request_scene(text)
	
	if dialogue_panel:
		dialogue_panel.set_waiting_for_response(true)

func _on_user_turn_started() -> void:
	if end_scene_button:
		var has_chars := _has_active_characters()
		end_scene_button.visible = has_chars
		end_scene_button.disabled = end_scene_request_active or not has_chars

func _on_user_turn_ended() -> void:
	if end_scene_button:
		end_scene_button.visible = false
func _on_impersonate_requested() -> void:
	if pending_impersonation_request:
		return
	if memory_summary_request_active:
		return

	pending_impersonation_request = true
	if dialogue_panel:
		dialogue_panel.set_impersonate_button_enabled(false)
	
	llm_controller.request_impersonation()

func _on_end_scene_pressed() -> void:
	print("End scene pressed, exit_scene_after_sequence=%s, end_scene_request_active=%s" % [exit_scene_after_sequence, end_scene_request_active])
	
	# FIRST: If we are in an event flow, handle event advancement
	# This takes priority over everything else
	if event_manager and event_manager.is_event_running:
		print("DEBUG event_running=%s, waiting_for_dialogue=%s, waiting_for_choice=%s, waiting_for_continue=%s" % [event_manager.is_event_running, event_manager.waiting_for_dialogue, event_manager.waiting_for_choice, event_manager.waiting_for_continue])
		
		if event_manager.waiting_for_dialogue:
			print("Waiting for dialogue/LLM, ignoring advance request.")
			return
		
		if event_manager.waiting_for_choice:
			print("Waiting for choice selection, ignoring advance request.")
			return
			
		print("Advancing event sequence...")
		if dialogue_panel:
			dialogue_panel.hide_input(false) # keep edit button if needed?
		# Clear waiting_for_continue flag since user clicked Continue
		event_manager.waiting_for_continue = false
		event_manager._process_next_action()
		return
	
	# NOTE: exit_scene_after_sequence is now handled automatically in _on_dialogue_sequence_finished
	# When the closing dialogue finishes playing, it immediately enters free roam.
	# So we should never reach here with exit_scene_after_sequence = true.
	
	if end_scene_request_active:
		return
	
	if not _has_active_characters():
		return

	end_scene_request_active = true
	if end_scene_button:
		end_scene_button.disabled = true
	exit_scene_after_sequence = true
	if dialogue_display_manager:
		dialogue_display_manager.skip_prompt_after_next_sequence()
	
	# Ensure scene stays active while waiting for LLM response
	_set_scene_active(true)
	
	# Hide input area while waiting (user shouldn't type during this)
	if dialogue_panel:
		dialogue_panel.hide_input(false)

	var history_text = ""
	if dialogue_panel:
		dialogue_panel.set_waiting_for_response(true)
		history_text = dialogue_panel.get_transcript_text()
	
	llm_controller.request_end_scene(history_text)








func _get_location_name(location_id: String) -> String:
	if location_manager == null:
		return ""
	var loc = location_manager.get_location(location_id)
	if loc:
		return loc.name
	return location_id



func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			_toggle_debug_menu()
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and (event.keycode == KEY_T):
			if memory_controller:
				memory_controller.toggle_debug_visible()

func _toggle_debug_menu() -> void:
	if debug_controller:
		debug_controller.toggle_debug_menu()

func _on_debug_menu_closed() -> void:
	if debug_controller:
		debug_controller.current_debug_menu = null
	current_debug_menu = null

## Get a list of characters not currently at this location
func _get_available_characters_for_location() -> Array:
	if character_manager == null:
		return []
	
	var result: Array = []
	var all_characters: Array = character_manager.get_all_characters(true)  # sorted
	
	for char_config in all_characters:
		var tag: String = str(char_config.tag)
		if tag == "p":  # Exclude player
			continue
		if tag in schedule_sprite_tags:  # Already at location
			continue
		result.append({"tag": tag, "name": char_config.name})
	
	return result

## Get a list of characters not in a specific group (for the speak panel)


func _on_sprite_clicked(tag: String) -> void:
	if speak_controller:
		speak_controller.on_sprite_clicked(tag, is_scene_active, travel_request_active)




func fade_screen(fade_in: bool, duration: float = 1.0) -> Tween:
	if fade_overlay == null: return null
	
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_STOP if not fade_in else Control.MOUSE_FILTER_IGNORE
	var tween = create_tween()
	var target_alpha = 0.0 if fade_in else 1.0
	# Manual alpha set if needed, but normally just tween from current
	
	tween.tween_property(fade_overlay, "color:a", target_alpha, duration)
	return tween



func _on_rest_button_pressed() -> void:
	if rest_handler:
		rest_handler.on_rest_button_pressed()

func _on_travel_narration_generated(text: String) -> void:
	travel_request_active = false
	_set_scene_active(true)
	current_sequence_label = "travel"
	if dialogue_panel:
		dialogue_panel.set_waiting_for_response(false)
	if dialogue_display_manager == null or dialogue_panel == null:
		_setup_enhanced_dialogue_panel()
	var parsed = DialogueParser.parse(text, character_manager)
	if parsed.lines.is_empty():
		var trimmed_text := text.strip_edges()
		if dialogue_panel and trimmed_text != "":
			var segments := trimmed_text.split("Narrator:")
			if segments.size() <= 1:
				dialogue_panel.display_narration(trimmed_text, false)
			else:
				for segment in segments:
					var line = segment.strip_edges()
					if line.begins_with("\"") and line.ends_with("\"") and line.length() >= 2:
						line = line.substr(1, line.length() - 2).strip_edges()
					dialogue_panel.display_narration(line, false)
		memory_controller.record_raw_ai_memory(text, current_sequence_label)
		memory_controller.trigger_memory_summary_if_needed()
		
		# Wait for user confirmation
		exit_scene_after_sequence = true
		if dialogue_display_manager:
			dialogue_display_manager.show_user_input("Arrived.", "", true)
			if dialogue_panel and dialogue_panel.input_field: dialogue_panel.input_field.editable = false
	else:
		if dialogue_display_manager and dialogue_panel:
			dialogue_display_manager.skip_prompt_after_next_sequence()
			dialogue_display_manager.preserve_history = true
			exit_scene_after_sequence = true
			dialogue_display_manager.play_sequence(parsed, text)
		elif dialogue_panel:
			var fallback_text := text.strip_edges()
			if fallback_text != "":
				dialogue_panel.display_narration(fallback_text, false)
			memory_controller.record_raw_ai_memory(text, current_sequence_label)
			memory_controller.trigger_memory_summary_if_needed()
			
			# Wait for user confirmation
			exit_scene_after_sequence = true
			if dialogue_display_manager:
				dialogue_display_manager.show_user_input("Arrived.", "", true)
				if dialogue_panel and dialogue_panel.input_field: dialogue_panel.input_field.editable = false
		else:
			print("Travel response received but dialogue panel is unavailable.")
			_enter_free_roam_mode()
