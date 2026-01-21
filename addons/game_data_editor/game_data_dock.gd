@tool
class_name GameDataDock
extends VBoxContainer

const LOCATION_ROOTS := ["res://assets/Locations"]
const MAPS_PATH := "res://assets/Maps"
const IMAGE_EXTS := ["png", "jpg", "jpeg", "webp"]
const DEFAULT_MARKER_SIZE := Vector2(0.05, 0.05)
const NEIGHBOR_GRAPH_PATH := "res://location_graph.json"
const SCHEDULE_FILE_PATH := "res://assets/Schedules/schedules.json"
const SPRITE_SIZE_FILE_PATH := "res://assets/Schedules/sprite_sizes.json"
const SCHEDULE_TIME_SLOTS := [
	{"key": "morning", "label": "Morning"},
	{"key": "day", "label": "Day"},
	{"key": "night", "label": "Night"}
]

const EVENTS_FILE_PATH := "res://assets/Events/events.json"

# Event Action Types
const EVENT_ACTION_TYPES := [
	{"id": "change_location", "label": "Change Location"},
	{"id": "character_enter", "label": "Character Enter"},
	{"id": "character_leave", "label": "Character Leave"},
	{"id": "create_group", "label": "Create Group"},
	{"id": "change_sprite", "label": "Change Sprite/Emotion"},
	{"id": "dialogue", "label": "Dialogue"},
	{"id": "branch", "label": "Branch / Choice"},
	{"id": "conditional_branch", "label": "Conditional Branch"},
	{"id": "llm_prompt", "label": "LLM Prompt"},
	{"id": "set_variable", "label": "Set Variable"},
	{"id": "edit_persona", "label": "Edit Persona"},
	{"id": "create_checkpoint", "label": "Create Checkpoint"},
	{"id": "return_to_checkpoint", "label": "Return to Checkpoint"},
	{"id": "advance_time", "label": "Advance Time"},
	{"id": "modify_inventory", "label": "Modify Inventory"},
	{"id": "end_event", "label": "End Event"}
]

const MapCanvas = preload("res://addons/game_data_editor/map_canvas.gd")

var region_data: Array = []
var region_lookup := {}
var map_lookup := {}
var current_region_id := ""
var current_location_entry = null
var dirty_lookup := {}

# Centralized neighbor graph data
var neighbor_graph := {}  # location_id -> Array of neighbor_ids
var neighbor_graph_dirty := false

var _setting_fields := false
var _suppress_list_signal := false
var _pending_marker_size := DEFAULT_MARKER_SIZE

var region_option: OptionButton
var location_list: ItemList
var show_all_regions_checkbox: CheckBox
var map_canvas: MapPointerCanvas
var pos_fields := {}
var remove_button: Button
var save_button: Button
var status_label: Label
var info_label: Label
var location_label: Label

# Neighbor editor UI elements
var neighbor_region_option: OptionButton
var neighbor_location_list: ItemList
var neighbor_list: ItemList
var neighbor_available_list: ItemList
var neighbor_add_button: Button
var neighbor_remove_button: Button
var neighbor_save_button: Button
var neighbor_status_label: Label
var neighbor_search_field: LineEdit
var neighbor_current_location = null

# Schedule editor state
var schedule_data: Dictionary = {"active_schedule_id": "", "schedules": []}
var schedule_lookup := {}
var schedule_id_list: Array[String] = []
var selected_schedule_id: String = ""
var selected_schedule_character_tag: String = ""
var schedule_dirty: bool = false
var schedule_selector: OptionButton
var schedule_name_field: LineEdit
var schedule_active_label: Label
var schedule_status_label: Label
var schedule_save_button: Button
var schedule_character_list: ItemList
var schedule_character_name_field: LineEdit
var schedule_default_location_field: LineEdit
var schedule_slot_widgets := {}
var schedule_set_active_button: Button
var schedule_add_schedule_button: Button
var schedule_duplicate_schedule_button: Button
var schedule_remove_schedule_button: Button
var schedule_add_missing_button: Button
var schedule_remove_character_button: Button
var schedule_add_character_option: OptionButton
var schedule_add_character_button: Button
var schedule_reload_button: Button
var schedule_suppress_signals: bool = false
var character_reference := {}
var character_emotions_reference := {}
var location_reference := {}
var location_option_data: Array = []

# Location Picker Dialog
var location_picker_dialog: ConfirmationDialog
var location_picker_search: LineEdit
var location_picker_region_list: ItemList
var location_picker_location_list: ItemList
var location_picker_request_slot: String = ""
var location_picker_target: Object = null # Can be Button or other widget


# Sprite Size editor state
var sprite_size_data: Dictionary = {}
var sprite_size_dirty: bool = false
var sprite_size_character_list: ItemList
var sprite_size_spin: SpinBox
var sprite_size_save_button: Button
var sprite_size_status_label: Label
var sprite_size_selected_tag: String = ""
# Global base sprite size
var global_base_sprite_size: float = 1.0
var global_base_sprite_size_spin: SpinBox
const GLOBAL_BASE_SIZE_KEY := "_global_base_size"
# Per-sprite customization UI
var sprite_list: ItemList
var sprite_selected_name: String = ""
var sprite_custom_clip_check: CheckBox
var sprite_clip_left_spin: SpinBox
var sprite_clip_right_spin: SpinBox
var sprite_scale_check: CheckBox
var sprite_scale_spin: SpinBox
# Preview panel
var sprite_size_preview_container: Control
var sprite_size_preview_background: TextureRect
var sprite_size_preview_twilight: TextureRect
var sprite_size_preview_character: TextureRect
var sprite_size_preview_twi_label: Label
var sprite_size_preview_char_label: Label
var sprite_size_preview_clip_left: ColorRect
var sprite_size_preview_clip_right: ColorRect

const PREVIEW_BACKGROUND_PATH := "res://assets/Locations/ponyville/ponyville_main_square/background.png"
const PREVIEW_REFERENCE_CHAR := "twi"  # Twilight as reference

# Event Editor State
var event_data: Dictionary = {"events": {}}
var event_list_data: Array = [] # Cached list for UI
var current_event_id: String = ""
var current_action_path: Array = [] # Stack of { "target": array_ref, "name": "Main" }
var event_dirty: bool = false

# Event Editor UI
var event_list: ItemList
var event_search: LineEdit
var event_id_field: LineEdit
var event_save_button: Button
var event_status_label: Label
var action_list: ItemList
var action_breadcrumbs: HBoxContainer
var action_properties_container: VBoxContainer
var action_add_type_option: OptionButton

func _ready():
	name = "Game Data Editor"
	_build_ui()
	_load_all_data()

func _build_ui():
	# Create tab container for multiple editors
	var tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(tab_container)

	# Create Map Pointer tab
	var map_pointer_tab = VBoxContainer.new()
	map_pointer_tab.name = "Map Pointers"
	tab_container.add_child(map_pointer_tab)

	# Create Neighbor Editor tab
	var neighbor_tab = VBoxContainer.new()
	neighbor_tab.name = "Neighbor Editor"
	tab_container.add_child(neighbor_tab)

	# Create Schedule Editor tab
	var schedule_tab = VBoxContainer.new()
	schedule_tab.name = "Schedules"
	tab_container.add_child(schedule_tab)

	# Create Sprite Size Editor tab
	var sprite_size_tab = VBoxContainer.new()
	sprite_size_tab.name = "Sprite Sizes"
	tab_container.add_child(sprite_size_tab)

	# Create Event Editor tab
	var event_tab = VBoxContainer.new()
	event_tab.name = "Event Editor"
	tab_container.add_child(event_tab)

	# Build dialogs (shared)
	_build_location_picker()

	# Build the Map Pointer UI in its tab
	_build_map_pointer_ui(map_pointer_tab)

	# Build the Neighbor Editor UI in its tab
	_build_neighbor_editor_ui(neighbor_tab)

	# Build the Schedule Editor UI
	_build_schedule_editor_ui(schedule_tab)

	# Build the Sprite Size Editor UI
	_build_sprite_size_editor_ui(sprite_size_tab)

	# Build the Event Editor UI
	_build_event_editor_ui(event_tab)

func _build_map_pointer_ui(parent: VBoxContainer):
	var title = Label.new()
	title.text = "Map Pointer Editor"
	title.add_theme_font_size_override("font_size", 16)
	parent.add_child(title)
	info_label = Label.new()
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.text = "Select a region and location, then click the map to place a pointer. Drag rectangles to move them, tweak size with the fields, and use Remove/Save when needed."
	parent.add_child(info_label)
	var region_bar = HBoxContainer.new()
	parent.add_child(region_bar)
	var region_label = Label.new()
	region_label.text = "Region:"
	region_bar.add_child(region_label)
	region_option = OptionButton.new()
	region_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	region_option.item_selected.connect(_on_region_selected)
	region_bar.add_child(region_option)
	var reload_button = Button.new()
	reload_button.text = "Reload"
	reload_button.pressed.connect(_on_reload_pressed)
	region_bar.add_child(reload_button)
	save_button = Button.new()
	save_button.text = "Save Changes"
	save_button.disabled = true
	save_button.pressed.connect(_on_save_pressed)
	parent.add_child(save_button)
	var split = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(split)
	var left_panel = VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(240, 320)
	split.add_child(left_panel)
	var list_header = HBoxContainer.new()
	left_panel.add_child(list_header)
	var list_label = Label.new()
	list_label.text = "Locations"
	list_header.add_child(list_label)
	show_all_regions_checkbox = CheckBox.new()
	show_all_regions_checkbox.text = "All Regions"
	show_all_regions_checkbox.tooltip_text = "Show locations from all regions, not just the current one"
	show_all_regions_checkbox.toggled.connect(_on_show_all_regions_toggled)
	list_header.add_child(show_all_regions_checkbox)
	location_list = ItemList.new()
	location_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	location_list.select_mode = ItemList.SELECT_SINGLE
	location_list.item_selected.connect(_on_location_selected)
	left_panel.add_child(location_list)
	remove_button = Button.new()
	remove_button.text = "Remove Pointer"
	remove_button.disabled = true
	remove_button.pressed.connect(_on_remove_pressed)
	left_panel.add_child(remove_button)
	var right_panel = VBoxContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right_panel)
	location_label = Label.new()
	location_label.text = "No location selected"
	right_panel.add_child(location_label)
	map_canvas = MapCanvas.new()
	map_canvas.pointer_clicked.connect(_on_canvas_pointer_clicked)
	map_canvas.pointer_rect_changed.connect(_on_canvas_rect_changed)
	map_canvas.pointer_created.connect(_on_canvas_pointer_created)
	right_panel.add_child(map_canvas)
	var grid = GridContainer.new()
	grid.columns = 2
	grid.custom_minimum_size = Vector2(0, 90)
	right_panel.add_child(grid)
	pos_fields["x"] = _create_spinbox("X", grid)
	pos_fields["y"] = _create_spinbox("Y", grid)
	pos_fields["w"] = _create_spinbox("Width", grid)
	pos_fields["h"] = _create_spinbox("Height", grid)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(status_label)

func _build_neighbor_editor_ui(parent: VBoxContainer):
	var title = Label.new()
	title.text = "Neighbor Editor"
	title.add_theme_font_size_override("font_size", 16)
	parent.add_child(title)

	var info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "Select a location on the left, then add/remove neighbors on the right. Neighbors are bidirectional."
	parent.add_child(info)

	# Region selector and reload/save buttons
	var top_bar = HBoxContainer.new()
	parent.add_child(top_bar)

	var region_label = Label.new()
	region_label.text = "Region:"
	top_bar.add_child(region_label)

	neighbor_region_option = OptionButton.new()
	neighbor_region_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	neighbor_region_option.item_selected.connect(_on_neighbor_region_selected)
	top_bar.add_child(neighbor_region_option)

	var reload_button = Button.new()
	reload_button.text = "Reload"
	reload_button.pressed.connect(_on_reload_pressed)
	top_bar.add_child(reload_button)

	neighbor_save_button = Button.new()
	neighbor_save_button.text = "Save Neighbors"
	neighbor_save_button.disabled = true
	neighbor_save_button.pressed.connect(_on_neighbor_save_pressed)
	parent.add_child(neighbor_save_button)

	# Main content: 3 columns (Locations | Current neighbors | All locations)
	var split = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(split)

	# Left panel: Location list
	var left_panel = VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(200, 300)
	split.add_child(left_panel)

	var left_label = Label.new()
	left_label.text = "Locations in Region"
	left_panel.add_child(left_label)

	neighbor_location_list = ItemList.new()
	neighbor_location_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	neighbor_location_list.item_selected.connect(_on_neighbor_location_selected)
	left_panel.add_child(neighbor_location_list)

	# Right panel: split into current neighbors and available locations
	var right_split = HSplitContainer.new()
	right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right_split)

	# Middle panel: Current neighbors
	var middle_panel = VBoxContainer.new()
	middle_panel.custom_minimum_size = Vector2(200, 300)
	right_split.add_child(middle_panel)

	var middle_label = Label.new()
	middle_label.text = "Current Neighbors"
	middle_panel.add_child(middle_label)

	neighbor_list = ItemList.new()
	neighbor_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	neighbor_list.select_mode = ItemList.SELECT_MULTI
	middle_panel.add_child(neighbor_list)

	neighbor_remove_button = Button.new()
	neighbor_remove_button.text = "Remove Selected"
	neighbor_remove_button.disabled = true
	neighbor_remove_button.pressed.connect(_on_neighbor_remove_pressed)
	middle_panel.add_child(neighbor_remove_button)

	# Right panel: All available locations to add
	var right_panel = VBoxContainer.new()
	right_panel.custom_minimum_size = Vector2(200, 300)
	right_split.add_child(right_panel)

	var right_label = Label.new()
	right_label.text = "All Locations (Select to Add)"
	right_panel.add_child(right_label)

	# Search field for filtering locations
	neighbor_search_field = LineEdit.new()
	neighbor_search_field.placeholder_text = "Search locations..."
	neighbor_search_field.clear_button_enabled = true
	neighbor_search_field.text_changed.connect(_on_neighbor_search_changed)
	right_panel.add_child(neighbor_search_field)

	neighbor_available_list = ItemList.new()
	neighbor_available_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	neighbor_available_list.select_mode = ItemList.SELECT_MULTI
	# For multi-select, we need to use multi_selected signal
	neighbor_available_list.multi_selected.connect(_on_neighbor_add_location_multi_selected)
	# Also connect item_selected in case single-click works
	neighbor_available_list.item_selected.connect(_on_neighbor_add_location_selected)
	right_panel.add_child(neighbor_available_list)

	neighbor_add_button = Button.new()
	neighbor_add_button.text = "Add as Neighbors"
	neighbor_add_button.disabled = true
	neighbor_add_button.pressed.connect(_on_neighbor_add_pressed)
	right_panel.add_child(neighbor_add_button)

	# Status label
	neighbor_status_label = Label.new()
	neighbor_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(neighbor_status_label)

func _build_schedule_editor_ui(parent: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)

	var container = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 10)
	scroll.add_child(container)

	var title = Label.new()
	title.text = "Schedule Builder"
	title.add_theme_font_size_override("font_size", 16)
	container.add_child(title)

	var info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "Define per-character schedules for each time slot. Chances (0.01-1.0) are normalized."
	container.add_child(info)

	# --- Top Management Bar ---
	var top_bar = HBoxContainer.new()
	container.add_child(top_bar)

	var schedule_label = Label.new()
	schedule_label.text = "Schedule File:"
	top_bar.add_child(schedule_label)

	schedule_selector = OptionButton.new()
	schedule_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	schedule_selector.item_selected.connect(_on_schedule_selected)
	top_bar.add_child(schedule_selector)

	var schedule_actions_sep = VSeparator.new()
	top_bar.add_child(schedule_actions_sep)

	var name_lbl = Label.new()
	name_lbl.text = "Name:"
	top_bar.add_child(name_lbl)

	schedule_name_field = LineEdit.new()
	schedule_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	schedule_name_field.placeholder_text = "Schedule Name"
	schedule_name_field.text_changed.connect(_on_schedule_name_changed)
	schedule_name_field.text_submitted.connect(_on_schedule_name_submitted)
	top_bar.add_child(schedule_name_field)

	var schedule_actions_sep2 = VSeparator.new()
	top_bar.add_child(schedule_actions_sep2)

	schedule_reload_button = Button.new()
	schedule_reload_button.text = "Reload"
	schedule_reload_button.pressed.connect(_on_schedule_reload_pressed)
	top_bar.add_child(schedule_reload_button)

	schedule_save_button = Button.new()
	schedule_save_button.text = "Save Changes"
	schedule_save_button.disabled = true
	schedule_save_button.pressed.connect(_on_schedule_save_pressed)
	top_bar.add_child(schedule_save_button)

	# --- Schedule Actions ---
	var manage_bar = HBoxContainer.new()
	manage_bar.alignment = BoxContainer.ALIGNMENT_END
	container.add_child(manage_bar)

	schedule_set_active_button = Button.new()
	schedule_set_active_button.text = "Set Active"
	schedule_set_active_button.pressed.connect(_on_schedule_set_active_pressed)
	manage_bar.add_child(schedule_set_active_button)

	schedule_active_label = Label.new()
	schedule_active_label.add_theme_color_override("font_color", Color(0.5, 1, 0.5))
	manage_bar.add_child(schedule_active_label)

	manage_bar.add_child(VSeparator.new())

	schedule_add_schedule_button = Button.new()
	schedule_add_schedule_button.text = "New File"
	schedule_add_schedule_button.pressed.connect(_on_schedule_add_pressed)
	manage_bar.add_child(schedule_add_schedule_button)

	schedule_duplicate_schedule_button = Button.new()
	schedule_duplicate_schedule_button.text = "Duplicate"
	schedule_duplicate_schedule_button.pressed.connect(_on_schedule_duplicate_pressed)
	manage_bar.add_child(schedule_duplicate_schedule_button)

	schedule_remove_schedule_button = Button.new()
	schedule_remove_schedule_button.text = "Delete"
	schedule_remove_schedule_button.pressed.connect(_on_schedule_remove_pressed)
	manage_bar.add_child(schedule_remove_schedule_button)

	container.add_child(HSeparator.new())

	# --- Main Content Split ---
	var split = HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.custom_minimum_size = Vector2(0, 400)
	container.add_child(split)

	# --- Left Panel: Character List ---
	var left_panel = VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(250, 0)
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(left_panel)

	# Header for list
	var list_header = HBoxContainer.new()
	left_panel.add_child(list_header)
	
	var char_label = Label.new()
	char_label.text = "Characters"
	char_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_header.add_child(char_label)

	schedule_add_missing_button = Button.new()
	schedule_add_missing_button.text = "+ All Missing"
	schedule_add_missing_button.tooltip_text = "Add all defined characters to this schedule"
	schedule_add_missing_button.pressed.connect(_on_schedule_add_missing_pressed)
	list_header.add_child(schedule_add_missing_button)

	# The list
	schedule_character_list = ItemList.new()
	schedule_character_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	schedule_character_list.item_selected.connect(_on_schedule_character_selected)
	left_panel.add_child(schedule_character_list)

	# Manual Add/Remove
	var add_char_row = HBoxContainer.new()
	left_panel.add_child(add_char_row)

	schedule_add_character_option = OptionButton.new()
	schedule_add_character_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	schedule_add_character_option.clip_text = true
	add_char_row.add_child(schedule_add_character_option)

	schedule_add_character_button = Button.new()
	schedule_add_character_button.text = "Add"
	schedule_add_character_button.pressed.connect(_on_schedule_add_character_pressed)
	add_char_row.add_child(schedule_add_character_button)
	
	schedule_remove_character_button = Button.new()
	schedule_remove_character_button.text = "Remove"
	schedule_remove_character_button.pressed.connect(_on_schedule_remove_character_pressed)
	left_panel.add_child(schedule_remove_character_button)


	# --- Right Panel: Editor ---
	var right_panel = VBoxContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right_panel)

	var detail_label = Label.new()
	detail_label.text = "Configuration"
	detail_label.add_theme_font_size_override("font_size", 16)
	right_panel.add_child(detail_label)

	var detail_grid = GridContainer.new()
	detail_grid.columns = 2
	right_panel.add_child(detail_grid)

	var name_label = Label.new()
	name_label.text = "Display Name:"
	detail_grid.add_child(name_label)
	schedule_character_name_field = LineEdit.new()
	schedule_character_name_field.custom_minimum_size = Vector2(200, 0)
	schedule_character_name_field.text_changed.connect(_on_schedule_char_name_changed)
	detail_grid.add_child(schedule_character_name_field)

	var default_label = Label.new()
	default_label.text = "Default Location:"
	detail_grid.add_child(default_label)
	schedule_default_location_field = LineEdit.new()
	schedule_default_location_field.placeholder_text = "e.g. golden_oak_library"
	schedule_default_location_field.text_changed.connect(_on_schedule_char_default_changed)
	detail_grid.add_child(schedule_default_location_field)

	right_panel.add_child(HSeparator.new())

	# Time Slots via TabContainer
	var tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(tabs)

	for slot_info in SCHEDULE_TIME_SLOTS:
		var tab_name = slot_info["label"]
		var slot_key = slot_info["key"]
		var tab_content = VBoxContainer.new()
		tab_content.name = tab_name
		tabs.add_child(tab_content)
		# Add internal spacing
		var margin_container = MarginContainer.new()
		margin_container.add_theme_constant_override("margin_top", 10)
		margin_container.add_theme_constant_override("margin_left", 10)
		margin_container.add_theme_constant_override("margin_right", 10)
		margin_container.add_theme_constant_override("margin_bottom", 10)
		margin_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tab_content.add_child(margin_container)
		
		var inner_vbox = VBoxContainer.new()
		inner_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		margin_container.add_child(inner_vbox)
		
		_create_schedule_slot_editor(inner_vbox, tab_name, slot_key)

	schedule_status_label = Label.new()
	schedule_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	container.add_child(schedule_status_label)
	_set_schedule_fields_enabled(false)

# --- Event Editor UI Construction ---

func _build_event_editor_ui(parent: VBoxContainer) -> void:
	# Top Bar: Search and File Ops
	var top_bar = HBoxContainer.new()
	parent.add_child(top_bar)

	var search_lbl = Label.new()
	search_lbl.text = "Search Events:"
	top_bar.add_child(search_lbl)
	
	event_search = LineEdit.new()
	event_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_search.placeholder_text = "Filter by ID..."
	event_search.text_changed.connect(_on_event_search_changed)
	top_bar.add_child(event_search)

	var refresh_btn = Button.new()
	refresh_btn.text = "Reload"
	refresh_btn.pressed.connect(_on_event_reload_pressed)
	top_bar.add_child(refresh_btn)

	event_save_button = Button.new()
	event_save_button.text = "Save Events"
	event_save_button.disabled = true
	event_save_button.pressed.connect(_on_event_save_pressed)
	top_bar.add_child(event_save_button)

	# Main Split: List vs Editor
	var split = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(split)

	# Left: Event List
	var left_panel = VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(200, 0)
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(left_panel)

	var list_ops = HBoxContainer.new()
	left_panel.add_child(list_ops)
	
	var add_evt_btn = Button.new()
	add_evt_btn.text = "New Event"
	add_evt_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_evt_btn.pressed.connect(_on_event_add_pressed)
	list_ops.add_child(add_evt_btn)

	var del_evt_btn = Button.new()
	del_evt_btn.text = "Delete"
	del_evt_btn.pressed.connect(_on_event_delete_pressed)
	list_ops.add_child(del_evt_btn)

	event_list = ItemList.new()
	event_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	event_list.item_selected.connect(_on_event_selected)
	left_panel.add_child(event_list)

	# Right: Action Editor
	var right_panel = VBoxContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right_panel)

	# Event Metadata
	var meta_row = HBoxContainer.new()
	right_panel.add_child(meta_row)
	var event_id_lbl = Label.new()
	event_id_lbl.text = "Event ID:"
	meta_row.add_child(event_id_lbl)
	event_id_field = LineEdit.new()
	event_id_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_id_field.editable = true
	event_id_field.placeholder_text = "Enter unique ID..."
	event_id_field.focus_exited.connect(_on_event_id_renamed)
	event_id_field.text_submitted.connect(func(_t): _on_event_id_renamed())
	meta_row.add_child(event_id_field)

	# Breadcrumbs
	action_breadcrumbs = HBoxContainer.new()
	right_panel.add_child(action_breadcrumbs)

	# Action List (Top Half of Right)
	var action_split = VSplitContainer.new()
	action_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(action_split)

	var action_top = VBoxContainer.new()
	action_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_split.add_child(action_top)

	# Toolbar for actions
	var action_toolbar = HBoxContainer.new()
	action_top.add_child(action_toolbar)

	action_add_type_option = OptionButton.new()
	for type in EVENT_ACTION_TYPES:
		action_add_type_option.add_item(type["label"])
		action_add_type_option.set_item_metadata(action_add_type_option.get_item_count()-1, type["id"])
	action_toolbar.add_child(action_add_type_option)

	var add_action_btn = Button.new()
	add_action_btn.text = "Add Action"
	add_action_btn.pressed.connect(_on_event_add_action_pressed)
	action_toolbar.add_child(add_action_btn)
	
	action_toolbar.add_child(VSeparator.new())

	var move_up_btn = Button.new()
	move_up_btn.text = "Move Up"
	move_up_btn.pressed.connect(_on_event_action_move.bind(-1))
	action_toolbar.add_child(move_up_btn)

	var move_down_btn = Button.new()
	move_down_btn.text = "Move Down"
	move_down_btn.pressed.connect(_on_event_action_move.bind(1))
	action_toolbar.add_child(move_down_btn)

	var remove_action_btn = Button.new()
	remove_action_btn.text = "Remove"
	remove_action_btn.pressed.connect(_on_event_remove_action_pressed)
	action_toolbar.add_child(remove_action_btn)

	action_list = ItemList.new()
	action_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_list.item_selected.connect(_on_event_action_selected)
	action_top.add_child(action_list)

	# Action Properties (Bottom Half of Right)
	var prop_scroll = ScrollContainer.new()
	prop_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_split.add_child(prop_scroll)

	action_properties_container = VBoxContainer.new()
	action_properties_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prop_scroll.add_child(action_properties_container)

	# Status
	event_status_label = Label.new()
	event_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(event_status_label)

# --- Event Editor Logic ---

func _load_event_data() -> void:
	event_data = {"events": {}}
	if FileAccess.file_exists(EVENTS_FILE_PATH):
		var file = FileAccess.open(EVENTS_FILE_PATH, FileAccess.READ)
		if file:
			var json = JSON.new()
			var error = json.parse(file.get_as_text())
			if error == OK:
				var data = json.get_data()
				if typeof(data) == TYPE_DICTIONARY and data.has("events"):
					event_data = data
			file.close()
	
	_refresh_event_list()
	_mark_event_dirty(false)

func _save_event_data() -> void:
	if not DirAccess.dir_exists_absolute("res://assets/Events"):
		DirAccess.make_dir_absolute("res://assets/Events")
		
	var file = FileAccess.open(EVENTS_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(event_data, "  "))
		file.close()
		_mark_event_dirty(false)
		_set_event_status("Events saved successfully.")
	else:
		_set_event_status("Error saving events.")

func _mark_event_dirty(dirty: bool) -> void:
	event_dirty = dirty
	if event_save_button:
		event_save_button.disabled = not dirty

func _set_event_status(text: String) -> void:
	if event_status_label:
		event_status_label.text = text

func _refresh_event_list() -> void:
	if not event_list: return
	
	var filter = event_search.text.to_lower()
	event_list.clear()
	event_list_data.clear()
	
	var ids = event_data["events"].keys()
	ids.sort()
	
	for id in ids:
		if filter == "" or id.to_lower().contains(filter):
			event_list.add_item(id)
			event_list_data.append(id)
	
	if current_event_id != "":
		var idx = event_list_data.find(current_event_id)
		if idx != -1:
			event_list.select(idx)
		else:
			current_event_id = ""
			_clear_event_editor()

func _on_event_search_changed(_new_text: String) -> void:
	current_event_id = ""
	_clear_event_editor()
	_refresh_event_list()

func _on_event_reload_pressed() -> void:
	_load_event_data()

func _on_event_save_pressed() -> void:
	_save_event_data()

func _on_event_add_pressed() -> void:
	var base_id = "new_event"
	var counter = 1
	var new_id = base_id
	while event_data["events"].has(new_id):
		counter += 1
		new_id = base_id + "_" + str(counter)
	
	event_data["events"][new_id] = {
		"id": new_id,
		"actions": []
	}
	
	current_event_id = new_id
	_mark_event_dirty(true)
	_refresh_event_list()
	_load_event_into_editor(new_id)

func _on_event_delete_pressed() -> void:
	if current_event_id == "": return
	
	event_data["events"].erase(current_event_id)
	current_event_id = ""
	_mark_event_dirty(true)
	_refresh_event_list()
	_clear_event_editor()

func _on_event_selected(index: int) -> void:
	if index < 0 or index >= event_list_data.size(): return
	var id = event_list_data[index]
	current_event_id = id
	_load_event_into_editor(id)

func _clear_event_editor() -> void:
	event_id_field.text = ""
	action_list.clear()
	current_action_path = []
	_refresh_action_list()
	_clear_action_properties()

func _load_event_into_editor(event_id: String) -> void:
	event_id_field.text = event_id
	var event = event_data["events"][event_id]
	if not event.has("actions"): event["actions"] = []
	
	# Root level
	current_action_path = [{"target": event["actions"], "name": "Main Sequence"}]
	_refresh_action_breadcrumbs()
	_refresh_action_list()
	_clear_action_properties()

func _refresh_action_breadcrumbs() -> void:
	for c in action_breadcrumbs.get_children():
		c.queue_free()
	
	for i in range(current_action_path.size()):
		var entry = current_action_path[i]
		var btn = Button.new()
		btn.text = entry["name"]
		if i == current_action_path.size() - 1:
			btn.disabled = true
			btn.add_theme_font_size_override("font_size", 14)
		else:
			btn.pressed.connect(_on_breadcrumb_clicked.bind(i))
		action_breadcrumbs.add_child(btn)
		
		if i < current_action_path.size() - 1:
			var sep = Label.new()
			sep.text = ">"
			action_breadcrumbs.add_child(sep)

func _on_breadcrumb_clicked(index: int) -> void:
	current_action_path = current_action_path.slice(0, index + 1)
	_refresh_action_breadcrumbs()
	_refresh_action_list()
	_clear_action_properties()

func _get_current_action_array() -> Array:
	if current_action_path.is_empty(): return []
	return current_action_path.back()["target"]

## Get all character IDs from character_enter actions that appear before the given action
func _get_entered_characters_before_action(target_action: Dictionary) -> Array:
	var result: Array = []
	var actions = _get_current_action_array()
	
	for action in actions:
		# Stop when we reach the target action
		if action == target_action:
			break
		
		# Collect character IDs from character_enter actions
		if action.get("type", "") == "character_enter":
			var char_id = str(action.get("character_id", ""))
			if char_id != "" and char_id not in result:
				result.append(char_id)
	
	return result

func _refresh_action_list() -> void:
	action_list.clear()
	var actions = _get_current_action_array()
	for i in range(actions.size()):
		var action = actions[i]
		var type = action.get("type", "unknown")
		var label = type
		# Improved labels
		for t in EVENT_ACTION_TYPES:
			if t["id"] == type:
				label = t["label"]
				break
		
		# Add specific detail if possible
		var detail = ""
		match type:
			"change_location": detail = str(action.get("location_id", ""))
			"character_enter": detail = str(action.get("character_id", ""))
			"dialogue": detail = "%s: %s" % [str(action.get("speaker_id", "")), str(action.get("text", "")).left(20)]
			"branch": detail = str(action.get("prompt", "")).left(20)
			"conditional_branch": detail = "(Silent)"
			"create_group": 
				var members = action.get("members", [])
				detail = "(%d chars)" % members.size() if members.size() > 0 else "(empty)"
			"create_checkpoint", "return_to_checkpoint": detail = str(action.get("checkpoint_id", ""))
		
		if detail != "":
			label += " (" + detail + ")"
			
		action_list.add_item(label)

func _on_event_add_action_pressed() -> void:
	if current_event_id == "" or current_action_path.is_empty(): return
	
	var type_id = str(action_add_type_option.get_selected_metadata())
	var new_action = {"type": type_id}
	
	# Default props
	match type_id:
		"change_location": new_action["location_id"] = ""
		"character_enter": new_action["character_id"] = "";
		"dialogue": new_action["speaker_id"] = ""; new_action["text"] = ""
		"branch": new_action["prompt"] = ""; new_action["options"] = []
		"conditional_branch": new_action["options"] = []
		"create_checkpoint": new_action["checkpoint_id"] = "point_1"
		"return_to_checkpoint": new_action["checkpoint_id"] = "point_1"
		"create_group": new_action["group_id"] = "group_1"; new_action["members"] = []
		"end_event": pass
	
	var arr: Array = _get_current_action_array()
	arr.append(new_action)
	
	_mark_event_dirty(true)
	_refresh_action_list()
	action_list.select(arr.size() - 1)
	_on_event_action_selected(arr.size() - 1)

func _on_event_remove_action_pressed() -> void:
	var sel = action_list.get_selected_items()
	if sel.is_empty(): return
	var idx = sel[0]
	var arr = _get_current_action_array()
	if idx < arr.size():
		arr.remove_at(idx)
		_mark_event_dirty(true)
		_refresh_action_list()
		_clear_action_properties()

func _on_event_action_move(param_dir: int) -> void:
	var sel = action_list.get_selected_items()
	if sel.is_empty(): return
	var idx = sel[0]
	var arr = _get_current_action_array()
	var new_idx = idx + param_dir
	if new_idx >= 0 and new_idx < arr.size():
		var tmp = arr[idx]
		arr[idx] = arr[new_idx]
		arr[new_idx] = tmp
		_mark_event_dirty(true)
		_refresh_action_list()
		action_list.select(new_idx)

func _on_event_action_selected(index: int) -> void:
	_clear_action_properties()
	var arr = _get_current_action_array()
	if index < 0 or index >= arr.size(): return
	var action = arr[index]
	_build_action_properties(action, index)

func _on_event_id_renamed() -> void:
	if current_event_id == "" or not event_data["events"].has(current_event_id):
		return
	
	var new_id = event_id_field.text.strip_edges()
	if new_id == "" or new_id == current_event_id:
		event_id_field.text = current_event_id # revert
		return
	
	if event_data["events"].has(new_id):
		_set_event_status("Error: Event ID '%s' already exists." % new_id)
		event_id_field.text = current_event_id
		return
	
	# Rename
	var event = event_data["events"][current_event_id]
	event["id"] = new_id
	event_data["events"].erase(current_event_id)
	event_data["events"][new_id] = event
	current_event_id = new_id
	
	_mark_event_dirty(true)
	_refresh_event_list()
	_set_event_status("Renamed event to '%s'." % new_id)

func _clear_action_properties() -> void:
	for c in action_properties_container.get_children():
		c.queue_free()

func _build_action_properties(action: Dictionary, act_idx: int = -1) -> void:
	var type = action.get("type", "")
	
	# Common helper
	var add_row = func(label_t: String, control: Control):
		var row = HBoxContainer.new()
		var l = Label.new()
		l.text = label_t
		l.custom_minimum_size = Vector2(120, 0)
		row.add_child(l)
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(control)
		action_properties_container.add_child(row)
		return row

	match type:
		"set_variable":
			# 1. Collect known variables
			var known_vars_dict = {
				"current_location_id": "string",
				"day_index": "int",
				"time_slot": "int",
				"valid_rest_locations": "array"
			}
			# Basic defaults for simulation
			var default_state = {
				"current_location_id": "ponyville_main_square",
				"day_index": 0,
				"time_slot": 0,
				"valid_rest_locations": []
			}
			
			var known_vars = []
			
			# Reuse scan logic (simplified)
			var _scan_recur_vars = func(acts: Array, collector: Dictionary, self_ref):
				for act in acts:
					if act.get("type") == "set_variable":
						var v = act.get("var_name", "")
						var val = act.get("value")
						var vt = "string"
						if typeof(val) == TYPE_INT: vt = "int"
						elif typeof(val) == TYPE_FLOAT: vt = "float"
						elif typeof(val) == TYPE_BOOL: vt = "bool"
						elif typeof(val) == TYPE_ARRAY: vt = "array"
						if v != "": collector[v] = vt
					elif act.get("type") == "branch":
						for o in act.get("options", []):
							if o.has("actions"): self_ref.call(o["actions"], collector, self_ref)
							
			if event_data.has("events"):
				for ev_id in event_data["events"]:
					var ev = event_data["events"][ev_id]
					if ev.has("actions"): _scan_recur_vars.call(ev["actions"], known_vars_dict, _scan_recur_vars)
			
			known_vars = known_vars_dict.keys()
			known_vars.sort()

			# Helper to simulate state up to this action
			var _get_simulated_value = func(target_var: String):
				# Start with defaults
				var state = default_state.duplicate(true)
				
				# Iterate current sequence up to this action
				var acts = _get_current_action_array()
				for i in range(act_idx): # Up to current index (exclusive) means PREVIOUS actions
					if i >= acts.size(): break
					var a = acts[i]
					var t = a.get("type", "")
					if t == "set_variable":
						var vn = a.get("var_name", "")
						if vn != "":
							state[vn] = a.get("value")
					elif t == "advance_time":
						var m = a.get("mode", "next_day_morning")
						var d = int(state.get("day_index", 0))
						var s = int(state.get("time_slot", 0))
						if m == "next_day_morning":
							d += 1; s = 0
						elif m == "next_time_slot":
							s += 1
							if s > 2: s = 0; d += 1
						elif m == "specific_time":
							var ts_map = {"morning": 0, "day": 1, "night": 2}
							var tgt = ts_map.get(a.get("target_slot", "morning"), 0)
							if tgt <= s: d += 1
							s = tgt
						state["day_index"] = d
						state["time_slot"] = s
					elif t == "change_location":
						state["current_location_id"] = a.get("location_id", "")
				
				if state.has(target_var):
					return state[target_var]
				return null

			# Variable Name Input with Autocomplete
			var name_edit = LineEdit.new()
			name_edit.text = str(action.get("var_name", ""))
			name_edit.placeholder_text = "Variable Name"
			name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
			# Autocomplete Panel
			var auto_panel = PanelContainer.new()
			auto_panel.visible = false
			auto_panel.set_as_top_level(true)
			auto_panel.z_index = 100
			var auto_list = ItemList.new()
			auto_list.auto_height = true
			auto_list.focus_mode = Control.FOCUS_NONE
			auto_panel.add_child(auto_list)
			
			# Container for row input
			var var_box = HBoxContainer.new()
			var_box.add_child(name_edit)
			
			# Load Current Value Button
			var load_btn = Button.new()
			load_btn.text = "Load Current"
			load_btn.tooltip_text = "Load the simulated value of this variable from the event chain up to this point."
			var_box.add_child(load_btn)
			
			# Add panel to scene
			var_box.add_child(auto_panel)
			
			add_row.call("Variable Name:", var_box)
			
			var type_opt = OptionButton.new() # Defined early for ref
			var types = ["string", "int", "float", "bool", "array", "dictionary"]
			
			# Type enforcement helper
			var _enforce_type = func(v_name: String):
				action["var_name"] = v_name
				_mark_event_dirty(true)
				if known_vars_dict.has(v_name):
					var req_type = known_vars_dict[v_name]
					var idx = types.find(req_type)
					if idx != -1:
						type_opt.select(idx)
						type_opt.item_selected.emit(idx)
						type_opt.disabled = true
				else:
					type_opt.disabled = false

			# Auto Logic
			name_edit.text_changed.connect(func(new_text):
				action["var_name"] = new_text
				_mark_event_dirty(true)
				
				if known_vars.is_empty(): return
				auto_list.clear()
				var cnt = 0
				for v in known_vars:
					if new_text == "" or new_text.to_lower() in v.to_lower():
						auto_list.add_item(v)
						cnt += 1
				
				if cnt > 0 and new_text != "":
					var gp = name_edit.get_global_position()
					var sz = name_edit.get_size()
					auto_panel.position = Vector2(gp.x, gp.y + sz.y)
					auto_panel.size = Vector2(sz.x, 0)
					auto_panel.show()
				else:
					auto_panel.hide()
			)
			
			name_edit.focus_exited.connect(func():
				await name_edit.get_tree().create_timer(0.2).timeout
				if is_instance_valid(auto_panel): auto_panel.hide()
			)
			
			auto_list.item_clicked.connect(func(idx, _a, _b):
				var txt = auto_list.get_item_text(idx)
				name_edit.text = txt
				auto_panel.hide()
				_enforce_type.call(txt)
			)

			# Pick Button
			if not known_vars.is_empty():
				var pick = MenuButton.new()
				pick.text = "v"
				var pop = pick.get_popup()
				pop.add_item("(New Variable...)", 9999) # Special ID
				pop.add_separator()
				for v in known_vars: pop.add_item(v)
				
				pop.id_pressed.connect(func(id):
					if id == 9999:
						# reset
						name_edit.text = ""
						action["var_name"] = ""
						type_opt.disabled = false
						_mark_event_dirty(true)
					else:
						var txt = pop.get_item_text(pop.get_item_index(id))
						name_edit.text = txt
						_enforce_type.call(txt)
				)
				var_box.add_child(pick)

			for t in types: type_opt.add_item(t)
			
			var current_type = str(action.get("var_type", "string"))
			var type_idx = types.find(current_type)
			if type_idx != -1:
				type_opt.select(type_idx)
			else:
				type_opt.select(0)
			
			var val_container = HBoxContainer.new()
			# Helper for single value input (extracted for reuse)
			var _create_single_input = func(target_dict: Dictionary, key: String, sel_type: String, container: Control, callback: Callable = Callable()):
				if sel_type == "bool":
					var val_input = CheckBox.new()
					val_input.text = "True"
					val_input.button_pressed = bool(target_dict.get(key, false))
					val_input.toggled.connect(func(b): 
						target_dict[key] = b
						if callback.is_valid(): callback.call()
						_mark_event_dirty(true)
					)
					val_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					container.add_child(val_input)
				elif sel_type == "int":
					var val_input = SpinBox.new()
					val_input.rounded = true
					val_input.allow_greater = true; val_input.allow_lesser = true
					val_input.value = int(target_dict.get(key, 0))
					val_input.value_changed.connect(func(v): 
						target_dict[key] = int(v)
						if callback.is_valid(): callback.call()
						_mark_event_dirty(true)
					)
					val_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					container.add_child(val_input)
				elif sel_type == "float":
					var val_input = SpinBox.new()
					val_input.step = 0.01
					val_input.allow_greater = true; val_input.allow_lesser = true
					val_input.value = float(target_dict.get(key, 0.0))
					val_input.value_changed.connect(func(v): 
						target_dict[key] = float(v)
						if callback.is_valid(): callback.call()
						_mark_event_dirty(true)
					)
					val_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					container.add_child(val_input)
				else: # string
					var val_input = LineEdit.new()
					val_input.text = str(target_dict.get(key, ""))
					val_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					val_input.text_changed.connect(func(t): 
						target_dict[key] = t
						if callback.is_valid(): callback.call()
						_mark_event_dirty(true)
					)
					val_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					container.add_child(val_input)

			var update_val_input = func(sel_type: String, self_ref: Callable):
				for c in val_container.get_children(): c.queue_free()
				
				# Operation Dropdown only for Dictionaries
				if sel_type == "dictionary":
					var op_hbox = HBoxContainer.new()
					op_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					val_container.add_child(op_hbox)
					
					var op_lbl = Label.new()
					op_lbl.text = "Op:"
					op_hbox.add_child(op_lbl)
					
					var op_opt = OptionButton.new()
					var ops = ["set", "merge", "add_key", "remove_key"]
					for op in ops: op_opt.add_item(op.capitalize().replace("_", " "))
					
					var cur_op = action.get("operation", "set")
					var op_idx = ops.find(cur_op)
					if op_idx != -1: op_opt.select(op_idx)

					# Description Label
					var desc_lbl = Label.new()
					desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
					desc_lbl.add_theme_font_size_override("font_size", 10)
					
					var update_desc = func(op):
						if op == "set": desc_lbl.text = "(Overwrites entire variable)"
						elif op == "merge": desc_lbl.text = "(Updates keys & adds new ones)"
						elif op == "add_key": desc_lbl.text = "(Adds/Updates single key)"
						elif op == "remove_key": desc_lbl.text = "(Removes single key)"
					
					update_desc.call(cur_op)
					
					op_opt.item_selected.connect(func(idx):
						action["operation"] = ops[idx]
						_mark_event_dirty(true)
						# Re-trigger update to change inputs
						self_ref.call("dictionary", self_ref)
					)
					op_hbox.add_child(op_opt)
					op_hbox.add_child(desc_lbl)
					
					var dict_val_vbox = VBoxContainer.new()
					dict_val_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					val_container.add_child(dict_val_vbox)
					
					if cur_op == "remove_key":
						# Single key (string) input
						var k_edit = LineEdit.new()
						k_edit.placeholder_text = "Key to remove"
						if typeof(action.get("value")) == TYPE_STRING:
							k_edit.text = action.get("value", "")
						k_edit.text_changed.connect(func(t): 
							action["value"] = t
							_mark_event_dirty(true)
						)
						dict_val_vbox.add_child(k_edit)
						
					elif cur_op == "add_key":
						# Single Key-Value Pair
						# Ensure value is dict
						if typeof(action.get("value")) != TYPE_DICTIONARY: action["value"] = {}
						var d_val = action["value"]
						
						# UI: Key Input | Type | Value
						var kv_row = HBoxContainer.new()
						dict_val_vbox.add_child(kv_row)
						
						var k_edit = LineEdit.new()
						k_edit.placeholder_text = "Key"
						k_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
						# Since add_key adds ONE key, we usually store it as { "key": "value" }
						# But here we might want to store it as { "key_name": val } in action.value
						# Let's assume action.value IS the dictionary to merge.
						# So we just edit the FIRST key found, or empty.
						var keys = d_val.keys()
						var first_key = keys[0] if keys.size() > 0 else ""
						k_edit.text = str(first_key)
						
						kv_row.add_child(k_edit)
						
						var v_type_opt = OptionButton.new()
						for t in ["string", "int", "float", "bool"]: v_type_opt.add_item(t)
						
						var initial_v_type = "string"
						var initial_v = ""
						if keys.size() > 0:
							initial_v = d_val[first_key]
							if typeof(initial_v) == TYPE_INT: initial_v_type = "int"
							elif typeof(initial_v) == TYPE_FLOAT: initial_v_type = "float"
							elif typeof(initial_v) == TYPE_BOOL: initial_v_type = "bool"
							
						var vt_idx = ["string", "int", "float", "bool"].find(initial_v_type)
						if vt_idx != -1: v_type_opt.select(vt_idx)
						
						var val_input_container = HBoxContainer.new()
						
						# Update Logic
						var _update_kv = func():
							var k = k_edit.text
							if k == "": return
							# Recreate dict with single key
							var new_d = {}
							
							# Get value from input container
							# This is tricky because recreating input destroys state.
							# Instead, we update the dict reference passed to input.
							# But key change means new entry.
							# Use separate holder object
							pass
						
						# Simplified approach: Holder Dictionary
						var holder = { "v": initial_v }
						
						var _refresh_v_input = func(vt: String):
							for c in val_input_container.get_children(): c.queue_free()
							_create_single_input.call(holder, "v", vt, val_input_container, func():
								if k_edit.text != "":
									action["value"] = { k_edit.text: holder["v"] }
									_mark_event_dirty(true)
							)
						
						_refresh_v_input.call(initial_v_type)
						
						v_type_opt.item_selected.connect(func(idx):
							var new_t = v_type_opt.get_item_text(idx)
							# Reset default
							if new_t == "string": holder["v"] = ""
							elif new_t == "int": holder["v"] = 0
							elif new_t == "float": holder["v"] = 0.0
							elif new_t == "bool": holder["v"] = false
							_refresh_v_input.call(new_t)
							if k_edit.text != "":
								action["value"] = { k_edit.text: holder["v"] }
								_mark_event_dirty(true)
						)
						
						k_edit.text_changed.connect(func(t):
							if t != "":
								action["value"] = { t: holder["v"] }
								_mark_event_dirty(true)
						)
						
						kv_row.add_child(v_type_opt)
						kv_row.add_child(val_input_container)
						
					else: # set or merge (Full Dictionary Editor)
						if typeof(action.get("value")) != TYPE_DICTIONARY: action["value"] = {}
						var d_val = action["value"]
						
						var render_dict = func(self_ref):
							for c in dict_val_vbox.get_children(): c.queue_free()
							
							var keys = d_val.keys()
							for k in keys:
								var row = HBoxContainer.new()
								dict_val_vbox.add_child(row)
								
								var k_lbl = LineEdit.new()
								k_lbl.text = str(k)
								k_lbl.editable = false # Keys immutable in this simple view
								k_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
								row.add_child(k_lbl)
								
								var val = d_val[k]
								var vt = "string"
								if typeof(val) == TYPE_INT: vt = "int"
								elif typeof(val) == TYPE_FLOAT: vt = "float"
								elif typeof(val) == TYPE_BOOL: vt = "bool"
								
								var val_holder = { "v": val }
								_create_single_input.call(val_holder, "v", vt, row, func():
									d_val[k] = val_holder["v"]
									action["value"] = d_val
									_mark_event_dirty(true)
								)
								
								var del = Button.new()
								del.text = "X"
								del.modulate = Color(1,0.5,0.5)
								del.pressed.connect(func():
									d_val.erase(k)
									action["value"] = d_val
									_mark_event_dirty(true)
									self_ref.call(self_ref)
								)
								row.add_child(del)

							# Add New Key Row
							var new_key_row = HBoxContainer.new()
							dict_val_vbox.add_child(new_key_row)
							
							var new_k = LineEdit.new()
							new_k.placeholder_text = "New Key"
							new_k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
							new_key_row.add_child(new_k)
							
							var new_t_opt = OptionButton.new()
							for t in ["string", "int", "float", "bool"]: new_t_opt.add_item(t)
							new_key_row.add_child(new_t_opt)
							
							var add_btn = Button.new()
							add_btn.text = "+"
							add_btn.pressed.connect(func():
								if new_k.text == "": return
								if d_val.has(new_k.text): return
								
								var t = new_t_opt.get_item_text(new_t_opt.selected)
								var init_v
								if t == "string": init_v = ""
								elif t == "int": init_v = 0
								elif t == "float": init_v = 0.0
								elif t == "bool": init_v = false
								
								d_val[new_k.text] = init_v
								action["value"] = d_val
								_mark_event_dirty(true)
								self_ref.call(self_ref)
							)
							new_key_row.add_child(add_btn)
						
						render_dict.call(render_dict)
				
				elif sel_type == "array":
					var list_vbox = VBoxContainer.new()
					list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					val_container.add_child(list_vbox)
					
					var arr = action.get("value", [])
					if typeof(arr) != TYPE_ARRAY: arr = []
					
					# Sub-type selector
					var subtype_row = HBoxContainer.new()
					var st_label = Label.new()
					st_label.text = "Element Type:"
					subtype_row.add_child(st_label)
					
					var subtype_opt = OptionButton.new()
					for t in ["string", "int", "float", "bool"]: subtype_opt.add_item(t)
					
					var current_subtype = action.get("array_subtype", "string")
					var st_idx = ["string", "int", "float", "bool"].find(current_subtype)
					if st_idx != -1: subtype_opt.select(st_idx)
					
					# Disable if items exist
					subtype_opt.disabled = (arr.size() > 0)
					
					subtype_opt.item_selected.connect(func(idx):
						# Only allow change if empty (enforced by disabled, but safety check ok)
						if arr.size() > 0: return 
						
						var new_st = subtype_opt.get_item_text(idx)
						action["array_subtype"] = new_st
						_mark_event_dirty(true)
					)
					subtype_row.add_child(subtype_opt)
					list_vbox.add_child(subtype_row)
					
					# Define refresh logic
					var _refresh_list = func(self_ref):
						# Clear existing items (skip first child which is subtype selector)
						for i in range(list_vbox.get_child_count() - 1, 0, -1):
							list_vbox.get_child(i).queue_free()
							
						current_subtype = action.get("array_subtype", "string")
						
						# Update disabled state based on count
						subtype_opt.disabled = (arr.size() > 0)
						
						for i in range(arr.size()):
							var item_val = arr[i]
							var row = HBoxContainer.new()
							list_vbox.add_child(row)
							
							var wrapper = {"val": item_val}
							_create_single_input.call(wrapper, "val", current_subtype, row, func(): 
								arr[i] = wrapper["val"]
								action["value"] = arr
							)
							
							var del_btn = Button.new()
							del_btn.text = "X"
							del_btn.modulate = Color(1, 0.5, 0.5)
							del_btn.pressed.connect(func():
								arr.remove_at(i)
								action["value"] = arr
								_mark_event_dirty(true)
								self_ref.call(self_ref)
							)
							row.add_child(del_btn)
						
						var add_btn = Button.new()
						add_btn.text = "+ Add Item"
						add_btn.pressed.connect(func():
							var def_val
							if current_subtype == "string": def_val = ""
							elif current_subtype == "int": def_val = 0
							elif current_subtype == "float": def_val = 0.0
							elif current_subtype == "bool": def_val = false
							
							arr.append(def_val)
							action["value"] = arr
							_mark_event_dirty(true)
							self_ref.call(self_ref)
						)
						list_vbox.add_child(add_btn)

					# Connect subtype logic to refresh
					if not subtype_opt.item_selected.is_connected(_refresh_list.bind(_refresh_list)):
						subtype_opt.item_selected.connect(func(_idx): _refresh_list.call(_refresh_list))
						subtype_opt.item_selected.connect(func(_idx): _refresh_list.call(_refresh_list))
					
					_refresh_list.call(_refresh_list)
				else:
					_create_single_input.call(action, "value", sel_type, val_container)
			
			type_opt.item_selected.connect(func(idx):
				var updated_type = type_opt.get_item_text(idx)
				action["var_type"] = updated_type
				if updated_type == "array":
					if typeof(action.get("value")) != TYPE_ARRAY: action["value"] = []
				else:
					match updated_type:
						"bool": action["value"] = false
						"int": action["value"] = 0
						"float": action["value"] = 0.0
						"string": action["value"] = ""
				update_val_input.call(updated_type, update_val_input)
				_mark_event_dirty(true)
			)
			add_row.call("Type:", type_opt)
			update_val_input.call(current_type, update_val_input)
			add_row.call("Value:", val_container)
			
			# Enforce known type lock on load
			if action.get("var_name", "") != "":
				_enforce_type.call(action["var_name"])

			# Connect Load Button
			load_btn.pressed.connect(func():
				var v_name = action.get("var_name", "")
				if v_name == "": return
				
				var sim_val = _get_simulated_value.call(v_name)
				if sim_val != null:
					if typeof(sim_val) == TYPE_ARRAY or typeof(sim_val) == TYPE_DICTIONARY:
						action["value"] = sim_val.duplicate(true)
					else:
						action["value"] = sim_val
					
					# Determine type
					var vt = "string"
					if typeof(sim_val) == TYPE_BOOL: vt = "bool"
					elif typeof(sim_val) == TYPE_INT: vt = "int"
					elif typeof(sim_val) == TYPE_FLOAT: vt = "float"
					elif typeof(sim_val) == TYPE_ARRAY: vt = "array"
					
					action["var_type"] = vt
					
					# Update Type Dropdown
					for i in range(type_opt.get_item_count()):
						if type_opt.get_item_text(i) == vt:
							type_opt.select(i)
							break
					
					# Refresh Value UI
					update_val_input.call(vt)
					_mark_event_dirty(true)
					# print("Loaded simulated value for '%s': %s" % [v_name, str(sim_val)])
				else:
					# print("No simulated value found for '%s'" % v_name)
					pass
			)

		"change_location":
			var btn = Button.new()
			btn.text = action.get("location_id", "")
			if btn.text == "": btn.text = "Select Location..."
			btn.pressed.connect(func(): _open_location_picker_for_action(btn, action))
			add_row.call("Location:", btn)
			
			var spin = SpinBox.new()
			spin.step = 0.1
			spin.value = float(action.get("fade_duration", 1.0))
			spin.value_changed.connect(func(v): action["fade_duration"] = v; _mark_event_dirty(true))
			add_row.call("Fade Time (s):", spin)
			
		"character_enter", "character_leave", "change_sprite":
			var char_opt = OptionButton.new()
			_populate_character_option(char_opt, action.get("character_id", ""))
			

			
			if type == "change_sprite" or type == "character_enter":
				var emotion_container = HBoxContainer.new()
				
				# Emotion Dropdown
				var emotion_opt = OptionButton.new()
				emotion_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				
				var update_emotion_list = func(char_tag: String):
					emotion_opt.clear()
					emotion_opt.add_item("default")
					var available = character_emotions_reference.get(char_tag, [])
					for spr in available:
						if spr != "default":
							emotion_opt.add_item(spr)
					
					var current_val = str(action.get("emotion", "default"))
					var found = false
					for i in range(emotion_opt.get_item_count()):
						if emotion_opt.get_item_text(i) == current_val:
							emotion_opt.select(i)
							found = true
							break
					if not found: 
						emotion_opt.select(0)
				
				update_emotion_list.call(str(action.get("character_id", "")))
				
				emotion_opt.item_selected.connect(func(idx): 
					action["emotion"] = emotion_opt.get_item_text(idx)
					_mark_event_dirty(true)
				)
				emotion_container.add_child(emotion_opt)
				
				add_row.call("Emotion:", emotion_container)

				# Connect character change to emotion update
				char_opt.item_selected.connect(func(idx): 
					var new_tag = char_opt.get_item_metadata(idx)
					action["character_id"] = new_tag
					action["emotion"] = "default" # Reset emotion on char change
					update_emotion_list.call(new_tag)
					_mark_event_dirty(true)
					_refresh_action_list()
				)
			else:
				# Standard connection for entering/leaving
				char_opt.item_selected.connect(func(idx): 
					action["character_id"] = char_opt.get_item_metadata(idx)
					_mark_event_dirty(true)
					_refresh_action_list()
				)

			add_row.call("Character:", char_opt)

		"dialogue":
			var spk_opt = OptionButton.new()
			# Narrator + Characters
			spk_opt.add_item("Narrator")
			spk_opt.set_item_metadata(0, "narrator")
			_populate_character_option(spk_opt, action.get("speaker_id", "narrator"), true) # append
			
			# Emotion UI
			var emotion_row_label = Label.new()
			emotion_row_label.text = "Emotion:"
			emotion_row_label.custom_minimum_size = Vector2(120, 0)
			
			var emotion_wrapper = HBoxContainer.new()
			
			var emotion_opt = OptionButton.new()
			emotion_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
			var update_diag_emotions = func(speaker_tag: String):
				emotion_opt.clear()
				if speaker_tag == "narrator":
					emotion_opt.disabled = true
					emotion_opt.add_item("(No Emotion)")
				else:
					emotion_opt.disabled = false
					emotion_opt.add_item("default")
					var available = character_emotions_reference.get(speaker_tag, [])
					for spr in available:
						if spr != "default":
							emotion_opt.add_item(spr)
						
					var current_val = str(action.get("emotion", "default"))
					var found = false
					for i in range(emotion_opt.get_item_count()):
						if emotion_opt.get_item_text(i) == current_val:
							emotion_opt.select(i)
							found = true
							break
					if not found: emotion_opt.select(0)
			
			update_diag_emotions.call(str(action.get("speaker_id", "narrator")))
			
			emotion_opt.item_selected.connect(func(idx):
				if not emotion_opt.disabled:
					action["emotion"] = emotion_opt.get_item_text(idx)
					_mark_event_dirty(true)
			)
			emotion_wrapper.add_child(emotion_opt)
			
			spk_opt.item_selected.connect(func(idx): 
				var new_speaker = spk_opt.get_item_metadata(idx)
				action["speaker_id"] = new_speaker
				# Reset emotion if switching type
				if new_speaker == "narrator":
					action.erase("emotion")
				else:
					action["emotion"] = "default"
				update_diag_emotions.call(new_speaker)
				_mark_event_dirty(true)
				_refresh_action_list()
			)
			add_row.call("Speaker:", spk_opt)
			
			var txt = TextEdit.new()
			txt.custom_minimum_size = Vector2(0, 80)
			txt.text = str(action.get("text", ""))
			txt.text_changed.connect(func(): action["text"] = txt.text; _mark_event_dirty(true); _refresh_action_list()) # Refresh for preview
			add_row.call("Text:", txt)
			
			# Manually add emotion row
			var em_row_container = HBoxContainer.new()
			em_row_container.add_child(emotion_row_label)
			emotion_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			em_row_container.add_child(emotion_wrapper)
			action_properties_container.add_child(em_row_container)
			
			# Seamless option - continue directly from prior choice text
			var seamless_check = CheckBox.new()
			seamless_check.text = "Seamlessly continue from prior choice"
			seamless_check.tooltip_text = "When enabled, this dialogue will merge onto the same line as the prior choice text instead of starting on a new line."
			seamless_check.button_pressed = action.get("seamless", false)
			seamless_check.toggled.connect(func(pressed):
				action["seamless"] = pressed
				_mark_event_dirty(true)
			)
			add_row.call("Options:", seamless_check)
			
		"llm_prompt":
			var sys = TextEdit.new()
			sys.custom_minimum_size = Vector2(0, 60)
			sys.placeholder_text = "Override system prompt/context..."
			sys.text = str(action.get("system_prompt", ""))
			sys.text_changed.connect(func(): action["system_prompt"] = sys.text; _mark_event_dirty(true))
			add_row.call("Context/System:", sys)
			
			var user = TextEdit.new()
			user.custom_minimum_size = Vector2(0, 60)
			user.placeholder_text = "Instruction for LLM..."
			user.text = str(action.get("user_prompt", ""))
			user.text_changed.connect(func(): action["user_prompt"] = user.text; _mark_event_dirty(true))
			add_row.call("Instruction:", user)
			
		"branch":
			var prompt = LineEdit.new()
			prompt.text = str(action.get("prompt", ""))
			prompt.text_changed.connect(func(t): action["prompt"] = t; _mark_event_dirty(true); _refresh_action_list())
			add_row.call("Choice Question:", prompt)
			
			var branch_list = VBoxContainer.new()
			add_row.call("Options:", branch_list)
			
			_render_branch_options(branch_list, action)

		"conditional_branch":
			var help = Label.new()
			help.text = "Automated logic branch. No UI shown."
			add_row.call("Info:", help)
			
			var branch_list = VBoxContainer.new()
			add_row.call("Branches:", branch_list)
			
			_render_branch_options(branch_list, action)

		"create_checkpoint", "return_to_checkpoint":
			var container = HBoxContainer.new()
			
			var id_edit = LineEdit.new()
			id_edit.text = str(action.get("checkpoint_id", ""))
			id_edit.placeholder_text = "Checkpoint ID"
			id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			id_edit.text_changed.connect(func(t): action["checkpoint_id"] = t; _mark_event_dirty(true); _refresh_action_list())
			container.add_child(id_edit)
			
			if type == "return_to_checkpoint":
				# Gather available checkpoints
				var known_cps = []
				var _scan = func(acts: Array, res: Array, self_r):
					for a in acts:
						if a.get("type") == "create_checkpoint":
							var c_id = str(a.get("checkpoint_id", ""))
							if c_id != "" and not c_id in res: res.append(c_id)
						if a.get("type") == "branch":
							for o in a.get("options", []):
								self_r.call(o.get("actions", []), res, self_r)
				
				if current_event_id != "" and event_data["events"].has(current_event_id):
					_scan.call(event_data["events"][current_event_id].get("actions", []), known_cps, _scan)
				
				# Autocomplete Popup
				var auto_panel = PanelContainer.new()
				auto_panel.set_as_top_level(true)
				auto_panel.visible = false
				auto_panel.z_index = 100
				var style = StyleBoxFlat.new()
				style.bg_color = Color(0.1, 0.1, 0.1)
				auto_panel.add_theme_stylebox_override("panel", style)
				
				var auto_list = ItemList.new()
				auto_list.auto_height = true
				auto_list.focus_mode = Control.FOCUS_NONE
				auto_panel.add_child(auto_list)
				container.add_child(auto_panel)
				
				auto_list.item_clicked.connect(func(idx, _a, _b):
					id_edit.text = auto_list.get_item_text(idx)
					action["checkpoint_id"] = id_edit.text
					_mark_event_dirty(true)
					_refresh_action_list()
					auto_panel.hide()
				)
				
				id_edit.text_changed.connect(func(txt):
					if known_cps.is_empty(): return
					auto_list.clear()
					var count = 0
					for cp in known_cps:
						if txt != "" and (txt.to_lower() in cp.to_lower()):
							auto_list.add_item(cp)
							count += 1
					
					if count > 0:
						var gpos = id_edit.get_global_position()
						auto_panel.position = Vector2(gpos.x, gpos.y + id_edit.size.y)
						auto_panel.size = Vector2(id_edit.size.x, 0)
						auto_panel.show()
					else:
						auto_panel.hide()
				)
				
				id_edit.focus_exited.connect(func():
					await get_tree().create_timer(0.2).timeout
					if is_instance_valid(auto_panel): auto_panel.hide()
				)

				# Dropdown (limit to available)
				if not known_cps.is_empty():
					var btn = MenuButton.new()
					btn.text = "v"
					var pop = btn.get_popup()
					for cp in known_cps: pop.add_item(cp)
					pop.id_pressed.connect(func(id):
						var txt = pop.get_item_text(pop.get_item_index(id))
						id_edit.text = txt
						action["checkpoint_id"] = txt
						_mark_event_dirty(true)
						_refresh_action_list()
					)
					container.add_child(btn)

			add_row.call("Checkpoint ID:", container)
			
		"create_group":
			# Group ID field
			var group_id_edit = LineEdit.new()
			group_id_edit.text = str(action.get("group_id", "group_1"))
			group_id_edit.placeholder_text = "Group ID"
			group_id_edit.text_changed.connect(func(t): action["group_id"] = t; _mark_event_dirty(true); _refresh_action_list())
			add_row.call("Group ID:", group_id_edit)
			
			# Info label
			var info = Label.new()
			info.text = "Select characters to group together (max 10):"
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			add_row.call("Info:", info)
			
			# Find all character_enter actions that come BEFORE this action in the sequence
			var available_chars: Array = _get_entered_characters_before_action(action)
			var current_members: Array = action.get("members", [])
			
			# Character selection list
			var char_list = VBoxContainer.new()
			add_row.call("Characters:", char_list)
			
			if available_chars.is_empty():
				var empty_label = Label.new()
				empty_label.text = "(Add Character Enter actions before this to select characters)"
				empty_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
				char_list.add_child(empty_label)
			else:
				for char_id in available_chars:
					var char_row = HBoxContainer.new()
					var check = CheckBox.new()
					check.button_pressed = char_id in current_members
					
					# Get character name if possible
					var display_name = char_id
					if character_reference.has(char_id):
						display_name = "%s (%s)" % [character_reference[char_id], char_id]
					
					check.text = display_name
					check.toggled.connect(func(pressed):
						var members: Array = action.get("members", [])
						if pressed:
							if char_id not in members and members.size() < 10:
								members.append(char_id)
						else:
							members.erase(char_id)
						action["members"] = members
						_mark_event_dirty(true)
						_refresh_action_list()
					)
					char_row.add_child(check)
					char_list.add_child(char_row)
			
		"advance_time":
			var mode_opts = ["Next Day (Morning)", "Next Time Slot (Morning->Day->Night...)", "Specific Time (Moves to next day if needed)"]
			var mode_opt = OptionButton.new()
			for m in mode_opts: mode_opt.add_item(m)
			
			var cur_mode = action.get("mode", "next_day_morning")
			var idx = 0
			if cur_mode == "next_time_slot": idx = 1
			elif cur_mode == "specific_time": idx = 2
			mode_opt.select(idx)
			
			var slot_container = HBoxContainer.new()
			var target_label = Label.new()
			target_label.text = "Target Time:"
			slot_container.add_child(target_label)
			
			var slot_opt = OptionButton.new()
			slot_opt.add_item("Morning")
			slot_opt.add_item("Day")
			slot_opt.add_item("Night")
			
			var cur_slot = action.get("target_slot", "morning")
			var s_idx = 0
			if cur_slot == "day": s_idx = 1
			elif cur_slot == "night": s_idx = 2
			slot_opt.select(s_idx)
			
			slot_opt.item_selected.connect(func(i):
				var s_val = "morning"
				if i == 1: s_val = "day"
				elif i == 2: s_val = "night"
				action["target_slot"] = s_val
				_mark_event_dirty(true)
			)
			slot_container.add_child(slot_opt)
			
			mode_opt.item_selected.connect(func(i):
				var m_val = "next_day_morning"
				if i == 1: m_val = "next_time_slot"
				elif i == 2: m_val = "specific_time"
				action["mode"] = m_val
				slot_container.visible = (m_val == "specific_time")
				_mark_event_dirty(true)
			)
			
			slot_container.visible = (cur_mode == "specific_time")
			
			add_row.call("Advance Mode:", mode_opt)
			# We add the slot container directly since we want it dynamic
			action_properties_container.add_child(slot_container)
			
		"modify_inventory":
			var op_opt = OptionButton.new()
			op_opt.add_item("Add Item", 0)
			op_opt.add_item("Remove Item", 1)
			
			var cur_op = action.get("operation", "add")
			if cur_op == "add": op_opt.select(0)
			elif cur_op == "remove": op_opt.select(1)
			
			op_opt.item_selected.connect(func(idx):
				action["operation"] = "add" if idx == 0 else "remove"
				_mark_event_dirty(true)
			)
			add_row.call("Operation:", op_opt)
			
			var item_id_edit = LineEdit.new()
			item_id_edit.text = str(action.get("item_id", ""))
			item_id_edit.placeholder_text = "Item ID"
			item_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			item_id_edit.text_changed.connect(func(t):
				action["item_id"] = t
				_mark_event_dirty(true)
			)
			add_row.call("Item ID:", item_id_edit)
			
			var amount_spin = SpinBox.new()
			amount_spin.min_value = 1
			amount_spin.value = int(action.get("amount", 1))
			amount_spin.value_changed.connect(func(v):
				action["amount"] = int(v)
				_mark_event_dirty(true)
			)
			add_row.call("Amount:", amount_spin)
		
		"edit_persona":
			# Mode: Direct edit OR show editor
			var mode_opt = OptionButton.new()
			mode_opt.add_item("Show Editor Popup", 0)
			mode_opt.add_item("Direct Field Edit", 1)
			
			var cur_show_editor = action.get("show_editor", true)
			mode_opt.select(0 if cur_show_editor else 1)
			
			# Field selection (only for direct edit mode)
			var field_container = VBoxContainer.new()
			field_container.visible = not cur_show_editor
			
			var field_opt = OptionButton.new()
			var fields = ["name", "sex", "species", "race", "appearance"]
			for f in fields:
				field_opt.add_item(f.capitalize())
			var cur_field = action.get("field", "sex")
			var field_idx = fields.find(cur_field)
			if field_idx != -1: field_opt.select(field_idx)
			
			var field_row = HBoxContainer.new()
			var field_lbl = Label.new()
			field_lbl.text = "Field:"
			field_lbl.custom_minimum_size = Vector2(120, 0)
			field_row.add_child(field_lbl)
			field_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			field_row.add_child(field_opt)
			field_container.add_child(field_row)
			
			# Value input - can be dropdown for sex/species/race or text for name/appearance
			var value_row = HBoxContainer.new()
			var value_lbl = Label.new()
			value_lbl.text = "Value:"
			value_lbl.custom_minimum_size = Vector2(120, 0)
			value_row.add_child(value_lbl)
			
			var value_input_container = VBoxContainer.new()
			value_input_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			value_row.add_child(value_input_container)
			field_container.add_child(value_row)
			
			# Function to update value input based on field type
			var update_value_input = func(field_name: String):
				for c in value_input_container.get_children():
					c.queue_free()
				
				var cur_val = str(action.get("value", ""))
				
				if field_name == "sex":
					var opt = OptionButton.new()
					opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					for i in range(SettingsManager.SEX_OPTIONS.size()):
						var item = SettingsManager.SEX_OPTIONS[i]
						opt.add_item(item["label"], i)
					opt.select(SettingsManager.get_sex_index(cur_val))
					opt.item_selected.connect(func(idx):
						action["value"] = SettingsManager.get_sex_id(idx)
						_mark_event_dirty(true)
					)
					value_input_container.add_child(opt)
				elif field_name == "species":
					var opt = OptionButton.new()
					opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					for i in range(SettingsManager.SPECIES_OPTIONS.size()):
						var item = SettingsManager.SPECIES_OPTIONS[i]
						opt.add_item(item["label"], i)
					opt.select(SettingsManager.get_species_index(cur_val))
					opt.item_selected.connect(func(idx):
						action["value"] = SettingsManager.get_species_id(idx)
						_mark_event_dirty(true)
					)
					value_input_container.add_child(opt)
				elif field_name == "race":
					var opt = OptionButton.new()
					opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					for i in range(SettingsManager.RACE_OPTIONS.size()):
						var item = SettingsManager.RACE_OPTIONS[i]
						opt.add_item(item["label"], i)
					opt.select(SettingsManager.get_race_index(cur_val))
					opt.item_selected.connect(func(idx):
						action["value"] = SettingsManager.get_race_id(idx)
						_mark_event_dirty(true)
					)
					value_input_container.add_child(opt)
				else:
					# Text field for name/appearance
					var edit = LineEdit.new()
					edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					edit.text = cur_val
					edit.placeholder_text = "Value to set"
					edit.text_changed.connect(func(t):
						action["value"] = t
						_mark_event_dirty(true)
					)
					value_input_container.add_child(edit)
			
			# Initial value input
			update_value_input.call(cur_field)
			
			field_opt.item_selected.connect(func(idx):
				action["field"] = fields[idx]
				_mark_event_dirty(true)
				update_value_input.call(fields[idx])
			)
			
			mode_opt.item_selected.connect(func(idx):
				var is_popup = (idx == 0)
				action["show_editor"] = is_popup
				if is_popup:
					action.erase("field")
					action.erase("value")
				else:
					if not action.has("field"):
						action["field"] = "sex"
					if not action.has("value"):
						action["value"] = ""
					update_value_input.call(action["field"])
				field_container.visible = not is_popup
				_mark_event_dirty(true)
			)
			
			add_row.call("Mode:", mode_opt)
			action_properties_container.add_child(field_container)
			
		"end_event":
			var l = Label.new()
			l.text = "Ends the event immediately."
			add_row.call("Info:", l)

func _render_branch_options(container: VBoxContainer, action: Dictionary) -> void:
	for c in container.get_children(): c.queue_free()
	
	var options: Array = action.get("options", [])
	
	for i in range(options.size()):
		var opt = options[i]
		var hbox = HBoxContainer.new()
		container.add_child(hbox)
		
		var lbl_edit = LineEdit.new()
		lbl_edit.text = opt.get("label", "Option")
		lbl_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl_edit.text_changed.connect(func(t): opt["label"] = t; _mark_event_dirty(true))
		hbox.add_child(lbl_edit)
		
		var cond_btn = Button.new()
		cond_btn.text = "Condition..."
		cond_btn.tooltip_text = "Set variable requirements"
		cond_btn.pressed.connect(func(): _open_branch_condition_dialog(opt))
		hbox.add_child(cond_btn)
		
		var open_btn = Button.new()
		open_btn.text = "Edit Actions"
		open_btn.pressed.connect(func(): _enter_branch(action, i))
		hbox.add_child(open_btn)
		
		var del_btn = Button.new()
		del_btn.text = "X"
		del_btn.modulate = Color(1, 0.5, 0.5)
		del_btn.pressed.connect(func(): 
			options.remove_at(i)
			_mark_event_dirty(true)
			_render_branch_options(container, action)
		)
		hbox.add_child(del_btn)

	var add_btn = Button.new()
	add_btn.text = "+ Add Option" if action.get("type") != "conditional_branch" else "+ Add Conditional Path"
	add_btn.pressed.connect(func():
		options.append({"label": "New Option" if action.get("type") != "conditional_branch" else "New Branch", "actions": []})
		_mark_event_dirty(true)
		_render_branch_options(container, action)
	)
	container.add_child(add_btn)

func _enter_branch(branch_action: Dictionary, option_index: int) -> void:
	var options = branch_action.get("options", [])
	if option_index < 0 or option_index >= options.size(): return
	var option = options[option_index]
	var label = option.get("label", "Option")
	
	current_action_path.append({"target": option["actions"], "name": label})
	_refresh_action_breadcrumbs()
	_refresh_action_list()
	_clear_action_properties()

var condition_dialog: ConfirmationDialog
var condition_editor_container: VBoxContainer

func _open_branch_condition_dialog(option_dict: Dictionary) -> void:
	if condition_dialog:
		condition_dialog.queue_free()
		
	condition_dialog = ConfirmationDialog.new()
	condition_dialog.title = "Edit Branch Condition"
	condition_dialog.size = Vector2(500, 500)
	add_child(condition_dialog)
	condition_editor_container = VBoxContainer.new()
	condition_dialog.add_child(condition_editor_container)
	
	condition_dialog.popup_centered() # Show immediately
	
	for c in condition_editor_container.get_children(): c.queue_free()
	
	var instructions = Label.new()
	instructions.text = "If these conditions are not met, the option will be hidden."
	condition_editor_container.add_child(instructions)
	
	# Condition is stored as { "var_name": "x", "operator": ">=", "value": 5, "type": "int" }
	# Or null if no condition
	
	var has_cond_check = CheckBox.new()
	has_cond_check.text = "Require Variable"
	var existing = option_dict.get("condition", null)
	
	# Check if existing is the fallback type
	var is_fallback = false
	if existing != null and existing.get("is_fallback", false):
		is_fallback = true
		existing = null # Reset for variable editor
	
	var has_var_cond = false
	if existing != null:
		if existing.has("var_name") and existing["var_name"] != "":
			has_var_cond = true
		elif existing.has("list") and not existing["list"].is_empty():
			has_var_cond = true
	
	has_cond_check.button_pressed = has_var_cond
	condition_editor_container.add_child(has_cond_check)
	
	var fallback_check = CheckBox.new()
	fallback_check.text = "Only show when other options conditions are not met"
	fallback_check.button_pressed = is_fallback
	condition_editor_container.add_child(fallback_check)
	
	# Require Item Checkbox
	var item_check = CheckBox.new()
	item_check.text = "Inventory Requirements" 
	# Note: We keep the checkbox to toggle the entire section, but we'll adapt logic
	
	var existing_items = []
	if option_dict.get("condition"):
		var c = option_dict["condition"]
		if c.has("items"):
			existing_items = c["items"].duplicate(true)
		elif c.has("item_id"):
			# Import Legacy
			existing_items.append({ 
				"item_id": c["item_id"], 
				"amount": c.get("item_amount", 1),
				"not_has": false 
			})
	
	item_check.button_pressed = (not existing_items.is_empty())
	condition_editor_container.add_child(item_check)
	
	# Item Logic Mode
	var item_logic_row = HBoxContainer.new()
	item_logic_row.visible = item_check.button_pressed
	condition_editor_container.add_child(item_logic_row)
	
	var item_logic_lbl = Label.new()
	item_logic_lbl.text = "Logic:"
	item_logic_row.add_child(item_logic_lbl)
	
	var item_logic_opt = OptionButton.new()
	item_logic_opt.add_item("Require ALL")
	item_logic_opt.add_item("Require ANY")
	item_logic_opt.add_item("Require At Least N")
	
	# Load existing mode
	var saved_item_mode = option_dict.get("condition", {}).get("item_mode", "ALL")
	if saved_item_mode == "ALL": item_logic_opt.select(0)
	elif saved_item_mode == "ANY": item_logic_opt.select(1)
	elif saved_item_mode == "AT_LEAST": item_logic_opt.select(2)
	
	item_logic_row.add_child(item_logic_opt)
	
	var item_count_spin = SpinBox.new()
	item_count_spin.min_value = 1
	item_count_spin.visible = false # Default hidden
	item_count_spin.min_value = 1
	item_count_spin.value = int(option_dict.get("condition", {}).get("item_min_count", 1))
	item_count_spin.custom_minimum_size = Vector2(80, 0) # Ensure visibility
	item_logic_row.add_child(item_count_spin)
	
	var update_logic_ui = func(idx):
		item_count_spin.visible = (idx == 2)
	
	# Initial check
	if saved_item_mode == "AT_LEAST": update_logic_ui.call(2)
	else: update_logic_ui.call(item_logic_opt.selected)
	
	item_logic_opt.item_selected.connect(update_logic_ui)

	var item_list_container = VBoxContainer.new()
	item_list_container.visible = item_check.button_pressed
	condition_editor_container.add_child(item_list_container)
	
	var item_rows_vbox = VBoxContainer.new()
	item_list_container.add_child(item_rows_vbox)
	
	var render_items = func(items, rec_call):
		for c in item_rows_vbox.get_children(): c.queue_free()
		
		for i in range(items.size()):
			var item_data = items[i]
			var row = HBoxContainer.new()
			item_rows_vbox.add_child(row)
			
			var id_edit = LineEdit.new()
			id_edit.placeholder_text = "Item ID"
			id_edit.text = str(item_data.get("item_id", ""))
			id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			id_edit.text_changed.connect(func(t): item_data["item_id"] = t)
			row.add_child(id_edit)
			
			var amt_spin = SpinBox.new()
			amt_spin.min_value = 1
			amt_spin.value = int(item_data.get("amount", 1))
			amt_spin.tooltip_text = "Required Amount"
			amt_spin.value_changed.connect(func(v): item_data["amount"] = int(v))
			row.add_child(amt_spin)
			
			var not_chk = CheckBox.new()
			not_chk.text = "Not"
			not_chk.tooltip_text = "Check if player MUST NOT have this item"
			not_chk.button_pressed = bool(item_data.get("not_has", false))
			not_chk.toggled.connect(func(b): item_data["not_has"] = b)
			row.add_child(not_chk)
			
			var del_btn = Button.new()
			del_btn.text = "X"
			del_btn.modulate = Color(1, 0.5, 0.5)
			del_btn.pressed.connect(func():
				items.remove_at(i)
				rec_call.call(items, rec_call)
			)
			row.add_child(del_btn)

	render_items.call(existing_items, render_items)

	var add_item_btn = Button.new()
	add_item_btn.text = "+ Add Item Requirement"
	add_item_btn.pressed.connect(func():
		existing_items.append({ "item_id": "", "amount": 1, "not_has": false })
		render_items.call(existing_items, render_items)
	)
	item_list_container.add_child(add_item_btn)
	
	item_list_container.add_child(add_item_btn)
	
	# === PERSONA REQUIREMENTS SECTION ===
	var persona_check = CheckBox.new()
	persona_check.text = "Persona Requirements"
	condition_editor_container.add_child(persona_check)
	
	var persona_container = VBoxContainer.new()
	persona_container.visible = false
	condition_editor_container.add_child(persona_container)
	
	# Load existing persona conditions
	var existing_persona = {}
	if option_dict.get("condition"):
		var c = option_dict["condition"]
		if c.has("persona"):
			existing_persona = c["persona"].duplicate(true)
	
	persona_check.button_pressed = not existing_persona.is_empty()
	
	# Sex Row
	var sex_row = HBoxContainer.new()
	persona_container.add_child(sex_row)
	var sex_check = CheckBox.new()
	sex_check.text = "Sex:"
	sex_check.button_pressed = existing_persona.has("sex")
	sex_row.add_child(sex_check)
	var sex_opt = OptionButton.new()
	SettingsManager.populate_option_button(sex_opt, SettingsManager.SEX_OPTIONS)
	if existing_persona.has("sex"):
		sex_opt.select(SettingsManager.get_sex_index(existing_persona["sex"]))
	sex_row.add_child(sex_opt)
	
	# Species Row
	var species_row = HBoxContainer.new()
	persona_container.add_child(species_row)
	var species_check = CheckBox.new()
	species_check.text = "Species:"
	species_check.button_pressed = existing_persona.has("species")
	species_row.add_child(species_check)
	var species_opt = OptionButton.new()
	SettingsManager.populate_option_button(species_opt, SettingsManager.SPECIES_OPTIONS)
	if existing_persona.has("species"):
		species_opt.select(SettingsManager.get_species_index(existing_persona["species"]))
	species_row.add_child(species_opt)
	
	# Race Row
	var race_row = HBoxContainer.new()
	persona_container.add_child(race_row)
	var race_check = CheckBox.new()
	race_check.text = "Pony Race:"
	race_check.button_pressed = existing_persona.has("race")
	race_row.add_child(race_check)
	var race_opt = OptionButton.new()
	SettingsManager.populate_option_button(race_opt, SettingsManager.RACE_OPTIONS)
	if existing_persona.has("race"):
		race_opt.select(SettingsManager.get_race_index(existing_persona["race"]))
	race_row.add_child(race_opt)
	
	# Info label
	var persona_info = Label.new()
	persona_info.text = "(All checked conditions must match)"
	persona_info.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	persona_info.add_theme_font_size_override("font_size", 10)
	persona_container.add_child(persona_info)
	
	var update_persona_vis = func():
		persona_container.visible = persona_check.button_pressed
	
	persona_check.toggled.connect(func(b):
		update_persona_vis.call()
		if b:
			fallback_check.button_pressed = false
	)
	
	# Master Visibility Update
	var update_item_vis = func():
		var b = item_check.button_pressed
		item_logic_row.visible = b
		item_list_container.visible = b
		# Also update main editor box visibility logic if needed, but that's handled by fallback
	
	item_check.toggled.connect(func(b):
		update_item_vis.call()
		if b:
			fallback_check.button_pressed = false
	)
	
	var editor_box = VBoxContainer.new()
	condition_editor_container.add_child(editor_box)
	
	# Logic to ensure mutual exclusivity or simply priority
	# If fallback is checked, uncheck require variable?
	fallback_check.toggled.connect(func(b): 
		if b: 
			has_cond_check.button_pressed = false
			editor_box.visible = false
			item_check.button_pressed = false
			update_item_vis.call()
			persona_check.button_pressed = false
			update_persona_vis.call()
	)
	has_cond_check.toggled.connect(func(b): 
		if b:
			fallback_check.button_pressed = false
		editor_box.visible = b
	)
	
	# Initial state
	update_item_vis.call()
	update_persona_vis.call()
	
	editor_box.visible = has_cond_check.button_pressed
	
	editor_box.visible = has_cond_check.button_pressed
	
	# Logic Mode Selection
	var logic_mode_container = HBoxContainer.new()
	editor_box.add_child(logic_mode_container)
	var logic_lbl = Label.new()
	logic_lbl.text = "Logic:"
	logic_mode_container.add_child(logic_lbl)
	var logic_mode_opt = OptionButton.new()
	logic_mode_opt.add_item("Require ALL")
	logic_mode_opt.add_item("Require ANY")
	logic_mode_opt.add_item("Require At Least N")
	logic_mode_container.add_child(logic_mode_opt)
	
	var count_spin = SpinBox.new()
	count_spin.min_value = 1
	count_spin.visible = false
	logic_mode_container.add_child(count_spin)

	logic_mode_opt.item_selected.connect(func(idx):
		count_spin.visible = (idx == 2) # At Least N
	)

	# Conditions List
	var conditions_label = Label.new()
	conditions_label.text = "Conditions:"
	editor_box.add_child(conditions_label)
	
	var conditions_list_container = VBoxContainer.new()
	editor_box.add_child(conditions_list_container)

	# SAVE LOGIC UPDATE
	condition_dialog.confirmed.connect(func():
		var new_cond = {}
		var active = false
		
		# Fallback
		if fallback_check.button_pressed:
			new_cond["is_fallback"] = true
			active = true
		
		else:
			# Variable Check
			if has_cond_check.button_pressed:
				var conditions_list = []
				for row in conditions_list_container.get_children():
					if row.has_meta("get_data"):
						conditions_list.append(row.get_meta("get_data").call())
				
				if conditions_list.size() > 0:
					active = true
					if conditions_list.size() == 1:
						# Flatten single condition
						new_cond.merge(conditions_list[0])
					else:
						# List mode
						new_cond["list"] = conditions_list
						# Logic mode
						var logic_idx = logic_mode_opt.selected
						if logic_idx == 0: new_cond["mode"] = "ALL"
						elif logic_idx == 1: new_cond["mode"] = "ANY"
						elif logic_idx == 2:
							new_cond["mode"] = "AT_LEAST"
							new_cond["count"] = int(count_spin.value)

			# Item Check
			if item_check.button_pressed and not existing_items.is_empty():
				active = true
				# Clean up empty IDs
				var clean_items = []
				for it in existing_items:
					if it.get("item_id", "") != "":
						clean_items.append(it)
				
				if not clean_items.is_empty():
					new_cond["items"] = clean_items
					
					var i_idx = item_logic_opt.selected
					if i_idx == 0: new_cond["item_mode"] = "ALL"
					elif i_idx == 1: new_cond["item_mode"] = "ANY"
					elif i_idx == 2: 
						new_cond["item_mode"] = "AT_LEAST"
						new_cond["item_min_count"] = int(item_count_spin.value)
				else:
					# If check is pressed but no valid items, maybe we shouldn't set active?
					# Or strict fail? 
					# Let's assume user intends to configure it. 
					# But for now, if empty list, it logically passes (trivial truth) or fails?
					# If strict req: fail. 
					# Let's clean up state.
					if clean_items.is_empty():
						# If they checked the box but added no items, we ignore it?
						# Or we treat it as "Has Item Check" with empty list which might be failure?
						# Logic in EventManager: empty items list -> has_items_check=false -> returns var_check result.
						pass
			
			# Persona Check
			if persona_check.button_pressed:
				var persona_cond = {}
				if sex_check.button_pressed:
					var sex_val = SettingsManager.get_sex_id(sex_opt.selected)
					if sex_val != "":
						persona_cond["sex"] = sex_val
				if species_check.button_pressed:
					var species_val = SettingsManager.get_species_id(species_opt.selected)
					if species_val != "":
						persona_cond["species"] = species_val
				if race_check.button_pressed:
					var race_val = SettingsManager.get_race_id(race_opt.selected)
					if race_val != "":
						persona_cond["race"] = race_val
				
				if not persona_cond.is_empty():
					new_cond["persona"] = persona_cond
					active = true
		
		if active:
			option_dict["condition"] = new_cond
		else:
			option_dict.erase("condition")
			
		_mark_event_dirty(true)
		_refresh_action_list()
	)
	
	# Collect known variables from ALL events recursively
	# Collect known variables from ALL events recursively, starting with standard globals
	# Dictionary of var_name -> type_string (e.g. "int", "string")
	var known_vars_dict = {
		"current_location_id": "string",
		"day_index": "int",
		"time_slot": "int",
		"valid_rest_locations": "array"
	}
	
	var _scan_vars_recur = func(actions: Array, collector: Dictionary, self_ref):
		for act in actions:
			if act.get("type") == "set_variable":
				var v_name = act.get("var_name", "")
				var val = act.get("value")
				# Infer type from value
				var v_type = "string"
				if typeof(val) == TYPE_INT: v_type = "int"
				elif typeof(val) == TYPE_FLOAT: v_type = "float"
				elif typeof(val) == TYPE_BOOL: v_type = "bool"
				elif typeof(val) == TYPE_ARRAY: v_type = "array"
				
				if v_name != "":
					# Last defined type wins, or existing
					collector[v_name] = v_type
			elif act.get("type") == "branch":
				for opt in act.get("options", []):
					if opt.has("actions"):
						self_ref.call(opt["actions"], collector, self_ref)
	
	if event_data.has("events"):
		for ev_id in event_data["events"]:
			var ev = event_data["events"][ev_id]
			if ev.has("actions"):
				_scan_vars_recur.call(ev["actions"], known_vars_dict, _scan_vars_recur)
	
	# Extract keys for autocomplete list
	var known_vars = known_vars_dict.keys()
	known_vars.sort()
	
	# Helper to Add Condition Row
	var _add_condition_row = func(cond_data: Dictionary):
		var row = PanelContainer.new()
		conditions_list_container.add_child(row)
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.15)
		row.add_theme_stylebox_override("panel", style)
		
		var vbox = VBoxContainer.new()
		row.add_child(vbox)
		
		# Top Row: Var Selection + Remove
		var top_hbox = HBoxContainer.new()
		vbox.add_child(top_hbox)
		
		var var_edit = LineEdit.new()
		var_edit.placeholder_text = "Variable Name"
		var_edit.text = cond_data.get("var_name", "")
		var_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_hbox.add_child(var_edit)
		
		# Autocomplete Custom Popup (Panel + ItemList)
		var auto_panel = PanelContainer.new()
		auto_panel.visible = false
		auto_panel.set_as_top_level(true) # Float above everything
		auto_panel.z_index = 100 # Ensure on top
		var auto_list = ItemList.new()
		auto_list.auto_height = true
		auto_list.focus_mode = Control.FOCUS_NONE # Don't steal focus
		auto_panel.add_child(auto_list)
		# We need to add it to the scene tree. Adding to the row is fine since it's top_level.
		top_hbox.add_child(auto_panel)
		
		auto_list.item_clicked.connect(func(idx, _at_pos, _mouse_btn_idx):
			var_edit.text = auto_list.get_item_text(idx)
			auto_panel.hide()
			# var_edit.grab_focus() # Ensure focus stays
		)
		
		var_edit.text_changed.connect(func(new_text):
			if known_vars.is_empty(): return
			
			auto_list.clear()
			var match_count = 0
			for v in known_vars:
				if new_text == "" or new_text.to_lower() in v.to_lower():
					auto_list.add_item(v)
					match_count += 1
			
			if match_count > 0 and new_text != "":
				var global_pos = var_edit.get_global_position()
				var size = var_edit.get_size()
				auto_panel.position = Vector2(global_pos.x, global_pos.y + size.y)
				auto_panel.size = Vector2(size.x, 0) # Width matches, height auto
				auto_panel.show()
			else:
				auto_panel.hide()
		)
		
		# Hide when focus lost (with delay to allow clicks on the list)
		var_edit.focus_exited.connect(func():
			if not is_instance_valid(var_edit) or not var_edit.is_inside_tree(): return
			await var_edit.get_tree().create_timer(0.2).timeout
			if is_instance_valid(auto_panel):
				auto_panel.hide()
		)


		


		# Second Row: Type | Op | Value
		var bot_hbox = HBoxContainer.new()
		vbox.add_child(bot_hbox)
		
		var row_type_opt = OptionButton.new()
		for t in ["string", "int", "float", "bool", "array"]: row_type_opt.add_item(t)
		var c_type = cond_data.get("type", "string")
		var t_idx = ["string", "int", "float", "bool", "array"].find(c_type)
		if t_idx != -1: row_type_opt.select(t_idx)
		bot_hbox.add_child(row_type_opt)
		
		var row_op_opt = OptionButton.new()
		bot_hbox.add_child(row_op_opt)

		# Helper to enforce type (Must be defined after row_type_opt)
		var _enforce_var_type = func(v_name: String):
			if known_vars_dict.has(v_name):
				var required_type = known_vars_dict[v_name]
				# Find index
				var idx = -1
				for i in range(row_type_opt.get_item_count()):
					if row_type_opt.get_item_text(i) == required_type:
						idx = i
						break
				if idx != -1:
					row_type_opt.select(idx)
					row_type_opt.item_selected.emit(idx)
					row_type_opt.disabled = true # Lock it!
			else:
				row_type_opt.disabled = false # Unlock if unknown/custom

		# Update autocomplete click handler
		auto_list.item_clicked.connect(func(idx, _at_pos, _mouse_btn_idx):
			var_edit.text = auto_list.get_item_text(idx)
			auto_panel.hide()
			_enforce_var_type.call(var_edit.text)
		)

		# Check existing value on load
		if var_edit.text != "":
			_enforce_var_type.call(var_edit.text)

		# "Pick" button for known vars (keep as manual fallback)
		if not known_vars.is_empty():
			var pick_btn = MenuButton.new()
			pick_btn.text = "v"
			pick_btn.get_popup().id_pressed.connect(func(id):
				var txt = pick_btn.get_popup().get_item_text(pick_btn.get_popup().get_item_index(id))
				var_edit.text = txt
				_enforce_var_type.call(txt)
			)
			for v in known_vars:
				pick_btn.get_popup().add_item(v)
			top_hbox.add_child(pick_btn)
		
		var del_cond_btn = Button.new()
		del_cond_btn.text = "X"
		del_cond_btn.modulate = Color(1, 0.5, 0.5)
		del_cond_btn.pressed.connect(func():
			row.queue_free()
			_mark_event_dirty(true)
		)
		top_hbox.add_child(del_cond_btn)
		
		var row_val_container = HBoxContainer.new()
		row_val_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bot_hbox.add_child(row_val_container)
		
		# Row logic helpers
		var _refresh_row_input = func(t_type: String, val):
			for c in row_val_container.get_children(): c.queue_free()
			var input
			if t_type == "bool":
				input = CheckBox.new()
				input.text = "True" # Used purely for value holding
				input.button_pressed = bool(val)
			elif t_type == "int":
				input = SpinBox.new()
				input.rounded = true; input.allow_greater = true; input.allow_lesser = true
				input.value = int(val) if str(val).is_valid_float() else 0
			elif t_type == "float":
				input = SpinBox.new()
				input.step = 0.01; input.allow_greater = true; input.allow_lesser = true
				input.value = float(val) if str(val).is_valid_float() else 0.0
			elif t_type == "dictionary_kv":
				# Key + Value Input for checks like "value_equals"
				var kv_box = HBoxContainer.new()
				kv_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				input = kv_box
				
				var dict_val = val
				if typeof(dict_val) != TYPE_DICTIONARY: dict_val = {"key": "", "value": ""}
				
				var k_edit = LineEdit.new()
				k_edit.placeholder_text = "Key"
				k_edit.text = str(dict_val.get("key", ""))
				k_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				k_edit.text_changed.connect(func(t):
					dict_val["key"] = t
					cond_data["value"] = dict_val
					_mark_event_dirty(true)
				)
				kv_box.add_child(k_edit)
				
				var v_edit = LineEdit.new()
				v_edit.placeholder_text = "Value"
				v_edit.text = str(dict_val.get("value", ""))
				v_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				v_edit.text_changed.connect(func(t):
					dict_val["value"] = t
					cond_data["value"] = dict_val
					_mark_event_dirty(true)
				)
				kv_box.add_child(v_edit)
				
				# Ensure init
				cond_data["value"] = dict_val
				
			elif t_type == "array":
				var outer = VBoxContainer.new()
				input = outer
				
				# Data extraction
				var val_list = []
				var mode = "ANY"
				var count = 1
				if typeof(val) == TYPE_DICTIONARY:
					val_list = val.get("values", [])
					mode = val.get("mode", "ANY")
					count = int(val.get("count", 1))
				elif typeof(val) == TYPE_ARRAY: # Legacy simple list
					val_list = val
				else:
					if str(val) != "": val_list.append(str(val))
				
				# Mode Row
				var mode_row = HBoxContainer.new()
				outer.add_child(mode_row)
				var mode_opt = OptionButton.new()
				mode_opt.add_item("Match Any (OR)"); mode_opt.set_item_metadata(0, "ANY")
				mode_opt.add_item("Match All (AND)"); mode_opt.set_item_metadata(1, "ALL")
				mode_opt.add_item("Match At Least N"); mode_opt.set_item_metadata(2, "AT_LEAST")
				
				var m_idx = 0
				if mode == "ALL": m_idx = 1
				elif mode == "AT_LEAST": m_idx = 2
				mode_opt.select(m_idx)
				
				var row_count_spin = SpinBox.new()
				row_count_spin.value = count
				row_count_spin.visible = (mode == "AT_LEAST")
				
				mode_opt.item_selected.connect(func(idx):
					row_count_spin.visible = (idx == 2)
				)
				mode_row.add_child(mode_opt)
				mode_row.add_child(row_count_spin)
				
				# List Container
				var list_c = VBoxContainer.new()
				outer.add_child(list_c)
				
				var render_fun = func(curr, loop_ref):
					for c in list_c.get_children(): c.queue_free()
					for i in range(curr.size()):
						var r = HBoxContainer.new()
						var le = LineEdit.new()
						le.text = str(curr[i])
						le.tooltip_text = "Use {{var_name}} to insert dynamic variable values."
						le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
						r.add_child(le)
						var db = Button.new()
						db.text = "X"; db.modulate = Color(1,0.5,0.5)
						db.pressed.connect(func(): curr.remove_at(i); loop_ref.call(curr, loop_ref))
						r.add_child(db)
						list_c.add_child(r)
				
				render_fun.call(val_list, render_fun)
				
				var ab = Button.new()
				ab.text = "+ Value"
				ab.pressed.connect(func(): val_list.append(""); render_fun.call(val_list, render_fun))
				outer.add_child(ab)
				
				outer.set_meta("get_complex_value", func():
					var final = []
					for r in list_c.get_children():
						final.append(r.get_child(0).text)
					var sm = "ANY"
					if mode_opt.selected == 1: sm = "ALL"
					elif mode_opt.selected == 2: sm = "AT_LEAST"
					return { "values": final, "mode": sm, "count": int(row_count_spin.value) }
				)
			else:
				input = LineEdit.new()
				input.text = str(val)
				input.tooltip_text = "Use {{var_name}} to insert dynamic variable values."
				
			input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row_val_container.add_child(input)

		var _update_row_ops = func(t_type: String):
			row_op_opt.clear()
			var available_ops = []
			if t_type == "bool": available_ops = ["is_true", "is_false"]
			elif t_type == "string": available_ops = ["==", "!="]
			elif t_type == "array": available_ops = ["has", "does_not_have", "is_empty", "is_not_empty"]
			else: available_ops = ["==", "!=", ">", "<", ">=", "<="]
			for o in available_ops: row_op_opt.add_item(o)
			
			var cur_op = cond_data.get("operator", "==")
			# Validate
			var match_idx = -1
			for i in range(row_op_opt.get_item_count()):
				if row_op_opt.get_item_text(i) == cur_op: match_idx = i
			if match_idx != -1: row_op_opt.select(match_idx)
			else: row_op_opt.select(0)
			
			# Visibility logic helper
			var update_vis = func():
				var op = row_op_opt.get_item_text(row_op_opt.selected) if row_op_opt.selected != -1 else ""
				var needs_val = true
				if t_type == "bool": needs_val = false
				if t_type == "array" and (op == "is_empty" or op == "is_not_empty"): needs_val = false
				row_val_container.visible = needs_val
			
			update_vis.call()
			if not row_op_opt.item_selected.is_connected(update_vis):
				row_op_opt.item_selected.connect(func(_idx): update_vis.call())

		# Connections
		row_type_opt.item_selected.connect(func(idx):
			var n_type = row_type_opt.get_item_text(idx)
			_refresh_row_input.call(n_type, "")
			_update_row_ops.call(n_type)
		)

		# Init row
		_update_row_ops.call(c_type)
		_refresh_row_input.call(c_type, cond_data.get("value", ""))
		
		# Metadata for saving
		row.set_meta("get_data", func():
			var r_type = row_type_opt.get_item_text(row_type_opt.selected)
			var r_op = row_op_opt.get_item_text(row_op_opt.selected)
			var r_val
			if r_type == "bool": r_val = true # Implied
			elif r_type == "array":
				if row_val_container.get_child_count() > 0:
					var child = row_val_container.get_child(0)
					if child.has_meta("get_complex_value"):
						r_val = child.get_meta("get_complex_value").call()
					else:
						# Should not happen if UI is consistent
						r_val = {"values":[], "mode":"ANY", "count":1}
				else:
					r_val = {"values":[], "mode":"ANY", "count":1}
			else:
				var c = row_val_container.get_child(0)
				if r_type == "int": r_val = int(c.value)
				elif r_type == "float": r_val = float(c.value)
				else: r_val = c.text
			
			return {
				"var_name": var_edit.text,
				"type": r_type,
				"operator": r_op,
				"value": r_val
			}
		)

	# Load Existing Data
	var current_mode = "ALL"
	var current_count = 1
	var condition_list = []
	
	if existing != null:
		if existing.has("list"):
			current_mode = existing.get("mode", "ALL")
			current_count = int(existing.get("count", 1))
			condition_list = existing.get("list", [])
		elif existing.has("var_name") and existing["var_name"] != "":
			# Legacy single condition
			condition_list.append(existing)
	
	# Set UI to State
	if current_mode == "ALL": logic_mode_opt.select(0)
	elif current_mode == "AT_LEAST":
		if current_count == 1: logic_mode_opt.select(1) # ANY
		else: logic_mode_opt.select(2) # N
	
	count_spin.value = current_count
	count_spin.visible = (logic_mode_opt.selected == 2)
	
	for c in condition_list:
		_add_condition_row.call(c)

	# Add Button
	var add_btn = Button.new()
	add_btn.text = "+ Add Condition"
	add_btn.pressed.connect(func(): _add_condition_row.call({"var_name":"", "type":"string"}))
	editor_box.add_child(add_btn)

	# Disconnect any old signal logic not needed as we use the lambda defined earlier
	
	condition_dialog.popup_centered()

func _save_condition_multi(option_dict, check, fallback_check, logic_opt, count_spin, list_cont):
	if fallback_check.button_pressed:
		option_dict["condition"] = { "is_fallback": true }
		print("Saved Condition: Fallback/Else")
	elif not check.button_pressed:
		option_dict.erase("condition")
		print("Saved Condition: None")
	else:
		var mode_sel = logic_opt.selected
		var mode_str = "ALL"
		var req_count = 1
		
		if mode_sel == 0: mode_str = "ALL"
		elif mode_sel == 1: 
			mode_str = "AT_LEAST"
			req_count = 1 # ANY
		elif mode_sel == 2:
			mode_str = "AT_LEAST"
			req_count = int(count_spin.value)
			
		var conditions = []
		for row in list_cont.get_children():
			if row.has_meta("get_data"):
				var data = row.get_meta("get_data").call()
				# print("Row Data: ", data)
				if data["var_name"].strip_edges() != "":
					conditions.append(data)
		
		if conditions.is_empty():
			option_dict.erase("condition")
			print("Saved Condition: Empty List -> None")
		else:
			print("Saved Condition: ", conditions.size(), " items (Mode: ", mode_str, ")")
			option_dict["condition"] = {
				"mode": mode_str,
				"count": req_count,
				"list": conditions
			}
	_mark_event_dirty(true)

func _open_location_picker_for_action(target_btn: Button, action: Dictionary) -> void:
	# Hijack the schedule editor's picker machinery slightly by storing callback context
	# Reusing generic picker flow:
	_open_location_picker("_event_action_loc", target_btn)
	
	# We need to hook the confirmation. The existing _on_location_picker_confirmed checks location_picker_target
	# which we set. But we also need to update the data model 'action'.
	# We can do this by using a custom signal or just relying on the fact that target_btn.text updates.
	# But wait, we need to update action["location_id"].
	# Let's attach a signal to the button just for this moment? Or check if target_btn has a meta?
	target_btn.set_meta("linked_action", action)
	
	if not target_btn.is_connected("draw", _check_location_picker_update):
		target_btn.draw.connect(_check_location_picker_update.bind(target_btn))

func _check_location_picker_update(btn: Button) -> void:
	# Hacky polling-ish: check if text changed from what we recall? 
	# Actually, better: we modified _on_location_picker_confirmed to update text.
	# We can just iterate the property editor logic? 
	# No, let's just make sure when the button text changes, we update the model.
	# But Button doesn't emit 'text_changed'.
	
	# Alternative: We modify _on_location_picker_confirmed to emit a signal or call a wrapper.
	pass # See below for a better fix in _on_location_picker_confirmed

func _populate_character_option(opt: OptionButton, selected_id: String, append: bool = false) -> void:
	if not append:
		opt.clear()
	
	var chars = character_reference.keys()
	chars.sort()
	
	for tag in chars:
		var name = character_reference[tag]
		opt.add_item("%s (%s)" % [name, tag])
		opt.set_item_metadata(opt.get_item_count()-1, tag)
	
	for i in range(opt.get_item_count()):
		if opt.get_item_metadata(i) == selected_id:
			opt.select(i)
			return


# --- Location Picker Logic ---

func _build_location_picker() -> void:
	location_picker_dialog = ConfirmationDialog.new()
	location_picker_dialog.title = "Select Location"
	location_picker_dialog.size = Vector2(600, 400)
	add_child(location_picker_dialog)
	location_picker_dialog.confirmed.connect(_on_location_picker_confirmed)

	var content = VBoxContainer.new()
	location_picker_dialog.add_child(content)

	var search_row = HBoxContainer.new()
	content.add_child(search_row)
	var search_lbl = Label.new()
	search_lbl.text = "Search:"
	search_row.add_child(search_lbl)
	location_picker_search = LineEdit.new()
	location_picker_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	location_picker_search.placeholder_text = "Type to search..."
	location_picker_search.text_changed.connect(_on_location_picker_search_changed)
	search_row.add_child(location_picker_search)

	var split = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(split)

	# Region List
	var left = VBoxContainer.new()
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size = Vector2(150, 0)
	split.add_child(left)
	var reg_lbl = Label.new()
	reg_lbl.text = "Regions"
	left.add_child(reg_lbl)
	location_picker_region_list = ItemList.new()
	location_picker_region_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	location_picker_region_list.item_selected.connect(_on_location_picker_region_selected)
	left.add_child(location_picker_region_list)

	# Location List
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	var loc_lbl = Label.new()
	loc_lbl.text = "Locations"
	right.add_child(loc_lbl)
	location_picker_location_list = ItemList.new()
	location_picker_location_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	location_picker_location_list.item_activated.connect(_on_location_picker_items_activated)
	right.add_child(location_picker_location_list)

func _open_location_picker(slot_key: String, target_control: Object) -> void:
	location_picker_request_slot = slot_key
	location_picker_target = target_control
	location_picker_search.text = ""
	_refresh_location_picker_regions()
	location_picker_dialog.popup_centered()
	location_picker_search.grab_focus()

func _refresh_location_picker_regions() -> void:
	location_picker_region_list.clear()
	# Add "All Regions"
	location_picker_region_list.add_item("All Regions")
	
	# Extract unique regions from region_data
	# region_data is sorted, so we can just add them?
	# region_data items: {id, name, ...}
	for region in region_data:
		location_picker_region_list.add_item(region["name"])
		location_picker_region_list.set_item_metadata(location_picker_region_list.get_item_count() - 1, region["id"])
	
	location_picker_region_list.select(0)
	_filter_location_picker_list()

func _on_location_picker_region_selected(_index: int) -> void:
	_filter_location_picker_list()

func _on_location_picker_search_changed(_new_text: String) -> void:
	_filter_location_picker_list()

func _filter_location_picker_list() -> void:
	location_picker_location_list.clear()
	
	var selected_idxs = location_picker_region_list.get_selected_items()
	var region_filter = "" # empty means all
	if selected_idxs.size() > 0:
		var idx = selected_idxs[0]
		if idx > 0: # 0 is All Regions
			region_filter = location_picker_region_list.get_item_metadata(idx)
	
	var search_text = location_picker_search.text.to_lower()
	
	# Gather all matching locations
	var matches = []
	
	for region in region_data:
		# If region filter is active, skip other regions
		if region_filter != "" and region["id"] != region_filter:
			continue
			
		for loc in region["locations"]:
			# loc: {id, name, ...}
			var loc_id: String = loc["id"]
			var loc_name: String = loc.get("name", loc_id)
			
			if search_text != "":
				if not (loc_id.to_lower().contains(search_text) or loc_name.to_lower().contains(search_text)):
					continue
			
			matches.append({"id": loc_id, "name": loc_name, "region": region["name"]})
	
	# Sort alphabetically
	matches.sort_custom(func(a, b): return a["id"].casecmp_to(b["id"]) < 0)
	
	for m in matches:
		location_picker_location_list.add_item("%s (%s)" % [m["id"], m["region"]])
		location_picker_location_list.set_item_metadata(location_picker_location_list.get_item_count() - 1, m["id"])

func _on_location_picker_items_activated(_index: int) -> void:
	_on_location_picker_confirmed()
	location_picker_dialog.hide()

func _on_location_picker_confirmed() -> void:
	var selected = location_picker_location_list.get_selected_items()
	if selected.size() == 0:
		return
	
	var loc_id = location_picker_location_list.get_item_metadata(selected[0])
	
	if location_picker_target and location_picker_target is Button:
		location_picker_target.text = loc_id
		
		# Event Editor Integration:
		if location_picker_target.has_meta("linked_action"):
			var action = location_picker_target.get_meta("linked_action")
			if typeof(action) == TYPE_DICTIONARY:
				action["location_id"] = loc_id
				_mark_event_dirty(true)

# --- End Location Picker Logic ---

func _create_schedule_slot_editor(parent: VBoxContainer, slot_label: String, slot_key: String) -> void:
	# Note: We rely on the parent (Tab) to show the label, so no header here.
	
	var list_lbl = Label.new()
	list_lbl.text = "Entries (Location | Chance | Note)"
	parent.add_child(list_lbl)

	var list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(0, 100)
	list.item_selected.connect(_on_schedule_slot_item_selected.bind(slot_key))
	parent.add_child(list)

	parent.add_child(HSeparator.new())

	var edit_area = HBoxContainer.new()
	parent.add_child(edit_area)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_area.add_child(grid)

	# Location
	var loc_label = Label.new()
	loc_label.text = "Location ID:"
	grid.add_child(loc_label)
	var location_selector = Button.new()
	location_selector.text = "Select Location..."
	location_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	location_selector.alignment = HORIZONTAL_ALIGNMENT_LEFT
	location_selector.pressed.connect(func(): _open_location_picker(slot_key, location_selector))
	grid.add_child(location_selector)

	# Chance
	var chance_label = Label.new()
	chance_label.text = "Chance:"
	grid.add_child(chance_label)
	var chance_spin = SpinBox.new()
	chance_spin.min_value = 0.01
	chance_spin.max_value = 1.0
	chance_spin.step = 0.01
	chance_spin.value = 0.5
	grid.add_child(chance_spin)

	# Note
	var note_label = Label.new()
	note_label.text = "Note:"
	grid.add_child(note_label)
	var note_field = LineEdit.new()
	note_field.placeholder_text = "Optional hint"
	note_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(note_field)

	# Action Buttons (Side)
	var btn_vbox = VBoxContainer.new()
	btn_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	edit_area.add_child(btn_vbox)

	var save_button = Button.new()
	save_button.text = "Add / Update Entry"
	save_button.pressed.connect(_on_schedule_slot_save_pressed.bind(slot_key))
	btn_vbox.add_child(save_button)

	var remove_button = Button.new()
	remove_button.text = "Remove Selected"
	remove_button.pressed.connect(_on_schedule_slot_remove_pressed.bind(slot_key))
	btn_vbox.add_child(remove_button)

	schedule_slot_widgets[slot_key] = {
		"list": list,
		"location_selector": location_selector,
		"chance": chance_spin,
		"note": note_field,
		"save_button": save_button,
		"remove_button": remove_button
	}

func _load_character_reference() -> void:
	character_reference.clear()
	var character_script = load("res://scripts/CharacterManager.gd")
	if character_script == null:
		return
	var manager = character_script.new()
	if manager == null:
		return
	if manager.has_method("_load_core_characters"):
		manager._load_core_characters()
	if manager.has_method("_load_custom_characters"):
		manager._load_custom_characters()
	if manager.has_method("get_all_characters"):
		var characters: Array = manager.get_all_characters(true)
		for config in characters:
			if typeof(config) == TYPE_OBJECT:
				var tag = str(config.tag)
				var name = str(config.name)
				if tag != "":
					character_reference[tag] = name
					# extract sprites
					var sprites = config.get("sprites")
					if typeof(sprites) == TYPE_ARRAY:
						character_emotions_reference[tag] = sprites
	manager.free()
	_refresh_available_character_option()

func _load_location_reference() -> void:
	location_reference.clear()
	location_option_data.clear()
	var location_script = load("res://scripts/LocationManager.gd")
	if location_script == null:
		_refresh_location_option_menus()
		return
	var manager = location_script.new()
	if manager == null:
		_refresh_location_option_menus()
		return
	if manager.has_method("_load_locations"):
		manager._load_locations()
	var raw_locations = manager.get("locations")
	if typeof(raw_locations) == TYPE_DICTIONARY:
		for location_id in raw_locations.keys():
			var entry = raw_locations[location_id]
			var display_name: String = location_id
			if typeof(entry) == TYPE_OBJECT:
				display_name = str(entry.name)
			elif typeof(entry) == TYPE_DICTIONARY and entry.has("name"):
				display_name = str(entry["name"])
			location_reference[location_id] = display_name
			location_option_data.append({"id": location_id, "name": display_name})
	manager.free()
	location_option_data.sort_custom(Callable(self, "_sort_location_entries"))
	_refresh_location_option_menus()

func _sort_location_entries(a, b) -> bool:
	var name_a: String = str(a.get("name", ""))
	var name_b: String = str(b.get("name", ""))
	return name_a.nocasecmp_to(name_b) < 0

func _refresh_location_option_menus() -> void:
	# Deprecated: Now using popup picker
	pass

func _populate_location_option_button(selector: Object, selected_id: String = "") -> void:
	# Deprecated: Now using popup picker
	pass

func _set_location_selector_value(slot_key: String, location_id: String) -> void:
	var widgets: Dictionary = schedule_slot_widgets.get(slot_key, {})
	if widgets.is_empty():
		return
	var button = widgets.get("location_selector", null)
	if button and button is Button:
		button.text = location_id if location_id != "" else "Select Location..."

func _get_selected_location_id(slot_key: String) -> String:
	var widgets: Dictionary = schedule_slot_widgets.get(slot_key, {})
	if widgets.is_empty():
		return ""
	var button = widgets.get("location_selector", null)
	if button == null or not (button is Button):
		return ""
	if button.text == "Select Location...":
		return ""
	return button.text

func _load_schedule_editor_state() -> void:
	var raw := _read_schedule_file()
	schedule_data = raw
	schedule_lookup.clear()
	schedule_id_list.clear()
	selected_schedule_id = ""
	selected_schedule_character_tag = ""
	var schedules: Array = raw.get("schedules", [])
	for entry in schedules:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var schedule_id: String = str(entry.get("id", "")).strip_edges()
		if schedule_id == "":
			continue
		if not entry.has("name"):
			entry["name"] = schedule_id
		if not entry.has("characters") or typeof(entry["characters"]) != TYPE_DICTIONARY:
			entry["characters"] = {}
		schedule_lookup[schedule_id] = entry
		schedule_id_list.append(schedule_id)
	var preferred_id: String = str(raw.get("active_schedule_id", ""))
	if preferred_id != "" and schedule_lookup.has(preferred_id):
		selected_schedule_id = preferred_id
	elif schedule_id_list.size() > 0:
		selected_schedule_id = schedule_id_list[0]
		schedule_data["active_schedule_id"] = selected_schedule_id
	_refresh_schedule_selector()
	_refresh_schedule_character_list()
	_update_schedule_active_label()
	_mark_schedule_dirty(false)
	_set_schedule_status("Schedules loaded.")

func _read_schedule_file() -> Dictionary:
	if not FileAccess.file_exists(SCHEDULE_FILE_PATH):
		return {"active_schedule_id": "", "schedules": []}
	var file := FileAccess.open(SCHEDULE_FILE_PATH, FileAccess.READ)
	if file == null:
		return {"active_schedule_id": "", "schedules": []}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var result := json.parse(text)
	if result != OK:
		push_error("Failed to parse schedules: %s" % json.get_error_message())
		return {"active_schedule_id": "", "schedules": []}
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return {"active_schedule_id": "", "schedules": []}
	return data

func _write_schedule_file(data: Dictionary) -> bool:
	var file := FileAccess.open(SCHEDULE_FILE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Unable to write schedules to %s" % SCHEDULE_FILE_PATH)
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return true

func _refresh_schedule_selector() -> void:
	if schedule_selector == null:
		return
	schedule_selector.clear()
	for i in range(schedule_id_list.size()):
		var schedule_id: String = schedule_id_list[i]
		var schedule: Dictionary = schedule_lookup.get(schedule_id, {})
		var name: String = str(schedule.get("name", schedule_id))
		schedule_selector.add_item(name)
		schedule_selector.set_item_metadata(i, schedule_id)
	if selected_schedule_id != "":
		for i in range(schedule_selector.get_item_count()):
			if schedule_selector.get_item_metadata(i) == selected_schedule_id:
				schedule_selector.select(i)
				break
	_update_schedule_controls()

func _refresh_schedule_character_list() -> void:
	if schedule_character_list == null:
		return
	schedule_suppress_signals = true
	schedule_character_list.clear()
	var schedule = _get_current_schedule()
	if schedule.is_empty():
		_set_schedule_fields_enabled(false)
		schedule_suppress_signals = false
		return
	var characters: Dictionary = schedule.get("characters", {})
	if typeof(characters) != TYPE_DICTIONARY:
		_set_schedule_fields_enabled(false)
		schedule_suppress_signals = false
		return
	var entries: Array = []
	for tag in characters.keys():
		var char_entry: Dictionary = characters[tag]
		var display_name: String = str(char_entry.get("name", tag))
		entries.append({"tag": tag, "name": display_name})
	entries.sort_custom(Callable(self, "_sort_schedule_character_entries"))
	for entry in entries:
		var item_index := schedule_character_list.add_item("%s (%s)" % [entry["name"], entry["tag"]])
		schedule_character_list.set_item_metadata(item_index, entry["tag"])
	if entries.size() > 0:
		if selected_schedule_character_tag == "":
			selected_schedule_character_tag = entries[0]["tag"]
		var matched := false
		for i in range(schedule_character_list.get_item_count()):
			if schedule_character_list.get_item_metadata(i) == selected_schedule_character_tag:
				schedule_character_list.select(i)
				matched = true
				break
		if not matched:
			selected_schedule_character_tag = entries[0]["tag"]
			schedule_character_list.select(0)
	else:
		selected_schedule_character_tag = ""
	_set_schedule_fields_enabled(selected_schedule_character_tag != "")
	_populate_schedule_character_details()
	schedule_suppress_signals = false
	_update_schedule_controls()
	_refresh_available_character_option()

func _sort_schedule_character_entries(a, b) -> bool:
	return a["name"].nocasecmp_to(b["name"]) < 0

func _populate_schedule_character_details() -> void:
	var char_entry = _get_selected_character_entry()
	schedule_suppress_signals = true
	if char_entry.is_empty():
		if schedule_character_name_field:
			schedule_character_name_field.text = ""
		if schedule_default_location_field:
			schedule_default_location_field.text = ""
		for slot_info in SCHEDULE_TIME_SLOTS:
			_clear_schedule_slot(slot_info["key"])
		_set_schedule_fields_enabled(false)
	else:
		_set_schedule_fields_enabled(true)
		if schedule_character_name_field:
			schedule_character_name_field.text = str(char_entry.get("name", selected_schedule_character_tag))
		if schedule_default_location_field:
			schedule_default_location_field.text = str(char_entry.get("default_location", ""))
		for slot_info in SCHEDULE_TIME_SLOTS:
			var slot_key: String = slot_info["key"]
			var entries: Array = []
			if char_entry.has("time_slots") and typeof(char_entry["time_slots"]) == TYPE_DICTIONARY:
				entries = char_entry["time_slots"].get(slot_key, [])
			_populate_slot_list(slot_key, entries)
	schedule_suppress_signals = false

func _refresh_available_character_option() -> void:
	if schedule_add_character_option == null:
		return
	var schedule = _get_current_schedule()
	var used_tags := {}
	if not schedule.is_empty():
		var characters: Dictionary = schedule.get("characters", {})
		if typeof(characters) == TYPE_DICTIONARY:
			used_tags = characters
	var available: Array = []
	for tag in character_reference.keys():
		if used_tags.has(tag):
			continue
		var name: String = str(character_reference.get(tag, tag))
		available.append({"tag": tag, "name": name})
	available.sort_custom(Callable(self, "_sort_schedule_character_entries"))
	schedule_add_character_option.clear()
	schedule_add_character_option.add_item("Select character")
	schedule_add_character_option.set_item_metadata(0, "")
	var idx := 1
	for entry in available:
		var label := "%s (%s)" % [entry["name"], entry["tag"]]
		schedule_add_character_option.add_item(label)
		schedule_add_character_option.set_item_metadata(idx, entry["tag"])
		idx += 1
	if schedule_add_character_option:
		schedule_add_character_option.select(0)
		schedule_add_character_option.disabled = schedule.is_empty() or available.size() == 0
	var can_add := not schedule.is_empty() and available.size() > 0
	if schedule_add_character_button:
		schedule_add_character_button.disabled = not can_add

func _populate_slot_list(slot_key: String, entries: Array) -> void:
	var widgets: Dictionary = schedule_slot_widgets.get(slot_key, {})
	if widgets.is_empty():
		return
	var list: ItemList = widgets["list"]
	list.clear()
	for i in range(entries.size()):
		var entry = entries[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var location_id: String = str(entry.get("location_id", ""))
		var chance_value: float = float(entry.get("chance", 0.0))
		var note_text: String = str(entry.get("note", ""))
		var label: String = "%s — %.0f%%" % [location_id, chance_value * 100.0]
		if note_text != "":
			label += " — " + note_text
		var item_index := list.add_item(label)
		list.set_item_metadata(item_index, i)
	_clear_slot_inputs(slot_key)

func _clear_schedule_slot(slot_key: String) -> void:
	var widgets: Dictionary = schedule_slot_widgets.get(slot_key, {})
	if widgets.is_empty():
		return
	var list: ItemList = widgets["list"]
	list.clear()
	_clear_slot_inputs(slot_key)

func _clear_slot_inputs(slot_key: String) -> void:
	var widgets: Dictionary = schedule_slot_widgets.get(slot_key, {})
	if widgets.is_empty():
		return
	var chance_spin: SpinBox = widgets["chance"]
	if chance_spin:
		chance_spin.value = 0.5
	var note_field: LineEdit = widgets["note"]
	if note_field:
		note_field.text = ""
	var list: ItemList = widgets["list"]
	if list:
		list.deselect_all()
	_set_location_selector_value(slot_key, "")

func _set_schedule_fields_enabled(enabled: bool) -> void:
	if schedule_character_name_field:
		schedule_character_name_field.editable = enabled
	if schedule_default_location_field:
		schedule_default_location_field.editable = enabled
	for slot_key in schedule_slot_widgets.keys():
		var widgets: Dictionary = schedule_slot_widgets[slot_key]
		var list: ItemList = widgets["list"]
		if list:
			list.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		var location_selector: Button = widgets.get("location_selector", null)
		if location_selector:
			location_selector.disabled = not enabled
		var chance_spin: SpinBox = widgets["chance"]
		if chance_spin:
			chance_spin.editable = enabled
		var note_field: LineEdit = widgets["note"]
		if note_field:
			note_field.editable = enabled
		var save_button: Button = widgets["save_button"]
		if save_button:
			save_button.disabled = not enabled
		var remove_button: Button = widgets["remove_button"]
		if remove_button:
			remove_button.disabled = not enabled

func _set_schedule_status(text: String) -> void:
	if schedule_status_label:
		schedule_status_label.text = text

func _mark_schedule_dirty(is_dirty: bool) -> void:
	schedule_dirty = is_dirty
	if schedule_save_button:
		schedule_save_button.disabled = not is_dirty
	if not is_dirty:
		_set_schedule_status("Schedules loaded.")
	else:
		_set_schedule_status("Unsaved schedule changes.")

func _update_schedule_active_label() -> void:
	if schedule_active_label == null:
		return
	var active_id: String = str(schedule_data.get("active_schedule_id", ""))
	if active_id == "" or not schedule_lookup.has(active_id):
		schedule_active_label.text = "Active Schedule: (none)"
		return
	var schedule: Dictionary = schedule_lookup[active_id]
	var name: String = str(schedule.get("name", active_id))
	schedule_active_label.text = "Active Schedule: %s (%s)" % [name, active_id]

func _get_current_schedule() -> Dictionary:
	if selected_schedule_id == "" or not schedule_lookup.has(selected_schedule_id):
		return {}
	return schedule_lookup[selected_schedule_id]

func _update_schedule_controls() -> void:
	var has_schedule := selected_schedule_id != "" and schedule_lookup.has(selected_schedule_id)
	if schedule_set_active_button:
		schedule_set_active_button.disabled = not has_schedule
	if schedule_duplicate_schedule_button:
		schedule_duplicate_schedule_button.disabled = not has_schedule
	if schedule_remove_schedule_button:
		schedule_remove_schedule_button.disabled = not has_schedule or schedule_id_list.size() <= 1
	if schedule_add_missing_button:
		schedule_add_missing_button.disabled = not has_schedule
	if schedule_remove_character_button:
		schedule_remove_character_button.disabled = not has_schedule or selected_schedule_character_tag == ""
	if schedule_add_character_button:
		if not has_schedule:
			schedule_add_character_button.disabled = true
	
	if schedule_name_field:
		schedule_name_field.editable = has_schedule
		if has_schedule:
			if not schedule_name_field.has_focus():
				schedule_name_field.text = schedule_lookup[selected_schedule_id].get("name", "")
		else:
			schedule_name_field.text = ""

func _get_selected_character_entry() -> Dictionary:
	if selected_schedule_character_tag == "":
		return {}
	var schedule = _get_current_schedule()
	if schedule.is_empty():
		return {}
	var characters: Dictionary = schedule.get("characters", {})
	if typeof(characters) != TYPE_DICTIONARY:
		return {}
	return characters.get(selected_schedule_character_tag, {})

func _ensure_schedule_has_character(schedule: Dictionary, tag: String, name: String) -> void:
	if tag == "":
		return
	if not schedule.has("characters") or typeof(schedule["characters"]) != TYPE_DICTIONARY:
		schedule["characters"] = {}
	if schedule["characters"].has(tag):
		return
	var safe_name: String = name if name != "" else str(character_reference.get(tag, tag))
	schedule["characters"][tag] = {
		"tag": tag,
		"name": safe_name,
		"default_location": "",
		"time_slots": {
			"morning": [],
			"day": [],
			"night": []
		},
		"notes": {}
	}

func _ensure_slot_entries(character_entry: Dictionary, slot_key: String) -> Array:
	if not character_entry.has("time_slots") or typeof(character_entry["time_slots"]) != TYPE_DICTIONARY:
		character_entry["time_slots"] = {
			"morning": [],
			"day": [],
			"night": []
		}
	if not character_entry["time_slots"].has(slot_key):
		character_entry["time_slots"][slot_key] = []
	return character_entry["time_slots"][slot_key]

func _generate_schedule_id(prefix: String) -> String:
	var base := prefix
	if base == "":
		base = "schedule"
	var attempt := base
	var counter := 1
	while schedule_lookup.has(attempt):
		counter += 1
		attempt = "%s_%d" % [base, counter]
	return attempt

func _on_schedule_selected(index: int) -> void:
	if schedule_selector == null:
		return
	var schedule_id: String = str(schedule_selector.get_item_metadata(index))
	if schedule_id == "":
		return
	selected_schedule_id = schedule_id
	_refresh_schedule_character_list()
	_update_schedule_active_label()
	_update_schedule_controls()

func _on_schedule_reload_pressed() -> void:
	_load_location_reference()
	_load_schedule_editor_state()

func _on_schedule_save_pressed() -> void:
	var output: Dictionary = {
		"active_schedule_id": schedule_data.get("active_schedule_id", selected_schedule_id),
		"schedules": []
	}
	for schedule_id in schedule_id_list:
		if schedule_lookup.has(schedule_id):
			output["schedules"].append(schedule_lookup[schedule_id])
	if _write_schedule_file(output):
		schedule_data = output
		_mark_schedule_dirty(false)
		_set_schedule_status("Schedules saved to disk.")

func _on_schedule_set_active_pressed() -> void:
	if selected_schedule_id == "":
		return
	schedule_data["active_schedule_id"] = selected_schedule_id
	_mark_schedule_dirty(true)
	_update_schedule_active_label()
	_set_schedule_status("Active schedule set to %s." % selected_schedule_id)

func _on_schedule_add_pressed() -> void:
	var new_id := _generate_schedule_id("custom_schedule")
	var new_schedule := {
		"id": new_id,
		"name": "New Schedule",
		"characters": {}
	}
	if character_reference.keys().size() > 0:
		for tag in character_reference.keys():
			_ensure_schedule_has_character(new_schedule, tag, character_reference[tag])
	schedule_lookup[new_id] = new_schedule
	schedule_id_list.append(new_id)
	selected_schedule_id = new_id
	selected_schedule_character_tag = ""
	_refresh_schedule_selector()
	_refresh_schedule_character_list()
	_mark_schedule_dirty(true)
	_set_schedule_status("Created schedule %s." % new_id)

func _on_schedule_duplicate_pressed() -> void:
	if selected_schedule_id == "":
		return
	var original := _get_current_schedule()
	if original.is_empty():
		return
	var new_id := _generate_schedule_id(selected_schedule_id + "_copy")
	var duplicate_schedule := original.duplicate(true)
	duplicate_schedule["id"] = new_id
	var original_name: String = str(duplicate_schedule.get("name", selected_schedule_id))
	duplicate_schedule["name"] = "%s Copy" % original_name
	schedule_lookup[new_id] = duplicate_schedule
	schedule_id_list.append(new_id)
	selected_schedule_id = new_id
	selected_schedule_character_tag = ""
	_refresh_schedule_selector()
	_refresh_schedule_character_list()
	_mark_schedule_dirty(true)
	_set_schedule_status("Duplicated schedule to %s." % new_id)

func _on_schedule_remove_pressed() -> void:
	if selected_schedule_id == "" or schedule_id_list.size() <= 1:
		_set_schedule_status("At least one schedule must remain.")
		return
	schedule_lookup.erase(selected_schedule_id)
	schedule_id_list.erase(selected_schedule_id)
	if schedule_data.get("active_schedule_id", "") == selected_schedule_id:
		var replacement := schedule_id_list[0] if schedule_id_list.size() > 0 else ""
		schedule_data["active_schedule_id"] = replacement
	selected_schedule_id = schedule_id_list[0] if schedule_id_list.size() > 0 else ""
	selected_schedule_character_tag = ""
	_refresh_schedule_selector()
	_refresh_schedule_character_list()
	_update_schedule_active_label()
	_mark_schedule_dirty(true)
	_set_schedule_status("Removed schedule.")

func _on_schedule_name_changed(new_text: String) -> void:
	if selected_schedule_id == "" or not schedule_lookup.has(selected_schedule_id):
		return
	schedule_lookup[selected_schedule_id]["name"] = new_text
	_mark_schedule_dirty(true)

func _on_schedule_name_submitted(_new_text: String) -> void:
	_refresh_schedule_selector()


func _on_schedule_character_selected(index: int) -> void:
	if schedule_suppress_signals:
		return
	if schedule_character_list == null:
		return
	selected_schedule_character_tag = str(schedule_character_list.get_item_metadata(index))
	_populate_schedule_character_details()

func _on_schedule_add_missing_pressed() -> void:
	var schedule = _get_current_schedule()
	if schedule.is_empty():
		return
	var added := 0
	for tag in character_reference.keys():
		if not schedule["characters"].has(tag):
			_ensure_schedule_has_character(schedule, tag, character_reference[tag])
			added += 1
	if added > 0:
		_mark_schedule_dirty(true)
		_set_schedule_status("Added %d missing character(s)." % added)
	_refresh_schedule_character_list()

func _on_schedule_remove_character_pressed() -> void:
	var schedule = _get_current_schedule()
	if schedule.is_empty() or selected_schedule_character_tag == "":
		return
	var characters: Dictionary = schedule.get("characters", {})
	if not characters.has(selected_schedule_character_tag):
		return
	characters.erase(selected_schedule_character_tag)
	selected_schedule_character_tag = ""
	_refresh_schedule_character_list()
	_mark_schedule_dirty(true)
	_set_schedule_status("Removed character from schedule.")

func _on_schedule_add_character_pressed() -> void:
	if schedule_add_character_option == null:
		return
	var selected_tag: String = str(schedule_add_character_option.get_selected_metadata())
	if selected_tag == "":
		_set_schedule_status("Select a character to add.")
		return
	var schedule = _get_current_schedule()
	if schedule.is_empty():
		return
	var characters: Dictionary = schedule.get("characters", {})
	if characters.has(selected_tag):
		_set_schedule_status("Character already in schedule.")
		return
	var display_name: String = str(character_reference.get(selected_tag, selected_tag))
	_ensure_schedule_has_character(schedule, selected_tag, display_name)
	selected_schedule_character_tag = selected_tag
	_refresh_schedule_character_list()
	_refresh_available_character_option()
	if schedule_add_character_option:
		schedule_add_character_option.select(0)
	_mark_schedule_dirty(true)
	_set_schedule_status("Added character %s." % selected_tag)

func _on_schedule_char_name_changed(new_text: String) -> void:
	if schedule_suppress_signals:
		return
	var char_entry = _get_selected_character_entry()
	if char_entry.is_empty():
		return
	char_entry["name"] = new_text
	_refresh_schedule_character_list()
	_mark_schedule_dirty(true)

func _on_schedule_char_default_changed(new_text: String) -> void:
	if schedule_suppress_signals:
		return
	var char_entry = _get_selected_character_entry()
	if char_entry.is_empty():
		return
	char_entry["default_location"] = new_text.strip_edges()
	_mark_schedule_dirty(true)

func _on_schedule_slot_item_selected(index: int, slot_key: String) -> void:
	if schedule_suppress_signals:
		return
	var widgets: Dictionary = schedule_slot_widgets.get(slot_key, {})
	if widgets.is_empty():
		return
	var list: ItemList = widgets["list"]
	var entry_index: int = int(list.get_item_metadata(index))
	var char_entry = _get_selected_character_entry()
	if char_entry.is_empty():
		return
	var slot_entries: Array = _ensure_slot_entries(char_entry, slot_key)
	if entry_index < 0 or entry_index >= slot_entries.size():
		return
	var entry: Dictionary = slot_entries[entry_index]
	var chance_spin: SpinBox = widgets["chance"]
	var note_field: LineEdit = widgets["note"]
	var loc_id: String = str(entry.get("location_id", ""))
	_set_location_selector_value(slot_key, loc_id)
	chance_spin.value = float(entry.get("chance", 0.5))
	note_field.text = str(entry.get("note", ""))

func _on_schedule_slot_save_pressed(slot_key: String) -> void:
	var char_entry = _get_selected_character_entry()
	if char_entry.is_empty():
		return
	var widgets: Dictionary = schedule_slot_widgets.get(slot_key, {})
	if widgets.is_empty():
		return
	var chance_spin: SpinBox = widgets["chance"]
	var note_field: LineEdit = widgets["note"]
	var location_id: String = _get_selected_location_id(slot_key)
	if location_id == "":
		_set_schedule_status("Location ID is required.")
		return
	var chance_value: float = float(chance_spin.value)
	chance_value = clampf(chance_value, 0.01, 1.0)
	var slot_entries: Array = _ensure_slot_entries(char_entry, slot_key)
	var list: ItemList = widgets["list"]
	var new_entry: Dictionary = {
		"location_id": location_id,
		"chance": chance_value
	}
	var note_text: String = note_field.text.strip_edges()
	if note_text != "":
		new_entry["note"] = note_text
	var selected_indices := list.get_selected_items()
	if selected_indices.size() > 0:
		var idx: int = int(list.get_item_metadata(selected_indices[0]))
		if idx >= 0 and idx < slot_entries.size():
			slot_entries[idx] = new_entry
	else:
		slot_entries.append(new_entry)
	_populate_slot_list(slot_key, slot_entries)
	_mark_schedule_dirty(true)
	_set_schedule_status("Updated %s slot for %s." % [slot_key, selected_schedule_character_tag])

func _on_schedule_slot_remove_pressed(slot_key: String) -> void:
	var char_entry = _get_selected_character_entry()
	if char_entry.is_empty():
		return
	var widgets: Dictionary = schedule_slot_widgets.get(slot_key, {})
	if widgets.is_empty():
		return
	var list: ItemList = widgets["list"]
	var selected_indices := list.get_selected_items()
	if selected_indices.size() == 0:
		return
	var slot_entries: Array = _ensure_slot_entries(char_entry, slot_key)
	selected_indices.sort()
	for i in range(selected_indices.size() - 1, -1, -1):
		var idx: int = int(list.get_item_metadata(selected_indices[i]))
		if idx >= 0 and idx < slot_entries.size():
			slot_entries.remove_at(idx)
	_populate_slot_list(slot_key, slot_entries)
	_mark_schedule_dirty(true)
	_set_schedule_status("Removed %s slot entries." % slot_key)

func _create_spinbox(label_text: String, parent: GridContainer) -> SpinBox:
	var label = Label.new()
	label.text = label_text + ":"
	parent.add_child(label)
	var spin = SpinBox.new()
	spin.min_value = 0.0
	spin.max_value = 1.0
	spin.step = 0.001
	spin.custom_minimum_size = Vector2(120, 0)
	spin.value_changed.connect(_on_rect_field_changed.bind(label_text.to_lower()))
	parent.add_child(spin)
	return spin

func _on_reload_pressed():
	_load_all_data()

func _load_all_data():
	var previous_region = current_region_id
	var previous_location = current_location_entry["id"] if current_location_entry else ""
	current_location_entry = null
	current_region_id = ""
	map_canvas.clear_all()
	region_data.clear()
	region_lookup.clear()
	map_lookup = _scan_map_textures()
	dirty_lookup.clear()
	for root_path in LOCATION_ROOTS:
		_scan_location_root(root_path)
	region_data.sort_custom(Callable(self, "_sort_regions"))
	_load_neighbor_graph()
	_populate_region_option(previous_region, previous_location)
	_populate_neighbor_editor_regions()
	_load_character_reference()
	_load_location_reference()
	_load_schedule_editor_state()
	_load_sprite_size_editor_state()
	_load_event_data()
	save_button.disabled = dirty_lookup.is_empty()
	save_button.disabled = dirty_lookup.is_empty()
	neighbor_save_button.disabled = not neighbor_graph_dirty
	_set_status("Loaded %d region(s)." % region_data.size())

func _populate_neighbor_editor_regions():
	if not neighbor_region_option:
		return

	neighbor_region_option.clear()
	for i in range(region_data.size()):
		var region = region_data[i]
		neighbor_region_option.add_item(region["name"])
		neighbor_region_option.set_item_metadata(i, region["id"])

	if not region_data.is_empty():
		neighbor_region_option.select(0)
		_neighbor_select_region(String(neighbor_region_option.get_item_metadata(0)))

func _scan_map_textures() -> Dictionary:
	var lookup := {}
	var dir = DirAccess.open(MAPS_PATH)
	if dir:
		dir.list_dir_begin()
		var entry = dir.get_next()
		while entry != "":
			if not dir.current_is_dir() and not entry.begins_with("."):
				var ext = entry.get_extension().to_lower()
				if ext in IMAGE_EXTS:
					var base = entry.get_basename()
					var normalized = _normalize_map_id(base)
					lookup[normalized] = MAPS_PATH + "/" + entry
			entry = dir.get_next()
		dir.list_dir_end()
	else:
		push_warning("Map directory not found at %s" % MAPS_PATH)
	return lookup

func _scan_location_root(root_path: String):
	var dir = DirAccess.open(root_path)
	if not dir:
		push_warning("Location root missing: %s" % root_path)
		return
	dir.list_dir_begin()
	var region_id = dir.get_next()
	while region_id != "":
		if dir.current_is_dir() and not region_id.begins_with("."):
			_scan_region(root_path, region_id)
		region_id = dir.get_next()
	dir.list_dir_end()

func _scan_region(root_path: String, region_id: String):
	var region_path = _join_paths(root_path, region_id)
	var dir = DirAccess.open(region_path)
	if not dir:
		return
	var region_entry = _ensure_region_entry(region_id)
	dir.list_dir_begin()
	var location_id = dir.get_next()
	while location_id != "":
		if dir.current_is_dir() and not location_id.begins_with("."):
			var entry = _build_location_entry(region_entry, _join_paths(region_path, location_id), location_id)
			if entry:
				region_entry["locations"].append(entry)
				region_entry["location_lookup"][entry["id"]] = entry
		location_id = dir.get_next()
	dir.list_dir_end()
	region_entry["locations"].sort_custom(Callable(self, "_sort_locations"))

func _ensure_region_entry(region_id: String) -> Dictionary:
	if region_lookup.has(region_id):
		return region_lookup[region_id]
	var display_name = _format_region_name(region_id)
	var normalized = _normalize_map_id(region_id)
	var texture_path = _find_map_path(normalized)
	var entry = {
		"id": region_id,
		"name": display_name,
		"map_id": normalized,
		"map_texture_path": texture_path,
		"locations": [],
		"location_lookup": {}
	}
	region_lookup[region_id] = entry
	region_data.append(entry)
	return entry

func _find_map_path(normalized_id: String) -> String:
	if map_lookup.has(normalized_id):
		return map_lookup[normalized_id]
	return ""

func _build_location_entry(region_entry: Dictionary, folder_path: String, location_id: String):
	var short_label = _format_location_name(location_id)
	var entry := {
		"id": location_id,
		"name": short_label,
		"label_name": short_label,
		"region_id": region_entry["id"],
		"region_name": region_entry["name"],
		"folder_path": folder_path,
		"json_path": folder_path + "/location.json",
		"json_data": {},
		"pos_rect": Rect2(),
		"has_pointer": false,
		"dirty": false
	}
	entry["dirty_key"] = "%s::%s" % [entry["region_id"], entry["id"]]
	if FileAccess.file_exists(entry["json_path"]):
		var file = FileAccess.open(entry["json_path"], FileAccess.READ)
		if file:
			var text = file.get_as_text()
			file.close()
			var json = JSON.new()
			if json.parse(text) == OK:
				var data = json.get_data()
				if typeof(data) == TYPE_DICTIONARY:
					entry["json_data"] = data
					if data.has("name") and typeof(data["name"]) == TYPE_STRING and data["name"].strip_edges() != "":
						entry["name"] = data["name"]
					if data.has("pos"):
						var rect = _rect_from_value(data["pos"])
						if rect.size != Vector2.ZERO:
							entry["pos_rect"] = rect
							entry["has_pointer"] = true
			else:
				push_warning("Invalid JSON in %s" % entry["json_path"])
	else:
		entry["json_data"] = {}
	return entry

func _rect_from_value(value) -> Rect2:
	if typeof(value) == TYPE_ARRAY and value.size() >= 4:
		return Rect2(Vector2(float(value[0]), float(value[1])), Vector2(float(value[2]), float(value[3])))
	return Rect2()

func _populate_region_option(prefer_region: String, prefer_location: String):
	region_option.clear()
	for i in range(region_data.size()):
		var region = region_data[i]
		region_option.add_item(region["name"])
		region_option.set_item_metadata(i, region["id"])
	if region_data.is_empty():
		location_list.clear()
		map_canvas.clear_all()
		location_label.text = "No location selected"
		return
	var target_index := 0
	if prefer_region != "":
		for i in range(region_data.size()):
			if region_data[i]["id"] == prefer_region:
				target_index = i
				break
	region_option.select(target_index)
	_select_region(String(region_option.get_item_metadata(target_index)), prefer_location)

func _select_region(region_id: String, prefer_location: String = ""):
	if not region_lookup.has(region_id):
		return
	current_region_id = region_id
	var region = region_lookup[region_id]
	var texture: Texture2D = null
	var tex_path = region.get("map_texture_path", "")
	if tex_path != "":
		texture = ResourceLoader.load(tex_path)
	map_canvas.set_map_texture(texture)
	var pointer_dict := {}
	var label_dict := {}
	for loc in region["locations"]:
		label_dict[loc["id"]] = _get_entry_label(loc)
		if loc["has_pointer"]:
			pointer_dict[loc["id"]] = loc["pos_rect"]
	map_canvas.set_pointer_dataset(pointer_dict, label_dict)
	_refresh_location_list(prefer_location)

func _refresh_location_list(prefer_location: String = ""):
	location_list.clear()
	if current_region_id == "" or not region_lookup.has(current_region_id):
		return
	var current_region = region_lookup[current_region_id]
	var show_all = show_all_regions_checkbox and show_all_regions_checkbox.button_pressed
	
	# Build the list of locations to display
	var locations_to_show: Array = []
	if show_all:
		# Show all locations from all regions, grouped by region
		for region in region_data:
			for loc in region["locations"]:
				locations_to_show.append(loc)
	else:
		# Show only locations from current region
		locations_to_show = current_region["locations"]
	
	var selected_id = prefer_location
	if selected_id == "" and current_location_entry:
		selected_id = current_location_entry["id"]
	if selected_id == "" and not locations_to_show.is_empty():
		selected_id = locations_to_show[0]["id"]
	_setting_fields = true
	for loc in locations_to_show:
		var label = _get_entry_label(loc)
		# Add region prefix when showing all regions and location is from different region
		if show_all and loc["region_id"] != current_region_id:
			label = "[%s] %s" % [loc["region_name"], label]
		if not loc["has_pointer"]:
			label += " (no pointer)"
		if loc["dirty"]:
			label = "* " + label
		var index = location_list.add_item(label)
		location_list.set_item_tooltip(index, _build_location_tooltip(loc))
		if not loc["has_pointer"]:
			location_list.set_item_custom_fg_color(index, Color(1.0, 0.6, 0.2))
		# For cross-region locations, use a different color to indicate they're from another region
		elif show_all and loc["region_id"] != current_region_id:
			location_list.set_item_custom_fg_color(index, Color(0.6, 0.8, 1.0))
		location_list.set_item_metadata(index, loc["id"])
		if selected_id != "" and loc["id"] == selected_id:
			_select_location_by_index(index)
	_setting_fields = false
	if selected_id == "":
		current_location_entry = null
		location_label.text = "No location selected"
		remove_button.disabled = true
		map_canvas.set_selected_location("")
		_set_rect_fields_enabled(false)

func _select_location_by_index(index: int):
	if index < 0 or index >= location_list.get_item_count():
		return
	_suppress_list_signal = true
	location_list.select(index)
	location_list.ensure_current_is_visible()
	var loc_id = String(location_list.get_item_metadata(index))
	_focus_location(loc_id)
	_suppress_list_signal = false

func _on_region_selected(index: int):
	var region_id = String(region_option.get_item_metadata(index))
	_select_region(region_id)

func _on_show_all_regions_toggled(_pressed: bool):
	# Refresh the location list to show/hide locations from other regions
	var current_loc_id = current_location_entry["id"] if current_location_entry else ""
	_refresh_location_list(current_loc_id)

func _on_location_selected(index: int):
	if _suppress_list_signal:
		return
	if index < 0 or index >= location_list.get_item_count():
		return
	var loc_id = String(location_list.get_item_metadata(index))
	_focus_location(loc_id)

func _focus_location(loc_id: String):
	if current_region_id == "":
		return
	
	# First try to find in current region
	var region = region_lookup[current_region_id]
	if region["location_lookup"].has(loc_id):
		current_location_entry = region["location_lookup"][loc_id]
	else:
		# If showing all regions, search in all regions
		var show_all = show_all_regions_checkbox and show_all_regions_checkbox.button_pressed
		if show_all:
			current_location_entry = _find_location_by_id(loc_id)
		else:
			return
	
	if current_location_entry == null:
		return
	
	var label_text = _get_entry_label(current_location_entry)
	# Add region info if from different region
	var is_cross_region = current_location_entry["region_id"] != current_region_id
	if is_cross_region:
		label_text = "%s [%s] (from %s)" % [label_text, current_location_entry["id"], current_location_entry["region_name"]]
		# For cross-region locations, add the label to the canvas so it can be placed/displayed
		map_canvas.set_label_for_location(current_location_entry["id"], _get_entry_label(current_location_entry))
		# If it already has a pointer, add that to the canvas too
		if current_location_entry["has_pointer"]:
			map_canvas.update_pointer_rect(current_location_entry["id"], current_location_entry["pos_rect"])
	else:
		label_text = "%s [%s]" % [label_text, current_location_entry["id"]]
	location_label.text = label_text
	map_canvas.set_selected_location(current_location_entry["id"])
	_update_rect_fields()

func _update_rect_fields():
	_setting_fields = true
	var has_pointer = current_location_entry and current_location_entry["has_pointer"]
	pos_fields["x"].editable = has_pointer
	pos_fields["y"].editable = has_pointer
	pos_fields["w"].editable = true
	pos_fields["h"].editable = true
	if has_pointer:
		pos_fields["x"].value = current_location_entry["pos_rect"].position.x
		pos_fields["y"].value = current_location_entry["pos_rect"].position.y
		pos_fields["w"].value = current_location_entry["pos_rect"].size.x
		pos_fields["h"].value = current_location_entry["pos_rect"].size.y
	else:
		pos_fields["x"].value = 0.0
		pos_fields["y"].value = 0.0
		pos_fields["w"].value = _pending_marker_size.x
		pos_fields["h"].value = _pending_marker_size.y
	remove_button.disabled = not has_pointer
	_setting_fields = false
	_update_marker_size_from_fields()

func _on_rect_field_changed(value: float, field_key: String):
	if _setting_fields:
		return
	if not current_location_entry:
		return
	if field_key in ["width", "height"]:
		_pending_marker_size = Vector2(pos_fields["w"].value, pos_fields["h"].value)
		_update_marker_size_from_fields()
		if not current_location_entry["has_pointer"]:
			return
	if not current_location_entry["has_pointer"]:
		return
	var rect: Rect2 = current_location_entry["pos_rect"]
	match field_key:
		"x":
			rect.position.x = clampf(pos_fields["x"].value, 0.0, 1.0 - rect.size.x)
		"y":
			rect.position.y = clampf(pos_fields["y"].value, 0.0, 1.0 - rect.size.y)
		"width":
			var new_w = clampf(pos_fields["w"].value, 0.01, 1.0)
			new_w = min(new_w, 1.0 - rect.position.x)
			rect.size.x = new_w
		"height":
			var new_h = clampf(pos_fields["h"].value, 0.01, 1.0)
			new_h = min(new_h, 1.0 - rect.position.y)
			rect.size.y = new_h
	current_location_entry["pos_rect"] = rect
	current_location_entry["has_pointer"] = true
	pos_fields["x"].value = rect.position.x
	pos_fields["y"].value = rect.position.y
	pos_fields["w"].value = rect.size.x
	pos_fields["h"].value = rect.size.y
	_mark_location_dirty(current_location_entry)
	map_canvas.update_pointer_rect(current_location_entry["id"], rect)
	_set_status("Pointer updated for %s." % _get_entry_label(current_location_entry))

func _update_marker_size_from_fields():
	map_canvas.set_default_marker_size(Vector2(
		max(0.005, pos_fields["w"].value),
		max(0.005, pos_fields["h"].value)
	))

func _on_remove_pressed():
	if not current_location_entry or not current_location_entry["has_pointer"]:
		_set_status("No pointer to remove.")
		return
	current_location_entry["has_pointer"] = false
	current_location_entry["pos_rect"] = Rect2()
	_mark_location_dirty(current_location_entry)
	map_canvas.remove_pointer(current_location_entry["id"])
	_update_rect_fields()
	_refresh_location_list(current_location_entry["id"])
	_set_status("Pointer removed for %s." % _get_entry_label(current_location_entry))

func _mark_location_dirty(entry: Dictionary):
	entry["dirty"] = true
	dirty_lookup[entry["dirty_key"]] = entry
	save_button.disabled = false
	_refresh_location_list(entry["id"])

func _on_save_pressed():
	if dirty_lookup.is_empty():
		_set_status("Nothing to save.")
		return
	var failed := []
	var remaining := {}
	for entry in dirty_lookup.values():
		if _write_location_entry(entry):
			continue
		failed.append(entry["id"])
		remaining[entry["dirty_key"]] = entry
	dirty_lookup = remaining
	if failed.is_empty():
		_set_status("Saved all pointer changes.")
	else:
		_set_status("Failed to save: %s" % ", ".join(failed))
	_refresh_location_list(current_location_entry["id"] if current_location_entry else "")
	save_button.disabled = dirty_lookup.is_empty()

func _write_location_entry(entry: Dictionary) -> bool:
	var data: Dictionary = entry["json_data"] if entry["json_data"] else {}
	data = data.duplicate(true)
	if entry["has_pointer"]:
		data["pos"] = [
			_round(entry["pos_rect"].position.x),
			_round(entry["pos_rect"].position.y),
			_round(entry["pos_rect"].size.x),
			_round(entry["pos_rect"].size.y)
		]
	else:
		data.erase("pos")
	var file = FileAccess.open(entry["json_path"], FileAccess.WRITE)
	if file == null:
		push_error("Unable to write file %s" % entry["json_path"])
		return false
	file.store_string(JSON.stringify(data, "  ") + "\n")
	file.close()
	entry["json_data"] = data
	entry["dirty"] = false
	return true

func _round(value: float, decimals: int = 4) -> float:
	var mult = pow(10.0, decimals)
	return round(value * mult) / mult

func _set_status(text: String):
	status_label.text = text

# Load neighbor graph from centralized file
func _load_neighbor_graph():
	neighbor_graph.clear()
	neighbor_graph_dirty = false

	var file_path = NEIGHBOR_GRAPH_PATH
	if not FileAccess.file_exists(file_path):
		print("Neighbor graph file not found, starting with empty graph")
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_warning("Could not open neighbor graph file: %s" % file_path)
		return

	var content = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(content)
	if parse_result != OK:
		push_warning("Failed to parse neighbor graph JSON")
		return

	var data = json.data
	if typeof(data) == TYPE_DICTIONARY and data.has("neighbors"):
		neighbor_graph = data["neighbors"].duplicate(true)
		print("Loaded neighbor graph with %d locations" % neighbor_graph.size())

# Save neighbor graph to centralized file
func _save_neighbor_graph() -> bool:
	var data = {
		"neighbors": neighbor_graph
	}

	var file = FileAccess.open(NEIGHBOR_GRAPH_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Unable to write neighbor graph file: %s" % NEIGHBOR_GRAPH_PATH)
		return false

	file.store_string(JSON.stringify(data, "  ") + "\n")
	file.close()
	neighbor_graph_dirty = false
	print("Saved neighbor graph with %d locations" % neighbor_graph.size())
	return true

func _on_canvas_pointer_clicked(loc_id: String):
	_select_list_item_by_id(loc_id)

func _select_list_item_by_id(loc_id: String):
	for index in range(location_list.get_item_count()):
		if String(location_list.get_item_metadata(index)) == loc_id:
			_select_location_by_index(index)
			break

func _on_canvas_rect_changed(loc_id: String, rect: Rect2):
	if current_region_id == "":
		return
	
	# Find the location entry - check current region first, then all regions
	var entry = null
	var region = region_lookup[current_region_id]
	if region["location_lookup"].has(loc_id):
		entry = region["location_lookup"][loc_id]
	else:
		# For cross-region locations, search all regions
		entry = _find_location_by_id(loc_id)
	
	if entry == null:
		return
	
	entry["pos_rect"] = Rect2(rect.position, rect.size)
	entry["has_pointer"] = true
	_mark_location_dirty(entry)
	if current_location_entry == entry:
		_update_rect_fields()

func _on_canvas_pointer_created(loc_id: String, rect: Rect2):
	_on_canvas_rect_changed(loc_id, rect)
	_select_list_item_by_id(loc_id)
	
	# Find the entry - check current region first, then all regions
	var entry = null
	var region = region_lookup[current_region_id]
	if region["location_lookup"].has(loc_id):
		entry = region["location_lookup"][loc_id]
	else:
		entry = _find_location_by_id(loc_id)
	
	if entry:
		_set_status("Pointer created for %s." % _get_entry_label(entry))

func _format_region_name(region_id: String) -> String:
	return _title_from_token(region_id)

func _format_location_name(location_id: String) -> String:
	return _title_from_token(location_id)

func _title_from_token(text: String) -> String:
	var cleaned = text.replace("_", " ").strip_edges()
	if cleaned == "":
		return text
	var parts = cleaned.split(" ", false)
	for i in range(parts.size()):
		var part = parts[i]
		if part.length() == 0:
			continue
		parts[i] = part.substr(0, 1).to_upper() + part.substr(1).to_lower()
	return " ".join(parts)

func _normalize_map_id(text: String) -> String:
	return text.to_lower().replace(" ", "_").replace("_map", "")

func _get_entry_label(entry: Dictionary) -> String:
	if entry.has("label_name") and String(entry["label_name"]).strip_edges() != "":
		return entry["label_name"]
	if entry.has("name") and String(entry["name"]).strip_edges() != "":
		return entry["name"]
	return entry.get("id", "Unknown")

func _build_location_tooltip(entry: Dictionary) -> String:
	var tooltip := ""
	var description = String(entry.get("name", ""))
	if description.strip_edges() != "" and description != _get_entry_label(entry):
		tooltip += description.strip_edges()
	if tooltip != "":
		tooltip += "\n"
	tooltip += "ID: %s" % entry.get("id", "unknown")
	return tooltip

func _join_paths(base: String, child: String) -> String:
	return base + child if base.ends_with("/") else base + "/" + child

func _sort_regions(a, b):
	return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0

func _sort_locations(a, b):
	return String(_get_entry_label(a)).naturalnocasecmp_to(String(_get_entry_label(b))) < 0

func _set_rect_fields_enabled(enabled: bool):
	pos_fields["x"].editable = enabled
	pos_fields["y"].editable = enabled
	pos_fields["w"].editable = enabled
	pos_fields["h"].editable = enabled
# Neighbor Editor Functions for GameDataDock
# Add these to the end of game_data_dock.gd

func _on_neighbor_region_selected(index: int):
	var region_id = String(neighbor_region_option.get_item_metadata(index))
	_neighbor_select_region(region_id)

func _neighbor_select_region(region_id: String):
	if not region_lookup.has(region_id):
		return

	current_region_id = region_id  # Set this so _neighbor_focus_location works
	neighbor_location_list.clear()
	var region = region_lookup[region_id]

	for loc in region["locations"]:
		var index = neighbor_location_list.add_item(loc["name"])
		neighbor_location_list.set_item_metadata(index, loc["id"])

	neighbor_current_location = null
	neighbor_list.clear()
	neighbor_available_list.clear()
	neighbor_status_label.text = "Select a location to edit its neighbors"

func _on_neighbor_location_selected(index: int):
	var loc_id = String(neighbor_location_list.get_item_metadata(index))
	_neighbor_focus_location(loc_id)

func _neighbor_focus_location(loc_id: String):
	if current_region_id == "" or not region_lookup.has(current_region_id):
		return

	var region = region_lookup[current_region_id]
	if not region["location_lookup"].has(loc_id):
		return

	neighbor_current_location = region["location_lookup"][loc_id]

	# Neighbors are now stored in centralized neighbor_graph
	if not neighbor_graph.has(loc_id):
		neighbor_graph[loc_id] = []

	_refresh_neighbor_lists()
	neighbor_status_label.text = "Editing neighbors for: %s" % neighbor_current_location["name"]

func _refresh_neighbor_lists():
	if not neighbor_current_location:
		return

	var loc_id = neighbor_current_location["id"]
	var neighbors_array = neighbor_graph.get(loc_id, [])

	# Populate current neighbors list
	neighbor_list.clear()
	for neighbor_id in neighbors_array:
		# Find the neighbor location to get its display name
		var neighbor_entry = _find_location_by_id(neighbor_id)
		var display_name = neighbor_entry["name"] if neighbor_entry else neighbor_id
		var index = neighbor_list.add_item(display_name)
		neighbor_list.set_item_metadata(index, neighbor_id)

	neighbor_remove_button.disabled = neighbors_array.is_empty()

	# Get search filter text
	var search_text = ""
	if neighbor_search_field:
		search_text = neighbor_search_field.text.strip_edges().to_lower()

	# Populate available locations list (all locations from all regions)
	neighbor_available_list.clear()
	for region in region_data:
		for loc in region["locations"]:
			# Skip the current location (can't be neighbor with itself)
			if loc["id"] == loc_id:
				continue
			# Filter by search text (prefix match, case-insensitive)
			if search_text != "" and not loc["name"].to_lower().begins_with(search_text):
				continue
			# Show location with region prefix for clarity
			var display_name = "%s (%s)" % [loc["name"], region["name"]]
			var index = neighbor_available_list.add_item(display_name)
			neighbor_available_list.set_item_metadata(index, loc["id"])
			# Highlight if already a neighbor
			if loc["id"] in neighbors_array:
				neighbor_available_list.set_item_custom_fg_color(index, Color(0.5, 1.0, 0.5))

func _on_neighbor_search_changed(_new_text: String):
	# Refresh the available locations list with the new search filter
	_refresh_neighbor_lists()

func _find_location_by_id(loc_id: String):
	# Search all regions for this location
	for region in region_data:
		if region["location_lookup"].has(loc_id):
			return region["location_lookup"][loc_id]
	return null

func _on_neighbor_add_location_multi_selected(_index: int, _selected: bool):
	# Called when multi-select mode changes selection
	_update_neighbor_add_button()

func _on_neighbor_add_location_selected(_index: int):
	# Called when single item selected
	_update_neighbor_add_button()

func _update_neighbor_add_button():
	# Enable add button when items are selected
	var selected = neighbor_available_list.get_selected_items()
	print("DEBUG: Available list selection changed, selected count: ", selected.size())
	neighbor_add_button.disabled = selected.is_empty()
	print("DEBUG: Add button disabled: ", neighbor_add_button.disabled)

func _on_neighbor_add_pressed():
	print("DEBUG: Add neighbor button pressed")
	if not neighbor_current_location:
		print("DEBUG: No current location selected")
		neighbor_status_label.text = "Error: No location selected"
		return

	var selected_indices = neighbor_available_list.get_selected_items()
	print("DEBUG: Selected indices: ", selected_indices)
	if selected_indices.is_empty():
		neighbor_status_label.text = "Error: No locations selected to add"
		return

	var current_loc_id = neighbor_current_location["id"]
	var neighbors_array = neighbor_graph.get(current_loc_id, []).duplicate()
	print("DEBUG: Current neighbors: ", neighbors_array)
	var added_count = 0
	var reciprocal_count = 0

	for index in selected_indices:
		var loc_id = String(neighbor_available_list.get_item_metadata(index))
		print("DEBUG: Trying to add: ", loc_id)

		# Don't add self as neighbor
		if loc_id == current_loc_id:
			print("DEBUG: Skipping self")
			continue

		# Don't add duplicates
		if loc_id in neighbors_array:
			print("DEBUG: Already a neighbor, skipping")
			continue

		neighbors_array.append(loc_id)
		added_count += 1
		print("DEBUG: Added: ", loc_id)

		# Add reciprocal relationship (two-way)
		if not neighbor_graph.has(loc_id):
			neighbor_graph[loc_id] = []

		var other_neighbors = neighbor_graph[loc_id]
		# Only add if not already present
		if not current_loc_id in other_neighbors:
			other_neighbors.append(current_loc_id)
			reciprocal_count += 1
			print("DEBUG: Added reciprocal relationship: ", loc_id, " -> ", current_loc_id)

	print("DEBUG: Total added: ", added_count, ", reciprocal: ", reciprocal_count)
	if added_count > 0:
		neighbor_graph[current_loc_id] = neighbors_array
		neighbor_graph_dirty = true
		_refresh_neighbor_lists()
		neighbor_save_button.disabled = false
		if reciprocal_count > 0:
			neighbor_status_label.text = "Added %d neighbor(s) (bidirectional)" % added_count
		else:
			neighbor_status_label.text = "Added %d neighbor(s)" % added_count
		neighbor_available_list.deselect_all()
		neighbor_add_button.disabled = true
	else:
		neighbor_status_label.text = "No neighbors added (already exist or invalid)"

func _on_neighbor_remove_pressed():
	if not neighbor_current_location:
		return

	var selected_indices = neighbor_list.get_selected_items()
	if selected_indices.is_empty():
		return

	var current_loc_id = neighbor_current_location["id"]
	var neighbors_array = neighbor_graph.get(current_loc_id, []).duplicate()
	var to_remove = []

	for index in selected_indices:
		var loc_id = String(neighbor_list.get_item_metadata(index))
		to_remove.append(loc_id)

	for loc_id in to_remove:
		neighbors_array.erase(loc_id)

	neighbor_graph[current_loc_id] = neighbors_array
	neighbor_graph_dirty = true
	_refresh_neighbor_lists()
	neighbor_save_button.disabled = false
	neighbor_status_label.text = "Removed %d neighbor(s)" % to_remove.size()

func _on_neighbor_save_pressed():
	if not neighbor_graph_dirty:
		neighbor_status_label.text = "Nothing to save."
		return

	if _save_neighbor_graph():
		neighbor_status_label.text = "Saved neighbor graph successfully."
		neighbor_save_button.disabled = true
	else:
		neighbor_status_label.text = "Failed to save neighbor graph."

# ==== Sprite Size Editor ====

func _build_sprite_size_editor_ui(parent: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)

	var container = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 10)
	scroll.add_child(container)

	var title = Label.new()
	title.text = "Sprite Size Editor"
	title.add_theme_font_size_override("font_size", 16)
	container.add_child(title)

	var info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "Set the default display scale for each character's sprites. The Global Base Size applies to ALL sprites, then per-character scales multiply on top of that."
	container.add_child(info)

	# --- Toolbar ---
	var top_bar = HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 8)
	container.add_child(top_bar)

	var reload_button = Button.new()
	reload_button.text = "Reload"
	reload_button.pressed.connect(_on_sprite_size_reload_pressed)
	top_bar.add_child(reload_button)

	sprite_size_save_button = Button.new()
	sprite_size_save_button.text = "Save Sprite Sizes"
	sprite_size_save_button.disabled = true
	sprite_size_save_button.pressed.connect(_on_sprite_size_save_pressed)
	top_bar.add_child(sprite_size_save_button)

	var reset_all_button = Button.new()
	reset_all_button.text = "Reset All to 1.0"
	reset_all_button.pressed.connect(_on_sprite_size_reset_all_pressed)
	top_bar.add_child(reset_all_button)

	# --- Global Settings Bar ---
	var global_size_bar = HBoxContainer.new()
	container.add_child(global_size_bar)

	var global_label = Label.new()
	global_label.text = "Global Base Size:"
	global_size_bar.add_child(global_label)

	global_base_sprite_size_spin = SpinBox.new()
	global_base_sprite_size_spin.min_value = 0.1
	global_base_sprite_size_spin.max_value = 2.0
	global_base_sprite_size_spin.step = 0.05
	global_base_sprite_size_spin.value = 1.0
	global_base_sprite_size_spin.custom_minimum_size = Vector2(100, 0)
	global_base_sprite_size_spin.value_changed.connect(_on_global_base_size_changed)
	global_size_bar.add_child(global_base_sprite_size_spin)

	var global_hint = Label.new()
	global_hint.text = "(Applies to ALL sprites)"
	global_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	global_size_bar.add_child(global_hint)

	# --- Main Content Split ---
	var split = HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.custom_minimum_size = Vector2(0, 400) # Ensure minimum height for editor area
	container.add_child(split)

	# --- Left Panel: Character List ---
	var left_panel = VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(250, 0)
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(left_panel)

	var char_label = Label.new()
	char_label.text = "1. Select Character"
	char_label.add_theme_font_size_override("font_size", 16)
	char_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	left_panel.add_child(char_label)

	sprite_size_character_list = ItemList.new()
	sprite_size_character_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sprite_size_character_list.item_selected.connect(_on_sprite_size_character_selected)
	left_panel.add_child(sprite_size_character_list)

	# --- Right Panel: Editor Controls ---
	var right_panel = VBoxContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right_panel)

	# 1. Character Scale Section
	var char_settings_label = Label.new()
	char_settings_label.text = "2. Character Scale"
	char_settings_label.add_theme_font_size_override("font_size", 16)
	char_settings_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	right_panel.add_child(char_settings_label)

	var scale_row = HBoxContainer.new()
	right_panel.add_child(scale_row)

	var scale_label = Label.new()
	scale_label.text = "Base Scale:"
	scale_row.add_child(scale_label)

	sprite_size_spin = SpinBox.new()
	sprite_size_spin.min_value = 0.1
	sprite_size_spin.max_value = 2.0
	sprite_size_spin.step = 0.05
	sprite_size_spin.value = 1.0
	sprite_size_spin.custom_minimum_size = Vector2(80, 0)
	sprite_size_spin.editable = false
	sprite_size_spin.value_changed.connect(_on_sprite_size_value_changed)
	scale_row.add_child(sprite_size_spin)

	var apply_button = Button.new()
	apply_button.text = "Apply"
	apply_button.pressed.connect(_on_sprite_size_apply_pressed)
	scale_row.add_child(apply_button)

	var reset_button = Button.new()
	reset_button.text = "Reset"
	reset_button.pressed.connect(_on_sprite_size_reset_pressed)
	scale_row.add_child(reset_button)

	right_panel.add_child(HSeparator.new())

	# 2. Per-Sprite Overrides Section
	var sprite_settings_label = Label.new()
	sprite_settings_label.text = "3. Per-Sprite Overrides"
	sprite_settings_label.add_theme_font_size_override("font_size", 16)
	sprite_settings_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	right_panel.add_child(sprite_settings_label)

	# Horizontal container for Sprite List + Sprite Controls
	var sprite_area = HBoxContainer.new()
	sprite_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(sprite_area)

	# Sprite List (Left side of sprite area)
	var sprite_list_group = VBoxContainer.new()
	sprite_list_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL # Expands to fill available width
	sprite_list_group.size_flags_stretch_ratio = 0.4 # Takes 40% width
	sprite_area.add_child(sprite_list_group)

	var sprite_list_label = Label.new()
	sprite_list_label.text = "Select Sprite:"
	sprite_list_group.add_child(sprite_list_label)

	sprite_list = ItemList.new()
	sprite_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sprite_list.item_selected.connect(_on_sprite_selected)
	sprite_list_group.add_child(sprite_list)

	# Sprite Controls (Right side of sprite area)
	var sprite_controls = VBoxContainer.new()
	sprite_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sprite_controls.size_flags_stretch_ratio = 0.6 # Takes 60% width
	sprite_area.add_child(sprite_controls)

	# Scale Override
	var sprite_scale_row = HBoxContainer.new()
	sprite_controls.add_child(sprite_scale_row)
	
	sprite_scale_check = CheckBox.new()
	sprite_scale_check.text = "Override Scale:"
	sprite_scale_check.disabled = true
	sprite_scale_check.toggled.connect(_on_sprite_scale_check_toggled)
	sprite_scale_row.add_child(sprite_scale_check)

	sprite_scale_spin = SpinBox.new()
	sprite_scale_spin.min_value = 0.1
	sprite_scale_spin.max_value = 3.0
	sprite_scale_spin.step = 0.05
	sprite_scale_spin.value = 1.0
	sprite_scale_spin.editable = false
	sprite_scale_spin.value_changed.connect(_on_sprite_scale_value_changed)
	sprite_scale_row.add_child(sprite_scale_spin)

	sprite_controls.add_child(HSeparator.new())

	# Clipping Override
	sprite_custom_clip_check = CheckBox.new()
	sprite_custom_clip_check.text = "Custom Clipping"
	sprite_custom_clip_check.disabled = true
	sprite_custom_clip_check.toggled.connect(_on_sprite_clip_check_toggled)
	sprite_controls.add_child(sprite_custom_clip_check)

	var clip_grid = GridContainer.new()
	clip_grid.columns = 2
	clip_grid.add_theme_constant_override("h_separation", 15)
	sprite_controls.add_child(clip_grid)

	# Left Clip
	var clip_left_row = HBoxContainer.new()
	clip_grid.add_child(clip_left_row)
	var clip_l_lbl = Label.new()
	clip_l_lbl.text = "Left (0.0):"
	clip_left_row.add_child(clip_l_lbl)
	sprite_clip_left_spin = SpinBox.new()
	sprite_clip_left_spin.min_value = 0.0
	sprite_clip_left_spin.max_value = 1.0
	sprite_clip_left_spin.step = 0.01
	sprite_clip_left_spin.value = 0.0
	sprite_clip_left_spin.editable = false
	sprite_clip_left_spin.value_changed.connect(_on_sprite_clip_value_changed)
	clip_left_row.add_child(sprite_clip_left_spin)

	# Right Clip
	var clip_right_row = HBoxContainer.new()
	clip_grid.add_child(clip_right_row)
	var clip_r_lbl = Label.new()
	clip_r_lbl.text = "Right (1.0):"
	clip_right_row.add_child(clip_r_lbl)
	sprite_clip_right_spin = SpinBox.new()
	sprite_clip_right_spin.min_value = 0.0
	sprite_clip_right_spin.max_value = 1.0
	sprite_clip_right_spin.step = 0.01
	sprite_clip_right_spin.value = 1.0
	sprite_clip_right_spin.editable = false
	sprite_clip_right_spin.value_changed.connect(_on_sprite_clip_value_changed)
	clip_right_row.add_child(sprite_clip_right_spin)

	# Spacer
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sprite_controls.add_child(spacer)

	# Action Buttons
	var sprite_btns_row = HBoxContainer.new()
	sprite_controls.add_child(sprite_btns_row)

	var apply_sprite_button = Button.new()
	apply_sprite_button.text = "Apply Sprite"
	apply_sprite_button.pressed.connect(_on_sprite_override_apply_pressed)
	sprite_btns_row.add_child(apply_sprite_button)

	var clear_sprite_button = Button.new()
	clear_sprite_button.text = "Clear Sprite"
	clear_sprite_button.pressed.connect(_on_sprite_override_clear_pressed)
	sprite_btns_row.add_child(clear_sprite_button)

	right_panel.add_child(HSeparator.new())
	
	sprite_size_status_label = Label.new()
	sprite_size_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_panel.add_child(sprite_size_status_label)

	# Preview Section Header
	var preview_header = Label.new()
	preview_header.text = "Preview (Left: Twilight reference | Right: Selected character)"
	preview_header.add_theme_font_size_override("font_size", 14)
	container.add_child(preview_header)

	# Preview container - 1920x1080 aspect ratio scaled to fit
	sprite_size_preview_container = Control.new()
	sprite_size_preview_container.custom_minimum_size = Vector2(640, 360)  # 16:9 aspect ratio
	sprite_size_preview_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sprite_size_preview_container.clip_contents = true
	container.add_child(sprite_size_preview_container)

	# Background TextureRect
	sprite_size_preview_background = TextureRect.new()
	sprite_size_preview_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	sprite_size_preview_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite_size_preview_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# Load background texture
	var bg_texture = ResourceLoader.load(PREVIEW_BACKGROUND_PATH, "Texture2D")
	if bg_texture:
		sprite_size_preview_background.texture = bg_texture
	sprite_size_preview_container.add_child(sprite_size_preview_background)

	# Twilight reference sprite (left side)
	sprite_size_preview_twilight = TextureRect.new()
	sprite_size_preview_twilight.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite_size_preview_twilight.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	sprite_size_preview_container.add_child(sprite_size_preview_twilight)

	# Twilight label
	sprite_size_preview_twi_label = Label.new()
	sprite_size_preview_twi_label.text = "Twilight (Reference)"
	sprite_size_preview_twi_label.add_theme_font_size_override("font_size", 12)
	sprite_size_preview_twi_label.add_theme_color_override("font_color", Color(1, 1, 1))
	sprite_size_preview_twi_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	sprite_size_preview_twi_label.add_theme_constant_override("shadow_offset_x", 1)
	sprite_size_preview_twi_label.add_theme_constant_override("shadow_offset_y", 1)
	sprite_size_preview_container.add_child(sprite_size_preview_twi_label)

	# Selected character sprite (right side)
	sprite_size_preview_character = TextureRect.new()
	sprite_size_preview_character.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite_size_preview_character.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	sprite_size_preview_container.add_child(sprite_size_preview_character)

	# Selected character label
	sprite_size_preview_char_label = Label.new()
	sprite_size_preview_char_label.text = "Selected Character"
	sprite_size_preview_char_label.add_theme_font_size_override("font_size", 12)
	sprite_size_preview_char_label.add_theme_color_override("font_color", Color(1, 1, 1))
	sprite_size_preview_char_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	sprite_size_preview_char_label.add_theme_constant_override("shadow_offset_x", 1)
	sprite_size_preview_char_label.add_theme_constant_override("shadow_offset_y", 1)
	sprite_size_preview_container.add_child(sprite_size_preview_char_label)

	# Clip visualization lines (semi-transparent red bars)
	sprite_size_preview_clip_left = ColorRect.new()
	sprite_size_preview_clip_left.color = Color(1, 0, 0, 0.3)
	sprite_size_preview_clip_left.visible = false
	sprite_size_preview_container.add_child(sprite_size_preview_clip_left)

	sprite_size_preview_clip_right = ColorRect.new()
	sprite_size_preview_clip_right.color = Color(1, 0, 0, 0.3)
	sprite_size_preview_clip_right.visible = false
	sprite_size_preview_container.add_child(sprite_size_preview_clip_right)

func _load_sprite_size_editor_state() -> void:
	sprite_size_data = _read_sprite_size_file()
	sprite_size_dirty = false
	sprite_size_selected_tag = ""
	# Extract global base size if present
	if sprite_size_data.has(GLOBAL_BASE_SIZE_KEY):
		global_base_sprite_size = float(sprite_size_data[GLOBAL_BASE_SIZE_KEY])
		sprite_size_data.erase(GLOBAL_BASE_SIZE_KEY)  # Remove from per-character data
	else:
		global_base_sprite_size = 1.0
	if global_base_sprite_size_spin:
		global_base_sprite_size_spin.value = global_base_sprite_size
	_refresh_sprite_size_character_list()
	_mark_sprite_size_dirty(false)
	_set_sprite_size_status("Sprite sizes loaded. Global base: %.2f" % global_base_sprite_size)

func _read_sprite_size_file() -> Dictionary:
	if not FileAccess.file_exists(SPRITE_SIZE_FILE_PATH):
		return {}
	var file := FileAccess.open(SPRITE_SIZE_FILE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var result := json.parse(text)
	if result != OK:
		push_error("Failed to parse sprite sizes: %s" % json.get_error_message())
		return {}
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data

func _write_sprite_size_file(data: Dictionary) -> bool:
	var file := FileAccess.open(SPRITE_SIZE_FILE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Unable to write sprite sizes to %s" % SPRITE_SIZE_FILE_PATH)
		return false
	file.store_string(JSON.stringify(data, "  ") + "\n")
	file.close()
	return true

func _refresh_sprite_size_character_list() -> void:
	if sprite_size_character_list == null:
		return
	sprite_size_character_list.clear()

	# Build sorted character list
	var entries: Array = []
	for tag in character_reference.keys():
		var display_name: String = str(character_reference[tag])
		var size_value: float = _get_character_scale(tag)
		var has_sprite_overrides: bool = _has_sprite_overrides(tag)
		entries.append({"tag": tag, "name": display_name, "size": size_value, "has_overrides": has_sprite_overrides})
	entries.sort_custom(Callable(self, "_sort_sprite_size_entries"))

	for entry in entries:
		var size_str = "%.2f" % entry["size"]
		var override_marker = " *" if entry["has_overrides"] else ""
		var label = "%s (%s) - Scale: %s%s" % [entry["name"], entry["tag"], size_str, override_marker]
		var item_index := sprite_size_character_list.add_item(label)
		sprite_size_character_list.set_item_metadata(item_index, entry["tag"])
		# Highlight characters with customizations
		if entry["has_overrides"]:
			sprite_size_character_list.set_item_custom_fg_color(item_index, Color(0.8, 0.6, 1.0))  # Purple for overrides
		elif absf(entry["size"] - 1.0) > 0.001:
			sprite_size_character_list.set_item_custom_fg_color(item_index, Color(0.4, 0.8, 1.0))  # Cyan for scale

	# Select first character if none selected
	if entries.size() > 0:
		if sprite_size_selected_tag == "":
			sprite_size_selected_tag = entries[0]["tag"]
		var matched := false
		for i in range(sprite_size_character_list.get_item_count()):
			if sprite_size_character_list.get_item_metadata(i) == sprite_size_selected_tag:
				sprite_size_character_list.select(i)
				matched = true
				break
		if not matched and entries.size() > 0:
			sprite_size_selected_tag = entries[0]["tag"]
			sprite_size_character_list.select(0)
		_update_sprite_size_spin_value()
		_refresh_sprite_list()
	else:
		sprite_size_selected_tag = ""

func _sort_sprite_size_entries(a, b) -> bool:
	return a["name"].nocasecmp_to(b["name"]) < 0

func _update_sprite_size_spin_value() -> void:
	if sprite_size_spin == null:
		return
	if sprite_size_selected_tag == "":
		sprite_size_spin.value = 1.0
		sprite_size_spin.editable = false
		_update_sprite_size_preview()
		return
	sprite_size_spin.editable = true
	var current_value: float = _get_character_scale(sprite_size_selected_tag)
	sprite_size_spin.value = current_value
	_update_sprite_size_preview()

func _update_sprite_size_preview() -> void:
	if sprite_size_preview_container == null:
		return
	
	var container_size: Vector2 = sprite_size_preview_container.size
	if container_size.x < 10 or container_size.y < 10:
		container_size = sprite_size_preview_container.custom_minimum_size
	
	# Base sprite height relative to preview (characters take roughly 60% of screen height in game)
	# Apply global base size to the base height
	var base_sprite_height: float = container_size.y * 0.6 * global_base_sprite_size
	
	# Load and position Twilight (reference character on left)
	var twi_scale: float = float(sprite_size_data.get(PREVIEW_REFERENCE_CHAR, 1.0))
	var twi_sprite_path: String = "res://assets/CoreCharacters/Twilight/sprites/neutral.png"
	var twi_texture: Texture2D = ResourceLoader.load(twi_sprite_path, "Texture2D")
	
	if twi_texture and sprite_size_preview_twilight:
		sprite_size_preview_twilight.texture = twi_texture
		# Calculate scaled size (global base is already in base_sprite_height)
		var aspect_ratio: float = float(twi_texture.get_width()) / float(twi_texture.get_height())
		var scaled_height: float = base_sprite_height * twi_scale
		var scaled_width: float = scaled_height * aspect_ratio
		sprite_size_preview_twilight.size = Vector2(scaled_width, scaled_height)
		# Position at bottom-left quarter
		var twi_x: float = container_size.x * 0.15
		var twi_y: float = container_size.y - scaled_height
		sprite_size_preview_twilight.position = Vector2(twi_x, twi_y)
		sprite_size_preview_twilight.visible = true
		
		# Update label - show final scale (global * character)
		var final_twi_scale: float = global_base_sprite_size * twi_scale
		if sprite_size_preview_twi_label:
			sprite_size_preview_twi_label.text = "Twilight (Final: %.2f)" % final_twi_scale
			sprite_size_preview_twi_label.position = Vector2(twi_x, twi_y - 20)
	
	# Load and position selected character (on right)
	# Hide clip visualizers by default
	if sprite_size_preview_clip_left:
		sprite_size_preview_clip_left.visible = false
	if sprite_size_preview_clip_right:
		sprite_size_preview_clip_right.visible = false
	
	if sprite_size_selected_tag == "" or sprite_size_selected_tag == PREVIEW_REFERENCE_CHAR:
		# Hide selected character sprite if none or same as reference
		if sprite_size_preview_character:
			sprite_size_preview_character.visible = false
		if sprite_size_preview_char_label:
			sprite_size_preview_char_label.visible = false
		return
	
	var char_scale: float = sprite_size_spin.value if sprite_size_spin else 1.0
	
	# Use selected sprite if available, otherwise use default sprite path
	var char_sprite_path: String = ""
	if sprite_selected_name != "":
		var folder_path: String = _get_character_folder_path(sprite_size_selected_tag)
		if folder_path != "":
			for ext in ["png", "webp"]:
				var test_path = folder_path + sprite_selected_name + "." + ext
				if FileAccess.file_exists(test_path):
					char_sprite_path = test_path
					break
	
	if char_sprite_path == "":
		char_sprite_path = _get_character_sprite_path(sprite_size_selected_tag)
	
	if char_sprite_path == "":
		if sprite_size_preview_character:
			sprite_size_preview_character.visible = false
		if sprite_size_preview_char_label:
			sprite_size_preview_char_label.visible = false
		return
	
	var char_texture: Texture2D = ResourceLoader.load(char_sprite_path, "Texture2D")
	
	if char_texture and sprite_size_preview_character:
		sprite_size_preview_character.texture = char_texture
		
		# Check for per-sprite scale override
		var preview_scale: float = char_scale
		if sprite_selected_name != "" and sprite_scale_check and sprite_scale_check.is_pressed():
			preview_scale = sprite_scale_spin.value
		
		# Calculate scaled size (global base is already in base_sprite_height)
		var aspect_ratio: float = float(char_texture.get_width()) / float(char_texture.get_height())
		var scaled_height: float = base_sprite_height * preview_scale
		var scaled_width: float = scaled_height * aspect_ratio
		sprite_size_preview_character.size = Vector2(scaled_width, scaled_height)
		# Position at bottom-right quarter
		var char_x: float = container_size.x * 0.65
		var char_y: float = container_size.y - scaled_height
		sprite_size_preview_character.position = Vector2(char_x, char_y)
		sprite_size_preview_character.visible = true
		
		# Update label - show final scale (global * character)
		var final_char_scale: float = global_base_sprite_size * preview_scale
		if sprite_size_preview_char_label:
			var char_name: String = str(character_reference.get(sprite_size_selected_tag, sprite_size_selected_tag))
			var sprite_label: String = ""
			if sprite_selected_name != "":
				sprite_label = " / %s" % sprite_selected_name
			sprite_size_preview_char_label.text = "%s%s (Final: %.2f)" % [char_name, sprite_label, final_char_scale]
			sprite_size_preview_char_label.position = Vector2(char_x, char_y - 20)
			sprite_size_preview_char_label.visible = true
		
		# Show clip visualization if custom clipping is enabled
		if sprite_custom_clip_check and sprite_custom_clip_check.is_pressed():
			var clip_left: float = sprite_clip_left_spin.value if sprite_clip_left_spin else 0.0
			var clip_right: float = sprite_clip_right_spin.value if sprite_clip_right_spin else 1.0
			
			# Left clip area (semi-transparent red from sprite left to clip point)
			if sprite_size_preview_clip_left and clip_left > 0.001:
				var clip_left_width: float = scaled_width * clip_left
				sprite_size_preview_clip_left.position = Vector2(char_x, char_y)
				sprite_size_preview_clip_left.size = Vector2(clip_left_width, scaled_height)
				sprite_size_preview_clip_left.visible = true
			
			# Right clip area (semi-transparent red from clip point to sprite right)
			if sprite_size_preview_clip_right and clip_right < 0.999:
				var clip_right_start: float = char_x + (scaled_width * clip_right)
				var clip_right_width: float = scaled_width * (1.0 - clip_right)
				sprite_size_preview_clip_right.position = Vector2(clip_right_start, char_y)
				sprite_size_preview_clip_right.size = Vector2(clip_right_width, scaled_height)
				sprite_size_preview_clip_right.visible = true

func _get_character_sprite_path(tag: String) -> String:
	# Try to find a neutral/default sprite for the character
	var character_script = load("res://scripts/CharacterManager.gd")
	if character_script == null:
		return ""
	var manager = character_script.new()
	if manager == null:
		return ""
	if manager.has_method("_load_core_characters"):
		manager._load_core_characters()
	if manager.has_method("_load_custom_characters"):
		manager._load_custom_characters()
	var config = manager.get_character(tag)
	if config == null:
		manager.free()
		return ""
	var folder_path: String = str(config.folder_path)
	manager.free()
	
	# Try common sprite names
	var sprite_names := ["neutral.png", "smile.png", "happy.png", "default.png"]
	for sprite_name in sprite_names:
		var full_path: String = folder_path + sprite_name
		if FileAccess.file_exists(full_path):
			return full_path
	
	# Fallback: try to find any png/webp file
	var dir = DirAccess.open(folder_path)
	if dir:
		dir.list_dir_begin()
		var entry = dir.get_next()
		while entry != "":
			if not dir.current_is_dir() and not entry.begins_with("."):
				var ext = entry.get_extension().to_lower()
				if ext in ["png", "webp", "jpg", "jpeg"]:
					dir.list_dir_end()
					return folder_path + entry
			entry = dir.get_next()
		dir.list_dir_end()
	return ""

func _mark_sprite_size_dirty(is_dirty: bool) -> void:
	sprite_size_dirty = is_dirty
	if sprite_size_save_button:
		sprite_size_save_button.disabled = not is_dirty
	if not is_dirty:
		_set_sprite_size_status("Sprite sizes loaded.")
	else:
		_set_sprite_size_status("Unsaved sprite size changes.")

func _set_sprite_size_status(text: String) -> void:
	if sprite_size_status_label:
		sprite_size_status_label.text = text

func _on_sprite_size_character_selected(index: int) -> void:
	if sprite_size_character_list == null:
		return
	sprite_size_selected_tag = str(sprite_size_character_list.get_item_metadata(index))
	_update_sprite_size_spin_value()
	_refresh_sprite_list()

func _on_sprite_size_value_changed(_value: float) -> void:
	# Update preview in real-time as user adjusts the slider
	_update_sprite_size_preview()

func _on_sprite_size_apply_pressed() -> void:
	if sprite_size_selected_tag == "":
		_set_sprite_size_status("Select a character first.")
		return
	var new_value: float = sprite_size_spin.value
	_set_character_scale(sprite_size_selected_tag, new_value)
	_mark_sprite_size_dirty(true)
	_refresh_sprite_size_character_list()
	var char_name: String = str(character_reference.get(sprite_size_selected_tag, sprite_size_selected_tag))
	_set_sprite_size_status("Set %s sprite size to %.2f." % [char_name, new_value])

func _on_sprite_size_reset_pressed() -> void:
	if sprite_size_selected_tag == "":
		_set_sprite_size_status("Select a character first.")
		return
	_set_character_scale(sprite_size_selected_tag, 1.0)
	sprite_size_spin.value = 1.0
	_mark_sprite_size_dirty(true)
	_refresh_sprite_size_character_list()
	var char_name: String = str(character_reference.get(sprite_size_selected_tag, sprite_size_selected_tag))
	_set_sprite_size_status("Reset %s sprite size to default (1.0)." % char_name)

func _on_sprite_size_reset_all_pressed() -> void:
	for tag in character_reference.keys():
		_set_character_scale(tag, 1.0)
	_mark_sprite_size_dirty(true)
	_refresh_sprite_size_character_list()
	_update_sprite_size_spin_value()
	_set_sprite_size_status("Reset all characters to default sprite size (1.0).")

func _on_sprite_size_reload_pressed() -> void:
	_load_character_reference()
	_load_sprite_size_editor_state()

func _on_sprite_size_save_pressed() -> void:
	if not sprite_size_dirty:
		_set_sprite_size_status("Nothing to save.")
		return
	# Build clean data for saving
	var clean_data: Dictionary = {}
	for tag in sprite_size_data.keys():
		var value = sprite_size_data[tag]
		if typeof(value) == TYPE_DICTIONARY:
			# New format with potential sprite overrides
			var char_data: Dictionary = value.duplicate()
			var scale: float = float(char_data.get("scale", 1.0))
			var sprites: Dictionary = char_data.get("sprites", {})
			
			# Clean up sprites - remove entries without overrides
			var clean_sprites: Dictionary = {}
			for sprite_name in sprites.keys():
				var sprite_data: Dictionary = sprites[sprite_name]
				var has_scale: bool = sprite_data.has("scale") and absf(float(sprite_data["scale"]) - 1.0) > 0.001
				var has_clip: bool = sprite_data.has("clip_left") or sprite_data.has("clip_right")
				if has_scale or has_clip:
					clean_sprites[sprite_name] = sprite_data
			
			# Only save if has non-default values
			if absf(scale - 1.0) > 0.001 or not clean_sprites.is_empty():
				var output_data: Dictionary = {}
				if absf(scale - 1.0) > 0.001:
					output_data["scale"] = scale
				if not clean_sprites.is_empty():
					output_data["sprites"] = clean_sprites
				clean_data[tag] = output_data
		else:
			# Old format: simple float
			var scale: float = float(value)
			if absf(scale - 1.0) > 0.001:
				clean_data[tag] = scale
	
	# Always save global base size if not default
	if absf(global_base_sprite_size - 1.0) > 0.001:
		clean_data[GLOBAL_BASE_SIZE_KEY] = global_base_sprite_size
	if _write_sprite_size_file(clean_data):
		# Reload to normalize format
		sprite_size_data = clean_data
		_mark_sprite_size_dirty(false)
		_set_sprite_size_status("Sprite sizes saved to disk. Global base: %.2f" % global_base_sprite_size)
	else:
		_set_sprite_size_status("Failed to save sprite sizes.")

func _on_global_base_size_changed(value: float) -> void:
	global_base_sprite_size = value
	_mark_sprite_size_dirty(true)
	_update_sprite_size_preview()
	_set_sprite_size_status("Global base size changed to %.2f (unsaved)" % value)

# ============ Helper functions for new data format ============

## Get the character-level scale from sprite_size_data (handles both formats)
func _get_character_scale(tag: String) -> float:
	if not sprite_size_data.has(tag):
		return 1.0
	var value = sprite_size_data[tag]
	if typeof(value) == TYPE_DICTIONARY:
		return float(value.get("scale", 1.0))
	else:
		return float(value)

## Set the character-level scale in sprite_size_data (preserving sprite overrides)
func _set_character_scale(tag: String, scale: float) -> void:
	if not sprite_size_data.has(tag):
		if absf(scale - 1.0) > 0.001:
			sprite_size_data[tag] = scale
		return
	
	var value = sprite_size_data[tag]
	if typeof(value) == TYPE_DICTIONARY:
		# Preserve existing structure, just update scale
		value["scale"] = scale
	else:
		# Convert to new format if we already have overrides coming
		sprite_size_data[tag] = scale

## Check if character has any per-sprite overrides
func _has_sprite_overrides(tag: String) -> bool:
	if not sprite_size_data.has(tag):
		return false
	var value = sprite_size_data[tag]
	if typeof(value) == TYPE_DICTIONARY:
		return value.has("sprites") and not value["sprites"].is_empty()
	return false

## Get per-sprite override data (returns empty dict if none)
func _get_sprite_override(tag: String, sprite_name: String) -> Dictionary:
	if not sprite_size_data.has(tag):
		return {}
	var value = sprite_size_data[tag]
	if typeof(value) == TYPE_DICTIONARY:
		var sprites: Dictionary = value.get("sprites", {})
		return sprites.get(sprite_name, {})
	return {}

## Set per-sprite override data
func _set_sprite_override(tag: String, sprite_name: String, override_data: Dictionary) -> void:
	if not sprite_size_data.has(tag):
		# Create new entry with default scale and sprite overrides
		sprite_size_data[tag] = {"scale": 1.0, "sprites": {sprite_name: override_data}}
		return
	
	var value = sprite_size_data[tag]
	if typeof(value) == TYPE_DICTIONARY:
		if not value.has("sprites"):
			value["sprites"] = {}
		value["sprites"][sprite_name] = override_data
	else:
		# Convert simple float to new format
		var old_scale: float = float(value)
		sprite_size_data[tag] = {"scale": old_scale, "sprites": {sprite_name: override_data}}

## Clear per-sprite override
func _clear_sprite_override(tag: String, sprite_name: String) -> void:
	if not sprite_size_data.has(tag):
		return
	var value = sprite_size_data[tag]
	if typeof(value) == TYPE_DICTIONARY:
		if value.has("sprites") and value["sprites"].has(sprite_name):
			value["sprites"].erase(sprite_name)

# ============ Sprite list and per-sprite UI callbacks ============

func _refresh_sprite_list() -> void:
	if sprite_list == null:
		return
	sprite_list.clear()
	sprite_selected_name = ""
	
	# Reset per-sprite controls
	_reset_sprite_controls()
	
	if sprite_size_selected_tag == "":
		return
	
	# Get character's folder path
	var folder_path: String = _get_character_folder_path(sprite_size_selected_tag)
	if folder_path == "":
		return
	
	# List sprite files
	var sprites: Array[String] = []
	var dir = DirAccess.open(folder_path)
	if dir:
		dir.list_dir_begin()
		var entry = dir.get_next()
		while entry != "":
			if not dir.current_is_dir() and not entry.begins_with("."):
				var ext = entry.get_extension().to_lower()
				if ext in ["png", "webp", "jpg", "jpeg"]:
					var name_without_ext = entry.get_basename()
					sprites.append(name_without_ext)
			entry = dir.get_next()
		dir.list_dir_end()
	
	sprites.sort()
	
	for sprite_name in sprites:
		var override_data = _get_sprite_override(sprite_size_selected_tag, sprite_name)
		var has_scale: bool = override_data.has("scale")
		var has_clip: bool = override_data.has("clip_left") or override_data.has("clip_right")
		var marker: String = ""
		if has_scale and has_clip:
			marker = " [S+C]"
		elif has_scale:
			marker = " [S]"
		elif has_clip:
			marker = " [C]"
		
		var item_idx = sprite_list.add_item(sprite_name + marker)
		sprite_list.set_item_metadata(item_idx, sprite_name)
		if has_scale or has_clip:
			sprite_list.set_item_custom_fg_color(item_idx, Color(0.4, 1.0, 0.6))  # Green for customized

func _reset_sprite_controls() -> void:
	if sprite_scale_check:
		sprite_scale_check.set_pressed_no_signal(false)
		sprite_scale_check.disabled = true
	if sprite_scale_spin:
		sprite_scale_spin.value = 1.0
		sprite_scale_spin.editable = false
	if sprite_custom_clip_check:
		sprite_custom_clip_check.set_pressed_no_signal(false)
		sprite_custom_clip_check.disabled = true
	if sprite_clip_left_spin:
		sprite_clip_left_spin.value = 0.0
		sprite_clip_left_spin.editable = false
	if sprite_clip_right_spin:
		sprite_clip_right_spin.value = 1.0
		sprite_clip_right_spin.editable = false

func _on_sprite_selected(index: int) -> void:
	if sprite_list == null:
		return
	sprite_selected_name = str(sprite_list.get_item_metadata(index))
	
	# Enable checkboxes
	if sprite_scale_check:
		sprite_scale_check.disabled = false
	if sprite_custom_clip_check:
		sprite_custom_clip_check.disabled = false
	
	# Load existing override data
	var override_data = _get_sprite_override(sprite_size_selected_tag, sprite_selected_name)
	
	# Populate scale controls
	if override_data.has("scale"):
		sprite_scale_check.set_pressed_no_signal(true)
		sprite_scale_spin.value = float(override_data["scale"])
		sprite_scale_spin.editable = true
	else:
		sprite_scale_check.set_pressed_no_signal(false)
		sprite_scale_spin.value = 1.0
		sprite_scale_spin.editable = false
	
	# Populate clip controls
	if override_data.has("clip_left") or override_data.has("clip_right"):
		sprite_custom_clip_check.set_pressed_no_signal(true)
		sprite_clip_left_spin.value = float(override_data.get("clip_left", 0.0))
		sprite_clip_right_spin.value = float(override_data.get("clip_right", 1.0))
		sprite_clip_left_spin.editable = true
		sprite_clip_right_spin.editable = true
	else:
		sprite_custom_clip_check.set_pressed_no_signal(false)
		sprite_clip_left_spin.value = 0.0
		sprite_clip_right_spin.value = 1.0
		sprite_clip_left_spin.editable = false
		sprite_clip_right_spin.editable = false
	
	_update_sprite_size_preview()

func _on_sprite_scale_check_toggled(pressed: bool) -> void:
	if sprite_scale_spin:
		sprite_scale_spin.editable = pressed
	_update_sprite_size_preview()

func _on_sprite_clip_check_toggled(pressed: bool) -> void:
	if sprite_clip_left_spin:
		sprite_clip_left_spin.editable = pressed
	if sprite_clip_right_spin:
		sprite_clip_right_spin.editable = pressed
	_update_sprite_size_preview()

func _on_sprite_scale_value_changed(_value: float) -> void:
	_update_sprite_size_preview()

func _on_sprite_clip_value_changed(_value: float) -> void:
	_update_sprite_size_preview()

func _on_sprite_override_apply_pressed() -> void:
	if sprite_size_selected_tag == "" or sprite_selected_name == "":
		_set_sprite_size_status("Select a character and sprite first.")
		return
	
	var override_data: Dictionary = {}
	
	if sprite_scale_check and sprite_scale_check.is_pressed():
		override_data["scale"] = sprite_scale_spin.value
	
	if sprite_custom_clip_check and sprite_custom_clip_check.is_pressed():
		override_data["clip_left"] = sprite_clip_left_spin.value
		override_data["clip_right"] = sprite_clip_right_spin.value
	
	if override_data.is_empty():
		_clear_sprite_override(sprite_size_selected_tag, sprite_selected_name)
		_set_sprite_size_status("Cleared overrides for %s." % sprite_selected_name)
	else:
		_set_sprite_override(sprite_size_selected_tag, sprite_selected_name, override_data)
		_set_sprite_size_status("Applied overrides for %s." % sprite_selected_name)
	
	_mark_sprite_size_dirty(true)
	_refresh_sprite_list()
	_refresh_sprite_size_character_list()

func _on_sprite_override_clear_pressed() -> void:
	if sprite_size_selected_tag == "" or sprite_selected_name == "":
		_set_sprite_size_status("Select a character and sprite first.")
		return
	
	_clear_sprite_override(sprite_size_selected_tag, sprite_selected_name)
	_reset_sprite_controls()
	_mark_sprite_size_dirty(true)
	_refresh_sprite_list()
	_refresh_sprite_size_character_list()
	_set_sprite_size_status("Cleared overrides for %s." % sprite_selected_name)

func _get_character_folder_path(tag: String) -> String:
	var character_script = load("res://scripts/CharacterManager.gd")
	if character_script == null:
		return ""
	var manager = character_script.new()
	if manager == null:
		return ""
	if manager.has_method("_load_core_characters"):
		manager._load_core_characters()
	if manager.has_method("_load_custom_characters"):
		manager._load_custom_characters()
	var config = manager.get_character(tag)
	if config == null:
		manager.free()
		return ""
	var folder_path: String = str(config.folder_path)
	manager.free()
	return folder_path
