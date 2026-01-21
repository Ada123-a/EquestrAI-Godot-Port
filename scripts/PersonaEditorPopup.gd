extends Control

signal editor_closed

var settings_manager

# UI References
@onready var persona_name_input: LineEdit = %PersonaNameInput
@onready var persona_sex_option: OptionButton = %PersonaSexOption
@onready var persona_species_option: OptionButton = %PersonaSpeciesOption
@onready var persona_race_option: OptionButton = %PersonaRaceOption
@onready var persona_race_container: HBoxContainer = %PersonaRaceContainer
@onready var persona_appearance_input: TextEdit = %PersonaAppearanceInput
@onready var save_button: Button = %SaveButton
@onready var cancel_button: Button = %CancelButton

func _ready():
	# Connect buttons
	save_button.pressed.connect(_on_save_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	
	# Connect field change handlers
	persona_species_option.item_selected.connect(_on_species_selected)
	
	# Populate dropdowns using centralized definitions
	_populate_dropdowns()
	
	# Load current persona data
	if settings_manager:
		_load_current_persona()

func set_settings_manager(manager):
	settings_manager = manager
	if is_node_ready():
		_load_current_persona()

func _populate_dropdowns():
	# Use centralized definitions from SettingsManager
	SettingsManager.populate_option_button(persona_sex_option, SettingsManager.SEX_OPTIONS)
	SettingsManager.populate_option_button(persona_species_option, SettingsManager.SPECIES_OPTIONS)
	SettingsManager.populate_option_button(persona_race_option, SettingsManager.RACE_OPTIONS)

func _load_current_persona():
	if not settings_manager:
		return
	
	var persona = settings_manager.get_active_persona()
	
	# Load name
	persona_name_input.text = str(persona.get("name", ""))
	
	# Load sex
	var sex = str(persona.get("sex", ""))
	persona_sex_option.select(SettingsManager.get_sex_index(sex))
	
	# Load species
	var species = str(persona.get("species", ""))
	persona_species_option.select(SettingsManager.get_species_index(species))
	_update_race_visibility(species)
	
	# Load race
	var race = str(persona.get("race", ""))
	persona_race_option.select(SettingsManager.get_race_index(race))
	
	# Load appearance
	persona_appearance_input.text = str(persona.get("appearance", ""))

func _on_species_selected(idx: int):
	var species = SettingsManager.get_species_id(idx)
	_update_race_visibility(species)
	if species != "pony":
		persona_race_option.select(0)

func _update_race_visibility(species: String):
	persona_race_container.visible = (species.to_lower() == "pony")

func _on_save_pressed():
	if not settings_manager:
		editor_closed.emit()
		return
	
	var active_idx = settings_manager.get_active_persona_index()
	
	# Save each field
	settings_manager.set_persona_field(active_idx, "name", persona_name_input.text)
	settings_manager.set_persona_field(active_idx, "sex", SettingsManager.get_sex_id(persona_sex_option.selected))
	settings_manager.set_persona_field(active_idx, "species", SettingsManager.get_species_id(persona_species_option.selected))
	settings_manager.set_persona_field(active_idx, "race", SettingsManager.get_race_id(persona_race_option.selected))
	settings_manager.set_persona_field(active_idx, "appearance", persona_appearance_input.text)
	
	settings_manager.save_settings()
	print("Persona saved successfully.")
	
	editor_closed.emit()

func _on_cancel_pressed():
	editor_closed.emit()
