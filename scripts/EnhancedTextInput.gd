extends TextEdit
class_name EnhancedTextInput

signal text_committed(text: String)

@export var enable_spell_check: bool = true
@export var spell_check_color: Color = Color(1.0, 0.3, 0.3, 0.5)
@export var expand_with_content: bool = true

var spell_checker: SpellChecker = null
var context_menu: PopupMenu = null
var current_right_click_word: Dictionary = {}
var pending_replacement_word: Dictionary = {}

const SUGGESTION_MENU_START_ID = 1000

func _ready() -> void:
	context_menu_enabled = false
	selecting_enabled = true
	deselect_on_focus_loss_enabled = false
	middle_mouse_paste_enabled = true
	wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY

	scroll_fit_content_height = expand_with_content

	if enable_spell_check:
		spell_checker = SpellChecker.new()
		add_child(spell_checker)
	_create_context_menu()
	gui_input.connect(_on_gui_input)
	gui_input.connect(_on_key_input)

func _create_context_menu() -> void:
	context_menu = PopupMenu.new()
	add_child(context_menu)
	context_menu.id_pressed.connect(_on_context_menu_item_pressed)
	context_menu.popup_hide.connect(_on_context_menu_hidden)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_show_context_menu(event.position)
			accept_event()

func _show_context_menu(position: Vector2) -> void:
	if not context_menu:
		return

	context_menu.clear()
	var click_pos = get_line_column_at_pos(position)
	var line = click_pos.y
	var column = click_pos.x

	if line < 0 or line >= get_line_count():
		return
	var clicked_word = _get_word_at_position(line, column)

	if enable_spell_check and clicked_word.has("word"):
		var analyzed_word = _analyze_word(clicked_word)
		current_right_click_word = analyzed_word

		if analyzed_word.get("misspelled", false):
			var suggestions = analyzed_word.get("suggestions", [])
			# Store for later use (after menu closes)
			pending_replacement_word = analyzed_word.duplicate(true)
			if suggestions.size() > 0:
				for i in range(suggestions.size()):
					var label = "%d. %s" % [i + 1, suggestions[i]]
					context_menu.add_item(label, SUGGESTION_MENU_START_ID + i)
				context_menu.add_separator()
			context_menu.add_item("Add to Dictionary", 100)
			context_menu.add_separator()
	var has_selection = has_selection()
	if has_selection:
		context_menu.add_item("Cut", 1)
		context_menu.add_item("Copy", 2)
	context_menu.add_item("Paste", 3)
	if has_selection:
		context_menu.add_separator()
		context_menu.add_item("Select All", 4)
	elif get_text().length() > 0:
		context_menu.add_item("Select All", 4)
	var screen_position = get_global_mouse_position()
	context_menu.position = Vector2i(screen_position)
	context_menu.popup()

func _on_context_menu_item_pressed(id: int) -> void:
	print("Context menu item pressed: id=%d" % id)

	match id:
		1:
			cut()
		2:
			copy()
		3:
			paste()
		4:
			select_all()
		100:  # Add to Dictionary
			if current_right_click_word.has("word") and spell_checker:
				spell_checker.add_word(current_right_click_word.word)
		_:
			# Handle spelling suggestions - use pending_replacement_word which persists
			if id >= SUGGESTION_MENU_START_ID and pending_replacement_word.has("suggestions"):
				var suggestion_index = id - SUGGESTION_MENU_START_ID
				var suggestions = pending_replacement_word.suggestions
				if suggestion_index < suggestions.size():
					# Get the actual suggestion (without the number label)
					var suggestion = suggestions[suggestion_index]
					_replace_word(pending_replacement_word, suggestion)

func _on_context_menu_hidden() -> void:
	current_right_click_word = {}

func _replace_word(word_data: Dictionary, replacement: String) -> void:
	if not word_data.has("line") or not word_data.has("start_col") or not word_data.has("end_col"):
		return
	var line = word_data.line
	var start_col = word_data.start_col
	var end_col = word_data.end_col
	# Select the word
	select(line, start_col, line, end_col)
	delete_selection()
	# Insert the replacement at the current caret position
	insert_text_at_caret(replacement)
	# Clear selection
	deselect()

func _get_word_at_position(line: int, column: int) -> Dictionary:
	if line < 0 or line >= get_line_count():
		return {}
	var line_text = get_line(line)
	var line_length = line_text.length()
	if line_length == 0:
		return {}

	# Clamp column to valid range (clicks beyond end of line snap to last char)
	column = clampi(column, 0, line_length - 1)

	# If clicked on whitespace/punctuation, search nearby characters for a word
	if not _is_word_char(line_text[column]):
		var found_index = -1

		# Search left
		var idx = column
		while idx >= 0:
			if _is_word_char(line_text[idx]):
				found_index = idx
				break
			idx -= 1

		# If not found, search right
		if found_index == -1:
			idx = column + 1
			while idx < line_length:
				if _is_word_char(line_text[idx]):
					found_index = idx
					break
				idx += 1

		if found_index == -1:
			return {}

		column = found_index

	if column < 0 or column >= line_length:
		return {}

	# Find word boundaries
	var start = column
	var end = column

	# Move start backwards to beginning of word
	while start > 0 and _is_word_char(line_text[start - 1]):
		start -= 1

	# Move end forwards to end of word
	while end < line_text.length() and _is_word_char(line_text[end]):
		end += 1

	if start == end:
		return {}

	return {
		"word": line_text.substr(start, end - start),
		"line": line,
		"start_col": start,
		"end_col": end
	}

func _analyze_word(word_data: Dictionary) -> Dictionary:
	var result = word_data.duplicate(true)
	result["misspelled"] = false
	result["suggestions"] = []

	if not enable_spell_check or not spell_checker or not spell_checker.is_loaded:
		return result

	var word = result.get("word", "")
	if word.strip_edges().is_empty():
		return result

	if not spell_checker.is_word_correct(word):
		result["misspelled"] = true
		result["suggestions"] = spell_checker.get_suggestions(word)

	return result

func _is_word_char(c: String) -> bool:
	if c.length() == 0:
		return false
	var code = c.unicode_at(0)
	# Letters, numbers, and apostrophes (for contractions)
	return (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or c == "'"

# Submit the text (like pressing Enter in a LineEdit)
func commit_text() -> void:
	text_committed.emit(get_text())

func _on_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if event.ctrl_pressed or get_line_count() == 1:
				commit_text()
				accept_event()
