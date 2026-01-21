extends PanelContainer
## A popup panel that displays a searchable list of characters to add

signal character_selected(tag: String)
signal random_character_requested
signal cancelled

@onready var search_input: LineEdit = %SearchInput
@onready var character_list: VBoxContainer = %CharacterList
@onready var scroll_container: ScrollContainer = %ScrollContainer
@onready var random_button: Button = %RandomButton
@onready var close_button: Button = %CloseButton

## Character entries: Array of {tag: String, name: String}
var available_characters: Array = []

## Currently filtered/displayed character buttons
var character_buttons: Array[Button] = []

func _ready() -> void:
	visible = false
	search_input.text_changed.connect(_on_search_text_changed)
	random_button.pressed.connect(_on_random_pressed)
	close_button.pressed.connect(_on_close_pressed)
	
	# Clear focus when mouse clicks on the panel (not button)
	search_input.grab_focus()

## Populate the list with characters not currently present
func set_available_characters(characters: Array) -> void:
	available_characters = characters.duplicate(true)
	# Sort by name
	available_characters.sort_custom(func(a, b):
		return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0
	)
	_rebuild_list("")

## Show the popup centered on screen
func show_popup() -> void:
	visible = true
	search_input.text = ""
	search_input.grab_focus()
	_rebuild_list("")

func hide_popup() -> void:
	visible = false
	_clear_buttons()

func _on_search_text_changed(new_text: String) -> void:
	_rebuild_list(new_text)

func _rebuild_list(filter_text: String) -> void:
	_clear_buttons()
	
	var filter_lower: String = filter_text.strip_edges().to_lower()
	
	for char_entry in available_characters:
		var char_name: String = str(char_entry.get("name", ""))
		var char_tag: String = str(char_entry.get("tag", ""))
		
		# Filter: check if name starts with the filter text (case insensitive)
		if filter_lower != "" and not char_name.to_lower().begins_with(filter_lower):
			continue
		
		# Create button for this character
		var btn := Button.new()
		btn.text = char_name
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_character_button_pressed.bind(char_tag))
		
		character_list.add_child(btn)
		character_buttons.append(btn)
	
	# Show "no results" message if empty
	if character_buttons.is_empty() and filter_lower != "":
		var no_results_label := Label.new()
		no_results_label.text = "No characters found matching '%s'" % filter_text.strip_edges()
		no_results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_results_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		character_list.add_child(no_results_label)

func _clear_buttons() -> void:
	character_buttons.clear()
	for child in character_list.get_children():
		child.queue_free()

func _on_character_button_pressed(tag: String) -> void:
	character_selected.emit(tag)
	hide_popup()

func _on_random_pressed() -> void:
	random_character_requested.emit()
	hide_popup()

func _on_close_pressed() -> void:
	cancelled.emit()
	hide_popup()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_close_pressed()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			# Enter selects the first visible character
			if character_buttons.size() > 0:
				character_buttons[0].emit_signal("pressed")
				get_viewport().set_input_as_handled()
