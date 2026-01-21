extends Control

signal open_quick_start
signal open_options
signal open_custom_start
signal open_debug_start
signal resume_game
signal quit_game

@onready var background_rect: TextureRect = $Background
@onready var resume_btn: Button = %ResumeButton
@onready var quick_start_btn: Button = %QuickStartButton
@onready var custom_start_btn: Button = %CustomStartButton
@onready var debug_start_btn: Button = %DebugStartButton
@onready var options_btn: Button = %OptionsButton
@onready var quit_btn: Button = %QuitButton

var game_active: bool = false

func _ready():
	setup_ui()

func setup_ui():
	# Load default background
	var bg_path = "res://assets/Menu/main.png"
	if FileAccess.file_exists(bg_path):
		background_rect.texture = load(bg_path)

	# Connect button signals
	resume_btn.pressed.connect(_on_resume_pressed)
	quick_start_btn.pressed.connect(_on_quick_start_pressed)
	custom_start_btn.pressed.connect(_on_custom_start_pressed)
	debug_start_btn.pressed.connect(_on_debug_start_pressed)
	options_btn.pressed.connect(_on_options_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

	# Update button visibility
	update_button_visibility()

func update_button_visibility():
	if resume_btn:
		resume_btn.visible = game_active

func set_game_active(active: bool):
	game_active = active
	update_button_visibility()

func _on_resume_pressed():
	resume_game.emit()

func _on_quick_start_pressed():
	open_quick_start.emit()

func _on_custom_start_pressed():
	open_custom_start.emit()

func _on_debug_start_pressed():
	open_debug_start.emit()

func _on_options_pressed():
	open_options.emit()

func _on_quit_pressed():
	get_tree().quit()
