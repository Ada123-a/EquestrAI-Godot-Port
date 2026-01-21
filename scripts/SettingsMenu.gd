extends Control

signal settings_closed

const PERSONA_SLOT_COUNT := 10

var settings_manager

# We'll store the persona dictionaries here temporarily while editing
var persona_data: Array = []
var current_editing_index: int = 0

# Store prompt data maps keys to content
var prompt_data: Dictionary = {}
var current_prompt_key: String = ""

# --- References to UI Nodes ---
@onready var background: TextureRect = $Background

# Sidebar Navigation
@onready var nav_game_btn: Button = %NavGameBtn
@onready var nav_api_btn: Button = %NavAPIBtn
@onready var nav_prompt_btn: Button = %NavPromptsBtn

@onready var save_button: Button = %SaveButton
@onready var close_button: Button = %CloseButton

# Sections
@onready var game_settings_section: VBoxContainer = %GameSettingsSection
@onready var api_settings_section: VBoxContainer = %APISettingsSection
@onready var prompt_settings_section: VBoxContainer = %PromptSettingsSection

# Game Settings / Persona
@onready var active_persona_option: OptionButton = %ActivePersonaOption
@onready var persona_slot_list: ItemList = %PersonaSlotList
@onready var persona_name_input: LineEdit = %PersonaNameInput
@onready var persona_sex_option: OptionButton = %PersonaSexOption
@onready var persona_species_option: OptionButton = %PersonaSpeciesOption
@onready var persona_race_option: OptionButton = %PersonaRaceOption
@onready var persona_race_container: HBoxContainer = %PersonaRaceContainer
@onready var persona_appearance_input: TextEdit = %PersonaAppearanceInput

# API Settings - General
@onready var provider_option: OptionButton = %ProviderOption
@onready var openai_settings: VBoxContainer = %OpenAISettings
@onready var gemini_settings: VBoxContainer = %GeminiSettings

# API Settings - OpenAI
@onready var api_url_input: LineEdit = %APIURLInput
@onready var api_key_input: LineEdit = %APIKeyInput
@onready var model_input: LineEdit = %ModelInput

# API Settings - Gemini
@onready var gemini_key_input: LineEdit = %GeminiKeyInput
@onready var gemini_model_input: LineEdit = %GeminiModelInput

# API Settings - Common
@onready var temperature_input: SpinBox = %TemperatureInput
@onready var max_context_input: SpinBox = %MaxContextInput
@onready var auto_summary_input: SpinBox = %AutoSummaryInput
@onready var auto_summary_label: Label = %AutoSummaryLabel
@onready var max_response_input: SpinBox = %MaxResponseInput
@onready var top_p_input: SpinBox = %TopPInput
@onready var top_k_input: SpinBox = %TopKInput

# Prompt Settings
@onready var prompt_selector: OptionButton = %PromptSelector
@onready var prompt_content_input: TextEdit = %PromptContentInput

# Prompt Definitions
var prompt_definitions = [
	{"key": "system_prompt", "name": "Dialogue Prompt"},
	{"key": "impersonate_prompt", "name": "Impersonation Prompt"},
	{"key": "travel_prompt", "name": "Travel Prompt"},
	{"key": "summary_prompt", "name": "Summary Prompt"}
]

func _ready():
	_setup_background()
	
	# Initialize persona data array
	persona_data.resize(PERSONA_SLOT_COUNT)
	for i in range(PERSONA_SLOT_COUNT):
		persona_data[i] = _create_empty_persona(i)
		
	# Setup Connections
	nav_game_btn.pressed.connect(func(): _update_nav_state(0))
	nav_api_btn.pressed.connect(func(): _update_nav_state(1))
	nav_prompt_btn.pressed.connect(func(): _update_nav_state(2))
	
	save_button.pressed.connect(_on_save_pressed)
	close_button.pressed.connect(_on_close_pressed)
	
	provider_option.item_selected.connect(_on_provider_selected)
	max_context_input.value_changed.connect(_on_max_context_value_changed)
	
	persona_slot_list.item_selected.connect(_on_persona_slot_selected)
	
	# Persona field connections
	if persona_name_input:
		persona_name_input.text_changed.connect(_on_persona_name_changed)
	if persona_sex_option:
		persona_sex_option.item_selected.connect(_on_persona_sex_selected)
	if persona_species_option:
		persona_species_option.item_selected.connect(_on_persona_species_selected)
	if persona_race_option:
		persona_race_option.item_selected.connect(_on_persona_race_selected)
	if persona_appearance_input:
		persona_appearance_input.text_changed.connect(_on_persona_appearance_changed)
	
	prompt_selector.item_selected.connect(_on_prompt_type_selected)
	prompt_content_input.text_changed.connect(_on_prompt_content_changed)
	
	# Populate persona field dropdowns
	_populate_persona_dropdowns()
	
	# Initial UI Setup
	_build_persona_list()
	_update_nav_state(0) # Default to Game Settings
	
	# Populate prompt selector
	prompt_selector.clear()
	for i in range(prompt_definitions.size()):
		prompt_selector.add_item(prompt_definitions[i]["name"], i)
	
	# Load if manager exists
	if settings_manager:
		load_current_settings()

func _create_empty_persona(index: int) -> Dictionary:
	return {
		"name": "Persona %d" % (index + 1),
		"sex": "",
		"species": "",
		"race": "",
		"appearance": ""
	}

func _populate_persona_dropdowns():
	# Use centralized definitions from SettingsManager
	if persona_sex_option:
		SettingsManager.populate_option_button(persona_sex_option, SettingsManager.SEX_OPTIONS)
	
	if persona_species_option:
		SettingsManager.populate_option_button(persona_species_option, SettingsManager.SPECIES_OPTIONS)
	
	if persona_race_option:
		SettingsManager.populate_option_button(persona_race_option, SettingsManager.RACE_OPTIONS)

func set_settings_manager(manager):
	settings_manager = manager
	if is_node_ready():
		load_current_settings()

func _setup_background():
	var bg_path = "res://assets/Locations/ponyville/ponyville_main_square/background.png"
	if FileAccess.file_exists(bg_path):
		background.texture = load(bg_path)

# --- Navigation Logic ---
func _update_nav_state(tab_index: int):
	# 0 = Game, 1 = API, 2 = Prompts
	nav_game_btn.set_pressed_no_signal(tab_index == 0)
	nav_api_btn.set_pressed_no_signal(tab_index == 1)
	nav_prompt_btn.set_pressed_no_signal(tab_index == 2)
	
	game_settings_section.visible = (tab_index == 0)
	api_settings_section.visible = (tab_index == 1)
	prompt_settings_section.visible = (tab_index == 2)

# --- Loading Settings ---
func load_current_settings():
	if not settings_manager:
		return
		
	# --- Persona Settings ---
	var saved_personas = settings_manager.get_persona_profiles()
	for i in range(min(saved_personas.size(), PERSONA_SLOT_COUNT)):
		if typeof(saved_personas[i]) == TYPE_DICTIONARY:
			persona_data[i] = saved_personas[i].duplicate()
		else:
			persona_data[i] = _create_empty_persona(i)
	
	# Update active persona option with descriptive names
	active_persona_option.clear()
	for i in range(PERSONA_SLOT_COUNT):
		var display_name = settings_manager.get_persona_display_name(i)
		active_persona_option.add_item(display_name, i)
	
	var active_idx = settings_manager.get_active_persona_index()
	if active_idx >= 0 and active_idx < active_persona_option.item_count:
		active_persona_option.select(active_idx)
	
	# Build persona list and select first persona to edit
	_build_persona_list()
	if persona_slot_list.item_count > 0:
		persona_slot_list.select(0)
		_on_persona_slot_selected(0)
		
	# --- API Settings ---
	# Provider
	var provider = settings_manager.get_setting("provider")
	if provider == "gemini":
		provider_option.select(1)
	else:
		provider_option.select(0)
	_on_provider_selected(provider_option.selected)
	
	# OpenAI
	api_url_input.text = settings_manager.get_setting("api_url")
	api_key_input.text = settings_manager.get_setting("api_key")
	var model_val = settings_manager.get_setting("model")
	if model_val == null: model_val = "gpt-4"
	model_input.text = model_val
	
	# Gemini
	var g_key = settings_manager.get_setting("gemini_key")
	if g_key == null: g_key = ""
	gemini_key_input.text = g_key
	
	var g_model = settings_manager.get_setting("gemini_model")
	if g_model == null: g_model = "gemini-pro"
	gemini_model_input.text = g_model
	
	# Common
	temperature_input.value = settings_manager.get_setting("temperature")
	max_context_input.value = settings_manager.get_setting("max_context")
	_update_auto_summary_limit()
	auto_summary_input.value = settings_manager.get_setting("auto_summary_context")
	max_response_input.value = settings_manager.get_setting("max_response_length")
	top_p_input.value = settings_manager.get_setting("top_p")
	top_k_input.value = settings_manager.get_setting("top_k")

	# --- Prompt Settings ---
	for def in prompt_definitions:
		var key = def["key"]
		var val = settings_manager.get_setting(key)
		if val == null: val = ""
		prompt_data[key] = val
	
	# Select first prompt
	if prompt_selector.item_count > 0:
		prompt_selector.select(0)
		_on_prompt_type_selected(0)

# --- Persona UI Logic ---
func _build_persona_list():
	persona_slot_list.clear()
	for i in range(PERSONA_SLOT_COUNT):
		var persona = persona_data[i]
		var display_name = _get_persona_list_name(persona, i)
		persona_slot_list.add_item(display_name)

func _get_persona_list_name(persona: Dictionary, index: int) -> String:
	var name = str(persona.get("name", "")).strip_edges()
	if name == "" or name.begins_with("Persona "):
		# Build descriptive name from fields
		var parts: Array[String] = []
		var sex = str(persona.get("sex", "")).strip_edges()
		var species = str(persona.get("species", "")).strip_edges()
		var race = str(persona.get("race", "")).strip_edges()
		if sex != "":
			parts.append(sex.capitalize())
		if species == "pony" and race != "":
			parts.append(race.replace("_", " ").capitalize())
		elif species != "":
			parts.append(species.capitalize())
		if parts.is_empty():
			return "Persona %d" % (index + 1)
		return " ".join(parts)
	return name

func _on_persona_slot_selected(index: int):
	current_editing_index = index
	var persona = persona_data[index]
	
	# Load name
	if persona_name_input:
		persona_name_input.text = str(persona.get("name", ""))
	
	# Load sex
	if persona_sex_option:
		var sex = str(persona.get("sex", ""))
		var sex_idx = _sex_to_index(sex)
		persona_sex_option.select(sex_idx)
	
	# Load species
	if persona_species_option:
		var species = str(persona.get("species", ""))
		var species_idx = _species_to_index(species)
		persona_species_option.select(species_idx)
		_update_race_visibility(species)
	
	# Load race
	if persona_race_option:
		var race = str(persona.get("race", ""))
		var race_idx = _race_to_index(race)
		persona_race_option.select(race_idx)
	
	# Load appearance
	if persona_appearance_input:
		persona_appearance_input.text = str(persona.get("appearance", ""))

func _sex_to_index(sex: String) -> int:
	return SettingsManager.get_sex_index(sex)

func _index_to_sex(idx: int) -> String:
	return SettingsManager.get_sex_id(idx)

func _species_to_index(species: String) -> int:
	return SettingsManager.get_species_index(species)

func _index_to_species(idx: int) -> String:
	return SettingsManager.get_species_id(idx)

func _race_to_index(race: String) -> int:
	return SettingsManager.get_race_index(race)

func _index_to_race(idx: int) -> String:
	return SettingsManager.get_race_id(idx)

func _update_race_visibility(species: String):
	# Only show race selector for ponies
	if persona_race_container:
		persona_race_container.visible = (species.to_lower() == "pony")

func _on_persona_name_changed(new_text: String):
	persona_data[current_editing_index]["name"] = new_text
	_update_persona_list_item(current_editing_index)

func _on_persona_sex_selected(idx: int):
	persona_data[current_editing_index]["sex"] = _index_to_sex(idx)
	_update_persona_list_item(current_editing_index)

func _on_persona_species_selected(idx: int):
	var species = _index_to_species(idx)
	persona_data[current_editing_index]["species"] = species
	_update_race_visibility(species)
	# Clear race if not a pony
	if species != "pony":
		persona_data[current_editing_index]["race"] = ""
		if persona_race_option:
			persona_race_option.select(0)
	_update_persona_list_item(current_editing_index)

func _on_persona_race_selected(idx: int):
	persona_data[current_editing_index]["race"] = _index_to_race(idx)
	_update_persona_list_item(current_editing_index)

func _on_persona_appearance_changed():
	if persona_appearance_input:
		persona_data[current_editing_index]["appearance"] = persona_appearance_input.text

func _update_persona_list_item(index: int):
	if index >= 0 and index < persona_slot_list.item_count:
		var display_name = _get_persona_list_name(persona_data[index], index)
		persona_slot_list.set_item_text(index, display_name)


# --- API UI Logic ---
func _on_provider_selected(index: int):
	if index == 0: # OpenAI
		openai_settings.visible = true
		gemini_settings.visible = false
	else: # Gemini
		openai_settings.visible = false
		gemini_settings.visible = true

func _on_max_context_value_changed(value: float) -> void:
	_update_auto_summary_limit()

func _update_auto_summary_limit() -> void:
	if not auto_summary_input or not max_context_input:
		return
	var allowed_max: float = max(max_context_input.value - 10000.0, 0.0)
	auto_summary_input.max_value = allowed_max
	if auto_summary_input.value > allowed_max:
		auto_summary_input.value = allowed_max
	
	if auto_summary_label:
		auto_summary_label.text = "Auto-Summary Limit (<= %d)" % int(allowed_max)

# --- Prompt UI Logic ---
func _on_prompt_type_selected(index: int):
	if index < 0 or index >= prompt_definitions.size():
		return
	
	current_prompt_key = prompt_definitions[index]["key"]
	prompt_content_input.text = prompt_data.get(current_prompt_key, "")

func _on_prompt_content_changed():
	if current_prompt_key != "":
		prompt_data[current_prompt_key] = prompt_content_input.text

# --- Save Logic ---
func _on_save_pressed():
	if not settings_manager:
		return
	
	# Save Personas
	for i in range(PERSONA_SLOT_COUNT):
		settings_manager.set_persona_slot(i, persona_data[i])
	
	var active_id = active_persona_option.get_selected_id()
	if active_id == -1: active_id = active_persona_option.get_selected()
	settings_manager.set_active_persona_index(active_id)
	
	# Save API Settings
	var provider = "openai"
	if provider_option.selected == 1:
		provider = "gemini"
	settings_manager.set_setting("provider", provider)
	
	settings_manager.set_setting("api_url", api_url_input.text)
	settings_manager.set_setting("api_key", api_key_input.text)
	settings_manager.set_setting("model", model_input.text)
	
	settings_manager.set_setting("gemini_key", gemini_key_input.text)
	settings_manager.set_setting("gemini_model", gemini_model_input.text)
	
	settings_manager.set_setting("temperature", temperature_input.value)
	settings_manager.set_setting("max_context", max_context_input.value)
	settings_manager.set_setting("auto_summary_context", auto_summary_input.value)
	settings_manager.set_setting("max_response_length", max_response_input.value)
	settings_manager.set_setting("top_p", top_p_input.value)
	settings_manager.set_setting("top_k", top_k_input.value)
	
	# Save Prompts
	for key in prompt_data.keys():
		settings_manager.set_setting(key, prompt_data[key])
	
	settings_manager.save_settings()
	
	print("Settings saved successfully.")
	_on_close_pressed()

func _on_close_pressed():
	emit_signal("settings_closed")
	queue_free()
