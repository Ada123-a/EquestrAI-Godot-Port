extends BaseStartFlow

class AnimatedIcon extends TextureRect:
	var frames: Array[Texture2D] = []
	var frame_duration: float = 0.1
	var _time_accumulator: float = 0.0
	var _current_frame: int = 0
	
	func _ready():
		if frames.is_empty():
			set_process(false)
			return
		texture = frames[0]
		
	func _process(delta):
		if frames.size() <= 1:
			return
		_time_accumulator += delta
		if _time_accumulator >= frame_duration:
			_time_accumulator -= frame_duration
			_current_frame = (_current_frame + 1) % frames.size()
			texture = frames[_current_frame]

enum Steps {
	PERSONA,
	SELECT,
	PROMPT,
	RESULT
}
enum GenerationPhase {
	IDLE,
	PLANNING,
	WRITING
}

const EXCLUDED_LOCATIONS: Array[String] = ["dream_realm"]
const MAX_SELECTED_CHARACTERS: int = 3
const SAMPLE_LINES: Array[String] = [
	"[location: train]",
	"Rain drums on the windows as the train nears Ponyville.",
	"[sprite: twi smile]",
	"twi \"Deep breath. I'll be right by your side once we pull in.\""
]
const START_LOCATION_OVERRIDES: Dictionary = {
	"twi": "golden_oak_interior",
	"spike": "golden_oak_interior",
	"aj": "sweet_apple_acres",
	"rarity": "carousel_boutique",
	"pinkie": "sugarcube_corner",
	"dash": "rainbow_dash_living_room",
	"shy": "fluttershy_cottage_inside",
	"trixie": "trixie_wagon",
	"zecora": "zecora_hut",
	"cel": "celestia_bedroom",
	"luna": "luna_bedroom",
	"chrys": "changeling_hive_throne_room"
}
const DEFAULT_START_LOCATION: String = "ponyville_main_square"

var available_characters: Array = []
var selected_tags: Array[String] = []
var prompt_text: String = ""
var response_text: String = ""
var plan_text: String = ""
var recommended_start_location_id: String = DEFAULT_START_LOCATION
var current_selected_characters: Array = []
var is_generating: bool = false
var current_step: int = Steps.PERSONA
var generation_phase: int = GenerationPhase.IDLE

var title_label: Label
var info_label: Label
var content_holder: VBoxContainer
var status_label: Label
var footer_holder: HBoxContainer
var prompt_input: TextEdit
var response_output: TextEdit
var footer_buttons: Dictionary = {}
var start_location_selector: OptionButton = null
var start_location_locked: bool = false
var start_location_container: VBoxContainer = null
var character_scroll: ScrollContainer = null

# Persona UI References
var persona_name_input: LineEdit
var persona_sex_option: OptionButton
var persona_species_option: OptionButton
var persona_race_option: OptionButton
var persona_race_container: Control
var persona_appearance_input: TextEdit

func initialize(char_mgr, loc_mgr, settings_mgr, llm_ctrl: LLMController = null):
	super.initialize(char_mgr, loc_mgr, settings_mgr, llm_ctrl)
	
	if llm_controller:
		llm_controller.llm_response_received.connect(_on_llm_response_received)
		llm_controller.llm_error_occurred.connect(_on_llm_error)

func _ready():
	_setup_layout()
	_load_dependencies()
	_render_step()

func _process(delta):
	# Auto-scroll logic for character selection
	if character_scroll and character_scroll.is_visible_in_tree():
		var local_mouse = character_scroll.get_local_mouse_position()
		var view_size = character_scroll.size
		var scroll_margin = 60.0
		var scroll_speed = 600.0
		
		# Check if mouse is roughly inside the scroll container horizontally
		if local_mouse.x >= 0 and local_mouse.x <= view_size.x:
			if local_mouse.y >= 0 and local_mouse.y < scroll_margin:
				# Scale speed by closeness to edge
				var factor = 1.0 - (local_mouse.y / scroll_margin)
				character_scroll.scroll_vertical -= int(scroll_speed * delta * factor)
			elif local_mouse.y > view_size.y - scroll_margin and local_mouse.y <= view_size.y:
				var dist = view_size.y - local_mouse.y
				var factor = 1.0 - (dist / scroll_margin)
				character_scroll.scroll_vertical += int(scroll_speed * delta * factor)

func _setup_layout():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var overlay: ColorRect = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.8)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel: Panel = Panel.new()
	panel.custom_minimum_size = Vector2(1100, 750)
	center.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	panel.add_child(margin)
	var root_vbox: VBoxContainer = VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 18)
	margin.add_child(root_vbox)
	title_label = Label.new()
	title_label.text = "Custom Start"
	title_label.add_theme_font_size_override("font_size", 42)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(title_label)
	info_label = Label.new()
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_vbox.add_child(info_label)
	var divider: HSeparator = HSeparator.new()
	root_vbox.add_child(divider)
	content_holder = VBoxContainer.new()
	content_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_holder.add_theme_constant_override("separation", 12)
	root_vbox.add_child(content_holder)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 18)
	status_label.modulate = Color(0.9, 0.8, 0.4)
	root_vbox.add_child(status_label)
	footer_holder = HBoxContainer.new()
	footer_holder.alignment = BoxContainer.ALIGNMENT_CENTER
	footer_holder.add_theme_constant_override("separation", 16)
	root_vbox.add_child(footer_holder)

func _load_dependencies():
	if character_manager:
		available_characters = character_manager.get_all_characters(true)
	else:
		available_characters = []

func _render_step():
	_clear_container(content_holder)
	_clear_container(footer_holder)
	footer_buttons.clear()
	status_label.text = "" # Ensure old status messages are cleared
	match current_step:
		Steps.PERSONA:
			_build_persona_editor()
		Steps.SELECT:
			_build_character_selection()
		Steps.PROMPT:
			_build_prompt_input()
		Steps.RESULT:
			_build_result_view()

func _build_persona_editor():
	title_label.text = "Custom Start — Define Your Persona"
	info_label.text = "Who will you be in this story?"
	
	var center_box: VBoxContainer = VBoxContainer.new()
	center_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_box.custom_minimum_size = Vector2(600, 0) 
	center_box.add_theme_constant_override("separation", 16)
	
	# Container for form
	var form_panel = PanelContainer.new()
	var form_style = StyleBoxFlat.new()
	form_style.bg_color = Color(0.1, 0.1, 0.12, 0.5)
	form_style.corner_radius_top_left = 8
	form_style.corner_radius_top_right = 8
	form_style.corner_radius_bottom_left = 8
	form_style.corner_radius_bottom_right = 8
	form_style.content_margin_left = 20
	form_style.content_margin_right = 20
	form_style.content_margin_top = 20
	form_style.content_margin_bottom = 20
	form_panel.add_theme_stylebox_override("panel", form_style)
	
	var form_vbox = VBoxContainer.new()
	form_vbox.add_theme_constant_override("separation", 16)
	form_panel.add_child(form_vbox)
	
	# Name
	var name_hbox = HBoxContainer.new()
	var name_lbl = Label.new()
	name_lbl.text = "Name:"
	name_lbl.custom_minimum_size = Vector2(100, 0)
	name_hbox.add_child(name_lbl)
	
	persona_name_input = LineEdit.new()
	persona_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	persona_name_input.placeholder_text = "Enter Name"
	name_hbox.add_child(persona_name_input)
	form_vbox.add_child(name_hbox)
	
	# Sex
	var sex_hbox = HBoxContainer.new()
	var sex_lbl = Label.new()
	sex_lbl.text = "Sex:"
	sex_lbl.custom_minimum_size = Vector2(100, 0)
	sex_hbox.add_child(sex_lbl)
	
	persona_sex_option = OptionButton.new()
	persona_sex_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	SettingsManager.populate_option_button(persona_sex_option, SettingsManager.SEX_OPTIONS)
	sex_hbox.add_child(persona_sex_option)
	form_vbox.add_child(sex_hbox)
	
	# Species
	var species_hbox = HBoxContainer.new()
	var species_lbl = Label.new()
	species_lbl.text = "Species:"
	species_lbl.custom_minimum_size = Vector2(100, 0)
	species_hbox.add_child(species_lbl)
	
	persona_species_option = OptionButton.new()
	persona_species_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	SettingsManager.populate_option_button(persona_species_option, SettingsManager.SPECIES_OPTIONS)
	species_hbox.add_child(persona_species_option)
	form_vbox.add_child(species_hbox)
	
	# Race (Conditional)
	persona_race_container = HBoxContainer.new()
	var race_lbl = Label.new()
	race_lbl.text = "Race:"
	race_lbl.custom_minimum_size = Vector2(100, 0)
	persona_race_container.add_child(race_lbl)
	
	persona_race_option = OptionButton.new()
	persona_race_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	SettingsManager.populate_option_button(persona_race_option, SettingsManager.RACE_OPTIONS)
	persona_race_container.add_child(persona_race_option)
	form_vbox.add_child(persona_race_container)
	
	# Connect Species -> Race logic
	persona_species_option.item_selected.connect(func(idx):
		var species_id = SettingsManager.get_species_id(idx)
		persona_race_container.visible = (species_id == "pony")
		if species_id != "pony":
			persona_race_option.select(0) # Reset to not specified
	)
	
	# Appearance
	var app_lbl = Label.new()
	app_lbl.text = "Appearance / Description:"
	form_vbox.add_child(app_lbl)
	
	persona_appearance_input = TextEdit.new()
	persona_appearance_input.custom_minimum_size = Vector2(0, 120)
	persona_appearance_input.placeholder_text = "Describe your character's look..."
	persona_appearance_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	form_vbox.add_child(persona_appearance_input)

	center_box.add_child(form_panel)
	content_holder.add_child(center_box)
	
	# Footer Actions
	_set_footer_buttons([
		{
			"text": "Cancel",
			"callback": _close_flow
		},
		{
			"text": "Continue",
			"name": "continue",
			"callback": _save_persona_step
		}
	])
	
	# Load current data
	if settings_manager:
		_load_active_persona_data()

func _load_active_persona_data():
	var persona = settings_manager.get_active_persona()
	persona_name_input.text = str(persona.get("name", ""))
	
	var sex = str(persona.get("sex", ""))
	persona_sex_option.select(SettingsManager.get_sex_index(sex))
	
	var species = str(persona.get("species", ""))
	persona_species_option.select(SettingsManager.get_species_index(species))
	
	var race = str(persona.get("race", ""))
	persona_race_option.select(SettingsManager.get_race_index(race))
	
	persona_appearance_input.text = str(persona.get("appearance", ""))
	
	# Trigger visibility update
	var species_id = SettingsManager.get_species_id(persona_species_option.selected)
	persona_race_container.visible = (species_id == "pony")

func _save_persona_step():
	if not settings_manager:
		current_step = Steps.SELECT
		_render_step()
		return
		
	var active_idx = settings_manager.get_active_persona_index()
	settings_manager.set_persona_field(active_idx, "name", persona_name_input.text)
	settings_manager.set_persona_field(active_idx, "sex", SettingsManager.get_sex_id(persona_sex_option.selected))
	settings_manager.set_persona_field(active_idx, "species", SettingsManager.get_species_id(persona_species_option.selected))
	settings_manager.set_persona_field(active_idx, "race", SettingsManager.get_race_id(persona_race_option.selected))
	settings_manager.set_persona_field(active_idx, "appearance", persona_appearance_input.text)
	settings_manager.save_settings()
	
	current_step = Steps.SELECT
	_render_step()

func _build_character_selection():
	title_label.text = "Custom Start — Choose Characters"
	info_label.text = "Pick which characters should greet the player in their custom introduction."
	character_scroll = ScrollContainer.new()
	character_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	character_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# To ensure centering, we use a container that expands but holds a centered child
	# Use a CenterContainer to ensure the grid is always centered in the scroll view
	var center_cont: CenterContainer = CenterContainer.new()
	center_cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_cont.size_flags_vertical = Control.SIZE_EXPAND_FILL
	character_scroll.add_child(center_cont)
	
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	
	center_cont.add_child(grid)
	
	if available_characters.is_empty():
		var empty_lbl: Label = Label.new()
		empty_lbl.text = "No characters found."
		grid.add_child(empty_lbl)
	else:
		for char_config in available_characters:
			# Skip if config is invalid
			if not char_config or not char_config.get("tag"):
				continue
			grid.add_child(_create_character_button(char_config))

	content_holder.add_child(character_scroll)
	
	# Add spacing before the start location
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	content_holder.add_child(spacer)

	start_location_container = VBoxContainer.new()
	start_location_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_location_container.custom_minimum_size = Vector2(760, 0)
	start_location_container.add_theme_constant_override("separation", 10)
	
	var start_label: Label = Label.new()
	start_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_label.text = "Start Location:"
	start_label.modulate = Color(0.8, 0.8, 0.8)
	start_location_container.add_child(start_label)

	start_location_selector = OptionButton.new()
	start_location_selector.clip_text = true
	start_location_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_location_selector.custom_minimum_size = Vector2(760, 40)
	start_location_selector.item_selected.connect(_on_start_location_selected)
	_populate_start_location_selector()
	start_location_container.add_child(start_location_selector)

	content_holder.add_child(start_location_container)

	var tip: Label = Label.new()
	tip.text = "Tip: Select 1-3 characters."
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 14)
	tip.modulate = Color(1, 1, 1, 0.6)
	content_holder.add_child(tip)

	var selection_count: Label = Label.new()
	selection_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selection_count.name = "SelectionCount"
	content_holder.add_child(selection_count)
	_update_selection_label()
	var continue_callback: Callable = func():
		if selected_tags.is_empty():
			status_label.text = "Select at least one character."
			return
		current_step = Steps.PROMPT
		_render_step()
		
	var back_callback: Callable = func():
		current_step = Steps.PERSONA
		_render_step()
		
	_set_footer_buttons([
		{
			"text": "Back",
			"callback": back_callback
		},
		{
			"text": "Continue",
			"name": "continue",
			"disabled": selected_tags.is_empty(),
			"callback": continue_callback
		}
	])

func _build_prompt_input():
	title_label.text = "Custom Start — Scene Request"
	var selected_characters: Array = _get_selected_characters()
	if selected_characters.is_empty():
		current_step = Steps.SELECT
		_render_step()
		return
	_ensure_recommended_start_location(selected_characters)
	
	# Layout Container
	var center_box: VBoxContainer = VBoxContainer.new()
	center_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_box.custom_minimum_size = Vector2(800, 0)
	center_box.add_theme_constant_override("separation", 20)
	
	# 1. Context Info Panel (Characters + Location)
	var info_panel = PanelContainer.new()
	var info_style = StyleBoxFlat.new()
	info_style.bg_color = Color(0.1, 0.1, 0.12, 0.5)
	info_style.corner_radius_top_left = 8
	info_style.corner_radius_top_right = 8
	info_style.corner_radius_bottom_left = 8
	info_style.corner_radius_bottom_right = 8
	info_style.content_margin_left = 16
	info_style.content_margin_right = 16
	info_style.content_margin_top = 12
	info_style.content_margin_bottom = 12
	info_panel.add_theme_stylebox_override("panel", info_style)
	
	var info_vbox = VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 8)
	info_panel.add_child(info_vbox)
	
	# Persona line
	var persona_hbox = HBoxContainer.new()
	var persona_label_title = Label.new()
	persona_label_title.text = "Persona:"
	persona_label_title.modulate = Color(0.7, 0.7, 0.7)
	persona_hbox.add_child(persona_label_title)
	
	var persona_name = "Unknown"
	if settings_manager:
		persona_name = settings_manager.get_persona_display_name(settings_manager.get_active_persona_index())
	
	var persona_label_val = Label.new()
	persona_label_val.text = persona_name
	persona_label_val.modulate = Color(1.0, 0.8, 0.2)
	persona_hbox.add_child(persona_label_val)
	info_vbox.add_child(persona_hbox)
	
	# Characters line
	var char_hbox = HBoxContainer.new()
	var char_label_title = Label.new()
	char_label_title.text = "Characters:"
	char_label_title.modulate = Color(0.7, 0.7, 0.7)
	char_hbox.add_child(char_label_title)
	
	var char_label_val = Label.new()
	char_label_val.text = _build_character_summary_clean(selected_characters)
	char_label_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	char_label_val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	char_label_val.modulate = Color(1, 1, 1)
	char_hbox.add_child(char_label_val)
	info_vbox.add_child(char_hbox)
	
	# Location line
	var loc_hbox = HBoxContainer.new()
	var loc_label_title = Label.new()
	loc_label_title.text = "Location:"
	loc_label_title.modulate = Color(0.7, 0.7, 0.7)
	loc_hbox.add_child(loc_label_title)
	
	var loc_display_name = _get_location_display_name(recommended_start_location_id)
	var loc_label_val = Label.new()
	loc_label_val.text = loc_display_name
	loc_label_val.modulate = Color(0.6, 0.8, 1.0) # Light blue for location
	loc_hbox.add_child(loc_label_val)
	info_vbox.add_child(loc_hbox)
	
	center_box.add_child(info_panel)
	
	# 2. Input Area
	var input_label = Label.new()
	input_label.text = "Describe your arrival scene:"
	input_label.add_theme_font_size_override("font_size", 18)
	center_box.add_child(input_label)
	
	prompt_input = TextEdit.new()
	prompt_input.size_flags_vertical = Control.SIZE_EXPAND_FILL
	prompt_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt_input.custom_minimum_size = Vector2(0, 200)
	prompt_input.placeholder_text = "Example: I stumble through the Everfree Forest and Twilight finds me."
	prompt_input.text = prompt_text
	prompt_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	prompt_input.text_changed.connect(func():
		prompt_text = prompt_input.text
		var too_short: bool = prompt_text.strip_edges().length() < 10
		_set_footer_button_disabled("generate", too_short or is_generating)
	)
	center_box.add_child(prompt_input)
	
	# 3. Examples
	var examples_panel = PanelContainer.new()
	var ex_style = StyleBoxFlat.new()
	ex_style.bg_color = Color(0.1, 0.1, 0.1, 0.3)
	ex_style.border_width_left = 2 # Left border accent
	ex_style.border_color = Color(0.4, 0.4, 0.5)
	ex_style.content_margin_left = 12
	ex_style.content_margin_top = 8
	ex_style.content_margin_bottom = 8
	examples_panel.add_theme_stylebox_override("panel", ex_style)
	
	var examples_vbox = VBoxContainer.new()
	examples_vbox.add_theme_constant_override("separation", 4)
	
	var ex_title = Label.new()
	ex_title.text = "Ideas:"
	ex_title.add_theme_font_size_override("font_size", 12)
	ex_title.uppercase = true
	ex_title.modulate = Color(0.5, 0.5, 0.5)
	examples_vbox.add_child(ex_title)
	
	for line in [
		"\"I wake up on the train just before Ponyville and meet Twilight on the platform\"",
		"\"Rainbow rescues me mid-flight and drops me off near the library\"",
		"\"Applejack finds me wandering a country road at dusk\""
	]:
		var lbl: Label = Label.new()
		lbl.text = "• " + line
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.modulate = Color(0.8, 0.8, 0.8)
		lbl.add_theme_font_size_override("font_size", 13)
		examples_vbox.add_child(lbl)
		
	examples_panel.add_child(examples_vbox)
	center_box.add_child(examples_panel)
	
	content_holder.add_child(center_box)
	var back_callback: Callable = func():
		current_step = Steps.SELECT
		_render_step()
	_set_footer_buttons([
		{
			"text": "Back",
			"callback": back_callback
		},
		{
			"text": "Generate Plan",
			"name": "generate",
			"callback": _on_generate_pressed,
			"disabled": prompt_text.strip_edges().length() < 10 or is_generating
		}
	])

func _build_result_view():
	title_label.text = "Custom Start — Review Plan"
	
	var center_box: VBoxContainer = VBoxContainer.new()
	center_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_box.custom_minimum_size = Vector2(900, 0)
	center_box.add_theme_constant_override("separation", 16)
	
	# 1. Location Info Panel
	var info_panel = PanelContainer.new()
	var info_style = StyleBoxFlat.new()
	info_style.bg_color = Color(0.1, 0.1, 0.12, 0.5)
	info_style.corner_radius_top_left = 6
	info_style.corner_radius_top_right = 6
	info_style.corner_radius_bottom_left = 6
	info_style.corner_radius_bottom_right = 6
	info_style.content_margin_left = 12
	info_style.content_margin_right = 12
	info_style.content_margin_top = 8
	info_style.content_margin_bottom = 8
	info_panel.add_theme_stylebox_override("panel", info_style)
	
	var loc_hbox = HBoxContainer.new()
	loc_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	loc_hbox.add_theme_constant_override("separation", 8)
	
	var loc_label_title = Label.new()
	loc_label_title.text = "Starting At:"
	loc_label_title.modulate = Color(0.7, 0.7, 0.7)
	loc_hbox.add_child(loc_label_title)
	
	var loc_display = _get_location_display_name(recommended_start_location_id)
	var loc_label_val = Label.new()
	loc_label_val.text = loc_display
	loc_label_val.modulate = Color(0.6, 0.8, 1.0)
	loc_label_val.add_theme_font_size_override("font_size", 16)
	loc_hbox.add_child(loc_label_val)
	
	info_panel.add_child(loc_hbox)
	center_box.add_child(info_panel)
	
	# 2. Plan Editor Area
	var plan_frame = PanelContainer.new()
	plan_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var plan_style = StyleBoxFlat.new()
	plan_style.bg_color = Color(0.08, 0.08, 0.1, 0.8)
	plan_style.border_width_left = 1
	plan_style.border_width_top = 1
	plan_style.border_width_right = 1
	plan_style.border_width_bottom = 1
	plan_style.border_color = Color(0.25, 0.25, 0.35)
	plan_style.corner_radius_top_left = 6
	plan_style.corner_radius_top_right = 6
	plan_style.corner_radius_bottom_left = 6
	plan_style.corner_radius_bottom_right = 6
	plan_style.content_margin_left = 4
	plan_style.content_margin_top = 4
	plan_style.content_margin_right = 4
	plan_style.content_margin_bottom = 4
	plan_frame.add_theme_stylebox_override("panel", plan_style)
	
	response_output = TextEdit.new()
	response_output.editable = true
	response_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	response_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	response_output.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	# Remove background from TextEdit to blend with panel
	var empty_style = StyleBoxEmpty.new()
	response_output.add_theme_stylebox_override("normal", empty_style)
	response_output.add_theme_stylebox_override("focus", empty_style)
	
	response_output.text_changed.connect(func():
		plan_text = response_output.text
		_set_footer_button_disabled("start", plan_text.strip_edges() == "")
	)
	
	if plan_text.strip_edges() != "":
		response_output.text = plan_text
	elif generation_phase == GenerationPhase.PLANNING:
		response_output.text = "Drafting intro plan..."
	else:
		response_output.text = "Waiting for AI response..."
		
	plan_frame.add_child(response_output)
	center_box.add_child(plan_frame)
	
	if is_generating:
		status_label.text = "Generating plan..."
		
	content_holder.add_child(center_box)
	
	var edit_callback: Callable = func():
		is_generating = false
		current_step = Steps.PROMPT
		_render_step()
		
	var start_callback: Callable = func():
		_use_scene(recommended_start_location_id)
		
	var reroll_callback: Callable = func():
		status_label.text = "Re-planning..."
		_on_generate_pressed()
		
	_set_footer_buttons([
		{
			"text": "Start Adventure",
			"name": "start",
			"callback": start_callback,
			"disabled": plan_text.strip_edges() == "" or is_generating
		},
		{
			"text": "Reroll Plan",
			"name": "reroll",
			"callback": reroll_callback,
			"disabled": is_generating
		},
		{
			"text": "Edit Request",
			"name": "edit",
			"callback": edit_callback
		},
		{
			"text": "Cancel",
			"callback": _close_flow
		}
	])

func _create_character_button(char_config) -> Button:
	var btn: Button = Button.new()
	btn.toggle_mode = true
	btn.button_pressed = selected_tags.has(char_config.tag)
	btn.custom_minimum_size = Vector2(220, 260) # Increased size
	btn.tooltip_text = _build_character_tooltip(char_config)
	
	# Create a PanelContainer for visual background
	var panel_container = PanelContainer.new()
	panel_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Custom style for the card background
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.15, 0.15, 0.2, 0.6)
	style_box.corner_radius_top_left = 12
	style_box.corner_radius_top_right = 12
	style_box.corner_radius_bottom_left = 12
	style_box.corner_radius_bottom_right = 12
	style_box.border_width_left = 2
	style_box.border_width_top = 2
	style_box.border_width_right = 2
	style_box.border_width_bottom = 2
	style_box.border_color = Color(0.3, 0.3, 0.4, 0.5)
	panel_container.add_theme_stylebox_override("panel", style_box)
	
	btn.add_child(panel_container)
	
	btn.toggled.connect(func(pressed):
		if pressed:
			style_box.border_color = Color(0.6, 0.8, 1.0, 1.0) # Highlight when selected
			style_box.bg_color = Color(0.2, 0.2, 0.35, 0.8)
		else:
			style_box.border_color = Color(0.3, 0.3, 0.4, 0.5)
			style_box.bg_color = Color(0.15, 0.15, 0.2, 0.6)
	)
	# Trigger initial state
	if btn.button_pressed:
		style_box.border_color = Color(0.6, 0.8, 1.0, 1.0)
		style_box.bg_color = Color(0.2, 0.2, 0.35, 0.8)
	
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_container.add_child(margin) # Add to panel_container instead of btn

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12) # Increased spacing
	margin.add_child(vbox)
	
	var icon_control = _create_icon_control(char_config)
	# Ensure it expands properly
	icon_control.custom_minimum_size = Vector2(100, 120)
	icon_control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL # Use EXPAND_FILL to let stretch_mode center it
	icon_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_control)
	
	var name_label = Label.new()
	name_label.text = char_config.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	vbox.add_child(name_label)
	
	var tag_label = Label.new()
	tag_label.text = "[%s]" % char_config.tag
	tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_label.add_theme_font_size_override("font_size", 12)
	tag_label.modulate = Color(0.6, 0.6, 0.7)
	tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(tag_label)
	
	btn.toggled.connect(func(pressed):
		if pressed:
			if selected_tags.size() >= MAX_SELECTED_CHARACTERS:
				status_label.text = "You can only choose up to %d characters." % MAX_SELECTED_CHARACTERS
				btn.button_pressed = false
				return
			if not selected_tags.has(char_config.tag):
				selected_tags.append(char_config.tag)
		else:
			selected_tags.erase(char_config.tag)
		_sort_selected_tags()
		_update_selection_label()
		_handle_recommended_start_location_update()
	)
	return btn

func _create_icon_control(char_config) -> Control:
	# 1. Check for "frames" folder
	var frames_path = _find_frames_folder(char_config)
	if frames_path != "":
		var loaded_frames = _load_frames(frames_path)
		if not loaded_frames.is_empty():
			var anim = AnimatedIcon.new()
			anim.frames = loaded_frames
			anim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			anim.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			return anim

	# 2. Fallback to static icon
	var icon_tex = _load_character_icon(char_config)
	var texture_rect = TextureRect.new()
	texture_rect.texture = icon_tex
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return texture_rect

func _find_frames_folder(char_config) -> String:
	var base_dir = char_config.folder_path.rstrip("/")
	if base_dir.get_file() == "sprites":
		base_dir = base_dir.get_base_dir()
	
	# Check for "icon/frames"
	var frames_dir = base_dir.path_join("icon/frames")
	var dir = DirAccess.open(frames_dir)
	if dir:
		return frames_dir
	return ""

func _load_frames(folder_path: String) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	var dir = DirAccess.open(folder_path)
	if not dir:
		return result
		
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var file_paths = []
	
	while file_name != "":
		if not dir.current_is_dir() and not file_name.begins_with("."):
			var ext = file_name.get_extension().to_lower()
			if ext in ["png", "jpg", "jpeg", "webp"]:
				file_paths.append(folder_path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	
	file_paths.sort()
	
	for path in file_paths:
		var tex = load(path)
		if tex is Texture2D:
			result.append(tex)
			
	return result

func _load_character_icon(char_config) -> Texture2D:
	# Expecting folder_path to be ".../sprites/" so we step up once
	var base_dir = char_config.folder_path.rstrip("/")
	if base_dir.get_file() == "sprites":
		base_dir = base_dir.get_base_dir()
	
	# Attempt 1: icon/icon.png, icon/icon.webp, or icon/icon.gif
	var candidates = [
		base_dir.path_join("icon/icon.png"),
		base_dir.path_join("icon/icon.webp"),
		base_dir.path_join("icon/icon.gif")
	]
	
	# If specific icon_path is manually set in config, prioritize it
	if char_config.icon_path != "":
		candidates.insert(0, char_config.icon_path)

	for path in candidates:
		if FileAccess.file_exists(path):
			# Special handling: Skip load() for gifs to avoid errors, go straight to Image load
			if path.get_extension().to_lower() != "gif":
				# Method A: Standard resource load
				var tex = load(path)
				if tex is Texture2D and tex.get_width() > 0 and tex.get_height() > 0:
					return tex
			
			# Method B: Direct Image load (bypasses failed/invalid imports or unsupported formats like gif)
			var img = Image.load_from_file(path)
			if img and not img.is_empty():
				return ImageTexture.create_from_image(img)

	# Fallback: sprites/neutral.png
	var fallback_candidates = [
		char_config.folder_path.path_join("neutral.png"),
		char_config.folder_path.path_join("neutral.webp"),
		char_config.folder_path.path_join("sprites/neutral.png"),
		char_config.folder_path.path_join("sprites/neutral.webp")
	]
	
	for path in fallback_candidates:
		if FileAccess.file_exists(path):
			var tex = load(path)
			if tex is Texture2D and tex.get_width() > 0 and tex.get_height() > 0:
				return tex

	# Final fallback
	return PlaceholderTexture2D.new()

func _build_character_tooltip(char_config) -> String:
	var lines: Array = []
	if char_config.description.strip_edges() != "":
		lines.append(char_config.description)
	if not char_config.sprites.is_empty():
		var preview_limit: int = min(char_config.sprites.size(), 8)
		var sprite_preview: Array = []
		for i in range(preview_limit):
			sprite_preview.append(str(char_config.sprites[i]))
		lines.append("Sprites: " + ", ".join(sprite_preview))
	return "\n".join(lines)

func _update_selection_label():
	var label: Label = content_holder.get_node_or_null("SelectionCount") as Label
	if label:
		label.text = "Selected: %d" % selected_tags.size()
	_set_footer_button_disabled("continue", selected_tags.is_empty())

func _build_character_summary(chars: Array) -> String:
	var names: Array = []
	for c in chars:
		names.append(c.name)
	var summary: String = "Characters: " + ", ".join(names)
	if chars.size() > 0:
		summary += " | Primary: %s (%s)" % [chars[0].name, chars[0].tag]
	return summary

func _build_character_summary_clean(chars: Array) -> String:
	var names: Array = []
	for c in chars:
		names.append(c.name)
	return ", ".join(names)

func _on_generate_pressed():
	if is_generating:
		return
	prompt_text = prompt_input.text
	if prompt_text.strip_edges().length() < 10:
		status_label.text = "Describe the scene in at least a sentence."
		return
	var selected_characters: Array = _get_selected_characters()
	if selected_characters.is_empty():
		status_label.text = "Select at least one character."
		current_step = Steps.SELECT
		_render_step()
		return
	current_selected_characters = selected_characters.duplicate()
	_ensure_recommended_start_location(selected_characters)
	if recommended_start_location_id.strip_edges() != "":
		request_location_change.emit(recommended_start_location_id)
	plan_text = ""
	response_text = ""
	is_generating = true
	generation_phase = GenerationPhase.PLANNING
	response_text = ""
	current_step = Steps.RESULT
	_render_step()
	status_label.text = "Planning the intro..."
	_send_planning_request(selected_characters)

func _send_planning_request(chars: Array) -> void:
	# Build location list for the prompt
	var locations: Array = []
	for loc_id in _get_available_locations():
		locations.append({
			"id": loc_id,
			"display": _get_location_display_name(loc_id)
		})
	
	# Get start location
	var start_location_id: String = _get_valid_start_location()
	var start_location_display: String = _get_location_display_name(start_location_id)
	
	# Get persona lines
	var persona_lines: Array = []
	if settings_manager:
		persona_lines = settings_manager.get_active_persona_context_lines()
	
	# Use consolidated PromptBuilder
	var plan_context: String = PromptBuilderUtils.build_planning_prompt(
		chars,
		locations,
		start_location_id,
		start_location_display,
		prompt_text,
		persona_lines
	)
	
	var user_prompt: String = "Draft a concise beat-by-beat intro plan (locations, character enters/exits, sprites/emotions). Do not write dialogue."
	if llm_controller:
		llm_controller.request_custom_generation(plan_context, user_prompt)
	else:
		_on_llm_error("LLMController not available")

func _build_guidelines(primary_char, start_location_id: String) -> Array:
	return [
		"Place [location: %s] early to lock the background to %s." % [start_location_id, _get_location_display_name(start_location_id)],
		"Show characters by emitting [sprite: TAG emotion]; if they weren't visible yet, they appear.",
		"Use [character_exit: TAG] when that character leaves the conversation.",
		"Use [location: location_id] to change the background. Travel between distant regions with plausible steps such as [location: train] then [location: train_station].",
		"Before any dialogue with a new emotion, add [sprite: TAG emotion].",
		"Never write dialogue for the player (tag 'player').",
	]
func _send_writing_request(plan: String, chars: Array) -> void:
	var trimmed_plan: String = plan.strip_edges()
	if trimmed_plan == "":
		is_generating = false
		generation_phase = GenerationPhase.IDLE
		status_label.text = "Plan was empty. Please try again."
		return
	var start_location_id: String = _get_valid_start_location()
	var scene_text: String = _build_writing_context(trimmed_plan, chars, start_location_id)
	var task = "Write the opening scene now, following the plan."
	var prompt_info: Dictionary = PromptBuilderUtils.build_scene_prompt(chars, scene_text, task, settings_manager)
	var system_prompt: String = prompt_info.get("system_prompt", scene_text)
	var post_instructions: String = prompt_info.get("post_story_instructions", "")
	var user_prompt: String = task
	if post_instructions.strip_edges() != "":
		user_prompt += "\n" + post_instructions.strip_edges()
	if llm_controller:
		llm_controller.request_custom_generation(system_prompt, user_prompt)
	else:
		_on_llm_error("LLMController not available")

func _build_writing_context(plan: String, chars: Array, start_location_id: String) -> String:
	var lines: Array = []
	lines.append("Use the approved plan below to write the intro. Do not include the plan text in the output.")
	lines.append("PLAN:")
	lines.append(plan.strip_edges())
	lines.append("")
	var primary_char = chars[0] if chars.size() > 0 else null
	var guidelines: Array = _build_guidelines(primary_char, start_location_id)
	lines.append("WRITING GUIDELINES:")
	for guide in guidelines:
		lines.append("- " + guide)
	lines.append("")
	# _append_format_rules removed; PromptBuilder adds rules automatically
	lines.append("")
	if settings_manager:
		var persona_lines = settings_manager.get_active_persona_context_lines()
		if persona_lines.size() > 0:
			lines.append("PLAYER PERSONA DETAILS:")
			for entry in persona_lines:
				lines.append(entry)
	lines.append("")
	lines.append("PLAYER'S SCENE REQUEST:")
	lines.append(prompt_text.strip_edges())
	lines.append("")
	lines.append("Never include the planning notes in the final output.")
	lines.append("Example:")
	lines.append("\n".join(SAMPLE_LINES))
	return "\n".join(lines)


func _get_available_locations() -> Array:
	var ids: Array = []
	if location_manager and location_manager.locations:
		for loc_id in location_manager.locations.keys():
			if EXCLUDED_LOCATIONS.has(loc_id):
				continue
			ids.append(loc_id)
	ids.sort()
	return ids

func _get_selected_characters() -> Array:
	var chars: Array = []
	if not character_manager:
		return chars
	for tag in selected_tags:
		var cfg = character_manager.get_character(tag)
		if cfg:
			chars.append(cfg)
	return chars

func _populate_start_location_selector():
	if start_location_selector == null:
		return
	start_location_selector.set_block_signals(true)
	start_location_selector.clear()
	var entries: Array = _get_sorted_locations()
	var default_id: String = _get_valid_start_location()
	if not start_location_locked:
		var auto_id: String = _choose_start_location(_get_selected_characters())
		if _location_exists(auto_id):
			default_id = auto_id
	var selected_index: int = -1
	for i in range(entries.size()):
		var loc_id: String = entries[i]["id"]
		var display: String = entries[i]["display"]
		start_location_selector.add_item(display, i)
		start_location_selector.set_item_metadata(i, loc_id)
		start_location_selector.set_item_tooltip(i, "%s (%s)" % [display, loc_id])
		if selected_index == -1 and loc_id == recommended_start_location_id:
			selected_index = i
	if selected_index == -1:
		selected_index = 0
	if entries.size() > 0:
		start_location_selector.select(selected_index)
		recommended_start_location_id = str(start_location_selector.get_item_metadata(selected_index))
	start_location_selector.set_block_signals(false)

func _on_start_location_selected(index: int):
	if start_location_selector == null:
		return
	var metadata = start_location_selector.get_item_metadata(index)
	if metadata == null:
		return
	var loc_id: String = _resolve_location(str(metadata))
	if loc_id.strip_edges() == "":
		return
	recommended_start_location_id = loc_id
	start_location_locked = true

func _handle_recommended_start_location_update():
	if start_location_locked:
		return
	var auto_id: String = _choose_start_location(_get_selected_characters())
	_set_recommended_start_location(auto_id, false)
	_sync_location_selector_selection()

func _sync_location_selector_selection():
	if start_location_selector == null:
		return
	start_location_selector.set_block_signals(true)
	for i in range(start_location_selector.get_item_count()):
		var meta = start_location_selector.get_item_metadata(i)
		if str(meta) == recommended_start_location_id:
			start_location_selector.select(i)
			start_location_selector.set_block_signals(false)
			return
	start_location_selector.set_block_signals(false)

func _set_recommended_start_location(loc_id: String, locked: bool):
	var resolved: String = _resolve_location(loc_id)
	if not _location_exists(resolved):
		return
	recommended_start_location_id = resolved
	if locked:
		start_location_locked = true

func _ensure_recommended_start_location(selected_chars: Array):
	if start_location_locked:
		if not _location_exists(recommended_start_location_id):
			recommended_start_location_id = _get_valid_start_location()
		_sync_location_selector_selection()
		return
	var auto_id: String = _choose_start_location(selected_chars)
	if _location_exists(auto_id):
		recommended_start_location_id = auto_id
	else:
		recommended_start_location_id = _get_valid_start_location()
	_sync_location_selector_selection()

func _get_sorted_locations() -> Array:
	var entries: Array = []
	for loc_id in _get_available_locations():
		var display: String = _get_location_display_label(loc_id)
		entries.append({"id": loc_id, "display": display})
	entries.sort_custom(func(a, b):
		return str(a["display"]).to_lower() < str(b["display"]).to_lower()
	)
	return entries

func _get_location_display_label(location_id: String) -> String:
	if location_manager:
		var loc = location_manager.get_location(location_id)
		if loc:
			var label: String = loc.name
			if loc.region.strip_edges() != "":
				label += " — " + loc.region
			return label
	return _get_location_display_name(location_id)

func _choose_start_location(chars: Array) -> String:
	var primary_tag: String = ""
	if not chars.is_empty():
		var first_char = chars[0]
		if first_char and first_char.tag:
			primary_tag = str(first_char.tag).to_lower()
	var candidate: String = ""
	if primary_tag != "" and START_LOCATION_OVERRIDES.has(primary_tag):
		candidate = str(START_LOCATION_OVERRIDES[primary_tag])
	if candidate == "":
		candidate = DEFAULT_START_LOCATION
	return _resolve_location(candidate)

func _get_valid_start_location() -> String:
	var resolved: String = _resolve_location(recommended_start_location_id)
	if _location_exists(resolved):
		return resolved
	var fallback: String = _resolve_location(DEFAULT_START_LOCATION)
	if _location_exists(fallback):
		return fallback
	if location_manager and location_manager.current_location_id != "":
		return location_manager.current_location_id
	return DEFAULT_START_LOCATION

func _resolve_location(location_id: String) -> String:
	if location_manager:
		var resolved: String = location_manager.resolve_location_id(location_id)
		if resolved.strip_edges() != "":
			return resolved
	return location_id

func _location_exists(location_id: String) -> bool:
	if location_manager == null:
		return false
	return location_manager.get_location(location_id) != null

func _get_location_display_name(location_id: String) -> String:
	if location_manager:
		var loc = location_manager.get_location(location_id)
		if loc:
			if loc.identifier.strip_edges() != "":
				return loc.identifier
			return loc.name
	return location_id.replace("_", " ").capitalize()

func _sort_selected_tags():
	if not character_manager:
		return
	var sortable: Array = []
	for tag in selected_tags:
		var cfg = character_manager.get_character(tag)
		if cfg:
			sortable.append({"tag": tag, "name": cfg.name.to_lower()})
	sortable.sort_custom(func(a, b):
		return a["name"] < b["name"])
	selected_tags.clear()
	for entry in sortable:
		selected_tags.append(entry["tag"])

func _set_footer_buttons(configs: Array):
	_clear_container(footer_holder)
	footer_buttons.clear()
	for cfg in configs:
		var btn: Button = Button.new()
		btn.text = cfg.get("text", "Button")
		btn.disabled = cfg.get("disabled", false)
		var tooltip: String = str(cfg.get("tooltip", ""))
		if tooltip != "":
			btn.tooltip_text = tooltip
		var callback = cfg.get("callback")
		if callback:
			btn.pressed.connect(callback)
		var name = cfg.get("name", "")
		if name != "":
			footer_buttons[name] = btn
		footer_holder.add_child(btn)

func _set_footer_button_disabled(name: String, disabled: bool):
	if footer_buttons.has(name):
		footer_buttons[name].disabled = disabled

func _copy_to_clipboard():
	if response_text.strip_edges() == "":
		return
	DisplayServer.clipboard_set(response_text)
	status_label.text = "Copied to clipboard."

func _get_start_location_for_scene() -> String:
	var trimmed: String = response_text.strip_edges()
	if trimmed != "":
		var parsed = DialogueParser.parse(trimmed, character_manager)
		for location_id in parsed.location_commands:
			var resolved: String = _resolve_location(location_id)
			if _location_exists(resolved):
				return resolved
	return _get_valid_start_location()

func _use_scene(start_location_id: String):
	if plan_text.strip_edges() == "":
		status_label.text = "No plan to start with."
		return
	var resolved: String = _resolve_location(start_location_id)
	if not _location_exists(resolved):
		resolved = _get_valid_start_location()
	if resolved.strip_edges() != "":
		request_location_change.emit(resolved)
	var data: Dictionary = {
		"plan_text": plan_text,
		"scene_text": "", # No scene text, we use plan now
		"start_location_id": resolved,
		"selected_tags": selected_tags.duplicate()
	}
	finished.emit(data)
	queue_free()

func _on_llm_response_received(text: String, _type: String) -> void:
	var trimmed: String = str(text).strip_edges()
	match generation_phase:
		GenerationPhase.PLANNING:
			is_generating = false
			generation_phase = GenerationPhase.IDLE
			
			if trimmed == "":
				status_label.text = "Planning failed. Try again."
				return
				
			plan_text = trimmed
			status_label.text = "Plan ready. Review or start."
			
			if current_step != Steps.RESULT:
				current_step = Steps.RESULT
			_render_step()
			return
		GenerationPhase.WRITING:
			is_generating = false
			generation_phase = GenerationPhase.IDLE
			response_text = text
			plan_text = ""
			if current_step != Steps.RESULT:
				current_step = Steps.RESULT
			_render_step()
			var start_location_id: String = _get_start_location_for_scene()
			status_label.text = "Scene ready! Start at %s." % _get_location_display_name(start_location_id)
			return
		_:
			is_generating = false
			response_text = text
			if current_step != Steps.RESULT:
				current_step = Steps.RESULT
			_render_step()
			var fallback_start: String = _get_start_location_for_scene()
			status_label.text = "Scene ready! Start at %s." % _get_location_display_name(fallback_start)

func _on_llm_error(error):
	is_generating = false
	generation_phase = GenerationPhase.IDLE
	if current_step != Steps.RESULT:
		current_step = Steps.RESULT
	_render_step()
	status_label.text = "Error: %s" % str(error)

func _close_flow():
	closed.emit()
	queue_free()

func _clear_container(node: Control):
	for child in node.get_children():
		child.queue_free()
