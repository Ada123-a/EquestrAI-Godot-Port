extends Node

# Music player for background music
var music_player: AudioStreamPlayer
var current_music_path: String = ""
var target_music_path: String = ""
var fade_tween: Tween

func _ready():
	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	music_player.bus = "Music"  # Use Music bus if it exists
	music_player.volume_db = -10  # Slightly quieter than max

func play_music(file_path: String, fade_duration: float = 1.0):
	# Unpause if necessary
	if music_player.stream_paused:
		music_player.stream_paused = false

	# Don't reload if already playing/targeting the same track
	if target_music_path == file_path:
		return
	
	target_music_path = file_path
	
	if file_path == "" or not FileAccess.file_exists(file_path):
		stop_music(fade_duration)
		return
	
	# Load the music file
	var stream = load_audio_file(file_path)
	if not stream:
		print("Failed to load music: ", file_path)
		return
	
	# Fade out current music if playing
	if music_player.playing:
		fade_out_and_switch(stream, file_path, fade_duration)
	else:
		# Start new music
		music_player.stream = stream
		music_player.play()
		current_music_path = file_path
		fade_in(fade_duration)

func pause_music():
	if music_player.playing and not music_player.stream_paused:
		music_player.stream_paused = true

func resume_music():
	if music_player.stream_paused:
		music_player.stream_paused = false

func fade_out_and_switch(new_stream: AudioStream, new_path: String, duration: float):
	if fade_tween:
		fade_tween.kill()
	
	fade_tween = create_tween()
	fade_tween.tween_property(music_player, "volume_db", -80, duration)
	fade_tween.tween_callback(func():
		music_player.stop()
		music_player.stream = new_stream
		music_player.volume_db = -80
		music_player.play()
		current_music_path = new_path
		fade_in(duration)
	)

func fade_in(duration: float):
	if fade_tween:
		fade_tween.kill()
	
	music_player.volume_db = -80
	fade_tween = create_tween()
	fade_tween.tween_property(music_player, "volume_db", -10, duration)

func stop_music(fade_duration: float = 1.0):
	target_music_path = ""
	
	if music_player.stream_paused:
		music_player.stream_paused = false

	if not music_player.playing:
		return
	
	if fade_tween:
		fade_tween.kill()
	
	fade_tween = create_tween()
	fade_tween.tween_property(music_player, "volume_db", -80, fade_duration)
	fade_tween.tween_callback(func():
		music_player.stop()
		current_music_path = ""
	)

func set_volume(volume_db: float):
	music_player.volume_db = volume_db

func load_audio_file(file_path: String) -> AudioStream:
	# For .mp3 files, we need to load them at runtime
	if file_path.ends_with(".mp3"):
		var file = FileAccess.open(file_path, FileAccess.READ)
		if not file:
			return null
		
		var buffer = file.get_buffer(file.get_length())
		file.close()
		
		var stream = AudioStreamMP3.new()
		stream.data = buffer
		stream.loop = true  # Background music should loop
		return stream
	
	# For other formats, try to load directly (if imported)
	if ResourceLoader.exists(file_path):
		return load(file_path)
	
	return null

var saved_music_info: Dictionary = {}

func play_temporary_music(file_path: String, fade_duration: float = 1.0):
	# Save current state
	if music_player.playing:
		saved_music_info = {
			"path": current_music_path,
			"position": music_player.get_playback_position(),
			"volume": music_player.volume_db,
			"paused": music_player.stream_paused
		}
	else:
		saved_music_info = {}
	
	play_music(file_path, fade_duration)

func restore_saved_music(fade_duration: float = 1.0):
	if saved_music_info.is_empty():
		stop_music(fade_duration)
		return

	var path = saved_music_info.get("path", "")
	var pos = saved_music_info.get("position", 0.0)
	var was_paused = saved_music_info.get("paused", false)
	# var vol = saved_music_info.get("volume", -10.0) # Not used currently as we fade to -10/standard
	
	saved_music_info = {} # Clear after restoring
	
	if path == "":
		stop_music(fade_duration)
		return
		
	# Check if we are already playing this track (unlikely if we just finished temporary music)
	if target_music_path == path and music_player.playing:
		return

	target_music_path = path

	var stream = load_audio_file(path)
	if not stream:
		return
	
	# Function to execute the restoration
	var restore_func = func():
		music_player.stop()
		music_player.stream = stream
		music_player.volume_db = -80
		music_player.play(pos)
		music_player.stream_paused = was_paused
		current_music_path = path
		
		if not was_paused:
			fade_in(fade_duration)
		else:
			# If it was paused, we just restore the volume but keep it paused? 
			# Or volume remains low? 
			# Logic: If it was paused, we probably shouldn't be hearing it, but we want it ready.
			# Let's just set the volume back to standard instantly or fade?
			# If paused, fade_in won't work well as it relies on property tweening while playing.
			# Let's assume we want to restore it as it was.
			music_player.volume_db = -10
	
	if music_player.playing:
		# Fade out current temporary music first
		if fade_tween: fade_tween.kill()
		fade_tween = create_tween()
		fade_tween.tween_property(music_player, "volume_db", -80, fade_duration)
		fade_tween.tween_callback(restore_func)
	else:
		restore_func.call()

